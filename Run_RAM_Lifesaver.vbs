Set WshShell = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")
currentDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = currentDir & "\RamLifesaverTray.ps1"

' Jalankan PowerShell dengan hak Administrator (Elevated) dan flag -STA di latar belakang
WshShell.ShellExecute "powershell.exe", "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & psScript & """", "", "runas", 0
