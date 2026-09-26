-- All identity and clue selection stays on the server.
local M = ZC_HMCD_MUTATORS
M.sightingSequence = ZC_INFORMANT_SIGHTING_SEQUENCE or 0
local CLASS = "weapon_zc_informant_phone"
local MODEL = "models/saraphines/insurgency explosives/ied/insurgency_ied_phone.mdl"
local WAYPOINT = "zc_informant_sighting"
local SIGHTING_SECONDS = ZC_HMCD_MUTATOR_INFO.SightingDuration
util.AddNetworkString(WAYPOINT)
local hint = CreateConVar("zc_mutator_informant_hint", "2", FCVAR_ARCHIVE, "Calls: 0 role only, 1 sighting only, 2 recurring random fresh hints", 0, 2)
local DEATH = "zc_informant_death"
util.AddNetworkString(DEATH)
local interval = CreateConVar("zc_mutator_informant_interval", "90", FCVAR_ARCHIVE, "Seconds between random Informant call slots", 5, 600)
local delay = CreateConVar("zc_mutator_informant_delay", "180", FCVAR_ARCHIVE, "Seconds from mutator activation to the call", 5, 900)
local ringTime = CreateConVar("zc_mutator_informant_ring_time", "20", FCVAR_ARCHIVE, "Seconds available to answer", 5, 60)
local callTime = CreateConVar("zc_mutator_informant_call_time", "8", FCVAR_ARCHIVE, "Seconds spent listening", 4, 30)
-- Existing ZCity assets: AddFile handles model companions; explicitly list its materials.
if file.Exists(MODEL, "GAME") then
    resource.AddFile(MODEL)
    for _, ext in ipairs({".vmt", ".vtf"}) do resource.AddFile("materials/models/saraphines/explosives/ied_cell_phone_dm" .. ext) end
    resource.AddFile("materials/models/saraphines/explosives/ied_cell_phone_nm.vtf")
    resource.AddFile("materials/models/saraphines/explosives/ied_cell_phone_em.vtf")
