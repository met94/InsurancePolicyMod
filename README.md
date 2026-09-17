# InsurancePolicyMod

Solo helper for the "Insurance Policy" achievement (Touch The Sky, 4 human shields on
Hard+ — impossible solo). Watches for the solo version of the condition (escaping while
actively holding a human shield, Very Hard+) and completes the achievement through the
game's own APIs.

## Requirements

- PAYDAY 3.
- [PD3 UE4SS V3.01 + Allow Pak Mods](https://modworkshop.net/mod/47771) installed.
- Nothing else — the [`pd3lib`](https://github.com/met94/pd3lib) helper library is bundled
  inside the mod zip.

## Install (players)

1. Download `InsurancePolicyMod-<version>.zip` (ModWorkshop).
2. Open the zip.
3. Drag the `InsurancePolicyMod` folder into:

   ```
   ...\PAYDAY3\PAYDAY3\Binaries\Win64\ue4ss\Mods
   ```

   Xbox App for PC: `...\Payday 3\Content\PAYDAY3\Binaries\WinGDK\ue4ss\Mods`.
4. Launch the game. The mod is enabled automatically (`enabled.txt` in the mod folder).

If it does not load, open `...\Mods\mods.txt` and add a line above the keybinds, then restart:

```
InsurancePolicyMod : 1
```

## Usage

1. Start **Touch The Sky** on **Very Hard** or above.
2. Grab a civilian as a human shield (hold the interact key).
3. Walk into the escape while still holding them.
4. The achievement pops on Steam/console.

The mod does everything by itself; there is nothing to configure. Note: local challenge map
status does not refresh mid-session after an unlock — treat the Steam/platform UI as the
source of truth.

## Auto condition

Unlocks on the first 1 s poll where the player is physically inside the escape volume
(`PlayersInEscapeVolume > 0`), is *actively holding a human shield* (`HumanShieldInstigatorState`
numerically 3/4), difficulty >= Very Hard and heist ref matches — while the shield is demonstrably
in hand, not after the fact. Non-numeric shield reads (mission-end pawn transitions) never
count as held, and merely having the escape window open elsewhere does not count. On an
attempt, every configured lever fires in order — three `CompleteAchievement` candidates
(Steam hashed key, AccelByte code, challenge name) then the OSS write — so a forced unlock
may issue several writes in one pass; `ok=true` only means the call dispatched, not that the
platform accepted it. `RequestMissionEnd` remains a fallback retry; a single unlock attempt
is made per session.

Console markers, always logged:

- `*** InsurancePolicy: attempting unlock (poll) ... ***` — fires mid-escape while the shield is held
- `*** InsurancePolicy: unlock requested via ... - verify in game/Steam ... ***`

Only with `Config.Debug = true`:

- `*** InsurancePolicy: condition latched ... ***`
- `*** InsurancePolicy: condition cleared ... ***`
- `*** InsurancePolicy status (level-init|return-to-menu): ... ***`

Per-lever detail (candidate names, OSS result, postcheck) is diagnostic output behind
`Config.Debug`.

## Config (`scripts/main.lua`, top)

```lua
Config = {
    HeistRef = "penthouse",     -- gate on heist ref, not level name ("Sky")
    MinDifficulty = 2,          -- 2 = Very Hard
    AutoUnlock = true,          -- condition path
    Debug = false,              -- true: verbose diagnostics in the UE4SS console
    UnlockLevers = { "complete", "oss" },
}
```

`TARGET_ACH_CODE = "ACH_PH_HUMAN_SHIELD_EXTRACT"`, target challenge name and discovery
needles are constants next to it.

## For developers

```
git submodule update --init
.\deploy.ps1      # dev: mirrors the mod + vendored pd3lib into Mods\InsurancePolicyMod
.\release.ps1     # build: dist/InsurancePolicyMod-<version>.zip for players
```

Both copy `shared/pd3lib` into the mod's own `scripts` folder (`scripts/pd3lib.lua` +
`scripts/pd3lib/`), so the dev install and the release zip use the same layout and the mod is
fully self-contained. `release.ps1` also adds the empty `enabled.txt` marker for zero-config
loading.

Full write-up (including the removed discovery dumps): [`docs/insurance-policy.md`](docs/insurance-policy.md).
Workshop page copy: [`docs/workshop.md`](docs/workshop.md).
