-- US1 addition (not upstream): everything that moves a door without a hand on it.
--
--   props / ragdolls   door PhysicsCollide callback      -> Impact.ApplyKick
--   kicks              native "openawayfrom"/"open"/"close" fired BY a player (sv_mapio) -> Impact.KickFrom
--   damage             EntityTakeDamage on a door        -> Impact.ApplyKick
--   bots               SwingDoors.OpenFor(ent, door)
--
-- A hit becomes hinge angular velocity with an inelastic point-mass model
--     w = m * (r x v).z / (I_door + m * |r|^2),   I_door = M * width^2 / 3
-- and is handed to the normal SwingDoors simulation as an ownerless coasting
-- session, so bounds, latching, portals, sounds and map outputs all behave
-- exactly as they do for a hand-swung door. Locked doors never move.
--
-- This file is hot-reloaded on a live server: state lives on SwingDoors.Impact,
-- never in file locals that an old closure could keep alive.
SwingDoors = SwingDoors or {}
SwingDoors.Impact = SwingDoors.Impact or {}

local Impact = SwingDoors.Impact
local CONFIG = SwingDoors.Config
local CONST = SwingDoors.Const
local DBG = SwingDoors.DBG
local Geometry = SwingDoors.Geometry
local Collision = SwingDoors.Collision
local DoorState = SwingDoors.DoorState
local Portals = SwingDoors.Portals
local Sessions = SwingDoors.Sessions

local VisualOffset = DoorState.VisualOffset
local SetDoorAngle = DoorState.SetDoorAngle
local baseAngles = DoorState.BaseAngles
local CLOSED_DEADZONE = DoorState.CLOSED_DEADZONE

local DOOR_CLASSES = { "prop_door_rotating", "func_door_rotating" }

for _, def in ipairs(SwingDoors.Settings and SwingDoors.Settings.Schema or {}) do
    if def.realm == "sv" and CONFIG[def.key] == nil then
        local cvar = GetConVar(def.cvar)
        CONFIG[def.key] = cvar and SwingDoors.Settings.Sanitize(def, cvar:GetFloat()) or def.default
    end
end
local LOCKED_RATTLE_INTERVAL = 0.6

local SETTING_FALLBACK = { breakStrength = 1, impactStrength = 1, kickSwingSpeed = 240, damageStrength = 1, slamStrength = 1, maxSwingSpeed = 260 }
local function Setting(key)
    return CONFIG[key] or SETTING_FALLBACK[key]
end

Impact.Stats = Impact.Stats or {}
local stats = Impact.Stats
for _, key in ipairs({ "hits", "opened", "added", "locked", "weak", "kicks", "damage", "shoved", "slams", "broken" }) do
    stats[key] = stats[key] or 0
end

Impact.Pending = Impact.Pending or {}

-- Pure so it can be tested offline. Returns degrees/second, +yaw positive.
function Impact.AngularKick(hingePos, hitPos, velocity, mass, doorWidth, doorMass)
    local rx, ry = hitPos.x - hingePos.x, hitPos.y - hingePos.y
    local r2 = rx * rx + ry * ry
    if r2 < 16 then return 0 end

    local cross = rx * velocity.y - ry * velocity.x
    local inertia = doorMass * doorWidth * doorWidth / 3
    return math.deg(mass * cross / (inertia + mass * r2))
end

local function DoorWidth(door)
    local mins, maxs = door:OBBMins(), door:OBBMaxs()
    return math.max(math.abs(mins.x), math.abs(maxs.x), math.abs(mins.y), math.abs(maxs.y), 16)
end

local function HitterMass(ent, physObj)
    if ent:GetClass() == "prop_ragdoll" then
        -- one limb touches the door, but the whole body is behind it
        local cached = ent.SwingDoors_BodyMass
        if not cached then
            cached = 0
            for i = 0, math.min(ent:GetPhysicsObjectCount(), 32) - 1 do
                local bone = ent:GetPhysicsObjectNum(i)
                if IsValid(bone) then cached = cached + bone:GetMass() end
            end
            ent.SwingDoors_BodyMass = cached
        end
        return cached * 0.6
    end
    return physObj:GetMass()
end

-- ---------------------------------------------------------------------------
-- Breaking. One health pool per door, shared with Z-City's kicks (ent.HP).
-- ---------------------------------------------------------------------------
local SLIDING_CLASS = "func_door"

