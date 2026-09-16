local MOD_NAME = "InsurancePolicyMod"

local OkLib, pd3lib = pcall(require, "pd3lib")
if not OkLib or pd3lib == nil then
    print(string.format("[%s] pd3lib load failed: %s\n", MOD_NAME, tostring(pd3lib)))
    return
end

local pd3 = pd3lib
pd3.Init({ prefix = "[" .. MOD_NAME .. "]", debug = true })

-- Discovery summary (F1/F2 logs):
--   criterion StatisticCode = penthouse-human-shield-extract, heist ref = penthouse
--   challenge -> achievement: AchievementSteamPenthouseHumanShieldExtract -> ACH_PH_HUMAN_SHIELD_EXTRACT
local Config = {
    HeistRef = "penthouse",
    MinDifficulty = 1, -- ESBZDifficulty: Normal=0, Hard=1, VeryHard=2, Overkill=3
    AutoUnlock = true,
    -- Order of unlock levers: "complete" = SBZAchievementManager:CompleteAchievement,
    -- "oss" = AchievementWriteCallbackProxy. Flip to { "oss", "complete" } if needed.
    UnlockLevers = { "complete", "oss" },
}

local CRITERIA_ASSET = "/Game/Gameplay/Data/StatisticData/DA_InsurancePolicy.DA_InsurancePolicy"
local TARGET_ACH_CODE = "ACH_PH_HUMAN_SHIELD_EXTRACT"
local TARGET_CHALLENGE_NAME = "AchievementSteamPenthouseHumanShieldExtract"
local TARGET_NAME_NEEDLES = { "penthouse human shield", "penthouse-human-shield" }

local SHIELD_STATE_NAMES = {
    [0] = "None", [1] = "ReachingSlot", [2] = "EnterGrabbing", [3] = "Grabbing",
    [4] = "Choking", [5] = "Exiting",
}

local State = {
    latched = false,
    unlocked = false,
    unlockedVia = nil,
    unlocking = false,
}

local PendingTargetKey = nil

local function Name(Value, Map)
    if type(Value) == "number" and Map ~= nil then
        return string.format("%s(%d)", Map[Value] or "?", Value)
    end
    return tostring(Value)
end

local function HasMethod(Obj, MethodName)
    if Obj == nil then return false end
    local Ok, Method = pcall(function() return Obj[MethodName] end)
    return Ok and Method ~= nil
end

local function ReadField(Obj, Field)
    if Obj == nil then return nil end
    return pd3.safe.Resolve(pd3.safe.Get(Obj, Field))
end

local function GetCriterion()
    local Criteria = pd3.mission.Criterion("InsurancePolicy")
    if Criteria ~= nil then return Criteria, "mission-state" end
    local Ok, Asset = pcall(StaticFindObject, CRITERIA_ASSET)
    if Ok and pd3.safe.IsValid(Asset) then return Asset, "asset" end
    return nil, "not-found"
end

