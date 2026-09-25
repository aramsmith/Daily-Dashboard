# Builds dist\DailyBoardSetup.exe from app\, runtime-src\ (Node.js) and installer\.
# With -Release it also copies the setup to release\DailyBoardSetup-<version>.exe and records its SHA-256.
param([switch]$Release)
$ErrorActionPreference = 'Stop'
$b = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $b 'stage'; $pkg = Join-Path $b 'pkg'; $dist = Join-Path $b 'dist'
Remove-Item $stage, $pkg -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$stage\app", "$stage\runtime", $pkg, $dist | Out-Null

# One version number for everything, from the VERSION file (MAJOR.MINOR.PATCH).
$Version = (Get-Content "$b\VERSION" -Raw).Trim()
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "VERSION must look like 1.2.3 (found '$Version')." }
Write-Output "Building Daily Board $Version"

# Only these app files go into the package, so a stray file (settings, logs, notes) can never slip in.
$AppFiles = 'server.js', 'app.js', 'briefing.js', 'artifacts.js', 'settings.js', 'keepalive.js', 'index.html', 'briefing.html', 'artifacts.html', 'settings.html',
  'styles.css', 'icon.ico', 'launch.vbs', 'message.vbs', 'windows-zones.json',
  'fonts\JetBrainsMono-Regular.woff2', 'fonts\JetBrainsMono-SemiBold.woff2', 'fonts\JetBrainsMono-Bold.woff2', 'fonts\OFL.txt'
New-Item -ItemType Directory -Force "$stage\app\fonts" | Out-Null
foreach ($f in $AppFiles) { Copy-Item (Join-Path "$b\app" $f) (Join-Path "$stage\app" $f) }
$extra = @(Get-ChildItem "$b\app" -Recurse -File | ForEach-Object { $_.FullName.Substring("$b\app\".Length) } | Where-Object { $AppFiles -notcontains $_ })
if ($extra.Count) { Write-Warning "Not packaged (not on the approved list): $($extra -join ', ')" }
Set-Content "$stage\app\VERSION" $Version -Encoding ASCII -NoNewline

# Only the pinned, officially signed Node.js engine is packaged (hash from nodejs.org/dist/v24.21.0/SHASUMS256.txt, "win-x64/node.exe").
# When you move to a new Node.js LTS, update these three values from the official SHASUMS256.txt.
$NodeVersion = 'v24.21.0'
$NodeSha256 = 'BA4E6D110E8C1592A1ECD390F6B05F3DA124B13871A5BE62B341A07A853C6C32'
$NodeSigner = 'CN=OpenJS Foundation,*'
$nodeDirs = @(Get-ChildItem "$b\runtime-src" -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'node.exe') })
if ($nodeDirs.Count -ne 1) { throw "runtime-src must hold exactly one Node.js folder (found $($nodeDirs.Count))." }
$nodeExe = Join-Path $nodeDirs[0].FullName 'node.exe'
if ((Get-FileHash $nodeExe -Algorithm SHA256).Hash -ne $NodeSha256) { throw "node.exe does not match the pinned SHA-256 for $NodeVersion." }
$sig = Get-AuthenticodeSignature $nodeExe
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notlike $NodeSigner) { throw "node.exe is not validly signed by the OpenJS Foundation ($($sig.Status))." }
if ((& $nodeExe --version) -ne $NodeVersion) { throw "node.exe is not $NodeVersion." }
Copy-Item $nodeExe "$stage\runtime\node.exe"
Copy-Item (Join-Path $nodeDirs[0].FullName 'LICENSE') "$stage\runtime\NODE-LICENSE.txt"
foreach ($f in 'app\server.js', 'app\app.js', 'app\briefing.js', 'app\artifacts.js', 'app\settings.js', 'app\keepalive.js') { & "$stage\runtime\node.exe" --check (Join-Path $stage $f); if ($LASTEXITCODE) { throw "Syntax error in $f" } }

Copy-Item "$b\installer\install.ps1", "$b\installer\uninstall.ps1", "$b\installer\ui.ps1", "$b\installer\setup.cmd" $pkg
Copy-Item "$b\app\icon.ico" "$pkg\icon.ico"
Set-Content "$pkg\VERSION" $Version -Encoding ASCII -NoNewline

