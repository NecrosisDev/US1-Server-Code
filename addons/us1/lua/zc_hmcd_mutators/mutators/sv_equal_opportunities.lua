-- Selected traitor subroles provide equipment/abilities; native allegiance is never spoofed.
local M = ZC_HMCD_MUTATORS
local ID, NET = "equal_opportunities", "zc_equal_opportunities"
util.AddNetworkString(NET)
local convars = {
    standard = {"ConVarName_SubRole_Traitor", "hmcd_subrole_traitor"},
    gunfreezone = {"ConVarName_SubRole_Traitor_GFZ", "hmcd_subrole_traitor_gfz"},
    soe = {"ConVarName_SubRole_Traitor_SOE", "hmcd_subrole_traitor_soe"}
}
local function RoleFor(mode, p)
    local variant = mode.RoleChooseRoundTypes and mode.RoleChooseRoundTypes[mode.Type]
    local setting = convars[mode.Type]
    if not variant or not variant.Traitor or not setting or not mode.SubRoles then return end
    local pick = p:GetInfo(mode[setting[1]] or setting[2])
    if not variant.Traitor[pick] or not mode.SubRoles[pick] then pick = variant.TraitorDefaultRole end
    local role = pick and variant.Traitor[pick] and mode.SubRoles[pick]
    if not role or type(role.SpawnFunction) ~= "function" then return end
    return pick, role
end
local function ReadyPlayer(p)
    return IsValid(p) and p:Alive() and p:Team() ~= TEAM_SPECTATOR and not p.isPolice
        and (not p.PlayerClassName or p.PlayerClassName == "none")
        and p.organism and p.organism.stamina and not p.organism.otrub and not p.organism.incapacitated
        and not IsValid(p.FakeRagdoll) and not p:InVehicle() and not p:GetNetVar("handcuffed", false)
end
local function Requirements(mode)
    if not hg or not hg.CreateInv or not hg.weaponInv or not hg.weaponInv.Sync then
        return false, "Native inventory API is unavailable"
    end
    local traitors, livingTraitors = 0, 0
    for _, p in ipairs(player.GetAll()) do
        if IsValid(p) and p:Team() ~= TEAM_SPECTATOR and p.isTraitor then traitors = traitors + 1 end
    end
    for _, p in ipairs(M:Players()) do
        if not ReadyPlayer(p) then return false, "Starting players must be conscious civilians with initialized inventories" end
        if not RoleFor(mode, p) then return false, "Native role choices/default are unavailable for " .. mode.Type end
        if p.isTraitor then livingTraitors = livingTraitors + 1 end
    end
    -- Preserve the actual native/staff-selected pair. Never reroll or expose them.
    if traitors ~= 2 or livingTraitors ~= 2 then return false, "Requires exactly two native traitors, both alive at activation (found " .. traitors .. ", alive " .. livingTraitors .. ")" end
    return true
end
local function StopAbilities(mode, p)
    if mode.StopBreakingOtherNeck then mode.StopBreakingOtherNeck(p) end
    if mode.StopDisarmingOther then mode.StopDisarmingOther(p) end
end
-- Undo only values changed by the synchronous kit function, not later damage/stamina use.
local function RestoreStats(current, before, after, seen)
    if type(current) ~= "table" then return end
    seen = seen or {}
    if seen[before] == after then return end
    seen[before] = after
    local keys = {}
    for key in pairs(before) do keys[key] = true end
    for key in pairs(after) do keys[key] = true end
    for key in pairs(keys) do
        local a, b = before[key], after[key]
        if (type(a) == "table" or a == nil) and type(b) == "table" then
            RestoreStats(current[key], a or {}, b, seen)
            if a == nil and type(current[key]) == "table" and next(current[key]) == nil then current[key] = nil end
        elseif a ~= b and current[key] == b then
            current[key] = type(a) == "table" and table.Copy(a) or a
        end
    end
