
param([ValidateSet('Menu','Status','Pause','Resume')][string]$Action='Menu')
$ErrorActionPreference = 'Stop'
$stateDirectory = Join-Path $env:LOCALAPPDATA 'GlodonLicenseSwitch'
$stateFile = Join-Path $stateDirectory 'original-state.json'
$sc = Join-Path $env:windir 'System32\sc.exe'
$pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$cf86 = [Environment]::GetEnvironmentVariable('CommonProgramFiles(x86)')
$gcp = Join-Path $env:CommonProgramFiles 'Glodon Shared\GCP'
$dog = Join-Path $cf86 'Grandsoft Shared\GrandDog'
$glodon = Join-Path $pf86 'Glodon'
$sense = Join-Path $pf86 'senseshield\ss'
$gtjRoots = @("$pf86\GrandSoft\GTJ2026","$env:ProgramFiles\Glodon\GTJ2026")
# Stop dependents first, then restore in the opposite order.
$targets = [ordered]@{
    GTJLaunchService = @($gtjRoots | ForEach-Object { "$_\bin\GMPLaunchService.exe" })
    gcpsvc = "$gcp\*\GCPService.exe"
    GSCService = "$dog\*\GSCService.exe"
    gssvc = "$glodon\GSSP\gsspservice.exe"
    SSMonitorService = "$sense\service\ss_monitor.exe"
    'Sense Shield Service' = "$sense\service\senseshield.exe"
    'Virbox License Control Center' = "$sense\virboxlcc\virboxlcc.exe"
    elite5 = "$env:windir\System32\drivers\elite5.sys"
    sprotect2 = "$sense\service\sprotect2.sys"
    slock2 = "$sense\service\slock2.sys"
}
$drivers = @('elite5','sprotect2','slock2')
$runEntries = [ordered]@{
    GSCServer = @{Key='HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Image="$dog\*\GSCServer.exe"}
    GWS = @{Key='Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Run'; Image="$glodon\GWS\*\GWSLoader.exe"}
}
$helpers = @("$gcp\*\GCPHost.exe","$dog\*\GSCMessenger.exe","$dog\*\GSCMonitor.exe","$dog\*\GSCServer.exe",
             "$glodon\GWS\*\GWSLoader.exe","$sense\*\ssclient.exe","$sense\*\virboxlcc.exe")
$modes = @('boot','system','auto','demand','disabled')

function Get-Image([string]$command) {
    $command = [Environment]::ExpandEnvironmentVariables($command.Trim())
    if ($command -match '^"([^"]+)"') { $command = $Matches[1] }
    elseif ($command -match '^(.+?\.(exe|sys))(?=\s|$)') { $command = $Matches[1] }
    else { throw "Cannot identify image: $command" }
    if ($command.StartsWith('\??\')) { $command = $command.Substring(4) }
    if ($command.StartsWith('\SystemRoot\',[StringComparison]::OrdinalIgnoreCase)) {
        $command = $env:windir + $command.Substring(11)
    }
    $command
}

function Get-Target([string]$name,[switch]$ForDisplay) {
    $key = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    $image = Get-Image $key.ImagePath
    if (!($targets[$name] | Where-Object { $image -like $_ })) {
        throw "The configured image for $name does not match a supported path: $($key.ImagePath)"
    }
    $status = [System.ServiceProcess.ServiceController]::new($name).Status
    if (!$ForDisplay -and $status -notin @('Stopped','Running')) { throw "$name is $status. Try again when it reaches Running or Stopped." }
    [pscustomobject]@{Name=$name; Start=[int]$key.Start; Delayed=[bool]$key.DelayedAutoStart; Status=$status; Running=($status -eq 'Running')}
}

function Get-Startup([string]$name) {
    $entry = $runEntries[$name]
    $key = Get-Item -LiteralPath $entry.Key -ErrorAction SilentlyContinue
    if (!$key -or $name -notin $key.GetValueNames()) { return }
    $value = $key.GetValue($name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $kind = [string]$key.GetValueKind($name)
    if ($kind -notin @('String','ExpandString') -or (Get-Image $value) -notlike $entry.Image) { throw "The startup entry $name has changed." }
    [pscustomobject]@{Name=$name; Value=$value; Kind=$kind}
}

function Get-Helpers {
    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        try { $path = $_.Path } catch { return }
        if ($path) {
            foreach ($image in $helpers) { if ($path -like $image) { $_; break } }
        }
    }
}

function Stop-Helpers {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $requested = [Collections.Generic.HashSet[int]]::new()
    $previousScanEmpty = $false
    do {
        $remaining = @(Get-Helpers)
        if (!$remaining.Count -and $previousScanEmpty) { return }
        $previousScanEmpty = !$remaining.Count
        foreach ($process in $remaining) {
            if (!$requested.Add($process.Id)) { continue }
            try { Stop-Process -InputObject $process -Force }
            catch { if (!$process.HasExited) { throw } }
        }
        # A terminated process may still appear in the next scan, or its watchdog may restart it once.
        Start-Sleep -Milliseconds 250
    } while ($timer.Elapsed.TotalSeconds -lt 5)

    $remaining = @(Get-Helpers)
    if ($remaining.Count) {
        $details = $remaining | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }
        throw "等待 5 秒后仍有后台进程运行：$($details -join ', ')"
    }
}

function Invoke-Sc([string[]]$arguments) {
    $result = & $sc @arguments
    if ($LASTEXITCODE -ne 0) { throw ($result -join [Environment]::NewLine) }
}

function Set-Running([string]$name,[bool]$running) {
    $controller = [System.ServiceProcess.ServiceController]::new($name)
    $status = if ($running) { 'Running' } else { 'Stopped' }
    if ($controller.Status -ne $status) {
        $verb = if ($running) { 'start' } else { 'stop' }
        try { Invoke-Sc @($verb,$name) }
        catch {
            $controlError = $_.Exception.Message
            # Some services close their control pipe while shutting down.
            try { $controller.WaitForStatus($status,[TimeSpan]::FromSeconds(5)) }
            catch { throw "$($name): $controlError" }
            return
        }
        try { $controller.WaitForStatus($status,[TimeSpan]::FromSeconds(15)) }
        catch { throw "$($name): $($_.Exception.Message)" }
    }
}

function Read-Snapshot {
    $saved = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($saved.Schema -ne 1 -or $saved.Services.Count -ne $targets.Count) { throw 'Invalid saved configuration.' }
    foreach ($name in $targets.Keys) {
        $entry = @($saved.Services | Where-Object Name -eq $name)
        if ($entry.Count -ne 1 -or $entry[0].Start -notin (0..4) -or $entry[0].Delayed -isnot [bool] -or $entry[0].Running -isnot [bool]) {
            throw "Invalid saved configuration for $name."
        }
    }
    $seen = @{}
    foreach ($entry in $saved.Startups) {
        if (!$runEntries.Contains($entry.Name) -or $seen.ContainsKey($entry.Name) -or $entry.Kind -notin @('String','ExpandString') -or
            (Get-Image $entry.Value) -notlike $runEntries[$entry.Name].Image) { throw "Invalid saved startup entry: $($entry.Name)" }
        $seen[$entry.Name] = $true
    }
    $saved
}

function Restore-Snapshot($saved) {
    foreach ($entry in $saved.Startups) {
        $current = Get-Startup $entry.Name
        if ($current -and ($current.Value -cne $entry.Value -or $current.Kind -ne $entry.Kind)) { throw "The startup entry $($entry.Name) changed. The snapshot was kept." }
    }
    foreach ($entry in $saved.Services) {
        $mode = $modes[[int]$entry.Start]
        if ($mode -eq 'auto' -and $entry.Delayed) { $mode = 'delayed-auto' }
        Invoke-Sc @('config',$entry.Name,'start=',$mode)
    }
    foreach ($entry in $saved.Startups) {
        if (!(Get-Startup $entry.Name)) {
            New-ItemProperty -LiteralPath $runEntries[$entry.Name].Key -Name $entry.Name -Value $entry.Value -PropertyType $entry.Kind | Out-Null
        }
    }
    $names = @($targets.Keys)
    [array]::Reverse($names)
    $errors = foreach ($name in $names) {
        $entry = $saved.Services | Where-Object Name -eq $name
        if ($entry.Running) {
            try { Set-Running $name $true }
            catch { "$($name): $($_.Exception.Message)" }
        }
    }
    if ($errors) {
        throw ("Startup settings were restored. Retry Resume after restarting Windows if a driver could not start." + [Environment]::NewLine + ($errors -join [Environment]::NewLine))
    }
    Remove-Item -LiteralPath $stateFile
}

function Pause-Targets($current,$startups) {
    $alreadySaved = Test-Path -LiteralPath $stateFile
    if (!$alreadySaved) {
        $saved = [pscustomobject]@{Schema=1; Services=@($current | Select-Object Name,Start,Delayed,Running); Startups=$startups}
        [void][IO.Directory]::CreateDirectory($stateDirectory)
        $temporary = "$stateFile.tmp"
        $saved | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding UTF8
        [IO.File]::Move($temporary,$stateFile)
    }
    $saved = Read-Snapshot
    foreach ($entry in $startups) {
        $original = $saved.Startups | Where-Object Name -eq $entry.Name
        if (!$original -or $original.Value -cne $entry.Value -or $original.Kind -ne $entry.Kind) {
            throw "The startup entry $($entry.Name) changed while paused. Resume first."
        }
    }
    try {
        foreach ($entry in $startups) { Remove-ItemProperty -LiteralPath $runEntries[$entry.Name].Key -Name $entry.Name }
        foreach ($name in $targets.Keys) { Invoke-Sc @('config',$name,'start=','disabled') }
        foreach ($name in $targets.Keys) {
            try { Set-Running $name $false }
            catch {
                if ($name -notin $drivers) { throw }
                Write-Warning "$name is disabled. Restart Windows if it is still loaded."
            }
        }
        Stop-Helpers
        # The GrandDog watchdog can restore automatic startup during shutdown.
        foreach ($name in $targets.Keys) {
            if ((Get-Target $name).Start -ne 4) { Invoke-Sc @('config',$name,'start=','disabled') }
        }
        foreach ($name in $targets.Keys) {
            $final = Get-Target $name
            if ($final.Start -ne 4 -or ($final.Running -and $name -notin $drivers)) {
                throw "$name did not stay paused."
            }
        }
    } catch {
        $pauseError = $_.Exception.Message
        if (!$alreadySaved) {
            try { Restore-Snapshot $saved }
            catch { throw "Pause failed: $pauseError. Automatic restoration also failed: $($_.Exception.Message)" }
            throw "Pause failed and the original configuration was restored: $pauseError"
        }
        throw "Pause could not finish. The original configuration is still saved: $pauseError"
    }
}

Add-Type -AssemblyName System.ServiceProcess

function Invoke-Switch([string]$operation) {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (![Security.Principal.WindowsPrincipal]::new($user).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw '开启和关闭需要管理员权限。'
    }
    $mutex = [Threading.Mutex]::new($false,"Global\GlodonLicenseSwitch-$($user.User.Value)")
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw '另一个窗口正在切换，请稍后重试。' }
        $current = @($targets.Keys | ForEach-Object { Get-Target $_ })
        $startups = @($runEntries.Keys | ForEach-Object { Get-Startup $_ })
        if ($operation -eq 'Pause') {
            Pause-Targets $current $startups
            Write-Host '关闭已执行，请查看下方状态。' -ForegroundColor Cyan
        } elseif (Test-Path -LiteralPath $stateFile) {
            Restore-Snapshot (Read-Snapshot)
            Write-Host '已恢复原来的启动设置，并启动了关闭前正在运行的服务和驱动。' -ForegroundColor Green
        } else {
            Write-Host '没有待恢复的设置，保留当前配置。'
        }
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Write-Section([string]$title) {
    Write-Host ''
    Write-Host "==== $title ====" -ForegroundColor Cyan
}

function Write-MenuChoices {
    Write-Section '操作'
    Write-Host '  [1] 开启' -ForegroundColor Green -NoNewline
    Write-Host '     [2] 关闭' -ForegroundColor Yellow -NoNewline
    Write-Host '     [0] 退出' -ForegroundColor Gray
}

function Show-Status {
    $current = @($targets.Keys | ForEach-Object { Get-Target $_ -ForDisplay })
    $startups = @($runEntries.Keys | ForEach-Object { Get-Startup $_ })
    $sources = @($targets.Values | ForEach-Object { $_ }) + $helpers
    $known = @($sources | Where-Object { $_ -like '*.exe' } | ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique)
    $relatedRoots = @("$gcp\*","$dog\*","$glodon\*","$sense\*","$pf86\GrandSoft\*") + @($gtjRoots | ForEach-Object { "$_\*" })
    $observed = @(Get-CimInstance Win32_Process | Where-Object {
        $process = $_
        if (!$process.ExecutablePath) { return $process.Name -in $known }
        foreach ($root in $relatedRoots) {
            if ($process.ExecutablePath -like $root) { return $true }
        }
        return $false
    })
    $saved = Test-Path -LiteralPath $stateFile
    $configuredOff = ($current.Start | Where-Object { $_ -ne 4 } | Measure-Object).Count -eq 0 -and !$startups.Count
    $active = ($current.Status | Where-Object { $_ -ne 'Stopped' } | Measure-Object).Count -gt 0 -or $observed.Count -gt 0
    $status = if ($configuredOff -and !$active) { '已关闭，重启后保持关闭' }
    elseif ($configuredOff) { '启动已禁用，仍有相关项目运行或正在切换' }
    elseif ($saved) { '部分开启，原设置仍可恢复' }
    else { '已开启，按当前 Windows 设置运行' }

    $statusColor = if ($configuredOff -and !$active) { 'Gray' }
    elseif ($configuredOff -or $saved) { 'Yellow' }
    else { 'Green' }
    $rule = '=' * 66
    Write-Host ''
    Write-Host $rule -ForegroundColor DarkCyan
    Write-Host '  广联达与 SenseShield/Virbox 开关' -ForegroundColor Cyan
    Write-Host '  当前状态  ' -NoNewline
    Write-Host $status -ForegroundColor $statusColor
    Write-Host $rule -ForegroundColor DarkCyan

    Write-Section "服务和驱动（$($current.Count - $drivers.Count) 项服务 / $($drivers.Count) 项驱动）"
    Write-Host ('  {0,-32}{1,-6}{2,-12}{3}' -f '名称','类型','运行状态','启动方式') -ForegroundColor DarkCyan
    $statusNames = @{Stopped='已停止';Running='运行中';StartPending='正在启动';StopPending='正在停止';Paused='已暂停'}
    $startNames = @('引导启动','系统启动','自动','手动','禁用')
    foreach ($entry in $current) {
        $type = if ($entry.Name -in $drivers) { '驱动' } else { '服务' }
        $running = $statusNames[[string]$entry.Status]
        if (!$running) { $running = [string]$entry.Status }
        $color = switch ([string]$entry.Status) {
            'Running' { 'Green' }
            'Stopped' { 'Gray' }
            default { 'Yellow' }
        }
        $mode = $startNames[$entry.Start]
        if ($entry.Start -eq 2 -and $entry.Delayed) { $mode = '自动（延迟）' }
        $modeColor = if ($entry.Start -eq 4) { 'Gray' } else { 'Cyan' }
        Write-Host ('  {0,-34}{1}    ' -f $entry.Name,$type) -NoNewline
        Write-Host $running -ForegroundColor $color -NoNewline
        $gap = if ($statusNames.ContainsKey([string]$entry.Status)) { ' ' * (16 - 2*$running.Length) }
        else { ' ' * [Math]::Max(2,16 - $running.Length) }
        Write-Host ($gap + $mode) -ForegroundColor $modeColor
    }

    Write-Section "相关进程（$($observed.Count) 个实例正在运行）"
    Write-Host ('  {0,-32}{1,-9}{2,-7}{3}' -f '进程','运行状态','实例','PID') -ForegroundColor DarkCyan
    foreach ($name in @($known + $observed.Name | Sort-Object -Unique)) {
        $matches = @($observed | Where-Object Name -eq $name)
        $running = if ($matches.Count) { '运行中' } else { '未运行' }
        $color = if ($matches.Count) { 'Green' } else { 'Gray' }
        $pids = if ($matches.Count) { $matches.ProcessId -join ', ' } else { '-' }
        Write-Host ('  {0,-34}' -f $name) -NoNewline
        Write-Host $running -ForegroundColor $color -NoNewline
        Write-Host ('       {0,-9}{1}' -f $matches.Count,$pids)
    }

    Write-Section '登录启动项'
    foreach ($name in $runEntries.Keys) {
        $present = $name -in $startups.Name
        $status = if ($present) { '已注册' } else { '已停用' }
        $color = if ($present) { 'Green' } else { 'Gray' }
        Write-Host ('  {0,-34}' -f $name) -NoNewline
        Write-Host $status -ForegroundColor $color
    }
}

if ($Action -ne 'Menu') {
    try {
        if ($Action -ne 'Status') { Invoke-Switch $Action }
        Show-Status
        exit 0
    } catch {
        [Console]::Error.WriteLine($_.Exception.Message)
        exit 1
    }
}

$user = [Security.Principal.WindowsIdentity]::GetCurrent()
if (![Security.Principal.WindowsPrincipal]::new($user).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        $exe = Join-Path $PSHOME 'powershell.exe'
        if (!(Test-Path -LiteralPath $exe)) { $exe = Join-Path $PSHOME 'pwsh.exe' }
        $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'))
        Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs -WindowStyle Normal
    } catch {
        Write-Host "无法打开管理员菜单：$($_.Exception.Message)" -ForegroundColor Red
        [void](Read-Host '按回车退出')
        exit 1
    }
    exit 0
}

while ($true) {
    try { Show-Status }
    catch { Write-Host "读取状态失败：$($_.Exception.Message)" -ForegroundColor Red }
    Write-MenuChoices
    $choice = Read-Host '请输入数字'
    if ($null -eq $choice -or $choice.Trim() -eq '0') { exit 0 }
    try {
        switch ($choice.Trim()) {
            '1' { Invoke-Switch 'Resume' }
            '2' { Invoke-Switch 'Pause' }
            default { Write-Host '请输入 1、2 或 0。' -ForegroundColor Yellow }
        }
    } catch { Write-Host "操作未完成：$($_.Exception.Message)" -ForegroundColor Red }
}
