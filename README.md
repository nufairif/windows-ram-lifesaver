# ⚡ Windows RAM Lifesaver (5-in-1 RAMMap System Tray Optimizer)

**Windows RAM Lifesaver** adalah utilitas native Windows yang berjalan di **System Tray** dengan 5 mode pembersihan memori lengkap setara **Microsoft Sysinternals RAMMap** menggunakan NT Native API (`NtSetSystemInformation`).

---

## 🌟 Fitur Utama & Mode Pembersihan

### 1. 🧹 5 Mode Pembersihan RAMMap (NT Native API)
1. **🧹 Empty Working Sets:** Memangkas alokasi RAM fisik milik aplikasi user (Brave, Discord, Spotify, Game, dll).
2. **🖥️ Empty System Working Set:** Menyegarkan dan memangkas memori kerja Kernel & Driver Windows.
3. **💾 Empty Modified Page List:** Memaksa penulisan data tertunda (*dirty cache*) langsung ke SSD/HDD.
4. **⚡ Empty Standby List:** Mengosongkan seluruh kolom **"Cached"** di Task Manager ke ~0 MB (RAM menjadi murni *Free*).
5. **🎯 Empty Priority 0 Standby:** Hanya menghapus cache file berprioritas paling rendah tanpa membuang cache penting.
6. **🚀 Super Purge (5-in-1):** Menjalankan seluruh mode pembersihan secara berurutan dalam sekali klik!

### 2. 🌐 Optimasi Khusus Browser (Targeted Clean)
- **Bersihkan RAM Browser Saja:** Memangkas memori khusus proses browser (Brave, Chrome, Edge, Firefox, Opera, Vivaldi, Arc, Zen, dll.) tanpa menyentuh aplikasi kerja lainnya.

### 3. 📊 Top 5 Pemakan RAM (Quick Trim)
- Menampilkan daftar 5 proses dengan konsumsi RAM terbesar saat ini di menu klik kanan.
- Anda dapat mengklik proses tertentu untuk memangkas memori proses tersebut secara spesifik atau memilih *"Pangkas Semua Top 5"*.

### 4. 🎨 Ikon Tray Dinamis (Real-time RAM %)
- Ikon di taskbar/system tray menampilkan angka beban persentase RAM secara real-time dengan kode warna:
  - 🟢 **Hijau (< 70%):** RAM lega dan aman.
  - 🟡 **Kuning (70% – 84%):** Penggunaan RAM sedang meningkat.
  - 🔴 **Merah (≥ 85%):** RAM mendekati penuh / kritis.

### 5. 🎮 Smart Game Mode (Deteksi Fullscreen)
- Otomatis mendeteksi saat Anda sedang bermain game layar penuh (*D3D Fullscreen*) atau presentasi:
  - Auto-clean akan beralih ke mode aman (*Standby Cache purge*) tanpa memangkas *working set* game, sehingga terhindar dari *micro-stutter* atau drop FPS.

### 6. ⚙️ Otomasi & Konfigurasi Persisten (`config.json`)
- **Auto-Clean Otomatis:** Membersihkan RAM otomatis saat beban mencapai ambang batas (*70%, 75%, 80%, 85%, 90%*).
- **🔕 Mode Senyap (Silent Mode):** Opsi mematikan balon notifikasi popup agar bekerja hening di latar belakang.
- **🚀 Run on Windows Startup:** Integrasi dengan Windows Task Scheduler untuk otomatis aktif saat komputer menyala dengan hak Administrator penuh tanpa prompt UAC berulang.
- **🛡️ Custom Whitelist:** Daftar pengecualian di `config.json` agar aplikasi penting (misal: *OBS, VS Code, Docker, Premiere*) tidak terganggu pembersihan.

---

## 🎮 Cara Menjalankan & Menggunakan

### Menjalankan Aplikasi:
- Klik ganda **`Run_RAM_Lifesaver.vbs`** atau **`Run_RAM_Lifesaver.bat`**.
- Aplikasi akan otomatis meminta izin Administrator (UAC) jika belum elevated, lalu menetap di **System Tray** (dekat jam Windows).

### Menggunakan Pintasan Tray:
- **⚡ Klik 2x pada ikon tray:** Menjalankan **Super Purge (5-in-1)** seketika.
- **🖱️ Klik Kanan pada ikon tray:**
  - Lihat status RAM real-time di header.
  - Jalankan pembersihan cepat (Super Purge, Browser Clean, atau Top 5 RAM).
  - Kelola pengaturan otomatisasi, ambang batas, mode hening, ikon dinamis, dan auto-start saat boot.

### Menghentikan Aplikasi:
- Klik kanan ikon di system tray > Pilih **"❌ Keluar"**, atau jalankan **`Stop_RAM_Lifesaver.bat`**.
