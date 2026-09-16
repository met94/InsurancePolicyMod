# InsurancePolicyMod

Solo helper for the "Insurance Policy" achievement (Touch The Sky, 4 human shields on
Hard+ — impossible solo). Detects a proxy condition (escape with a human shield held on
Hard+, heist `penthouse`) and completes the achievement through the game's own APIs.

## Keybinds

| Key | Action |
|---|---|
| F1 | Read the `DA_InsurancePolicy` criterion (stat code, difficulty, heist) |
| F2 | Probe unlock levers (managers, maps, challenge->achievement codes) |
| F3 | Force unlock attempt (bypasses the condition; works in menu and in mission) |
| F4 | Dump condition state (difficulty, heist, escape timer, shield state, latch) |
| F9 | Reflection dump (mission + criterion + challenge/stat structs) |

F5-F8 belong to HumanShieldMod, F10 is the pd3lib selftest.

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

Latches when the escape is active (`EscapeTimeLeft > 0` or `PlayersInEscapeVolume > 0`)
while the player holds a human shield (`HumanShieldInstigatorState` 3/4), then at mission
end (or `RequestMissionEnd`, deferred out of the hook) unlocks if difficulty >= Hard and
heist ref matches.

Console markers:

- `*** InsurancePolicy: condition latched ... ***`
- `*** InsurancePolicy: attempting unlock (...) ***`
- `*** InsurancePolicy: unlock requested via ... - verify in game/Steam ... ***`
- `*** InsurancePolicy status (level-init|return-to-menu): ... ***`

## Usage

1. Install: run `deploy.ps1` from the repo root (mirrors this mod and `shared/pd3lib`
   into `<PAYDAY3>/Binaries/Win64/ue4ss/Mods`), restart the game.
2. Re-test the condition path: Touch The Sky, Hard+, grab a civilian (HumanShieldMod F5),
   walk into the escape holding the shield. Watch for the `***` lines.
3. Force test without a heist: press F3 in the menu.

Note: local challenge map status does not refresh mid-session after an unlock — treat
Steam/platform UI as the source of truth.

Full write-up: `docs/insurance-policy.md`.