function Impact.IsBreakable(door)
    if not IsValid(door) or door.SwingDoors_Broken or door:GetNoDraw() then return false end
    local class = door:GetClass()
    if class == DOOR_CLASSES[1] or class == DOOR_CLASSES[2] then return true end
    if class ~= SLIDING_CLASS then return false end

    local size = door:OBBMaxs() - door:OBBMins()
    return math.max(size.x, size.y, size.z) <= (CONST.breakSlidingMaxDim or 140)
end

local function EndAnySession(door)
    local owner, s, fromDoorSessions = Sessions.FindActiveSessionForDoor(door)
    if not s then return end
    if fromDoorSessions then Sessions.DoorSessions[door] = nil else Sessions.Sessions[owner] = nil end
    if IsValid(owner) and owner:IsPlayer() then
        net.Start("SwingDoors_ForceRelease")
        net.Send(owner)
    end
    door:StopSound(SwingDoors.Sounds.swing)
    Sessions.FinalizeSession(s)
end

function Impact.BreakDoor(door, velocity, breaker, cause)
    if hook.Run("hg_CanDestroyDoor", door, breaker) == false then return false end

    EndAnySession(door)
    door.SwingDoors_Broken = true
    stats.broken = stats.broken + 1
    cause = "broke_" .. (cause or "other")
    stats[cause] = (stats[cause] or 0) + 1
    stats.lastBreakDamage = door.SwingDoors_LastBreakAmount

    local model = door:GetModel() or ""
    if hgBlastThatDoor and string.sub(model, 1, 1) ~= "*" then
        hgBlastThatDoor(door, velocity) -- Z-City: hides the door, opens its portal, throws a prop of it
        return true
    end

    -- brush doors have no model a prop could take: open the way and leave splinters
    sound.Play("Wood_Crate.Break", door:WorldSpaceCenter(), 70, 95)
    door:Fire("unlock", "", 0)
    door:Fire("open", "", 0)
    door:SetNoDraw(true)
    door:SetNotSolid(true)
    local name = door:GetName()
    if name ~= "" then
        for _, portal in ipairs(ents.FindByClass("func_areaportal")) do
            if portal:GetInternalVariable("target") == name then portal:Fire("Open") end
        end
    end
    return true
end

-- amount is "kick damage" units: Z-City's leg kick deals its melee damage into the same pool.
function Impact.DamageDoor(door, amount, velocity, breaker, cause)
    amount = amount * Setting("breakStrength")
    if amount < (CONST.breakMinDamage or 4) or not Impact.IsBreakable(door) then return false end

    local hard = door:GetMaterialType() == MAT_METAL
    door.SwingDoors_LastBreakAmount = math.floor(amount)
    door.HP = (door.HP or CONST.breakDoorHP or 200) - amount * (hard and 1 or 2)

    if door.HP > 0 then
        if CurTime() >= (door.SwingDoors_NextCrack or 0) then
            door.SwingDoors_NextCrack = CurTime() + 0.35
            door:EmitSound(hard and "physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav"
                or "physics/wood/wood_crate_impact_hard" .. math.random(1, 4) .. ".wav", 75, math.random(90, 105))
        end
        return false
    end
    return Impact.BreakDoor(door, velocity, breaker, cause)
end

function Impact.OnDoorCollide(door, data)
    if data.Speed < CONST.impactMinSpeed then return end
    if Setting("impactStrength") <= 0 or not SwingDoors.Enabled() then return end

    local other, physObj = data.HitEntity, data.HitObject
    if not IsValid(other) or not IsValid(physObj) or other:IsPlayer() then return end
    if not physObj:IsMoveable() then return end
    if not data.TheirOldVelocity or not data.HitPos then return end

    -- Never touch physics inside the callback: queue, resolve next Think.
    local mass = math.min(HitterMass(other, physObj), CONST.impactMaxMass)
    local momentum = mass * data.Speed
    local queued = Impact.Pending[door]
    if queued and queued.momentum >= momentum then return end

    Impact.Pending[door] = {
        hitPos = data.HitPos,
        velocity = data.TheirOldVelocity,
        mass = mass,
        momentum = momentum,
        other = other,
    }
end

