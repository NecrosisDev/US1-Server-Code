-- Hurt Grab: lets you RMB-grab (weapon_hands_sh) players who are still
-- standing but critically injured / in serious pain - they get ragdolled
-- into your grip.
--
-- Anti-grief by design:
--  - Only works on genuinely messed-up targets (thresholds below)
--  - The victim is NOT locked: pressing their fake bind stands them up
--    instantly, breaking the grab
--  - After being hurt-grabbed, a target can't be hurt-grabbed again for
--    a few seconds (no chain knockdowns)
if not SERVER then return end

local GRAB_RANGE = 75

-- Target qualifies if ANY of these are true:
local PAIN_MIN   = 40     -- serious pain
local HURT_MIN   = 55     -- badly wounded
local BLOOD_MAX  = 3200   -- heavy blood loss (full is ~5000)

local REGRAB_COOLDOWN = 6 -- seconds before the same target can be hurt-grabbed again

local function QualifiesAsHurt(org)
    if not org then return false end
    if (org.pain or 0) >= PAIN_MIN then return true end
    if (org.hurt or 0) >= HURT_MIN then return true end
    if (org.blood or 5000) <= BLOOD_MAX then return true end
    return false
end

hook.Add("KeyPress", "HurtGrab_Attempt", function(ply, key)
    if key ~= IN_ATTACK2 then return end
    if not IsValid(ply) or not ply:Alive() then return end

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "weapon_hands_sh" then return end

    -- already carrying something - vanilla behavior handles it
    if IsValid(wep.CarryEnt) then return end

    local trace = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * GRAB_RANGE,
        filter = { ply, ply.FakeRagdoll },
        mask = MASK_SHOT,
    })

    local victim = trace.Entity
    if not IsValid(victim) or not victim:IsPlayer() then return end
    if victim == ply or not victim:Alive() then return end

    -- must be STANDING (already-ragdolled players are grabbable natively)
    if IsValid(victim.FakeRagdoll) then return end

    -- must be genuinely hurt
    if not QualifiesAsHurt(victim.organism) then return end

    if ZCityInteractions and not ZCityInteractions.HurtGrabAllowed(ply,victim) then return end

    -- re-grab protection
    if (victim.HurtGrabCD or 0) > CurTime() then return end
    victim.HurtGrabCD = CurTime() + REGRAB_COOLDOWN

    -- down they go - deliberately NO locks so their fake bind stands
    -- them up instantly and breaks the grab
    if hg and hg.Fake then
        hg.Fake(victim)
    else
        return
    end

    pcall(function()
        victim:Notify("A hand seizes you - too weak to stay on your feet, you crumple into their grip.", true, "hurtgrab", 3)
    end)

    -- Attach the carry once the ragdoll exists
    local attempts = 0
    local function TryCarry()
        if not IsValid(ply) or not IsValid(victim) then return end
        if not ply:Alive() or not victim:Alive() then return end

        local wep2 = ply:GetActiveWeapon()
        if not IsValid(wep2) or wep2:GetClass() ~= "weapon_hands_sh" then return end

        if ZCityInteractions and not ZCityInteractions.HurtGrabAllowed(ply,victim) then return end

        local rag = victim.FakeRagdoll
        if IsValid(rag) then
            local bone = rag:LookupBone("ValveBiped.Bip01_Spine2") or 0
            local physIdx = rag:TranslateBoneToPhysBone(bone)
            local phys = rag:GetPhysicsObjectNum(physIdx >= 0 and physIdx or 0)

            if IsValid(phys) and hg.SetCarryEnt2 then
                hg.SetCarryEnt2(
                    ply, rag, bone, phys:GetMass(),
                    Vector(0, 0, 0),
                    ply:GetAimVector() * 45 + ply:GetShootPos(),
                    ply:EyeAngles()
                )
            end
            return
        end

        attempts = attempts + 1
        if attempts < 20 then
            timer.Simple(0, TryCarry)
        end
    end
    timer.Simple(0, TryCarry)
end)

print("[HurtGrab] Loaded - RMB grabs critically hurt standing players")
