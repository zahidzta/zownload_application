# Download only missing files from the source lock, then verify all bytes and signatures.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify-downloads.ps1') -FetchMissing
