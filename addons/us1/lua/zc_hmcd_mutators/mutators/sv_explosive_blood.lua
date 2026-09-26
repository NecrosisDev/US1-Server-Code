-- Native gas-can Fire presentation and initial blast, without its global coroutine,
-- persistent VFire spread, door destruction or shrapnel. No base ZCity detours.
local M = ZC_HMCD_MUTATORS
local ID, MODEL = "explosive_blood", "models/props_junk/gascan001a.mdl"
local RADIUS, COOLDOWN, PER_TICK = 300, 2, 8
local START_GRACE = 10
local BLAST_SCALE = 0.5 -- blast radius only; peak damage and anti-chain radius stay unchanged

local function Requirements()
    local spec = hg and hg.expItems and hg.expItems[MODEL]
    if not spec or spec.ExpType ~= "Fire" or not M.Finite(spec.Force) or spec.Force <= 0 then
        return false, "Requires ZCity's native gas-can Fire definition"
    end
    if type(hg.ExplosionEffect) ~= "function" or not util.IsValidModel(MODEL)
        or util.NetworkStringToID("zc_explosive_blood_fx") == 0 then
        return false, "Requires mounted gas-can model and Explosive Blood half-size effect loader"
    end
    return true
end
local function Position(pos)
    if not isvector(pos) or not M.Finite(pos.x) or not M.Finite(pos.y) or not M.Finite(pos.z) then return end
    return Vector(pos.x, pos.y, pos.z)
end
local function RemoveZone(ctx, zone)
    for i = #ctx.data.zones, 1, -1 do
        if ctx.data.zones[i] == zone then table.remove(ctx.data.zones, i); return end
    end
end
local function Blocked(ctx, pos, except)
    local blocked = false
    for i = #ctx.data.zones, 1, -1 do
        local zone = ctx.data.zones[i]
        if not zone.pending and CurTime() >= zone.expires then
            table.remove(ctx.data.zones, i)
        elseif pos and zone ~= except then
            local dx, dy, dz = pos.x - zone.pos.x, pos.y - zone.pos.y, pos.z - zone.pos.z
            if dx * dx + dy * dy + dz * dz <= RADIUS * RADIUS then blocked = true end
        end
    end
    return blocked
end
local function Enroll(ctx, p)
    if not IsValid(p) or not p:IsPlayer() or not p:Alive() or p:Team() == TEAM_SPECTATOR then return end
    -- Repeated spawn callbacks for one still-living life must not invalidate a death record.
    if ctx.data.lives[p] and ctx.data.lives[p].armed then return end
    ctx.data.lives[p] = {armed = true, previousBody = p:GetNWEntity("RagdollDeath")}
end
local function RemoveEmitter(ctx)
    local ent = ctx.data.emitter
    ctx.data.emitter = nil
    if IsValid(ent) then ent:Remove() end
end
local function Explode(ctx, pending)
    local p = pending.ply
    if not IsValid(p) or p:Alive() or p:Team() == TEAM_SPECTATOR
        or ctx.data.lives[p] ~= pending.life then return end
    local pos = pending.pos
    local body = p:GetNWEntity("RagdollDeath")
    if IsValid(body) and body ~= pending.life.previousBody and body:IsRagdoll() and body.ply == p then
        pos = Position(body:WorldSpaceCenter()) or pos
    end
    if not pos or Blocked(ctx, pos, pending.zone) then return end
    local ready, reason = Requirements()
    assert(ready, reason)

    -- Publish this blast's local exclusion zone before any damage can cause another death.
    pending.zone.pos, pending.zone.expires, pending.zone.pending = pos, CurTime() + COOLDOWN, false
    local ent = ents.Create("prop_physics")
    assert(IsValid(ent), "Could not create gas-can blast source")
    ctx.data.emitter = ent -- owned immediately, including partially initialized failures
    ent.HasExploded, ent.babahnut, ent.ZCExplosiveBlood = true, true, true
    ent:SetModel(MODEL)
    ent:SetPos(pos)
    ent:SetNoDraw(true)
    ent:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    ent:Spawn()
    local phys = ent:GetPhysicsObject()
    assert(IsValid(phys), "Gas-can blast source has no physics mass")
    local mass = phys:GetMass()
    assert(M.Finite(mass) and mass > 0 and mass <= 100, "Unexpected gas-can model mass")
    phys:EnableMotion(false)
    ent:SetMoveType(MOVETYPE_NONE)
    ent:SetSolid(SOLID_NONE)
    -- Match the downloaded native gas-can initial blast formula, including model mass.
    local force = hg.expItems[MODEL].Force * 2 * math.min(mass / 10, 20)
    assert(M.Finite(force) and force > 0, "Invalid gas-can blast force")
    local radius = ((force / 8) / 0.01905) * BLAST_SCALE
    ctx.data.explosions = ctx.data.explosions + 1

    -- A private half-size copy of the native gas-can particle; same native sound set.
    hg.ExplosionEffect(pos, force / 0.2, 80)
    net.Start("zc_explosive_blood_fx")
    net.WriteVector(pos)
    net.Broadcast()
    util.ScreenShake(pos, 100, 900, 1, 5000)
    -- An involuntary death effect is environmental damage, not another player attack.
    util.BlastDamage(ent, game.GetWorld(), pos, radius, force * 2)
    RemoveEmitter(ctx)
    return true
