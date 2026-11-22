# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$workRoot = Join-Path $repositoryRoot 'work/android/gate-5a/5a-03'
$inputDirectory = Join-Path $workRoot 'source-inputs'
$archiveName = 'amazon-corretto-21.0.11.10.1-windows-x64-jdk.zip'
$archivePath = Join-Path $inputDirectory $archiveName
$archiveUrl = 'https://corretto.aws/downloads/resources/21.0.11.10.1/amazon-corretto-21.0.11.10.1-windows-x64-jdk.zip'
$archiveSha256 = '5d63fdb5a19393081919afc0daa4ce82a7fadcced569981a995529caed28fb14'
$jdkRoot = Join-Path $workRoot 'jdk-host'
New-Item -ItemType Directory -Path $inputDirectory -Force | Out-Null

if (-not (Test-Path -LiteralPath $archivePath)) {
    $partialPath = "$archivePath.partial"
    Invoke-WebRequest -Uri $archiveUrl -OutFile $partialPath
    $downloadHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadHash -ne $archiveSha256) {
        Remove-Item -LiteralPath $partialPath -Force
        throw "Corretto archive SHA-256 mismatch: $downloadHash"
    }
    Move-Item -LiteralPath $partialPath -Destination $archivePath
}

$actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $archiveSha256) {
    throw "Corretto archive SHA-256 mismatch: $actualHash"
}

if (-not (Test-Path -LiteralPath $jdkRoot)) {
    Expand-Archive -LiteralPath $archivePath -DestinationPath $jdkRoot
}

$javaExecutable = Get-ChildItem -LiteralPath $jdkRoot -Filter 'java.exe' -File -Recurse |
    Where-Object { $_.FullName -match '\\bin\\java\.exe$' } |
    Select-Object -First 1
if (-not $javaExecutable) {
    throw "Could not find Corretto java.exe under $jdkRoot."
}
$javaHome = Split-Path (Split-Path $javaExecutable.FullName -Parent) -Parent
if (-not (Test-Path -LiteralPath (Join-Path $javaHome 'lib/jvm.cfg'))) {
    throw "Corretto JDK is missing lib/jvm.cfg: $javaHome"
}
$savedErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $version = (& $javaExecutable.FullName -version 2>&1 | Out-String)
}
finally {
    $ErrorActionPreference = $savedErrorActionPreference
}
if ($version -notmatch '21\.0\.11') {
    throw "Unexpected Corretto version: $version"
}
$env:JAVA_HOME = $javaHome
"JAVA_HOME=$javaHome"
"PASS Corretto JDK 21.0.11.10.1 sha256=$archiveSha256"
