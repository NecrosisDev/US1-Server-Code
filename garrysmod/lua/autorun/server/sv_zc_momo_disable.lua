-- Removes the SetupMove/momo_tf2_movemod hook (workshop-mounted lua/includes/modules/
-- ppp_includes/tf2lib.lua, installed via includes/modules/pk_pills.lua:1211).
--
-- WHY: it is the server's #1 Lua allocator, ~2.9 MB/s (2086-2088 B/call, one ply:GetWeapons()
-- table build per player per usercmd) for a branch that can never fire: it multiplies player speed
-- by wep:momo_SpeedMod() for any weapon where `wep.momo_SpeedMod` is truthy, and across every
-- mounted Lua file on this server (4227 files, loose + every Workshop GMA, both realms) the exact
-- identifier `momo_SpeedMod` occurs in exactly one place -- its own check/call site in tf2lib.lua.
-- Verified against 520 registered weapons by walking each SWEP.Base chain to its root (not just the
-- leaf table -- a leaf-only scan is proven unreliable here: it undercounts a real, common field,
-- HoldType, by 19/520 versus the chain walk), against every live weapon entity, every currently
-- held weapon, and the Weapon/Entity/Player metatables. Full evidence ladder, all commands and raw
-- output: outputs/perf-20260921/notes_I.md (agent I2, 2026-09-21).
--
-- Console `hook.Remove` of this hook lasts only until the next map change (confirmed reverted twice
-- in one day) because pk_pills.lua re-installs it, unconditionally, every map load. This file lives
-- under lua/autorun/server/, so the engine re-executes it fresh on every map load too -- the same
-- mechanism that reverts a console removal is what makes this removal self-reapplying.
--
-- Safety:
--  * Idempotent: re-running this file (same map, e.g. a manual re-source) finds the hook already
--    gone and no-ops instead of double-removing or clobbering the saved original.
--  * Guarded: only removes a hook whose debug.getinfo identity (short_src/linedefined/
--    lastlinedefined) matches the exact body this evidence was gathered against. If the addon ever
--    changes that function, the identity check fails and this script refuses to touch it -- it does
--    NOT compare bytecode (a slow, brittle method that cost an earlier session its whole attempt).
--  * No-ops safely if the hook is already absent for any reason.
--  * Retried: the trigger is a named, bounded, self-cancelling timer rather than a single
--    hook, because a single InitPostEntity listener was measured NOT to run on a live map
--    load (see the trigger block at the bottom of this file for the dispatcher evidence).
--  * Saves the removed function so an admin can put it back without a restart:
--    `lua_run ZC_MomoDisable.Restore()`.
if not SERVER then return end

local D = ZC_MomoDisable or {}
ZC_MomoDisable = D
D.Version = "20260922.1"

-- Pin: the exact identity of the hook body this removal has been verified safe against.
-- Captured 2026-09-21 via debug.getinfo(hook.GetTable().SetupMove.momo_tf2_movemod,'S'),
-- reproduced identically across three separate probes (notes_I.md probes 1, 5, 11).
local EXPECT_SRC   = "lua/includes/modules/ppp_includes/tf2lib.lua"
local EXPECT_START = 4
local EXPECT_END   = 25

local function log(msg)
    print("[zc_momo_disable] " .. msg)
    file.CreateDir("zc_momo_disable")
    file.Append("zc_momo_disable/log.txt", os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. msg .. "\n")
end

-- Returns true if it removed the hook this map load, false otherwise (already absent, already
-- removed, or the installed body no longer matches the pinned identity).
function D.Apply()
    local listeners = hook.GetTable().SetupMove
    local fn = listeners and listeners.momo_tf2_movemod

    if not fn then
        log("no-op: SetupMove/momo_tf2_movemod is absent (already removed this map, or the addon " ..
            "is gone) -- nothing to do")
        return false
    end

    local info = debug.getinfo(fn, "S")
    if not info or info.short_src ~= EXPECT_SRC or info.linedefined ~= EXPECT_START
        or info.lastlinedefined ~= EXPECT_END then
        log(string.format(
            "no-op: installed hook body does not match the pinned identity (got %s:%s-%s, " ..
            "expected %s:%d-%d) -- the addon likely changed; refusing to remove an unverified body",
            tostring(info and info.short_src), tostring(info and info.linedefined),
            tostring(info and info.lastlinedefined), EXPECT_SRC, EXPECT_START, EXPECT_END))
        return false
    end

    D.saved = fn
    D.savedMap = game.GetMap()
    hook.Remove("SetupMove", "momo_tf2_movemod")
    log(string.format("removed SetupMove/momo_tf2_movemod on map %s (pin %s:%d-%d)",
        D.savedMap, EXPECT_SRC, EXPECT_START, EXPECT_END))
    return true
end

-- Puts the saved original back, if there is one and the slot is still free. Safe to call any time,
-- any number of times: no-ops if nothing is saved, or if something already occupies the slot.
function D.Restore()
    if not D.saved then
        log("restore no-op: nothing saved this map load")
        return false
    end
    local listeners = hook.GetTable().SetupMove
    if listeners and listeners.momo_tf2_movemod then
        log("restore no-op: SetupMove/momo_tf2_movemod is already present")
        return false
    end
    hook.Add("SetupMove", "momo_tf2_movemod", D.saved)
    log("restored SetupMove/momo_tf2_movemod")
    D.saved = nil
    return true
