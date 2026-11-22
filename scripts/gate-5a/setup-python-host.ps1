# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$workRoot = Join-Path $repositoryRoot 'work/android/gate-5a/5a-03'
$inputDirectory = Join-Path $workRoot 'source-inputs'
$installerPath = Join-Path $inputDirectory 'python-3.13.17-amd64.exe'
$installerUrl = 'https://www.python.org/ftp/python/3.13.17/python-3.13.17-amd64.exe'
$installerSha256 = '5da012101ba2e17113a9a1cd901e9ce1441086f2b7ecb5de06ec94163899a190'
$pythonDirectory = Join-Path $workRoot 'python-host'
$pythonPath = Join-Path $pythonDirectory 'python.exe'
New-Item -ItemType Directory -Path $inputDirectory -Force | Out-Null

if (-not (Test-Path -LiteralPath $installerPath)) {
    $partialPath = "$installerPath.partial"
    Invoke-WebRequest -Uri $installerUrl -OutFile $partialPath
    $downloadHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadHash -ne $installerSha256) {
        Remove-Item -LiteralPath $partialPath -Force
        throw "Python installer SHA-256 mismatch: $downloadHash"
    }
    Move-Item -LiteralPath $partialPath -Destination $installerPath
}

$actualHash = (Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $installerSha256) {
    throw "Python installer SHA-256 mismatch: $actualHash"
}

if (-not (Test-Path -LiteralPath $pythonPath)) {
    $arguments = @(
        '/quiet',
        'InstallAllUsers=0',
        "TargetDir=$pythonDirectory",
        'Include_pip=1',
        'Include_test=0',
        'Include_doc=0',
        'Include_launcher=0',
        'PrependPath=0'
    )
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw "Python installer exited with code $($process.ExitCode)."
    }
}

$version = (& $pythonPath --version 2>&1 | Out-String).Trim()
if ($version -ne 'Python 3.13.17') {
    throw "Unexpected Python build host: $version"
}
$env:CHAQUOPY_BUILD_PYTHON = $pythonPath
"CHAQUOPY_BUILD_PYTHON=$pythonPath"
"PASS Python build host: $version sha256=$installerSha256"
