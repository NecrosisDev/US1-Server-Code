--[[----------------------------------------------------------------------------
    sv_zc_gore_splitphys.lua -- redundancy gate for ZCity Gore V2's split-ragdoll weld.

    ZCity Gore V2 (workshop 3780773397, GMA-mounted, not editable) registers
    Think / "ZCity Gore V2_SplitPhysics" at lua/autorun/z_podgruz.lua:806-828.
    Every frame, for every split body, it re-applies a manual weld:

        ForceHiddenPhys(rag,   upperPhysParents)   -- SetPos/SetAngles/SetVelocity
        ForceHiddenPhys(lower, lowerPhysParents)   -- on each hidden phys object
        UpdateCap(upperCap); UpdateCap(lowerCap)

    Every hidden phys object in those maps is frozen at construction time --
    ConfigureHiddenPhys (z_podgruz.lua:419-426) calls EnableCollisions(false),
    SetMass(0.01) and EnableMotion(false) -- and each is pinned to ONE anchor:
    spine2 for the upper half (BuildUpperHalf:465,474), pelvis for the lower
    (BuildLowerHalf:500,507). Only the anchor ever moves.

    So when the anchor's position, angles and velocity are all unchanged since
    the last frame we applied, every value those calls would write is identical
    to the value already there, and the whole half can be skipped. This is
    redundancy removal, not approximation: we do not reimplement any of the
    addon's logic, we call ITS OWN ForceHiddenPhys and UpdateCap upvalues and
    only decide whether the call is needed.

    A severed torso lies on the floor for the rest of the round, so the settled
    state is the dominant one.

    Ships INERT, per house style: zc_gore_splitgate defaults to 0 = OBSERVE,
    which counts the redundant frames and changes nothing at all. Flip to 1
    only once the observed skip rate justifies it.
------------------------------------------------------------------------------]]

if not SERVER then return end

local VERSION = "20260922.1"

-- The original registration we replace. Event + name must match byte for byte:
-- re-registering the same pair replaces the listener in place.
local EVENT = "Think"
local TAG   = "ZCity Gore V2_SplitPhysics"

-- Identity pin for the body we are willing to displace. If the workshop addon
-- updates, every one of these moves and we refuse rather than silently running
-- a gate against a loop we have not read.
local SRC     = "lua/autorun/z_podgruz.lua"
local L0, L1  = 806, 828
local NUPS    = 4
local UPNAMES = { "splitStates", "ForceHiddenPhys", "UpdateCap", "torsoStates" }

local MODE = CreateConVar("zc_gore_splitgate", "0", FCVAR_ARCHIVE,
    "ZCity Gore V2 split-physics gate. 0 = observe (count only, change nothing), 1 = active (skip redundant frames)")

local stats = {
    frames = 0,
    skipUpper = 0, workUpper = 0,
    skipLower = 0, workLower = 0,
    installs = 0, reinstalls = 0,
}

local G = { installed = false, ours = nil, orig = nil, why = "not attempted" }

local function log(msg)
    MsgN("[GoreSplitGate] " .. msg)
end

--------------------------------------------------------------------------------
-- identity guard
--------------------------------------------------------------------------------

-- Returns the original's upvalues by name, or nil plus the reason we refused.
local function Verify(fn)
    if not isfunction(fn) then return nil, "hook absent" end

    local i = debug.getinfo(fn, "Su")
    if not i then return nil, "no debug info" end
    if i.short_src ~= SRC then return nil, "short_src is " .. tostring(i.short_src) end
    if i.linedefined ~= L0 or i.lastlinedefined ~= L1 then
        return nil, ("lines %s-%s, expected %d-%d"):format(
            tostring(i.linedefined), tostring(i.lastlinedefined), L0, L1)
    end
    if i.nups ~= NUPS then return nil, "nups " .. tostring(i.nups) .. ", expected " .. NUPS end

    local up = {}
    for n = 1, NUPS do
        local name, value = debug.getupvalue(fn, n)
        if name ~= UPNAMES[n] then
            return nil, ("upvalue %d is %s, expected %s"):format(n, tostring(name), UPNAMES[n])
        end
        up[name] = value
    end

    if type(up.splitStates) ~= "table" then return nil, "splitStates is not a table" end
    if type(up.torsoStates) ~= "table" then return nil, "torsoStates is not a table" end
    if not isfunction(up.ForceHiddenPhys) then return nil, "ForceHiddenPhys is not a function" end
    if not isfunction(up.UpdateCap) then return nil, "UpdateCap is not a function" end

    return up
