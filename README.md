# InsurancePolicyMod

Solo helper for the "Insurance Policy" achievement (Touch The Sky, 4 human shields on
Hard+ — impossible solo). Detects a proxy condition (escape with a human shield held on
Hard+, heist `penthouse`) and completes the achievement through the game's own APIs.

## Requirements

- PAYDAY 3 with [PD3 UE4SS V3.01 + Allow Pak Mods](https://modworkshop.net/mod/47771).
- [`pd3lib`](https://github.com/met94/pd3lib) v2 — install it to `Mods/shared/pd3lib` (the
  bundled `deploy.ps1` handles this through the `shared/pd3lib` submodule).

## Install

1. Install PD3 UE4SS V3.01 + Allow Pak Mods.
2. Install [`pd3lib`](https://github.com/met94/pd3lib) into
   `...\PAYDAY3\Binaries\Win64\ue4ss\Mods\shared\pd3lib`.
3. Copy this mod's `scripts` folder and `mod.txt` into
   `...\PAYDAY3\Binaries\Win64\ue4ss\Mods\InsurancePolicyMod\`.

Or from a git clone: `git submodule update --init`, then run `deploy.ps1` (see below).

## Config (`scripts/main.lua`, top)

```lua
Config = {
    HeistRef = "penthouse",     -- gate on heist ref, not level name ("Sky")
    MinDifficulty = 1,          -- 1 = Hard
    AutoUnlock = true,          -- condition path
    UnlockLevers = { "complete", "oss" },
}
```

`TARGET_ACH_CODE = "ACH_PH_HUMAN_SHIELD_EXTRACT"`, target challenge name and discovery
needles are constants next to it.

## Auto condition

Unlocks on the first 1 s poll where the player is physically inside the escape volume
(`PlayersInEscapeVolume > 0`), is *actively holding a human shield* (`HumanShieldInstigatorState`
numerically 3/4), difficulty >= Hard and heist ref matches — while the shield is demonstrably
in hand, not after the fact. Non-numeric shield reads (mission-end pawn transitions) never
count as held, and merely having the escape window open elsewhere does not count. The unlock
chain stops at the first lever that succeeds, so a normal run produces a single achievement
write/popup; fallbacks run only when an earlier lever fails. `RequestMissionEnd` remains a
fallback retry; a single unlock attempt is made per session.

Console markers:

- `*** InsurancePolicy: condition latched ... ***`
- `*** InsurancePolicy: condition cleared ... ***`
- `*** InsurancePolicy: attempting unlock (poll) ... ***` — fires mid-escape while the shield is held
- `*** InsurancePolicy: unlock requested via ... - verify in game/Steam ... ***`
- `*** InsurancePolicy status (level-init|return-to-menu): ... ***`

## Usage

1. Install via `deploy.ps1` or the manual copy above, restart the game.
2. Re-test the condition path: Touch The Sky, Hard+, grab a civilian as a human shield,
   walk into the escape holding the shield. Watch for the `***` lines.

Note: local challenge map status does not refresh mid-session after an unlock — treat
Steam/platform UI as the source of truth.

Full write-up (including the removed discovery dumps): [`docs/insurance-policy.md`](docs/insurance-policy.md).
