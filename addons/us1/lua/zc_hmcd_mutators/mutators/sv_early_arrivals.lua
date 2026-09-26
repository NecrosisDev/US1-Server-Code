-- Starting innocents with native reinforcement classes/kits; not a reinforcement wave.
local M = ZC_HMCD_MUTATORS
local ID = "early_arrivals"
local roles = {"early_arrival_1", "early_arrival_2"}
local function Eligible(p)
    return IsValid(p) and p:Alive() and p:Team() ~= TEAM_SPECTATOR and not p.isTraitor and not p.isPolice
        and (not p.PlayerClassName or p.PlayerClassName == "none")
        and p.organism and not p.organism.otrub and not p.organism.incapacitated
        and not p:InVehicle() and not IsValid(p.FakeRagdoll) and not p:GetNetVar("handcuffed", false)
end
local function Pairs(participants)
    local a = M:SpecialRoleCandidates(roles[1], participants)
    local b = M:SpecialRoleCandidates(roles[2], participants)
    local out = {}
    for _, first in ipairs(a) do
        for _, second in ipairs(b) do
            if first ~= second then out[#out + 1] = {first, second} end
        end
    end
    return out
end
local function Recipe(mode)
    if mode.Type == "soe" then
        return "nationalguard", function(p, index) mode:EquipNationalGuard(p, index) end,
            type(mode.EquipNationalGuard) == "function"
    end
    local variant = mode.Types and mode.Types[mode.Type]
    return "police", variant and variant.PoliceEquipment, variant and type(variant.PoliceEquipment) == "function"
end
local function Requirements(mode)
    local class, _, exists = Recipe(mode)
    if not exists then return false, "Native reinforcement equipment function is unavailable" end
    if not player.classList or not player.classList[class] or type(player.classList[class].On) ~= "function" then
        return false, "Native " .. class .. " player class is unavailable"
    end
    if not hg or not hg.CreateInv or not hg.weaponInv or not hg.weaponInv.Sync then return false, "Inventory API is unavailable" end
    if #Pairs() == 0 then return false, "Needs two different eligible innocents; check both staff picks" end
    return true
end
local fields = {"isPolice", "isGunner", "Profession", "SubRole", "MainTraitor"}
local netvars = {"CurPluv", "Accessories", "flashlight"}
local function Snapshot(p)
    local mode = CurrentRound()
    local role = mode.Roles and mode.Roles[mode.Type] and mode.Roles[mode.Type][p.isGunner and "gunner" or "innocent"]
    local s = {ply = p, class = p.PlayerClassName, role = role, fields = {}, vars = {}, weapons = {},
        ammo = table.Copy(p:GetAmmo()), inventory = table.Copy(p:GetNetVar("Inventory") or {}),
        slots = {}, ammoInv = table.Copy(p.ammoInv or {}), ammoAlias = p.ammoInv == p.weaponInv, armors = table.Copy(p.armors or {}),
        armorHealth = table.Copy(p.armors_health or {}), model = p:GetModel(), skin = p:GetSkin(),
        color = p:GetPlayerColor(), name = p:GetNWString("PlayerName"), groups = {}, materials = {},
        appearance = table.Copy(p.CurAppearance or {}), cached = p.CachedAppearance and table.Copy(p.CachedAppearance),
        recoil = p.organism.recoilmul, active = IsValid(p:GetActiveWeapon()) and p:GetActiveWeapon():GetClass()}
    for _, key in ipairs(fields) do s.fields[key] = p[key] end
    for _, key in ipairs(netvars) do s.vars[key] = p:GetNetVar(key) end
    for category, slot in pairs(p.weaponInv or {}) do s.slots[category] = {limit = slot.limit} end
    for _, group in ipairs(p:GetBodyGroups()) do s.groups[group.id] = p:GetBodygroup(group.id) end
    for i = 0, #p:GetMaterials() - 1 do s.materials[i] = p:GetSubMaterial(i) end
    for _, w in ipairs(p:GetWeapons()) do
        s.weapons[#s.weapons + 1] = {class = w:GetClass(), clip1 = w:Clip1(), clip2 = w:Clip2(),
            attachments = w.attachments and table.Copy(w.attachments)}
    end
    return s
end
local function ClearKit(p, slots)
    local ammoAlias = p.ammoInv == p.weaponInv
    p:StripWeapons()
    p:StripAmmo()
    p.weaponInv = table.Copy(slots)
    if ammoAlias then p.ammoInv = p.weaponInv end
    p.armors, p.armors_health = {}, {}
    hg.CreateInv(p)
    p:SyncArmor()
    hg.weaponInv.Sync(p)
end
local function Restore(s)
    local p = s.ply
    if s.retired or not IsValid(p) or not p:Alive() then return end
    s.retired = true
    -- Do not overwrite a new life, allegiance, or a class assigned by another system.
    if p.isTraitor or (s.applied and p.PlayerClassName ~= s.applied) then return end
    ClearKit(p, s.slots)
    p:SetPlayerClass(s.class)
    p.CurAppearance, p.CachedAppearance = table.Copy(s.appearance), s.cached and table.Copy(s.cached)
    p:SetModel(s.model); p:SetSkin(s.skin); p:SetPlayerColor(s.color)
    p:SetSubMaterial()
    for i, material in pairs(s.materials) do p:SetSubMaterial(i, material) end
    for i, value in pairs(s.groups) do p:SetBodygroup(i, value) end
    p:SetNWString("PlayerName", s.name)
    for _, key in ipairs(fields) do p[key] = s.fields[key] end
    for _, key in ipairs(netvars) do p:SetNetVar(key, s.vars[key]) end
    p.organism.recoilmul = s.recoil
    p.armors, p.armors_health = table.Copy(s.armors), table.Copy(s.armorHealth)
    p.ammoInv = s.ammoAlias and p.weaponInv or table.Copy(s.ammoInv)
    for _, data in ipairs(s.weapons) do
        local w = p:Give(data.class, true)
        if IsValid(w) then
            w.DontEquipInstantly = true
            if data.attachments and hg.AddAttachmentForce then
                for _, attachment in pairs(data.attachments) do
                    if type(attachment) == "table" and type(attachment[1]) == "string" and attachment[1] ~= "empty" then
                        hg.AddAttachmentForce(p, w, attachment[1])
                    end
                end
            end
            w:SetClip1(data.clip1); w:SetClip2(data.clip2)
        end
    end
    p:StripAmmo()
    for ammo, count in pairs(s.ammo) do p:SetAmmo(count, ammo) end
    -- Restore virtual inventory items, but rebuild weapon references after re-granting.
    local inv = table.Copy(s.inventory)
    inv.Weapons = inv.Weapons or {}
    for key, value in pairs(inv.Weapons) do if type(value) ~= "boolean" then inv.Weapons[key] = nil end end
    for _, w in ipairs(p:GetWeapons()) do
        if w:GetClass() ~= "weapon_hands_sh" then inv.Weapons[w:GetClass()] = w end
    end
    inv.Ammo = p:GetAmmo()
    p.inventory = inv; p:SetNetVar("Inventory", inv)
    p:SyncArmor(); hg.weaponInv.Sync(p)
    local active = s.active and p:GetWeapon(s.active)
    if IsValid(active) then p:SetActiveWeapon(active) end
    zb.GiveRole(p, s.role and s.role.name or "Innocent", s.role and s.role.color or Color(70, 180, 70))
end
local function Retire(ctx, p, respawn)
    for _, s in ipairs(ctx.data.arrivals or {}) do
        if s.ply == p and not s.retired then
            s.retired = true
            -- Native death handles corpses. A later respawn must not retain this class.
            if respawn and p.PlayerClassName == s.applied then p:SetPlayerClass(s.class) end
        end
    end
end
M:Register({
    ID = ID, Title = "Early Arrivals",
    Description = "Two starting innocents become police officers, or National Guard in State of Emergency, with their normal reinforcement kits.",
    Types = {standard = true, gunfreezone = true, soe = true}, MinPlayers = 3, Weight = 1,
    CanStart = Requirements,
    Start = function(ctx)
        local pairs = Pairs(ctx.participants)
        if #pairs == 0 then error("Two different eligible innocents are required") end
        local chosen = pairs[math.floor(M:Random() * #pairs) + 1]
        local class, equip, exists = Recipe(ctx.mode)
        if not exists then error("Reinforcement recipe disappeared") end
        ctx.data.arrivals = {}
        -- Select and snapshot BOTH recipients before changing either player.
        for index, p in ipairs(chosen) do
            M:SelectSpecialRole(ctx, roles[index], {p})
            local s = Snapshot(p)
            ctx.data.arrivals[index] = s
        end
        -- Observe every spawn, including one that invalidates the context before core dispatch.
        local spawnHook = ctx.prefix .. "early_arrivals_spawn"
        hook.Add("PlayerSpawn", spawnHook, function(p) Retire(ctx, p, true) end)
        ctx:Cleanup(function() hook.Remove("PlayerSpawn", spawnHook) end)
        for _, s in ipairs(ctx.data.arrivals) do
            ctx:Cleanup(function() if s.started then Restore(s) end end)
        end
        for index, s in ipairs(ctx.data.arrivals) do
            local p = s.ply
            if not Eligible(p) or not ctx:Valid() then error("Recipient became unavailable") end
            s.started = true
            ClearKit(p, s.slots)
            p.isGunner, p.Profession, p.SubRole, p.MainTraitor = false, nil, nil, false
            -- isPolice is the late-wave/victory-accounting flag, not the player class.
            -- Starting innocents continue to count toward survival and do not advance SWAT deaths.
            p.isPolice = false
            -- Scope validation to these synchronous native grants; never replace global Give.
            local give, rawGive = p.Give, p:GetTable().Give
            p.Give = function(target, weapon, ...)
                local w = give(target, weapon, ...)
                if not IsValid(w) or w:GetOwner() ~= target then error("Native kit grant failed: " .. tostring(weapon)) end
                return w
            end
            local ok, err = xpcall(function() equip(p, index) end, debug.traceback)
            p.Give = rawGive
            if not ok then error(err) end
            s.applied = class
            if not IsValid(p) or not p:Alive() or p.PlayerClassName ~= class or not util.IsValidModel(p:GetModel()) then
                s.applied = nil
                error("Native reinforcement class/model setup failed")
            end
            if p.isTraitor then error("Native equipment unexpectedly changed allegiance") end
            local armorCount = table.Count(p.armors or {})
            if armorCount < (class == "nationalguard" and 2 or 1) then error("Native reinforcement armor could not be equipped") end
            p.isPolice = false
            local hands = p:GetWeapon("weapon_hands_sh")
            if not IsValid(hands) then error("Native reinforcement kit did not provide hands") end
            for _, w in ipairs(p:GetWeapons()) do w.DontEquipInstantly = true end
            p:SetActiveWeapon(hands)
        end
        M:Log("Early Arrivals equipped two " .. class .. " starting innocents; normal reinforcement schedule unchanged")
    end,
    PlayerDeath = function(ctx, p) Retire(ctx, p, false) end,
    PlayerDisconnected = function(ctx, p) Retire(ctx, p, false) end,
    PlayerSpawn = function(ctx, p) Retire(ctx, p, true) end
})
for i, id in ipairs(roles) do
    M:RegisterSpecialRole({ID = id, Mutator = ID, Title = "Early arrival " .. i, Eligible = Eligible})
end
