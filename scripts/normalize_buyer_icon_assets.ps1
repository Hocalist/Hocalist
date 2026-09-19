param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function Get-InkScore {
    param(
        [System.Drawing.Color]$Pixel,
        [ValidateSet('blue', 'green', 'orange')]
        [string]$Mode
    )

    switch ($Mode) {
        'blue' {
            return $Pixel.B - [Math]::Max($Pixel.R, $Pixel.G)
        }
        'green' {
            return $Pixel.G - [Math]::Max($Pixel.R, $Pixel.B)
        }
        'orange' {
            return [Math]::Min($Pixel.R - $Pixel.B, $Pixel.G - $Pixel.B)
        }
    }
}

function Write-NormalizedIcon {
    param(
        [string]$RelativePath,
        [string]$OutputRelativePath = '',
        [ValidateSet('blue', 'green', 'orange')]
        [string]$Mode,
        [string]$CircleColor = '',
        [bool]$KeepSecondaryComponents = $true
    )

    $assetPath = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine($ProjectRoot, $RelativePath)
    )
    $projectPath = [System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'
    if (-not $assetPath.StartsWith($projectPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside the project: $assetPath"
    }
    if (-not (Test-Path -LiteralPath $assetPath)) {
        throw "Missing Buyer icon asset: $assetPath"
    }

    $destinationPath = if ($OutputRelativePath) {
        [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine($ProjectRoot, $OutputRelativePath)
        )
    }
    else {
        $assetPath
    }
    if (-not $destinationPath.StartsWith($projectPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside the project: $destinationPath"
    }

    $source = [System.Drawing.Bitmap]::FromFile($assetPath)
    try {
        $width = $source.Width
        $height = $source.Height
        $mask = [bool[,]]::new($width, $height)
        $scoreCutoff = switch ($Mode) {
            'blue' { 32 }
            'green' { 28 }
            'orange' { 28 }
        }
        $maximumInkRadius = [Math]::Min($width, $height) * 0.43
        $centerX = ($width - 1) / 2
        $centerY = ($height - 1) / 2

        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $pixel = $source.GetPixel($x, $y)
                if ($pixel.A -eq 0) {
                    continue
                }
                $dx = $x - $centerX
                $dy = $y - $centerY
                if ([Math]::Sqrt(($dx * $dx) + ($dy * $dy)) -gt $maximumInkRadius) {
                    continue
                }
                if ((Get-InkScore -Pixel $pixel -Mode $Mode) -ge $scoreCutoff) {
                    $mask[$x, $y] = $true
                }
            }
        }

        $visited = [bool[,]]::new($width, $height)
        $components = [System.Collections.ArrayList]::new()
        $directions = @(
            @(-1, -1), @(0, -1), @(1, -1),
            @(-1, 0),             @(1, 0),
            @(-1, 1),  @(0, 1),  @(1, 1)
        )

        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                if (-not $mask[$x, $y] -or $visited[$x, $y]) {
                    continue
                }

                $queue = [System.Collections.Generic.Queue[System.Drawing.Point]]::new()
                $points = [System.Collections.Generic.List[System.Drawing.Point]]::new()
                $queue.Enqueue([System.Drawing.Point]::new($x, $y))
                $visited[$x, $y] = $true

                while ($queue.Count -gt 0) {
                    $point = $queue.Dequeue()
                    $points.Add($point)
                    foreach ($direction in $directions) {
                        $nextX = $point.X + $direction[0]
                        $nextY = $point.Y + $direction[1]
                        if (
                            $nextX -ge 0 -and $nextX -lt $width -and
                            $nextY -ge 0 -and $nextY -lt $height -and
                            $mask[$nextX, $nextY] -and
                            -not $visited[$nextX, $nextY]
                        ) {
                            $visited[$nextX, $nextY] = $true
                            $queue.Enqueue([System.Drawing.Point]::new($nextX, $nextY))
                        }
                    }
                }
                [void]$components.Add($points)
            }
        }

        $ordered = @($components | Sort-Object Count -Descending)
        if ($ordered.Count -eq 0) {
            throw "No foreground icon pixels found in $RelativePath"
        }
        $largestCount = $ordered[0].Count

        $output = [System.Drawing.Bitmap]::new(
            $width,
            $height,
            [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
        )
        try {
            if ($CircleColor) {
                $graphics = [System.Drawing.Graphics]::FromImage($output)
                try {
                    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                    $graphics.Clear([System.Drawing.Color]::Transparent)
                    $brush = [System.Drawing.SolidBrush]::new(
                        [System.Drawing.ColorTranslator]::FromHtml($CircleColor)
                    )
                    try {
                        $graphics.FillEllipse($brush, 2, 2, $width - 4, $height - 4)
                    }
                    finally {
                        $brush.Dispose()
                    }
                }
                finally {
                    $graphics.Dispose()
                }
            }

            for ($index = 0; $index -lt $ordered.Count; $index++) {
                $component = $ordered[$index]
                if (-not $KeepSecondaryComponents -and $index -gt 0) {
                    continue
                }
                if (
                    $KeepSecondaryComponents -and
                    $component.Count -lt [Math]::Max(8, $largestCount * 0.04)
                ) {
                    continue
                }
                foreach ($point in $component) {
                    $pixel = $source.GetPixel($point.X, $point.Y)
                    $output.SetPixel(
                        $point.X,
                        $point.Y,
                        [System.Drawing.Color]::FromArgb(255, $pixel.R, $pixel.G, $pixel.B)
                    )
                }
            }

            $temporaryPath = "$destinationPath.normalized.png"
            $output.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Png)
        }
        finally {
            $output.Dispose()
        }
    }
    finally {
        $source.Dispose()
    }

    Move-Item -LiteralPath $temporaryPath -Destination $destinationPath -Force
}

