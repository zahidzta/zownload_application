# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

$ErrorActionPreference = 'Stop'

# Load only the log reader, without running installers or accessing app data.
$scriptPath = Join-Path $PSScriptRoot 'test-windows-upgrade.ps1'
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors) { throw "Upgrade script parse errors: $parseErrors" }
$reader = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-UpdaterScenarioLog'
}, $false)
if (!$reader) { throw 'Missing scenario log reader.' }
. ([scriptblock]::Create($reader.Extent.Text))

$logPath = Join-Path ([IO.Path]::GetTempPath()) ('zownload-upgrade-log-' + [guid]::NewGuid().ToString('N') + '.log')
$nsis = '/Zownload_0.0.1_x64-setup.exe'
$msi = '/Zownload_0.0.1_x64_en-US.msi'
try {
    if ((Get-UpdaterScenarioLog $logPath 0) -ne '') { throw 'Missing logs must read as empty.' }
    Set-Content -LiteralPath $logPath -Value @(
        "GET $nsis HTTP/1.1 200",
        "TRANSFER $nsis complete bytes=100",
        "TRANSFER $msi complete bytes=100"
    )
    $startLine = @(Get-Content -LiteralPath $logPath).Count
    if ((Get-UpdaterScenarioLog $logPath $startLine) -ne '') {
        throw 'Earlier package requests or completed transfers leaked into the new scenario.'
    }

    Add-Content -LiteralPath $logPath -Value "GET $msi HTTP/1.1 200"
    $requests = Get-UpdaterScenarioLog $logPath $startLine
    if (!$requests.Contains($msi) -or $requests.Contains($nsis)) {
        throw 'The MSI scenario must see its own request without the earlier NSIS request.'
    }
    if ($requests.Contains("TRANSFER $msi complete bytes=")) {
        throw 'The current transfer was incorrectly marked complete by an older log entry.'
    }
    Add-Content -LiteralPath $logPath -Value "TRANSFER $msi complete bytes=200"
    if (!(Get-UpdaterScenarioLog $logPath $startLine).Contains("TRANSFER $msi complete bytes=200")) {
        throw 'The current completed transfer was lost.'
    }
    Add-Content -LiteralPath $logPath -Value "GET $nsis HTTP/1.1 200"
    if (!(Get-UpdaterScenarioLog $logPath $startLine).Contains($nsis)) {
        throw 'A wrong-format request in the current scenario must remain detectable.'
    }
    Write-Output 'Updater scenario log isolation passed; current wrong-format requests remain detectable.'
}
finally {
    if (Test-Path -LiteralPath $logPath) { Remove-Item -LiteralPath $logPath }
}
