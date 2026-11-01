# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 zahidzta

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$capabilities = @(Get-WindowsCapability -Online | Where-Object { $_.Name -match '(?i)VBScript' })
if ($capabilities.Count -eq 0) {
    throw 'The Windows image does not expose the VBScript Feature on Demand required by WiX.'
}

$capability = $capabilities | Select-Object -First 1
if ($capability.State -ne 'Installed') {
    Add-WindowsCapability -Online -Name $capability.Name | Out-Null
    $capability = Get-WindowsCapability -Online -Name $capability.Name
}
if ($capability.State -ne 'Installed') {
    throw 'The VBScript Feature on Demand could not be installed for WiX MSI bundling.'
}
if (!(Get-Command 'cscript.exe' -ErrorAction SilentlyContinue)) {
    throw 'VBScript is marked installed, but Windows Script Host is unavailable.'
}

Write-Output "VBScript Feature on Demand is installed: $($capability.Name)."
