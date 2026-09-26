-- make_torso: admin command that removes all four limbs from whoever the
-- admin is currently carrying (RMB grab with hands), clots their bleeding,
-- removes their pain, and keeps them conscious - a living torso.
if not SERVER then return end

local LIMBS = { "larm", "rarm", "lleg", "rleg" }

local function FindCarriedPlayer(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return nil end

    local ent = wep.CarryEnt
    if not IsValid(ent) then return nil end

    -- Carrying a ragdoll - resolve the owner
    if ent:GetClass() == "prop_ragdoll" then
        local owner = ent.ply
        if not IsValid(owner) and hg and hg.RagdollOwner then
            owner = hg.RagdollOwner(ent)
        end
        if not IsValid(owner) then
            for _, p in player.Iterator() do
                if p:GetRagdollEntity() == ent then owner = p break end
                if p.FakeRagdoll == ent then owner = p break end
            end
        end
        if IsValid(owner) and owner:IsPlayer() then return owner end
    end

    if ent:IsPlayer() then return ent end
    return nil
end

local function Stabilize(victim)
    if not IsValid(victim) or not victim.organism then return end
    local org = victim.organism

    org.bleed = 0
    if org.wounds then table.Empty(org.wounds) end
    org.pain = 0
    org.shock = 0
    org.consciousness = 1
    org.otrub = false
    org.analgesiaAdd = math.max(org.analgesiaAdd or 0, 1)
end

-- the complete torso pipeline - shared by the concommand and the
-- context-menu property (single source of truth)
function MakeTorso_Apply(victim, byName)
    if not IsValid(victim) or not victim.organism then return false end
    local org = victim.organism

    -- Blow off all four limbs (head stays)
    for _, limb in ipairs(LIMBS) do
        if not org[limb .. "amputated"] and hg and hg.organism and hg.organism.AmputateLimb then
            hg.organism.AmputateLimb(org, limb)
        end
    end

    -- Stabilize now and repeatedly for a few seconds to catch delayed
    -- bleed/pain from the amputations
    Stabilize(victim)
    local reps = 0
    timer.Create("MakeTorso_Stabilize_" .. victim:EntIndex(), 0.25, 16, function()
        reps = reps + 1
        Stabilize(victim)
    end)

    -- a full syringe of fentanyl, administered exactly the way the
    -- real item does it (one syringe = +1.0 analgesia, capped at 4)
    org.analgesiaAdd = math.min((org.analgesiaAdd or 0) + 1, 4)

    -- REAL tourniquets on every stump: the same application logic as
    -- weapon_bandage_sh's Tourniquet() - visible bands (Tourniquets
    -- netvar triplets), arterial wound consumed, bleed field zeroed,
    -- TourniquetGuys registration. Runs shortly after amputation so
    -- the stump wounds have registered.
    timer.Simple(0.6, function()
        if not IsValid(victim) or not victim:Alive() or not victim.organism then return end
        local o = victim.organism
        local body = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(victim) or victim

        victim.tourniquets = victim.tourniquets or {}
        local applied = 0

        while o.arterialwounds and #o.arterialwounds > 0 and applied < 8 do
            local wound = o.arterialwounds[1]
            if not wound then break end

            victim.tourniquets[#victim.tourniquets + 1] = { wound[2], wound[3], wound[4] }
            if wound[7] then o[wound[7]] = 0 end
            if wound[7] == "arteria" and o.o2 then o.o2.regen = 0 end
            table.remove(o.arterialwounds, 1)

            -- zero + drop regular wounds on the same bone
            if o.wounds and IsValid(body) then
                local wBoneIdx = wound[4] and body:LookupBone(wound[4])
                local wBone = wBoneIdx and body:GetBoneName(wBoneIdx)
                for i = #o.wounds, 1, -1 do
                    local tbl = o.wounds[i]
                    if tbl and tbl[4] and body:LookupBone(tbl[4]) then
                        if body:GetBoneName(body:LookupBone(tbl[4])) == wBone then
                            tbl[1] = 0
                            table.remove(o.wounds, i)
                        end
                    end
                end
            end

            applied = applied + 1
        end

        if applied > 0 then
            o.owner:SetNetVar("arterialwounds", o.arterialwounds)
            o.owner:SetNetVar("wounds", o.wounds)
            victim:SetNetVar("Tourniquets", victim.tourniquets)
            if IsValid(victim.FakeRagdoll) then
                victim.FakeRagdoll:SetNetVar("Tourniquets", victim.tourniquets)
            end
            hg.TourniquetGuys = hg.TourniquetGuys or {}
            if not table.HasValue(hg.TourniquetGuys, victim) then
                table.insert(hg.TourniquetGuys, victim)
            end
            SetNetVar("TourniquetGuys", hg.TourniquetGuys)
            victim:EmitSound("snd_jack_hmcd_bandage.wav", 65, 100)
            print("[MakeTorso] Applied " .. applied .. " real tourniquets to " .. victim:Nick())
        else
            -- no arterial wounds registered (amputation modeled its
            -- bleeding differently) - fall back to the virtual pin so
            -- the torso still never bleeds out
            print("[MakeTorso] No arterial wounds found - virtual staunching engaged")
            timer.Create("MakeTorso_Tourniquets_" .. victim:EntIndex(), 1, 0, function()
                if not IsValid(victim) or not victim:Alive() or not victim.organism then
                    timer.Remove("MakeTorso_Tourniquets_" .. victim:EntIndex())
                    return
                end
                local o2 = victim.organism
                o2.bleed = 0
                if o2.wounds then table.Empty(o2.wounds) end
            end)
        end
    end)

    print("[MakeTorso] " .. (byName or "?") .. " torso'd " .. victim:Nick())
    return true
end

concommand.Add("make_torso", function(ply, cmd, args)
    if not IsValid(ply) then print("[MakeTorso] Run in-game while carrying someone.") return end
    if not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end

    local victim = FindCarriedPlayer(ply)
    if not IsValid(victim) then
        ply:ChatPrint("[MakeTorso] You aren't carrying a player's body (grab them with RMB first).")
        return
    end

    if MakeTorso_Apply(victim, ply:Nick()) then
        ply:ChatPrint("[MakeTorso] " .. victim:Nick() .. " is now a torso. Tourniquets on, fentanyl administered.")
    else
        ply:ChatPrint("[MakeTorso] Target has no organism.")
    end
end)

print("[MakeTorso] Loaded - make_torso command available")
