-- Super Crusher: admin-only crusher variant.
-- Normal crusher role + abilities, PLUS 10 Fury-13 doses of strength
-- (berserk +20), with the berserk screen effect suppressed for the wearer.
--
-- Commands (the "zc staff playertools" ULX right, zc_goobos/sv_staff.lua; IsAdmin()
-- only when ULib is not installed; the server console always may). Logged to ULX:
--   give_supercrusher [name]    - grant (self if no name, in-game)
--   remove_supercrusher [name]  - remove
if not SERVER then return end
if not ZCStaff then include("zc_goobos/sv_staff.lua") end

local BERSERK_POWER = 20  -- 10 Fury-13 doses (each dose = +2)

local function Allowed(ply)
    return ZCStaff.Can(ply, "playertools") -- true for the server console
end

local function FindTarget(caller, args)
    local search = args[1]
    if not search then
        return IsValid(caller) and caller or nil
    end
    search = string.lower(search)
    for _, p in player.Iterator() do
        if string.lower(p:Nick()) == search then return p end
    end
    for _, p in player.Iterator() do
        if string.find(string.lower(p:Nick()), search, 1, true) then return p end
    end
    return nil
end

local function Say(caller, msg)
    if IsValid(caller) then caller:ChatPrint(msg) else print(msg) end
end

concommand.Add("give_supercrusher", function(caller, cmd, args)
    if not Allowed(caller) then return end

    local target = FindTarget(caller, args)
    if not IsValid(target) then Say(caller, "[SuperCrusher] Player not found.") return end

    -- normal crusher role/abilities (as the console, without pasting the name into a console line)
    if not ZCStaff.RunOn("give_crusher", target) then Say(caller, "[SuperCrusher] give_crusher did not run; strength only.") end

    -- strength without the light show
    target:SetNWBool("SilentBerserk", true)
    target.SuperCrusher = true

    if target.organism then
        target.organism.berserk = math.max(target.organism.berserk or 0, BERSERK_POWER)
        target.organism.recoilmul = 0.25
    end

    Say(caller, "[SuperCrusher] " .. target:Nick() .. " is now a Super Crusher.")
    ZCStaff.Log(caller, "#A made #T a super crusher", target)
end, nil, "Staff: make a player a Super Crusher - crusher role plus berserk strength without the screen effect, no dismemberment. give_supercrusher [name]; no name = yourself. Needs the 'zc staff playertools' ULX right.")

concommand.Add("remove_supercrusher", function(caller, cmd, args)
    if not Allowed(caller) then return end

    local target = FindTarget(caller, args)
    if not IsValid(target) then Say(caller, "[SuperCrusher] Player not found.") return end

    ZCStaff.RunOn("remove_crusher", target)

    target.SuperCrusher = nil

    if target.organism then
        target.organism.berserk = 0
        -- push the organism state to the client right away
        pcall(function()
            target.fullsend = true
            hg.send_bareinfo(target.organism)
        end)
    end

    -- keep visuals suppressed a few seconds longer so the client never
    -- sees "berserk > 0 and not silent" during sync lag (which would
    -- trigger the whole berserk intro sequence)
    timer.Simple(4, function()
        if IsValid(target) and not target.SuperCrusher then
            target:SetNWBool("SilentBerserk", false)
        end
    end)

    Say(caller, "[SuperCrusher] Removed from " .. target:Nick() .. ".")
    ZCStaff.Log(caller, "#A removed #T's super crusher", target)
end, nil, "Staff: remove Super Crusher (and the crusher role) from a player. remove_supercrusher [name]; no name = yourself. Needs the 'zc staff playertools' ULX right.")

-- Keep the power topped up (berserk depletes as a resource) and make sure
-- it clears if the flag is gone
timer.Create("SuperCrusher_Maintain", 5, 0, function()
    for _, ply in player.Iterator() do
        if ply.SuperCrusher and ply:Alive() and ply.organism then
            ply.organism.berserk = math.max(ply.organism.berserk or 0, BERSERK_POWER)
        end
    end
end)

-- Clean up on death/respawn so the power doesn't leak into next round
hook.Add("PlayerSpawn", "SuperCrusher_ClearOnSpawn", function(ply)
    if OverrideSpawn then return end -- FakeUp restores the same life, not a new spawn.
    if ply.SuperCrusher then
        ply.SuperCrusher = nil
        ply:SetNWBool("SilentBerserk", false)
    end
end)

hook.Add("ShutDown", "SuperCrusher_Shutdown", function()
    timer.Remove("SuperCrusher_Maintain")
end)

print("[SuperCrusher] Loaded - give_supercrusher / remove_supercrusher")

-- =========================================================================
-- LIMB PROTECTION: Super Crushers cannot be dismembered
-- Wraps ZCity's amputation/head-explosion functions with a guard.
-- =========================================================================
local function ResolveOwner(target)
    -- target can be an organism table, a player, or a ragdoll
    if not target then return nil end
    if type(target) == "table" and target.owner ~= nil then target = target.owner end
    if not IsValid(target) then return nil end
    if target:IsPlayer() then return target end
    if target.ply and IsValid(target.ply) then return target.ply end
    for _, p in player.Iterator() do
        if p.FakeRagdoll == target then return p end
    end
    return nil
end

local function InstallLimbGuards()
    if not (hg and hg.organism) then return end

    if hg.organism.AmputateLimb and not hg.organism.SC_AmpWrapped then
        local orig = hg.organism.AmputateLimb
        hg.organism.AmputateLimb = function(org, limb, ...)
            local owner = ResolveOwner(org)
            if IsValid(owner) and owner.SuperCrusher then return end
            return orig(org, limb, ...)
        end
        hg.organism.SC_AmpWrapped = true
    end

    if hg.ExplodeHead and not hg.SC_HeadWrapped then
        local orig = hg.ExplodeHead
        hg.ExplodeHead = function(ent, ...)
            local owner = ResolveOwner(ent)
            if IsValid(owner) and owner.SuperCrusher then return end
            return orig(ent, ...)
        end
        hg.SC_HeadWrapped = true
    end
end

hook.Add("InitPostEntity", "SuperCrusher_LimbGuards", function()
    timer.Simple(5, InstallLimbGuards)
end)
InstallLimbGuards()