# Privacy check: the package must not hold personal or customer data. Besides fixed patterns, it checks the name and
# customers from this computer's own board settings, so those names never need to be written down in the repository.
$private = [System.Collections.Generic.List[string]]::new()
foreach ($w in @($env:USERNAME)) { if ($w -and $w.Length -ge 3) { $private.Add($w) } }
$localConfig = Join-Path $env:LOCALAPPDATA 'DailyBoard\config.json'
if (Test-Path $localConfig) {
  try { $c = Get-Content $localConfig -Raw | ConvertFrom-Json; foreach ($w in @($c.userName) + @($c.customers)) { if ($w -and ([string]$w).Length -ge 2) { $private.Add([string]$w) } } } catch { }
}
$patterns = @('[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}', '[A-Za-z]:\\Users\\', 'OneDrive - ', 'config\.json\.tmp') + @($private | ForEach-Object { '\b' + [regex]::Escape($_) + '\b' })
$scan = @(Get-ChildItem "$stage\app" -Recurse -File -Include *.js, *.html, *.css, *.json, *.vbs, *.txt, VERSION) + @(Get-ChildItem "$pkg\*" -File -Include *.ps1, *.cmd, VERSION)
$hits = foreach ($f in $scan) {
  $rel = $f.FullName.Substring($b.Length + 1)
  if ($rel -eq 'stage\app\fonts\OFL.txt') { continue }   # the font licence names its authors and their e-mail address
  # Technical Windows names that contain common words (the WScript.Shell component, the registry key \shell\open\command) are not data.
  $text = [IO.File]::ReadAllText($f.FullName) -replace '(?i)WScript\.Shell|Shell\.Application|\$shell\b|\\shell\\open\\command', ''
  foreach ($pat in $patterns) { foreach ($m in [regex]::Matches($text, $pat, 'IgnoreCase')) { "$rel : '$($m.Value)'" } }
}
if (@(Get-ChildItem "$stage\app" -Recurse -File -Filter 'config.json').Count) { $hits = @($hits) + 'a config.json file' }
if ($hits) { throw "Privacy check failed. The package would contain:`n  " + (@($hits) -join "`n  ") }
Write-Output "Privacy check passed ($($scan.Count) files, $($patterns.Count) patterns)."

Compress-Archive -Path "$stage\app", "$stage\runtime" -DestinationPath "$pkg\payload.zip" -CompressionLevel NoCompression

$target = Join-Path $dist 'DailyBoardSetup.exe'
Remove-Item $target -Force -ErrorAction SilentlyContinue
$files = 'install.ps1', 'uninstall.ps1', 'ui.ps1', 'setup.cmd', 'VERSION', 'payload.zip', 'icon.ico'
$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$target
FriendlyName=Daily Board setup
AppLaunched=cmd.exe /c setup.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=
UserQuietInstCmd=
$(($files | ForEach-Object -Begin { $i = 0 } -Process { "FILE$i=`"$_`""; $i++ }) -join "`r`n")
[SourceFiles]
SourceFiles0=$pkg\
[SourceFiles0]
$(($files | ForEach-Object -Begin { $i = 0 } -Process { "%FILE$i%="; $i++ }) -join "`r`n")
"@
Set-Content "$pkg\setup.sed" $sed -Encoding ASCII
$iexpress = Join-Path $env:SystemRoot 'SysWOW64\iexpress.exe'
if (-not (Test-Path $iexpress)) { $iexpress = Join-Path $env:SystemRoot 'System32\iexpress.exe' }
$p = Start-Process $iexpress -ArgumentList "/N /Q $pkg\setup.sed" -Wait -PassThru -WorkingDirectory $pkg  # IExpress cannot open a quoted path
if (-not (Test-Path $target)) { throw "IExpress failed (exit $($p.ExitCode))" }
Get-Item $target

if ($Release) {
  $rel = Join-Path $b 'release'
  New-Item -ItemType Directory -Force $rel | Out-Null
  $name = "DailyBoardSetup-$Version.exe"
  Copy-Item $target (Join-Path $rel $name) -Force
  $hash = (Get-FileHash (Join-Path $rel $name) -Algorithm SHA256).Hash
  $sums = Join-Path $rel 'SHA256SUMS.txt'
  $lines = @(if (Test-Path $sums) { Get-Content $sums | Where-Object { $_ -and $_ -notmatch [regex]::Escape($name) } }) + "$hash  $name"
  Set-Content $sums $lines -Encoding ASCII
  Write-Output "Release: release\$name  SHA-256 $hash"
}
