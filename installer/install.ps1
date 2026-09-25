# Daily Board setup: asks for the user's name and 1-3 customers, replaces any older version,
# installs the new version with its own Node.js engine,
# creates shortcuts and registers an uninstaller under Windows Settings > Apps.
param([switch]$Quiet, [string]$UserName, [string[]]$Customers, [string[]]$Colors)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
# The version comes from the VERSION file that the build puts next to this script (single source of truth).
$AppVersion = '0.0.0-dev'
try { $v = (Get-Content (Join-Path $Here 'VERSION') -Raw).Trim(); if ($v -match '^\d+\.\d+\.\d+$') { $AppVersion = $v } } catch { }
$Root = Join-Path $env:LOCALAPPDATA 'DailyBoard'
$ConfigFile = Join-Path $Root 'config.json'
$InstallInfo = Join-Path $Root 'install.json'
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DailyBoard'
$Port = 12800
# Customer colours (keep in sync with CUSTOMER_COLORS in app\server.js, styles.css and the palettes in ui.ps1).
$ColorKeys = @('amber', 'blue', 'violet', 'pink', 'cyan', 'slate')

# Keeps valid, unique choices; fills the rest with the first free colour, starting at the row's default.
function Resolve-Colors([string[]]$wanted, [int]$count) {
  $out = New-Object string[] $count
  $used = @()
  for ($i = 0; $i -lt $count; $i++) {
    $c = if ($wanted -and $wanted.Count -gt $i) { ([string]$wanted[$i]).Trim().ToLowerInvariant() } else { '' }
    if ($ColorKeys -contains $c -and $used -notcontains $c) { $out[$i] = $c; $used += $c }
  }
  for ($i = 0; $i -lt $count; $i++) {
    if ($out[$i]) { continue }
    $c = @($ColorKeys[$i..($ColorKeys.Count - 1)] + $ColorKeys | Where-Object { $used -notcontains $_ })[0]
    $out[$i] = $c; $used += $c
  }
  return ,$out
}

function Show-Message([string]$Text, [bool]$ok = $true) {
  if ($Quiet) {
    # The quiet setup runs hidden, so IT can read the result in a log file as well as in the exit code.
    Write-Output $Text
    try { Add-Content -Path (Join-Path $env:TEMP 'DailyBoardSetup.log') -Value "$(Get-Date -Format s) $Text" } catch { }
    return
  }
  try {
    . (Join-Path $Here 'ui.ps1')
    Show-UiMessage $(if ($ok) { 'Done' } else { 'Setup could not finish' }) $Text $ok 'Daily Board setup' (Join-Path $Here 'icon.ico')
    return
  } catch { }
  Add-Type -AssemblyName System.Windows.Forms
  [void][System.Windows.Forms.MessageBox]::Show($Text, 'Daily Board setup', 'OK', $(if ($ok) { 'Information' } else { 'Error' }))
}

# Same rules as the board: letters (any language), digits, spaces and & . , ' ( ) -
function Clean-Name([string]$s) {
  if (-not $s) { return '' }
  $t = ($s.Normalize([Text.NormalizationForm]::FormC) -replace "[^\p{L}\p{N} &.,'()\-]", '' -replace '\s+', ' ').Trim()
  if ($t.Length -gt 40) { $t = $t.Substring(0, 40) }
  return $t
}

function Get-BoardTitle([string]$name) {
  if (-not $name) { return 'Daily Board' }
  if ($name -match 's$') { return "$name' Daily Board" }
  return "$name's Daily Board"
}

