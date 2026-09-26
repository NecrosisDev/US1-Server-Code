-- Fear Events context menu: right-click a player -> "Fear Event" ->
-- pick a horror to inflict. Admin/superadmin only. Works best during
-- fear rounds; the self-contained events work anywhere.
--
-- Downed players are valid targets. The context menu acts on whatever is under
-- the crosshair, and a downed player is a prop_ragdoll, so every entry point
-- resolves that body back to its owner before doing anything.

local EVENTS = {
    { id = 1, label = "Jumpscare" },
    { id = 2, label = "Scary Black Guy" },
    { id = 3, label = "Charple Sprint" },
    { id = 4, label = "Floor Take" },
    { id = 5, label = "Whisper" },
    { id = 6, label = "Prop fling" },
    { id = 7, label = "Player ragdoll fling" },
    { id = 8, label = "The Stalker (toggle, lasts the round)" },
}

-- Rate-limit the two physical actions per admin; client requests still require
-- the existing server-side admin/living-player Filter below.
local nextPhysicalEvent = setmetatable({}, {__mode = "k"})

local WHISPERS = {
    "It knows where you are.",
    "Don't turn around.",
    "You are being watched.",
    "It remembers you.",
    "You've been marked.",
    "It is standing very still.",
    "Something followed you here.",
}

