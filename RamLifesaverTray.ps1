Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 1. Pastikan Berjalan Sebagai Administrator (Self-Elevation)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    # Otomatis meminta izin Administrator (UAC Prompt)
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = "D:\1-dev\dev-miid\optimasi browser\windows-ram-lifesaver\RamLifesaverTray.ps1" }
    
    Start-Process powershell.exe -ArgumentList "-STA -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`"" -Verb RunAs
    exit
}

# Win32 & Native NT API (Setara Penuh Fitur RAMMap Microsoft + Game Mode & Window Query)
$win32Code = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public enum SYSTEM_MEMORY_LIST_COMMAND {
    MemoryCaptureAccessedBits = 0,
    MemoryEmptyWorkingSets = 1,
    MemoryEmptySystemWorkingSet = 2,
    MemoryFlushModifiedList = 3,
    MemoryPurgeStandbyList = 4,
    MemoryPurgeLowPriorityStandbyList = 5
}

public enum QUERY_USER_NOTIFICATION_STATE {
    QUNS_NOT_PRESENT = 1,
    QUNS_BUSY = 2,
    QUNS_RUNNING_D3D_FULL_SCREEN = 3,
    QUNS_PRESENTATION_MODE = 4,
    QUNS_ACCEPTS_NOTIFICATIONS = 5,
    QUNS_QUIET_TIME = 6,
    QUNS_APP = 7
}

public class Win32RamMap {
    [DllImport("ntdll.dll")]
    public static extern uint NtSetSystemInformation(int SystemInformationClass, ref int SystemInformation, int SystemInformationLength);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    [DllImport("kernel32.dll")]
    public static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);

    [DllImport("psapi.dll")]
    public static extern int EmptyWorkingSet(IntPtr hwProc);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, int dwProcessId);

    [DllImport("shell32.dll")]
    public static extern int SHQueryUserNotificationState(out QUERY_USER_NOTIFICATION_STATE pquns);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetDesktopWindow();

    [DllImport("user32.dll")]
    public static extern IntPtr GetShellWindow();

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 1)]
    public struct TOKEN_PRIVILEGES {
        public int PrivilegeCount;
        public long Luid;
        public int Attributes;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public class MEMORYSTATUSEX {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;

        public MEMORYSTATUSEX() {
            this.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        }
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

    public const int SystemMemoryListInformation = 80;
    public const string SE_INCREASE_QUOTA_NAME = "SeIncreaseQuotaPrivilege";
    public const string SE_PROFILE_SINGLE_PROCESS_NAME = "SeProfileSingleProcessPrivilege";
    public const int SE_PRIVILEGE_ENABLED = 0x00000002;

    public static bool EnablePrivilege(string privilege) {
        IntPtr hToken;
        if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out hToken)) return false;
        try {
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Attributes = SE_PRIVILEGE_ENABLED;
            if (!LookupPrivilegeValue(null, privilege, out tp.Luid)) return false;
            return AdjustTokenPrivileges(hToken, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        } finally {
            CloseHandle(hToken);
        }
    }

    public static uint ExecuteCommand(SYSTEM_MEMORY_LIST_COMMAND command) {
        EnablePrivilege(SE_INCREASE_QUOTA_NAME);
        EnablePrivilege(SE_PROFILE_SINGLE_PROCESS_NAME);

        int cmd = (int)command;
        return NtSetSystemInformation(SystemMemoryListInformation, ref cmd, sizeof(int));
    }

    public static bool CleanWorkingSet(int pid) {
        IntPtr hProcess = OpenProcess(0x0400 | 0x0100, false, pid);
        if (hProcess == IntPtr.Zero) return false;
        try {
            return EmptyWorkingSet(hProcess) != 0;
        } finally {
            CloseHandle(hProcess);
        }
    }

    public static MEMORYSTATUSEX GetMemoryStatus() {
        MEMORYSTATUSEX memStatus = new MEMORYSTATUSEX();
        GlobalMemoryStatusEx(memStatus);
        return memStatus;
    }
}
"@

Add-Type -TypeDefinition $win32Code -Language CSharp

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { "D:\1-dev\dev-miid\optimasi browser\windows-ram-lifesaver" }
$iconPath = Join-Path $scriptDir "app.ico"
$configFile = Join-Path $scriptDir "config.json"
$vbsPath = Join-Path $scriptDir "Run_RAM_Lifesaver.vbs"
$taskName = "WindowsRAMLifesaver"