end
local fields = {"isTraitor", "isPolice", "isGunner", "Profession", "SubRole", "MainTraitor"}
local netvars = {"CurPluv", "Accessories", "flashlight"}
local function Snapshot(p)
    local mode = CurrentRound()
    local role = mode.Roles and mode.Roles[mode.Type] and mode.Roles[mode.Type][p.isTraitor and "traitor" or (p.isGunner and "gunner" or "innocent")]
    local s = {ply = p, class = p.PlayerClassName, role = role, fields = {}, vars = {}, weapons = {},
        ammo = table.Copy(p:GetAmmo()), inventory = table.Copy(p:GetNetVar("Inventory") or {}),
        slots = {}, ammoInv = table.Copy(p.ammoInv or {}), ammoAlias = p.ammoInv == p.weaponInv, armors = table.Copy(p.armors or {}),
        armorHealth = table.Copy(p.armors_health or {}), model = p:GetModel(), skin = p:GetSkin(),
        color = p:GetPlayerColor(), name = p:GetNWString("PlayerName"), groups = {}, materials = {},
        appearance = table.Copy(p.CurAppearance or {}), cached = p.CachedAppearance and table.Copy(p.CachedAppearance),
        organism = table.Copy(p.organism), chemicals = table.Copy(p.PassiveAbility_ChemicalAccumulation or {}),
        crusher = p:GetNWBool("zb_is_crusher", false), active = IsValid(p:GetActiveWeapon()) and p:GetActiveWeapon():GetClass()}
    for _, key in ipairs(fields) do s.fields[key] = p[key] end
    for _, key in ipairs(netvars) do s.vars[key] = p:GetNetVar(key) end
    for category, slot in pairs(p.weaponInv or {}) do s.slots[category] = type(slot) == "table" and {limit = slot.limit} or slot end
    for _, group in ipairs(p:GetBodyGroups()) do s.groups[group.id] = p:GetBodygroup(group.id) end
    for i = 0, #p:GetMaterials() - 1 do s.materials[i] = p:GetSubMaterial(i) end
    for _, w in ipairs(p:GetWeapons()) do
        s.weapons[#s.weapons + 1] = {class = w:GetClass(), clip1 = w:Clip1(), clip2 = w:Clip2(),
            attachments = w.attachments and table.Copy(w.attachments), frequency = w.Frequency}
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
    if s.applied and (p.isTraitor ~= s.fields.isTraitor or p.PlayerClassName ~= s.applied) then return end
    StopAbilities(s.mode, p)
    ClearKit(p, s.slots)
    if p.PlayerClassName ~= (s.class or "none") then p:SetPlayerClass(s.class) end
    p.CurAppearance, p.CachedAppearance = table.Copy(s.appearance), s.cached and table.Copy(s.cached)
    p:SetModel(s.model); p:SetSkin(s.skin); p:SetPlayerColor(s.color)
    p:SetSubMaterial()
    for i, material in pairs(s.materials) do p:SetSubMaterial(i, material) end
    for i, value in pairs(s.groups) do p:SetBodygroup(i, value) end
    p:SetNWString("PlayerName", s.name)
    for _, key in ipairs(fields) do p[key] = s.fields[key] end
    for _, key in ipairs(netvars) do p:SetNetVar(key, s.vars[key]) end
    RestoreStats(p.organism, s.organism, s.afterOrganism or s.organism)
    p.PassiveAbility_ChemicalAccumulation = table.Copy(s.chemicals)
    p:SetNWBool("zb_is_crusher", s.crusher)
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
            w:SetClip1(data.clip1); w:SetClip2(data.clip2); w.Frequency = data.frequency
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

