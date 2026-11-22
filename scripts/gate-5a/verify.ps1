# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('python-runtime')]
    [string]$Case
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'runtime-lock.psd1')
$workRoot = Join-Path $repositoryRoot 'work/android/gate-5a/5a-03'
$inputDirectory = Join-Path $workRoot 'source-inputs'
$buildLog = Join-Path $workRoot 'android-build.log'
New-Item -ItemType Directory -Path $inputDirectory -Force | Out-Null

$lockedInputs = @(
    @{ Name = 'chaquopy-17.2.0.tar.gz'; Url = $lock.Chaquopy.SourceUrl; Sha256 = $lock.Chaquopy.SourceSha256 },
    @{ Name = 'Python-3.13.16.tgz'; Url = $lock.Python.SourceUrl; Sha256 = $lock.Python.SourceSha256 },
    @{ Name = 'yt-dlp-2026.08.19.tar.gz'; Url = $lock.YtDlp.SourceUrl; Sha256 = $lock.YtDlp.SourceSha256 },
    @{ Name = 'yt_dlp-2026.8.19-py3-none-any.whl'; Url = $lock.YtDlp.WheelUrl; Sha256 = $lock.YtDlp.WheelSha256 },
    @{ Name = 'yt-dlp-ejs-0.8.0.tar.gz'; Url = $lock.Ejs.SourceUrl; Sha256 = $lock.Ejs.SourceSha256 },
    @{ Name = 'yt_dlp_ejs-0.8.0-py3-none-any.whl'; Url = $lock.Ejs.WheelUrl; Sha256 = $lock.Ejs.WheelSha256 }
)

foreach ($input in $lockedInputs) {
    $inputPath = Join-Path $inputDirectory $input.Name
    if (-not (Test-Path -LiteralPath $inputPath)) {
        $partialPath = "$inputPath.partial"
        Invoke-WebRequest -Uri $input.Url -OutFile $partialPath
        $downloadHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($downloadHash -ne $input.Sha256) {
            Remove-Item -LiteralPath $partialPath -Force
            throw "SHA-256 mismatch for downloaded $($input.Name): $downloadHash"
        }
        Move-Item -LiteralPath $partialPath -Destination $inputPath
    }

    $actualHash = (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $input.Sha256) {
        throw "SHA-256 mismatch for $($input.Name): $actualHash"
    }
}

$defaultPython = Join-Path $workRoot 'python-host/python.exe'
$pythonCommand = if ($env:CHAQUOPY_BUILD_PYTHON) {
    $env:CHAQUOPY_BUILD_PYTHON
} elseif (Test-Path -LiteralPath $defaultPython) {
    $defaultPython
} else {
    'python'
}
$pythonVersion = (& $pythonCommand --version 2>&1 | Out-String).Trim()
if ($pythonVersion -notmatch '^Python 3\.13\.') {
    throw "Chaquopy requires a Python 3.13 host interpreter; found '$pythonVersion'. Set CHAQUOPY_BUILD_PYTHON."
}
$env:CHAQUOPY_BUILD_PYTHON = $pythonCommand

$localJdkRoot = Join-Path $workRoot 'jdk-host'
$localJava = if (Test-Path -LiteralPath $localJdkRoot) {
    Get-ChildItem -LiteralPath $localJdkRoot -Filter 'java.exe' -File -Recurse |
        Where-Object { $_.FullName -match '\\bin\\java\.exe$' } |
        Select-Object -First 1
}
$candidateJavaHome = if ($localJava) {
    Split-Path (Split-Path $localJava.FullName -Parent) -Parent
} else {
    $env:JAVA_HOME
}
$javaHomeConfig = if ($candidateJavaHome) { Join-Path $candidateJavaHome 'lib/jvm.cfg' } else { '' }
if (-not $javaHomeConfig -or -not (Test-Path -LiteralPath $javaHomeConfig)) {
    $javaExecutable = (Get-Command 'java.exe' -ErrorAction Stop).Source
    $candidateJavaHome = Split-Path (Split-Path $javaExecutable -Parent) -Parent
    if (-not (Test-Path -LiteralPath (Join-Path $candidateJavaHome 'lib/jvm.cfg'))) {
        throw "JAVA_HOME '$env:JAVA_HOME' is invalid and the java.exe on PATH has no lib/jvm.cfg."
    }
}
$env:JAVA_HOME = $candidateJavaHome
$env:PATH = "$(Join-Path $candidateJavaHome 'bin');$env:PATH"
"Using Java home: $candidateJavaHome"

$npmCommand = Get-Command 'npm.cmd' -ErrorAction SilentlyContinue
if (-not $npmCommand) {
    $npmCommand = Get-Command 'npm' -ErrorAction Stop
}

