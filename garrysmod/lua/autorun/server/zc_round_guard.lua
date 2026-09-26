-- US1 Round System v2, Stage 1: per-listener + per-mode-method fencing of the round transition
-- + stuck-round watchdog. Extends addons/zcity/gamemodes/zcity/gamemode/libraries/sv_roundsystem.lua
-- (zb) WITHOUT editing it. Owner: work/loader/round_v2/BLUEPRINT.md, Stage 1, S1.1 + S1.2 +
-- S1.5's consumer. Dark by default: every behaviour here is gated by a convar defaulting to
-- current behaviour.
--
-- Release policy hard rule: this file NEVER assigns hook.Run, hook.Call, hook.Add/Remove
-- themselves, net.*, or include - eProtect (addons/eprotect-.../lua/e_protect/server/sv_eprotect.lua)
-- calls hook.Run itself and the server's release policy forbids replacing global hook/net/include
-- functions. An earlier draft of this file replaced hook.Run for exactly 3 event names; that
-- draft was rejected in review and is NOT what ships. Everything below fences INDIVIDUAL
-- LISTENERS (via hook.Add, re-registering the same id under a wrapper) and INDIVIDUAL MODE
-- METHODS (zb.modes[name].X = wrapper) instead - hook.Run/hook.Call/hook.Add/hook.Remove
-- themselves are called exactly as ULib defines them, never reassigned.
--
-- Second review pass fixed three more defects (documented at each site below): the selftest
-- used to dispatch the REAL ZB_PreRoundStart event, which fires ~40 production listeners
-- mid-round for the sake of a staff command - it now calls the two installed wrapper functions
-- directly and never touches hook.Run/hook.Call at all. The watchdog's "far future END_TIME"
-- release path used to skip the elapsed/vote/highlight guards the plain-stuck path had - every
-- release path now shares one gate. And boot.txt/watchdog.txt/errors.txt now use file.Append
-- (verified live elsewhere in this tree, e.g. lua/zc_killcam/sv_tape.lua:174,
-- lua/autorun/server/zc_make_crawler.lua:56) with a 200-line rotation (keep last 100), checked
-- at most once per map instead of a full read+write on every single line.
--
-- Reality checks made before writing this (documented, not silently changed):
--   * S1.1's mode-method list (RoundStart/EndRound/Intermission/GiveEquipment/PreRound) was
--     checked against sv_roundsystem.lua's actual bare `CurrentRound():X()` dispatch sites
--     (the only ones that exist: RoundThink, EndRound :88, ShouldRoundEnd, BoringRoundFunction,
--     RoundStart :558, RoundStartPost, Intermission :886, GiveEquipment :888). There is no
--     `CurrentRound():PreRound()` anywhere in that file - PreRound is zb's OWN method, not a
--     per-mode one - so PreRound is excluded from mode-method fencing (nothing to wrap).
--   * Intermission is ALSO excluded, for a safety reason the blueprint could not have known:
--     addons/zcity/gamemodes/zcity/gamemode/modes/homicide/sv_homicide.lua's MODE:Intermission
--     (mode key "hmcd", sh_homicide.lua:2) calls zb:TransitionYield() twice (:1144, :1170) -
--     i.e. it yields. zb:PrepareReplayRound calls CurrentRound():Intermission() (:886) from
--     INSIDE the same coroutine that yields via that exact call. Whole-function xpcall-wrapping
--     a listener/method that yields puts a pcall frame between coroutine.resume
--     (zb:StepReplayTransition) and a later coroutine.yield, whose safety under this GMod
--     build's LuaJIT could not be verified offline. Grepping the whole
--     addons/zcity/gamemodes/zcity/gamemode/modes tree found exactly one TransitionYield call
--     site outside sv_roundsystem.lua - homicide's Intermission - and no static, reliable way
--     exists to prove every OTHER mode's Intermission stays yield-free forever. So Intermission
--     is excluded for every mode, not just hmcd: conservative, and re-auditable the same way
--     (`grep -rln TransitionYield modes/`) if a mode changes.
--   * RoundStart, EndRound and GiveEquipment were grepped the same way across every mode file:
--     zero TransitionYield/coroutine.yield hits. They ARE wrapped, per mode, identity-checked.
if not SERVER then return end

