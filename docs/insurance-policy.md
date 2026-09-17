# Insurance Policy (PD3 achievement) — solo unlock project

Goal: unlock the Steam/PS/Xbox achievement **Insurance Policy** (`Complete Touch The Sky
with 4 active human shields on Hard or above`) in solo play, where 4 human shields are
impossible.

## What the game actually checks

Read from the live criterion asset `DA_InsurancePolicy`
(`SBZStatisticCriteriaData`):

| Field | Value |
|---|---|
| `StatisticCode` | `penthouse-human-shield-extract` |
| `LowestDifficulty` | Hard (1) |
| `MinPassableState` / `MaxPassableState` | Stealth (0) / PointOfNoReturn (8) |
| flags | no-kill / all-loot / completion-time unused; `bHasLevelCriteria = false` |
| `HeistDataArray` | 1 entry, heist ref `penthouse` ("Touch the Sky") |

The stat is evaluated server/backend-side from progress accumulated by the game; solo
can only ever contribute 1 shield, so the native path can never complete. Note the level
name for Touch The Sky is `Sky`; the heist reference is `penthouse` — gate on the heist
ref, not the level.

## Unlock architecture (discovered via UE4SS dump + probes)

- Live `BP_ChallengeManager_C` and `SBZAchievementManager` live on `PD3_GameInstance_C`
  (transient objects, found with `FindAllOf`, skipping `Default__`).
- `AchievementMap` (88 entries) keys are hashed FNames; values are `FSBZChallengeData`.
  The target: key `64f5dd4f088b9a1e4d5f447a`, name `Achievement Steam Penthouse Human
  Shield Extract` (Xbox/PS/Epic variants share the same AccelByte code).
- `SBZChallengeToAchievementSettings.ChallengeToAchievementMap` (128 entries) maps
  challenge FName -> AccelByte code: `AchievementSteamPenthouseHumanShieldExtract` ->
  `ACH_PH_HUMAN_SHIELD_EXTRACT`.
- Completion call used: `SBZAchievementManager:CompleteAchievement(FName)`; fallback OSS
  proxy `AchievementWriteCallbackProxy:WriteAchievementProgress`.

## Crash post-mortems (all fixed)

1. `SBZChallengeManager:GetStatProgress(statId)` froze the game thread — removed.
2. Calling UFunction getters that return `TMap`/`TArray` **by value** ended in an engine
   crash — replaced with UPROPERTY reads.
3. Calling `CompleteAchievement` while a Lua hook was registered on the same UFunction
   re-entered the hook callback; inside it, `Safe.Describe` invoked object methods on an
   FName wrapper -> crash in UE4SS `push_nameproperty`. Fixes: hook removed, `Resolve`
   never invokes object methods on unknown wrappers, unlock deferred out of hook context.
4. Passing **Lua strings** where `FName` parameters were expected crashed argument
   marshalling on this UE4SS build. Fix: pre-build names with `pd3.safe.ToFName(text)`
   and pass the FName userdata (verified by an inert `MakeLiteralName` probe).

## Working unlock chain (as shipped)

Condition (client-side proxy, Hard + penthouse):

- poll every 1 s: `EscapeTimeLeft > 0` or `PlayersInEscapeVolume > 0`, **and** player
  `HumanShieldInstigatorState` in {3 Grabbing, 4 Choking} -> latch
- also sampled on `Multicast_SetEscapeVolumeData` and at `RequestMissionEnd` (deferred)

Unlock, in order:

1. `CompleteAchievement(AchievementMap key)` (Steam hashed key)
2. `CompleteAchievement("ACH_PH_HUMAN_SHIELD_EXTRACT")`
3. `CompleteAchievement("AchievementSteamPenthouseHumanShieldExtract")`
4. `AchievementWriteCallbackProxy:WriteAchievementProgress(..., 100.0, "")`

`Config.UnlockLevers` controls the order. All levers fire on an attempt — there is no early
stop on a successful dispatch (`ok=true` only means the call did not raise, not that the
platform accepted the write; 0.3.0 stopped after the first dispatch-ok lever and skipped the
writes that actually unlock). Status is confirmed via the achievement map (COMPLETED) when it
refreshes; the platform UI is authoritative.

## Result

Unlocked on 2026-09-16 via menu-side `F3` (force) after the crash fixes; all levers
returned `ok=true`, postcheck showed stale `INPROGRESS` (expected mid-session), and the
achievement appeared on the platform. The condition path (1 shield at escape, Hard+,
Touch The Sky) remains armed for re-testing.

## Files

- `scripts/main.lua` — the mod (see the README for keybinds)
- `shared/pd3lib/` — git submodule pinned to
  [met94/pd3lib](https://github.com/met94/pd3lib) v2.0.0 (`safe.ToFName`, `core.maps`,
  `core.reflect`, `game.challenge`, `game.mission`)
- `deploy.ps1` — mirrors the mod + pd3lib into the UE4SS `Mods` directory