# Whitelist Proses Kritis Windows (Jangan pernah dipangkas)
$systemWhitelist = @(
    'System', 'Idle', 'Registry', 'smss', 'csrss', 'wininit', 'services', 
    'lsass', 'winlogon', 'dwm', 'fontdrvhost', 'spoolsv', 'Memory Compression',
    'Secure System', 'ntoskrnl'
)

# Daftar Proses Browser Populer
$browserProcessNames = @(
    'brave', 'chrome', 'msedge', 'firefox', 'opera', 'opera_gx', 
    'vivaldi', 'arc', 'zen', 'thorium', 'waterfox', 'librewolf', 
    'floorp', 'chromium', 'yandex', 'sidekick'
)

# Fungsi Pengaturan (Config Management)
function Load-Config {
    $defaultConfig = @{
        AutoClean = $true
        Threshold = 80
        CheckInterval = 10
        AutoCleanCooldownMinutes = 3
        SilentMode = $false
        ShowDynamicIcon = $true
        SmartGameMode = $true
        CustomWhitelist = @('obs64', 'code', 'devenv', 'docker', 'vmmem', 'premiere', 'AfterFX', 'blender')
        LastAutoClean = [DateTime]::MinValue
    }

    if (Test-Path $configFile) {
        try {
            $json = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($json.PSObject.Properties['AutoClean']) { $defaultConfig.AutoClean = [bool]$json.AutoClean }
            if ($json.PSObject.Properties['Threshold']) { $defaultConfig.Threshold = [int]$json.Threshold }
            if ($json.PSObject.Properties['CheckInterval']) { $defaultConfig.CheckInterval = [int]$json.CheckInterval }
            if ($json.PSObject.Properties['AutoCleanCooldownMinutes']) { $defaultConfig.AutoCleanCooldownMinutes = [int]$json.AutoCleanCooldownMinutes }
            if ($json.PSObject.Properties['SilentMode']) { $defaultConfig.SilentMode = [bool]$json.SilentMode }
            if ($json.PSObject.Properties['ShowDynamicIcon']) { $defaultConfig.ShowDynamicIcon = [bool]$json.ShowDynamicIcon }
            if ($json.PSObject.Properties['SmartGameMode']) { $defaultConfig.SmartGameMode = [bool]$json.SmartGameMode }
            if ($json.PSObject.Properties['CustomWhitelist']) { $defaultConfig.CustomWhitelist = @($json.CustomWhitelist) }
        } catch {}
    } else {
        Save-ConfigInternal $defaultConfig
    }

    return $defaultConfig
}

function Save-ConfigInternal($cfg) {
    try {
        $exportObj = @{
            AutoClean = $cfg.AutoClean
            Threshold = $cfg.Threshold
            CheckInterval = $cfg.CheckInterval
            AutoCleanCooldownMinutes = $cfg.AutoCleanCooldownMinutes
            SilentMode = $cfg.SilentMode
            ShowDynamicIcon = $cfg.ShowDynamicIcon
            SmartGameMode = $cfg.SmartGameMode
            CustomWhitelist = $cfg.CustomWhitelist
        }
        $exportObj | ConvertTo-Json -Depth 4 | Set-Content -Path $configFile -Encoding UTF8
    } catch {}
}

function Save-Config {
    Save-ConfigInternal $global:config
}

$global:config = Load-Config