end
local function OnDeath(ctx, p)
    local life = ctx.data.lives[p]
    if not life or not life.armed or not IsValid(p) or p:Team() == TEAM_SPECTATOR then return end
    life.armed = false -- a suppressed death is consumed, never retried after the cooldown
    ctx.data.deaths = ctx.data.deaths + 1
    -- Consume opening deaths now; never queue them to explode when the grace expires.
    if CurTime() < ctx.data.armedAt then ctx.data.skipped = ctx.data.skipped + 1; return end
    local pos = Position(p:WorldSpaceCenter())
    local fake = p.FakeRagdoll
    if IsValid(fake) and fake:IsRagdoll() and fake.ply == p then pos = Position(fake:WorldSpaceCenter()) or pos end
    if not pos or Blocked(ctx, pos) then ctx.data.skipped = ctx.data.skipped + 1; return end
    -- Reserve the area immediately so simultaneous nearby deaths cannot all get accepted.
    local zone = {pos = pos, expires = CurTime() + COOLDOWN, pending = true}
    ctx.data.zones[#ctx.data.zones + 1] = zone
    ctx.data.pending[#ctx.data.pending + 1] = {ply = p, life = life, pos = pos,
        at = CurTime() + 0.05, zone = zone}

end
M:Register({
    ID = ID, Title = "Explosive Blood",
    Description = "After a 10-second round-start grace period, deaths erupt with a half-size gas-can fireball and half-radius blast. Other deaths within 300 units of an explosion are suppressed for two seconds. Deaths farther away can still explode. Combat karma loss is halved.",
    Types = {standard = true, gunfreezone = true, soe = true, wildwest = true},
    MinPlayers = 2, Weight = 1, MidRound = true, CanStart = Requirements,
    Start = function(ctx)
        local ready, reason = Requirements(); assert(ready, reason)
        ctx.data.armedAt = ctx.stamp + START_GRACE -- anchored to round start, including mid-round activation
        ctx.data.lives = setmetatable({}, {__mode = "k"})
        ctx.data.deaths, ctx.data.explosions, ctx.data.skipped = 0, 0, 0
        ctx.data.zones, ctx.data.pending = {}, {}
        ctx:Cleanup(function() ctx.data.pending = {}; ctx.data.zones = {}; RemoveEmitter(ctx) end)
        for _, p in ipairs(ctx.participants) do Enroll(ctx, p) end
        ctx:Hook("PlayerSilentDeath", "explosive_blood_silent", function(c, p)
            local life = c.data.lives[p]
            if life then life.armed = false; life.silent = true end
        end)
        -- One fixed timer. Process at most eight accepted, spatially separate deaths per tick;
        -- new deaths caused by BlastDamage always wait for a later tick, never recurse.
        ctx:Timer("explosive_blood", 0.05, 0, function(c)
            Blocked(c) -- prune expired zones even during quiet periods
            local count = math.min(#c.data.pending, PER_TICK)
            for i = 1, count do
                if not c:Valid() then return end
                local pending = c.data.pending[1]
                if not pending or CurTime() < pending.at then break end
                table.remove(c.data.pending, 1)
                if pending.life.silent or not Explode(c, pending) then
                    c.data.skipped = c.data.skipped + 1
                    RemoveZone(c, pending.zone)
                end
            end
        end)
    end,
    PlayerDeath = OnDeath,
    PlayerSpawn = Enroll,
    PlayerDisconnected = function(ctx, p) ctx.data.lives[p] = nil end
})
concommand.Add("zc_mutator_explosive_blood_status", function(p)
    if IsValid(p) and not (p:IsAdmin() or p:IsSuperAdmin()) then return end
    local ctx = M.current
    local message = "[Explosive Blood] inactive"
    if ctx and ctx.definition.ID == ID then
        message = string.format("[Explosive Blood] blasts=%d deaths=%d skipped=%d suppression_radius=%d cooldown=%.1fs blast_scale=0.5 visual_scale=0.5 zones=%d pending=%d grace=%.1fs",
            ctx.data.explosions, ctx.data.deaths, ctx.data.skipped, RADIUS, COOLDOWN,
            #ctx.data.zones, #ctx.data.pending, math.max(0, ctx.data.armedAt - CurTime()))
    end
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, message) else print(message) end
end)