local function DumpCriterion()
    pd3.log.Info("=== F1 criterion read ===")
    local Criteria, Source = GetCriterion()
    pd3.log.Info("criterion source: %s", Source)
    if Criteria == nil then
        pd3.log.Warn("DA_InsurancePolicy not found")
        return
    end

    pd3.log.Info("asset: %s", pd3.safe.Describe(Criteria))
    pd3.log.Info("StatisticCode=%s", pd3.safe.String(ReadField(Criteria, "StatisticCode")))
    pd3.log.Info("LowestDifficulty=%s MinState=%s MaxState=%s",
        Name(ReadField(Criteria, "LowestDifficulty"), pd3.mission.DifficultyNames),
        Name(ReadField(Criteria, "MinPassableState"), pd3.mission.HeistStateNames),
        Name(ReadField(Criteria, "MaxPassableState"), pd3.mission.HeistStateNames))
    pd3.log.Info("flags: NoKill=%s AllLoot=%s UseCompletionTime=%s CompletionTime=%s HasLevelCriteria=%s",
        pd3.safe.String(ReadField(Criteria, "bRequiresNoKill")),
        pd3.safe.String(ReadField(Criteria, "bRequiresAllLoot")),
        pd3.safe.String(ReadField(Criteria, "bUseCompletionTime")),
        pd3.safe.String(ReadField(Criteria, "CompletionTime")),
        pd3.safe.String(ReadField(Criteria, "bHasLevelCriteria")))

    local Heists = ReadField(Criteria, "HeistDataArray")
    local HeistCount = pd3.safe.ArrayCount(Heists)
    if HeistCount ~= nil then
        pd3.log.Info("HeistDataArray count=%d", HeistCount)
        for i = 1, HeistCount do
            local Heist = Heists[i]
            if pd3.safe.IsValid(Heist) then
                local OkRef, Ref = pd3.safe.CallFn(Heist, "GetHeistReferenceText")
                pd3.log.Info("  heist[%d] ref=%s name=%s", i,
                    OkRef and pd3.safe.String(Ref) or "?",
                    pd3.safe.Text(pd3.safe.Get(Heist, "HeistDisplayName")))
            else
                pd3.log.Info("  heist[%d] invalid", i)
            end
        end
    else
        pd3.log.Warn("HeistDataArray unreadable")
    end

    local Mission = pd3.mission.Get()
    if Mission == nil then
        pd3.log.Info("no live mission state (in menu?)")
        return
    end

    local Difficulty = pd3.mission.Difficulty(Mission)
    local Escape = pd3.mission.Escape(Mission)
    pd3.log.Info("mission: difficulty=%s heistRef=%s escapeLeft=%s playersInEscape=%s/%s",
        Name(Difficulty, pd3.mission.DifficultyNames), tostring(pd3.mission.HeistRef(Mission)),
        tostring(Escape.TimeLeft), tostring(Escape.PlayersIn), tostring(Escape.PlayersRequired))

    local HeistData = pd3.mission.HeistData(Mission)
    local MissionCriteria = pd3.safe.Get(HeistData, "StatisticCriteriaDataArray")
    local CriteriaCount = pd3.safe.ArrayCount(MissionCriteria)
    if CriteriaCount ~= nil then
        pd3.log.Info("heist StatisticCriteriaDataArray count=%d", CriteriaCount)
        for i = 1, math.min(CriteriaCount, 20) do
            pd3.log.Info("  criteria[%d] StatisticCode=%s", i, pd3.safe.String(ReadField(MissionCriteria[i], "StatisticCode")))
        end
    end

    -- ChallengeManager:GetStatProgress freezes the game thread for unknown stat ids
    -- (same hazard class as ModeArray reads). Do not call; stat id is read above.
    pd3.log.Info("stat progress lookup skipped (engine freeze)")
    pd3.log.Info("=== F1 done ===")
end

local function DumpMapSample(Map, Label, MaxLines)
    local Shown = 0
    local Ok = pd3.maps.ForEach(Map, function(Key, V)
        Shown = Shown + 1
        if Shown <= MaxLines then
            local Record = pd3.safe.Resolve(V)
            pd3.log.Info("%s[%d] key=%s record=%s", Label, Shown, pd3.safe.String(Key), pd3.safe.Describe(Record))
            pd3.challenge.DumpRecord(string.format("%s[%d]", Label, Shown), Record)
            local Tags = ReadField(Record, "Tags")
            local TagCount = pd3.safe.ArrayCount(Tags)
            if TagCount ~= nil and TagCount > 0 then
                local Parts = {}
                for i = 1, math.min(TagCount, 5) do Parts[i] = pd3.safe.String(Tags[i]) end
                pd3.log.Info("%s[%d] tags=%s", Label, Shown, table.concat(Parts, ","))
            end
        end
    end)
    if not Ok then pd3.log.Warn("%s sample failed", Label) end
    pd3.log.Info("%s sample entries=%d", Label, Shown)
end