# The same checks for the wizard and the quiet install. Returns an error text, or $null when the input is good.
function Test-Answer([string]$userName, [string[]]$customers, [string[]]$colors) {
  if (-not $userName) { return 'Please enter your name.' }
  if (-not $customers -or $customers.Count -eq 0) { return 'Please enter at least one customer.' }
  if ($customers.Count -gt 3) { return 'You can enter at most 3 customers.' }
  if (@($customers | Where-Object { $_.Length -lt 2 }).Count) { return 'Each customer name needs at least 2 characters.' }
  if (@($customers | ForEach-Object { $_.ToLowerInvariant() } | Select-Object -Unique).Count -ne $customers.Count) { return 'Each customer can be entered only once.' }
  if ($colors -and $colors.Count) {
    if ($colors.Count -gt $customers.Count) { return 'There are more colours than customers.' }
    $bad = @($colors | Where-Object { $ColorKeys -notcontains $_ })
    if ($bad.Count) { return "Unknown colour: $($bad[0]). Choose from: $($ColorKeys -join ', ')." }
    if (@($colors | Select-Object -Unique).Count -ne $colors.Count) { return 'Pick a different colour for each customer.' }
  }
  return $null
}

# The installed version (from install.json), or $null when the board is not installed.
function Get-InstalledVersion {
  try { $v = [string](Get-Content $InstallInfo -Raw | ConvertFrom-Json).version; if ($v -match '^\d+\.\d+\.\d+$') { return $v } } catch { }
  return $null
}

function Get-Defaults {
  $d = @{ UserName = ''; Customers = @(); Colors = @() }
  if (Test-Path $ConfigFile) {
    try {
      $cfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
      $d.UserName = [string]$cfg.userName
      $d.Customers = @($cfg.customers | ForEach-Object { [string]$_ })
      $d.Colors = @($cfg.colors | ForEach-Object { [string]$_ })
      return $d
    } catch { }
  }
  try {
    Add-Type -AssemblyName System.DirectoryServices.AccountManagement
    $d.UserName = [System.DirectoryServices.AccountManagement.UserPrincipal]::Current.GivenName
  } catch { }
  if (-not $d.UserName) { $d.UserName = (Get-Culture).TextInfo.ToTitleCase($env:USERNAME) }
  return $d
}

