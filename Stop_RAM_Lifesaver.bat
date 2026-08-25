@echo off
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*RamLifesaverTray.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