local function DumpMapKeys(Map, Label, Needles, MaxLines)
    local Shown, Printed = 0, 0
    pd3.maps.ForEach(Map, function(Key, V)
        Shown = Shown + 1
        local Record = pd3.safe.Resolve(V)
        local Id = pd3.safe.String(ReadField(Record, "ChallengeId"))
        local ChallengeName = pd3.safe.String(ReadField(Record, "ChallengeName"))
        local Line = string.format("key=%s | id=%s | name=%s", pd3.safe.String(Key), Id, ChallengeName)
        local Lower = string.lower(Line)
        local Hit = false
        for _, Needle in ipairs(Needles) do
            if string.find(Lower, Needle, 1, true) then Hit = true; break end
        end
        if Hit or Shown <= MaxLines then
            Printed = Printed + 1
            pd3.log.Info("%s: %s", Label, Line)
        end
    end)
    pd3.log.Info("%s entries=%d printed=%d", Label, Shown, Printed)
end

local KEY_NEEDLES = { "insur", "penthouse", "human", "shield", "extract" }

local function DumpNamePairs(Map, Label, Needles, MaxLines)
    local Shown, Printed = 0, 0
    pd3.maps.ForEach(Map, function(Key, V)
        Shown = Shown + 1
        local Line = string.format("%s -> %s", pd3.safe.String(Key), pd3.safe.String(V))
        local Lower = string.lower(Line)
        local Hit = false
        for _, Needle in ipairs(Needles) do
            if string.find(Lower, Needle, 1, true) then Hit = true; break end
        end
        if Hit or Shown <= MaxLines then
            Printed = Printed + 1
            pd3.log.Info("%s: %s", Label, Line)
        end
    end)
    pd3.log.Info("%s entries=%d printed=%d", Label, Shown, Printed)
end

local function DumpChallengeToAchievement()
    local OkFind, Settings = pcall(StaticFindObject, pd3.challenge.SettingsClassPath)
    if not OkFind or not pd3.safe.IsValid(Settings) then
        pd3.log.Warn("SBZChallengeToAchievementSettings CDO not found")
        return
    end
    -- Property read only: the getter returns a TMap by value (see docs hazards).
    local Map = pd3.safe.Resolve(pd3.safe.Get(Settings, "ChallengeToAchievementMap"))
    if Map == nil then
        pd3.log.Warn("no ChallengeToAchievementMap available")
        return
    end
    pd3.log.Info("ChallengeToAchievementMap size=%s", tostring(pd3.maps.Size(Map)))
    DumpNamePairs(Map, "challengeToAchievement", KEY_NEEDLES, 140)
end

local function TargetMatch(Key, Id, ChallengeName)
    local Haystack = string.lower(tostring(Key) .. " " .. tostring(Id) .. " " .. tostring(ChallengeName))
    if string.find(Haystack, string.lower(TARGET_ACH_CODE), 1, true) then return true end
    for _, Needle in ipairs(TARGET_NAME_NEEDLES) do
        if string.find(Haystack, Needle, 1, true) then return true end
    end
    return false
end

local function FindTargetKey()
    local Found = nil
    for _, Summary in ipairs(pd3.challenge.Find(nil, "penthouse human shield")) do
        pd3.log.Info("target achievement: key=%s name=%s status=%s",
            Summary.Key, Summary.ChallengeName, pd3.challenge.StatusName(Summary.Status))
        if Found == nil and string.find(string.lower(Summary.ChallengeName), "steam", 1, true) then
            Found = Summary.Key
        end
    end
    return Found
end

local function ScanMapStatus(Map, Label)
    local Found = nil
    if Map == nil then return nil end
    pd3.maps.ForEach(Map, function(Key, Value)
        local Summary = pd3.challenge.RecordSummary(Key, Value)
        if TargetMatch(Summary.Key, Summary.ChallengeId, Summary.ChallengeName) then
            pd3.log.Info("target[%s] key=%s name=%s status=%s", Label,
                Summary.Key, Summary.ChallengeName, pd3.challenge.StatusName(Summary.Status))
            if Summary.Status == pd3.challenge.CompletedStatus then
                Found = string.format("%s key=%s name=%s", Label, Summary.Key, Summary.ChallengeName)
            end
        end
    end)
    return Found
