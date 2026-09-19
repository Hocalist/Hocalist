param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputPath = 'output/buyer-icons/buyer-interface-icons.png'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$families = @(
    'assets/buyer_nav',
    'assets/approved_onboarding_home',
    'assets/post_request',
    'assets/approved_offers_chat',
    'assets/approved_trends_notifications/transparent'
)

$excludedNames = @(
    'actual-chat-426.png', 'actual-offers-426.png',
    'actual-view-offer-426.png', 'comparison-contact-sheet.png',
    'buyer-video-payment.png', 'buyer-video-welcome.png',
    'dashboard-gift.png', 'home-buyer-card.png', 'home-seller-card.png',
    'home-video.png', 'john-avatar.png', 'offer-thumbnail.png',
    'ps5.png', 'ready-gift.png', 'reward-network-full.png',
    'rewards-gift.png', 'saving-gift.png', 'wordmark.png'
)

$assets = foreach ($family in $families) {
    $path = Join-Path $ProjectRoot $family
    if (Test-Path -LiteralPath $path) {
        Get-ChildItem -LiteralPath $path -File -Filter '*.png' |
            Where-Object { $_.Name -notin $excludedNames }
    }
}
$assets = @($assets | Sort-Object FullName -Unique)

$cellWidth = 210
$cellHeight = 142
$columns = 5
$rows = [Math]::Ceiling($assets.Count / $columns)
$sheet = [System.Drawing.Bitmap]::new(
    $cellWidth * $columns,
    $cellHeight * $rows,
    [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
)

$graphics = [System.Drawing.Graphics]::FromImage($sheet)
try {
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $graphics.Clear([System.Drawing.Color]::White)
    $labelFont = [System.Drawing.Font]::new('Segoe UI', 8)
    $metaFont = [System.Drawing.Font]::new('Segoe UI', 7)
    $darkBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(12, 18, 61))
    $mutedBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(89, 97, 127))
    $linePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(226, 228, 239))
    $checkerLight = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(248, 248, 252))
    $checkerDark = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(232, 232, 240))
    try {
        for ($index = 0; $index -lt $assets.Count; $index++) {
            $column = $index % $columns
            $row = [Math]::Floor($index / $columns)
            $x = $column * $cellWidth
            $y = $row * $cellHeight
            $graphics.DrawRectangle($linePen, $x, $y, $cellWidth - 1, $cellHeight - 1)

            $previewSize = 86
            $previewX = $x + (($cellWidth - $previewSize) / 2)
            $previewY = $y + 8
            for ($checkerY = 0; $checkerY -lt $previewSize; $checkerY += 8) {
                for ($checkerX = 0; $checkerX -lt $previewSize; $checkerX += 8) {
                    $brush = if ((($checkerX + $checkerY) / 8) % 2 -eq 0) { $checkerLight } else { $checkerDark }
                    $graphics.FillRectangle($brush, $previewX + $checkerX, $previewY + $checkerY, 8, 8)
                }
            }

            $icon = [System.Drawing.Bitmap]::FromFile($assets[$index].FullName)
            try {
                $scale = [Math]::Min($previewSize / $icon.Width, $previewSize / $icon.Height)
                $drawWidth = $icon.Width * $scale
                $drawHeight = $icon.Height * $scale
                $drawX = $previewX + (($previewSize - $drawWidth) / 2)
                $drawY = $previewY + (($previewSize - $drawHeight) / 2)
                $graphics.DrawImage($icon, $drawX, $drawY, $drawWidth, $drawHeight)
                $graphics.DrawString($assets[$index].Name, $labelFont, $darkBrush, $x + 6, $y + 99)
                $familyName = Split-Path -Leaf $assets[$index].DirectoryName
                $graphics.DrawString("$familyName | $($icon.Width)x$($icon.Height)", $metaFont, $mutedBrush, $x + 6, $y + 118)
            }
            finally {
                $icon.Dispose()
            }
        }
    }
    finally {
        $labelFont.Dispose()
        $metaFont.Dispose()
        $darkBrush.Dispose()
        $mutedBrush.Dispose()
        $linePen.Dispose()
        $checkerLight.Dispose()
        $checkerDark.Dispose()
    }
}
finally {
    $graphics.Dispose()
}

$absoluteOutput = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $OutputPath))
$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
if (-not $absoluteOutput.StartsWith($projectPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    $sheet.Dispose()
    throw "Refusing to write outside the project: $absoluteOutput"
}
$outputDirectory = Split-Path -Parent $absoluteOutput
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
try {
    $sheet.Save($absoluteOutput, [System.Drawing.Imaging.ImageFormat]::Png)
}
finally {
    $sheet.Dispose()
}

Write-Output "Wrote $($assets.Count) Buyer interface assets to $absoluteOutput"
