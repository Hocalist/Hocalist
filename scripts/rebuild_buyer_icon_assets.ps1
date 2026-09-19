param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Buyer interface glyphs are rebuilt in place so every current and future
# screen consumes the same clean, centred source. Product photos, avatars,
# logos, social marks, and decorative illustrations are deliberately excluded.
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
    'buyer-avatar.png', 'buyer-video-payment.png', 'buyer-video-welcome.png',
    'dashboard-gift.png', 'home-buyer-card.png', 'home-seller-card.png',
    'home-video.png', 'john-avatar.png', 'offer-thumbnail.png',
    'ps5.png', 'ready-gift.png', 'reward-network-full.png',
    'rewards-gift.png', 'saving-gift.png', 'social-apple.png',
    'social-facebook.png', 'social-google.png', 'wordmark.png',
    'chat-ipad.png', 'chat-tv.png'
)

# These assets intentionally include the approved soft circle or rounded badge.
# Their treatment remains part of the glyph and therefore receives less inset.
$surfaceNames = @(
    'account-role-buyer.png', 'account-role-seller.png',
    'activity-chat.png', 'activity-check.png', 'activity-reward.png',
    'activity-star.png', 'benefit-chat.png', 'benefit-green-shield.png',
    'benefit-location.png', 'benefit-medal.png',
    'benefit-payment-shield.png', 'benefit-review-dollar.png',
    'benefit-reward.png', 'benefit-shield.png', 'benefit-tag.png',
    'buyer-mode-check.png', 'dashboard-calendar.png',
    'dashboard-clipboard.png', 'dashboard-medal.png', 'dashboard-plus.png',
    'dashboard-trophy.png', 'faq-buyer.png', 'faq-gift.png',
    'faq-question.png', 'faq-store.png', 'faq-target.png',
    'home-benefit-handshake.png', 'home-benefit-reward.png',
    'home-benefit-shield.png', 'home-benefit-target.png',
    'notification.png', 'offers-calendar.png', 'offers-clock.png',
    'offers-envelope.png', 'offers-fast-reply.png', 'offers-gift.png',
    'offers-heart.png', 'offers-identity.png', 'offers-location.png',
    'offers-lock.png', 'offers-top-match.png'
)

function Get-AlphaBounds {
    param([System.Drawing.Bitmap]$Bitmap)

    $left = $Bitmap.Width
    $top = $Bitmap.Height
    $right = -1
    $bottom = -1
    for ($y = 0; $y -lt $Bitmap.Height; $y++) {
        for ($x = 0; $x -lt $Bitmap.Width; $x++) {
            if ($Bitmap.GetPixel($x, $y).A -gt 8) {
                if ($x -lt $left) { $left = $x }
                if ($x -gt $right) { $right = $x }
                if ($y -lt $top) { $top = $y }
                if ($y -gt $bottom) { $bottom = $y }
            }
        }
    }
    if ($right -lt $left -or $bottom -lt $top) {
        throw 'Asset contains no visible pixels.'
    }
    return [System.Drawing.Rectangle]::FromLTRB($left, $top, $right + 1, $bottom + 1)
}

function Write-RebuiltIcon {
    param(
        [System.IO.FileInfo]$Asset,
        [bool]$HasSurface
    )

    $source = [System.Drawing.Bitmap]::FromFile($Asset.FullName)
    try {
        $bounds = Get-AlphaBounds -Bitmap $source
        $canvasSize = 128
        $fillRatio = if ($HasSurface) { 0.91 } else { 0.76 }
        $maximumPaint = $canvasSize * $fillRatio
        $actualMaximumPaint = [Math]::Max($bounds.Width, $bounds.Height)
        $boundsCenterX = $bounds.Left + (($bounds.Width - 1) / 2)
        $boundsCenterY = $bounds.Top + (($bounds.Height - 1) / 2)
        $canvasCenter = ($canvasSize - 1) / 2
        $alreadyCanonical =
            $source.Width -eq $canvasSize -and
            $source.Height -eq $canvasSize -and
            [Math]::Abs($actualMaximumPaint - $maximumPaint) -le 2 -and
            [Math]::Abs($boundsCenterX - $canvasCenter) -le 1.5 -and
            [Math]::Abs($boundsCenterY - $canvasCenter) -le 1.5
        if ($alreadyCanonical) {
            return
        }
        $scale = [Math]::Min($maximumPaint / $bounds.Width, $maximumPaint / $bounds.Height)
        $paintWidth = $bounds.Width * $scale
        $paintHeight = $bounds.Height * $scale
        $paintX = ($canvasSize - $paintWidth) / 2
        $paintY = ($canvasSize - $paintHeight) / 2

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
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
                $destination = [System.Drawing.RectangleF]::new($paintX, $paintY, $paintWidth, $paintHeight)
                $graphics.DrawImage($source, $destination, $bounds, [System.Drawing.GraphicsUnit]::Pixel)
            }
            finally {
                $graphics.Dispose()
            }

            $temporaryPath = "$($Asset.FullName).rebuilt.png"
            $output.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $output.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }

    Move-Item -LiteralPath $temporaryPath -Destination $Asset.FullName -Force
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
$assets = foreach ($family in $families) {
    $familyPath = [System.IO.Path]::GetFullPath((Join-Path $ProjectRoot $family))
    if (-not $familyPath.StartsWith($projectPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to process a directory outside the project: $familyPath"
    }
    if (Test-Path -LiteralPath $familyPath) {
        Get-ChildItem -LiteralPath $familyPath -File -Filter '*.png' |
            Where-Object { $_.Name -notin $excludedNames }
    }
}
$assets = @($assets | Sort-Object FullName -Unique)

foreach ($asset in $assets) {
    Write-RebuiltIcon -Asset $asset -HasSurface ($asset.Name -in $surfaceNames)
}

foreach ($asset in $assets) {
    $icon = [System.Drawing.Bitmap]::FromFile($asset.FullName)
    try {
        if ($icon.Width -ne 128 -or $icon.Height -ne 128) {
            throw "$($asset.FullName) is not on the canonical 128x128 canvas."
        }
        for ($x = 0; $x -lt $icon.Width; $x++) {
            if ($icon.GetPixel($x, 0).A -gt 8 -or $icon.GetPixel($x, $icon.Height - 1).A -gt 8) {
                throw "$($asset.FullName) touches the top or bottom canvas edge."
            }
        }
        for ($y = 0; $y -lt $icon.Height; $y++) {
            if ($icon.GetPixel(0, $y).A -gt 8 -or $icon.GetPixel($icon.Width - 1, $y).A -gt 8) {
                throw "$($asset.FullName) touches the left or right canvas edge."
            }
        }
    }
    finally {
        $icon.Dispose()
    }
}

Write-Output "Rebuilt and verified $($assets.Count) Buyer interface icon assets."