end
-- Delete only references to this exact event-created entity, including corpse inventories.
local function RemoveGrant(wep)
    if not IsValid(wep) then return end
    local holders = {}
    local function add(ent) if IsValid(ent) then holders[ent] = true end end
    add(wep:GetOwner())
    add(wep:GetParent())
    for _, ply in ipairs(player.GetAll()) do
        add(ply)
        add(ply.FakeRagdoll)
        add(ply:GetNWEntity("RagdollDeath"))
    end
    for ent in pairs(holders) do
        if ent.weaponInv and hg and hg.weaponInv and hg.weaponInv.Sync then
            local removed = false
            for _, slot in pairs(ent.weaponInv) do
                if type(slot) == "table" then
                    for i = #slot, 1, -1 do
                        if slot[i] == wep then table.remove(slot, i); removed = true end
                    end
                end
            end
            if removed then wep:RemoveCallOnRemove("weaponInv"); hg.weaponInv.Sync(ent) end
        end
        local CLASS = wep:GetClass()
        local inv = ent.inventory
        if inv and inv.Weapons and inv.Weapons[CLASS] == wep then
            inv.Weapons[CLASS] = nil
            ent:SetNetVar("Inventory", inv)
        end
    end
    wep:Remove()
end
local function Send(s, active)
    if not IsValid(s.ply) then return end
    net.Start(NET)
    net.WriteUInt(s.generation, 32)
    net.WriteBool(active)
    net.WriteString(active and s.pick or (s.ply.SubRole or ""))
    net.WriteString(s.variant)
    net.Send(s.ply) -- Own kit only; never broadcast allegiance, secret words, or the traitor list.
end
local function Retire(ctx, p, respawn)
    for _, s in ipairs(ctx.data.loadouts or {}) do
        if s.ply == p and not s.retired then
            s.retired = true
            StopAbilities(ctx.mode, p)
            -- A spawn may already have assigned a new subrole; don't overwrite it.
            if respawn and p.SubRole == s.pick then p.SubRole = s.fields.SubRole end
            Send(s, false)
        end
    end
