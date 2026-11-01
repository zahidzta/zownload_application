# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PreviousBundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$CandidateBundleRoot,

    [Parameter(Mandatory = $true)]
    [string]$CandidateConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$MinisignPath,

    [Parameter(Mandatory = $true)]
    [string]$PreviousVersion,

    [Parameter(Mandatory = $true)]
    [string]$CandidateVersion,

    [Parameter(Mandatory = $true)]
    [string]$PreviousRef,

    [Parameter(Mandatory = $true)]
    [string]$CandidateRef,

    [int]$FixturePort = 38547,

    [string]$EvidencePath = 'docs/gates/evidence/3c/3c-03.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$config = Get-Content -LiteralPath $CandidateConfigPath -Raw | ConvertFrom-Json
$publicKey = [string]$config.plugins.updater.pubkey
$previousRoot = (Resolve-Path -LiteralPath $PreviousBundleRoot).Path
$candidateRoot = (Resolve-Path -LiteralPath $CandidateBundleRoot).Path

if ([version]$CandidateVersion -le [version]$PreviousVersion) {
    throw 'The candidate package version must be newer than the previous package version.'
}

& (Join-Path $PSScriptRoot 'verify-windows-release.ps1') `
    -BundleRoot $previousRoot `
    -ConfigPath $CandidateConfigPath `
    -MinisignPath $MinisignPath `
    -ExpectedVersion $PreviousVersion `
    -PublicKey $publicKey
& (Join-Path $PSScriptRoot 'verify-windows-release.ps1') `
    -BundleRoot $candidateRoot `
    -ConfigPath $CandidateConfigPath `
    -MinisignPath $MinisignPath

function Get-OnlyPackage([string]$Directory, [string]$Filter) {
    $packages = @(Get-ChildItem -LiteralPath $Directory -File -Filter $Filter)
    if ($packages.Count -ne 1) {
        throw "Expected one package matching $Filter in $Directory; found $($packages.Count)."
    }
    return $packages[0]
}

function Get-ZownloadInstallRecords {
    $uninstallRoots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    return Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'Zownload' }
}

function Get-ZownloadInstallRecord([string]$Version) {
    return Get-ZownloadInstallRecords |
        Where-Object { $_.DisplayVersion -eq $Version } |
        Select-Object -First 1
}

function Get-ZownloadExecutable($InstallRecord) {
    $locations = @()
    if ($InstallRecord.InstallLocation) { $locations += $InstallRecord.InstallLocation }
    if ($InstallRecord.DisplayIcon) {
        $iconPath = [string]$InstallRecord.DisplayIcon -replace ',\d+$', '' -replace '^"|"$', ''
        if (Test-Path -LiteralPath $iconPath) { return Get-Item -LiteralPath $iconPath }
    }
    $locations += @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Zownload'),
        (Join-Path $env:ProgramFiles 'Zownload')
    )
    if (${env:ProgramFiles(x86)}) { $locations += (Join-Path ${env:ProgramFiles(x86)} 'Zownload') }

    foreach ($location in $locations | Select-Object -Unique) {
        if (Test-Path -LiteralPath $location) {
            $candidates = @(Get-ChildItem -LiteralPath $location -File -Filter '*.exe' -Recurse |
                Where-Object { $_.Name -notmatch 'uninstall|webview' })
            $named = @($candidates | Where-Object { $_.Name -eq 'zownload.exe' })
            if ($named.Count -eq 1) { return $named[0] }
            if ($candidates.Count -eq 1) { return $candidates[0] }
        }
    }
    throw 'Could not locate the installed Zownload executable.'
}