function Impact.Register(door)
    if not IsValid(door) then return end
    local class = door:GetClass()
    if class ~= DOOR_CLASSES[1] and class ~= DOOR_CLASSES[2] and class ~= SLIDING_CLASS then return end

    -- a hot reload leaves the previous file's closure on the door; replace it
    if door.SwingDoors_ImpactCallback then
        door:RemoveCallback("PhysicsCollide", door.SwingDoors_ImpactCallback)
    end
    door.SwingDoors_ImpactCallback = door:AddCallback("PhysicsCollide", function(ent, data)
        return Impact.OnDoorCollide(ent, data)
    end)
end

local function StartImpactSession(door, base, lo, hi, offset, kick)
    local prevMoveType = DoorState.FreezeNativeMotion(door)
    SetDoorAngle(door, Angle(base.p, base.y + VisualOffset(offset), base.r))

    -- The door "holds itself": every upstream IsValid(HeldBy) guard keeps working,
    -- and a player grab takes the session over through the normal coasting path.
    door.SwingDoors_HeldBy = door
    door.SwingDoors_ControlUntil = 0

    Portals.PreOpenPortal(door)

    Sessions.DoorSessions[door] = {
        door = door,
        base = base,
        offset = offset,
        angVel = kick,
        prevMoveType = prevMoveType,
        lo = lo,
        hi = hi,
        nextSwoosh = 0,
        ignoreStatics = Collision.ComputeStructuralIgnoreSet(door, base, lo, hi),
        everOpened = math.abs(offset) > 2,
        lastReportedOpen = math.abs(offset) > CLOSED_DEADZONE,
        closeSoundPlayed = math.abs(offset) <= 0.5,
        stopSoundPlayed = (offset <= lo + 0.5) or (offset >= hi - 0.5),
        fullyOpenFired = Sessions.IsAtOpenLimit(offset, lo, hi),
        openSoundPending = math.abs(offset) <= 2,
        openSoundPlayed = false,
        coasting = true,
        reverseLockUntil = 0,
        ownerless = true,
        mode = "drag",
        target = 0,
        blockedOpening = false,
        blockedClosing = false,
    }
end

-- The one door-moving entry point. kick is deg/s, +yaw positive.
-- opts.latchBreak: deg/s a CLOSED door needs before it pops (default CONST.impactLatchBreak; 0 = always).
-- Returns "opened" | "added" | "locked" | "limit" | "weak" | "busy".
function Impact.ApplyKick(door, kick, opts)
    if not Geometry.IsSwingable(door, "Impact") then return "busy" end

    DoorState.RememberBaseAngle(door)
    local base = baseAngles[door]
    if not base then return "busy" end

    local maxSpeed = Setting("maxSwingSpeed")
    kick = math.Clamp(kick, -maxSpeed, maxSpeed)

    local _, existing = Sessions.FindActiveSessionForDoor(door)
    local lo, hi = Geometry.GetDoorMotionBounds(door)
    local offset = existing and existing.offset or DoorState.GetCurrentOffset(door, base, lo, hi)
    local closed = math.abs(offset) <= CLOSED_DEADZONE

    local latchBreak = opts and opts.latchBreak or CONST.impactLatchBreak
    if math.abs(kick) < (closed and latchBreak or CONST.impactAjarMin) then
        stats.weak = stats.weak + 1
        return "weak"
    end

    if Geometry.IsLatched(door) then
        stats.locked = stats.locked + 1
        if CurTime() >= (door.SwingDoors_NextLockedRattle or 0) then
            door.SwingDoors_NextLockedRattle = CurTime() + LOCKED_RATTLE_INTERVAL
            SwingDoors.PlayDoorStinger(door, "stop", math.abs(kick))
        end
        return "locked"
    end

    if (kick > 0 and offset >= hi) or (kick < 0 and offset <= lo) then return "limit" end

    if existing then
        if CurTime() < existing.reverseLockUntil then return "busy" end
        existing.angVel = math.Clamp(existing.angVel + kick, -maxSpeed, maxSpeed)
        stats.added = stats.added + 1
        return "added"
    end

    if IsValid(door.SwingDoors_HeldBy) then return "busy" end

    local nativeState = door:GetInternalVariable("m_eDoorState")
    if nativeState == 1 or nativeState == 3 then return "busy" end

    StartImpactSession(door, base, lo, hi, offset, kick)
    stats.opened = stats.opened + 1
    return "opened"
