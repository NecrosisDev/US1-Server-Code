-- ULX / ZCity chat bridge v1.2.0 (server only).
-- Moderation is checked at the hook dispatcher boundary, so a native
-- early return cannot bypass it. Other events and allowed callbacks keep
-- their original order, priorities, entity arguments and return values.
if not SERVER then return end

ULXZChatBridge = ULXZChatBridge or {}
local B = ULXZChatBridge
B.Version = "1.2.0"
B.PDataCache = setmetatable({}, { __mode = "k" })

local function ValidPlayer(ply)
    return IsValid(ply) and ply:IsPlayer()
end

local function HasActivePData(ply, key, fresh)
    local row = B.PDataCache[ply]
    if not row then row = {}; B.PDataCache[ply] = row end
    local cached = row[key]
    if not fresh and cached and cached.untilTime > CurTime() then return cached.active end
    local value = ply:GetPData(key)
    local minutes = tonumber(value)
    local active = value == true or (minutes ~= nil and minutes > 0) or value == "true"
    row[key] = { active = active, untilTime = CurTime() + 5 }
    return active
end

local function Strangled(ply)
    return type(Fiberwire_IsStrangled) == "function" and Fiberwire_IsStrangled(ply)
end

local function IsMuted(ply)
    if not ValidPlayer(ply) then return false end
    if ply.ulx_muted == true or ply:GetNWBool("ulx_muted", false) or ply.tmuted == true then return true end
    if Strangled(ply) then return true end
    -- Text is per message, not per listener/talker pair: read timed mute
    -- directly so applying or removing tmute has no five-second grace.
    return HasActivePData(ply, "tmuted", true)
end

local function IsGagged(ply)
    if ply.ulx_gagged == true or ply:GetNWBool("ulx_gagged", false) or ply.tgagged == true then return true end
    if Strangled(ply) then return true end
    return HasActivePData(ply, "tgagged", false)
end

local function IsDeadOrObserving(ply)
    if not ply:Alive() then return true end
    -- GetCurrentCharacter falls back to the player; it is not evidence
    -- of a living body. Use the engine's actual observer mode instead.
    if ply:GetObserverMode() ~= OBS_MODE_NONE then return true end
    -- Preserve staff's intentional alive-as-spectator listening behavior.
    return ply:IsAdmin() and ply:Team() == TEAM_SPECTATOR
end

function B.VoiceDecision(listener, talker)
    if not ValidPlayer(listener) or not ValidPlayer(talker) then return false, false end
    if IsGagged(talker) then return false, false end
    if IsDeadOrObserving(talker) and not IsDeadOrObserving(listener) then
        -- Only the actual results window, never lobby/next-round state 0.
        if zb and zb.ROUND_STATE == 3 then return true, false end
        if not talker:IsAdmin() then return false, false end
    end
end

function B.TextBlocked(ply)
    return IsMuted(ply)
end

-- A stable dispatcher references the current policy instead of capturing
-- old policy closures on every round/reload. Never wrap individual hooks.
if not B.Dispatch then
    local previous = hook.Call
    assert(type(previous) == "function", "ULX-ZChat Bridge requires hook.Call")
    B.Dispatch = function(event, gm, ...)
        if event == "PlayerCanHearPlayersVoice" then
            local allowed, spatial = B.VoiceDecision(...)
            if allowed ~= nil then return allowed, spatial end
        elseif event == "PlayerSay" then
            local ply = ...
            if B.TextBlocked(ply) then
                ply:ChatPrint("You are muted.")
                return ""
            end
        elseif event == "HG_PlayerSay" then
            local ply, text = ...
            if B.TextBlocked(ply) then
                if type(text) == "table" then text[1] = "" end
                ply:ChatPrint("You are muted.")
                return true -- stop modifiers from turning an empty message back into text
            end
        end
        return previous(event, gm, ...)
    end
    hook.Call = B.Dispatch
elseif hook.Call ~= B.Dispatch then
    -- A later addon might wrap us (fine) or replace the dispatcher (not
    -- verifiable here). Do not capture an unknown chain again on reload.
    print("[ULX-ZChat Bridge] Dispatcher changed externally; verify integration before relying on reload.")
end

local moderation = {
    ["ulx gag"] = true, ["ulx ungag"] = true,
    ["ulx tgag"] = true, ["ulx untgag"] = true,
    ["ulx mute"] = true, ["ulx unmute"] = true,
    ["ulx tmute"] = true, ["ulx untmute"] = true
}
hook.Add("ULibPostTranslatedCommand", "ULXZChat_InvalidateModeration", function(_, command)
    if type(command) == "string" and moderation[string.lower(command)] then
        B.PDataCache = setmetatable({}, { __mode = "k" })
    end
end, HOOK_MONITOR_HIGH or -2)
hook.Add("PlayerDisconnected", "ULXZChat_CacheClear", function(ply)
    B.PDataCache[ply] = nil
end)

-- Remove only our old named registrations. Anonymous legacy wrappers
-- already embedded in other hooks cannot safely be unwrapped: restart
-- the process when upgrading from the original bridge or v1.1.0.
hook.Remove("PlayerCanHearPlayersVoice", "ULXZChat_GagBridge")
hook.Remove("HG_PlayerSay", "ULXZChat_MuteBridge")
hook.Remove("InitPostEntity", "ULXZChat_WrapVoice")
hook.Remove("ZB_StartRound", "ULXZChat_RewrapVoice")
timer.Remove("ULXZChat_SpectatorNormalizer")

print("[ULX-ZChat Bridge] v1.2.0 loaded - ULX moderation + post-round dead voice")