Push-Location $repositoryRoot
$savedErrorActionPreference = $ErrorActionPreference
try {
    # Windows PowerShell 5 treats native stderr as a terminating error when
    # ErrorActionPreference is Stop, even though the build's exit code is valid.
    $ErrorActionPreference = 'Continue'
    & $npmCommand.Source run android:debug 2>&1 |
        ForEach-Object { "$_" } |
        Set-Content -LiteralPath $buildLog -Encoding utf8
    $buildExitCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $savedErrorActionPreference
    Pop-Location
}

if ($buildExitCode -ne 0) {
    Get-Content -LiteralPath $buildLog -Tail 50 | ForEach-Object {
        if ($_.Length -gt 500) { $_.Substring(0, 500) + ' ... [long line truncated]' } else { $_ }
    }
    throw "Android package build failed with exit code $buildExitCode."
}

$apkDirectory = Join-Path $repositoryRoot 'src-tauri/gen/android/app/build/outputs/apk'
$apk = Get-ChildItem -LiteralPath $apkDirectory -Filter '*.apk' -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if (-not $apk) {
    throw "No APK was produced under $apkDirectory."
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$package = [System.IO.Compression.ZipFile]::OpenRead($apk.FullName)
try {
    $abis = @(
        $package.Entries |
            ForEach-Object {
                if ($_.FullName -match '^lib/([^/]+)/') { $Matches[1] }
                elseif ($_.FullName -match '^assets/chaquopy/bootstrap-native/([^/]+)/') { $Matches[1] }
            } |
            Sort-Object -Unique
    )
    if ($abis.Count -ne 1 -or $abis[0] -ne $lock.Abi) {
        throw "Expected only $($lock.Abi) native libraries; APK contains: $($abis -join ', ')"
    }

    $pythonLibraries = @($package.Entries | Where-Object { $_.FullName -match '^lib/arm64-v8a/libpython[^/]*\.so$' })
    if ($pythonLibraries.Count -eq 0) {
        throw 'The APK does not contain Chaquopy Python shared libraries for arm64-v8a.'
    }

    $buildMetadataEntry = $package.GetEntry('assets/chaquopy/build.json')
    if (-not $buildMetadataEntry) { throw 'The APK is missing Chaquopy build metadata.' }
    $metadataReader = [System.IO.StreamReader]::new($buildMetadataEntry.Open())
    try { $buildMetadata = $metadataReader.ReadToEnd() | ConvertFrom-Json }
    finally { $metadataReader.Dispose() }
    if ($buildMetadata.python_version -ne '3.13') {
        throw "Expected Python 3.13 in the APK; found '$($buildMetadata.python_version)'."
    }

    $requirementsEntry = $package.GetEntry('assets/chaquopy/requirements-common.imy')
    if (-not $requirementsEntry) { throw 'The APK is missing the pinned Python requirements archive.' }
    $requirementsStream = $requirementsEntry.Open()
    $requirementsBytes = [System.IO.MemoryStream]::new()
    try { $requirementsStream.CopyTo($requirementsBytes) }
    finally { $requirementsStream.Dispose() }
    $requirementsBytes.Position = 0
    $requirementsArchive = [System.IO.Compression.ZipArchive]::new(
        $requirementsBytes,
        [System.IO.Compression.ZipArchiveMode]::Read,
        $true
    )
    try {
        $expectedPackages = @(
            @{ Metadata = "yt_dlp-$($lock.YtDlp.MetadataVersion).dist-info/METADATA"; Version = $lock.YtDlp.MetadataVersion },
            @{ Metadata = "yt_dlp_ejs-$($lock.Ejs.Version).dist-info/METADATA"; Version = $lock.Ejs.Version }
        )
        foreach ($expected in $expectedPackages) {
            $entry = $requirementsArchive.GetEntry($expected.Metadata)
            if (-not $entry) { throw "The APK is missing package metadata $($expected.Metadata)." }
            $reader = [System.IO.StreamReader]::new($entry.Open())
            try { $packageMetadata = $reader.ReadToEnd() }
            finally { $reader.Dispose() }
            if ($packageMetadata -notmatch "(?m)^Version:\s*$([regex]::Escape($expected.Version))\s*$") {
                throw "APK package metadata does not confirm version $($expected.Version) for $($expected.Metadata)."
            }
        }
        foreach ($solverScript in @('yt_dlp_ejs/yt/solver/core.min.js', 'yt_dlp_ejs/yt/solver/lib.min.js')) {
            if (-not $requirementsArchive.GetEntry($solverScript)) {
                throw "The APK is missing the pinned EJS solver script $solverScript."
            }
        }
    }
    finally {
        $requirementsArchive.Dispose()
        $requirementsBytes.Dispose()
    }
}
finally {
    $package.Dispose()
}

$apkHash = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
"PASS python-runtime: Chaquopy $($lock.Chaquopy.Version), Python $($lock.Python.Version), yt-dlp $($lock.YtDlp.Version), EJS $($lock.Ejs.Version), ABI $($lock.Abi)"
"APK $($apk.FullName) bytes=$($apk.Length) sha256=$apkHash"