end

-- Push the leaf directly away from a point at a chosen swing speed (kicks, bots).
function Impact.KickFrom(door, fromPos, swingSpeed, opts)
    local centre = door:WorldSpaceCenter()
    local dir = centre - fromPos
    dir.z = 0
    if dir:LengthSqr() < 1 then return "weak" end
    dir:Normalize()

    local sign = Impact.AngularKick(door:GetPos(), centre, dir, 1, DoorWidth(door), CONST.impactDoorMass)
    if sign == 0 then return "weak" end
    return Impact.ApplyKick(door, (sign > 0 and 1 or -1) * swingSpeed, opts)
end

local function Resolve(door, hit)
    stats.hits = stats.hits + 1
    local kick = Impact.AngularKick(door:GetPos(), hit.hitPos, hit.velocity, hit.mass,
        DoorWidth(door), CONST.impactDoorMass) * Setting("impactStrength")
    local result = Impact.ApplyKick(door, kick)

    local soaked = (result == "opened" or result == "added") and (CONST.breakSwingAway or 0.35) or 1
    local speed = hit.velocity:Length()
    if speed > 1 then
        Impact.DamageDoor(door, hit.momentum / (CONST.breakImpactDivisor or 600) * soaked,
            hit.velocity * (math.Clamp(speed * 0.5, 100, 600) / speed), hit.other,
            hit.other:GetClass() == "prop_ragdoll" and "body" or "prop")
    end
    DBG("%s hit by %s (mass=%.0f kick=%.0f deg/s) -> %s", tostring(door), tostring(hit.other), hit.mass, kick, result)
end

hook.Add("Think", "SwingDoors_Impact", function()
    if next(Impact.Pending) == nil then return end
    local batch = Impact.Pending
    Impact.Pending = {}
    for door, hit in pairs(batch) do
        if IsValid(door) then Resolve(door, hit) end
    end
end)

-- ---------------------------------------------------------------------------
-- Double doors: the leaves the map links natively (m_hMaster / slavename)
-- ---------------------------------------------------------------------------
function Impact.Partners(door)
    local cached = door.SwingDoors_PartnerList
    if not cached then
        cached = {}
        local master = door:GetInternalVariable("m_hMaster")
        local slaveName = door:GetInternalVariable("slavename")
        if not IsValid(master) then master = nil end
        if not isstring(slaveName) or slaveName == "" then slaveName = nil end

        for _, class in ipairs(DOOR_CLASSES) do
            for _, other in ipairs(ents.FindByClass(class)) do
                if other ~= door then
                    local otherMaster = other:GetInternalVariable("m_hMaster")
                    if other == master or otherMaster == door or (master and otherMaster == master)
                        or (slaveName and other:GetName() == slaveName) then
                        cached[#cached + 1] = other
                    end
                end
            end
        end
        door.SwingDoors_PartnerList = cached
    end
    return cached
end

-- After a tap/full-swing starts on one leaf, send the linked leaves the same way.
function Impact.SwingPartners(ply, door)
    local main = Sessions.DoorSessions[door]
    if not main or main.mode ~= "auto" then return end
    local open = main.target ~= 0

    for _, partner in ipairs(Impact.Partners(door)) do
        if IsValid(partner) and Geometry.IsSwingable(partner, "Partner") and not Geometry.IsLatched(partner) then
            local owner, existing, fromDoorSessions = Sessions.FindActiveSessionForDoor(partner)
            local steered = existing and existing.mode == "drag" and not existing.coasting
            local alreadyGoing = existing and existing.mode == "auto" and (existing.target ~= 0) == open
            if not steered and not alreadyGoing then
                Sessions.StartOrRetargetAutoSession(ply, partner, owner, existing, fromDoorSessions, open)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Kicks. Z-City's leg kick and jump kick fire native inputs with the PLAYER as
-- caller; +use never does that, map logic never does that.
-- Returns true when the kick was fully handled here (native input is swallowed).
-- ---------------------------------------------------------------------------
function Impact.HandleNativeKick(door, kicker)
    local from = SwingDoors.PlayerPos(kicker)
    local result = Impact.KickFrom(door, from, Setting("kickSwingSpeed"), { latchBreak = 0 })
    if result ~= "opened" and result ~= "added" and result ~= "locked" then return false end

    stats.kicks = stats.kicks + 1
    if result == "locked" then SwingDoors.MapIO.Fire(door, "OnLockedUse", kicker) end
    for _, partner in ipairs(Impact.Partners(door)) do
        if IsValid(partner) then Impact.KickFrom(partner, from, Setting("kickSwingSpeed"), { latchBreak = 0 }) end
    end
    return true
end

-- Bots and scripts. Players get a normal auto swing; anything else shoulders the door open.
function SwingDoors.OpenFor(ent, door, open)
    if not IsValid(ent) or not Geometry.IsSwingable(door, "OpenFor") or Geometry.IsLatched(door) then return false end

    if ent:IsPlayer() then
        local owner, existing, fromDoorSessions = Sessions.FindActiveSessionForDoor(door)
        if existing and existing.mode == "drag" and not existing.coasting then return false end
        Sessions.StartOrRetargetAutoSession(ent, door, owner, existing, fromDoorSessions, open ~= false)
        Impact.SwingPartners(ent, door)
        return true
    end

    local result = Impact.KickFrom(door, ent:GetPos(), 160, { latchBreak = 0 })
    return result == "opened" or result == "added"
end

-- ---------------------------------------------------------------------------
-- Damage: bullets only move a door that is already ajar (or a big burst);
-- blasts and melee can pop a closed one.
-- ---------------------------------------------------------------------------
local BULLET_TYPES = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_SNIPER or 0)

