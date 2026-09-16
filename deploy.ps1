param(
    [string]$ModsRoot = 'D:\SteamLibrary\steamapps\common\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods'
)

if (-not (Test-Path -LiteralPath $ModsRoot)) {
    Write-Error "Mods root not found: $ModsRoot"
    exit 1
}

robocopy "$PSScriptRoot\scripts" "$ModsRoot\InsurancePolicyMod\scripts" /MIR /NFL /NDL /NJH /NJS
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed (scripts) with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

New-Item -ItemType Directory -Force -Path "$ModsRoot\InsurancePolicyMod" | Out-Null
Copy-Item -Force "$PSScriptRoot\mod.txt" "$ModsRoot\InsurancePolicyMod\mod.txt"

robocopy "$PSScriptRoot\shared\pd3lib" "$ModsRoot\shared\pd3lib" /MIR /NFL /NDL /NJH /NJS /XD .git /XF .git
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy failed (pd3lib) with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "deployed: InsurancePolicyMod + shared\pd3lib -> $ModsRoot"
