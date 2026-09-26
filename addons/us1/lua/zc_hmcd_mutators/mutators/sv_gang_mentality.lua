-- Gang presentation and zero combat karma loss; native roles, classes and kits stay authoritative.
local M = ZC_HMCD_MUTATORS
local ID, NET = "gang_mentality", "zc_gang_mentality"
local gangs = {
    {name = "Bloodz", color = Color(165, 0, 0):ToVector(), pluv = "pluvred", models = {
        "models/gang_ballas_chem/gang_ballas_chem.mdl",
        "models/gang_ballas/gang_ballas_2.mdl", "models/gang_ballas/gang_ballas_1.mdl"
    }},
    {name = "Groove", color = Color(0, 165, 0):ToVector(), pluv = "pluvgreen", models = {
        "models/gang_groove/gang_1.mdl", "models/gang_groove/gang_2.mdl",
        "models/gang_chem/gang_groove_chem.mdl"
    }}
}
local prefixes = {"Big ", "Lil ", "OG "}
util.AddNetworkString(NET)
local function Pick(t) return t[math.floor(M:Random() * #t) + 1] end
local function Models()
    local out = {{}, {}}
    for index, gang in ipairs(gangs) do
        for _, model in ipairs(gang.models) do
            if util.IsValidModel(model) then out[index][#out[index] + 1] = model end
        end
    end
    return out
end
local function Eligible(p)
    return IsValid(p) and p:Alive() and p:Team() ~= TEAM_SPECTATOR and not p.isPolice
        and (not p.PlayerClassName or p.PlayerClassName == "none" or p.PlayerClassName == "default")
        and not IsValid(p.FakeRagdoll) and not p:InVehicle()
end
local function Requirements()
    local models = Models()
    if #models[1] == 0 or #models[2] == 0 then return false, "Requires mounted Bloodz and Groove models" end
    for _, p in ipairs(M:Players()) do
        if not Eligible(p) then return false, "Starting players must be living civilians outside vehicles/ragdolls" end
    end
    return true
end
local function Sync(ctx, p, record)
    if not IsValid(p) then return end
    net.Start(NET)
    net.WriteUInt(M.generation % 4294967296, 32)
    net.WriteBool(record ~= nil and record.active == true and ctx:Valid())
    net.WriteUInt(record and record.gang or 0, 2)
    net.WriteString(ctx and ctx.variant or "")
    net.WriteFloat(ctx and ctx.stamp or 0) -- Same precision as native RoundInfo.
    net.Send(p) -- Only this player's gang; never send an allegiance or role list.
end
local function Snapshot(p)
    local s = {ply = p, active = true, model = p:GetModel(), skin = p:GetSkin(),
        color = p:GetPlayerColor(), nwcolor = p:GetNWVector("PlayerColor"),
        name = p:GetNWString("PlayerName", p:Nick()), class = p.PlayerClassName,
        team = p:Team(), groups = {}, materials = {},
        accessories = p:GetNetVar("Accessories"), pluv = p:GetNetVar("CurPluv")}
    for _, group in ipairs(p:GetBodyGroups()) do s.groups[group.id] = p:GetBodygroup(group.id) end
    for i = 0, #p:GetMaterials() - 1 do s.materials[i] = p:GetSubMaterial(i) end
    return s
end
local function Restore(s)
    local p = s.ply
    if s.finished then return end
    s.finished = true
    -- Never overwrite a corpse, reinforcement life, disguise or another system's class/model.
    if not s.started or not IsValid(p) or not p:Alive() or p:GetModel() ~= s.appliedModel
        or p.PlayerClassName ~= s.class or p:Team() ~= s.team then return end
    p:SetModel(s.model)
    p:SetSkin(s.skin)
    p:SetSubMaterial()
    for i, mat in pairs(s.materials) do p:SetSubMaterial(i, mat) end
    for i, value in pairs(s.groups) do p:SetBodygroup(i, value) end
    if p:GetPlayerColor() == s.appliedColor then p:SetPlayerColor(s.color) end
    if p:GetNWVector("PlayerColor") == s.appliedColor then p:SetNWVector("PlayerColor", s.nwcolor) end
    if p:GetNWString("PlayerName") == s.appliedName then p:SetNWString("PlayerName", s.name) end
    if p:GetNetVar("Accessories") == "" then p:SetNetVar("Accessories", s.accessories) end
    if p:GetNetVar("CurPluv") == s.appliedPluv then p:SetNetVar("CurPluv", s.pluv) end
end
local function Retire(ctx, p, restore)
    local s = ctx.data.members[p]
    if not s then return end
    s.active = false
    if restore then Restore(s) end
    Sync(ctx, p, s)
end
local requests = setmetatable({}, {__mode = "k"})
net.Receive(NET, function(len, p)
    if len ~= 0 or not IsValid(p) or (requests[p] or 0) > CurTime() then return end
    requests[p] = CurTime() + 1
    local ctx = M.current
    if ctx and ctx.definition.ID == ID then Sync(ctx, p, ctx.data.members and ctx.data.members[p])
    else Sync(nil, p) end
end)
M:Register({
    MidRound = true,
    CombatKarmaMultiplier = 0,
    ID = ID, Title = "Gang Mentality",
    Description = "Bloodz and Groove colors divide the crowd. Normal Homicide gear, allegiance and objectives remain. Combat causes no karma loss.",
    Types = {standard = true, gunfreezone = true, soe = true}, MinPlayers = 2, Weight = 1,
    CanStart = Requirements,
    Start = function(ctx)
        local models, order = Models(), {}
        if #models[1] == 0 or #models[2] == 0 then error("Gang models became unavailable") end
        ctx.data.members = {}
        for _, p in ipairs(ctx.participants) do
            if not Eligible(p) then error("Gang participant became unavailable") end
            order[#order + 1] = p
            ctx.data.members[p] = Snapshot(p)
        end
        -- Independent of all role flags. Do not guarantee one traitor per gang.
        for i = #order, 2, -1 do
            local j = math.floor(M:Random() * i) + 1
            order[i], order[j] = order[j], order[i]
        end
        local first = math.floor(M:Random() * 2) + 1
        -- The framework protects each callback separately, so one failed restore
        -- cannot leave everyone else wearing their gang appearance.
        for p, s in pairs(ctx.data.members) do
            ctx:Cleanup(function()
                s.active = false
                Sync(ctx, p, s)
                Restore(s)
            end)
        end
        local function lifecycle(event, fn)
            local key = ctx.prefix .. "gang_" .. event
            hook.Add(event, key, fn)
            ctx:Cleanup(function() hook.Remove(event, key) end)
        end
        lifecycle("PlayerDeath", function(p) Retire(ctx, p, false) end)
        lifecycle("PlayerSilentDeath", function(p) Retire(ctx, p, false) end)
        lifecycle("PlayerSpawn", function(p) if not OverrideSpawn then Retire(ctx, p, true) end end)
        lifecycle("PlayerDisconnected", function(p) local s=ctx.data.members[p]; if s then s.active=false; s.finished=true end end)
        for i, p in ipairs(order) do
            if not ctx:Valid() or not Eligible(p) then error("Gang participant changed during setup") end
            local s = ctx.data.members[p]
            s.gang = (i + first) % 2 + 1
            local gang = gangs[s.gang]
            s.appliedModel, s.appliedColor = Pick(models[s.gang]), gang.color
            s.appliedName, s.appliedPluv = Pick(prefixes) .. s.name, gang.pluv
            s.started = true
            p:SetModel(s.appliedModel)
            p:SetSkin(0)
            p:SetSubMaterial()
            for _, group in ipairs(p:GetBodyGroups()) do
                local choices = math.max(tonumber(group.num) or 1, 1)
                p:SetBodygroup(group.id, math.floor(M:Random() * choices))
            end
            p:SetPlayerColor(s.appliedColor)
            p:SetNWVector("PlayerColor", s.appliedColor)
            p:SetNWString("PlayerName", s.appliedName)
            p:SetNetVar("Accessories", "")
            p:SetNetVar("CurPluv", s.appliedPluv)
        end
        for p, s in pairs(ctx.data.members) do Sync(ctx, p, s) end
        ctx:Timer("gang_lifecycle", 1, 0, function(c)
            for p, s in pairs(c.data.members) do
                if s.active and (not IsValid(p) or not p:Alive() or p.isPolice
                    or p.PlayerClassName ~= s.class or p:Team() ~= s.team) then Retire(c, p, false) end
            end
        end)
    end
})
