-- Boot-time repair for a source-ownership collision that disables the Justice v3 bridge.
--
-- WHAT BREAKS: lua/zc_killcam/sv_tape.lua:959 WRAPS includes {"AttackFront","weapon_hands_sh"}
-- and {"Attack","weapon_melee"}; its wrapWeapons() runs at file load AND again on InitPostEntity
-- (sv_tape.lua:993). Its only re-entrancy guard is `not T.wrapped[original]`, which stops it
-- re-wrapping its OWN wrapper but not the Justice bridge's. Running after the bridge installed, it
-- does stored[name]=wrapper and takes two slots the bridge audits. The bridge's ownership sweep
-- (bridge.lua:334-338) then hits w.table[w.key]~=w.wrapper and calls Issue('ownership_changed'),
-- which sets self.enabled=false and stats.errors=1 (bridge.lua:39-46).
-- CONSEQUENCE: deployment_verify.lua:25 asserts runtime.enabled and aborts BEFORE the hash loop at
-- :29-40, so none of the 39 pinned medical files is verified. :26 (stats.errors==0) and :70
-- (per-wrapper ownership) would fail for the same reason, so relaxing :25 could never work --
-- ownership has to be genuinely restored.
--
-- WHAT THIS DOES: after InitPostEntity has finished (so the killcam has already wrapped), if any
-- bridge wrapper has lost its slot, re-include the shadow autorun. That stops the stale bridge and
-- observer and builds fresh ones whose Wrap() captures the current (killcam-owned) functions as
-- `original`, so BOTH systems stay in the call chain and the bridge legitimately owns the outermost
-- slot again, with enabled=true and stats.errors=0. Does nothing at all when ownership is intact.
--
-- Observer-only. Adds no gameplay behaviour, no enforcement, no net message, no player write.
if not SERVER then return end

local NAME = "ZCJOwnershipRepair"
local SHADOW = "autorun/server/zc_justice_v3_shadow.lua"
local ATTEMPTS = { 2, 5, 9 } -- seconds after InitPostEntity; all inside the verifier's 15 x 1 s window

-- Labels of every bridge wrapper whose slot is no longer the bridge's own function.
local function lostLabels()
    local runtime = ZCJusticeV3Integration
    if not runtime or type(runtime.wrappers) ~= "table" then return nil end
    local lost = {}
    for _, w in ipairs(runtime.wrappers) do
        if w.table and w.table[w.key] ~= w.wrapper then lost[#lost + 1] = w.label end
    end
    return lost
end

local function describe(lost)
    return #lost .. (#lost > 0 and (" (" .. table.concat(lost, ", ") .. ")") or "")
end

-- PROVISIONAL(2026-09-22, repairing automatically at boot is a policy choice the task did not
-- dictate: the alternative is to leave the bridge disabled and only report. Chosen because the
-- medical manifest verifies nothing at all until the bridge is healthy, ratify-by: 2026-10-20)
local function repair(why)
    local runtime = ZCJusticeV3Integration
    if not runtime then
        return false, "no ZCJusticeV3Integration; Justice v3 is not installed"
    end
    local lost = lostLabels()
    if not lost then return false, "integration has no wrappers table" end
    -- "Healthy" must mean the same thing here as it does in attempt(), and the same thing
    -- deployment_verify.lua asks for: :25 enabled, :26 stats.errors == 0, :70 every slot owned.
    -- Leaving stats.errors out would strand a bridge that is enabled and owns its slots but still
    -- carries a recorded error, because :26 would keep failing with nothing ever repairing it.
    if #lost == 0 and runtime.enabled and runtime.stats and runtime.stats.errors == 0 then
        return false, "ownership intact, bridge enabled, no recorded errors; nothing to repair"
    end

    -- zc_justice_v3_shadow.lua:4-5 returns early when BOTH observer and integration are enabled,
    -- so a bridge that has lost a slot but not yet noticed must be stopped first or the
    -- re-include is a no-op.
    if runtime.enabled and type(runtime.Stop) == "function" then runtime:Stop() end

    local ok, err = pcall(include, SHADOW)
    if not ok then
        return false, "re-include failed: " .. tostring(err)
    end

    local after = lostLabels()
    local fresh = ZCJusticeV3Integration
    local healthy = after and #after == 0 and fresh and fresh.enabled
        and fresh.stats and fresh.stats.errors == 0
    return healthy and true or false,
        string.format("%s: lost before=%s after=%s enabled=%s errors=%s",
            why, describe(lost), after and describe(after) or "?",
            tostring(fresh and fresh.enabled), tostring(fresh and fresh.stats and fresh.stats.errors))
end

local function attempt(index)
    local lost = lostLabels()
    if lost and #lost == 0 and ZCJusticeV3Integration and ZCJusticeV3Integration.enabled
        and ZCJusticeV3Integration.stats and ZCJusticeV3Integration.stats.errors == 0 then
        return -- healthy boot: stay silent and do nothing
    end
    local ok, detail = repair("boot attempt " .. index)
    print("[" .. NAME .. "] " .. (ok and "REPAIRED" or "not repaired") .. " -- " .. tostring(detail))
    if not ok and ATTEMPTS[index + 1] then
        timer.Simple(ATTEMPTS[index + 1] - ATTEMPTS[index], function() attempt(index + 1) end)
    end
end

hook.Add("InitPostEntity", NAME, function()
    hook.Remove("InitPostEntity", NAME)
    if engine.ActiveGamemode() ~= "zcity" then return end
    timer.Simple(ATTEMPTS[1], function() attempt(1) end)
end)

-- Operator handle. A push to lua/zc_killcam/sv_tape.lua re-runs its wrapWeapons() at file load and
-- takes the slots again mid-session; this re-runs the repair without waiting for a map change.
-- Mid-session it DISCARDS the observer's accumulated session (rounds_observed, captured, ...),
-- so it is deliberately not automatic.
concommand.Add("zcj_ownership_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local runtime = ZCJusticeV3Integration
    local lost = lostLabels()
    print("[" .. NAME .. "] enabled=" .. tostring(runtime and runtime.enabled)
        .. " errors=" .. tostring(runtime and runtime.stats and runtime.stats.errors)
        .. " wrappers=" .. tostring(runtime and runtime.wrappers and #runtime.wrappers)
        .. " lost=" .. (lost and describe(lost) or "?")
        .. " last_error=" .. tostring(runtime and runtime.last_error and runtime.last_error.code)
        .. "/" .. tostring(runtime and runtime.last_error and runtime.last_error.detail))
end)

concommand.Add("zcj_ownership_repair", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local ok, detail = repair("manual")
    print("[" .. NAME .. "] " .. (ok and "REPAIRED" or "not repaired") .. " -- " .. tostring(detail))
end)
