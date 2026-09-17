local MOD_NAME = "InsurancePolicyMod"

local OkLib, pd3lib = pcall(require, "pd3lib")
if not OkLib or pd3lib == nil then
    print(string.format("[%s] pd3lib load failed: %s\n", MOD_NAME, tostring(pd3lib)))
    return
end

local pd3 = pd3lib
pd3.Init({ prefix = "[" .. MOD_NAME .. "]" })

local Config = {
    HeistRef = "penthouse",
    MinDifficulty = 2, -- ESBZDifficulty: Normal=0, Hard=1, VeryHard=2, Overkill=3
    AutoUnlock = true,
    Debug = false, -- true: verbose diagnostics in the UE4SS console
    -- Every lever is attempted in order on an unlock attempt:
    -- "complete" = SBZAchievementManager:CompleteAchievement (candidates in order),
    -- "oss" = AchievementWriteCallbackProxy. Flip to { "oss", "complete" } if needed.
    UnlockLevers = { "complete", "oss" },
}

-- Verbose diagnostics: only printed when Config.Debug is true.
local function Debug(...)
    if Config.Debug then pd3.log.Info(...) end
end

local TARGET_ACH_CODE = "ACH_PH_HUMAN_SHIELD_EXTRACT"
local TARGET_CHALLENGE_NAME = "AchievementSteamPenthouseHumanShieldExtract"
local TARGET_NAME_NEEDLES = { "penthouse human shield", "penthouse-human-shield" }

local SHIELD_STATE_NAMES = {
    [0] = "None", [1] = "ReachingSlot", [2] = "EnterGrabbing", [3] = "Grabbing",
    [4] = "Choking", [5] = "Exiting",
}

local State = {
    latched = false,
    attempted = false,
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
        Debug("target achievement: key=%s name=%s status=%s",
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
            Debug("target[%s] key=%s name=%s status=%s", Label,
                Summary.Key, Summary.ChallengeName, pd3.challenge.StatusName(Summary.Status))
            if Summary.Status == pd3.challenge.CompletedStatus then
                Found = string.format("%s key=%s name=%s", Label, Summary.Key, Summary.ChallengeName)
            end
        end
    end)
    return Found
end

local function IsAlreadyUnlocked()
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
        Debug("unlock skipped (already unlocked this session via %s)", tostring(State.unlockedVia))
        return
    end
    if State.unlocking then
        Debug("unlock skipped (attempt already in progress)")
        return
    end
    State.unlocking = true

    local AchMgr, AchName = pd3.challenge.AchievementManager()
    if AchMgr == nil then
        pd3.log.Warn("unlock: no live SBZAchievementManager")
        State.unlocking = false
        return
    end

    State.attempted = true

    local Was, Detail = IsAlreadyUnlocked()
    Debug("unlock precheck: alreadyUnlocked=%s (%s) reason=%s achMgr=%s",
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
            local After, AfterDetail = IsAlreadyUnlocked()
            State.unlocked = After and true or false
            Debug("unlock postcheck: unlocked=%s (%s) attempted=%s",
                tostring(After), tostring(AfterDetail), tostring(State.unlockedVia))
            pd3.log.Info("*** InsurancePolicy: unlock requested via %s - verify in game/Steam (local map status can lag) ***",
                tostring(State.unlockedVia))
            State.unlocking = false
        end)
    end

    local function RunCompleteCandidates(OnDone)
        local Candidates = UnlockCandidates()
        local Attempt = 0
        -- One candidate per second: if the engine crashes on a conversion,
        -- the last "calling" line names the culprit.
        local function Step()
            Attempt = Attempt + 1
            local Candidate = Candidates[Attempt]
            if Candidate == nil then OnDone(false); return end
            local Name, Index = pd3.safe.ToFName(Candidate)
            Debug("lever A.%d calling CompleteAchievement(text=%s fnameIdx=%s)", Attempt, tostring(Candidate), tostring(Index))
            if Name == nil then
                pd3.log.Warn("lever A.%d skipped: FName not in name pool", Attempt)
            else
                local OkCall, Err = pd3.challenge.Complete(Name)
                Debug("lever A.%d done ok=%s err=%s", Attempt, tostring(OkCall), pd3.safe.String(Err))
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
        Debug("lever C OSS WriteAchievementProgress(%s) ok=%s err=%s", TARGET_ACH_CODE, tostring(OkWrite), pd3.safe.String(WriteErr))
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
        EscapeActive = Escape.PlayersIn > 0,
        ShieldState = ShieldState,
        ShieldActive = type(ShieldState) == "number" and (ShieldState == 3 or ShieldState == 4),
    }
end

local function HeistMatches(Info)
    if Config.HeistRef == "" then return true end
    return string.find(string.lower(Info.HeistRef), string.lower(Config.HeistRef), 1, true) ~= nil
end

