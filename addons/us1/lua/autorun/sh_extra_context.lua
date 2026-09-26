-- Extra Context: admin right-click options in the context menu (C)
-- Currently: Make Torso / Make Crusher / Remove Crusher
-- Works on players and their ragdolls. Admin/superadmin only.
-- Shared file: properties must register on both client and server.

local function ResolvePlayer(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end

    if ent:GetClass() == "prop_ragdoll" then
        local owner = ent.ply
        if IsValid(owner) and owner:IsPlayer() then return owner end
        if SERVER and hg and hg.RagdollOwner then
            owner = hg.RagdollOwner(ent)
            if IsValid(owner) and owner:IsPlayer() then return owner end
        end
        for _, p in player.Iterator() do
            if p:GetRagdollEntity() == ent then return p end
            if p.FakeRagdoll == ent then return p end
        end
    end
    return nil
end

local function BaseFilter(ent, ply)
    if not IsValid(ent) then return false end
    if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return false end
    if ent:IsPlayer() then return ent ~= ply end
    return ent:GetClass() == "prop_ragdoll"
end

-- ========================================================================
-- MAKE TORSO
-- ========================================================================
properties.Add("zc_maketorso", {
    MenuLabel = "Make Torso",
    Order = 3100,
    MenuIcon = "icon16/user_delete.png",

    Filter = function(self, ent, ply)
        return BaseFilter(ent, ply)
    end,

    Action = function(self, ent) -- clientside
        self:MsgStart()
            net.WriteEntity(ent)
        self:MsgEnd()
    end,

    Receive = function(self, length, ply) -- serverside
        local ent = net.ReadEntity()
        if not self:Filter(ent, ply) then return end

        local victim = ResolvePlayer(ent)
        if not IsValid(victim) or not victim.organism then
            ply:ChatPrint("[MakeTorso] Couldn't resolve a player from that.")
            return
        end

        -- the full shared pipeline (amputate + stabilize + fentanyl +
        -- real tourniquets) lives in sv_make_torso.lua
        if MakeTorso_Apply and MakeTorso_Apply(victim, ply:Nick() .. " (context menu)") then
            ply:ChatPrint("[MakeTorso] " .. victim:Nick() .. " is now a torso. Tourniquets on, fentanyl administered.")
        else
            ply:ChatPrint("[MakeTorso] Torso pipeline unavailable - is sv_make_torso loaded?")
        end
    end,
})

-- ========================================================================
-- MAKE CRUSHER
-- ========================================================================
properties.Add("zc_makecrusher", {
    MenuLabel = "Make Crusher",
    Order = 3101,
    MenuIcon = "icon16/user_red.png",

    Filter = function(self, ent, ply)
        return BaseFilter(ent, ply)
    end,

    Action = function(self, ent)
        self:MsgStart()
            net.WriteEntity(ent)
        self:MsgEnd()
    end,

    Receive = function(self, length, ply)
        local ent = net.ReadEntity()
        if not self:Filter(ent, ply) then return end

        local target = ResolvePlayer(ent)
        if not IsValid(target) then
            ply:ChatPrint("[MakeCrusher] Couldn't resolve a player from that.")
            return
        end

        game.ConsoleCommand('give_crusher "' .. target:Nick() .. '"\n')
        ply:ChatPrint("[MakeCrusher] " .. target:Nick() .. " is now a Crusher.")
        print("[MakeCrusher] " .. ply:Nick() .. " gave crusher to " .. target:Nick() .. " (context menu)")
    end,
})

-- ========================================================================
-- REMOVE CRUSHER
-- ========================================================================
properties.Add("zc_removecrusher", {
    MenuLabel = "Remove Crusher",
    Order = 3102,
    MenuIcon = "icon16/user_gray.png",

    Filter = function(self, ent, ply)
        if not BaseFilter(ent, ply) then return false end
        local target = ResolvePlayer(ent)
        -- Only show on players who are currently crushers
        if IsValid(target) and (target.SubRole == "traitor_strangler" or target.SubRole == "traitor_strangler_soe" or target:GetNWBool("zb_is_crusher", false)) then
            return true
        end
        return false
    end,

    Action = function(self, ent)
        self:MsgStart()
            net.WriteEntity(ent)
        self:MsgEnd()
    end,

    Receive = function(self, length, ply)
        local ent = net.ReadEntity()
        local target = ResolvePlayer(ent)
        if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
        if not IsValid(target) then return end

        game.ConsoleCommand('remove_crusher "' .. target:Nick() .. '"\n')
        ply:ChatPrint("[MakeCrusher] Removed crusher from " .. target:Nick() .. ".")
    end,
})

-- ========================================================================
-- MAKE SUPER CRUSHER (admin variant: crusher + 10 furys, no screen effect)
-- ========================================================================
properties.Add("zc_makesupercrusher", {
    MenuLabel = "Make Super Crusher",
    Order = 3103,
    MenuIcon = "icon16/user_add.png",

    Filter = function(self, ent, ply)
        return BaseFilter(ent, ply)
    end,

    Action = function(self, ent)
        self:MsgStart()
            net.WriteEntity(ent)
        self:MsgEnd()
    end,

    Receive = function(self, length, ply)
        local ent = net.ReadEntity()
        if not self:Filter(ent, ply) then return end

        local target = ResolvePlayer(ent)
        if not IsValid(target) then
            ply:ChatPrint("[SuperCrusher] Couldn't resolve a player from that.")
            return
        end

        game.ConsoleCommand('give_supercrusher "' .. target:Nick() .. '"\n')
        ply:ChatPrint("[SuperCrusher] " .. target:Nick() .. " is now a Super Crusher.")
    end,
})

-- ========================================================================
-- REMOVE SUPER CRUSHER
-- ========================================================================
properties.Add("zc_removesupercrusher", {
    MenuLabel = "Remove Super Crusher",
    Order = 3104,
    MenuIcon = "icon16/user_gray.png",

    Filter = function(self, ent, ply)
        if not BaseFilter(ent, ply) then return false end
        local target = ResolvePlayer(ent)
        -- SilentBerserk NWBool is networked, so this works clientside too
        return IsValid(target) and target:GetNWBool("SilentBerserk", false)
    end,

    Action = function(self, ent)
        self:MsgStart()
            net.WriteEntity(ent)
        self:MsgEnd()
    end,

    Receive = function(self, length, ply)
        local ent = net.ReadEntity()
        local target = ResolvePlayer(ent)
        if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return end
        if not IsValid(target) then return end

        game.ConsoleCommand('remove_supercrusher "' .. target:Nick() .. '"\n')
        ply:ChatPrint("[SuperCrusher] Removed from " .. target:Nick() .. ".")
    end,
})
