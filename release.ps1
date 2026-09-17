$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$Dist = Join-Path $Root 'dist'
$Name = 'InsurancePolicyMod'

$Meta = Get-Content -Raw -LiteralPath (Join-Path $Root 'mod.txt') | ConvertFrom-Json
$Version = $Meta.version
$Stage = Join-Path $Dist $Name
$Zip = Join-Path $Dist "$Name-$Version.zip"

$Pd3Lib = Join-Path $Root 'shared\pd3lib'

$Files = @(
    @{ Source = (Join-Path $Root 'mod.txt');              Dest = 'mod.txt' },
    @{ Source = (Join-Path $Root 'LICENSE.md');           Dest = 'LICENSE.md' },
    @{ Source = (Join-Path $Root 'scripts\main.lua');     Dest = 'scripts/main.lua' },
    @{ Source = (Join-Path $Pd3Lib 'pd3lib.lua');         Dest = 'scripts/pd3lib.lua' },
    @{ Source = (Join-Path $Pd3Lib 'selftest.lua');       Dest = 'scripts/pd3lib/selftest.lua' },
    @{ Source = (Join-Path $Pd3Lib 'LICENSE.md');         Dest = 'scripts/pd3lib/LICENSE.md' }
)

foreach ($Item in $Files) {
    if (-not (Test-Path -LiteralPath $Item.Source)) {
        Write-Error "missing required file: $($Item.Source)"
        exit 1
    }
}
foreach ($Dir in @('core', 'game')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Pd3Lib $Dir))) {
        Write-Error "missing required pd3lib directory: $Dir"
        exit 1
    }
}

if (Test-Path -LiteralPath $Stage) {
    Remove-Item -LiteralPath $Stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $Stage 'scripts\pd3lib') | Out-Null

foreach ($Item in $Files) {
    $Dest = Join-Path $Stage ($Item.Dest -replace '/', '\')
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Dest) | Out-Null
    Copy-Item -Force -LiteralPath $Item.Source -Destination $Dest
}
foreach ($Dir in @('core', 'game')) {
    Copy-Item -Recurse -Force -LiteralPath (Join-Path $Pd3Lib $Dir) -Destination (Join-Path $Stage 'scripts\pd3lib')
}

# Empty marker: UE4SS loads mods with enabled.txt without a mods.txt entry.
New-Item -ItemType File -Force -Path (Join-Path $Stage 'enabled.txt') | Out-Null

if (Test-Path -LiteralPath $Zip) {
    Remove-Item -Force -LiteralPath $Zip
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Build the archive manually with forward-slash entry names (Compress-Archive
# writes backslashes on Windows PowerShell 5.1, which is not zip-spec).
$Archive = [System.IO.Compression.ZipFile]::Open($Zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $Prefix = Split-Path -Leaf $Stage
    foreach ($File in (Get-ChildItem -LiteralPath $Stage -Recurse -File)) {
        $Relative = $File.FullName.Substring($Stage.Length + 1) -replace '\\', '/'
        $EntryName = "$Prefix/$Relative"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Archive, $File.FullName, $EntryName) | Out-Null
    }
} finally {
    $Archive.Dispose()
}

$Archive = [System.IO.Compression.ZipFile]::OpenRead($Zip)
try {
    $Entries = $Archive.Entries | ForEach-Object { $_.FullName }
} finally {
    $Archive.Dispose()
}

$Expected = @(
    'InsurancePolicyMod/mod.txt',
    'InsurancePolicyMod/LICENSE.md',
    'InsurancePolicyMod/enabled.txt',
    'InsurancePolicyMod/scripts/main.lua',
    'InsurancePolicyMod/scripts/pd3lib.lua',
    'InsurancePolicyMod/scripts/pd3lib/selftest.lua',
    'InsurancePolicyMod/scripts/pd3lib/LICENSE.md',
    'InsurancePolicyMod/scripts/pd3lib/core/log.lua',
    'InsurancePolicyMod/scripts/pd3lib/game/heist.lua',
    'InsurancePolicyMod/scripts/pd3lib/game/mission.lua'
)
foreach ($Entry in $Expected) {
    if ($Entries -notcontains $Entry) {
        Write-Error "zip is missing expected entry: $Entry"
        exit 1
    }
}

Write-Host "built: $Zip ($($Entries.Count) entries)"
$Entries | Sort-Object | ForEach-Object { Write-Host "  $_" }