hook.Add("EntityTakeDamage", "SwingDoors_DamageNudge", function(door, dmg)
    if not IsValid(door) then return end
    local class = door:GetClass()
    if class ~= DOOR_CLASSES[1] and class ~= DOOR_CLASSES[2] and class ~= SLIDING_CLASS then return end
    if not SwingDoors.Enabled() then return end

    local amount = dmg:GetDamage()
    if amount < 3 then return end

    -- bullets punch through a door rather than wreck it; buckshot is the breaching round; blasts count in full
    local share = dmg:IsDamageType(DMG_BLAST) and 1 or dmg:IsDamageType(DMG_BUCKSHOT) and 0.4
        or dmg:IsDamageType(DMG_BULLET) and 0.15 or 0.3
    local breakAmount, breaker = math.min(amount, 400) * share, dmg:GetAttacker()
    local cause = share == 1 and "blast" or share == 0.4 and "buckshot" or share == 0.15 and "bullet" or "melee"
    local force = dmg:GetDamageForce()
    local throw = force:LengthSqr() > 1 and force:GetNormalized() * 250 or nil
    timer.Simple(0, function()
        if IsValid(door) then Impact.DamageDoor(door, breakAmount, throw, breaker, cause) end
    end)

    if class == SLIDING_CLASS or Setting("damageStrength") <= 0 then return end

    local hitPos = dmg:GetDamagePosition()
    local source = dmg:GetReportedPosition()
    if source:IsZero() then
        local from = IsValid(dmg:GetInflictor()) and dmg:GetInflictor() or dmg:GetAttacker()
        if not IsValid(from) then return end
        source = from:IsPlayer() and SwingDoors.PlayerPos(from) or from:WorldSpaceCenter()
    end
    if hitPos:IsZero() then hitPos = door:WorldSpaceCenter() end

    local dir = hitPos - source
    dir.z = 0
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    -- express the hit as a light, fast point mass carrying damage * damageMomentum of momentum
    local momentum = math.min(amount, 150) * (CONST.damageMomentum or 25) * Setting("damageStrength")
    local kick = Impact.AngularKick(door:GetPos(), hitPos, dir * 100, momentum / 100, DoorWidth(door), CONST.impactDoorMass)
    local isBullet = dmg:IsDamageType(BULLET_TYPES)

    -- resolve outside the damage hook
    timer.Simple(0, function()
        if not IsValid(door) then return end
        local result = Impact.ApplyKick(door, kick, { latchBreak = CONST.impactLatchBreak * (isBullet and (CONST.bulletLatchMult or 3) or 1) })
        if result == "opened" or result == "added" then stats.damage = stats.damage + 1 end
    end)
end)

-- ---------------------------------------------------------------------------
-- A moving leaf shoves ragdolls out of its arc, and their weight brakes it.
-- Called from SimulateSessionTick after the leaf has moved.
-- ---------------------------------------------------------------------------
local RAGDOLL_PAD = 6

