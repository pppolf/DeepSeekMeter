# 生成 Windows 应用图标 app.ico（无第三方依赖，仅用 .NET System.Drawing）
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File Scripts/make-windows-icon.ps1
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$Output = Join-Path (Split-Path -Parent $PSScriptRoot) "windows\src\DeepSeekMeter\app.ico"
$size = 256

$bmp = New-Object System.Drawing.Bitmap -ArgumentList $size, $size
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
$g.Clear([System.Drawing.Color]::Transparent)

# 圆角方块背景（DeepSeek 蓝 #4D6BFE）
$blue = [System.Drawing.Color]::FromArgb(77, 107, 254)
$bgBrush = New-Object System.Drawing.SolidBrush -ArgumentList $blue
$d = 10
$rect = New-Object System.Drawing.Rectangle -ArgumentList $d, $d, ($size - 2 * $d), ($size - 2 * $d)
$r = 56
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc($rect.X, $rect.Y, $r, $r, 180, 90)
$path.AddArc(($rect.Right - $r), $rect.Y, $r, $r, 270, 90)
$path.AddArc(($rect.Right - $r), ($rect.Bottom - $r), $r, $r, 0, 90)
$path.AddArc($rect.X, ($rect.Bottom - $r), $r, $r, 90, 90)
$path.CloseFigure()
$g.FillPath($bgBrush, $path)

# 白色「DS」文字
$white = New-Object System.Drawing.SolidBrush -ArgumentList ([System.Drawing.Color]::White)
$font = New-Object System.Drawing.Font -ArgumentList "Segoe UI", ([float]($size * 0.40)), ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$g.DrawString("DS", $font, $white, $rect, $fmt)

$g.Dispose()

# 保存 PNG 后构造 ICO（内嵌 PNG，Windows 会按需缩放）
$pngPath = [System.IO.Path]::GetTempFileName() + ".png"
$bmp.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$pngBytes = [System.IO.File]::ReadAllBytes($pngPath)
[System.IO.File]::Delete($pngPath)

$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter -ArgumentList $ms
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]1)
$bw.Write([Byte]0)
$bw.Write([Byte]0)
$bw.Write([Byte]0)
$bw.Write([Byte]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]32)
$bw.Write([UInt32]$pngBytes.Length)
$bw.Write([UInt32]22)
$bw.Write($pngBytes)
$bw.Flush()
[System.IO.File]::WriteAllBytes($Output, $ms.ToArray())
$bw.Dispose()

Write-Host "已生成图标：$Output"
