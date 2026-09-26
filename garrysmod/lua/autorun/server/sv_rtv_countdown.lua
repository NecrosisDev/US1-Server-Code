-- RTV Countdown 1.1.1: stock ZCity and SolidMapVote repair compatibility.
-- Replace garrysmod/lua/autorun/server/sv_rtv_countdown.lua.
if not SERVER then return end

local TIMER = "RTVCountdown_Announce"
local function number(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or math.abs(value) == math.huge then return fallback end
    return value
end

local function announcement()
    if not zb then return end
    local vote = SolidMapVote
    local integrated = type(vote) == "table" and vote.initialized and type(vote.number) == "function"
    if integrated and vote.isOpen then return end
    local series = zb.CROUND == "cstrike" and zb.RoundsLeft
    if integrated and vote.pending then
        return series and "[Map] Map vote queued for after the Counter-Strike series."
            or "[Map] Map vote queued for the next intermission."
    end
    local dev = GetConVar("zb_dev")
    if dev and dev:GetBool() then return end

    local count = number(zb.Roundscount, 0)
    local limit, base = 16, 0
    if integrated then
        limit = math.floor(vote.number("Rounds Per Vote", 16, 1, 1000))
        base = number(vote.roundBase, 0)
        -- Match SolidMapVote's handling of a reset ZCity round counter.
        if count < base then base = count end
    end
    local left = math.max(0, math.ceil(limit - (count - base)))
    if series and left <= 1 then
        return left == 1 and "[Map] Map vote due in 1 round; voting waits for the Counter-Strike series to finish."
            or "[Map] Map vote is due; waiting for the Counter-Strike series to finish."
    elseif left == 0 then
        return "[Map] Map vote is due at the next available intermission."
    elseif left == 1 then
        return "[Map] Final round before the map vote! !rtv to change early."
    end
    return "[Map] " .. left .. " rounds until the map vote. !rtv to change early."
end

-- A named timer prevents duplicate/stale announcements on fast round changes or refresh.
timer.Remove(TIMER)
hook.Add("ZB_StartRound", "RTVCountdown_Announce", function()
    if not zb then return end
    local count, started = zb.Roundscount, zb.ROUND_START
    timer.Create(TIMER, 3, 1, function()
        if not zb or zb.ROUND_STATE ~= 1 or zb.Roundscount ~= count or zb.ROUND_START ~= started then return end
        local text = announcement()
        if text then PrintMessage(HUD_PRINTTALK, text .. " !nominate to nominate a map.") end
    end)
end)
hook.Add("ZB_EndRound", "RTVCountdown_Cancel", function() timer.Remove(TIMER) end)
print("[RTVCountdown] 1.1.1 loaded (SolidMapVote compatible)")