# The setup window: Details -> Installing -> Done (or a clear error). Returns the exit code.
function Show-SetupUi($defaults, [bool]$upgrade) {
  . (Join-Path $Here 'ui.ps1')
  $ui = New-SetupWindow "Daily Board setup - version $AppVersion" (Join-Path $Here 'icon.ico')
  $t = $ui.Theme
  $cap = { param($k) $k.Substring(0, 1).ToUpper() + $k.Substring(1) }

  $form = New-Object System.Windows.Controls.StackPanel
  [void]$form.Children.Add((New-UiText 'Your name' $t.Text 13 'SemiBold' '0,0,0,6'))
  $name = New-Object System.Windows.Controls.TextBox
  $name.MaxLength = 40; $name.Text = $defaults.UserName
  [System.Windows.Automation.AutomationProperties]::SetName($name, 'Your name')
  [void]$form.Children.Add($name)
  $preview = New-UiText '' $t.Muted 12 'Normal' '0,6,0,0'
  [void]$form.Children.Add($preview)
  $updatePreview = { $preview.Text = 'The board will be called: ' + (Get-BoardTitle (Clean-Name $name.Text)) }
  $name.Add_TextChanged($updatePreview); & $updatePreview

  [void]$form.Children.Add((New-UiText 'Customers (1 to 3)' $t.Text 13 'SemiBold' '0,22,0,2'))
  [void]$form.Children.Add((New-UiText 'Each customer gets its own mail section on the board, in the colour you pick.' $t.Muted 12 'Normal' '0,0,0,10'))
  $boxes = @()
  $script:picked = [string[]](Resolve-Colors $defaults.Colors 3)
  for ($i = 0; $i -lt 3; $i++) {
    $row = New-Object System.Windows.Controls.Grid
    $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
    [void]$row.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
    [void]$row.ColumnDefinitions.Add($c2)
    $box = New-Object System.Windows.Controls.TextBox
    $box.MaxLength = 40
    if ($defaults.Customers.Count -gt $i) { $box.Text = $defaults.Customers[$i] }
    [System.Windows.Automation.AutomationProperties]::SetName($box, "Customer $($i + 1)")
    $box.Background = ConvertTo-Brush $t.Colors[$script:picked[$i]][1]
    $box.BorderBrush = ConvertTo-Brush $t.Colors[$script:picked[$i]][0]
    [void]$row.Children.Add($box)
    $swatches = New-Object System.Windows.Controls.StackPanel
    $swatches.Orientation = 'Horizontal'; $swatches.VerticalAlignment = 'Center'
    $swatches.Margin = New-Object System.Windows.Thickness(12, 0, 0, 0)
    [System.Windows.Controls.Grid]::SetColumn($swatches, 1)
    foreach ($key in $ColorKeys) {
      $rb = New-Object System.Windows.Controls.RadioButton
      $rb.Style = $ui.Window.FindResource('Swatch')
      $rb.GroupName = "customer$i"
      $rb.Background = ConvertTo-Brush $t.Colors[$key][0]
      $rb.ToolTip = & $cap $key
      [System.Windows.Automation.AutomationProperties]::SetName($rb, "$(& $cap $key) for customer $($i + 1)")
      $rb.Tag = @{ Row = $i; Key = $key; Box = $box }
      $rb.IsChecked = ($script:picked[$i] -eq $key)
      $rb.Add_Checked({
        $d = $this.Tag
        $script:picked[$d.Row] = $d.Key
        $d.Box.Background = ConvertTo-Brush $ui.Theme.Colors[$d.Key][1]
        $d.Box.BorderBrush = ConvertTo-Brush $ui.Theme.Colors[$d.Key][0]
      })
      [void]$swatches.Children.Add($rb)
    }
    [void]$row.Children.Add($swatches)
    [void]$form.Children.Add($row)
    $boxes += $box
  }

  $heading = if ($upgrade) { 'Update your Daily Board' } else { 'Set up your Daily Board' }
  $installed = Get-InstalledVersion
  $cmp = try { ([version]$installed).CompareTo([version]$AppVersion) } catch { -1 }
  $intro = if (-not $upgrade) { "Your personal board with live Outlook mail, meetings and Copilot briefings. Enter your name and the customers you follow. This installs version $AppVersion." }
    elseif (-not $installed) { "This replaces your current Daily Board with version $AppVersion. Check your details, then click Update." }
    elseif ($cmp -lt 0) { "You have version $installed. This updates it to version $AppVersion. Check your details, then click Update." }
    elseif ($cmp -eq 0) { "Version $AppVersion is already installed. Click Update to repair it or to change your details." }
    else { "Note: you have a newer version ($installed). This setup installs the older version $AppVersion. Click Update only if you want to go back." }
  Set-UiPage $ui $heading $intro $form $(if ($upgrade) { 'Update' } else { 'Install' }) 'Cancel'

  $script:stage = 'details'
  $script:setupExit = 1
  $ui.SecondaryButton.Add_Click({ $ui.Window.Close() })
  $ui.PrimaryButton.Add_Click({
    if ($script:stage -eq 'done') {
      # Start from the board's own folder; otherwise the board would lock the setup's temporary folder and block the next setup.
      Start-Process (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList "`"$(Join-Path $Root 'app\launch.vbs')`"" -WorkingDirectory (Join-Path $Root 'app')
      $ui.Window.Close(); return
    }
    if ($script:stage -ne 'details') { $ui.Window.Close(); return }

    $n = Clean-Name $name.Text
    $rows = @(for ($j = 0; $j -lt 3; $j++) { $v = Clean-Name $boxes[$j].Text; if ($v) { @{ Name = $v; Color = $script:picked[$j] } } })
    $cs = @($rows | ForEach-Object { $_.Name })
    $ks = @($rows | ForEach-Object { $_.Color })
    $problem = Test-Answer $n $cs $ks
    if ($problem) {
      $ui.ErrorText.Text = $problem
      if (-not $n) { [void]$name.Focus() } elseif ($cs.Count -eq 0) { [void]$boxes[0].Focus() }
      return
    }

    $script:stage = 'working'
    $prog = New-UiProgress $ui
    Set-UiPage $ui $(if ($upgrade) { 'Updating your Daily Board' } else { 'Installing your Daily Board' }) 'This takes a few seconds.' $prog.Panel '' ''
    $ui.CloseButton.IsEnabled = $false
    Update-Ui
    try {
      $title = Invoke-Install @{ UserName = $n; Customers = $cs; Colors = $ks } { param($pct, $text) $prog.Bar.Value = $pct; $prog.Step.Text = $text; Update-Ui } | Select-Object -Last 1
      $script:stage = 'done'; $script:setupExit = 0
      Set-UiPage $ui "$title is ready" '' (New-UiResult $ui $true "Version $AppVersion is installed. Shortcuts are on your desktop and in the Start menu. When the board opens, sign in with your Microsoft 365 work account.") 'Start the board' 'Close'
    } catch {
      $script:stage = 'failed'; $script:setupExit = 2
      Set-UiPage $ui 'Setup could not finish' '' (New-UiResult $ui $false $_.Exception.Message) 'Close' '' -IsError
    }
  })
  $ui.Window.Add_Closing({ param($s, $e) if ($script:stage -eq 'working') { $e.Cancel = $true } })
  $ui.Window.Add_ContentRendered({ [void]$name.Focus(); $name.SelectAll() })
  [void]$ui.Window.ShowDialog()
  return $script:setupExit
}

function Stop-OldBoard {
  # Stop whatever board (old or new) is listening on the board's port, but only if it is really ours.
  $isOurs = $false
  try {
    $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3
    $isOurs = $h.app -eq 'daily-board'
  } catch { }
  if ($isOurs) {
    Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
      try { Stop-Process -Id $_.OwningProcess -Force -ErrorAction Stop } catch { }
    }
    Start-Sleep -Milliseconds 800
  }
  # Any node.exe still running from an install folder (for example during sign-in) is stopped too.
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like "*$Root*" } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch { } }
}

function Remove-OldShortcuts([string[]]$keep) {
  # Removes shortcuts of older versions (and of this board under an older title), but not the ones just created.
  $shortcutDirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) | Where-Object { $_ -and (Test-Path $_) }
  $shell = New-Object -ComObject WScript.Shell
  foreach ($dir in $shortcutDirs) {
    Get-ChildItem $dir -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $keep -notcontains $_.FullName } | ForEach-Object {
      try {
        $lnk = $shell.CreateShortcut($_.FullName)
        $target = "$($lnk.TargetPath) $($lnk.Arguments)"
        if ($target -like "*\DailyBoard\app\launch.vbs*") { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
      } catch { }
    }
  }
}

# Unpacks the new version next to the old one and checks it, before anything of the old version is touched.
function Expand-NewVersion([string]$payload, [string]$staging) {
  if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
  New-Item -ItemType Directory -Force $staging | Out-Null
  Expand-Archive -Path $payload -DestinationPath $staging -Force
  foreach ($f in 'runtime\node.exe', 'app\server.js', 'app\index.html', 'app\app.js', 'app\styles.css', 'app\launch.vbs', 'app\keepalive.js', 'app\icon.ico') {
    if (-not (Test-Path (Join-Path $staging $f))) { throw "The setup package is incomplete ($f is missing)." }
  }
}

function New-Shortcut([string]$path, [string]$title) {
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut($path)
  $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
  $lnk.Arguments = '"' + (Join-Path $Root 'app\launch.vbs') + '"'
  $lnk.WorkingDirectory = Join-Path $Root 'app'
  $lnk.IconLocation = (Join-Path $Root 'app\icon.ico') + ',0'
  $lnk.Description = "$title - live Outlook mail, meetings and Copilot briefings"
  $lnk.Save()
}

# Installs or upgrades the board. $step (optional) receives progress: percent and a short text.
function Invoke-Install($answer, [scriptblock]$step) {
  $report = { param($p, $x) if ($step) { & $step $p $x } }
  $title = Get-BoardTitle $answer.UserName
  & $report 10 'Unpacking the new version...'

  # Safe upgrade: unpack and check the new version first, then swap folders. If anything fails, the old version comes back.
  $staging = Join-Path $Root '.new'
  $backup = Join-Path $Root '.old'
  New-Item -ItemType Directory -Force $Root | Out-Null
  Expand-NewVersion $payload $staging

  & $report 35 'Closing the board if it is open...'
  Stop-OldBoard
  $oldConfig = if (Test-Path $ConfigFile) { [System.IO.File]::ReadAllText($ConfigFile) } else { $null }
  if (Test-Path $backup) { Remove-Item $backup -Recurse -Force }
  New-Item -ItemType Directory -Force $backup | Out-Null
  $safe = ($title -replace '[\\/:*?"<>|]', '').Trim()
  $desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "$safe.lnk"
  $startLnk = Join-Path ([Environment]::GetFolderPath('Programs')) "$safe.lnk"
  try {
    & $report 55 'Installing the new version...'
    # Directory.Move is a single rename: it either moves the whole folder or nothing (Move-Item may stop halfway).
    foreach ($sub in 'app', 'runtime') { $p = Join-Path $Root $sub; if (Test-Path $p) { [System.IO.Directory]::Move($p, (Join-Path $backup $sub)) } }
    foreach ($sub in 'app', 'runtime') { [System.IO.Directory]::Move((Join-Path $staging $sub), (Join-Path $Root $sub)) }
    Copy-Item (Join-Path $Here 'uninstall.ps1'), (Join-Path $Here 'ui.ps1') $Root -Force
    & $report 70 'Saving your settings...'

    $json = [ordered]@{ userName = $answer.UserName; customers = @($answer.Customers); colors = [string[]](Resolve-Colors $answer.Colors $answer.Customers.Count) } | ConvertTo-Json
    [System.IO.File]::WriteAllText($ConfigFile, $json, (New-Object System.Text.UTF8Encoding($false)))

    & $report 80 'Creating the shortcuts...'
    New-Shortcut $desktopLnk $title
    New-Shortcut $startLnk $title
    [ordered]@{ version = $AppVersion; shortcuts = @($desktopLnk, $startLnk) } | ConvertTo-Json | Set-Content $InstallInfo -Encoding UTF8

    & $report 90 'Adding the board to Windows Settings > Apps...'
    $sizeKb = [int]((Get-ChildItem $Root -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
    New-Item -Path $UninstallKey -Force | Out-Null
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $values = @{
      DisplayName = 'Daily Board'; DisplayVersion = $AppVersion; Publisher = 'Daily Board'
      InstallLocation = $Root; DisplayIcon = (Join-Path $Root 'app\icon.ico')
      UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Root 'uninstall.ps1')`""
      QuietUninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $Root 'uninstall.ps1')`" -Quiet"
    }
    foreach ($k in $values.Keys) { Set-ItemProperty -Path $UninstallKey -Name $k -Value $values[$k] }
    Set-ItemProperty -Path $UninstallKey -Name NoModify -Value 1 -Type DWord
    Set-ItemProperty -Path $UninstallKey -Name NoRepair -Value 1 -Type DWord
    Set-ItemProperty -Path $UninstallKey -Name EstimatedSize -Value $sizeKb -Type DWord

    # The dailyboard:// link lets the "Start the board" button on a board page start the engine again. It always runs the
    # board's own launcher with the fixed /quiet option; nothing from the link itself is passed on.
    $proto = 'HKCU:\Software\Classes\dailyboard'
    $launchCmd = '"{0}" "{1}" /quiet' -f (Join-Path $env:SystemRoot 'System32\wscript.exe'), (Join-Path $Root 'app\launch.vbs')
    New-Item -Path "$proto\shell\open\command" -Force | Out-Null
    New-Item -Path "$proto\DefaultIcon" -Force | Out-Null
    Set-ItemProperty -Path $proto -Name '(default)' -Value 'URL:Daily Board'
    Set-ItemProperty -Path $proto -Name 'URL Protocol' -Value ''
    Set-ItemProperty -Path "$proto\DefaultIcon" -Name '(default)' -Value ((Join-Path $Root 'app\icon.ico') + ',0')
    Set-ItemProperty -Path "$proto\shell\open\command" -Name '(default)' -Value $launchCmd
  } catch {
    $failure = $_
    foreach ($sub in 'app', 'runtime') {
      $old = Join-Path $backup $sub
      if (Test-Path $old) {
        $p = Join-Path $Root $sub
        try {
          if (Test-Path $p) { [System.IO.Directory]::Move($p, (Join-Path $staging "$sub-failed")) }
          [System.IO.Directory]::Move($old, $p)
        } catch { }
      }
    }
    if ($null -ne $oldConfig) { [System.IO.File]::WriteAllText($ConfigFile, $oldConfig, (New-Object System.Text.UTF8Encoding($false))) }
    throw "The update was undone, and the previous version is kept. $($failure.Exception.Message)"
  }

  & $report 97 'Cleaning up...'
  # Only now, with the new version in place, clean up the old version, its shortcuts and the temporary folders.
  Remove-OldShortcuts @($desktopLnk, $startLnk)
  Remove-Item $backup, $staging -Recurse -Force -ErrorAction SilentlyContinue
  & $report 100 'Done'
  return $title
}

# ---------------- main ----------------
try {
  $payload = Join-Path $Here 'payload.zip'
  if (-not (Test-Path $payload)) { throw 'The setup package is incomplete (payload.zip is missing).' }

  $upgrade = Test-Path (Join-Path $Root 'app')
  $defaults = Get-Defaults
  if ($Quiet) {
    # Quiet install: check everything first and stop with a clear error, so IT never gets different settings than asked for.
    $split = { param($v) @($v | Where-Object { $_ } | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim(" '") } | Where-Object { $_ }) }
    $n = Clean-Name $UserName
    if ($UserName -and $n -ne (($UserName -replace '\s+', ' ').Trim())) { throw "The name '$UserName' has characters that are not allowed, or is longer than 40 characters." }
    $rawCustomers = @(& $split $Customers)
    $cs = @($rawCustomers | ForEach-Object { Clean-Name $_ })
    for ($i = 0; $i -lt $rawCustomers.Count; $i++) {
      if ($cs[$i] -ne (($rawCustomers[$i] -replace '\s+', ' ').Trim())) { throw "The customer '$($rawCustomers[$i])' has characters that are not allowed, or is longer than 40 characters." }
    }
    $ks = @(& $split $Colors | ForEach-Object { $_.ToLowerInvariant() })
    $problem = Test-Answer $n $cs $ks
    if ($problem) { throw "Quiet setup: $problem" }
    $answer = @{ UserName = $n; Customers = $cs; Colors = (Resolve-Colors $(if ($ks.Count) { $ks } else { $defaults.Colors }) $cs.Count) }
    $title = Invoke-Install $answer $null | Select-Object -Last 1
    Show-Message "Installed $title $AppVersion"
    exit 0
  }
  exit (Show-SetupUi $defaults $upgrade | Select-Object -Last 1)

} catch {
  Show-Message ("The Daily Board could not be installed.`n`n" + $_.Exception.Message) $false
  exit 2
}