end
M:Register({
    ID = ID, Title = "Equal Opportunities",
    Description = "Everyone starts with their chosen traitor role's kit and abilities, with IEDs reserved for actual traitors. Only the two actual traitors are enemies; innocents remain innocent.",
    Types = {standard = true, gunfreezone = true, soe = true}, MinPlayers = 3, Weight = 1,
    CanStart = Requirements,
    Start = function(ctx)
        local ready, reason = Requirements(ctx.mode)
        if not ready then error(reason) end
        ctx.data.loadouts = {}
        for _, p in ipairs(ctx.participants) do
            local s = Snapshot(p)
            s.pick, s.recipe = RoleFor(ctx.mode, p)
            s.mode, s.variant, s.generation = ctx.mode, ctx.variant, M.generation
            s.grants = {}
            ctx.data.loadouts[#ctx.data.loadouts + 1] = s
        end
        local spawnHook = ctx.prefix .. "equal_spawn"
        hook.Add("PlayerSpawn", spawnHook, function(p) Retire(ctx, p, true) end)
        ctx:Cleanup(function() hook.Remove("PlayerSpawn", spawnHook) end)
        for _, s in ipairs(ctx.data.loadouts) do
            ctx:Cleanup(function()
                if s.started then
                    -- Remove event weapons even from dropped/corpse inventories before restoring a living kit.
                    for w in pairs(s.grants) do RemoveGrant(w) end
                    Restore(s)
                    Send(s, false)
                end
            end)
        end
        for _, s in ipairs(ctx.data.loadouts) do
            local p = s.ply
            if not ctx:Valid() or not ReadyPlayer(p) then error("Starting participant became unavailable") end
            s.started = true
            ClearKit(p, s.slots)
            p.SubRole = s.pick
            -- GMod resolves Player methods before entity-table fields, so p.Give
            -- cannot intercept native recipes. Wrap the shared method only for
            -- this synchronous grant, and pass all other players through untouched.
            local playerMeta = FindMetaTable("Player")
            local give = playerMeta.Give
            local function scopedGive(target, class, ...)
                if target ~= p then return give(target, class, ...) end
                -- Only filter this mutation's synchronous kit grant, using original allegiance.
                -- No IED entity/inventory entry is created for an innocent or gunner.
                if target == p and class == "weapon_traitor_ied" and not s.fields.isTraitor then return nil end
                local ok, w = pcall(give, target, class, ...)
                -- WeaponEquip can throw after the entity has already been created.
                local created = ok and w or target:GetWeapon(class)
                if IsValid(created) then s.grants[created] = true; created.DontEquipInstantly = true end
                if not ok then error(w) end
                if not IsValid(w) or w:GetOwner() ~= target or w:GetClass() ~= class then error("Native role grant failed: " .. tostring(class)) end
                return w
            end
            playerMeta.Give = scopedGive
            local ok, err = xpcall(function()
                s.recipe.SpawnFunction(p)
                local hands = p:Give("weapon_hands_sh")
                if ctx.variant == "soe" then
                    local radio = p:Give("weapon_walkie_talkie")
                    -- Keep the real traitors' private channel private. Innocent radios use their native default.
                    if p.isTraitor and radio.Frequencies then radio.Frequency = ctx.mode.TraitorFrequency or radio.Frequency end
                end
                p:SetActiveWeapon(hands)
            end, debug.traceback)
            if playerMeta.Give == scopedGive then
                playerMeta.Give = give
            else
                ok, err = false, "Native role setup replaced Player.Give during the scoped grant"
            end
            s.afterOrganism = table.Copy(p.organism or {})
            if not ok then error(err) end
            -- A loadout must never change victory/karma allegiance or late-wave membership.
            if p.isTraitor ~= s.fields.isTraitor or p.isPolice ~= s.fields.isPolice or p.isGunner ~= s.fields.isGunner then
                p.isTraitor, p.isPolice, p.isGunner = s.fields.isTraitor, s.fields.isPolice, s.fields.isGunner
                error("Native role setup unexpectedly changed allegiance")
            end
            if p.SubRole ~= s.pick then error("Native recipe unexpectedly changed selected subrole") end
            for _, slot in pairs(p.weaponInv or {}) do
                if type(slot) == "table" then for i = #slot, 1, -1 do slot[i] = nil end end
            end
            for _, w in ipairs(p:GetWeapons()) do
                local slot = w.weaponInvCategory and p.weaponInv[w.weaponInvCategory]
                if type(slot) == "table" then
                    if not M.Finite(slot.limit) or #slot >= slot.limit then error("Native role kit exceeds inventory capacity") end
                    slot[#slot + 1] = w
                end
            end
            hg.weaponInv.Sync(p)
            s.applied = p.PlayerClassName
        end
        for _, s in ipairs(ctx.data.loadouts) do Send(s, true) end
        -- Native role briefings are delayed per player. Reassert the private kit afterward as well.
        ctx:Timer("equal_resync", 1, 0, function()
            for _, s in ipairs(ctx.data.loadouts) do
                if not s.retired and IsValid(s.ply) and s.ply:Alive() then
                    if s.ply.isTraitor ~= s.fields.isTraitor or s.ply.PlayerClassName ~= s.applied or s.ply.SubRole ~= s.pick then
                        Retire(ctx, s.ply)
                    else Send(s, true) end
                end
            end
        end)
    end,
    PlayerDeath = function(ctx, p) Retire(ctx, p) end,
    PlayerDisconnected = function(ctx, p) Retire(ctx, p) end,
    PlayerSpawn = function(ctx, p) Retire(ctx, p, true) end
})

concommand.Add("zc_mutator_equal_status", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local function output(text)
        local line = "[zc_mutators] " .. text
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line .. "\n") else print(line) end
    end
    local ctx = M.current
    if not ctx or ctx.definition.ID ~= ID then output("Equal Opportunities is inactive") return end
    output("Equal Opportunities: " .. ctx.variant)
    for _, s in ipairs(ctx.data.loadouts or {}) do
        if IsValid(s.ply) then
            output(s.ply:Nick() .. " | " .. s.pick .. " | " .. (s.fields.isTraitor and "traitor" or "innocent")
                .. (s.retired and " | retired" or " | active"))
        end
    end
end)