end

local function ProbeLevers()
    pd3.log.Info("=== F2 lever probe ===")

    local AchMgr, AchName = pd3.challenge.AchievementManager()
    pd3.log.Info("SBZAchievementManager live=%s name=%s", tostring(AchMgr ~= nil), tostring(AchName))
    if AchMgr ~= nil then
        pd3.log.Info("CompleteAchievement available=%s", tostring(HasMethod(AchMgr, "CompleteAchievement")))
    end

    local ChallengeManager, ChallengeName = pd3.challenge.Manager()
    pd3.log.Info("BP_ChallengeManager_C live=%s name=%s", tostring(ChallengeManager ~= nil), tostring(ChallengeName))
    if ChallengeManager ~= nil then
        local AchMap = pd3.challenge.Achievements(ChallengeManager)
        local ChalMap = pd3.challenge.AllChallenges(ChallengeManager)
        pd3.log.Info("AchievementMap size=%s", tostring(pd3.maps.Size(AchMap)))
        DumpMapSample(AchMap, "AchievementMap", 3)
        DumpMapKeys(AchMap, "AchievementMap", KEY_NEEDLES, 90)
        ScanMapStatus(AchMap, "AchievementMap")
        pd3.log.Info("ChallengeMap size=%s", tostring(pd3.maps.Size(ChalMap)))
        DumpMapSample(ChalMap, "ChallengeMap", 3)
        DumpMapKeys(ChalMap, "ChallengeMap", KEY_NEEDLES, 0)
        ScanMapStatus(ChalMap, "ChallengeMap")
    end

    PendingTargetKey = FindTargetKey()
    pd3.log.Info("target steam key: %s", tostring(PendingTargetKey))

    DumpChallengeToAchievement()

    local OkProxy, Proxy = pcall(StaticFindObject, "/Script/OnlineSubsystemUtils.Default__AchievementWriteCallbackProxy")
    pd3.log.Info("OSS AchievementWriteCallbackProxy CDO=%s", tostring(OkProxy and pd3.safe.IsValid(Proxy)))

    local ApiClient, ApiClientName = pd3.world.FindLive("ABApiClient")
    pd3.log.Info("ABApiClient live=%s name=%s", tostring(ApiClient ~= nil), tostring(ApiClientName))
    if ApiClient ~= nil then
        local Achievement = pd3.safe.Get(ApiClient, "Achievement")
        pd3.log.Info("ABApiClient.Achievement=%s", pd3.safe.Describe(Achievement))
    end

    pd3.log.Info("=== F2 done ===")
end

local function IsAlreadyUnlocked(AchMgr)
    local ChallengeManager = pd3.challenge.Manager()
    if ChallengeManager ~= nil then
        local Found = ScanMapStatus(pd3.challenge.Achievements(ChallengeManager), "AchievementMap")
            or ScanMapStatus(pd3.challenge.AllChallenges(ChallengeManager), "ChallengeMap")
        if Found ~= nil then return true, Found end
    end
    return false, "not in challenge maps"
end