function Invoke-Installer([System.IO.FileInfo]$Package, [string]$Format, [string]$Action, [string]$Version) {
    if ($Format -eq 'NSIS') {
        if ($Action -eq 'install') {
            $result = Start-Process -FilePath $Package.FullName -ArgumentList @('/S') -Wait -PassThru
        }
        else {
            $record = Get-ZownloadInstallRecord $Version
            if (!$record) { throw "Could not find the $Format installation to uninstall." }
            $installedExe = Get-ZownloadExecutable $record
            $uninstaller = Get-ChildItem -LiteralPath $installedExe.DirectoryName -File -Filter '*uninstall*.exe' -Recurse |
                Select-Object -First 1
            if (!$uninstaller) { throw 'Could not find the NSIS uninstaller.' }
            $result = Start-Process -FilePath $uninstaller.FullName -ArgumentList @('/S') -Wait -PassThru
        }
    }
    else {
        $verb = if ($Action -eq 'install') { '/i' } else { '/x' }
        $result = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList @($verb, ('"' + $Package.FullName + '"'), '/qn', '/norestart') `
            -Wait -PassThru
    }
    if ($result.ExitCode -notin @(0, 3010)) {
        throw "$Format $Action returned exit code $($result.ExitCode)."
    }
}

function Find-Button($Window, [string]$Name, [int]$TimeoutSeconds) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $buttonCondition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )
    while ([DateTime]::UtcNow -lt $deadline) {
        $buttons = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)
        foreach ($button in $buttons) {
            if ($button.Current.Name -eq $Name) { return $button }
        }
        Start-Sleep -Seconds 1
    }
    throw "Could not find the '$Name' button in the running app."
}

function Get-AppWindow($Process) {
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = [System.Windows.Automation.PropertyCondition]::new(
        [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
        $Process.Id
    )
    while ([DateTime]::UtcNow -lt $deadline) {
        $window = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
        if ($window) { return $window }
        Start-Sleep -Seconds 1
    }
    throw 'The Zownload window did not become available to Windows UI Automation.'
}

function Wait-ForInstalledVersion(
    [string]$Version,
    [int]$TimeoutSeconds = 120,
    [string]$DiagnosticContext = ''
) {
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $record = Get-ZownloadInstallRecord $Version
        if ($record) { return $record }
        Start-Sleep -Seconds 2
    }
    $records = @(Get-ZownloadInstallRecords | ForEach-Object {
        "$($_.DisplayVersion) at $($_.InstallLocation)"
    })
    if ($records.Count -eq 0) { $records = @('(no Zownload uninstall entries)') }
    throw "The installed package did not reach version $Version. $DiagnosticContext Current entries: $($records -join '; ')."
}

function Get-UpgradeInstallDiagnostics($ExpectedAppProcess) {
    $trackedProcess = '(tracked app process is unavailable)'
    $trackedProcessId = -1
    if ($ExpectedAppProcess) {
        $trackedProcessId = $ExpectedAppProcess.Id
        try {
            $current = Get-Process -Id $ExpectedAppProcess.Id -ErrorAction Stop
            $sameStartTime = $current.StartTime -eq $ExpectedAppProcess.StartTime
            $trackedProcess = "tracked PID $($ExpectedAppProcess.Id) name=$($current.ProcessName) path=$($current.Path) sameStartTime=$sameStartTime"
        }
        catch {
            $trackedProcess = "tracked PID $($ExpectedAppProcess.Id) has exited"
        }
    }

    $installEntries = @(Get-ZownloadInstallRecords | ForEach-Object {
        $record = $_
        try {
            $executable = Get-ZownloadExecutable $record
            $productVersion = if ($executable.VersionInfo.ProductVersion) { $executable.VersionInfo.ProductVersion } else { '(no file version)' }
            "$($record.DisplayVersion) at $($record.InstallLocation); exe=$($executable.FullName); productVersion=$productVersion"
        }
        catch {
            "$($record.DisplayVersion) at $($record.InstallLocation); executable lookup failed: $($_.Exception.Message)"
        }
    })
    if ($installEntries.Count -eq 0) { $installEntries = @('(no Zownload uninstall entries)') }

    $relatedProcesses = @(Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -eq $trackedProcessId -or
            $_.Name -match '(?i)zownload|msiexec|setup'
        } |
        Select-Object -First 12 ProcessId, ParentProcessId, Name, ExecutablePath, CommandLine |
        ConvertTo-Json -Compress -Depth 3)
    if ($relatedProcesses.Count -eq 0) { $relatedProcesses = @('(no related process details)') }

    return "Install entries: $($installEntries -join ' | '). $trackedProcess. Related processes: $($relatedProcesses -join ' ')"
}

function Clear-TestAppData {
    $appDataPath = Join-Path $env:LOCALAPPDATA 'com.zownload.app'
    if (Test-Path -LiteralPath $appDataPath) {
        $resolved = [IO.Path]::GetFullPath($appDataPath)
        $localAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\') + '\'
        if (!$resolved.StartsWith($localAppData, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove app data outside this hosted runner user profile.'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}

$nsisPrevious = Get-OnlyPackage (Join-Path $previousRoot 'nsis') '*-setup.exe'
$msiPrevious = Get-OnlyPackage (Join-Path $previousRoot 'msi') '*.msi'
$nsisCandidate = Get-OnlyPackage (Join-Path $candidateRoot 'nsis') '*-setup.exe'
$msiCandidate = Get-OnlyPackage (Join-Path $candidateRoot 'msi') '*.msi'
$fixtureDirectory = Join-Path $env:RUNNER_TEMP ('zownload-update-fixture-' + [guid]::NewGuid().ToString('N'))
$reportRows = [System.Collections.Generic.List[string]]::new()
$server = $null
$activeApp = $null

New-Item -ItemType Directory -Path $fixtureDirectory | Out-Null
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $FixturePort)
$listener.Start()
$listener.Stop()
$port = $FixturePort
$baseUrl = "http://127.0.0.1:$port"

try {
    foreach ($package in @($nsisCandidate, $msiCandidate)) {
        Copy-Item -LiteralPath $package.FullName -Destination $fixtureDirectory
    }

    $nsisSignature = [IO.File]::ReadAllText($nsisCandidate.FullName + '.sig').Trim()
    $msiSignature = [IO.File]::ReadAllText($msiCandidate.FullName + '.sig').Trim()
    $latest = [ordered]@{
        version = $CandidateVersion
        notes = 'Disposable Gate 3C installed-upgrade test.'
        pub_date = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        platforms = [ordered]@{
            'windows-x86_64-nsis' = [ordered]@{ signature = $nsisSignature; url = "$baseUrl/$($nsisCandidate.Name)" }
            'windows-x86_64-msi' = [ordered]@{ signature = $msiSignature; url = "$baseUrl/$($msiCandidate.Name)" }
        }
    }
    $latestPath = Join-Path $fixtureDirectory 'latest.json'
    $latest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestPath -Encoding utf8

    $serverLog = Join-Path $fixtureDirectory 'server-error.log'
    $serverOutput = Join-Path $fixtureDirectory 'server-output.log'
    $fixtureServerScript = Join-Path $PSScriptRoot 'windows-updater-fixture-server.py'
    $server = Start-Process -FilePath 'python.exe' `
        -ArgumentList @(
            ('"' + $fixtureServerScript + '"'),
            '--port', [string]$port,
            '--bind', '127.0.0.1',
            '--directory', ('"' + $fixtureDirectory + '"')
        ) `
        -WorkingDirectory $fixtureDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $serverOutput -RedirectStandardError $serverLog

    $response = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri "$baseUrl/latest.json" -UseBasicParsing
            break
        }
        catch { Start-Sleep -Seconds 1 }
    }
    if (!$response -or $response.StatusCode -ne 200) {
        throw 'The local updater fixture server did not return latest.json.'
    }

    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes

    foreach ($scenario in @(
        [pscustomobject]@{ Format = 'NSIS'; Previous = $nsisPrevious; Candidate = $nsisCandidate; Other = $msiCandidate },
        [pscustomobject]@{ Format = 'MSI'; Previous = $msiPrevious; Candidate = $msiCandidate; Other = $nsisCandidate }
    )) {
        Clear-TestAppData
        if (Get-ZownloadInstallRecord $PreviousVersion) {
            throw "A Zownload installation existed before the $($scenario.Format) clean-install scenario."
        }

        Invoke-Installer $scenario.Previous $scenario.Format 'install' $PreviousVersion
        $previousRecord = Wait-ForInstalledVersion $PreviousVersion
        $previousExe = Get-ZownloadExecutable $previousRecord
        $activeApp = Start-Process -FilePath $previousExe.FullName -WorkingDirectory $previousExe.DirectoryName -PassThru
        $window = Get-AppWindow $activeApp
        $settingsButton = Find-Button $window 'Settings' 45
        $settingsButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        $updateButton = Find-Button $window 'Update Zownload' 60
        $updateButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()

        $expectedRequest = '/' + $scenario.Candidate.Name
        $otherRequest = '/' + $scenario.Other.Name
        $deadline = [DateTime]::UtcNow.AddSeconds(120)
        do {
            Start-Sleep -Seconds 2
            $serverRequests = if (Test-Path -LiteralPath $serverLog) { Get-Content -LiteralPath $serverLog -Raw } else { '' }
            $requestedExpected = $serverRequests.Contains($expectedRequest)
        } while (!$requestedExpected -and [DateTime]::UtcNow -lt $deadline)
        if (!$requestedExpected) {
            throw "$($scenario.Format) did not request its matching updater package."
        }
        if ($serverRequests.Contains($otherRequest)) {
            throw "$($scenario.Format) requested the other installer format."
        }

        $serverRequests = if (Test-Path -LiteralPath $serverLog) {
            (Get-Content -LiteralPath $serverLog -Tail 10) -join ' | '
        } else { '(no updater server log)' }
        $appProcess = if ($activeApp) {
            Get-Process -Id $activeApp.Id -ErrorAction SilentlyContinue
        } else { $null }
        $processState = if ($appProcess) { "app process $($appProcess.Id) is still running" } else { 'app process has exited' }
        try {
            # The package request is logged before its large response body
            # finishes downloading. Wait for the byte-counted transfer before
            # allowing time for Windows Installer to register the new version.
            $candidateRecord = $null
            $transferComplete = $false
            $downloadDeadline = [DateTime]::UtcNow.AddSeconds(600)
            do {
                $candidateRecord = Get-ZownloadInstallRecord $CandidateVersion
                if ($candidateRecord) { break }

                $serverRequests = if (Test-Path -LiteralPath $serverLog) {
                    Get-Content -LiteralPath $serverLog -Raw
                } else { '' }
                $transferComplete = $serverRequests.Contains("TRANSFER $expectedRequest complete bytes=")
                if ($transferComplete) { break }
                Start-Sleep -Seconds 2
            } while ([DateTime]::UtcNow -lt $downloadDeadline)

            if (!$candidateRecord -and !$transferComplete) {
                throw "$($scenario.Format) updater package transfer did not complete within 600 seconds."
            }
            if (!$candidateRecord) {
                $candidateRecord = Wait-ForInstalledVersion $CandidateVersion 180 `
                    "Format $($scenario.Format); package transfer completed; $processState."
            }
        }
        catch {
            $serverRequests = if (Test-Path -LiteralPath $serverLog) {
                (Get-Content -LiteralPath $serverLog -Tail 20) -join ' | '
            } else { '(no updater server log)' }
            $installDiagnostics = Get-UpgradeInstallDiagnostics $activeApp
            throw "$($_.Exception.Message) $installDiagnostics Latest updater server log: $serverRequests."
        }
        if (Get-ZownloadInstallRecord $PreviousVersion) {
            throw "$($scenario.Format) update left the previous-version uninstall entry in place."
        }
        $activeApp = Get-Process -Id $activeApp.Id -ErrorAction SilentlyContinue
        if ($activeApp) { Stop-Process -Id $activeApp.Id -Force -ErrorAction SilentlyContinue }
        $activeApp = $null
        $candidateExe = Get-ZownloadExecutable $candidateRecord
        $activeApp = Start-Process -FilePath $candidateExe.FullName -WorkingDirectory $candidateExe.DirectoryName -PassThru
        $null = Get-AppWindow $activeApp
        $relaunchVersion = (Get-ZownloadInstallRecord $CandidateVersion).DisplayVersion
        if ($relaunchVersion -ne $CandidateVersion) {
            throw "$($scenario.Format) relaunch reported version $relaunchVersion instead of $CandidateVersion."
        }
        if ($candidateExe.VersionInfo.ProductVersion -and !$candidateExe.VersionInfo.ProductVersion.StartsWith($CandidateVersion)) {
            throw "$($scenario.Format) executable reports version $($candidateExe.VersionInfo.ProductVersion)."
        }
        Stop-Process -Id $activeApp.Id -Force -ErrorAction SilentlyContinue
        $activeApp = $null

        Invoke-Installer $scenario.Candidate $scenario.Format 'uninstall' $CandidateVersion
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while ((Get-ZownloadInstallRecord $CandidateVersion) -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Seconds 2
        }
        if (Get-ZownloadInstallRecord $CandidateVersion) {
            throw "$($scenario.Format) uninstall left an installed-app registry entry."
        }
        Clear-TestAppData
        $reportRows.Add("| $($scenario.Format) | Pass ($PreviousVersion) | Pass | Pass ($($scenario.Candidate.Name)) | Pass ($CandidateVersion) | Pass |")
        Write-Output "$($scenario.Format): clean install, matching updater, relaunch, and uninstall passed."
    }

    $requestLog = Get-Content -LiteralPath $serverLog -Raw
    if (!$requestLog.Contains('/latest.json')) {
        throw 'The installed apps did not request the signed updater metadata.'
    }

    $evidenceFile = Join-Path $repoRoot $EvidencePath
    New-Item -ItemType Directory -Path (Split-Path -Parent $evidenceFile) -Force | Out-Null
    $evidence = [System.Collections.Generic.List[string]]::new()
    @(
        '<!-- SPDX-License-Identifier: GPL-3.0-or-later -->',
        '<!-- SPDX-FileCopyrightText: 2026 zahidzta -->',
        '',
        '# Gate 3C-03 — installed Windows upgrade evidence',
        '',
        "- Previous source ref: ``$PreviousRef`` (package version $PreviousVersion).",
        "- Candidate source ref: ``$CandidateRef`` (package version $CandidateVersion).",
        '- Environment: disposable `windows-latest` GitHub Actions runner; VBSCRIPT enabled; local signed updater fixture; no public release used.',
        '- Admin prompts: silent NSIS and MSI scenarios completed on the isolated runner; no interactive prompt was shown.',
        '',
        '| Format | Clean install and launch | Same-format updater | Matching package selected | Post-update relaunch/version | Uninstall and cleanup |',
        '|---|---|---|---|---|'
    ) | ForEach-Object { $evidence.Add([string]$_) }
    foreach ($row in $reportRows) { $evidence.Add($row) }
    [IO.File]::WriteAllLines($evidenceFile, $evidence.ToArray(), [Text.UTF8Encoding]::new($false))
    Write-Output "Evidence written to $EvidencePath."
}
finally {
    if ($activeApp) { Stop-Process -Id $activeApp.Id -Force -ErrorAction SilentlyContinue }
    if ($server) { Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue }

    $remainingRecords = @()
    $previousRecord = Get-ZownloadInstallRecord $PreviousVersion
    $candidateRecord = Get-ZownloadInstallRecord $CandidateVersion
    if ($previousRecord) { $remainingRecords += $previousRecord }
    if ($candidateRecord) { $remainingRecords += $candidateRecord }
    foreach ($record in $remainingRecords) {
        if ($record) {
            $format = if ($record.UninstallString -match 'msiexec') { 'MSI' } else { 'NSIS' }
            if ($format -eq 'MSI' -and $record.UninstallString -match '\{[A-Fa-f0-9-]{36}\}') {
                Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/x', $matches[0], '/qn', '/norestart') -Wait -ErrorAction SilentlyContinue
            }
            elseif ($format -eq 'NSIS') {
                $install = Get-ZownloadExecutable $record
                $uninstaller = Get-ChildItem -LiteralPath $install.DirectoryName -File -Filter '*uninstall*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($uninstaller) { Start-Process -FilePath $uninstaller.FullName -ArgumentList @('/S') -Wait -ErrorAction SilentlyContinue }
            }
        }
    }

    $fixtureFullPath = [IO.Path]::GetFullPath($fixtureDirectory)
    $runnerTemp = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
    if ($fixtureFullPath.StartsWith($runnerTemp, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $fixtureFullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
