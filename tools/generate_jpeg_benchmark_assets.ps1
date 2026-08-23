param(
    [string]$OutputPath = "src/p4_jpeg_benchmark_assets.cpp",
    [string]$AssetDirectory = "test/fixtures/zshow_frames"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$width = 800
$height = 800
$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
    Where-Object { $_.MimeType -eq "image/jpeg" }
if ($null -eq $jpegCodec) {
    throw "System.Drawing JPEG encoder is unavailable"
}

function Save-JpegBytes {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [long]$Quality
    )

    $qualityEncoder = [System.Drawing.Imaging.Encoder]::Quality
    $parameters = [System.Drawing.Imaging.EncoderParameters]::new(1)
    $parameters.Param[0] = [System.Drawing.Imaging.EncoderParameter]::new(
        $qualityEncoder, $Quality)
    $stream = [System.IO.MemoryStream]::new()
    try {
        $Bitmap.Save($stream, $jpegCodec, $parameters)
        return $stream.ToArray()
    }
    finally {
        $stream.Dispose()
        $parameters.Dispose()
    }
}

function New-GraphicFrame {
    param([int]$Phase)

    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::FromArgb(7, 10, 18))
        $accent = if ($Phase -eq 0) {
            [System.Drawing.Color]::FromArgb(0, 190, 255)
        } else {
            [System.Drawing.Color]::FromArgb(255, 54, 126)
        }
        $ringPen = [System.Drawing.Pen]::new($accent, 34)
        $thinPen = [System.Drawing.Pen]::new(
            [System.Drawing.Color]::FromArgb(130, $accent), 4)
        $brush = [System.Drawing.SolidBrush]::new($accent)
        try {
            $offset = $Phase * 34
            $graphics.DrawEllipse($ringPen, 92 + $offset, 92, 616, 616)
            $graphics.DrawEllipse($thinPen, 152, 152 + $offset, 496, 496)
            $graphics.FillEllipse($brush, 354 + $offset, 354, 92, 92)
            for ($i = 0; $i -lt 12; $i++) {
                $angle = ($i * 30 + $Phase * 15) * [Math]::PI / 180
                $x1 = 400 + [Math]::Cos($angle) * 250
                $y1 = 400 + [Math]::Sin($angle) * 250
                $x2 = 400 + [Math]::Cos($angle) * 305
                $y2 = 400 + [Math]::Sin($angle) * 305
                $graphics.DrawLine($thinPen, $x1, $y1, $x2, $y2)
            }
        }
        finally {
            $ringPen.Dispose()
            $thinPen.Dispose()
            $brush.Dispose()
        }
    }
    finally {
        $graphics.Dispose()
    }
    return $bitmap
}

function New-GradientFrame {
    param([int]$Phase)

    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rectangle = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
        $first = if ($Phase -eq 0) {
            [System.Drawing.Color]::FromArgb(8, 16, 45)
        } else {
            [System.Drawing.Color]::FromArgb(52, 4, 64)
        }
        $second = if ($Phase -eq 0) {
            [System.Drawing.Color]::FromArgb(255, 75, 115)
        } else {
            [System.Drawing.Color]::FromArgb(0, 210, 180)
        }
        $gradient = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
            $rectangle, $first, $second, 35 + $Phase * 70)
        try {
            $graphics.FillRectangle($gradient, $rectangle)
        }
        finally {
            $gradient.Dispose()
        }

        for ($i = 0; $i -lt 90; $i++) {
            $alpha = 30 + (($i * 19) % 90)
            $color = [System.Drawing.Color]::FromArgb(
                $alpha, (31 * $i + 70 * $Phase) % 256,
                (79 * $i + 30) % 256, (47 * $i + 180) % 256)
            $brush = [System.Drawing.SolidBrush]::new($color)
            try {
                $size = 18 + (($i * 37) % 150)
                $x = ($i * 83 + 43 * $Phase) % 780 - 40
                $y = ($i * 137 + 71 * $Phase) % 780 - 40
                $graphics.FillEllipse($brush, $x, $y, $size, $size)
            }
            finally {
                $brush.Dispose()
            }
        }
    }
    finally {
        $graphics.Dispose()
    }
    return $bitmap
}

