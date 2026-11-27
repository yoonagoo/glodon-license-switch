@echo off
setlocal
set "GLD_POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "GLD_POWERSHELL=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "GLD_ACTION=Menu"
if /I "%~1"=="--status" set "GLD_ACTION=Status"

"%GLD_POWERSHELL%" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "$dir = Join-Path $env:LOCALAPPDATA 'GlodonLicenseSwitch';" ^
    "[void][IO.Directory]::CreateDirectory($dir);" ^
    "$script = Join-Path $dir 'GlodonLicenseSwitch.ps1';" ^
    "$download = Join-Path $dir ([guid]::NewGuid().ToString('N') + '.download');" ^
    "$url = 'https://raw.githubusercontent.com/yoonagoo/glodon-license-switch/main/GlodonLicenseSwitch.ps1?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();" ^
    "try {" ^
    "    Write-Host 'Downloading the latest Glodon License Switch...';" ^
    "    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download -TimeoutSec 30;" ^
    "    $tokens = $null; $errors = $null;" ^
    "    $ast = [Management.Automation.Language.Parser]::ParseFile($download, [ref]$tokens, [ref]$errors);" ^
    "    if ($errors -or !$ast.ParamBlock) { throw 'The downloaded file is not a valid version of the PowerShell script.' }" ^
    "    Move-Item -LiteralPath $download -Destination $script -Force;" ^
    "    $powershell = Join-Path $PSHOME 'powershell.exe';" ^
    "    & $powershell -NoProfile -ExecutionPolicy Bypass -File $script -Action $env:GLD_ACTION;" ^
    "    exit $LASTEXITCODE;" ^
    "} finally {" ^
    "    if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -ErrorAction SilentlyContinue }" ^
    "}"
if errorlevel 1 (
    echo.
    echo Failed to update or start Glodon License Switch.
    pause
    exit /b 1
)
exit /b 0
