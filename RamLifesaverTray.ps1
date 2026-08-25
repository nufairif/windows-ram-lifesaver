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

# Win32 & Native NT API (Setara Penuh 5 Fitur RAMMap Microsoft)
$win32Code = @"
using System;
using System.Runtime.InteropServices;

public enum SYSTEM_MEMORY_LIST_COMMAND {
    MemoryCaptureAccessedBits = 0,
    MemoryEmptyWorkingSets = 1,
    MemoryEmptySystemWorkingSet = 2,
    MemoryFlushModifiedList = 3,
    MemoryPurgeStandbyList = 4,
    MemoryPurgeLowPriorityStandbyList = 5
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

# Whitelist Proses Kritis Windows
$systemWhitelist = @(
    'System', 'Idle', 'Registry', 'smss', 'csrss', 'wininit', 'services', 
    'lsass', 'winlogon', 'dwm', 'fontdrvhost', 'spoolsv', 'Memory Compression',
    'Secure System', 'ntoskrnl'
)

$global:config = @{
    AutoClean = $true
    Threshold = 80
    CheckInterval = 30
    LastAutoClean = [DateTime]::MinValue
    AutoCleanCooldownMinutes = 3
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

# 5 Fungsi Khusus Sesuai Fitur RAMMap (Dengan Native Privilege)
function Clean-WorkingSets {
    # 1. Empty Working Sets (Aplikasi User & Sistem)
    $processes = Get-Process -ErrorAction SilentlyContinue
    foreach ($proc in $processes) {
        if ($systemWhitelist -contains $proc.ProcessName -or $proc.Id -le 4) { continue }
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

function Invoke-FullPurge([string]$modeName = "Super Purge (5-in-1)", [scriptblock]$actionBlock = $null, [bool]$isAuto = $false) {
    $before = Get-RAMStats

    if ($actionBlock) {
        & $actionBlock
    } else {
        # Super Purge: Jalankan ke-5 mode secara berurutan
        Clean-ModifiedPageList
        Clean-WorkingSets
        Clean-SystemWorkingSet
        Clean-StandbyList
    }

    Start-Sleep -Milliseconds 300
    $after = Get-RAMStats
    $freedBytes = $after.AvailBytes - $before.AvailBytes
    $freedMB = [Math]::Max(0, [Math]::Round($freedBytes / 1MB, 0))
    $freedGB = [Math]::Round($freedMB / 1024, 2)

    $title = if ($isAuto) { "Auto-Clean: $modeName" } else { "RAM Lifesaver: $modeName" }
    $msg = "Pembersihan selesai!`nRAM saat ini: $($after.Load)% ($($after.UsedGB) GB / $($after.TotalGB) GB)`nTersedia: $($after.AvailGB) GB"

    $global:notifyIcon.BalloonTipTitle = $title
    $global:notifyIcon.BalloonTipText = $msg
    $global:notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
    $global:notifyIcon.ShowBalloonTip(3000)

    Update-TrayTooltip
}

function Update-TrayTooltip {
    $stats = Get-RAMStats
    $txt = "RAM Lifesaver: $($stats.Load)% ($($stats.UsedGB)/$($stats.TotalGB) GB)"
    if ($txt.Length -gt 63) {
        $txt = "RAM: $($stats.Load)% ($($stats.UsedGB)/$($stats.TotalGB) GB)"
    }
    $global:notifyIcon.Text = $txt
    $global:menuHeader.Text = "Status RAM: $($stats.Load)% ($($stats.UsedGB) GB / $($stats.TotalGB) GB)"
}

# Inisialisasi NotifyIcon (System Tray)
$global:notifyIcon = New-Object System.Windows.Forms.NotifyIcon

if (Test-Path $iconPath) {
    $global:notifyIcon.Icon = New-Object System.Drawing.Icon($iconPath)
} else {
    $global:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}

$global:notifyIcon.Visible = $true

# Context Menu
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

# 1. Header Info
$global:menuHeader = New-Object System.Windows.Forms.ToolStripMenuItem
$global:menuHeader.Enabled = $false
$global:menuHeader.Font = New-Object System.Drawing.Font($global:menuHeader.Font, [System.Drawing.FontStyle]::Bold)
$contextMenu.Items.Add($global:menuHeader) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 2. Tombol Utama: Super Purge (5-in-1)
$menuSuperPurge = New-Object System.Windows.Forms.ToolStripMenuItem("Bersihkan Total (Super Purge 5-in-1)")
$menuSuperPurge.Font = New-Object System.Drawing.Font($menuSuperPurge.Font, [System.Drawing.FontStyle]::Bold)
$menuSuperPurge.Add_Click({
    Invoke-FullPurge -modeName "Super Purge (5-in-1)"
})
$contextMenu.Items.Add($menuSuperPurge) | Out-Null

# 3. Submenu 5 Mode Spesifik RAMMap
$menuModes = New-Object System.Windows.Forms.ToolStripMenuItem("Pilih Mode RAMMap Khusus")

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

# 4. Toggle Auto-Clean
$global:menuAutoClean = New-Object System.Windows.Forms.ToolStripMenuItem("Auto-Clean Otomatis")
$global:menuAutoClean.Checked = $global:config.AutoClean
$global:menuAutoClean.Add_Click({
    $global:config.AutoClean = -not $global:config.AutoClean
    $global:menuAutoClean.Checked = $global:config.AutoClean
    $stateStr = if ($global:config.AutoClean) { "Aktif" } else { "Nonaktif" }
    $global:notifyIcon.ShowBalloonTip(2000, "Auto-Clean", "Mode pembersihan otomatis sekarang: $stateStr", [System.Windows.Forms.ToolTipIcon]::Info)
})
$contextMenu.Items.Add($global:menuAutoClean) | Out-Null

# 5. Ambang Batas Submenu
$menuThreshold = New-Object System.Windows.Forms.ToolStripMenuItem("Ambang Batas Otomatis")
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
        $global:notifyIcon.ShowBalloonTip(2000, "Pengaturan Disimpan", "Auto-clean aktif saat RAM di atas $tVal%", [System.Windows.Forms.ToolTipIcon]::Info)
    }.GetNewClosure())
    
    $menuThreshold.DropDownItems.Add($tItem) | Out-Null
}
$contextMenu.Items.Add($menuThreshold) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

# 6. Buka Folder
$menuOpenFolder = New-Object System.Windows.Forms.ToolStripMenuItem("Buka Folder Aplikasi")
$menuOpenFolder.Add_Click({
    explorer.exe $scriptDir
})
$contextMenu.Items.Add($menuOpenFolder) | Out-Null

# 7. Keluar
$menuExit = New-Object System.Windows.Forms.ToolStripMenuItem("Keluar")
$menuExit.Add_Click({
    $global:timer.Stop()
    $global:notifyIcon.Visible = $false
    $global:notifyIcon.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$contextMenu.Items.Add($menuExit) | Out-Null

$global:notifyIcon.ContextMenuStrip = $contextMenu

# Event Double Click pada Tray Icon untuk Super Purge
$global:notifyIcon.Add_DoubleClick({
    Invoke-FullPurge -modeName "Super Purge (5-in-1)"
})

# Timer Background Monitor
$global:timer = New-Object System.Windows.Forms.Timer
$global:timer.Interval = ($global:config.CheckInterval * 1000)
$global:timer.Add_Tick({
    Update-TrayTooltip

    if ($global:config.AutoClean) {
        $stats = Get-RAMStats
        $now = [DateTime]::Now
        $cooldownPassed = ($now - $global:config.LastAutoClean).TotalMinutes -ge $global:config.AutoCleanCooldownMinutes

        if ($stats.Load -ge $global:config.Threshold -and $cooldownPassed) {
            $global:config.LastAutoClean = $now
            Invoke-FullPurge -modeName "Super Purge (Auto)" -isAuto $true
        }
    }
})

Update-TrayTooltip
$global:timer.Start()

# Notifikasi awal saat berjalan
$global:notifyIcon.BalloonTipTitle = "Windows RAM Lifesaver (5-in-1 RAMMap)"
$global:notifyIcon.BalloonTipText = "Aplikasi aktif di System Tray dengan hak Administrator penuh!"
$global:notifyIcon.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
$global:notifyIcon.ShowBalloonTip(3000)

# Jalankan Message Loop Windows Forms
[System.Windows.Forms.Application]::Run()