function Impact.ShoveRagdolls(s, nearby, dt)
    local w = s.angVel
    if math.abs(w) < 8 then return end

    local door = s.door
    local mins, maxs = door:OBBMins(), door:OBBMaxs()
    local hinge = door:GetPos()
    local wr = math.rad(w)
    local touchedMass = 0
    local holder = door.SwingDoors_HeldBy
    local ownBody = (not s.coasting and IsValid(holder) and holder:IsPlayer()) and SwingDoors.PlayerBody(holder) or nil

    for _, ent in ipairs(nearby) do
        if IsValid(ent) and ent ~= ownBody and ent:GetClass() == "prop_ragdoll" then
            for i = 0, math.min(ent:GetPhysicsObjectCount(), 24) - 1 do
                local phys = ent:GetPhysicsObjectNum(i)
                if IsValid(phys) then
                    local pos = phys:GetPos()
                    local lp = door:WorldToLocal(pos)
                    if lp.x >= mins.x - RAGDOLL_PAD and lp.x <= maxs.x + RAGDOLL_PAD
                        and lp.y >= mins.y - RAGDOLL_PAD and lp.y <= maxs.y + RAGDOLL_PAD
                        and lp.z >= mins.z and lp.z <= maxs.z then
                        -- surface velocity of the leaf at this point: w (z) x r
                        local rx, ry = pos.x - hinge.x, pos.y - hinge.y
                        local surface = Vector(-ry * wr, rx * wr, 0)
                        local speed = surface:Length()
                        if speed > 1 then
                            local dir = surface / speed
                            local cur = phys:GetVelocity()
                            local along = cur:Dot(dir)
                            if along < speed then
                                phys:Wake()
                                phys:SetVelocity(cur + dir * (speed * 1.1 - along))
                            end
                        end
                        touchedMass = touchedMass + phys:GetMass()
                    end
                end
            end
        end
    end

    if touchedMass > 0 then
        s.angVel = math.Approach(s.angVel, 0, touchedMass * (CONST.ragdollDrag or 6) * dt)
        stats.shoved = stats.shoved + 1
    end
end

