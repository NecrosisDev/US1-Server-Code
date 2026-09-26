-- Corpse Sleeper v2.1: corpses far from any living player get their physics
-- frozen and organism simulation zeroed - they stop costing tick budget.
-- Corpses near players stay fully awake and interactive; frozen ones wake
-- instantly on ANY interaction (damage, physgun, use, AND the homigrad
-- grab-drag), then hold a short grace so they don't re-freeze mid-drag.
--
-- v2 fix: an org-zeroed (>60s) corpse used to only wake on damage/physgun,
-- never on the grab-drag (homigrad's carry is a shadow control, not a
-- physgun/constraint hold, so IsPlayerHolding stayed false and proximity
-- wake is deliberately disabled for zeroed corpses). That's why you had to
-- PUNCH a body to drag it. Now .isheld / SetPhysicsAttacker / PlayerUse all
-- wake it too.
if not SERVER then return end

local NEAR_DIST      = 150
local STALE_TIME     = 15
local ORG_ZERO_TIME  = 60
local CHECK_INTERVAL = 2
local INTERACT_GRACE = 12   -- seconds a just-handled corpse stays awake

local NEAR_DIST_SQR = NEAR_DIST * NEAR_DIST

local frozenSet = {}   -- rag -> true : corpses WE froze (for the fast grab scan)
-- Entity flags and motion ownership survive a Lua refresh. Rebuild the scan ledger.
for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
    if IsValid(rag) and rag.CorpseFrozen then frozenSet[rag] = true end
end

local function IsCorpse(rag)
    if not IsValid(rag) or rag:GetClass() ~= "prop_ragdoll" then return false end

    local owner = rag.ply
    if IsValid(owner) and owner:IsPlayer() then
        if owner:Alive() and owner.FakeRagdoll == rag then return false end
    end
    for _, p in player.Iterator() do
        if p:Alive() and p.FakeRagdoll == rag then return false end
    end

    if rag.StrangleLocked then return false end          -- fiberwire
    if rag.spasm or rag.fencing then return false end    -- death seizures playing out
    if IsValid(rag:GetParent()) then return false end
    if rag:IsPlayerHolding() then return false end

    return true
end

-- is a player interacting with this corpse right now (incl. homigrad grab-drag)?
local function BeingHandled(rag)
    if rag.isheld then return true end
    if rag:IsPlayerHolding() then return true end
    if (rag.CorpseInteractGrace or 0) > CurTime() then return true end
    local att = rag.GetPhysicsAttacker and rag:GetPhysicsAttacker(0)
    if IsValid(att) then return true end
    return false
end

local function FreezeCorpse(rag)
    if rag.CorpseFrozen then frozenSet[rag] = true return end
    local motion = {}
    rag.CorpseSleeperMotion = motion
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) and phys:IsMotionEnabled() then
            motion[i] = phys
            phys:EnableMotion(false)
        end
    end
    rag.CorpseFrozen = true
    rag.CorpseFrozenAt = rag.CorpseFrozenAt or CurTime()
    frozenSet[rag] = true
end

local function ZeroOrganism(rag)
    local org = rag.organism
    if org and not rag.CorpseOrgZeroed then
        org.bleed = 0
        if org.wounds then table.Empty(org.wounds) end
        rag.CorpseOrgZeroed = true
    end
end

local function WakeCorpse(rag)
    if not IsValid(rag) then frozenSet[rag] = nil return end
    if not rag.CorpseFrozen then
        rag.CorpseSleeperMotion = nil
        frozenSet[rag] = nil
        return
    end
    local motion = rag.CorpseSleeperMotion
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        -- Legacy frozen corpses have no mask: retain their old wake behavior.
        -- New freezes restore only the exact bodies this sleeper disabled.
        if IsValid(phys) and (not motion or motion[i] == phys) then
            phys:EnableMotion(true)
            phys:Wake()
        end
    end
    rag.CorpseSleeperMotion = nil
    rag.CorpseFrozen = nil
    rag.CorpseStale = CurTime()
    frozenSet[rag] = nil
end

-- wake because a PLAYER touched it: also stamp a grace so it won't re-freeze
-- while it's still being handled (this is the grab-drag fix). Works even on
-- org-zeroed scenery corpses.
local function InteractWake(rag)
    if not IsValid(rag) then frozenSet[rag] = nil return end
    rag.CorpseInteractGrace = CurTime() + INTERACT_GRACE
    if rag.CorpseFrozen then WakeCorpse(rag) end
end

