param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# The Seller conversation uses role-specific copies of the approved chat
# artwork. The interface glyphs were originally cropped from a white screen,
# so their opaque outer canvas becomes visible when an IconButton is pressed.
# Remove only white pixels connected to the bitmap edge. Enclosed white pixels
# (for example, the inside of a paper-plane glyph) and colored surfaces remain.
$excludedNames = @(
    'actual-chat-426.png',
    'actual-offers-426.png',
    'actual-view-offer-426.png',
    'comparison-contact-sheet.png',
    'chat-ipad.png',
    'john-avatar.png',
    'offer-thumbnail.png',
    'ps5.png',
    'rewards-gift.png',
    'wordmark.png'
)

function Remove-OuterWhiteCanvas {
    param([System.IO.FileInfo]$Asset)

    $source = [System.Drawing.Bitmap]::FromFile($Asset.FullName)
    try {
        $hasOuterWhite = $false
        for ($x = 0; $x -lt $source.Width -and -not $hasOuterWhite; $x++) {
            foreach ($y in @(0, ($source.Height - 1))) {
                $pixel = $source.GetPixel($x, $y)
                $maximum = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
                $minimum = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
                if ($pixel.A -gt 0 -and $minimum -ge 238 -and ($maximum - $minimum) -le 16) {
                    $hasOuterWhite = $true
                    break
                }
            }
        }
        for ($y = 0; $y -lt $source.Height -and -not $hasOuterWhite; $y++) {
            foreach ($x in @(0, ($source.Width - 1))) {
                $pixel = $source.GetPixel($x, $y)
                $maximum = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
                $minimum = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
                if ($pixel.A -gt 0 -and $minimum -ge 238 -and ($maximum - $minimum) -le 16) {
                    $hasOuterWhite = $true
                    break
                }
            }
        }
        if (-not $hasOuterWhite) { return 0 }

        $bitmap = [System.Drawing.Bitmap]::new(
            $source.Width,
            $source.Height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.DrawImageUnscaled($source, 0, 0)
        }
        finally {
            $graphics.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }

    try {
        $width = $bitmap.Width
        $height = $bitmap.Height
        $rectangle = [System.Drawing.Rectangle]::new(0, 0, $width, $height)
        $bitmapData = $bitmap.LockBits(
            $rectangle,
            [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            $stride = $bitmapData.Stride
            if ($stride -le 0) {
                throw "Unsupported bitmap stride for $($Asset.FullName)."
            }
            $pixels = [byte[]]::new($stride * $height)
            [System.Runtime.InteropServices.Marshal]::Copy(
                $bitmapData.Scan0,
                $pixels,
                0,
                $pixels.Length
            )

            $queue = [System.Collections.Generic.Queue[int]]::new()
            $visited = [bool[]]::new($width * $height)
            for ($x = 0; $x -lt $width; $x++) {
                $queue.Enqueue($x)
                $queue.Enqueue((($height - 1) * $width) + $x)
            }
            for ($y = 1; $y -lt ($height - 1); $y++) {
                $queue.Enqueue($y * $width)
                $queue.Enqueue(($y * $width) + ($width - 1))
            }

            $removed = 0
            while ($queue.Count -gt 0) {
                $index = $queue.Dequeue()
                if ($visited[$index]) { continue }
                $visited[$index] = $true

                $x = $index % $width
                $y = [int][Math]::Floor($index / $width)
                $offset = ($y * $stride) + ($x * 4)
                $blue = $pixels[$offset]
                $green = $pixels[$offset + 1]
                $red = $pixels[$offset + 2]
                $alpha = $pixels[$offset + 3]
                $maximum = [Math]::Max($red, [Math]::Max($green, $blue))
                $minimum = [Math]::Min($red, [Math]::Min($green, $blue))
                $isOuterWhite = $alpha -eq 0 -or (
                    $minimum -ge 238 -and ($maximum - $minimum) -le 16
                )
                if (-not $isOuterWhite) { continue }

                if ($alpha -ne 0) {
                    $pixels[$offset + 3] = 0
                    $removed++
                }
                if ($x -gt 0) { $queue.Enqueue($index - 1) }
                if ($x + 1 -lt $width) { $queue.Enqueue($index + 1) }
                if ($y -gt 0) { $queue.Enqueue($index - $width) }
                if ($y + 1 -lt $height) { $queue.Enqueue($index + $width) }
            }

            [System.Runtime.InteropServices.Marshal]::Copy(
                $pixels,
                0,
                $bitmapData.Scan0,
                $pixels.Length
            )
        }
        finally {
            $bitmap.UnlockBits($bitmapData)
        }

        if ($removed -gt 0) {
            $temporaryPath = "$($Asset.FullName).cleaned.png"
            $bitmap.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
            Move-Item -LiteralPath $temporaryPath -Destination $Asset.FullName -Force
        }
        return $removed
    }
    finally {
        $bitmap.Dispose()
    }
}

$projectPath = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
$familyPath = [System.IO.Path]::GetFullPath(
    (Join-Path $ProjectRoot 'assets/approved_seller/chat')
)
if (-not $familyPath.StartsWith(
    $projectPath,
    [System.StringComparison]::OrdinalIgnoreCase
)) {
    throw "Refusing to process a directory outside the project: $familyPath"
}

$assets = Get-ChildItem -LiteralPath $familyPath -File -Filter '*.png' |
    Where-Object { $_.Name -notin $excludedNames }

$changed = 0
foreach ($asset in $assets) {
    if ((Remove-OuterWhiteCanvas -Asset $asset) -gt 0) { $changed++ }
}

foreach ($asset in $assets) {
    $bitmap = [System.Drawing.Bitmap]::FromFile($asset.FullName)
    try {
        $corners = @(
            $bitmap.GetPixel(0, 0),
            $bitmap.GetPixel($bitmap.Width - 1, 0),
            $bitmap.GetPixel(0, $bitmap.Height - 1),
            $bitmap.GetPixel($bitmap.Width - 1, $bitmap.Height - 1)
        )
        foreach ($pixel in $corners) {
            $maximum = [Math]::Max($pixel.R, [Math]::Max($pixel.G, $pixel.B))
            $minimum = [Math]::Min($pixel.R, [Math]::Min($pixel.G, $pixel.B))
            if ($pixel.A -gt 0 -and $minimum -ge 238 -and ($maximum - $minimum) -le 16) {
                throw "$($asset.FullName) still has an opaque screenshot-white corner."
            }
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

Write-Output "Cleaned $changed Seller chat icon assets; verified $($assets.Count)."
