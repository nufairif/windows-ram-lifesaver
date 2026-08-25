Add-Type -AssemblyName System.Drawing

$outDir = "D:\1-dev\dev-miid\optimasi browser\windows-ram-lifesaver"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$icoPath = Join-Path $outDir "app.ico"
$size = 64
$bmp = New-Object System.Drawing.Bitmap $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

# Background circle with gradient
$rect = New-Object System.Drawing.Rectangle 2, 2, ($size - 4), ($size - 4)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    [System.Drawing.Color]::FromArgb(255, 255, 94, 58),
    [System.Drawing.Color]::FromArgb(255, 255, 42, 84),
    45.0
)
$g.FillEllipse($brush, $rect)

# Draw Lightning bolt
$p1 = New-Object System.Drawing.PointF ($size * 0.55), ($size * 0.18)
$p2 = New-Object System.Drawing.PointF ($size * 0.35), ($size * 0.52)
$p3 = New-Object System.Drawing.PointF ($size * 0.52), ($size * 0.52)
$p4 = New-Object System.Drawing.PointF ($size * 0.42), ($size * 0.82)
$p5 = New-Object System.Drawing.PointF ($size * 0.68), ($size * 0.46)
$p6 = New-Object System.Drawing.PointF ($size * 0.50), ($size * 0.46)

$points = [System.Drawing.PointF[]]@($p1, $p2, $p3, $p4, $p5, $p6)
$fillBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$g.FillPolygon($fillBrush, $points)

$hIcon = $bmp.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($hIcon)

$fs = New-Object System.IO.FileStream($icoPath, [System.IO.FileMode]::Create)
$icon.Save($fs)
$fs.Close()

$g.Dispose()
$bmp.Dispose()

Write-Host "Generated Tray Icon: $icoPath"
