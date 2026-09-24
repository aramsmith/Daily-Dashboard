@echo off
rem Runs the Daily Board setup with the native (64-bit) Windows PowerShell when available.
rem Any options are passed on to install.ps1, for example: setup.cmd -Quiet -UserName Alex -Customers Contoso,Fabrikam -Colors amber,blue
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0install.ps1" %*
exit /b %ERRORLEVEL%
