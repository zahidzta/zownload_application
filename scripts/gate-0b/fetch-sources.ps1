# Download only missing files, including the locked zlib source, then verify
# every archive against its attested bytes and the available signatures.
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify-downloads.ps1') -FetchMissing