-- Ragdoll -> player. Mirrors ResolvePlayer in sh_zc_snatchlite.lua; kept local
-- so each autorun file stays independently hot-reloadable. hg.RagdollOwner is
-- defined in both realms (homigrad/fake/sv_tier_0.lua, cl_fake.lua) but reads
-- different fields, so the fallbacks below cover a client that has the
-- networked value but not the server's Lua field.
local function ResolveVictim(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end
    if ent:GetClass() ~= "prop_ragdoll" then return nil end

    if hg and isfunction(hg.RagdollOwner) then
        local hgOwner = hg.RagdollOwner(ent)
        if IsValid(hgOwner) and hgOwner:IsPlayer() then return hgOwner end
    end

    local owner = ent.ply
    if IsValid(owner) and owner:IsPlayer() then return owner end

    owner = ent:GetNWEntity("ply", NULL)
    if IsValid(owner) and owner:IsPlayer() then return owner end

    -- Filter runs in both realms, so nothing here may assume a server-only
    -- method exists: an error thrown here would take the whole context menu
    -- down, not just this entry.
    for _, p in player.Iterator() do
        if p.FakeRagdoll == ent then return p end
        if p:GetNWEntity("FakeRagdoll", NULL) == ent then return p end
        if isfunction(p.GetRagdollEntity) and p:GetRagdollEntity() == ent then return p end
    end

    return nil
end

-- Where the player physically is right now: their fake ragdoll while downed,
-- otherwise themselves. MODE:FloorTake / FlingPlayer / PropStrike already
-- resolve this internally, so only the self-contained events need it.
local function BodyOf(ply)
    if not IsValid(ply) then return ply end

    if hg and isfunction(hg.GetCurrentCharacter) then
        local body = hg.GetCurrentCharacter(ply)
        if IsValid(body) then return body end
    end

    if IsValid(ply.FakeRagdoll) then return ply.FakeRagdoll end

    local nw = ply:GetNWEntity("FakeRagdoll", NULL)
    if IsValid(nw) then return nw end

    return ply
end

-- Players, their bodies and loose ragdolls must never veto a lane: a crowded
-- room is exactly where a scare is wanted. Everything else still blocks.
local function LaneFilter(victim, body)
    return function(e)
        if e == victim or e == body then return false end
        if e:IsPlayer() then return false end
        if e:GetClass() == "prop_ragdoll" then return false end
        return true
    end
end

-- Eye-height origin for the self-contained scares. Valid for someone standing
-- and for a body lying on the floor, where EyePos is meaningless.
local function ScareOrigin(victim, body)
    if body == victim then return victim:EyePos() end

    local center = body:WorldSpaceCenter()
    local down = util.TraceLine({
        start = center, endpos = center - vector_up * 128,
        filter = LaneFilter(victim, body),
    })

    return (down.Hit and down.HitPos or body:GetPos()) + vector_up * 44
end

-- Lane search for the charple sprint. The old version drew 8 purely random
-- yaws and discarded anything under 450u, so one unlucky roll or a mid-sized
-- room produced "No open lane near them". Now the sweep is evenly spaced with
-- a random phase so it covers the circle instead of clustering, players and
-- ragdolls do not block it, the wall pull-back scales with the room available,
-- and the longest lane found is kept as a fallback instead of the whole
-- attempt failing.
local LANE_TRIES = 24
local LANE_IDEAL = 450 -- stop looking once a lane is at least this long
local LANE_MIN = 140 -- below this a sprint reads as a teleport, not a charge
local LANE_REACH = 900

local function FindLane(victim, body, origin)
    local filter = LaneFilter(victim, body)
    local best, bestYaw, bestDist
    local phase = math.random() * 360

    for i = 0, LANE_TRIES - 1 do
        local yaw = (phase + i * (360 / LANE_TRIES)) % 360
        local dir = Angle(0, yaw, 0):Forward()
        local lane = util.TraceHull({
            start = origin, endpos = origin + dir * LANE_REACH,
            filter = filter, mins = Vector(-20, -20, 0), maxs = Vector(20, 20, 40),
        })

        local reach = lane.HitPos:Distance(origin)
        if not lane.StartSolid and reach >= LANE_MIN then
            -- Clear the wall we just hit without stepping back past the target.
            local mouth = lane.HitPos - dir * math.Clamp(reach * 0.25, 32, 72)
            local floor = util.TraceLine({
                start = mouth + vector_up * 24,
                endpos = mouth - vector_up * 900,
                filter = filter,
            })

            if floor.Hit and not floor.StartSolid then
                local spawn = floor.HitPos + vector_up * 2
                local room = util.TraceHull({
                    start = spawn + vector_up * 4, endpos = spawn + vector_up * 4,
                    filter = filter, mins = Vector(-16, -16, 0), maxs = Vector(16, 16, 68),
                })

                if not room.StartSolid then
                    local dist = spawn:Distance(origin)
                    if not bestDist or dist > bestDist then
                        best, bestYaw, bestDist = spawn, yaw, dist
                    end
                    if dist >= LANE_IDEAL then break end
                end
            end
        end
    end

    return best, bestYaw
end

-- The Stalker: a silent figure only the target can see. It walks after them and
-- always faces them, holding at a distance to stare. Let it get close -- or walk
-- up to it -- and it is simply gone, stepping back into view somewhere else a
-- few moments later. Runs until the round ends.
--
-- It is ent_zc_anim wearing models/stalker.mdl, not a live npc_stalker: the
-- per-player visibility this needs (SetWhiteListToSee + the CanSeeUserID netvar,
-- the same pair sv_scary_black_guy.lua and sv_fear.lua use) is implemented only
-- for ent_zc_anim, a real NPC would be visible to everyone and would attack, and
-- US1 has no navmesh on its votable maps for one to path with.
local STALK_MODEL = "models/stalker.mdl"
local STALK_STARE = 260 -- closes to here, then holds and stares
local STALK_VANISH = 90 -- "a few feet": it blinks out inside this
local STALK_BACK_MIN, STALK_BACK_MAX = 6, 11 -- seconds spent gone
local STALK_NEAR, STALK_FAR = 480, 1200 -- how far away it steps back into view
-- Units/sec, a walk. A homing LerpVector (what MODE:FlingPlayer's cousin in
-- Trauma's sv_fear_stalker.lua uses for its kill charge) crosses 800u in half a
-- second, which reads as a lunge; this is meant to be outpaceable.
local STALK_SPEED = 130

local stalkers = {} -- [player] = { ent, round, backAt, moving }

-- Autorefresh re-runs this file and hands us a fresh, empty stalkers table,
-- which orphans anything the previous copy was driving: it would stand there
-- until the map changed. Nothing else on this server builds an ent_zc_anim with
-- the stalker model, so sweeping them at load is safe and keeps a live edit from
-- littering the map. On a cold boot this finds nothing.
-- The stale Think hook has to go with them: it closes over the PREVIOUS
-- stalkers table, so left alone it keeps respawning a stalker that this copy's
-- ZB_EndRound cleanup can no longer see.
if SERVER then
    hook.Remove("Think", "ZCFE_Stalker")
    for _, old in ipairs(ents.FindByClass("ent_zc_anim")) do
        if old:GetModel() == STALK_MODEL then old:Remove() end
    end
end

-- Behind them first, because being followed reads best from behind, then a
-- sweep so a corridor or a corner still produces somewhere to stand.
local function StalkerSpot(victim, body, origin)
    local filter = LaneFilter(victim, body)
    local yaws = { (victim:EyeAngles().y + 180) % 360 }
    for _ = 1, 8 do yaws[#yaws + 1] = math.random(0, 359) end

    for _, yaw in ipairs(yaws) do
        local dir = Angle(0, yaw, 0):Forward()
        local out = util.TraceHull({
            start = origin, endpos = origin + dir * STALK_FAR,
            filter = filter, mins = Vector(-20, -20, 0), maxs = Vector(20, 20, 40),
        })

        if not out.StartSolid then
            local want = math.min(out.HitPos:Distance(origin) - 48,
                math.random(STALK_NEAR, STALK_FAR))
            if want >= STALK_NEAR * 0.5 then
                local at = origin + dir * want
                local ground = util.TraceLine({
                    start = at + vector_up * 24, endpos = at - vector_up * 900,
                    filter = filter,
                })
                if ground.Hit and not ground.StartSolid then
                    return ground.HitPos + vector_up * 2
                end
            end
        end
    end

    return nil
end

local function StalkerStop(victim)
    local rec = stalkers[victim]
    if not rec then return false end
    if IsValid(rec.ent) then rec.ent:Remove() end
    stalkers[victim] = nil
    if not next(stalkers) then hook.Remove("Think", "ZCFE_Stalker") end
    return true
end

local function StalkerAppear(victim)
    local rec = stalkers[victim]
    if not rec then return end

    local body = BodyOf(victim)
    if not IsValid(body) then body = victim end
    local spot = StalkerSpot(victim, body, ScareOrigin(victim, body))
    if not spot then
        rec.backAt = CurTime() + 2 -- nowhere to stand yet; try again shortly
        return
    end

    local ent = ents.Create("ent_zc_anim")
    if not IsValid(ent) then return end
    ent:SetPos(spot)
    ent:SetModel(STALK_MODEL)
    ent:SetAngles(Angle(0, (body:GetPos() - spot):Angle().yaw, 0))
    ent:Spawn()
    -- Only the target renders it. Note ent_zc_anim:Draw gates on lply:Alive(),
    -- so a dead spectator sees every whitelisted apparition; that is existing
    -- behaviour shared with the other fear scares, not something set here.
    ent:SetWhiteListToSee(true)
    ent:SetNetVar("CanSeeUserID", { [victim:UserID()] = true })
    local idle = ent:LookupSequence("idle01")
    ent:ResetSequence(idle >= 0 and idle or 1)

    rec.ent = ent
    rec.backAt = nil
    rec.moving = false
end

local function StalkerThink()
    for victim, rec in pairs(stalkers) do
        if not IsValid(victim) or not victim:Alive()
            or (zb and zb.ROUND_START) ~= rec.round then
            StalkerStop(victim)
        elseif rec.backAt then
            if CurTime() >= rec.backAt then StalkerAppear(victim) end
        elseif not IsValid(rec.ent) then
            rec.backAt = CurTime() + 1
        else
            local body = BodyOf(victim)
            if not IsValid(body) then body = victim end

            local ent = rec.ent
            local here = body:GetPos()
            local gap = ent:GetPos():Distance(here)

            if gap <= STALK_VANISH then
                ent:Remove()
                rec.ent = nil
                rec.backAt = CurTime() + math.Rand(STALK_BACK_MIN, STALK_BACK_MAX)
            else
                ent:SetAngles(Angle(0, (here - ent:GetPos()):Angle().yaw, 0))

                if gap > STALK_STARE then
                    -- Constant ground speed, stopping on the stare ring rather
                    -- than overshooting into the vanish radius on one tick.
                    local toward = here - ent:GetPos()
                    toward.z = 0
                    local step = ent:GetPos() + toward:GetNormalized()
                        * math.min(STALK_SPEED * FrameTime(), gap - STALK_STARE)
                    local ground = util.TraceLine({
                        start = step + vector_up * 32, endpos = step - vector_up * 200,
                        filter = LaneFilter(victim, body),
                    })
                    ent:SetPos(ground.Hit and (ground.HitPos + vector_up * 2) or step)
                    if not rec.moving then
                        rec.moving = true
                        local walk = ent:LookupSequence("walk_all")
                        ent:ResetSequence(walk >= 0 and walk or 2)
                    end
                elseif rec.moving then
                    rec.moving = false
                    local idle = ent:LookupSequence("idle01")
                    ent:ResetSequence(idle >= 0 and idle or 1)
                end
            end
        end
    end
end

-- Returns true when it started stalking, false when this call stopped it.
-- Re-picking the entry is the only off switch an admin has for a round-long
-- effect, so the menu entry toggles rather than stacking a second stalker.
local function StalkerToggle(victim)
    if StalkerStop(victim) then return false end
    stalkers[victim] = { round = zb and zb.ROUND_START }
    hook.Add("Think", "ZCFE_Stalker", StalkerThink)
    StalkerAppear(victim)
    return true
end

local function StalkerClearAll()
    for victim in pairs(stalkers) do StalkerStop(victim) end
end

for _, ev in ipairs({ "ZB_EndRound", "ZB_PreRoundStart", "PreCleanupMap", "ShutDown" }) do
    hook.Add(ev, "ZCFE_Stalker_Cleanup", StalkerClearAll)
end

hook.Add("PlayerDisconnected", "ZCFE_Stalker_Cleanup", function(ply)
    StalkerStop(ply)
end)

properties.Add("zc_fearevent", {
    MenuLabel = "Fear Event",
    Order = 3120,
    MenuIcon = "icon16/error.png",

    Filter = function(self, ent, ply)
        if not IsValid(ply) or not (ply:IsAdmin() or ply:IsSuperAdmin()) then return false end
        -- Downed players resolve through their prop_ragdoll; a corpse resolves
        -- to a dead player and is still refused, exactly as before.
        local victim = ResolveVictim(ent)
        return IsValid(victim) and victim:Alive()
    end,

    MenuOpen = function(self, option, ent, tr)
        local submenu = option:AddSubMenu()
        for _, ev in ipairs(EVENTS) do
            submenu:AddOption(ev.label, function()
                self:MsgStart()
                    net.WriteEntity(ent)
                    net.WriteUInt(ev.id, 4)
                self:MsgEnd()
            end)
        end
    end,

    Action = function(self, ent) end, -- submenu drives everything

    Receive = function(self, length, ply)
        local ent = net.ReadEntity()
        local id = net.ReadUInt(4)
        if not self:Filter(ent, ply) or not EVENTS[id] then return end

        local victim = ResolveVictim(ent)
        if not IsValid(victim) then return end
        local body = BodyOf(victim)

        local fear = zb and zb.modes and zb.modes["fear"]

        if id == 6 or id == 7 then
            if (nextPhysicalEvent[ply] or 0) > CurTime() then return end
            nextPhysicalEvent[ply] = CurTime() + 1
            local method
            if fear then
                if id == 6 then method = fear.PropStrike else method = fear.FlingPlayer end
            end
            if type(method) ~= "function" then
                ply:ChatPrint("[FearEvent] This event is unavailable; the Fear server update must be loaded.")
                return
            end
            local ok, applied, reason = pcall(method, fear, victim)
            if not ok then
                ErrorNoHalt("[FearEvent] Physical event failed: " .. tostring(applied) .. "\n")
                ply:ChatPrint("[FearEvent] The event failed; check the server console.")
                return
            end
            if applied == false then
                if id == 6 then
                    ply:ChatPrint("[FearEvent] " .. (reason or "No suitable prop or protected target (server core may need updating)."))
                else
                    ply:ChatPrint("[FearEvent] No suitable nearby wall, or the target is unavailable.")
                end
                return
            end
        elseif id == 1 then
            net.Start("fear_jumpscare")
                net.WriteUInt(math.random(2), 2)
            net.Send(victim)
            victim:ViewPunch(Angle(-12, 4, -3))

        elseif id == 2 and fear then
            pcall(function() fear:StartEvent("scary_black_guy", victim) end)

        elseif id == 3 then
            -- standalone charple sprint
            local origin = ScareOrigin(victim, body)
            local sp, sy = FindLane(victim, body, origin)
            if not sp then
                -- One more sweep from a little higher: a body wedged against
                -- geometry starts every hull trace solid at floor height.
                sp, sy = FindLane(victim, body, origin + vector_up * 24)
            end
            if not sp then
                if ply.ChatPrint then ply:ChatPrint("[FearEvent] No open lane near them.") end
                return
            end
            local fig = ents.Create("ent_zc_anim")
            if not IsValid(fig) then return end
            fig:SetPos(sp)
            fig:SetModel("models/humans/charple01.mdl")
            fig:SetAngles(Angle(0, sy + 180, 0))
            fig:Spawn()
            local seq = fig:LookupSequence("run_all")
            fig:ResetSequence(seq >= 0 and seq or 126)
            fig:EmitSound("npc/fast_zombie/gurgle_loop1.wav", 85, 110)
            if body == victim then victim:SetEyeAngles(Angle(5, sy, 0)) end
            local idx = fig:EntIndex()
            hook.Add("Think", "ZCFE_Charple_" .. idx, function()
                if not IsValid(fig) or not IsValid(victim) or not victim:Alive() then
                    hook.Remove("Think", "ZCFE_Charple_" .. idx)
                    if IsValid(fig) then fig:Remove() end
                    return
                end
                -- Chase the body, not the player slot: a downed player's
                -- prop_ragdoll is what is lying there, and it can be dragged
                -- out from under the charple while this runs.
                local chase = BodyOf(victim)
                if not IsValid(chase) then chase = victim end
                local v = chase:GetPos() - fig:GetPos()
                local dist = v:Length()
                if dist < 30 then
                    fig:StopSound("npc/fast_zombie/gurgle_loop1.wav")
                    victim:EmitSound("ambient/wind/wind_hit1.wav", 90, 95)
                    hook.Remove("Think", "ZCFE_Charple_" .. idx)
                    fig:Remove()
                    return
                end
                fig:SetPos(fig:GetPos() + v:GetNormalized() * math.min(1500 * FrameTime(), dist))
                fig:SetAngles(Angle(0, v:Angle().yaw, 0))
                if chase == victim then
                    local l = (fig:GetPos() + vector_up * 50 - victim:EyePos()):Angle()
                    victim:SetEyeAngles(Angle(l.pitch, l.yaw, 0))
                end
            end)

        elseif id == 8 then
            if StalkerToggle(victim) then
                ply:ChatPrint("[FearEvent] " .. victim:Nick() .. " is being stalked for the rest of the round.")
            else
                ply:ChatPrint("[FearEvent] Called the stalker off " .. victim:Nick() .. ".")
            end

        elseif id == 4 and fear and fear.FloorTake then
            fear:FloorTake(victim)

        elseif id == 5 then
            if victim.Notify then victim:Notify(WHISPERS[math.random(#WHISPERS)], 0) end
        end

        print("[FearEvent] " .. ply:Nick() .. " -> " .. (EVENTS[id] and EVENTS[id].label or id) .. " on " .. victim:Nick())
    end,
})