ZCRoundGuard = ZCRoundGuard or {}
local G = ZCRoundGuard
G.Version = "20260923.s1c"
G.errorSeen = G.errorSeen or {}
G.errorCount = G.errorCount or 0
G.watchdogFires = G.watchdogFires or 0
-- Weak-keyed: a wrapper/original that is GC'd (its owner unloaded) does not pin memory here.
G.listenerWrapped = G.listenerWrapped or setmetatable({}, { __mode = "k" })   -- [wrapperFn] = true
G.listenerOriginalOf = G.listenerOriginalOf or setmetatable({}, { __mode = "k" }) -- [wrapperFn] = originalFn
G.listenerTracked = G.listenerTracked or {}   -- [event] = { [id] = true }
G.modeWraps = G.modeWraps or {}               -- ["modeName.method"] = {original=, wrapper=}

local cvGuard = CreateConVar("zc_round_guard", "0", FCVAR_ARCHIVE,
    "Fence ZB_StartRound/ZB_EndRound/ZB_PreRoundStart listeners and the bare mode-method calls sv_roundsystem.lua makes, each under its own xpcall. 0 off (current behaviour), 1 on.", 0, 1)
local cvWatchdog = CreateConVar("zc_round_watchdog_seconds", "0", FCVAR_ARCHIVE,
    "Seconds a stuck round state (0=lobby, 3=intermission) is tolerated before the watchdog releases it. 0 = watchdog off; 1-29 are clamped up to 30.", 0, 3600)

-- ---------------------------------------------------------------------------------------------
-- data/zc_round_v2/boot.txt, data/zc_round_v2/errors.txt, data/zc_round_v2/watchdog.txt.
-- file.Append (verified live in this tree: lua/zc_killcam/sv_tape.lua:174,
-- lua/autorun/server/zc_make_crawler.lua:56 and 17 more call sites) for the common case; rotation
-- (200-line cap, keep the last 100) needs a full file.Read/file.Write, so it only runs at boot and
-- at PostCleanupMap - never on the hot per-line append path.
local DIR = "zc_round_v2"
local ROTATE_CAP, ROTATE_KEEP = 200, 100
local ROTATED_FILES = { "boot.txt", "errors.txt", "watchdog.txt" }

local function appendLine(rel, line)
    file.CreateDir(DIR)
    file.Append(DIR .. "/" .. rel, line .. "\n")
end