-- ---------------------------------------------------------------------------
-- A fast leaf hitting a standing player throws them; fast enough, it drops them.
-- Called from SimulateSessionTick's blocked branch, before the bounce.
-- ---------------------------------------------------------------------------
function Impact.SlamPlayer(s, victim, owner)
    if Setting("slamStrength") <= 0 then return end
    if victim == owner and not s.coasting then return end -- you cannot slam yourself with the door in your hand
    if CurTime() < (victim.SwingDoors_NextSlam or 0) then return end

    local hinge = s.door:GetPos()
    local pos = victim:GetPos()
    local rx, ry = pos.x - hinge.x, pos.y - hinge.y
    local wr = math.rad(s.angVel)
    local surface = Vector(-ry * wr, rx * wr, 0)
    local speed = surface:Length() * Setting("slamStrength")
    if speed < (CONST.slamMinSurface or 60) then return end

    victim.SwingDoors_NextSlam = CurTime() + 1.5
    stats.slams = stats.slams + 1

    victim:SetVelocity(surface:GetNormalized() * speed * 1.5 + Vector(0, 0, 40))
    victim:ViewPunch(Angle(-5, 0, 0))

    if speed >= (CONST.slamRagdollSurface or 120) and hg and hg.Fake and not SwingDoors.PlayerBody(victim)
        and CurTime() >= (victim.SwingDoors_NextSlamDrop or 0) then
        victim.SwingDoors_NextSlamDrop = CurTime() + 8
        timer.Simple(0, function()
            if IsValid(victim) and victim:Alive() and not SwingDoors.PlayerBody(victim) then hg.Fake(victim) end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Native input on a door nobody is actively steering: settle our session, step aside.
-- ---------------------------------------------------------------------------
function Impact.YieldToNative(door)
    local owner, s, fromDoorSessions = Sessions.FindActiveSessionForDoor(door)
    if not s or not s.coasting then return false end

    if fromDoorSessions then
        Sessions.DoorSessions[door] = nil
    else
        Sessions.Sessions[owner] = nil
    end
    door:StopSound(SwingDoors.Sounds.swing)
    Sessions.FinalizeSession(s)
    return true
end

hook.Add("OnEntityCreated", "SwingDoors_ImpactRegister", function(ent)
    timer.Simple(0, function() Impact.Register(ent) end)
end)

local function RegisterAll()
    for _, class in ipairs({ DOOR_CLASSES[1], DOOR_CLASSES[2], SLIDING_CLASS }) do
        for _, door in ipairs(ents.FindByClass(class)) do Impact.Register(door) end
    end
end

hook.Add("InitPostEntity", "SwingDoors_ImpactRegisterExisting", function()
    timer.Simple(0.5, RegisterAll)
end)
RegisterAll()

cvars.RemoveChangeCallback("swingdoors_sv_enabled", "SwingDoors_ImpactDisable")
cvars.AddChangeCallback("swingdoors_sv_enabled", function(_, _, new)
    if tobool(new) then
        -- RememberBaseAngle is gated on the switch, so a map that booted with it off knows no doors yet
        timer.Simple(0, function()
            if not SwingDoors.Enabled() then return end
            for _, class in ipairs(DOOR_CLASSES) do
                for _, door in ipairs(ents.FindByClass(class)) do DoorState.RememberBaseAngle(door) end
            end
        end)
        return
    end

    -- Switching off lets every live session coast to rest and hand back to native.
    for ply, s in pairs(Sessions.Sessions) do
        s.coasting = true
        if IsValid(ply) then
            net.Start("SwingDoors_ForceRelease")
            net.Send(ply)
        end
    end
    for _, s in pairs(Sessions.DoorSessions) do s.coasting = true end
end, "SwingDoors_ImpactDisable")

-- ---------------------------------------------------------------------------
-- Cost meter: wraps the two upstream hot paths once. swingdoors_sv_perf prints ms per minute.
-- ---------------------------------------------------------------------------
Impact.Perf = Impact.Perf or { since = SysTime(), scan = 0, sim = 0, ticks = 0 }
local perf = Impact.Perf

-- Stable shims: a later hot reload of an upstream file re-assigns the raw function,
-- Impact.WrapHotPaths() (run again on every load of this file and by the command) re-wraps it.
function Impact.WrapHotPaths()
    local BodyPush = SwingDoors.BodyPush
    Impact.ScanShim = Impact.ScanShim or function()
        local t = SysTime()
        Impact.RawScan()
        perf.scan = perf.scan + (SysTime() - t)
    end
    if BodyPush.ScanForBodyPushes ~= Impact.ScanShim then
        Impact.RawScan = BodyPush.ScanForBodyPushes
        BodyPush.ScanForBodyPushes = Impact.ScanShim
    end

    Impact.SimulateShim = Impact.SimulateShim or function(...)
        local t = SysTime()
        local done = Impact.RawSimulate(...)
        perf.sim = perf.sim + (SysTime() - t)
        perf.ticks = perf.ticks + 1
        return done
    end
    if Sessions.SimulateSessionTick ~= Impact.SimulateShim then
        Impact.RawSimulate = Sessions.SimulateSessionTick
        Sessions.SimulateSessionTick = Impact.SimulateShim
    end
end
Impact.WrapHotPaths()

concommand.Add("swingdoors_sv_perf", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    Impact.WrapHotPaths()
    local minutes = math.max((SysTime() - perf.since) / 60, 1 / 60)
    SwingDoors.PrintTo(ply, string.format("[SwingDoors] over %.1f min: body-push scan %.2f ms/min, session sim %.2f ms/min (%d session-ticks)",
        minutes, perf.scan * 1000 / minutes, perf.sim * 1000 / minutes, perf.ticks))
    perf.since, perf.scan, perf.sim, perf.ticks = SysTime(), 0, 0, 0
end, nil, "Admin: print swing-door impact CPU cost since the last call.")

concommand.Add("swingdoors_sv_impact_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    SwingDoors.PrintTo(ply, string.format("[SwingDoors] hits=%d opened=%d added=%d locked=%d weak=%d kicks=%d damage=%d shoved=%d slams=%d broken=%d",
        stats.hits, stats.opened, stats.added, stats.locked, stats.weak, stats.kicks, stats.damage, stats.shoved, stats.slams, stats.broken))
end, nil, "Admin: print swing-door impact counters.")
