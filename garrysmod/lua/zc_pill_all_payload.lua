-- Creature-only collision/damage and rendering for the installed ZCity/Pill Pack.
if SERVER then AddCSLuaFile("autorun/zcity_pillpack_compat.lua") end
ZCityPillCompat = ZCityPillCompat or {}
local C = ZCityPillCompat
C.Version = "20260915.5"
C.states = C.states or setmetatable({}, { __mode = "k" })
C.pending = C.pending or setmetatable({}, { __mode = "k" })
C.wraps = C.wraps or setmetatable({}, { __mode = "k" })
function C.Morph(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    local ent = pk_pills and pk_pills.getMappedEnt and pk_pills.getMappedEnt(ply)
    if IsValid(ent) then return ent end
    if CLIENT then
        ent = ply:GetNWEntity("zc_pill_morph")
        if IsValid(ent) then return ent end
    end
end
function C.Wrap(t, key, factory)
    if not t or not isfunction(t[key]) then return end
    C.wraps[t] = C.wraps[t] or {}
    local r = C.wraps[t][key]
    if r and t[key] == r.wrapper and r.version == C.Version then return end
    local original = r and t[key] == r.wrapper and r.original or t[key]
    local wrapper = factory(original)
    C.wraps[t][key] = { original = original, wrapper = wrapper, version = C.Version }
    t[key] = wrapper
end
function C.IsCarrier(ent)
    if IsValid(C.Morph(ent)) then return true end
    if not IsValid(ent) or not ent:IsPlayer() then return false end
    return (SERVER and C.spawning and C.spawning[ent] ~= nil)
        or (CLIENT and ent.GetNWBool and ent:GetNWBool("zc_pill_spawning", false)) or false
end
-- The native registry stays authoritative; no parallel list of pill definitions.
function C.ResolveAllDefinitions()
    local forms = C.nativeForms
    if not istable(forms) or not pk_pills then return end
    local report = { count = 0, valid = 0, repaired = 0, invalid = {} }
    for name in SortedPairs(forms) do
        report.count = report.count + 1
        local inherited = forms[name].parent ~= nil
        local ok, form, reason = pcall(pk_pills.getPillTable, name)
        if not ok then reason, form = tostring(form), nil end
        if not istable(form) or (form.type ~= "ply" and form.type ~= "phys") then
            report.invalid[name] = tostring(reason or "definition has no supported pill type")
        else
            report.valid = report.valid + 1
            if inherited then report.repaired = report.repaired + 1 end
        end
    end
    C.DefinitionAudit, C.definitionsDirty = report, false
    return report
end
function C.InstallDefinitions()
    if not pk_pills then return end
    C.Wrap(pk_pills, "getPillTable", function(rawGet)
        C.nativeForms = nil
        -- Supported installed Pill Pack keeps its registry in this native getter.
        for i = 1, 32 do
            local key, value = debug.getupvalue(rawGet, i)
            if not key then break end
            if key == "forms" and istable(value) then C.nativeForms = value break end
        end
        C.definitionsDirty = true
        return function(name)
            local visiting = {}
            local function resolve(key, depth)
                if not isstring(key) then return nil, "pill identifier must be a string" end
                if depth > 64 or visiting[key] then
                    return nil, "cyclic or excessively deep pill inheritance: " .. key
                end
                local raw = rawGet(key)
                if not istable(raw) then return nil, "missing pill definition: " .. key end
                if raw.parent == nil then return raw end
                visiting[key] = true
                local parent, err = resolve(raw.parent, depth + 1)
                visiting[key] = nil
                if not parent then return nil, err end
                local merged = table.Merge(table.Copy(parent), table.Copy(raw))
                merged.parent = nil
                return merged
            end
            local resolved, err = resolve(name, 0)
            if not resolved then return nil, err end
            local raw = rawGet(name)
            if resolved ~= raw then
                for k in pairs(raw) do raw[k] = nil end
                for k, v in pairs(resolved) do raw[k] = v end
            end
            return raw
        end
    end)
    C.Wrap(pk_pills, "register", function(previous)
        return function(...)
            local result = previous(...)
            C.definitionsDirty = true
            timer.Create("ZCityPillCompat.Definitions", 0, 1, C.ResolveAllDefinitions)
            return result
        end
    end)
    if C.nativeForms then
        local t = hook.GetTable().Initialize
        if t and isfunction(t.pk_pill_finalize) then
            local before = t.pk_pill_finalize
            C.Wrap(t, "pk_pill_finalize", function()
                -- A malformed addon cannot stop the other valid forms finalizing.
                return function() C.ResolveAllDefinitions() end
            end)
            if before ~= t.pk_pill_finalize then hook.Add("Initialize", "pk_pill_finalize", t.pk_pill_finalize) end
        end
        if C.definitionsDirty then C.ResolveAllDefinitions() end
    end
end

function C.Body(ent)
    if not IsValid(ent) then return end
    local morph = ent.ZCPillCostume
    if IsValid(morph) and morph.GetPuppet and morph:GetPuppet() == ent then
        local ply = morph:GetPillUser()
        if C.Morph(ply) == morph then return morph, ply end
    elseif ent:GetClass() == "pill_ent_phys" then
        local ply = ent:GetPillUser()
        if C.Morph(ply) == ent then return ent, ply end
    end
end
if SERVER then
-- User menu selections can revive spectators, but only after permission checks.
C.spawning = C.spawning or setmetatable({}, { __mode = "k" })
function C.SelectionAllowed(ply, name, form)
    if not form.printName then return false, "You cannot use this pill directly." end
    if pk_pills.convars.admin_restrict:GetBool() and not ply:IsAdmin() then
        return false, "Pills are restricted to Admins."
    end
    if pk_pills._restricted[name] and not ply:IsAdmin() then
        return false, "You must be an Admin to use this pill."
    end
    local old = C.Morph(ply)
    if IsValid(old) and old.locked then return false, "You are locked in your current pill." end
    return true
end
function C.CancelSpawn(ply)
    local r = C.spawning[ply]
    if not r then return end
    C.spawning[ply] = nil
    if IsValid(ply) then
        ply:SetNWBool("zc_pill_spawning", false)
        if r.base then
            ply:Freeze(false)
            if not C.Morph(ply) then ply:SetRenderMode(r.base.render) end
        end
    end
end
function C.RollbackSpawn(ply, reason)
    local r = C.spawning[ply]
    if not r then return end
    if not IsValid(ply) then C.spawning[ply] = nil return end
    local morph, old = C.Morph(ply), r.old
    if ply:Alive() then ply:KillSilent() end
    if IsValid(morph) then morph.dead = true; morph:Remove() end
    for _, ent in ipairs(r.created) do
        if IsValid(ent) then ent.dead = true; ent:Remove() end
    end
    C.Sync(ply)
    C.CancelSpawn(ply)
    ply:SetTeam(old.team)
    ply:SetPos(old.pos)
    ply:SetEyeAngles(old.angles)
    ply:Spectate(old.observer ~= OBS_MODE_NONE and old.observer or OBS_MODE_ROAMING)
    if IsValid(old.target) then ply:SpectateEntity(old.target) end
    ply:SetMoveType(old.movetype)
    ply:SetRenderMode(old.render)
    ply:SetNotSolid(old.notsolid)
    ply:Freeze(old.frozen)
    if old.god then ply:GodEnable() else ply:GodDisable() end
    ply.chosenSpectEntity, ply.lastSpectTarget = old.chosen, old.last
    ply.viewmode, ply.chosenspect = old.viewmode, old.chosenspect
    ply:SetNWEntity("spect", IsValid(old.spect) and old.spect or NULL)
    ply:SetNWInt("viewmode", old.nwview)
    if reason then ply:ChatPrint("Pill selection failed; you remain spectating. " .. reason) end
end
function C.SpawnSelection(ply, name, mode, option)
    if C.spawning[ply] then return end
    local form, err = pk_pills.getPillTable(name)
    if not form then ply:ChatPrint("Cannot use pill: " .. tostring(err)) return end
    local allowed, reason = C.SelectionAllowed(ply, name, form)
    if not allowed then ply:ChatPrint(reason) return end
    if ply.initialspawn or OverrideSpawn then
        ply:ChatPrint("Please wait for the current spawn to finish, then select your pill again.") return
    end
    local old = C.Capture(ply)
    old.team, old.pos, old.angles = ply:Team(), ply:GetPos(), ply:EyeAngles()
    old.observer, old.target, old.frozen = ply:GetObserverMode(), ply:GetObserverTarget(), ply:IsFrozen()
    old.chosen, old.last = ply.chosenSpectEntity, ply.lastSpectTarget
    old.viewmode, old.chosenspect = ply.viewmode, ply.chosenspect
    old.spect, old.nwview = ply:GetNWEntity("spect"), ply:GetNWInt("viewmode")
    local r = { old = old, created = {}, inSpawn = true, round = zb and zb.ROUND_START, phase = zb and zb.ROUND_STATE }
    C.spawning[ply] = r
    local ok, failure = xpcall(function()
        if old.team == TEAM_SPECTATOR or old.team == TEAM_UNASSIGNED then
            ply:SetTeam(zb and zb.BalancedChoice and zb:BalancedChoice(0, 1) or 1)
        end
        ply:UnSpectate()
        ply:Spawn()
        if not ply:Alive() then error("The gamemode rejected the spawn.") end
        if isfunction(ply.GetRandomSpawn) then ply:GetRandomSpawn() end
        ply:SetNWEntity("spect", NULL)
        ply:SetViewEntity(ply)
        ply.chosenSpectEntity, ply.lastSpectTarget = nil, nil
        r.base = C.Capture(ply)
        ply:Freeze(true)
        ply:SetRenderMode(RENDERMODE_NONE)
        ply:SetNWBool("zc_pill_spawning", true)
    end, debug.traceback)
    r.inSpawn = false
    if not ok then C.RollbackSpawn(ply, "Spawn initialization failed.") ErrorNoHalt(failure .. "\n") return end
    -- Run after the gamemode's queued spawn/hull resets, not before them.
    timer.Simple(0, function()
        if not IsValid(ply) or C.spawning[ply] ~= r then return end
        if not ply:Alive() or (zb and (zb.ROUND_START ~= r.round or zb.ROUND_STATE ~= r.phase)) then
            C.RollbackSpawn(ply, "The round or player state changed.") return
        end
        local definition, why = pk_pills.getPillTable(name)
        local permit, denial = false, why
        if definition then permit, denial = C.SelectionAllowed(ply, name, definition) end
        if not permit then C.RollbackSpawn(ply, denial) return end
        ply:Freeze(false)
        ply:SetRenderMode(r.base.render)
        r.applying = true
        local success, result = xpcall(function() return pk_pills.apply(ply, name, mode, option) end, debug.traceback)
        r.applying = false
        if not success or not IsValid(result) or C.Morph(ply) ~= result then
            C.RollbackSpawn(ply, "The selected creature could not be created.")
            if not success then ErrorNoHalt(result .. "\n") end
            return
        end
        C.CancelSpawn(ply)
        C.Sync(ply)
    end)
end
hook.Add("PlayerSpawn", "ZCityPillCompat_CancelPendingSpawn", function(ply)
    local r = C.spawning[ply]
    if r and not r.inSpawn and not r.applying then C.CancelSpawn(ply) end
end)

    function C.EnsureClass(ply)
        if not IsValid(ply) then return end
        local classes = player_manager.GetPlayerClasses()
        local cur = classes[player_manager.GetPlayerClass(ply)]
        if cur and isnumber(cur.StartHealth) then return end
        local fallback = classes.player_default
        if fallback then
            fallback.StartHealth = fallback.StartHealth or 100
            player_manager.SetPlayerClass(ply, "player_default")
        end
    end
    function C.Capture(ply)
        return { render = ply:GetRenderMode(), notsolid = bit.band(ply:GetSolidFlags(), FSOLID_NOT_SOLID) ~= 0,
            god = ply:HasGodMode(), health = ply:Health(), maxhealth = ply:GetMaxHealth(),
            movetype = ply:GetMoveType() }
    end
    function C.Configure(morph, ply)
        if morph:GetClass() ~= "pill_ent_costume" then return end
        local puppet = morph:GetPuppet()
        if not IsValid(puppet) then return end
        if puppet.ZCPillCostume ~= morph then
            puppet.ZCPillCostume = morph
            puppet:SetPos(ply:GetPos())
            puppet:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            puppet:SetMoveType(MOVETYPE_NONE)
            puppet:SetSolid(SOLID_BBOX)
            puppet:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            puppet:SetOwner(ply)
            puppet:SetHealth(1000000)
            local mins, maxs = puppet:GetModelBounds()
            puppet:SetCollisionBounds(mins, maxs)
            puppet:AddSolidFlags(FSOLID_NOT_STANDABLE)
        end
        puppet:SetNotSolid(morph.burrowed == true)
    end
    function C.Begin(ply, morph, base)
        if not IsValid(ply) or not IsValid(morph) then return end
        C.states[ply] = { morph = morph, base = base }
        ply:SetNWEntity("zc_pill_morph", morph)
        ply:SetNotSolid(true)
        ply:SetRenderMode(RENDERMODE_NONE)
        C.Configure(morph, ply)
    end
    function C.End(ply)
        local state = C.states[ply]
        if not state or not IsValid(ply) then return end
        C.states[ply] = nil
        ply:SetNWEntity("zc_pill_morph", NULL)
        local base = state.base
        ply:SetRenderMode(base.render)
        ply:SetNotSolid(base.notsolid)
        if base.god then ply:GodEnable() else ply:GodDisable() end
        if ply:Alive() then
            ply:SetMoveType(base.movetype)
            ply:SetMaxHealth(base.maxhealth)
            ply:SetHealth(base.health)
        end
    end
    function C.Sync(ply)
        local state = C.states[ply]
        if not state then return end
        if not IsValid(ply) then C.states[ply] = nil return end
        local morph = C.Morph(ply)
        if not IsValid(morph) then C.End(ply) return end
        state.morph = morph
        if ply:GetNWEntity("zc_pill_morph") ~= morph then ply:SetNWEntity("zc_pill_morph", morph) end
        ply:SetRenderMode(RENDERMODE_NONE)
        ply:SetNotSolid(true)
        C.Configure(morph, ply)
    end
    function C.Damage(ent, dmg)
        if C.IsCarrier(ent) then return true end
        local morph, ply = C.Body(ent)
        if not morph then return end
        local state = C.states[ply]
        if not state or state.dying or state.base.god then return true end
        local amount = dmg:GetDamage()
        if amount <= 0 or amount ~= amount then return true end
        if morph:GetClass() == "pill_ent_phys" then
            -- Keep the pack's explosive-only health, die callbacks and physics forms.
            if morph.ZCHandlingDamage then return true end
            morph.ZCHandlingDamage = true
            local ok, err = pcall(morph.OnTakeDamage, morph, dmg)
            if IsValid(morph) then morph.ZCHandlingDamage = nil end
            if not ok then ErrorNoHalt("[ZCityPillCompat] physical damage: " .. tostring(err) .. "\n") end
            return true
        end
        local form = morph.formTable or {}
        if not form.health then return true end
        local blast = dmg:IsDamageType(DMG_BLAST)
        if form.onlyTakesExplosiveDamage and not blast then return true end
        if form.onlyTakesExplosiveDamage then amount = 1 end
        local hp = ply:Health() - amount
        if hp <= 0 or (form.diesOnExplode and blast) then
            state.dying = true
            morph:PillDie()
            C.Sync(ply)
        else
            -- Player health is Pill Pack's HUD backing store, not a human damage event.
            ply:SetHealth(hp)
        end
        return true
    end
    function C.ProtectEvent(event, mode)
        local t = hook.GetTable()[event]
        if not t then return end
        for key in pairs(t) do
            local identifier, before = key, t[key]
            C.Wrap(t, key, function(previous)
                return function(...)
                    local a, b, c = ...
                    local ent, dmg = a, b
                    if not isstring(identifier) then ent, dmg = b, c end
                    if mode == "damage" then
                        local result = C.Damage(ent, dmg)
                        if result ~= nil then return result end
                    elseif C.IsCarrier(ent) or (mode == "trace" and C.Body(ent)) then
                        return true
                    end
                    return previous(...)
                end
            end)
            if t[key] ~= before then hook.Add(event, key, t[key]) end
        end
    end
    function C.Install()
        C.InstallDefinitions()
        if not pk_pills or not pk_pills.getMappedEnt then return end
        C.Wrap(pk_pills, "apply", function(previous)
            return function(ply, ...)
                if not IsValid(ply) or not ply:IsPlayer() then return end
                local name, mode, option = ...
                local spawn = C.spawning[ply]
                if mode == "user" and spawn and not spawn.applying then return end
                local form, err = pk_pills.getPillTable(name)
                if not form or (form.type ~= "ply" and form.type ~= "phys") then
                    ply:ChatPrint("Cannot use pill \"" .. tostring(name) .. "\": " .. tostring(err or "definition has no supported pill type")) return
                end
                if mode == "user" and not IsValid(C.Morph(ply))
                    and (not ply:Alive() or ply:Team() == TEAM_SPECTATOR or ply:GetObserverMode() ~= OBS_MODE_NONE) then
                    return C.SpawnSelection(ply, name, mode, option)
                end
                C.EnsureClass(ply)
                local pending, args = C.pending[ply], { ... }
                C.pending[ply] = pending or (C.states[ply] and C.states[ply].base) or C.Capture(ply)
                local ok, result = xpcall(function() return previous(ply, unpack(args)) end, debug.traceback)
                C.pending[ply] = pending
                C.Sync(ply)
                if not ok then error(result, 0) end
                return result
            end
        end)
        C.Wrap(pk_pills, "restore", function(previous)
            return function(ply, ...)
                C.EnsureClass(ply)
                local result = previous(ply, ...)
                C.Sync(ply)
                return result
            end
        end)
        for _, name in ipairs({ "pill_ent_costume", "pill_ent_phys" }) do
            local stored = scripted_ents.GetStored(name)
            local t = stored and stored.t
            C.Wrap(t, "Initialize", function(previous)
                return function(ent, ...)
                    local ply = ent:GetPillUser()
                    if not IsValid(ply) then return previous(ent, ...) end
                    C.EnsureClass(ply)
                    local base = C.pending[ply] or (C.states[ply] and C.states[ply].base) or C.Capture(ply)
                    local spawning = C.spawning[ply]
                    if spawning and spawning.applying then spawning.created[#spawning.created + 1] = ent end
                    local result = previous(ent, ...)
                    if IsValid(ent) and C.Morph(ply) == ent then C.Begin(ply, ent, base) end
                    return result
                end
            end)
            C.Wrap(t, "OnRemove", function(previous)
                return function(ent, ...)
                    local ply = ent:GetPillUser()
                    local result = previous(ent, ...)
                    if IsValid(ply) then C.Sync(ply) end
                    return result
                end
            end)
        end
        C.ProtectEvent("EntityTakeDamage", "damage")
        C.ProtectEvent("ScalePlayerDamage", "trace")
        C.ProtectEvent("PlayerTraceAttack", "trace")
        C.ProtectEvent("ScaleNPCDamage", "trace")
        C.ProtectEvent("Org Think", "organism")
        C.Wrap(hg, "Fake", function(previous)
            return function(ply, ...)
                if C.IsCarrier(ply) then return end
                return previous(ply, ...)
            end
        end)
    end
    hook.Add("EntityTakeDamage", "ZCityPillCompat_CreatureDamage", C.Damage)
    hook.Add("Think", "ZCityPillCompat_State", function()
        for ply in pairs(C.states) do C.Sync(ply) end
    end)
    local function restoreAll()
        for ply in pairs(C.spawning) do C.RollbackSpawn(ply) end
        if not pk_pills or not pk_pills.restore then return end
        for _, ply in ipairs(player.GetAll()) do
            if C.IsCarrier(ply) then
                local ok, err = pcall(pk_pills.restore, ply, true)
                if not ok then ErrorNoHalt("[ZCityPillCompat] restore: " .. tostring(err) .. "\n") end
                C.Sync(ply)
            end
        end
    end
    hook.Add("ZB_EndRound", "ZCityPillCompat_RoundReset", restoreAll)
    hook.Add("ZB_PreRoundStart", "ZCityPillCompat_RoundReset", restoreAll)
    hook.Add("PlayerDisconnected", "ZCityPillCompat_Cleanup", function(ply)
        C.states[ply], C.pending[ply], C.spawning[ply] = nil, nil, nil
    end)
else
    C.hidden = C.hidden or setmetatable({}, { __mode = "k" })
    local function hideHuman(previous)
        return function(a, b, ...)
            if C.IsCarrier(a) or C.IsCarrier(b) then return end
            return previous(a, b, ...)
        end
    end
    hook.Add("PrePlayerDraw", "ZCityPillCompat_HideHuman", function(ply)
        if C.IsCarrier(ply) then return true end
    end)
    function C.Install()
        C.InstallDefinitions()
        C.Wrap(hg, "renderOverride", hideHuman)
        C.Wrap(hg, "build_bone_positions", hideHuman)
        for _, name in ipairs({ "DrawPlayerRagdoll", "DrawAppearance", "RenderAccessoriesCool" }) do
            C.Wrap(_G, name, hideHuman)
        end
        local t = hook.GetTable().CalcView
        if t then
            local before = t.momo_calcview
            C.Wrap(t, "momo_calcview", function(previous)
                return function(ply, pos, ang, fov, nearZ, farZ)
                    local morph = C.Morph(ply)
                    if not IsValid(morph) then return previous(ply, pos, ang, fov, nearZ, farZ) end
                    if GetViewEntity() ~= ply then return end
                    if ZCityDronesCompat and IsValid(ZCityDronesCompat.Active(ply)) then return end
                    local view = previous(ply, pos, ang, fov, nearZ, farZ)
                    if istable(view) then return view end
                    local form = morph.formTable or {}
                    if form.type == "phys" then
                        pos = morph:LocalToWorld(form.camera and form.camera.offset or vector_origin)
                    end
                    return { origin = pos, angles = ang, fov = fov,
                        znear = nearZ, zfar = farZ, drawviewer = false }
                end
            end)
            if before ~= t.momo_calcview then hook.Add("CalcView", "momo_calcview", t.momo_calcview) end
        end
    end
    hook.Add("Think", "ZCityPillCompat_HideCarrier", function()
        for _, ply in ipairs(player.GetAll()) do
            if C.IsCarrier(ply) then
                if not C.hidden[ply] then C.hidden[ply] = { nodraw = ply:GetNoDraw() } end
                if not ply:GetNoDraw() then ply:SetNoDraw(true) end
            elseif C.hidden[ply] then
                if ply:GetNoDraw() then ply:SetNoDraw(C.hidden[ply].nodraw) end
                C.hidden[ply] = nil
            end
        end
    end)
end
hook.Add("InitPostEntity", "ZCityPillCompat_Install", C.Install)
hook.Add("PostGamemodeLoaded", "ZCityPillCompat_Install", C.Install)
timer.Create("ZCityPillCompat.Install", 1, 0, C.Install)
C.Install()
print("[ZCityPillCompat] " .. C.Version .. " loaded (" .. (SERVER and "server" or "client") .. ")")

-- Shared camera arbiter; identical in both compatibility addons.
if CLIENT then
    ZCityCompatView = ZCityCompatView or { hooks = {} }
    function ZCityCompatView.Active()
        local p = LocalPlayer()
        if not IsValid(p) then return false end
        return (ZCityDronesCompat and IsValid(ZCityDronesCompat.Active(p)))
            or (ZCityPillCompat and IsValid(ZCityPillCompat.Morph(p)))
    end
    function ZCityCompatView.Install()
        for event, name in pairs({ CalcView = "homigrad-view", RenderScene = "jopa" }) do
            local t = hook.GetTable()[event]
            local current = t and t[name]
            local old = ZCityCompatView.hooks[event]
            if isfunction(current) and (not old or current ~= old.wrapper) then
                local original = current
                local wrapper = function(...)
                    if ZCityCompatView.Active() then return end
                    return original(...)
                end
                ZCityCompatView.hooks[event] = { original = original, wrapper = wrapper }
                hook.Add(event, name, wrapper)
            end
        end
    end
    timer.Create("ZCityCompatView.Install", 1, 0, ZCityCompatView.Install)
    ZCityCompatView.Install()
end
