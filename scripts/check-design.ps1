# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$designRoot = Join-Path $repoRoot 'docs/design'
$inventoryPath = Join-Path $designRoot 'README.md'
$inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8

# Read the nine PNG rows from the confirmed Markdown inventory.
$rowPattern = '(?m)^\|\s*\[`(?<path>(?:desktop|mobile)/[a-z0-9-]+\.png)`\]\((?<link>[^)]+)\)\s*\|[^|]*\|\s*(?<width>\d+)\s*\u00D7\s*(?<height>\d+)\s*\|\s*$'
$rows = [regex]::Matches($inventory, $rowPattern)
if ($rows.Count -ne 9) {
    throw "Expected nine indexed PNG rows in $inventoryPath; found $($rows.Count)."
}

$seen = @{}
foreach ($row in $rows) {
    $relativePath = $row.Groups['path'].Value
    if ($seen.ContainsKey($relativePath)) {
        throw "Duplicate design reference: $relativePath"
    }
    $seen[$relativePath] = $true

    if ($row.Groups['link'].Value -cne $relativePath) {
        throw "Design link differs from its label: $relativePath"
    }

    $imagePath = Join-Path $designRoot ($relativePath -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
        throw "Missing design image: $relativePath"
    }

    $gitPath = 'docs/design/' + $relativePath
    git -C $repoRoot ls-files --error-unmatch -- $gitPath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Design image is not tracked by Git: $relativePath"
    }

    # PNG stores big-endian width and height in the first IHDR chunk.
    $header = @(Get-Content -LiteralPath $imagePath -Encoding Byte -TotalCount 24)
    $pngSignature = @(137, 80, 78, 71, 13, 10, 26, 10)
    if ($header.Count -ne 24) {
        throw "Incomplete PNG header: $relativePath"
    }
    for ($i = 0; $i -lt $pngSignature.Count; $i++) {
        if ($header[$i] -ne $pngSignature[$i]) {
            throw "Invalid PNG signature: $relativePath"
        }
    }
    if ([Text.Encoding]::ASCII.GetString([byte[]]$header[12..15]) -cne 'IHDR') {
        throw "Missing PNG IHDR chunk: $relativePath"
    }

    $width = ([uint32]$header[16] -shl 24) -bor ([uint32]$header[17] -shl 16) -bor ([uint32]$header[18] -shl 8) -bor [uint32]$header[19]
    $height = ([uint32]$header[20] -shl 24) -bor ([uint32]$header[21] -shl 16) -bor ([uint32]$header[22] -shl 8) -bor [uint32]$header[23]
    $expectedWidth = [uint32]$row.Groups['width'].Value
    $expectedHeight = [uint32]$row.Groups['height'].Value
    if ($width -ne $expectedWidth -or $height -ne $expectedHeight) {
        throw "Dimension mismatch for ${relativePath}: expected ${expectedWidth}x${expectedHeight}, found ${width}x${height}."
    }

    Write-Output "OK $relativePath ${width}x${height}"
}

$imageCount = @(Get-ChildItem -LiteralPath $designRoot -Recurse -File -Filter '*.png').Count
if ($imageCount -ne $rows.Count) {
    throw "Found $imageCount PNG files, but $($rows.Count) are indexed."
}

Write-Output 'Design inventory verified: nine tracked PNGs with matching dimensions.'