end

--------------------------------------------------------------------------------
-- the gated loop
--------------------------------------------------------------------------------

local function MakeThink(up)
    local splitStates, torsoStates = up.splitStates, up.torsoStates
    local ForceHiddenPhys, UpdateCap = up.ForceHiddenPhys, up.UpdateCap

    -- Every entry in a phys-parent map points at the same anchor, so any value
    -- is the anchor. NOTE: physID 0 is a legitimate anchor -- BuildLowerHalf:488
    -- falls back to pelvisPhysID = 0 -- so "no anchor" must mean nil and nothing
    -- else. Never add a zero test here; it would silently stop gating every
    -- lower half whose pelvis is phys 0.
    local function AnchorOf(map)
        if type(map) ~= "table" then return nil end
        for _, parentID in pairs(map) do return parentID end
        return nil
    end

    -- True when every value this half's ForceHiddenPhys/UpdateCap would write
    -- equals the value written on the last frame we applied.
    local function Redundant(state, ent, map, anchorField, cacheField)
        local anchorID = state[anchorField]
        if anchorID == nil then
            anchorID = AnchorOf(map)
            if anchorID == nil then return false end   -- empty map: never gate
            state[anchorField] = anchorID
        end

        local phys = ent:GetPhysicsObjectNum(anchorID)
        if not IsValid(phys) then return false end

        local pos, ang, vel = phys:GetPos(), phys:GetAngles(), phys:GetVelocity()
        local c = state[cacheField]
        if c and c.ent == ent and c.pos == pos and c.ang == ang and c.vel == vel then
            return true
        end

        state[cacheField] = { ent = ent, pos = pos, ang = ang, vel = vel }
        return false
    end

    return function()
        local active = MODE:GetInt() >= 1
        stats.frames = stats.frames + 1

        for state in pairs(splitStates) do
            local ragValid   = state and IsValid(state.rag)
            local lowerValid = state and IsValid(state.lower)

            if not ragValid and not lowerValid then
                splitStates[state] = nil
            else
                if ragValid then
                    local skip = Redundant(state, state.rag, state.upperPhysParents,
                                           "__gateUpperAnchor", "__gateUpperCache")
                    if skip then stats.skipUpper = stats.skipUpper + 1
                    else stats.workUpper = stats.workUpper + 1 end

                    if not (skip and active) then
                        ForceHiddenPhys(state.rag, state.upperPhysParents)
                        if IsValid(state.upperCap) then UpdateCap(state.upperCap) end
                    end
                end

                if lowerValid then
                    local skip = Redundant(state, state.lower, state.lowerPhysParents,
                                           "__gateLowerAnchor", "__gateLowerCache")
                    if skip then stats.skipLower = stats.skipLower + 1
                    else stats.workLower = stats.workLower + 1 end

                    if not (skip and active) then
                        ForceHiddenPhys(state.lower, state.lowerPhysParents)
                        if IsValid(state.lowerCap) then UpdateCap(state.lowerCap) end
                    end
                end
            end
        end

        -- unchanged from the original (z_podgruz.lua:823-827)
        for ply, state in pairs(torsoStates) do
            if not IsValid(ply) or not ply:Alive()
                or not ply:GetNWBool("ZCityTorsoSevered", false) or not state then
                torsoStates[ply] = nil
            end
        end
    end
