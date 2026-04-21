param(
  [Parameter(Mandatory = $true)]
  [string]$ScriptName,
  [Parameter(Mandatory = $true)]
  [string]$LogName
)

$ErrorActionPreference = 'Stop'
$installerDir = 'c:\Users\pc\DEV\PROYECTOS\INTERNO\FULLTECH\installer'
$iscc = 'c:\Users\pc\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
$scriptPath = Join-Path $installerDir $ScriptName
$logPath = Join-Path $installerDir $LogName

if (-not (Test-Path $iscc)) {
  throw "ISCC no existe en $iscc"
}

if (-not (Test-Path $scriptPath)) {
  throw "Script Inno no existe en $scriptPath"
}

Set-Location $installerDir
if (Test-Path $logPath) {
  Remove-Item $logPath -Force
}

$process = Start-Process -FilePath $iscc -ArgumentList $scriptPath -WorkingDirectory $installerDir -Wait -PassThru -NoNewWindow -RedirectStandardOutput $logPath -RedirectStandardError $logPath
exit $process.ExitCode