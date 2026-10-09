$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Pubspec = Get-Content (Join-Path $ProjectRoot 'app\pubspec.yaml') -Raw
if ($Pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$') { throw 'App version is missing' }
$ReleaseVersion = $Matches[1]
Push-Location (Join-Path $ProjectRoot 'app')
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
  $VsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  if (!(Test-Path $VsWhere)) { throw 'Install Visual Studio with Desktop development with C++ first' }
  $VsPath = & $VsWhere -latest -products '*' -property installationPath
  if ($LASTEXITCODE -ne 0 -or !$VsPath) { throw 'Visual Studio installation not found' }
  $Crt = Get-ChildItem "$VsPath\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
  if (!$Crt) { throw 'Visual C++ runtime not found' }
  Copy-Item "$($Crt.FullName)\*.dll" 'build\windows\x64\runner\Release\'
} finally { Pop-Location }
$Compiler = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($Compiler) { $Iscc = $Compiler.Source }
else { $Iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
if (!(Test-Path $Iscc)) { throw 'Install Inno Setup 6 first' }
& $Iscc "/DAppVersion=$ReleaseVersion" (Join-Path $ProjectRoot 'packaging\windows.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer packaging failed' }
$Dist = Join-Path $ProjectRoot 'dist'
$Setup = Join-Path $Dist "Vkusnoteka-Windows-$ReleaseVersion-Setup.exe"
Copy-Item (Join-Path $Dist 'Vkusnoteka-Windows-Setup.exe') $Setup -Force
$Portable = Join-Path $Dist "Vkusnoteka-Windows-$ReleaseVersion-Portable.zip"
Compress-Archive -Path (Join-Path $ProjectRoot 'app\build\windows\x64\runner\Release\*') -DestinationPath $Portable -Force
$Checksums = @($Setup, $Portable) | ForEach-Object {
  $Hash = (Get-FileHash $_ -Algorithm SHA256).Hash.ToLowerInvariant()
  "$Hash  $(Split-Path -Leaf $_)"
}
$Checksums | Set-Content (Join-Path $Dist "Vkusnoteka-Windows-$ReleaseVersion.sha256") -Encoding ascii
Write-Output "Built Vkusnoteka Windows ${ReleaseVersion}: installer and portable ZIP"
