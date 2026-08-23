param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Add-Type -AssemblyName System.Drawing

if (-not ('ToyotaLogoAlpha' -as [type])) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;

public static class ToyotaLogoAlpha
{
    public static void Convert(string inputPath, string outputPath)
    {
        using (var source = new Bitmap(inputPath))
        using (var output = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            for (var y = 0; y < source.Height; y++)
            {
                for (var x = 0; x < source.Width; x++)
                {
                    var pixel = source.GetPixel(x, y);
                    var intensity = Math.Max(pixel.R, Math.Max(pixel.G, pixel.B));
                    var alpha = intensity <= 8
                        ? 0
                        : Math.Min(255, (int)Math.Round((intensity - 8) * 255.0 / 247.0));

                    output.SetPixel(x, y, Color.FromArgb(alpha, pixel.R, pixel.G, pixel.B));
                }
            }

            output.Save(outputPath, ImageFormat.Png);
        }
    }
}
'@
}

$resolvedInput = (Resolve-Path -LiteralPath $InputPath).Path
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = [System.IO.Path]::GetDirectoryName($resolvedOutput)

if (-not [System.IO.Directory]::Exists($outputDirectory)) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

[ToyotaLogoAlpha]::Convert($resolvedInput, $resolvedOutput)
