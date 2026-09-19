param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Write-DetailPinIcon {
    param([string]$TargetPath)

    $canvasSize = 128
    $output = [System.Drawing.Bitmap]::new(
        $canvasSize,
        $canvasSize,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($output)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

            $outline = [System.Drawing.Color]::FromArgb(255, 43, 30, 242)
            $softFill = [System.Drawing.Color]::FromArgb(255, 239, 237, 255)
            $white = [System.Drawing.Color]::White
            $outlinePen = [System.Drawing.Pen]::new($outline, 5)
            $outlinePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
            $outlinePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $outlinePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
            $shieldFill = [System.Drawing.SolidBrush]::new($softFill)
            $whiteBrush = [System.Drawing.SolidBrush]::new($white)
            $outlineBrush = [System.Drawing.SolidBrush]::new($outline)
            try {
                $shield = [System.Drawing.Drawing2D.GraphicsPath]::new()
                try {
                    $shield.StartFigure()
                    $shield.AddBezier(64, 17, 52, 25, 42, 27, 30, 28)
                    $shield.AddBezier(30, 28, 30, 56, 33, 78, 43, 90)
                    $shield.AddBezier(43, 90, 49, 98, 57, 104, 64, 108)
                    $shield.AddBezier(64, 108, 71, 104, 79, 98, 85, 90)
                    $shield.AddBezier(85, 90, 95, 78, 98, 56, 98, 28)
                    $shield.AddBezier(98, 28, 86, 27, 76, 25, 64, 17)
                    $shield.CloseFigure()
                    $graphics.FillPath($shieldFill, $shield)
                    $graphics.DrawPath($outlinePen, $shield)
                }
                finally {
                    $shield.Dispose()
                }

                $questionPen = [System.Drawing.Pen]::new($outline, 6)
                try {
                    $questionPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $questionPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $graphics.DrawBezier($questionPen, 48, 51, 52, 42, 72, 41, 77, 51)
                    $graphics.DrawBezier($questionPen, 77, 51, 82, 63, 65, 64, 64, 75)
                    $graphics.FillEllipse($outlineBrush, 61, 82, 7, 7)
                }
                finally {
                    $questionPen.Dispose()
                }

                $graphics.FillEllipse($whiteBrush, 73, 72, 39, 39)
                $graphics.DrawEllipse($outlinePen, 73, 72, 39, 39)
                $graphics.FillEllipse($outlineBrush, 90, 82, 5, 5)
                $infoPen = [System.Drawing.Pen]::new($outline, 4)
                try {
                    $infoPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $infoPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
                    $graphics.DrawLine($infoPen, 92.5, 91, 92.5, 101)
                }
                finally {
                    $infoPen.Dispose()
                }
            }
            finally {
                $outlinePen.Dispose()
                $shieldFill.Dispose()
                $whiteBrush.Dispose()
                $outlineBrush.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }

        $absoluteTarget = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $TargetPath))
        $projectPath = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
        if (-not $absoluteTarget.StartsWith($projectPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to write outside the project: $absoluteTarget"
        }
        $temporaryPath = "$absoluteTarget.rebuilt.png"
        $output.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
        Move-Item -LiteralPath $temporaryPath -Destination $absoluteTarget -Force
    }
    finally {
        $output.Dispose()
    }
}

$targets = @(
    'assets/approved_offers_chat/detail-pin.png',
    'assets/approved_seller/chat/detail-pin.png'
)
foreach ($target in $targets) {
    Write-DetailPinIcon -TargetPath $target
}

Write-Output "Rebuilt $($targets.Count) clean detail PIN icon assets."
