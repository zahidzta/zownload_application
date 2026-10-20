# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repoRoot
try {
    $checks = @(
        @{ Name = 'frontend build and type check'; Command = 'npm'; Arguments = @('run', 'build') },
        @{ Name = 'TypeScript contract fixtures'; Command = 'npm'; Arguments = @('run', 'check:contracts') },
        @{ Name = 'Rust and contract tests'; Command = 'cargo'; Arguments = @('test', '--manifest-path', 'src-tauri/Cargo.toml') },
        @{ Name = 'design inventory'; Command = 'powershell'; Arguments = @('-NoProfile', '-File', 'scripts/check-design.ps1') }
    )

    foreach ($check in $checks) {
        Write-Output "Checking $($check.Name)..."
        $checkArguments = $check.Arguments
        & $check.Command @checkArguments
        if ($LASTEXITCODE -ne 0) {
            throw "$($check.Name) failed with exit code $LASTEXITCODE."
        }
    }

    Write-Output 'Foundation verification passed.'
}
finally {
    Pop-Location
}