# Helper Startup Task Scheduler
function Test-StartupEnabled {
    try {
        & schtasks.exe /Query /TN $taskName 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Set-StartupState([bool]$enable) {
    if ($enable) {
        $action = "wscript.exe `"$vbsPath`""
        & schtasks.exe /Create /TN $taskName /TR $action /SC ONLOGON /RL HIGHEST /F 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Show-Notification "Startup Windows" "Windows RAM Lifesaver akan otomatis berjalan saat Windows booting (dengan hak Admin penuh)." [System.Windows.Forms.ToolTipIcon]::Info -force $true
        }
    } else {
        & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
        Show-Notification "Startup Windows" "Fitur auto-start saat Windows booting telah dinonaktifkan." [System.Windows.Forms.ToolTipIcon]::Info -force $true
    }
}

# Helper Notifikasi
function Show-Notification([string]$title, [string]$msg, [System.Windows.Forms.ToolTipIcon]$iconType = [System.Windows.Forms.ToolTipIcon]::Info, [bool]$force = $false) {
    if ($global:config.SilentMode -and -not $force) { return }
    $global:notifyIcon.BalloonTipTitle = $title
    $global:notifyIcon.BalloonTipText = $msg
    $global:notifyIcon.BalloonTipIcon = $iconType
    $global:notifyIcon.ShowBalloonTip(3000)
}

# Helper Deteksi Game / Fullscreen (Smart Game Mode)
function Test-IsGameOrFullscreenActive {
    try {
        $state = [QUERY_USER_NOTIFICATION_STATE]::QUNS_NOT_PRESENT
        $hr = [Win32RamMap]::SHQueryUserNotificationState([ref]$state)
        if ($hr -eq 0) {
            if ($state -eq [QUERY_USER_NOTIFICATION_STATE]::QUNS_RUNNING_D3D_FULL_SCREEN -or 
                $state -eq [QUERY_USER_NOTIFICATION_STATE]::QUNS_BUSY -or
                $state -eq [QUERY_USER_NOTIFICATION_STATE]::QUNS_PRESENTATION_MODE) {
                return $true
            }
        }

        $fgWnd = [Win32RamMap]::GetForegroundWindow()
        if ($fgWnd -ne [IntPtr]::Zero) {
            $shellWnd = [Win32RamMap]::GetShellWindow()
            $desktopWnd = [Win32RamMap]::GetDesktopWindow()
            if ($fgWnd -eq $shellWnd -or $fgWnd -eq $desktopWnd) {
                return $false
            }

            $rect = New-Object Win32RamMap+RECT
            if ([Win32RamMap]::GetWindowRect($fgWnd, [ref]$rect)) {
                $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
                $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
                $w = $rect.Right - $rect.Left
                $h = $rect.Bottom - $rect.Top
                if ($w -ge $screenWidth -and $h -ge $screenHeight -and $rect.Left -le 0 -and $rect.Top -le 0) {
                    $sb = New-Object System.Text.StringBuilder 256
                    [Win32RamMap]::GetClassName($fgWnd, $sb, 256) | Out-Null
                    $cls = $sb.ToString()
                    if ($cls -notin @("Shell_TrayWnd", "Progman", "WorkerW")) {
                        return $true
                    }
                }
            }
        }
    } catch {}
    return $false
}

function Get-RAMStats {
    $mem = [Win32RamMap]::GetMemoryStatus()
    $tot = [Math]::Round($mem.ullTotalPhys / 1GB, 1)
    $avail = [Math]::Round($mem.ullAvailPhys / 1GB, 1)
    $used = [Math]::Round(($mem.ullTotalPhys - $mem.ullAvailPhys) / 1GB, 1)
    $ld = $mem.dwMemoryLoad

    return @{
        Load = $ld
        TotalGB = $tot
        UsedGB = $used
        AvailGB = $avail
        AvailBytes = $mem.ullAvailPhys
    }
}

# 5 Fungsi Khusus Sesuai Fitur RAMMap
function Clean-WorkingSets {
    # 1. Empty Working Sets (Aplikasi User & Sistem, kecuali Whitelist)
    $allWhitelist = $systemWhitelist + $global:config.CustomWhitelist
    $processes = Get-Process -ErrorAction SilentlyContinue
    foreach ($proc in $processes) {
        if ($allWhitelist -contains $proc.ProcessName -or $proc.Id -le 4) { continue }
        try { [Win32RamMap]::CleanWorkingSet($proc.Id) | Out-Null } catch {}
    }
    [Win32RamMap]::ExecuteCommand([SYSTEM_MEMORY_LIST_COMMAND]::MemoryEmptyWorkingSets) | Out-Null
}

function Clean-SystemWorkingSet {
    # 2. Empty System Working Set (Kernel/Driver/File System)
    [Win32RamMap]::ExecuteCommand([SYSTEM_MEMORY_LIST_COMMAND]::MemoryEmptySystemWorkingSet) | Out-Null
}

function Clean-ModifiedPageList {
    # 3. Empty Modified Page List (Flush ke SSD)
    [Win32RamMap]::ExecuteCommand([SYSTEM_MEMORY_LIST_COMMAND]::MemoryFlushModifiedList) | Out-Null
}

function Clean-StandbyList {
    # 4. Empty Standby List (Kosongkan Cache File / Kolom "Cached" di Task Manager)
    [Win32RamMap]::ExecuteCommand([SYSTEM_MEMORY_LIST_COMMAND]::MemoryPurgeStandbyList) | Out-Null
}

function Clean-Priority0StandbyList {
    # 5. Empty Priority 0 Standby (Cache Sampah Prioritas Rendah)
    [Win32RamMap]::ExecuteCommand([SYSTEM_MEMORY_LIST_COMMAND]::MemoryPurgeLowPriorityStandbyList) | Out-Null
}

# Fitur Khusus: Optimasi Browser Saja
function Clean-BrowserWorkingSets {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $browserProcessNames -contains $_.ProcessName }
    if (-not $procs -or $procs.Count -eq 0) {
        Show-Notification "Optimasi Browser" "Tidak ada proses browser yang sedang aktif." [System.Windows.Forms.ToolTipIcon]::Info -force $true
        return
    }

    $memBefore = 0
    foreach ($p in $procs) { $memBefore += $p.WorkingSet64 }

    $count = 0
    foreach ($p in $procs) {
        try {
            if ([Win32RamMap]::CleanWorkingSet($p.Id)) {
                $count++
            }
        } catch {}
    }

    Clean-ModifiedPageList
    Start-Sleep -Milliseconds 250

    $procsAfter = Get-Process -ErrorAction SilentlyContinue | Where-Object { $browserProcessNames -contains $_.ProcessName }
    $memAfter = 0
    foreach ($p in $procsAfter) { $memAfter += $p.WorkingSet64 }

    $freedBytes = [Math]::Max(0, $memBefore - $memAfter)
    $freedMB = [Math]::Round($freedBytes / 1MB, 0)
    $freedGB = [Math]::Round($freedMB / 1024, 2)
    $freedStr = if ($freedMB -ge 1024) { "$freedGB GB" } else { "$freedMB MB" }

    Show-Notification "🌐 Optimasi Browser Selesai" "Berhasil memangkas RAM dari $count proses browser!`nMemori dihemat: $freedStr" [System.Windows.Forms.ToolTipIcon]::Info -force $true
    Update-TrayTooltip
}

# Fitur Khusus: Pangkas Proses Tunggal berdasarkan Nama
function Clean-ProcessByName([string]$procName) {
    $procs = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if (-not $procs) { return }

    $memBefore = 0
    foreach ($p in $procs) { $memBefore += $p.WorkingSet64 }

    foreach ($p in $procs) {
        try { [Win32RamMap]::CleanWorkingSet($p.Id) | Out-Null } catch {}
    }

    Start-Sleep -Milliseconds 200

    $procsAfter = Get-Process -Name $procName -ErrorAction SilentlyContinue
    $memAfter = 0
    foreach ($p in $procsAfter) { $memAfter += $p.WorkingSet64 }

    $freedMB = [Math]::Max(0, [Math]::Round(($memBefore - $memAfter) / 1MB, 0))

    Show-Notification "Pangkas RAM: $procName" "Proses '$procName' berhasil dipangkas.`nMemori dibebaskan: $freedMB MB" [System.Windows.Forms.ToolTipIcon]::Info -force $true
    Update-TrayTooltip
}

# Fungsi Utama Eksekusi Pembersihan (Super Purge / Spesifik)
function Invoke-FullPurge([string]$modeName = "Super Purge (5-in-1)", [scriptblock]$actionBlock = $null, [bool]$isAuto = $false) {
    $before = Get-RAMStats

    if ($actionBlock) {
        & $actionBlock
    } else {
        # Super Purge: Jalankan kelima mode secara berurutan
        Clean-ModifiedPageList
        Clean-WorkingSets
        Clean-SystemWorkingSet
        Clean-Priority0StandbyList
        Clean-StandbyList
    }

    Start-Sleep -Milliseconds 300
    $after = Get-RAMStats
    $freedBytes = $after.AvailBytes - $before.AvailBytes
    $freedMB = [Math]::Max(0, [Math]::Round($freedBytes / 1MB, 0))
    $freedGB = [Math]::Round($freedMB / 1024, 2)
    $freedStr = if ($freedMB -ge 1024) { "$freedGB GB" } else { "$freedMB MB" }

    $title = if ($isAuto) { "Auto-Clean: $modeName" } else { "RAM Lifesaver: $modeName" }
    $msg = "Pembersihan selesai!`nRAM saat ini: $($after.Load)% ($($after.UsedGB) GB / $($after.TotalGB) GB)`nDihemat: $freedStr | Tersedia: $($after.AvailGB) GB"

    Show-Notification $title $msg [System.Windows.Forms.ToolTipIcon]::Info -force (-not $isAuto)
    Update-TrayTooltip
}

# Helper Menggambar Dynamic Tray Icon (Angka RAM & Indikator Warna)
$global:currentDynamicIcon = $null
$defaultStaticIcon = if (Test-Path $iconPath) { New-Object System.Drawing.Icon($iconPath) } else { [System.Drawing.SystemIcons]::Application }

function Update-DynamicIcon([int]$load) {
    if (-not $global:config.ShowDynamicIcon) {
        $global:notifyIcon.Icon = $defaultStaticIcon
        if ($global:currentDynamicIcon) {
            $global:currentDynamicIcon.Dispose()
            $global:currentDynamicIcon = $null
        }
        return
    }

    try {
        $bmp = New-Object System.Drawing.Bitmap(32, 32)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        # Warna Ring berdasarkan Beban RAM:
        # < 70% : Hijau Emerald (#22C55E)
        # 70% - 84% : Kuning Amber (#F59E0B)
        # >= 85% : Merah Crimson (#EF4444)
        $ringColor = if ($load -lt 70) {
            [System.Drawing.Color]::FromArgb(255, 34, 197, 94)
        } elseif ($load -lt 85) {
            [System.Drawing.Color]::FromArgb(255, 245, 158, 11)
        } else {
            [System.Drawing.Color]::FromArgb(255, 239, 68, 68)
        }

        # Background gelap (Slate Dark #0F172A)
        $brushBg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 15, 23, 42))
        $g.FillEllipse($brushBg, 1, 1, 29, 29)
        $brushBg.Dispose()

        # Lingkaran Indikator
        $pen = New-Object System.Drawing.Pen($ringColor, 2.5)
        $g.DrawEllipse($pen, 1, 1, 29, 29)
        $pen.Dispose()

        # Angka Persentase RAM
        $fontSize = if ($load -ge 100) { 8.5 } elseif ($load -ge 10) { 10.5 } else { 11.5 }
        $font = New-Object System.Drawing.Font("Segoe UI", $fontSize, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $brushText = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

        $g.DrawString("$load", $font, $brushText, 15.5, 15.5, $sf)

        $font.Dispose()
        $brushText.Dispose()
        $sf.Dispose()
        $g.Dispose()

        $hIcon = $bmp.GetHicon()
        $newIcon = [System.Drawing.Icon]::FromHandle($hIcon).Clone()
        [Win32RamMap]::DestroyIcon($hIcon) | Out-Null
        $bmp.Dispose()

        $oldIcon = $global:currentDynamicIcon
        $global:notifyIcon.Icon = $newIcon
        $global:currentDynamicIcon = $newIcon

        if ($oldIcon) {
            $oldIcon.Dispose()
        }
    } catch {
        $global:notifyIcon.Icon = $defaultStaticIcon
    }
}

function Update-TrayTooltip([bool]$isGameActive = $false) {
    $stats = Get-RAMStats
    $gameTag = if ($isGameActive) { " [🎮 Game Mode]" } else { "" }
    $txt = "RAM Lifesaver: $($stats.Load)% ($($stats.UsedGB)/$($stats.TotalGB) GB)$gameTag"
    if ($txt.Length -gt 63) {
        $txt = "RAM: $($stats.Load)% ($($stats.UsedGB)/$($stats.TotalGB) GB)$gameTag"
    }
    $global:notifyIcon.Text = $txt
    $global:menuHeader.Text = "Status RAM: $($stats.Load)% ($($stats.UsedGB) GB / $($stats.TotalGB) GB)$gameTag"
    Update-DynamicIcon $stats.Load
}

# Inisialisasi NotifyIcon (System Tray)
$global:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$global:notifyIcon.Icon = $defaultStaticIcon
$global:notifyIcon.Visible = $true

# Context Menu Utama
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# 1. Header Info
$global:menuHeader = New-Object System.Windows.Forms.ToolStripMenuItem
$global:menuHeader.Enabled = $false
$global:menuHeader.Font = New-Object System.Drawing.Font($global:menuHeader.Font, [System.Drawing.FontStyle]::Bold)
$contextMenu.Items.Add($global:menuHeader) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 2. Tombol Utama: Super Purge (5-in-1)
$menuSuperPurge = New-Object System.Windows.Forms.ToolStripMenuItem("🚀 Bersihkan Total (Super Purge 5-in-1)")
$menuSuperPurge.Font = New-Object System.Drawing.Font($menuSuperPurge.Font, [System.Drawing.FontStyle]::Bold)
$menuSuperPurge.Add_Click({
    Invoke-FullPurge -modeName "Super Purge (5-in-1)"
})
$contextMenu.Items.Add($menuSuperPurge) | Out-Null

# 3. Tombol Optimasi Khusus Browser
$menuBrowserClean = New-Object System.Windows.Forms.ToolStripMenuItem("🌐 Bersihkan RAM Browser Saja")
$menuBrowserClean.ToolTipText = "Pangkas RAM browser (Brave, Chrome, Edge, Firefox, dll) tanpa menyentuh aplikasi lain"
$menuBrowserClean.Add_Click({
    Clean-BrowserWorkingSets
})
$contextMenu.Items.Add($menuBrowserClean) | Out-Null

# 4. Submenu Top 5 Pemakan RAM (Dinamis saat menu dibuka)
$global:menuTop5 = New-Object System.Windows.Forms.ToolStripMenuItem("📊 Top 5 Pemakan RAM")
$contextMenu.Items.Add($global:menuTop5) | Out-Null

# 5. Submenu 5 Mode Spesifik RAMMap
$menuModes = New-Object System.Windows.Forms.ToolStripMenuItem("📋 Pilih Mode RAMMap Khusus")

$mode1 = New-Object System.Windows.Forms.ToolStripMenuItem("1. Empty Working Sets (Aplikasi User)")
$mode1.Add_Click({ Invoke-FullPurge -modeName "Empty Working Sets" -actionBlock { Clean-WorkingSets } })
$menuModes.DropDownItems.Add($mode1) | Out-Null

$mode2 = New-Object System.Windows.Forms.ToolStripMenuItem("2. Empty System Working Set (Kernel/Driver)")
$mode2.Add_Click({ Invoke-FullPurge -modeName "Empty System Working Set" -actionBlock { Clean-SystemWorkingSet } })
$menuModes.DropDownItems.Add($mode2) | Out-Null

$mode3 = New-Object System.Windows.Forms.ToolStripMenuItem("3. Empty Modified Page List (Flush ke SSD)")
$mode3.Add_Click({ Invoke-FullPurge -modeName "Empty Modified Page List" -actionBlock { Clean-ModifiedPageList } })
$menuModes.DropDownItems.Add($mode3) | Out-Null

$mode4 = New-Object System.Windows.Forms.ToolStripMenuItem("4. Empty Standby List (Kosongkan Cache File)")
$mode4.Add_Click({ Invoke-FullPurge -modeName "Empty Standby List" -actionBlock { Clean-StandbyList } })
$menuModes.DropDownItems.Add($mode4) | Out-Null

$mode5 = New-Object System.Windows.Forms.ToolStripMenuItem("5. Empty Priority 0 Standby (Cache Sampah)")
$mode5.Add_Click({ Invoke-FullPurge -modeName "Empty Priority 0 Standby" -actionBlock { Clean-Priority0StandbyList } })
$menuModes.DropDownItems.Add($mode5) | Out-Null

$contextMenu.Items.Add($menuModes) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 6. Submenu Pengaturan & Otomasi
$menuSettings = New-Object System.Windows.Forms.ToolStripMenuItem("⚙️ Pengaturan && Otomasi")

# 6a. Toggle Auto-Clean
$global:menuAutoClean = New-Object System.Windows.Forms.ToolStripMenuItem("⚡ Auto-Clean Otomatis")
$global:menuAutoClean.Checked = $global:config.AutoClean
$global:menuAutoClean.Add_Click({
    $global:config.AutoClean = -not $global:config.AutoClean
    $global:menuAutoClean.Checked = $global:config.AutoClean
    Save-Config
    $stateStr = if ($global:config.AutoClean) { "Aktif" } else { "Nonaktif" }
    Show-Notification "Auto-Clean" "Mode pembersihan otomatis sekarang: $stateStr" [System.Windows.Forms.ToolTipIcon]::Info -force $true
})
$menuSettings.DropDownItems.Add($global:menuAutoClean) | Out-Null

# 6b. Ambang Batas Submenu
$menuThreshold = New-Object System.Windows.Forms.ToolStripMenuItem("🎯 Ambang Batas Otomatis")
$thresholds = @(70, 75, 80, 85, 90)

foreach ($t in $thresholds) {
    $tText = "Saat RAM di atas $t%"
    $tItem = New-Object System.Windows.Forms.ToolStripMenuItem($tText)
    $tItem.Checked = ($global:config.Threshold -eq $t)
    $tVal = $t
    
    $tItem.Add_Click({
        $global:config.Threshold = $tVal
        foreach ($sub in $menuThreshold.DropDownItems) { $sub.Checked = $false }
        $this.Checked = $true
        Save-Config
        Show-Notification "Pengaturan Disimpan" "Auto-clean aktif saat RAM di atas $tVal%" [System.Windows.Forms.ToolTipIcon]::Info -force $true
    }.GetNewClosure())
    
    $menuThreshold.DropDownItems.Add($tItem) | Out-Null
}
$menuSettings.DropDownItems.Add($menuThreshold) | Out-Null

$menuSettings.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 6c. Dynamic Icon Toggle
$menuDynamicIcon = New-Object System.Windows.Forms.ToolStripMenuItem("🎨 Ikon Tray Dinamis (Angka RAM %)")
$menuDynamicIcon.Checked = $global:config.ShowDynamicIcon
$menuDynamicIcon.Add_Click({
    $global:config.ShowDynamicIcon = -not $global:config.ShowDynamicIcon
    $menuDynamicIcon.Checked = $global:config.ShowDynamicIcon
    Save-Config
    Update-TrayTooltip
})
$menuSettings.DropDownItems.Add($menuDynamicIcon) | Out-Null

# 6d. Smart Game Mode Toggle
$menuGameMode = New-Object System.Windows.Forms.ToolStripMenuItem("🎮 Smart Game Mode (Jeda saat Fullscreen)")
$menuGameMode.Checked = $global:config.SmartGameMode
$menuGameMode.Add_Click({
    $global:config.SmartGameMode = -not $global:config.SmartGameMode
    $menuGameMode.Checked = $global:config.SmartGameMode
    Save-Config
    $st = if ($global:config.SmartGameMode) { "Aktif" } else { "Nonaktif" }
    Show-Notification "Smart Game Mode" "Deteksi game & fullscreen sekarang: $st" [System.Windows.Forms.ToolTipIcon]::Info -force $true
})
$menuSettings.DropDownItems.Add($menuGameMode) | Out-Null

# 6e. Silent Mode Toggle
$menuSilent = New-Object System.Windows.Forms.ToolStripMenuItem("🔕 Mode Senyap (Tanpa Notifikasi Pop-up)")
$menuSilent.Checked = $global:config.SilentMode
$menuSilent.Add_Click({
    $global:config.SilentMode = -not $global:config.SilentMode
    $menuSilent.Checked = $global:config.SilentMode
    Save-Config
    $st = if ($global:config.SilentMode) { "Aktif (Notifikasi dinonaktifkan)" } else { "Nonaktif (Notifikasi aktif)" }
    Show-Notification "Mode Senyap" "Status mode senyap: $st" [System.Windows.Forms.ToolTipIcon]::Info -force $true
})
$menuSettings.DropDownItems.Add($menuSilent) | Out-Null

# 6f. Run on Windows Startup Toggle
$global:menuStartup = New-Object System.Windows.Forms.ToolStripMenuItem("🚀 Jalankan saat Windows Menyala (Startup)")
$global:menuStartup.Checked = Test-StartupEnabled
$global:menuStartup.Add_Click({
    $newState = -not $global:menuStartup.Checked
    Set-StartupState $newState
    $global:menuStartup.Checked = Test-StartupEnabled
})
$menuSettings.DropDownItems.Add($global:menuStartup) | Out-Null

$menuSettings.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 6g. Buka Whitelist config.json
$menuEditWhitelist = New-Object System.Windows.Forms.ToolStripMenuItem("🛡️ Buka && Edit Whitelist (config.json)")
$menuEditWhitelist.Add_Click({
    Start-Process notepad.exe $configFile
})
$menuSettings.DropDownItems.Add($menuEditWhitelist) | Out-Null

$contextMenu.Items.Add($menuSettings) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 7. Buka Folder Aplikasi
$menuOpenFolder = New-Object System.Windows.Forms.ToolStripMenuItem("📁 Buka Folder Aplikasi")
$menuOpenFolder.Add_Click({
    explorer.exe $scriptDir
})
$contextMenu.Items.Add($menuOpenFolder) | Out-Null

# 8. Keluar
$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem("❌ Keluar")
$menuExit.Add_Click({
    $global:timer.Stop()
    $global:notifyIcon.Visible = $false
    $global:notifyIcon.Dispose()
    if ($global:currentDynamicIcon) { $global:currentDynamicIcon.Dispose() }
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.Items.Add($menuExit) | Out-Null

# Event Refresh Dinamis saat Context Menu Dibuka
$contextMenu.Add_Opening({
    # 1. Update Tooltip & Header
    $isGame = if ($global:config.SmartGameMode) { Test-IsGameOrFullscreenActive } else { $false }
    Update-TrayTooltip $isGame

    # 2. Update Top 5 RAM Hogs Submenu
    $global:menuTop5.DropDownItems.Clear()

    $allWhitelist = $systemWhitelist + $global:config.CustomWhitelist

    $topProcs = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -gt 4 -and ($allWhitelist -notcontains $_.ProcessName) -and $_.WorkingSet64 -gt 10MB } |
        Group-Object ProcessName |
        Select-Object Name, @{Name='TotalWS'; Expression={ ($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum }} |
        Sort-Object TotalWS -Descending |
        Select-Object -First 5

    if ($topProcs -and $topProcs.Count -gt 0) {
        foreach ($item in $topProcs) {
            $pName = $item.Name
            $wsMB = [Math]::Round($item.TotalWS / 1MB, 0)
            $wsGB = [Math]::Round($wsMB / 1024, 2)
            $wsStr = if ($wsMB -ge 1024) { "$wsGB GB" } else { "$wsMB MB" }
            
            $subItem = New-Object System.Windows.Forms.ToolStripMenuItem("🔹 $pName ($wsStr)")
            $subItem.ToolTipText = "Klik untuk memangkas memori proses '$pName'"
            $subItem.Add_Click({
                Clean-ProcessByName $pName
            }.GetNewClosure())

            $global:menuTop5.DropDownItems.Add($subItem) | Out-Null
        }

        $global:menuTop5.DropDownItems.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null
        $itemTrimAll = New-Object System.Windows.Forms.ToolStripMenuItem("🧹 Pangkas Semua Top 5 di Atas")
        $itemTrimAll.Font = New-Object System.Drawing.Font($itemTrimAll.Font, [System.Drawing.FontStyle]::Bold)
        $itemTrimAll.Add_Click({
            foreach ($tp in $topProcs) {
                Clean-ProcessByName $tp.Name
            }
        }.GetNewClosure())
        $global:menuTop5.DropDownItems.Add($itemTrimAll) | Out-Null
    } else {
        $emptyItem = New-Object System.Windows.Forms.ToolStripMenuItem("(Tidak ada proses besar aktif)")
        $emptyItem.Enabled = $false
        $global:menuTop5.DropDownItems.Add($emptyItem) | Out-Null
    }

    # 3. Update Status Startup di Menu
    $global:menuStartup.Checked = Test-StartupEnabled
})

$global:notifyIcon.ContextMenuStrip = $contextMenu

# Event Double Click pada Tray Icon untuk Super Purge
$global:notifyIcon.Add_DoubleClick({
    Invoke-FullPurge -modeName "Super Purge (5-in-1)"
})

# Timer Background Monitor
$global:timer = New-Object System.Windows.Forms.Timer
$global:timer.Interval = ($global:config.CheckInterval * 1000)
$global:timer.Add_Tick({
    $isGameActive = if ($global:config.SmartGameMode) { Test-IsGameOrFullscreenActive } else { $false }
    Update-TrayTooltip $isGameActive

    if ($global:config.AutoClean) {
        $stats = Get-RAMStats
        $now = [DateTime]::Now
        $cooldownPassed = ($now - $global:config.LastAutoClean).TotalMinutes -ge $global:config.AutoCleanCooldownMinutes

        if ($stats.Load -ge $global:config.Threshold -and $cooldownPassed) {
            if ($isGameActive) {
                # Saat sedang main game, hindari memangkas working set agar tidak stutter.
                # Cukup kosongkan cache Standby List yang aman tanpa drop FPS.
                $global:config.LastAutoClean = $now
                Invoke-FullPurge -modeName "Standby Cache (Game Safe)" -actionBlock { Clean-StandbyList } -isAuto $true
            } else {
                $global:config.LastAutoClean = $now
                Invoke-FullPurge -modeName "Super Purge (Auto)" -isAuto $true
            }
        }
    }
})

Update-TrayTooltip
$global:timer.Start()

# Notifikasi awal saat startup
Show-Notification "Windows RAM Lifesaver (5-in-1 RAMMap)" "Aplikasi aktif di System Tray dengan hak Administrator penuh!" [System.Windows.Forms.ToolTipIcon]::Info -force $true

# Jalankan Message Loop Windows Forms
[System.Windows.Forms.Application]::Run()