local function MaybeLatch(Source, Info)
    if Info == nil then return end
    if Info.EscapeActive and Info.ShieldActive then
        if not State.latched then
            Debug("*** InsurancePolicy: condition latched (source=%s, shield=%s) ***",
                Source, Name(Info.ShieldState, SHIELD_STATE_NAMES))
        end
        State.latched = true
    elseif State.latched and (not Info.EscapeActive or type(Info.ShieldState) == "number") then
        Debug("*** InsurancePolicy: condition cleared (source=%s, shield=%s) ***",
            Source, Name(Info.ShieldState, SHIELD_STATE_NAMES))
        State.latched = false
    end
end

local function CheckAndUnlock(Source, Force)
    if State.attempted and not Force then return end
    local Info = ConditionState()
    if Info == nil then
        if Force then
            Debug("[%s] no mission state, forcing unlock anyway", Source)
            Unlock("force key")
        else
            Debug("[%s] no mission state, skip", Source)
        end
        return
    end
    Debug("[%s] diff=%s heist=%s escapeLeft=%s playersInEscape=%s shield=%s latched=%s",
        Source, Name(Info.Difficulty, pd3.mission.DifficultyNames), Info.HeistRef, tostring(Info.EscapeLeft),
        tostring(Info.PlayersIn), Name(Info.ShieldState, SHIELD_STATE_NAMES), tostring(State.latched))

    if Force then
        Unlock("force key")
        return
    end
    if not Config.AutoUnlock then
        Debug("[%s] auto unlock disabled", Source)
        return
    end
    if not (type(Info.Difficulty) == "number" and Info.Difficulty >= Config.MinDifficulty) then
        Debug("[%s] condition fail: difficulty", Source)
        return
    end
    if not HeistMatches(Info) then
        Debug("[%s] condition fail: heist ref %s does not match config %s", Source, Info.HeistRef, Config.HeistRef)
        return
    end
    if not Info.EscapeActive then
        Debug("[%s] condition fail: escape not active", Source)
        return
    end
    if not Info.ShieldActive then
        Debug("[%s] condition fail: shield not held (state=%s)", Source,
            Name(Info.ShieldState, SHIELD_STATE_NAMES))
        return
    end
    Unlock(Source)
end

local function LogTargetStatus(Tag)
    local Found = ScanMapStatus(pd3.challenge.Achievements(), "AchievementMap")
    Debug("*** InsurancePolicy status (%s): %s ***", tostring(Tag),
        Found ~= nil and "COMPLETED(2)" or "INPROGRESS/unknown")
end

local ESCAPE_HOOK = "/Script/Starbreeze.SBZMissionState:Multicast_SetEscapeVolumeData"
local MISSION_END_HOOK = "/Script/Starbreeze.SBZGameStateMachine:RequestMissionEnd"

local EscapeHookId = nil
local MissionEndHookId = nil
local PollHandle = nil

local function RegisterConditionHooks()
    if EscapeHookId ~= nil or MissionEndHookId ~= nil then return end
    EscapeHookId = pd3.hooks.Hook(ESCAPE_HOOK, function()
        -- Hook-context property reads are unreliable; defer a tick.
        pd3.timers.After(250, function()
            MaybeLatch("escape-volume-multicast", ConditionState())
        end)
    end)
    MissionEndHookId = pd3.hooks.Hook(MISSION_END_HOOK, function()
        -- Do not call UFunctions from inside a hook callback; defer a tick.
        pd3.timers.After(250, function()
            CheckAndUnlock("mission-end", false)
        end)
    end)
end

local function UnregisterConditionHooks()
    if EscapeHookId ~= nil then
        pd3.hooks.Unhook(ESCAPE_HOOK, EscapeHookId)
        EscapeHookId = nil
    end
    if MissionEndHookId ~= nil then
        pd3.hooks.Unhook(MISSION_END_HOOK, MissionEndHookId)
        MissionEndHookId = nil
    end
end

local function Poll()
    local Info = ConditionState()
    if Info ~= nil then
        MaybeLatch("poll", Info)
        if State.latched then CheckAndUnlock("poll", false) end
    end
end

local function Activate(HeistRef)
    if PollHandle ~= nil then
        Debug("arm skipped: already armed (%s)", tostring(HeistRef))
        return
    end
    State.latched = false
    State.attempted = false
    Debug("*** InsurancePolicy: armed for heist %s ***", tostring(HeistRef))
    RegisterConditionHooks()
    Poll()
    PollHandle = pd3.timers.Every(1000, Poll)
    LogTargetStatus("heist-enter")
end

local function Deactivate(HeistRef, Reason)
    if PollHandle ~= nil then
        pd3.timers.Cancel(PollHandle)
        PollHandle = nil
    end
    UnregisterConditionHooks()
    Debug("*** InsurancePolicy: disarmed (heist=%s reason=%s) ***", tostring(HeistRef), tostring(Reason))
    if State.attempted then
        pd3.timers.After(3000, function() LogTargetStatus("heist-exit") end)
    end
end

pd3.heist.Watch(Config.HeistRef, { Enter = Activate, Exit = Deactivate })

-- pd3.keys.Bind(Key.F3, function() CheckAndUnlock("force key", true) end, "force unlock achievement")

Debug("loaded.")
