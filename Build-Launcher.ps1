
param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))

$ErrorActionPreference = 'Stop'
$launcherName = '广联达与 Virbox 开关'
$cmd = Join-Path $PSScriptRoot "$launcherName.cmd"
$compiler = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (!(Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw '找不到 Windows .NET Framework 64 位 C# 编译器。'
}

$output = [IO.Directory]::CreateDirectory($OutputDirectory).FullName
$exe = Join-Path $output "$launcherName.exe"
$cmdCopy = Join-Path $output "$launcherName.cmd"
$icon = Join-Path $PSScriptRoot 'launcher.ico'
$source = Join-Path $PSScriptRoot 'Launcher.cs'
& $compiler /nologo /optimize+ /target:exe /codepage:65001 "/out:$exe" "/win32icon:$icon" "/resource:$cmd,GlodonLicenseSwitch.Launcher.cmd" $source
if ($LASTEXITCODE) { throw "启动器编译失败，退出码 $LASTEXITCODE。" }

Copy-Item -LiteralPath $cmd -Destination $cmdCopy -Force
$zip = Join-Path $output 'GlodonLicenseSwitch-zh-CN.zip'
Compress-Archive -LiteralPath @($exe,$cmdCopy) -DestinationPath $zip -Force
Get-Item -LiteralPath $exe,$cmdCopy,$zip