$specifications = @(
    @{ Path = 'assets/approved_onboarding_home/dashboard-trophy.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/dashboard-trophy.png'; Output = 'assets/approved_onboarding_home/dashboard-trophy-glyph.png'; Mode = 'blue'; Circle = ''; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/dashboard-calendar.png'; Mode = 'green'; Circle = '#E8F7F0'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/dashboard-clipboard.png'; Mode = 'green'; Circle = '#E8F7F0'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/dashboard-medal.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-chat.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-location.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-medal.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-payment-shield.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-review-dollar.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-reward.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-shield.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/benefit-tag.png'; Mode = 'blue'; Circle = '#F0EEFE'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/activity-check.png'; Mode = 'green'; Circle = '#E8F7F0'; Multi = $true },
    @{ Path = 'assets/approved_onboarding_home/activity-star.png'; Mode = 'orange'; Circle = '#FFF7E8'; Multi = $true },
    @{ Path = 'assets/approved_offers_chat/offers-identity.png'; Mode = 'blue'; Circle = '#F2F0FF'; Multi = $true },
    @{ Path = 'assets/approved_offers_chat/offers-location.png'; Mode = 'blue'; Circle = '#F2F0FF'; Multi = $true },
    @{ Path = 'assets/approved_offers_chat/offers-clock.png'; Mode = 'blue'; Circle = '#F2F0FF'; Multi = $true },
    @{ Path = 'assets/approved_offers_chat/chat-location.png'; Mode = 'blue'; Circle = ''; Multi = $false },
    @{ Path = 'assets/approved_offers_chat/chat-time.png'; Mode = 'orange'; Circle = ''; Multi = $true },
    @{ Path = 'assets/approved_offers_chat/chat-price.png'; Mode = 'green'; Circle = ''; Multi = $true },
    @{ Path = 'assets/approved_offers_chat/chat-reward.png'; Mode = 'orange'; Circle = ''; Multi = $false }
)

foreach ($specification in $specifications) {
    Write-NormalizedIcon `
        -RelativePath $specification.Path `
        -OutputRelativePath $(if ($specification.ContainsKey('Output')) { $specification.Output } else { '' }) `
        -Mode $specification.Mode `
        -CircleColor $specification.Circle `
        -KeepSecondaryComponents $specification.Multi
}

Write-Output "Normalized $($specifications.Count) Buyer icon assets."