end

--------------------------------------------------------------------------------
-- install, with the patch29 retry pattern
--------------------------------------------------------------------------------

local RETRY_EVERY, RETRY_MAX = 5, 24
local RETRY_TIMER = "zc_gore_splitgate_retry"
local WATCH_TIMER = "zc_gore_splitgate_watch"

local function TryInstall(trigger)
    local listeners = hook.GetTable()[EVENT]
    local current = listeners and listeners[TAG]

    if G.ours ~= nil and current == G.ours then return true end

    local up, why = Verify(current)
    if not up then
        G.why = why
        return false, why
    end

    G.orig = current
    G.ours = MakeThink(up)
    -- same event + same name replaces the listener; nothing is returned into dispatch
    hook.Add(EVENT, TAG, G.ours)
    G.installed = true
    G.why = "ok"
    stats.installs = stats.installs + 1
    log(("installed %s over %s:%d-%d (trigger: %s, mode: %s)"):format(
        VERSION, SRC, L0, L1, trigger, MODE:GetInt() >= 1 and "ACTIVE" or "OBSERVE"))
    return true
end

local attempts = 0
timer.Create(RETRY_TIMER, RETRY_EVERY, RETRY_MAX, function()
    attempts = attempts + 1
    local ok, why = TryInstall("timer")
    if ok then
        timer.Remove(RETRY_TIMER)
        log(("armed on attempt %d of %d"):format(attempts, RETRY_MAX))
    elseif attempts >= RETRY_MAX then
        log(("gave up after %d attempts: %s"):format(attempts, tostring(why)))
    end
end)

-- Autorefresh is on for this server and re-including z_podgruz would re-register
-- the original over us, silently. Cheap periodic re-check; one table lookup.
timer.Create(WATCH_TIMER, 30, 0, function()
    if not G.installed then return end
    local listeners = hook.GetTable()[EVENT]
    if listeners and listeners[TAG] ~= G.ours then
        log("original registration returned -- reinstalling")
        G.ours = nil
        stats.reinstalls = stats.reinstalls + 1
        TryInstall("watchdog")
    end
end)

--------------------------------------------------------------------------------
-- operator surface
--------------------------------------------------------------------------------

concommand.Add("zc_gore_splitgate_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local su, wu = stats.skipUpper, stats.workUpper
    local sl, wl = stats.skipLower, stats.workLower
    local total = su + wu + sl + wl
    local pct = total > 0 and ((su + sl) / total * 100) or 0

    log(("v%s | %s | installed=%s (%d installs, %d reinstalls) | last: %s"):format(
        VERSION, MODE:GetInt() >= 1 and "ACTIVE (skipping)" or "OBSERVE (counts only, changes nothing)",
        tostring(G.installed), stats.installs, stats.reinstalls, G.why))
    log(("frames %d | upper skip %d / work %d | lower skip %d / work %d | redundant %.1f%% of %d half-updates"):format(
        stats.frames, su, wu, sl, wl, pct, total))
end, nil, "Superadmin: print the gore split-physics gate status.")

-- Live rollback lever: hand the original registration back, untouched.
concommand.Add("zc_gore_splitgate_restore", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    if not G.installed or not isfunction(G.orig) then
        log("restore: nothing to restore")
        return
    end
    timer.Remove(WATCH_TIMER)
    timer.Remove(RETRY_TIMER)
    hook.Add(EVENT, TAG, G.orig)
    G.installed, G.ours = false, nil
    G.why = "restored by command"
    log("restore: original ZCity Gore V2 registration is live again")
end, nil, "Superadmin: remove the split-physics gate and restore Gore V2's original.")

log(("loaded %s -- arming, retry every %ds for up to %ds"):format(
    VERSION, RETRY_EVERY, RETRY_EVERY * RETRY_MAX))