function New-TextureFrame {
    param([int]$Phase)

    $bitmap = [System.Drawing.Bitmap]::new(
        $width, $height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $rectangle = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
    $data = $bitmap.LockBits(
        $rectangle, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
        [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    try {
        $bytes = [byte[]]::new($data.Stride * $height)
        [uint32]$state = 0x7a41c923 + [uint32]$Phase * 0x1020304
        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $state = [uint32](([uint64]1664525 * $state + 1013904223) -band 0xffffffffL)
                $noise = [int](($state -shr 24) -band 0xff)
                $wave = [int](38 * [Math]::Sin(($x + $Phase * 41) / 19.0) +
                    34 * [Math]::Cos(($y - $Phase * 29) / 23.0))
                $index = $y * $data.Stride + $x * 3
                $bytes[$index] = [byte][Math]::Max(
                    0, [Math]::Min(255, [int](70 + $noise / 2 + $wave)))
                $bytes[$index + 1] = [byte][Math]::Max(
                    0, [Math]::Min(255, [int](35 + $noise / 2 - $wave)))
                $bytes[$index + 2] = [byte][Math]::Max(
                    0, [Math]::Min(255, [int](100 + $noise / 2 + $wave / 2)))
            }
        }
        [System.Runtime.InteropServices.Marshal]::Copy(
            $bytes, 0, $data.Scan0, $bytes.Length)
    }
    finally {
        $bitmap.UnlockBits($data)
    }
    return $bitmap
}

$definitions = @(
    @{ Name = "graphic_a"; Class = "graphic"; Quality = 88; Factory = { New-GraphicFrame 0 } },
    @{ Name = "graphic_b"; Class = "graphic"; Quality = 88; Factory = { New-GraphicFrame 1 } },
    @{ Name = "gradient_a"; Class = "gradient"; Quality = 88; Factory = { New-GradientFrame 0 } },
    @{ Name = "gradient_b"; Class = "gradient"; Quality = 88; Factory = { New-GradientFrame 1 } },
    @{ Name = "texture_q35"; Class = "texture"; Quality = 35; Factory = { New-TextureFrame 2 } },
    @{ Name = "texture_q55"; Class = "texture"; Quality = 55; Factory = { New-TextureFrame 3 } },
    @{ Name = "texture_a"; Class = "texture"; Quality = 82; Factory = { New-TextureFrame 0 } },
    @{ Name = "texture_b"; Class = "texture"; Quality = 82; Factory = { New-TextureFrame 1 } }
)

$assets = @()
$absoluteAssetDirectory = [System.IO.Path]::GetFullPath($AssetDirectory)
[System.IO.Directory]::CreateDirectory($absoluteAssetDirectory) | Out-Null
foreach ($definition in $definitions) {
    $bitmap = & $definition.Factory
    try {
        $bytes = Save-JpegBytes $bitmap $definition.Quality
        $assets += [pscustomobject]@{
            Name = $definition.Name
            Class = $definition.Class
            Bytes = $bytes
        }
        [System.IO.File]::WriteAllBytes(
            [System.IO.Path]::Combine($absoluteAssetDirectory,
                "$($definition.Name).jpg"), $bytes)
        Write-Host ("{0}: {1:N0} bytes" -f $definition.Name, $bytes.Length)
    }
    finally {
        $bitmap.Dispose()
    }
}

$builder = [System.Text.StringBuilder]::new()
[void]$builder.AppendLine("// Generated by tools/generate_jpeg_benchmark_assets.ps1. Do not edit.")
[void]$builder.AppendLine('#include "p4_jpeg_benchmark_assets.h"')
[void]$builder.AppendLine()
[void]$builder.AppendLine("namespace p4jpegbenchmark {")
[void]$builder.AppendLine("namespace {")
foreach ($asset in $assets) {
    [void]$builder.AppendLine("alignas(16) const uint8_t k_$($asset.Name)[] = {")
    for ($offset = 0; $offset -lt $asset.Bytes.Length; $offset += 16) {
        $count = [Math]::Min(16, $asset.Bytes.Length - $offset)
        $values = for ($i = 0; $i -lt $count; $i++) {
            '0x{0:x2}' -f $asset.Bytes[$offset + $i]
        }
        [void]$builder.AppendLine("    $($values -join ', '),")
    }
    [void]$builder.AppendLine("};")
    [void]$builder.AppendLine()
}
[void]$builder.AppendLine("}  // namespace")
[void]$builder.AppendLine()
[void]$builder.AppendLine("const BenchmarkAsset kBenchmarkAssets[] = {")
foreach ($asset in $assets) {
    [void]$builder.AppendLine(
        "    {`"$($asset.Name)`", `"$($asset.Class)`", k_$($asset.Name), sizeof(k_$($asset.Name))},")
}
[void]$builder.AppendLine("};")
[void]$builder.AppendLine(
    "const size_t kBenchmarkAssetCount = sizeof(kBenchmarkAssets) / sizeof(kBenchmarkAssets[0]);")
[void]$builder.AppendLine()
[void]$builder.AppendLine("}  // namespace p4jpegbenchmark")

$absoluteOutput = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($absoluteOutput)) | Out-Null
[System.IO.File]::WriteAllText($absoluteOutput, $builder.ToString(), [System.Text.UTF8Encoding]::new($false))
Write-Host "Wrote $absoluteOutput"