local function UnlockCandidates()
    local Candidates = {}
    local Key = PendingTargetKey or FindTargetKey()
    PendingTargetKey = Key
    if Key ~= nil then Candidates[#Candidates + 1] = Key end
    Candidates[#Candidates + 1] = TARGET_ACH_CODE
    Candidates[#Candidates + 1] = TARGET_CHALLENGE_NAME
    return Candidates
end

local function Unlock(Reason)
    if State.unlocked then
        pd3.log.Info("unlock skipped (already unlocked this session via %s)", tostring(State.unlockedVia))
        return
    end
    if State.unlocking then
        pd3.log.Info("unlock skipped (attempt already in progress)")
        return
    end
    State.unlocking = true

    local AchMgr, AchName = pd3.challenge.AchievementManager()
    if AchMgr == nil then
        pd3.log.Warn("unlock: no live SBZAchievementManager")
        State.unlocking = false
        return
    end

    local Was, Detail = IsAlreadyUnlocked(AchMgr)
    pd3.log.Info("unlock precheck: alreadyUnlocked=%s (%s) reason=%s achMgr=%s",
        tostring(Was), tostring(Detail), Reason, tostring(AchName))
    if Was then
        State.unlocked = true
        State.unlockedVia = "already"
        State.unlocking = false
        return
    end

    pd3.log.Info("*** InsurancePolicy: attempting unlock (%s) ***", tostring(Reason))

    local function Postcheck()
        pd3.timers.After(2500, function()
            local After, AfterDetail = IsAlreadyUnlocked(AchMgr)
            State.unlocked = After and true or false
            pd3.log.Info("unlock postcheck: unlocked=%s (%s) attempted=%s",
                tostring(After), tostring(AfterDetail), tostring(State.unlockedVia))
            pd3.log.Info("*** InsurancePolicy: unlock requested via %s - verify in game/Steam (local map status can lag) ***",
                tostring(State.unlockedVia))
            State.unlocking = false
        end)
    end

    -- Inert UFunction with an FName parameter: distinguishes broken FName
    -- marshalling from a crash inside CompleteAchievement itself.
    local function ProbeFNameMarshalling()
        local OkFind, Statics = pcall(StaticFindObject, "/Script/Engine.Default__KismetSystemLibrary")
        if not OkFind or not pd3.safe.IsValid(Statics) then
            pd3.log.Warn("fname probe: KismetSystemLibrary CDO not found")
            return false
        end
        local Name, Index = pd3.safe.ToFName(TARGET_ACH_CODE)
        if Name == nil then
            pd3.log.Warn("fname probe: %s not in name pool", TARGET_ACH_CODE)
            return false
        end
        local OkCall, Result = pd3.safe.CallFn(Statics, "MakeLiteralName", Name)
        pd3.log.Info("fname probe: MakeLiteralName(%s idx=%d) ok=%s result=%s",
            TARGET_ACH_CODE, Index, tostring(OkCall), pd3.safe.String(Result))
        return OkCall
    end

    local function RunCompleteCandidates(OnDone)
        local Candidates = UnlockCandidates()
        local Attempt = 0
        -- One candidate per second: if the engine crashes on a conversion,
        -- the last "calling" line names the culprit.
        local function Step()
            Attempt = Attempt + 1
            local Candidate = Candidates[Attempt]
            if Candidate == nil then OnDone(); return end
            local Name, Index = pd3.safe.ToFName(Candidate)
            pd3.log.Info("lever A.%d calling CompleteAchievement(text=%s fnameIdx=%s)", Attempt, tostring(Candidate), tostring(Index))
            if Name == nil then
                pd3.log.Warn("lever A.%d skipped: FName not in name pool", Attempt)
            else
                local OkCall, Err = pd3.challenge.Complete(Name)
                pd3.log.Info("lever A.%d done ok=%s err=%s", Attempt, tostring(OkCall), pd3.safe.String(Err))
                if OkCall then
                    State.unlockedVia = "CompleteAchievement(" .. tostring(Candidate) .. ")"
                end
            end
            pd3.timers.After(1000, Step)
        end
        Step()
    end

    local function RunOssLever()
        local OkFind, Proxy = pcall(StaticFindObject, "/Script/OnlineSubsystemUtils.Default__AchievementWriteCallbackProxy")
        if not OkFind or not pd3.safe.IsValid(Proxy) then
            pd3.log.Warn("lever C unavailable")
            return false
        end
        local Code = pd3.safe.ToFName(TARGET_ACH_CODE)
        local World = pd3.world.GetWorld()
        local PC = pd3.world.GetPlayerController()
        local OkWrite, WriteErr = pd3.safe.CallFn(Proxy, "WriteAchievementProgress", World, PC, Code or TARGET_ACH_CODE, 100.0, "")
        pd3.log.Info("lever C OSS WriteAchievementProgress(%s) ok=%s err=%s", TARGET_ACH_CODE, tostring(OkWrite), pd3.safe.String(WriteErr))
        if OkWrite then
            State.unlockedVia = "OSS"
        end
        return OkWrite
    end

    local function RunLevers()
        local LeverIndex = 0
        local function Next()
            LeverIndex = LeverIndex + 1
            local Lever = Config.UnlockLevers[LeverIndex]
            if Lever == nil then
                Postcheck()
                return
            end
            if Lever == "complete" then
                RunCompleteCandidates(Next)
            elseif Lever == "oss" then
                RunOssLever()
                Next()
            else
                pd3.log.Warn("unknown lever: %s", tostring(Lever))
                Next()
            end
        end
        Next()
    end

    ProbeFNameMarshalling()
    RunLevers()
end

local function ConditionState()
    local Mission = pd3.mission.Get()
    if Mission == nil then return nil end

    local Escape = pd3.mission.Escape(Mission)
    local Pawn = pd3.world.GetPawn()
    local ShieldState = pd3.shield.InstigatorState(Pawn)

    return {
        Difficulty = pd3.mission.Difficulty(Mission),
        HeistRef = tostring(pd3.mission.HeistRef(Mission)),
        EscapeLeft = Escape.TimeLeft,
        PlayersIn = Escape.PlayersIn,
        ShieldState = ShieldState,
        ShieldActive = ShieldState == 3 or ShieldState == 4,
    }
end

local function HeistMatches(Info)
    if Config.HeistRef == "" then return true end
    return string.find(string.lower(Info.HeistRef), string.lower(Config.HeistRef), 1, true) ~= nil
end

local function MaybeLatch(Source, Info)
    if Info == nil then return end
    local EscapeActive = Info.EscapeLeft > 0 or Info.PlayersIn > 0
    if EscapeActive and Info.ShieldActive then
        if not State.latched then
            pd3.log.Info("*** InsurancePolicy: condition latched (source=%s, shield=%s) ***",
                Source, Name(Info.ShieldState, SHIELD_STATE_NAMES))
        end
        State.latched = true
    end
end

local function CheckAndUnlock(Source, Force)
    local Info = ConditionState()
    if Info == nil then
        if Force then
            pd3.log.Info("[%s] no mission state, forcing unlock anyway", Source)
            Unlock("force key")
        else
            pd3.log.Info("[%s] no mission state, skip", Source)
        end
        return
    end
    pd3.log.Info("[%s] diff=%s heist=%s escapeLeft=%s playersInEscape=%s shield=%s latched=%s",
        Source, Name(Info.Difficulty, pd3.mission.DifficultyNames), Info.HeistRef, tostring(Info.EscapeLeft),
        tostring(Info.PlayersIn), Name(Info.ShieldState, SHIELD_STATE_NAMES), tostring(State.latched))

    if Force then
        Unlock("force key")
        return
    end
    if not Config.AutoUnlock then
        pd3.log.Info("[%s] auto unlock disabled", Source)
        return
    end
    if not (type(Info.Difficulty) == "number" and Info.Difficulty >= Config.MinDifficulty) then
        pd3.log.Info("[%s] condition fail: difficulty", Source)
        return
    end
    if not HeistMatches(Info) then
        pd3.log.Info("[%s] condition fail: heist ref %s does not match config %s", Source, Info.HeistRef, Config.HeistRef)
        return
    end
    if not State.latched then
        pd3.log.Info("[%s] condition fail: shield latch not set", Source)
        return
    end
    Unlock(Source)
end

local function DumpCondition()
    local Info = ConditionState()
    if Info == nil then
        pd3.log.Info("F4: no mission state")
        return
    end
    pd3.log.Info("F4: difficulty=%s heist=%s escapeLeft=%s playersInEscape=%s shield=%s active=%s latched=%s unlocked=%s",
        Name(Info.Difficulty, pd3.mission.DifficultyNames), Info.HeistRef, tostring(Info.EscapeLeft), tostring(Info.PlayersIn),
        Name(Info.ShieldState, SHIELD_STATE_NAMES), tostring(Info.ShieldActive), tostring(State.latched),
        tostring(State.unlocked))
end

local function LogTargetStatus(Tag)
    local Found = ScanMapStatus(pd3.challenge.Achievements(), "AchievementMap")
    pd3.log.Info("*** InsurancePolicy status (%s): %s ***", tostring(Tag),
        Found ~= nil and "COMPLETED(2)" or "INPROGRESS/unknown")
end

-- Reflection dump (update-proof re-discovery when the game patches).
local function DumpReflection()
    pd3.log.Info("=== F9 reflection dump ===")

    local Mission = pd3.mission.Get()
    if Mission ~= nil then
        pd3.mission.DumpCriterion(pd3.mission.Criterion("InsurancePolicy"), { MaxLines = 60 })
        pd3.mission.DumpHeistData(pd3.mission.HeistData(Mission), { MaxLines = 60 })
        pd3.mission.DumpMissionResult(Mission, { MaxLines = 60, MaxDepth = 0 })
    else
        pd3.log.Info("no live mission state")
    end

    local ChallengeManager = pd3.challenge.Manager()
    if ChallengeManager ~= nil then
        pd3.challenge.DumpStatMap(ChallengeManager, 10, { MaxLines = 20 })
        pd3.challenge.DumpCaches(ChallengeManager)
        local Summaries = pd3.challenge.Find(ChallengeManager, "penthouse human shield")
        if Summaries[1] ~= nil then
            pd3.reflect.DumpStruct(Summaries[1].Record, "SBZChallengeData", { MaxLines = 40 })
        end
    else
        pd3.log.Info("no live challenge manager")
    end
    pd3.log.Info("=== F9 done ===")
end

local function RegisterConditionHooks()
    pd3.hooks.Hook("/Script/Starbreeze.SBZMissionState:Multicast_SetEscapeVolumeData", function()
        MaybeLatch("escape-volume-multicast", ConditionState())
    end)
    pd3.hooks.Hook("/Script/Starbreeze.SBZGameStateMachine:RequestMissionEnd", function()
        -- Do not call UFunctions from inside a hook callback; defer a tick.
        pd3.timers.After(250, function()
            CheckAndUnlock("mission-end", false)
        end)
    end)
end

pd3.lifecycle.OnLevelInit(function(LevelName)
    State.latched = false
    pd3.log.Info("level init: %s", tostring(LevelName))
    pd3.timers.After(3000, function()
        local Info = ConditionState()
        if Info ~= nil then
            pd3.log.Info("mission detected: diff=%s heist=%s", Name(Info.Difficulty, pd3.mission.DifficultyNames), Info.HeistRef)
        end
    end)
    pd3.timers.After(5000, function() LogTargetStatus("level-init") end)
end)

pd3.lifecycle.OnReturnToMenu(function()
    pd3.timers.After(3000, function() LogTargetStatus("return-to-menu") end)
end)

pd3.timers.Every(1000, function()
    local Info = ConditionState()
    if Info ~= nil then MaybeLatch("poll", Info) end
end)

RegisterConditionHooks()

pd3.keys.Bind(Key.F1, DumpCriterion, "read DA_InsurancePolicy criterion")
pd3.keys.Bind(Key.F2, ProbeLevers, "probe achievement unlock levers")
pd3.keys.Bind(Key.F3, function() CheckAndUnlock("force key", true) end, "force unlock achievement")
pd3.keys.Bind(Key.F4, DumpCondition, "dump unlock condition state")
pd3.keys.Bind(Key.F9, DumpReflection, "reflection dump (mission + challenge structs)")

pd3.log.Info("loaded. F1 criterion, F2 probes, F3 force unlock, F4 condition state, F9 reflection dump")
