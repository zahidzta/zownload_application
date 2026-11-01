# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$version = '0.9'
$expectedSha256 = '2D3D26D635417D0E1177EA7D5E927F66635CEA719A6727039D834E1A8A5D0580'
$temporaryRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$toolDirectory = Join-Path $temporaryRoot "minisign-$version"
$executable = Join-Path $toolDirectory 'minisign.exe'
$archive = Join-Path $toolDirectory "minisign-win64-$version.zip"

if (!(Test-Path -LiteralPath $executable)) {
    New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
    Invoke-WebRequest `
        -Uri "https://github.com/jedisct1/minisign/releases/download/$version/minisign-win64.zip" `
        -OutFile $archive `
        -UseBasicParsing

    $actualSha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($actualSha256 -ne $expectedSha256) {
        throw 'The pinned Minisign archive SHA-256 did not match.'
    }

    Expand-Archive -LiteralPath $archive -DestinationPath $toolDirectory -Force
}

if (!(Test-Path -LiteralPath $executable)) {
    throw 'The pinned Minisign archive did not contain minisign.exe.'
}

Write-Output $executable
