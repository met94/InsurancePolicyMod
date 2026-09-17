param(
    [string]$ModsRoot = 'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods'
)

if (-not (Test-Path -LiteralPath $ModsRoot)) {
    Write-Error "Mods root not found: $ModsRoot"
    exit 1
}

$ModDir = "$ModsRoot\InsurancePolicyMod"
$ScriptsDir = "$ModDir\scripts"
$LibDir = "$ScriptsDir\pd3lib"
$Pd3Lib = "$PSScriptRoot\shared\pd3lib"

# /XD pd3lib + /XF pd3lib.lua keep the vendored library intact between deploys.
robocopy "$PSScriptRoot\scripts" $ScriptsDir /MIR /NFL /NDL /NJH /NJS /XD pd3lib /XF pd3lib.lua
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed (scripts) with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force -Path $LibDir | Out-Null

# Vendored pd3lib: same layout as the release zip (scripts\pd3lib.lua + scripts\pd3lib\).
Copy-Item -Force "$Pd3Lib\pd3lib.lua" "$ScriptsDir\pd3lib.lua"
Copy-Item -Force "$Pd3Lib\selftest.lua" "$LibDir\selftest.lua"
Copy-Item -Force "$Pd3Lib\LICENSE.md" "$LibDir\LICENSE.md"

foreach ($Sub in @('core', 'game')) {
    robocopy "$Pd3Lib\$Sub" "$LibDir\$Sub" /MIR /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) {
        Write-Error "robocopy failed (pd3lib\$Sub) with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

Copy-Item -Force "$PSScriptRoot\mod.txt" "$ModDir\mod.txt"

Write-Host "deployed: InsurancePolicyMod (vendored pd3lib) -> $ModDir"