timer.Create("CorpseSleeper_Check", CHECK_INTERVAL, 0, function()
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if not IsCorpse(rag) then
            if rag.CorpseFrozen then WakeCorpse(rag) end
            rag.CorpseStale = nil
            continue
        end

        -- a player handling it (incl. grab-drag) keeps it awake regardless
        if BeingHandled(rag) then
            if rag.CorpseFrozen then WakeCorpse(rag) end
            rag.CorpseStale = CurTime()
            continue
        end

        local pos = rag:GetPos()
        local playerNear = false
        for _, p in player.Iterator() do
            if p:Alive() and p:GetPos():DistToSqr(pos) < NEAR_DIST_SQR then
                playerNear = true
                break
            end
        end

        if playerNear and not rag.CorpseOrgZeroed then
            if rag.CorpseFrozen then WakeCorpse(rag) end
            rag.CorpseStale = CurTime()
        else
            rag.CorpseStale = rag.CorpseStale or CurTime()
            rag.CorpseFirstSeen = rag.CorpseFirstSeen or CurTime()
            if not rag.CorpseFrozen and CurTime() - rag.CorpseStale >= STALE_TIME
                and (rag.CorpseInteractGrace or 0) < CurTime() then
                FreezeCorpse(rag)
            end
            if CurTime() - rag.CorpseFirstSeen >= ORG_ZERO_TIME then
                ZeroOrganism(rag)
            end
        end
    end
end)

-- fast grab-drag catch: scan ONLY our frozen set (small) for a handling player.
-- This is what makes dragging a frozen/zeroed body wake it near-instantly
-- instead of only on a punch.
timer.Create("CorpseSleeper_GrabScan", 0.25, 0, function()
    local wake
    for rag in pairs(frozenSet) do
        if not IsValid(rag) then frozenSet[rag] = nil
        elseif rag.isheld or rag:IsPlayerHolding()
            or (rag.GetPhysicsAttacker and IsValid(rag:GetPhysicsAttacker(0))) then
            wake = wake or {} wake[#wake + 1] = rag
        end
    end
    if wake then for _, rag in ipairs(wake) do InteractWake(rag) end end
end)

-- =====================================================================
-- Round-end purge (unchanged): remove stale corpses in small batches
-- during the round-end screen so CleanUpMap has little ragdoll-shaped
-- to trip on (the VPhysics crash class).
-- =====================================================================
local PURGE_BATCH = 12

local function IsPurgeable(rag)
    if not IsValid(rag) then return false end
    if rag:GetClass() ~= "prop_ragdoll" then return false end
    if not rag.CorpseFirstSeen and not rag.CorpseOrgZeroed then
        local owner = rag.ply
        if IsValid(owner) and owner:Alive() then return false end
        if rag.StrangleLocked or rag:IsPlayerHolding() then return false end
        if not IsValid(owner) then return true end
        return not owner:Alive()
    end
    local owner = rag.ply
    if IsValid(owner) and owner:Alive() then return false end
    if rag:IsPlayerHolding() then return false end
    return true
end

hook.Add("ZB_EndRound", "CorpseSleeper_RoundPurge", function()
    local victims = {}
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        if IsPurgeable(rag) then victims[#victims + 1] = rag end
    end
    if #victims == 0 then return end

    local idx = 1
    timer.Create("CorpseSleeper_PurgeStep", 0.1, math.ceil(#victims / PURGE_BATCH), function()
        for i = 1, PURGE_BATCH do
            local rag = victims[idx]
            idx = idx + 1
            if not rag then return end
            if IsValid(rag) then SafeRemoveEntity(rag) end
        end
    end)
end)

-- instant wake on the direct-interaction hooks (now with grace stamp)
hook.Add("EntityTakeDamage", "CorpseSleeper_WakeOnDamage", function(ent)
    if ent.CorpseFrozen then InteractWake(ent) end
end)
hook.Add("PhysgunPickup", "CorpseSleeper_WakeOnPhysgun", function(_, ent)
    if ent.CorpseFrozen then InteractWake(ent) end
end)
hook.Add("PlayerUse", "CorpseSleeper_WakeOnUse", function(_, ent)
    if IsValid(ent) and ent.CorpseFrozen then InteractWake(ent) end
end)

hook.Add("ShutDown", "CorpseSleeper_Shutdown2", function()
    timer.Remove("CorpseSleeper_PurgeStep")
end)
hook.Add("ShutDown", "CorpseSleeper_Shutdown", function()
    timer.Remove("CorpseSleeper_Check")
    timer.Remove("CorpseSleeper_GrabScan")
end)

print("[CorpseSleeper] v2.1 loaded - distant corpses sleep after " .. STALE_TIME .. "s; wake on any interaction incl. grab-drag")
