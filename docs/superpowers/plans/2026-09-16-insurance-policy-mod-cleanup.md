# InsurancePolicyMod Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip all discovery dumps/probes from `InsurancePolicyMod/scripts/main.lua`, keeping only achievement-unlock functionality, condition detection, and the regular `***` logging around them.

**Architecture:** Pure deletion + two small line edits in one Lua file; no API/behavior change to the unlock path. Condition detection (`ConditionState`, `MaybeLatch`, `CheckAndUnlock`), precheck/status (`ScanMapStatus`, `FindTargetKey`, `IsAlreadyUnlocked`), and unlock levers (`Unlock`, `RunCompleteCandidates`, `RunOssLever`) stay.

**Tech Stack:** Lua (UE4SS), pd3lib. No Lua toolchain on machine -> verification = static grep + diff review + in-game smoke test.

## Global Constraints

- Do NOT touch `shared/pd3lib`, `HumanShieldMod`, or `docs/insurance-policy.md` (historical record).
- Keep every `pd3.log.Info` line that reports condition/unlock progress, including the `*** InsurancePolicy ... ***` markers.
- Keep `Config`, `TARGET_*` constants, `SHIELD_STATE_NAMES`, F3 force-unlock bind.
- No new dependencies, no test framework (none exists in repo).

---

### Task 1: Remove dump/probe machinery from main.lua

**Files:**
- Modify: `InsurancePolicyMod/scripts/main.lua`

- [ ] **Step 1: Delete discovery comment + unused constant**

Delete lines 12-14 (`-- Discovery summary (F1/F2 logs): ...`) and line 24 (`local CRITERIA_ASSET = ...`).

- [ ] **Step 2: Delete dump-only helpers**

Delete whole blocks: `HasMethod` (50-54), `ReadField` (56-59), `GetCriterion` (61-67), `DumpCriterion` (69-136), `DumpMapSample` (138-157), `DumpMapKeys` (159-178), `KEY_NEEDLES` (180), `DumpNamePairs` (182-198), `DumpChallengeToAchievement` (200-214), `ProbeLevers` (253-293), `DumpCondition` (517-527), `DumpReflection` (535-560).

- [ ] **Step 3: Delete FName-marshalling probe**

Delete comment + function in `Unlock` (lines 357-374) and its call site (line 440).

`ProbeFNameMarshalling()` before `RunLevers()` is removed, leaving only `RunLevers()`.

- [ ] **Step 4: Drop unused `AchMgr` parameter of `IsAlreadyUnlocked`**

Signature (line 295) -> `local function IsAlreadyUnlocked()`; call sites line 333 and line 347 drop the argument.

- [ ] **Step 5: Trim Init + keybinds + load log**

Line 10 -> `pd3.Init({ prefix = "[" .. MOD_NAME .. "]" })`.

Keybind block (597-603) becomes:

```lua
pd3.keys.Bind(Key.F3, function() CheckAndUnlock("force key", true) end, "force unlock achievement")

pd3.log.Info("loaded. F3 force unlock")
```

- [ ] **Step 6: Verify no dangling references**

Run:
```powershell
Select-String -Path "InsurancePolicyMod\scripts\main.lua" -Pattern "DumpCriterion|ProbeLevers|DumpReflection|DumpCondition|ProbeFName|DumpMapSample|DumpMapKeys|DumpNamePairs|ReadField|HasMethod|GetCriterion|KEY_NEEDLES|CRITERIA_ASSET|DumpChallengeToAchievement"
```
Expected: no output.

- [ ] **Step 7: Review diff**

Run: `git diff -- InsurancePolicyMod/scripts/main.lua`
Expected: only deletions + the 4 edited lines; retained code untouched.

- [ ] **Step 8: Commit**

```powershell
git add InsurancePolicyMod/scripts/main.lua
git commit -m "refactor(InsurancePolicyMod): remove discovery dumps and probes"
```

### Task 2: Update mod docs

**Files:**
- Modify: `InsurancePolicyMod/README.md`
- Modify: `InsurancePolicyMod/mod.txt`

- [ ] **Step 1: README keybind table -> F3 only**

Replace F1/F2/F4/F9 rows with:

```markdown
| Key | Action |
|---|---|
| F3 | Force unlock attempt (bypasses the condition; works in menu and in mission) |
```

Keep the `F5-F8 belong to HumanShieldMod, F10 is the pd3lib selftest.` line. Update the trailing `Full write-up:` line to `Full write-up (including the removed discovery dumps): docs/insurance-policy.md`.

- [ ] **Step 2: mod.txt**

Bump `"version": "0.2.0"`; description -> `"Insurance Policy achievement helper: unlocks on a solo proxy condition (human shield held during escape, Hard+)"`.

- [ ] **Step 3: Commit**

```powershell
git add InsurancePolicyMod/README.md InsurancePolicyMod/mod.txt
git commit -m "docs(InsurancePolicyMod): drop removed keybinds from docs"
```

### Task 3: Deploy + in-game smoke test (manual, user-run)

- [ ] **Step 1: Deploy**

Run `.\deploy.ps1` from repo root (pass `-ModsRoot` if game path differs).

- [ ] **Step 2: Launch game, check UE4SS log**

Expected load lines: `[InsurancePolicyMod] pd3lib v2 loaded` and `[InsurancePolicyMod] loaded. F3 force unlock` - no Lua syntax/load error.

- [ ] **Step 3: Press F3 in menu**

Expected: `*** InsurancePolicy: attempting unlock (force key) ***` and `lever A.1 ... ok=...` lines, no crash. (Achievement already unlocked -> precheck may short-circuit; that's fine.)

- [ ] **Step 4 (optional): Condition path**

Touch The Sky Hard+, grab shield (HumanShieldMod F5), enter escape; expect `condition latched` then `attempting unlock`.