end
local function Living(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:Alive() and ply:Team() ~= TEAM_SPECTATOR
end
local function Available(ply)
    return Living(ply) and not ply.isTraitor and not (ply.organism and ply.organism.otrub)
        and not IsValid(ply.FakeRagdoll) and not ply:InVehicle()
        and not ply:GetNetVar("handcuffed", false) and ply.PlayerClassName ~= "Gordon"
        and (not hg or not hg.CanUseRightHand or hg.CanUseRightHand(ply))
end
local roleClues = {
    traitor_default = "One of them is Defoko. They came prepared with explosives. Be careful what you pick up.",
    traitor_default_soe = "One of them is Defoko. They came prepared with explosives. Be careful what you pick up.",
    traitor_infiltrator = "An Infiltrator is among you. They can steal a face. Don't trust appearances.",
    traitor_infiltrator_soe = "An Infiltrator is among you. They can steal a face. Don't trust appearances.",
    traitor_assasin = "An Assassin is among you. They can disarm you fast. Keep your distance.",
    traitor_assasin_soe = "An Assassin is among you. They can disarm you fast. Keep your distance.",
    traitor_chemist = "A Chemist is among you. Watch what you eat and drink. That's all I can tell you.",
    traitor_zombie = "A Zombie is hiding among you. They can spread infection while looking human. Find a doctor."
}
local function Clue(mode, ply)
    if not Living(ply) or not ply.isTraitor then return end
    local id = ply.SubRole
    if id == nil or id == "" then
        -- GFZ normally has no subrole selection. Also supports roles-disabled Standard/SOE.
        -- Check current equipment, never label the default loadout as a specialist role.
        if ply:HasWeapon("weapon_traitor_ied") then
            return "One of the killers has a remote explosive. Be careful around unattended objects."
        end
        for _, class in ipairs({"weapon_traitor_poison1", "weapon_traitor_poison2", "weapon_traitor_poison3", "weapon_traitor_poison4", "weapon_traitor_poison_consumable"}) do
            if ply:HasWeapon(class) then return "One of the killers has poison. Be careful what you touch or consume." end
        end
        if ply:HasWeapon("weapon_traitor_suit") then
            return "One of the killers has a disguise kit. Don't rely on appearances."
        end
        return "A killer is still among you. I couldn't confirm their equipment. Keep your eyes open."
    end
    local role = mode.SubRoles and mode.SubRoles[id]
    local name = role and role.Name
    if type(name) ~= "string" or #name == 0 or #name > 80 then return end
    name = name:gsub("[%c]", "")
    if name == "" then return end
    return roleClues[id] or ("A living traitor's specialty is " .. name .. ". Stay alert.")
end
local function Position(ply)
    if not Living(ply) or not ply.isTraitor then return end
    local character = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or ply
    if not IsValid(character) then return end
    local v = character:GetPos()
    if not v or not M.Finite(v.x) or not M.Finite(v.y) or not M.Finite(v.z)
        or math.abs(v.x) > 32768 or math.abs(v.y) > 32768 or math.abs(v.z) > 32768 then return end
    return Vector(v.x, v.y, v.z + 40)
end
local function ClearWaypoint(ctx)
    local d = ctx.data
    if not d.waypointSent then return end
    d.waypointSent = false
    if not IsValid(d.recipient) then return end
    net.Start(WAYPOINT)
    net.WriteUInt(d.waypointID, 32); net.WriteBool(false)
    net.Send(d.recipient)
end
local function RemovePhone(wep)
    if not wep then return end
    if IsValid(wep) then wep:StopRing() end
    local holders = {}
    local function add(ent) if IsValid(ent) then holders[ent] = true end end
    if IsValid(wep) then add(wep:GetOwner()); add(wep:GetParent()) end
    for _, ply in ipairs(player.GetAll()) do
        add(ply); add(ply.FakeRagdoll); add(ply:GetNWEntity("RagdollDeath"))
    end
    for ent in pairs(holders) do
        if IsValid(wep) and ent.weaponInv and hg and hg.weaponInv and hg.weaponInv.Remove and hg.weaponInv.Sync then
            if hg.weaponInv.Remove(ent, wep) then hg.weaponInv.Sync(ent) end
        end
        local inv = ent.inventory
        if inv and inv.Weapons and inv.Weapons[CLASS] == wep then
            inv.Weapons[CLASS] = nil
            ent:SetNetVar("Inventory", inv)
        end
    end
    if IsValid(wep) then
        wep.ZCInformantContext = nil
        wep:Remove()
    end
end
local function NextSlot(d)
    local due = d.nextSlot or d.due + d.interval
    while due <= CurTime() do due = due + d.interval end
    d.due, d.nextSlot = due, due + d.interval
end
local function Finish(ctx, reason, terminal)
    local d = ctx.data
    if d.finished then return end
    ClearWaypoint(ctx)
    RemovePhone(d.phone)
    d.phone, d.sightings, d.abortReason = nil, nil, nil
    if d.hint == 2 and not terminal and Living(d.recipient) and not d.recipient.isTraitor then
        d.phase, d.outcome = "between_calls", reason
        NextSlot(d)
        M:Log("Informant call ended: " .. reason .. "; next call slot scheduled")
        return
    end
    d.finished, d.outcome = true, reason
    M:Log("Informant call ended: " .. reason)
end
local function InformantDeath(ctx, ply)
    local d = ctx.data
    if ply ~= d.recipient or d.deathAnnounced then return end
    d.deathAnnounced = true
    net.Start(DEATH)
    net.WriteUInt(ctx.generation, 32)
    net.WriteUInt(math.floor(M:Random() * 3) + 1, 2)
    net.Broadcast()
    Finish(ctx, "recipient died", true)
end
local function Owned(ctx, wep, ply)
    return ctx:Valid() and not ctx.data.finished and ctx.data.phone == wep
        and ctx.data.recipient == ply and IsValid(wep) and wep:GetOwner() == ply and Available(ply)
end
function M:InformantAnswer(wep, ply)
    local ctx = self.current
    if not ctx or ctx.definition.ID ~= "informant" or not Owned(ctx, wep, ply)
        or ply:GetActiveWeapon() ~= wep or ctx.data.phase ~= "ringing" or CurTime() >= ctx.data.deadline then return end
    ctx.data.phase, ctx.data.transition = "raising", CurTime() + 0.6
    wep:StopRing()
    wep:SetCallPhase(1); wep:SetPhaseStart(CurTime())
end
function M:InformantAbort(wep, reason)
    local ctx = self.current
    if ctx and ctx.definition.ID == "informant" and ctx.data.phone == wep then
        ctx.data.abortReason = reason or "interrupted"
        if IsValid(wep) then wep:StopRing() end
    end
end
local function DisplayName(ply)
    if not IsValid(ply) then return end
    local name = ply:Nick()
    if type(name) ~= "string" or #name > 128 then return end
    name = name:gsub("[%c]", " "):match("^%s*(.-)%s*$")
    if name == "" then return end
    return name
end
local function ConfirmedName(ctx, target)
    if not Living(target) or target == ctx.data.recipient or target.isTraitor then return end
    local name = DisplayName(target)
    if not name then return end
    -- Never clear a name shared by another living player, including a traitor.
    for _, other in ipairs(player.GetAll()) do
        if other ~= target and Living(other) and DisplayName(other) == name then return end
    end
    return name
end
local function Notify(ctx, ply, text, key, confirmed, confirmedName)
    local callNumber = ctx.data.callNumber
    -- ZCity Notify schedules its send: revalidate the context in its cancellation predicate.
    return ply:Notify(text, 0, ctx.prefix .. callNumber .. "_" .. key, 0, function(p)
        return ctx.data.callNumber ~= callNumber or not Owned(ctx, ctx.data.phone, p) or ctx.data.abortReason ~= nil
            or (confirmed ~= nil and ConfirmedName(ctx, confirmed) ~= confirmedName)
            or (key == "clue" and p:GetActiveWeapon() ~= ctx.data.phone)
    end, Color(220, 200, 150))
end
local function FreshTargets(ctx, kind)
    local d, out = ctx.data, {}
    if kind == 0 and d.roleCount >= 2 then return out end
    for _, target in ipairs(ctx.participants) do
        if (kind == 0 and not d.rolesSeen[target] and Clue(ctx.mode, target))
            or (kind == 1 and Position(target))
            or (kind == 2 and not d.innocentsSeen[target] and ConfirmedName(ctx, target)) then
            out[#out + 1] = target
        end
    end
    return out
end
local function Tick(ctx)
    local d, now = ctx.data, CurTime()
    if d.finished then return end
    if d.hint == 2 then
        if IsValid(d.recipient) and not d.recipient:Alive() then InformantDeath(ctx, d.recipient); return end
        if not Living(d.recipient) or d.recipient.isTraitor then Finish(ctx, "recipient unavailable", true); return end
    end
    if now < d.due then return end
    if d.abortReason then Finish(ctx, d.abortReason); return end
    if d.phase == "waiting" or d.phase == "between_calls" then
        local candidates, targets = {}, {}
        if d.hint == 2 then
            if not Available(d.recipient) or d.recipient:HasWeapon(CLASS) then Finish(ctx, "recipient temporarily unavailable"); return end
            local pool = {}
            for kind = 0, 2 do
                local rows = FreshTargets(ctx, kind)
                if #rows > 0 then pool[#pool + 1] = {kind = kind, targets = rows} end
            end
            if #pool == 0 then Finish(ctx, "no fresh information"); return end
            local picked = pool[math.floor(M:Random() * #pool) + 1]
            d.callKind, targets = picked.kind, picked.targets
            candidates = {d.recipient}
            d.callNumber = d.callNumber + 1
            d.nextSlot = d.due + d.interval
        else
        for _, ply in ipairs(ctx.participants) do
            if (d.callNumber == 1 or ply == d.recipient) and Available(ply) and type(ply.Notify) == "function" and not ply:HasWeapon(CLASS) then candidates[#candidates + 1] = ply end
            if (d.callKind == 2 and ConfirmedName(ctx, ply)) or
                ((d.hint ~= 2 or d.callNumber == 1 or ply == d.reportedTarget)
                and ((d.callKind == 1 and Position(ply)) or (d.callKind == 0 and Clue(ctx.mode, ply)))) then targets[#targets + 1] = ply end
        end
        end
        if #candidates == 0 or #targets == 0 then
            if now >= d.due + 30 then Finish(ctx, "no eligible recipient or clue target") end
            return
        end
        local ply = candidates[math.floor(M:Random() * #candidates) + 1]
        d.recipient = ply
        if d.callKind == 1 then
            -- Copy each possible target before the first ring; never update these positions.
            d.sightings = {}
            for _, target in ipairs(targets) do
                local pos = Position(target)
                if pos then d.sightings[#d.sightings + 1] = {target = target, pos = pos, time = now} end
            end
        end
        -- Also covers an Equip hook throwing after Give has already created the entity.
        local granted, pending = nil, true
        ctx:Cleanup(function() RemovePhone(granted or (pending and IsValid(ply) and ply:GetWeapon(CLASS))) end)
        local wep = ply:Give(CLASS, true)
        granted, pending = wep, false
        if not IsValid(wep) then error("Informant phone grant failed") end
        d.phone = wep
        if wep:GetOwner() ~= ply then error("Informant phone has unexpected owner") end
        wep.ZCInformantContext = ctx
        d.phase, d.deadline, d.nextRing = "ringing", now + d.ringTime, now + 0.3
        wep:SetCallPhase(0); wep:SetPhaseStart(now)
        Notify(ctx, ply, "A phone is ringing in your pocket. Select it and press primary attack to answer.", "ring")
        return
    end
    local ply, wep = d.recipient, d.phone
    if not Owned(ctx, wep, ply) then Finish(ctx, "recipient unavailable"); return end
    if d.phase ~= "ringing" and ply:GetActiveWeapon() ~= wep then Finish(ctx, "phone put away"); return end
    if d.phase == "ringing" then
        if now >= d.deadline then Finish(ctx, "unanswered"); return end
        if now >= d.nextRing then
            -- Server-side spatial sound, audible to nearby players. No clue text in sound/net state.
            wep:PlayRing()
            d.nextRing = now + 2.4
        end
    elseif d.phase == "raising" and now >= d.transition then
        local targets, clue, sighting, confirmed, confirmedName = {}, nil, nil, nil, nil
        if d.callKind == 2 then
            for _, target in ipairs(ctx.participants) do
                if ConfirmedName(ctx, target) and (d.hint ~= 2 or not d.innocentsSeen[target]) then targets[#targets + 1] = target end
            end
            if #targets == 0 then Finish(ctx, "no other living innocent to confirm"); return end
            confirmed = targets[math.floor(M:Random() * #targets) + 1]
            confirmedName = ConfirmedName(ctx, confirmed)
            clue = "Unknown caller: You're going to need help. " .. confirmedName .. " isn't one of them. What you do with that is up to you."
        elseif d.callKind == 1 then
            for _, row in ipairs(d.sightings or {}) do
                if Living(row.target) and row.target.isTraitor then targets[#targets + 1] = row end
            end
            if #targets == 0 then Finish(ctx, "no living sighting target"); return end
            sighting = targets[math.floor(M:Random() * #targets) + 1]
            clue = "Unknown caller: One of them was seen at the marked spot. They may have moved. You have ten seconds."
        else
            for _, target in ipairs(ctx.participants) do if Clue(ctx.mode, target) and (d.hint ~= 2 or (d.roleCount < 2 and not d.rolesSeen[target])) then targets[#targets + 1] = target end end
            if #targets == 0 then Finish(ctx, "no living traitor clue"); return end
            local target = targets[math.floor(M:Random() * #targets) + 1]
            d.reportedTarget = target
            clue = (d.hint == 2 and d.roleCount > 0 and "Unknown caller: A different traitor this time. " or "Unknown caller: Listen carefully. ") .. Clue(ctx.mode, target)
        end
        d.phase, d.transition = "listening", now + math.max(d.callTime, d.callKind == 1 and SIGHTING_SECONDS or 0)
        wep:SetCallPhase(2); wep:SetPhaseStart(now)
        -- Consume unique information when its notification is requested, never on an unanswered ring.
        -- Conservative if the gamemode later suppresses Notify: never repeat a potentially seen identity.
        if d.hint == 2 then
            if d.callKind == 0 then d.rolesSeen[d.reportedTarget] = true; d.roleCount = d.roleCount + 1 end
            if confirmed then d.innocentsSeen[confirmed] = true end
        end
        Notify(ctx, ply, clue, "clue", confirmed, confirmedName)
        if sighting then
            M.sightingSequence = (M.sightingSequence or 0) + 1
            ZC_INFORMANT_SIGHTING_SEQUENCE = M.sightingSequence
            d.waypointID = M.sightingSequence
            net.Start(WAYPOINT)
            net.WriteUInt(d.waypointID, 32); net.WriteBool(true)
            net.WriteVector(sighting.pos)
            net.WriteFloat(now + SIGHTING_SECONDS); net.WriteFloat(sighting.time)
            net.Send(ply)
            d.waypointSent = true
            d.sightings = nil
        end
        d.clueRequested = true -- Notify may still be suppressed by the gamemode's injury rules.
    elseif d.phase == "listening" and now >= d.transition then
        d.phase, d.transition = "lowering", now + 0.6
        wep:SetCallPhase(3); wep:SetPhaseStart(now)
    elseif d.phase == "lowering" and now >= d.transition then
        Finish(ctx, "completed")
    end
end
M:Register({
    MidRound = true,
    ID = "informant", Title = "The Informant",
    Description = "An innocent may receive a mysterious call. Nearby players can hear the phone ring.",
    Types = {standard = true, gunfreezone = true, soe = true}, MinPlayers = 2, Weight = 1,
    CanStart = function()
        if not weapons.GetStored(CLASS) then return false, "Informant phone weapon is unavailable" end
        if not file.Exists(MODEL, "GAME") then return false, "ZCity Content 2 phone model is missing" end
        if hint:GetInt() == 2 then
            for _, ply in ipairs(M:Players()) do
                if Available(ply) and type(ply.Notify) == "function" and not ply:HasWeapon(CLASS) then return true end
            end
            return false, "No eligible informant at round activation"
        end
        return true
    end,
    Start = function(ctx)
        ctx.generation = M.generation % 4294967296
        ctx.data.hint = hint:GetInt()
        ctx.data.callKind = ctx.data.hint == 2 and 0 or ctx.data.hint
        ctx.data.callNumber = ctx.data.hint == 2 and 0 or 1
        ctx.data.interval = interval:GetFloat()
        ctx.data.rolesSeen, ctx.data.innocentsSeen, ctx.data.roleCount = {}, {}, 0
        if ctx.data.hint == 2 then
            ctx.data.recipient = M:SelectSpecialRole(ctx, "informant")
        end
        ctx:Cleanup(function() ClearWaypoint(ctx) end)
        ctx.data.phase, ctx.data.due = "waiting", CurTime() + (ctx.data.hint == 2 and ctx.data.interval or delay:GetFloat())
        ctx.data.ringTime, ctx.data.callTime = ringTime:GetFloat(), callTime:GetFloat()
        ctx:Cleanup(function() RemovePhone(ctx.data.phone) end)
        ctx:Timer("phone", 0.1, 0, Tick)
        ctx:Hook("PlayerCanPickupWeapon", "phone_owner", function(c, ply, wep)
            if wep == c.data.phone and ply ~= c.data.recipient then return false end
        end)
        ctx:Hook("HG_OnOtrub", "phone_unconscious", function(c, ply)
            if ply == c.data.recipient and IsValid(c.data.phone) then Finish(c, "unconscious") end
        end)
    end,
    PlayerDeath = InformantDeath,
    PlayerDisconnected = function(ctx, ply) if ply == ctx.data.recipient then Finish(ctx, "recipient disconnected", true) end end,
    PlayerSpawn = function(ctx, ply) if ply == ctx.data.recipient then Finish(ctx, "recipient respawned", true) end end
})
concommand.Add("zc_mutator_informant_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() and not ply:IsSuperAdmin() then return end
    local ctx = M.current
    local msg = "[zc_mutators] Informant: inactive"
    if ctx and ctx.definition.ID == "informant" then
        local d = ctx.data
        msg = "[zc_mutators] Informant: " .. (d.finished and d.outcome or d.phase)
        if (d.phase == "waiting" or d.phase == "between_calls") and not d.finished then msg = msg .. " (call in " .. math.ceil(math.max(0, d.due - CurTime())) .. "s)" end
    end
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)

M:RegisterSpecialRole({
    ID = "informant", Mutator = "informant", Title = "Informant",
    Eligible = function(ply)
        return hint:GetInt() == 2 and Available(ply) and type(ply.Notify) == "function" and not ply:HasWeapon(CLASS)
    end
})


-- A temporary bot-only visual preview; never assigns a gameplay role or sends clues.
local PREVIEW = "zc_mutators_phone_preview"
local previewEvents = {"PlayerDeath", "PlayerDisconnected", "PlayerSpawn"}
function M:StopPhonePreview()
    local d = self.phonePreview
    self.phonePreview = nil
    timer.Remove(PREVIEW)
    hook.Remove("StartCommand", PREVIEW)
    for _, event in ipairs(previewEvents) do hook.Remove(event, PREVIEW) end
    if not d then return end
    local wep = d.phone or (d.pending and IsValid(d.ply) and d.ply:GetWeapon(CLASS))
    local restore = IsValid(d.ply) and d.ply:GetActiveWeapon() == wep
    RemovePhone(wep)
    if restore and IsValid(d.previous) and d.previous:GetOwner() == d.ply then d.ply:SelectWeapon(d.previous:GetClass()) end
end
function M:StartPhonePreview(ply)
    if self.phonePreview then return false, "A preview is already running. Use zc_mutator_phone_preview stop first." end
    if not IsValid(ply) or not ply:IsBot() or not ply:Alive() or ply:Team() == TEAM_SPECTATOR then return false, "Choose a living, participating bot." end
    if ply:InVehicle() or IsValid(ply.FakeRagdoll) or (ply.organism and ply.organism.otrub) then return false, "Bot must be standing and conscious." end
    if ply:HasWeapon(CLASS) then return false, "That bot already has a phone; its existing call is unchanged." end
    if not weapons.GetStored(CLASS) or not file.Exists(MODEL, "GAME") then return false, "Phone weapon/model unavailable." end
    local d = {ply = ply, previous = ply:GetActiveWeapon(), pending = true, started = CurTime(),
        stamp = zb and zb.ROUND_START, state = zb and zb.ROUND_STATE}
    self.phonePreview = d
    local ok, err = xpcall(function()
        local wep = ply:Give(CLASS, true)
        d.phone, d.pending = wep, false
        if not IsValid(wep) or wep:GetOwner() ~= ply then error("Preview phone grant failed") end
        wep:SetCallPhase(0); wep:SetPhaseStart(CurTime())
        ply:SelectWeapon(CLASS)
        hook.Add("StartCommand", PREVIEW, function(target, cmd)
            if self.phonePreview ~= d or target ~= ply or not IsValid(wep) then return end
            cmd:ClearButtons(); cmd:ClearMovement(); cmd:SelectWeapon(wep)
        end)
        for _, event in ipairs(previewEvents) do
            hook.Add(event, PREVIEW, function(target) if target == ply and self.phonePreview == d then self:StopPhonePreview() end end)
        end
        timer.Create(PREVIEW, 0.1, 0, function()
            if self.phonePreview ~= d then return end
            if not IsValid(ply) or not ply:Alive() or ply:Team() == TEAM_SPECTATOR or not IsValid(wep)
                or wep:GetOwner() ~= ply or IsValid(ply.FakeRagdoll) or ply:InVehicle() or (ply.organism and ply.organism.otrub)
                or (zb and zb.ROUND_START) ~= d.stamp or (zb and zb.ROUND_STATE) ~= d.state then self:StopPhonePreview(); return end
            local elapsed = CurTime() - d.started
            if elapsed >= 13.7 then self:StopPhonePreview(); return end
            local phase = elapsed >= 13.1 and 3 or elapsed >= 3.1 and 2 or elapsed >= 2.5 and 1 or 0
            if phase ~= wep:GetCallPhase() then
                wep:StopRing(); wep:SetCallPhase(phase); wep:SetPhaseStart(CurTime())
            end
            if phase == 0 and elapsed >= 0.3 and not d.rang then wep:PlayRing(); d.rang = true end
        end)
    end, debug.traceback)
    if not ok then self:StopPhonePreview(); self:Log(tostring(err)); return false, "Preview failed; temporary phone cleaned up." end
    return true, "Preview: ring, raise to ear, hold for ten seconds, lower, remove. No role assignment."
end
concommand.Add("zc_mutator_phone_preview", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() and not ply:IsSuperAdmin() then return end
    local function reply(msg)
        msg = "[zc_mutators] " .. msg
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
    if args[1] == "stop" then M:StopPhonePreview(); reply("Phone preview stopped."); return end
    local target
    for _, bot in ipairs(player.GetAll()) do
        if bot:IsBot() and bot:Nick() == args[1] then
            if target then reply("More than one bot has that exact name; give them distinct names first."); return end
            target = bot
        end
    end
    if not target then reply('Use zc_mutator_phone_preview "exact bot name" (for example Bot1).'); return end
    local _, message = M:StartPhonePreview(target)
    reply(message)
end)