end

-- ---------------------------------------------------------------------------------------------
-- TRIGGER: a bounded, self-cancelling retry.
--
-- 20260922.1. This file originally shipped one trigger,
-- hook.Add("InitPostEntity", "zc_momo_disable_apply", D.Apply), on the reasoning that
-- pk_pills.lua's include() always runs ahead of InitPostEntity. On a live map load that trigger
-- did not run: the file had loaded (D.Version set, the listener registered) and the live hook
-- matched the pin exactly, yet momo_tf2_movemod was still installed, D.saved was false, and the
-- log gained no line at all. Every branch of D.Apply() logs, so Apply was never reached.
--
-- Two mechanisms can cause that, and this file has to survive both:
--   (a) the hook is installed LATER than InitPostEntity fires, or
--   (b) the InitPostEntity dispatch never reaches our listener. lua/includes/modules/hook.lua
--       iterates listeners with pairs() -- arbitrary order -- and returns early the moment any
--       listener returns a non-nil value, skipping every remaining listener. There are 120
--       InitPostEntity registrations on this server, and pairs() order is not stable between
--       map loads.
-- A retry loop on a named timer is immune to both, so no diagnosis between them is needed.
--
-- The same dispatcher rule is why the InitPostEntity listener below is WRAPPED: D.Apply returns
-- true/false and never nil, so passing it to hook.Add directly (as this file used to) aborted
-- InitPostEntity for every listener ordered after it and for GM:InitPostEntity itself.
local TIMER_NAME = "zc_momo_disable_retry"
local RETRY_INTERVAL = 5   -- seconds between attempts
local MAX_ATTEMPTS = 24    -- 24 * 5 s = a 120 s window, measured from the map's first server frame

-- Ends the run for the rest of this map load. D.done makes every other trigger (a later timer
-- tick, the InitPostEntity listener, a re-include) a no-op, so the hook is never removed twice.
function D.Stop(reason)
    D.done = true
    if timer.Exists(TIMER_NAME) then timer.Remove(TIMER_NAME) end
    if reason then log(reason) end
end

-- One attempt. Returns true once the hook has been removed.
function D.Tick(source)
    if D.done then return false end
    D.attempts = (D.attempts or 0) + 1
    local attempt = D.attempts

    local listeners = hook.GetTable().SetupMove
    local present = listeners ~= nil and listeners.momo_tf2_movemod ~= nil

    -- D.Apply() logs on EVERY branch, so it is only called when it has something real to say:
    -- the hook is actually installed, or this is the first attempt (whose log line is the proof
    -- that the trigger ran at all -- precisely the evidence that was missing before). Silent
    -- ticks are what keep this from writing a line every 5 s for two minutes.
    if present or attempt == 1 then
        if D.Apply() then
            D.Stop(string.format(
                "retry: removed on attempt %d of %d (trigger: %s) -- loop cancelled",
                attempt, MAX_ATTEMPTS, tostring(source)))
            return true
        end
        if present then
            -- Apply() has already logged exactly which identity it refused. pk_pills.lua installs
            -- this hook once per map load and never mid-round, so an installed-but-unpinned body
            -- will not become a pinned one later this map; retrying would only repeat that line.
            D.Stop(string.format(
                "retry: stopping on attempt %d -- the hook is installed but its body does not " ..
                "match the pin (reason logged above)", attempt))
            return false
        end
    end

    if attempt >= MAX_ATTEMPTS then
        D.Stop(string.format(
            "retry: gave up after %d attempts over %d s -- SetupMove/momo_tf2_movemod never " ..
            "appeared this map load", attempt, MAX_ATTEMPTS * RETRY_INTERVAL))
    end
    return false
end

-- Arms the retry loop. Safe to call any number of times: the timer is NAMED, so a re-include of
-- this file replaces the existing timer instead of stacking a second one, and D.done
-- short-circuits a run that has already finished.
--
-- The first attempt is deliberately NOT made here at file-execution time. Timers only tick on
-- server frames, i.e. after the entire Lua load pass, which removes the one race this file could
-- otherwise lose: removing the hook a moment BEFORE pk_pills.lua installs it.
function D.Start()
    if D.done then
        log("start no-op: this map load already finished (hook removed, or the window expired)")
        return false
    end
    -- Late-bound through D.Tick so a re-include's new body is the one that runs.
    timer.Create(TIMER_NAME, RETRY_INTERVAL, 0, function() D.Tick("timer") end)
    log(string.format("armed %s: retrying every %d s for up to %d s",
        tostring(D.Version), RETRY_INTERVAL, MAX_ATTEMPTS * RETRY_INTERVAL))
    return true
end

-- Belt and braces: when InitPostEntity DOES reach us it removes the hook seconds earlier than the
-- first timer tick. The wrapper swallows D.Tick's return value (see the dispatcher note above).
hook.Add("InitPostEntity", "zc_momo_disable_apply", function() D.Tick("InitPostEntity") end)

D.Start()
