-- Round-end slow-mo (round_v2 Stage 2 S2.1 / Step 5's round-end panel "frame 1" beat). A brief
-- SERVER-WIDE host_timescale dip right as the round ends, purely presentational. host_timescale is
-- server-side and slows EVERY player, not just the client watching the GoobOS panel -- that's expected
-- and documented in BLUEPRINT.md S2.1. Off by default; never touches game.SetTimeScale when the convar
-- is 0.
if not SERVER then return end

local M = {}
ZCRoundSlowmo = M
M.Version = "20260925.slowmo2"

local cv = CreateConVar("zc_round_slowmo", "0", FCVAR_ARCHIVE, "Brief host_timescale dip at round end (0/1).")
-- postround_20260925 (owner 2026-09-25: "post-round intermission ~20 seconds, slow motion for the first 3 realtime
-- seconds immediately after round end"). The dip now lasts zc_round_slowmo_seconds of REAL time, and this module also
-- owns the intermission length: zc_postround_seconds of real time, the slow motion included, converted to game time
-- because zb.END_TIME is CurTime() and CurTime() crawls during the dip. 0 keeps each mode's own end_time (5-10 s).
-- A mode that wants a longer intermission than this still gets it (the larger of the two wins), and the co-op
-- first-round timer (60 s, sv_roundsystem.lua EndRoundThink) is left alone. zc_killcam_highlight_hold 1 can still push the
-- end later (sv_highlight.lua, at most HOLD_MAX 20 s past the natural end) to finish a long highlight.
-- PROVISIONAL(2026-09-25, 0.35 scale kept from slowmo1; 20 s and 3 s are the owner's numbers, ratify-by: 2026-10-09)
local cvSeconds = CreateConVar("zc_round_slowmo_seconds", "3", FCVAR_ARCHIVE, "Real seconds the round-end slow motion lasts.", 0, 10)
local cvScale = CreateConVar("zc_round_slowmo_scale", "0.35", FCVAR_ARCHIVE, "Time scale during the round-end slow motion.", 0.1, 1)
local cvPost = CreateConVar("zc_postround_seconds", "20", FCVAR_ARCHIVE, "Real seconds of post-round intermission, slow motion included (0 = each mode's own end_time).", 0, 120)
-- Living players' number keys during the intermission: 0 (default) = never taken (the round-end card only shows the
-- vote), 1 = the mode / map vote takes them while it is open, as before. Read by lua/zc_goobos/roundend.lua.
local cvAliveVote = CreateConVar("zc_postround_alive_vote", "0", FCVAR_ARCHIVE, "Let the round-end vote take a LIVING player's number keys (0/1).", 0, 1)

local restoreAt = nil -- RealTime() deadline; nil when not currently slowed
local dipPending = nil -- the dip to apply on the next Think (after every ZB_EndRound handler has run)
local heldIntermission = false -- this intermission already handled (cleared once the round state leaves 3)

local function setScale(v)
    local ok, err = pcall(game.SetTimeScale, v)
    if not ok then ErrorNoHalt("[GoobOS roundend] zc_round_slowmo game.SetTimeScale: " .. tostring(err) .. "\n") end
end

local function restore()
    if restoreAt == nil then return end
    restoreAt = nil
    setScale(1)
end

-- Game seconds that take `want` real seconds when the first `slowReal` of them run at `scale`.
function M.GameSeconds(want, slowReal, scale)
    want, slowReal, scale = tonumber(want) or 0, math.max(tonumber(slowReal) or 0, 0), math.Clamp(tonumber(scale) or 1, 0.01, 1)
    local slow = math.min(slowReal, want)
    return (want - slow) + slow * scale
end
local function onEndRound()
    -- Once per intermission: zb:EndRound() can run twice before the round moves on (any mode or addon may call it,
    -- see sv_highlight.lua `natural`); a second call must not restart the slow motion or the 20 s.
    local zbNow = rawget(_G, "zb")
    if heldIntermission and istable(zbNow) and zbNow.ROUND_STATE == 3 then return end
    heldIntermission = istable(zbNow) and zbNow.ROUND_STATE == 3
    local slowReal, scale = 0, 1
    if cv:GetBool() then
        slowReal, scale = math.Clamp(cvSeconds:GetFloat(), 0, 10), math.Clamp(cvScale:GetFloat(), 0.1, 1)
        if slowReal > 0 and scale < 1 then
            -- Applied on the next Think, not here: zc_headshot_slowmo resets on ZB_EndRound too (it puts the scale back
            -- when it still equals its own zc_headshot_slowmo_scale), and hook order is not fixed.
            dipPending = {scale = scale, seconds = slowReal}
        else
            slowReal, scale = 0, 1
        end
    end
    SetGlobalBool("zc_postround_alive_vote", cvAliveVote:GetBool())
    local want = cvPost:GetFloat()
    local zbT = rawget(_G, "zb")
    if want <= 0 or not istable(zbT) or zbT.ROUND_STATE ~= 3 then return end
    if zbT.nextround == "coop" and GetGlobalVar("coop_first_round_timer", 0) == 0 then return end
    local mode = isfunction(CurrentRound) and CurrentRound()
    local own = istable(mode) and tonumber(mode.end_time) or 5
    local at = CurTime() + math.max(M.GameSeconds(want, slowReal, scale), own)
    -- Never shorter than a deadline another ZB_EndRound handler already wrote (zc_vote_manager.lua's final
    -- intermission sets END_TIME = CurTime() + zc_final_intermission for the map vote; hook order is not fixed).
    local cur = zbT.END_TIME
    if isnumber(cur) and cur == cur and cur < math.huge and cur > at then at = cur end
    zbT.END_TIME = at
    M.IntermissionEnd = at
end
hook.Add("ZB_EndRound", "ZCRoundSlowmo.End", function()
    local ok, err = pcall(onEndRound)
    if not ok then ErrorNoHalt("[GoobOS roundend] zc_round_slowmo ZB_EndRound: " .. tostring(err) .. "\n") end
end)

-- Safety restores (never leave the server slowed): PreRoundStart/StartRound cover a stuck/short
-- intermission, ShutDown covers a restart landing mid-dip. Real-time Think check, not a game-time
-- timer -- CurTime()-scheduled timers would themselves run slow while host_timescale is down.
local function safetyRestore()
    local ok, err = pcall(restore)
    if not ok then ErrorNoHalt("[GoobOS roundend] zc_round_slowmo safety restore: " .. tostring(err) .. "\n") end
end
hook.Add("ZB_PreRoundStart", "ZCRoundSlowmo.Pre", function() dipPending = nil safetyRestore() end)
hook.Add("ZB_StartRound", "ZCRoundSlowmo.Start", safetyRestore)
hook.Add("ShutDown", "ZCRoundSlowmo.Shutdown", safetyRestore)

hook.Add("Think", "ZCRoundSlowmo.Watch", function()
    if heldIntermission then
        local zbNow = rawget(_G, "zb")
        if not istable(zbNow) or zbNow.ROUND_STATE ~= 3 then heldIntermission = false end
    end
    if dipPending then
        local d = dipPending
        dipPending = nil
        setScale(d.scale)
        restoreAt = RealTime() + d.seconds
    end
    if restoreAt and RealTime() >= restoreAt then restore() end
end)

-- Boot receipt.
local receipted = false
local function receipt()
    if receipted then return end
    receipted = true
    print("[GoobOS] zc_round_slowmo.lua version=" .. M.Version .. " on=" .. (cv:GetBool() and 1 or 0))
end
hook.Add("InitPostEntity", "ZCRoundSlowmo.Boot", receipt)
if hook.GetULibTable then receipt() end
