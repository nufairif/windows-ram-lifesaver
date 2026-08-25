$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = "D:\1-dev\dev-miid\optimasi browser\windows-ram-lifesaver" }
$vbsPath = Join-Path $scriptDir "Run_RAM_Lifesaver.vbs"
$icoPath = Join-Path $scriptDir "app.ico"

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop "Windows RAM Lifesaver.lnk"

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "wscript.exe"
$shortcut.Arguments = "`"$vbsPath`""
$shortcut.WorkingDirectory = $scriptDir
$shortcut.IconLocation = "$icoPath,0"
$shortcut.Description = "Windows Process RAM Optimizer (System Tray)"
$shortcut.Save()

Write-Host "Shortcut berhasil diperbarui di Desktop: $shortcutPath" -ForegroundColor Green
