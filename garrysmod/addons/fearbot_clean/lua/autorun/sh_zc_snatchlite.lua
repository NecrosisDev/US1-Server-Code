-- Snatch Lite: the fear creature grabs the target, drags them off to
-- somewhere out of sight... and dumps them there. Nobody disappears.
-- Admin/superadmin only, right-click a player (or their ragdoll).

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

properties.Add("zc_snatchlite", {
    MenuLabel = "Snatch (Catch && Release)",
    Order = 3110,
    MenuIcon = "icon16/arrow_out.png",

    Filter = function(self, ent, ply)
        if not IsValid(ent) then return false end
        if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return false end
        if CurrentRound and not CurrentRound() then return false end
        if ent:IsPlayer() then return ent ~= ply end
        return ent:GetClass() == "prop_ragdoll"
    end,

    Action = function(self, ent) -- clientside
        Derma_Query(
            "They get dragged off and dumped somewhere - not deleted.",
            "Snatch (catch & release)?",
            "Yes",
            function()
                self:MsgStart()
                    net.WriteEntity(ent)
                self:MsgEnd()
            end,
            "No"
        )
    end,

    Receive = function(self, length, ply) -- serverside
        local ent = net.ReadEntity()
        if not self:Filter(ent, ply) then return end

        local victim = ResolvePlayer(ent) or ent
        local bot = ents.Create("bot_yoink")
        if not IsValid(bot) then return end
        bot.Victim = victim
        bot:Spawn()
        print("[SnatchLite] " .. ply:Nick() .. " snatched (catch & release) " .. (victim.Nick and victim:Nick() or tostring(victim)))
    end,
})
