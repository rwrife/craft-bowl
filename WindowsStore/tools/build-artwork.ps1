param(
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$output = Join-Path $RepositoryRoot 'WindowsStore'
$icons = Join-Path $output 'icons'
New-Item -ItemType Directory -Path $icons -Force | Out-Null
$source = [System.Drawing.Image]::FromFile(
    (Join-Path $RepositoryRoot 'App\Assets.xcassets\AppIcon.appiconset\AppIcon.png')
)

function New-Canvas([int]$Width, [int]$Height) {
    return [System.Drawing.Bitmap]::new(
        $Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb
    )
}

function New-Graphics([System.Drawing.Bitmap]$Bitmap) {
    $graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return $graphics
}

try {
    foreach ($size in @(300, 150, 71)) {
        $bitmap = New-Canvas $size $size
        $graphics = New-Graphics $bitmap
        try {
            $graphics.DrawImage($source, 0, 0, $size, $size)
            $bitmap.Save(
                (Join-Path $icons "Square${size}x${size}Logo.png"),
                [System.Drawing.Imaging.ImageFormat]::Png
            )
        }
        finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }
    }

    $wallpaper = New-Canvas 1920 1080
    $graphics = New-Graphics $wallpaper
    $background = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Rectangle]::new(0, 0, 1920, 1080),
        [System.Drawing.Color]::FromArgb(7, 17, 35),
        [System.Drawing.Color]::FromArgb(17, 55, 49),
        35.0
    )
    $fieldPen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(25, 255, 255, 255), 2)
    $gold = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 204, 52))
    $white = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(236, 242, 248))
    $shadow = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(3, 10, 23))
    $titleFont = [System.Drawing.Font]::new('Arial', 116, [System.Drawing.FontStyle]::Bold,
        [System.Drawing.GraphicsUnit]::Pixel)
    $subtitleFont = [System.Drawing.Font]::new('Arial', 25, [System.Drawing.FontStyle]::Bold,
        [System.Drawing.GraphicsUnit]::Pixel)
    try {
        $graphics.FillRectangle($background, 0, 0, 1920, 1080)
        for ($x = -600; $x -lt 2400; $x += 220) {
            $graphics.DrawLine($fieldPen, $x, 1080, ($x + 620), 0)
        }
        $graphics.FillRectangle($shadow, 936, 112, 864, 864)
        $graphics.DrawImage($source, 960, 88, 864, 864)
        $graphics.FillRectangle($gold, 112, 684, 96, 8)
        $graphics.DrawString('BLOCK', $titleFont, $white, 104, 712)
        $graphics.DrawString('BOWL', $titleFont, $gold, 104, 824)
        $graphics.DrawString('CALL THE PLAY. TAKE THE FIELD.', $subtitleFont, $white, 112, 982)
        $wallpaper.Save(
            (Join-Path $output 'wallpaper-1920x1080.png'),
            [System.Drawing.Imaging.ImageFormat]::Png
        )
    }
    finally {
        $titleFont.Dispose()
        $subtitleFont.Dispose()
        $background.Dispose()
        $fieldPen.Dispose()
        $gold.Dispose()
        $white.Dispose()
        $shadow.Dispose()
        $graphics.Dispose()
        $wallpaper.Dispose()
    }
}
finally {
    $source.Dispose()
}
