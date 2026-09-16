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
    MinDifficulty = 1, -- ESBZDifficulty: Normal=0, Hard=1, VeryHard=2, Overkill=3
    AutoUnlock = true,
    -- Order of unlock levers: "complete" = SBZAchievementManager:CompleteAchievement,
    -- "oss" = AchievementWriteCallbackProxy. Flip to { "oss", "complete" } if needed.
    UnlockLevers = { "complete", "oss" },
}

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

    local Was, Detail = IsAlreadyUnlocked()
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
            local After, AfterDetail = IsAlreadyUnlocked()
            State.unlocked = After and true or false
            pd3.log.Info("unlock postcheck: unlocked=%s (%s) attempted=%s",
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

local function LogTargetStatus(Tag)
    local Found = ScanMapStatus(pd3.challenge.Achievements(), "AchievementMap")
    pd3.log.Info("*** InsurancePolicy status (%s): %s ***", tostring(Tag),
        Found ~= nil and "COMPLETED(2)" or "INPROGRESS/unknown")
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

pd3.keys.Bind(Key.F3, function() CheckAndUnlock("force key", true) end, "force unlock achievement")

pd3.log.Info("loaded. F3 force unlock")