local function rotateFile(rel)
    local path = DIR .. "/" .. rel
    local existing = file.Read(path, "DATA")
    if not existing or existing == "" then return end
    local lines, n = {}, 0
    for line in existing:gmatch("([^\n]*)\n") do n = n + 1 lines[n] = line end
    if n <= ROTATE_CAP then return end
    local kept, first = {}, n - ROTATE_KEEP + 1
    for i = first, n do kept[#kept + 1] = lines[i] end
    file.Write(path, table.concat(kept, "\n") .. "\n")
end

local function rotateLogsOncePerMap()
    file.CreateDir(DIR)
    for _, rel in ipairs(ROTATED_FILES) do rotateFile(rel) end
end

local function receipt(line)
    appendLine("boot.txt", os.date("%Y-%m-%d %H:%M:%S") .. " " .. line)
end

local ERROR_CAP = 200
local function logError(event, name, err)
    local sig = event .. "|" .. tostring(name) .. "|" .. tostring(err)
    if G.errorSeen[sig] then return end
    if G.errorCount >= ERROR_CAP then return end
    G.errorSeen[sig] = true
    G.errorCount = G.errorCount + 1
    appendLine("errors.txt", string.format("%s [%s] %s: %s", os.date("%Y-%m-%d %H:%M:%S"), event, tostring(name), tostring(err)))
    ErrorNoHalt(string.format("[zc_round_guard] %s '%s' errored (fenced, transition continues): %s\n", event, tostring(name), tostring(err)))
end

hook.Add("PostCleanupMap", "ZCRoundGuard_ResetErrorCap", function()
    G.errorSeen = {}
    G.errorCount = 0
    rotateLogsOncePerMap()
end)

-- ---------------------------------------------------------------------------------------------
-- S1.1: per-listener fencing for ZB_PreRoundStart / ZB_StartRound / ZB_EndRound.
--
-- hook.GetTable() (ULib, addons/ulib/lua/ulib/shared/hook.lua:36) returns BackwardsHooks: a
-- FLAT { [id] = fn } map per event, independent of priority. hook.GetULibTable() (:37) returns
-- Hooks: { [event] = { [-2]={}, [-1]={}, [0]={}, [1]={}, [2]={} } }, each tier keyed by id ->
-- {fn=, isstring=} (:60) - THIS is where a listener's priority actually lives, so its current
-- tier is looked up there before re-registering it, and re-registered at that same priority via
-- hook.Add(event, id, wrapper, priority) - hook.Add itself does the priority-tier bookkeeping
-- (:42-63); this file only ever calls it with the SAME id and SAME priority a real listener was
-- already registered under, so no ordering changes.
local LISTENER_EVENTS = { "ZB_PreRoundStart", "ZB_StartRound", "ZB_EndRound" }

local function findPriority(event, id)
    local byPriority = hook.GetULibTable and hook.GetULibTable()[event]
    if not byPriority then return 0 end
    for i = -2, 2 do
        local tier = byPriority[i]
        if tier and tier[id] then return i end
    end
    return 0
end

local function makeListenerWrapper(event, id, fn)
    local wrapper = function(...)
        local r = { xpcall(fn, debug.traceback, ...) }
        if not r[1] then
            logError(event, id, r[2])
            return
        end
        return unpack(r, 2)
    end
    G.listenerWrapped[wrapper] = true
    G.listenerOriginalOf[wrapper] = fn
    return wrapper
end

-- Idempotent: safe to call every second (and immediately at InitPostEntity, and on demand from
-- the selftest). Re-wraps a listener that was replaced by its owner (hook.GetTable() shows a fn
-- that is not one of our wrappers) and forgets an id that no longer exists.
local function installListenerFence(event)
    if not hook.GetTable then return end
    local flat = hook.GetTable()[event]
    if not flat then return end
    local tracked = G.listenerTracked[event] or {}
    G.listenerTracked[event] = tracked

    for id in pairs(tracked) do
        if not flat[id] then tracked[id] = nil end -- removed by its owner: forget it
    end

    for id, fn in pairs(flat) do
        if isfunction(fn) and not G.listenerWrapped[fn] then
            local priority = findPriority(event, id)
            local wrapper = makeListenerWrapper(event, id, fn)
            hook.Add(event, id, wrapper, priority)
        end
        tracked[id] = true
    end
end

-- Restores every currently-wrapped id under `event` back to the original listener, at whatever
-- priority the wrapper currently holds (which is always the priority it was installed at, since
-- installListenerFence never changes it).
local function restoreListenerFence(event)
    if not hook.GetTable then return end
    local flat = hook.GetTable()[event]
    local tracked = G.listenerTracked[event]
    if not flat or not tracked then return end
    for id in pairs(tracked) do
        local current = flat[id]
        local original = current and G.listenerOriginalOf[current]
        if original then
            hook.Add(event, id, original, findPriority(event, id))
        end
    end
    G.listenerTracked[event] = nil
end

-- ---------------------------------------------------------------------------------------------
-- S1.1: per-mode-method fencing. See the file header for exactly why Intermission and PreRound
-- are not in this list.
local MODE_METHODS = { "RoundStart", "EndRound", "GiveEquipment" }

local function wrapModeMethod(modeName, methodName)
    local mode = zb and zb.modes and zb.modes[modeName]
    if not mode then return end
    local current = mode[methodName]
    if not isfunction(current) then return end
    local key = modeName .. "." .. methodName
    local rec = G.modeWraps[key]
    if rec and rec.wrapper == current then return end -- unchanged, still ours

    local original = (rec and current == rec.wrapper) and rec.original or current
    local wrapper = function(self, ...)
        local r = { xpcall(original, debug.traceback, self, ...) }
        if not r[1] then
            logError("mode", key, r[2])
            return
        end
        return unpack(r, 2)
    end
    mode[methodName] = wrapper
    G.modeWraps[key] = { original = original, wrapper = wrapper }
end

local function installModeWraps()
    if not zb or not zb.modes then return end
    for modeName in pairs(zb.modes) do
        for _, methodName in ipairs(MODE_METHODS) do
            wrapModeMethod(modeName, methodName)
        end
    end
end

local function restoreModeWraps()
    if not zb or not zb.modes then return end
    for key, rec in pairs(G.modeWraps) do
        local modeName, methodName = string.match(key, "^(.-)%.([^.]+)$")
        local mode = modeName and zb.modes[modeName]
        if mode and mode[methodName] == rec.wrapper then mode[methodName] = rec.original end
    end
    G.modeWraps = {}
end

-- Reset hygiene: sv_mapvote.lua:158/180 can leave zb.votestarted stuck true after a vote error,
-- which blocks zb:PreRound's own RTV check forever. zb.votestarted is safe to clear every round
-- start (PreRound/openBallot only ever set it true when a vote is actually opening). An
-- unconditional SolidMapVote.reset() every round start would also be safe to CALL, but would
-- cancel a vote that legitimately opened in the same instant it is invoked - so M.reset() only
-- runs when the flag is provably stuck (true, but nothing is actually open or pending).
hook.Add("ZB_StartRound", "ZCRoundGuard_RoundStartHygiene", function()
    if not cvGuard:GetBool() then return end
    local wasStuck = zb and zb.votestarted == true
    if zb then zb.votestarted = false end
    local M = SolidMapVote
    if wasStuck and M and M.initialized and isfunction(M.reset) and not M.isOpen and not M.pending then
        M.reset("Round guard: map-vote state was stuck after an earlier error.")
    end
end)

-- ---------------------------------------------------------------------------------------------
-- S1.2 stuck-round watchdog. Independent of zc_round_guard; gated purely by
-- zc_round_watchdog_seconds > 0 (default 0 = off).
local function killcamHolding()
    local K = ZCKillcam
    if K and isfunction(K.HighlightHolding) then
        local ok, holding = pcall(K.HighlightHolding)
        return ok and holding == true
    end
    return false -- predicate not loaded yet: err toward NOT holding rather than never firing
end

local function mapVoteActive()
    local M = SolidMapVote
    return (M ~= nil and (M.isOpen == true or M.pending == true)) or (zb ~= nil and zb.votestarted == true)
end

local function modeVoteActive()
    return isfunction(ZC_MODEVOTE_ACTIVE) and ZC_MODEVOTE_ACTIVE() == true
end

-- A watchdog under ~30s can race legitimate work (a map vote opening between rounds, a killcam
-- hold - sv_highlight.lua's own HOLD_MAX is 20s, `local CARD, FADES, GM_FADE, HOLD_MAX,
-- PACK_TIME = 1.25, 1.0, 1.5, 20, 1`, mirror ~line 21) - reviewer-requested clamp, warned once
-- per drop below the floor rather than silently overridden.
local MIN_WATCHDOG_SECONDS = 30
local HOLD_MAX = 20 -- sv_highlight.lua's own HOLD_MAX, cited above; not importable, so mirrored
local FAR_FUTURE_MARGIN = HOLD_MAX + 10
local warnedLowWatchdog = false
local function effectiveWatchdogSeconds()
    local seconds = cvWatchdog:GetInt()
    if seconds <= 0 then
        warnedLowWatchdog = false
        return 0
    end
    if seconds < MIN_WATCHDOG_SECONDS then
        if not warnedLowWatchdog then
            warnedLowWatchdog = true
            ErrorNoHalt(string.format("[zc_round_guard] zc_round_watchdog_seconds=%d is below the safe minimum; using %d instead.\n", seconds, MIN_WATCHDOG_SECONDS))
        end
        return MIN_WATCHDOG_SECONDS
    end
    warnedLowWatchdog = false
    return seconds
end

local function watchdogLog(reason)
    appendLine("watchdog.txt", string.format(
        "%s state=%s END_TIME=%s START_TIME=%s votestarted=%s mode=%s highlight_holding=%s map_vote=%s mode_vote=%s reason=%s",
        os.date("%Y-%m-%d %H:%M:%S"), tostring(zb and zb.ROUND_STATE), tostring(zb and zb.END_TIME),
        tostring(zb and zb.START_TIME), tostring(zb and zb.votestarted), tostring(zb and zb.CROUND),
        tostring(killcamHolding()), tostring(mapVoteActive()), tostring(modeVoteActive()), reason))
    G.watchdogFires = G.watchdogFires + 1
end

-- Release exactly as zc_killcam_unstick does: reuse K.Highlight.Unstick (sv_highlight.lua:355,
-- exported at :418 as H.Unstick) when present; otherwise duplicate its minimal release only
-- (set END_TIME = CurTime() - 1). Never changelevel from here.
--
-- H.Unstick has NO return value on either path (verified: both its release branch and its
-- decline-within-GRACE branch, sv_highlight.lua :355-372, end in a bare `return`) - so whether it
-- actually acted is inferred from whether END_TIME is now in the past, not from a return value
-- that does not exist. If it declined (END_TIME still in the future - e.g. still inside its own
-- GRACE window), this does NOT force its own duplicate release that tick: it logs and returns
-- false, and watchdogTick leaves lastStateAt untouched so the very next tick (not the next full
-- watchdog window) retries.
local function releaseStuckIntermission(reason)
    watchdogLog(reason)
    local H = ZCKillcam and ZCKillcam.Highlight
    if H and isfunction(H.Unstick) then
        pcall(H.Unstick)
        if zb and isnumber(zb.END_TIME) and zb.END_TIME <= CurTime() then
            return true
        end
        watchdogLog(reason .. " (ZCKillcam.Highlight.Unstick declined this tick; not forcing, will retry next tick)")
        return false
    end
    if zb and zb.ROUND_STATE == 3 then
        local e = zb.END_TIME
        if e == nil or not isnumber(e) or e ~= e or e == math.huge or e > CurTime() then
            zb.END_TIME = CurTime() - 1
            return true
        end
    end
    return false
end

-- Every state-3 release path (bad END_TIME, far-future END_TIME, or plain stuck-past-deadline)
-- shares ONE gate: elapsed > seconds AND not mapVoteActive AND not modeVoteActive AND not
-- killcamHolding. An earlier draft let the bad/far-future check skip that gate entirely, so it
-- could fire a single tick after entering state 3 - fixed here.
local lastState, lastStateAt = nil, 0
local function watchdogTick()
    if not zb then return end
    local seconds = effectiveWatchdogSeconds()
    if seconds <= 0 then lastState = nil return end

    local state = zb.ROUND_STATE
    if state ~= lastState then
        lastState, lastStateAt = state, CurTime()
        return
    end
    local elapsed = CurTime() - lastStateAt

    if state == 3 then
        if elapsed <= seconds then return end
        if mapVoteActive() or modeVoteActive() or killcamHolding() then return end

        local e = zb.END_TIME
        local bad = e ~= nil and (not isnumber(e) or e ~= e or e == math.huge)
        local farFutureThreshold = CurTime() + math.max(seconds, FAR_FUTURE_MARGIN)
        local farFuture = (not bad) and e ~= nil and isnumber(e) and e > farFutureThreshold

        local reason
        if bad then
            reason = "END_TIME is not a finite number"
        elseif farFuture then
            reason = string.format("END_TIME %.0fs past the watchdog+hold margin", e - farFutureThreshold)
        else
            reason = string.format("state 3 stuck %.0fs, no vote active, highlight not holding", elapsed)
        end

        if releaseStuckIntermission(reason) then lastStateAt = CurTime() end
        return
    end

    if state == 0 and zb.START_TIME == nil and elapsed > seconds and #player.GetAll() > 1 then
        -- Dossier only: the blueprint's release mechanism (END_TIME = CurTime()) is state-3
        -- specific. Forcing START_TIME here would bypass zb:PreRound's own RTV/map-count gating
        -- instead of releasing a wedge, so this case logs and does not act.
        watchdogLog(string.format("state 0 stuck %.0fs with START_TIME nil and >1 player (log only, no release defined)", elapsed))
        lastStateAt = CurTime()
    end
end

-- ---------------------------------------------------------------------------------------------
-- InitPostEntity + 1s re-install timer (same pattern as zc_ff_brain.lua's InstallDamagePriority
-- and zzz_zcj_ownership_repair.lua's boot repair): idempotent, safe to call every second.
local function ensureInstalled()
    if cvGuard:GetBool() then
        for _, event in ipairs(LISTENER_EVENTS) do installListenerFence(event) end
        installModeWraps()
    else
        for _, event in ipairs(LISTENER_EVENTS) do restoreListenerFence(event) end
        restoreModeWraps()
    end
end

hook.Add("InitPostEntity", "ZCRoundGuard_Install", function()
    ensureInstalled()
    rotateLogsOncePerMap()
    receipt(string.format("boot version=%s guard=%d watchdog=%d", G.Version, cvGuard:GetInt(), cvWatchdog:GetInt()))
end)
timer.Create("ZCRoundGuard_Install", 1, 0, ensureInstalled)
timer.Create("ZCRoundGuard_Watchdog", 1, 0, watchdogTick)

cvars.AddChangeCallback("zc_round_guard", function(_, _, new)
    ensureInstalled()
    receipt(string.format("convar zc_round_guard changed to %s", tostring(new)))
end, "ZCRoundGuard_Toggle")

-- If the file loaded after InitPostEntity already fired (a reload, not a fresh boot - autorefresh
-- does not fire on US1, but this stays correct if the file is ever pushed and the server restarted
-- mid-session-tools), try once immediately too.
if hook.GetULibTable then ensureInstalled() end

-- ---------------------------------------------------------------------------------------------
-- Staff console commands.
--
-- Selftest: registers two throwaway ZB_PreRoundStart listeners (A errors, B just flips a flag),
-- force-installs the listener fence for that event immediately (not waiting for the 1s timer),
-- then calls the two installed WRAPPER functions DIRECTLY - never hook.Run/hook.Call. Dispatching
-- the real ZB_PreRoundStart event would fire every production listener on it mid-round (killcam
-- tape/recorder resets, traitor unfreeze, bot state resets - roughly 40 listeners observed on
-- this server via hook.GetTable()["ZB_PreRoundStart"]) for the sake of a staff command; calling
-- the two wrappers by hand exercises exactly the fencing logic and nothing else. Passes only if
-- errors.txt gained exactly one line for A AND B still ran (proving A's fenced error did not stop
-- B from being called).
concommand.Add("zc_round_guard_selftest", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local function reply(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
    if not cvGuard:GetBool() then
        reply("[RoundGuard] zc_round_guard is 0; enable it first (a selftest run now would not be fenced).")
        return
    end

    local ID_A, ID_B = "ZCRoundGuard_SelfTestA", "ZCRoundGuard_SelfTestB"
    local bRan = false
    hook.Add("ZB_PreRoundStart", ID_A, function() error("zc_round_guard_selftest deliberate error") end, -1)
    hook.Add("ZB_PreRoundStart", ID_B, function() bRan = true end, 0)
    installListenerFence("ZB_PreRoundStart") -- wrap both right now, do not wait for the timer

    local flat = hook.GetTable and hook.GetTable()["ZB_PreRoundStart"]
    local wrapperA = flat and flat[ID_A]
    local wrapperB = flat and flat[ID_B]

    local before, after = G.errorCount, G.errorCount
    local installedOk = isfunction(wrapperA) and isfunction(wrapperB)
    if installedOk then
        pcall(wrapperA)
        pcall(wrapperB)
        after = G.errorCount
    end

    hook.Remove("ZB_PreRoundStart", ID_A)
    hook.Remove("ZB_PreRoundStart", ID_B)

    if not installedOk then
        reply("[RoundGuard] selftest FAIL: the fence did not install wrappers for the test listeners.")
        return
    end
    local pass = (after > before) and bRan
    reply(string.format("[RoundGuard] selftest: errors.txt lines before=%d after=%d, following listener ran=%s - %s",
        before, after, tostring(bRan), pass and "PASS (fenced; the round would not have been blocked)"
            or "FAIL (either no error was recorded, or the next listener did not run)"))
end)

concommand.Add("zc_round_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local function reply(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
    reply(string.format("[RoundGuard] %s guard=%d watchdog=%ds (effective %ds)", G.Version, cvGuard:GetInt(), cvWatchdog:GetInt(), effectiveWatchdogSeconds()))
    reply(string.format("  ROUND_STATE=%s END_TIME=%s START_TIME=%s votestarted=%s CROUND=%s",
        tostring(zb and zb.ROUND_STATE), tostring(zb and zb.END_TIME), tostring(zb and zb.START_TIME),
        tostring(zb and zb.votestarted), tostring(zb and zb.CROUND)))
    reply(string.format("  errors logged=%d watchdog fires=%d highlight_holding=%s map_vote_active=%s mode_vote_active=%s",
        G.errorCount, G.watchdogFires, tostring(killcamHolding()), tostring(mapVoteActive()), tostring(modeVoteActive())))
    for _, event in ipairs(LISTENER_EVENTS) do
        local tracked = G.listenerTracked[event]
        reply(string.format("  listeners fenced on %s: %d", event, tracked and table.Count(tracked) or 0))
    end
    local modeCount = 0
    for _ in pairs(G.modeWraps) do modeCount = modeCount + 1 end
    reply(string.format("  mode methods fenced: %d (%s)", modeCount, table.concat(MODE_METHODS, "/")))
end)
