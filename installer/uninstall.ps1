# Removes the Daily Board: stops it, deletes its shortcuts, files, settings and the Apps entry.
param([switch]$Quiet)

$ErrorActionPreference = 'SilentlyContinue'
$Root = Join-Path $env:LOCALAPPDATA 'DailyBoard'
$UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DailyBoard'
$Port = 12800

# Does the removal. $step (optional) receives progress: percent and a short text.
function Invoke-Uninstall([scriptblock]$step) {
  $report = { param($p, $x) if ($step) { & $step $p $x } }
  & $report 15 'Closing the board if it is open...'
  try {
    $h = Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 3
    if ($h.app -eq 'daily-board') {
      Get-NetTCPConnection -LocalPort $Port -State Listen | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
    }
  } catch { }
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like "*$Root*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Start-Sleep -Milliseconds 800

  & $report 45 'Removing the shortcuts...'
  $info = Join-Path $Root 'install.json'
  if (Test-Path $info) { try { (Get-Content $info -Raw | ConvertFrom-Json).shortcuts | ForEach-Object { Remove-Item $_ -Force } } catch { } }
  $shell = New-Object -ComObject WScript.Shell
  foreach ($dir in @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))) {
    Get-ChildItem $dir -Filter '*.lnk' | ForEach-Object {
      $lnk = $shell.CreateShortcut($_.FullName)
      if ("$($lnk.TargetPath) $($lnk.Arguments)" -like "*\DailyBoard\app\launch.vbs*") { Remove-Item $_.FullName -Force }
    }
  }

  & $report 65 'Removing the board from Windows Settings > Apps...'
  Remove-Item $UninstallKey -Recurse -Force
  Remove-Item 'HKCU:\Software\Classes\dailyboard' -Recurse -Force

  & $report 85 'Removing the files and your settings...'
  Set-Location $env:TEMP
  Remove-Item $Root -Recurse -Force
  if (Test-Path $Root) {
    # A file was still in use: finish the clean-up a few seconds later.
    Start-Process (Join-Path $env:SystemRoot 'System32\cmd.exe') -ArgumentList "/c timeout /t 5 /nobreak >nul & rmdir /s /q `"$Root`"" -WindowStyle Hidden
  }
  & $report 100 'Done'
}

if ($Quiet) { Invoke-Uninstall $null; exit 0 }

$script:exitCode = 1
try {
  . (Join-Path $PSScriptRoot 'ui.ps1')
  $installedVersion = try { [string](Get-Content (Join-Path $Root 'install.json') -Raw | ConvertFrom-Json).version } catch { '' }
  $ui = New-SetupWindow $(if ($installedVersion) { "Daily Board - version $installedVersion" } else { 'Daily Board' }) (Join-Path $Root 'app\icon.ico')
  if (-not $ui.Window) { throw 'no window' }
  Set-UiPage $ui 'Remove the Daily Board?' 'Your mail and calendar are not affected. Your name, customers and colours are removed from this computer.' $null 'Remove' 'Cancel' 'Danger'
  $script:stage = 'confirm'
  $ui.SecondaryButton.Add_Click({ $ui.Window.Close() })
  $ui.PrimaryButton.Add_Click({
    if ($script:stage -ne 'confirm') { $ui.Window.Close(); return }
    $script:stage = 'working'
    $prog = New-UiProgress $ui
    Set-UiPage $ui 'Removing the Daily Board' '' $prog.Panel '' ''
    $ui.CloseButton.IsEnabled = $false
    Update-Ui
    Invoke-Uninstall { param($pct, $text) $prog.Bar.Value = $pct; $prog.Step.Text = $text; Update-Ui }
    $script:stage = 'done'; $script:exitCode = 0
    Set-UiPage $ui 'The Daily Board is removed' '' (New-UiResult $ui $true 'Everything is gone from this computer. To use the board again, run DailyBoardSetup.exe.') 'Close' ''
  })
  $ui.Window.Add_Closing({ param($s, $e) if ($script:stage -eq 'working') { $e.Cancel = $true } })
  [void]$ui.Window.ShowDialog()
  exit $script:exitCode
} catch {
  # Fallback when the modern window cannot open.
  Add-Type -AssemblyName System.Windows.Forms
  $r = [System.Windows.Forms.MessageBox]::Show("Remove the Daily Board from this computer?`n`nYour mail and calendar are not affected. Your name, customers and colours are removed.", 'Daily Board', 'YesNo', 'Question')
  if ($r -ne 'Yes') { exit 1 }
  Invoke-Uninstall $null
  [void][System.Windows.Forms.MessageBox]::Show('The Daily Board has been removed.', 'Daily Board', 'OK', 'Information')
  exit 0
}
