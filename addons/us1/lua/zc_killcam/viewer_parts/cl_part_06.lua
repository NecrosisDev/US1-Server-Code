return string.sub([========[x    if not file.Exists("sound/" .. path, "GAME") then return end
    local duration = SoundDuration(path)
    if not duration or duration <= 0 or duration > 8 then return end -- no missing assets or long/looping tracks
    return duration
end
function V.RecordedSoundNear(clip, kind, actor, cs)
    if not V.SoundCV:GetBool() then return false end
    for _, row in ipairs(clip.sounds or {}) do
        if V.ValidReplaySound(row) and row[10] == kind and row[2] == actor and math.abs(row[1] - cs) <= 8 and V.ReplaySoundDuration(row[3]) then return true end
    end
    return false
end
function V.ValidReplaySound(row)
    if not istable(row) or #row ~= 10 then return false end
    for i = 1, 10 do
        if i ~= 3 and (type(row[i]) ~= "number" or row[i] ~= row[i] or math.abs(row[i]) > 1e8) then return false end
    end
    return row[2] >= 0 and row[10] >= 1 and row[10] <= 4
end
function V.StopReplaySounds()
    for _, item in ipairs(L and L.sounds or {}) do item.patch:Stop() end
    if L then L.sounds = {} end
end
function V.UpdateReplaySounds(rate, paused)
    if not L then return end
    if paused or not V.SoundCV:GetBool() or (V.UISide and V.UISide()) then return V.StopReplaySounds() end -- a side card is silent
    for i = #(L.sounds or {}), 1, -1 do
        local item = L.sounds[i]
        local pitch = math.Clamp(item.pitch * (0.38 + rate * 0.62), 25, 255)
        item.remaining = item.remaining - RealFrameTime() * pitch / 100
        if item.remaining <= 0 or RealTime() >= item.untilAt then item.patch:Stop() table.remove(L.sounds, i)
        else item.patch:ChangePitch(pitch, 0.05) end
    end
end
function V.PlayRecordedSounds(clip, from, to, ear, rate)
    if not L or not ear or to <= from or not V.SoundCV:GetBool() or (V.UISide and V.UISide()) then return end
    local used = 0
    for _, row in ipairs(clip.sounds or {}) do
        if V.ValidReplaySound(row) and row[1] > from and row[1] <= to then
            local duration = V.ReplaySoundDuration(row[3])
            if duration then
                local o = clip.origin
                local pos = Vector(o[1] + row[4] / 10, o[2] + row[5] / 10, o[3] + row[6] / 10)
                local range = math.Clamp(1200 * 10 ^ ((row[7] - 75) / 40), 200, 6000)
                local volume = math.Clamp(row[9], 0, 1) * math.Clamp(1 - pos:Distance(ear) / range, 0, 1)
                if volume > 0 then
                    local patch = CreateSound(LocalPlayer(), row[3])
                    if patch then
                        L.sounds = L.sounds or {}
                        if #L.sounds >= 16 then L.sounds[1].patch:Stop() table.remove(L.sounds, 1) end
                        local pitch = math.Clamp(row[8] * (0.38 + rate * 0.62), 25, 255)
                        patch:SetSoundLevel(0) patch:PlayEx(volume, pitch)
                        L.sounds[#L.sounds + 1] = {patch=patch, pitch=row[8], remaining=duration, untilAt=RealTime() + 12}
                    end
                end
                used = used + 1
                if used >= 12 then break end -- a seek/hitch must not burst the entire sound track at once
            end
        end
    end
end

local function fireEvents(from, to, rate)
    local clip = L.clip
    local ear = select(1, L.eye and L.eye() or nil)
    V.PlayRecordedSounds(clip, from, to, ear, rate)
    local events = clip.events
    for k = V.EvFrom(clip, from), #events do -- replay_v1 P3: from event 1 for a death clip, as before
        local e = events[k]
        if clip.round and e[1] > to then break end -- a round clip is long and sorted; a death clip is scanned whole, as always
        if e[1] > from and e[1] <= to then
            local actor = clip.actors[e[3]]
            if e[2] == 1 and actor then
                local pos = worldPos(clip, actor, e[1], 56)
                if not V.RecordedSoundNear(clip, 2, e[3], e[1]) then play(fireSound(clip.weaponName[e[7]], actor), pos, ear, rate, true) end
                if pos and not V.UISide() then -- postround_20260925: no replay muzzle light in a side card's live world
                    local light = DynamicLight(4096 + e[3])
                    if light then light.pos, light.r, light.g, light.b, light.brightness, light.size, light.decay, light.dietime = pos, 255, 190, 110, 3, 180, 1800, CurTime() + 0.08 end
                end
                if e[3] == clip.pov then L.kick = 1 end
            elseif e[2] == 2 and clip.actors[e[4]] then
                if e[4] == clip.target then L.hitFlash, L.hitDmg, L.hitGroup = 1, e[5], e[6] end
                if not V.RecordedSoundNear(clip, 3, e[4], e[1]) and not V.RecordedSoundNear(clip, 3, e[3], e[1]) then
                    play(FLESH[math.random(#FLESH)], worldPos(clip, clip.actors[e[4]], e[1], 40), ear, rate, false)
                end
            end
        end
    end
    -- footsteps: one per stride of distance covered
    for i, g in pairs(L.ghosts) do
        if IsValid(g) and g.zcStride and not g:GetNoDraw() then
            local stepAt = math.floor(g.zcStride / 70)
            if g.zcStep and stepAt > g.zcStep and not V.RecordedSoundNear(clip, 1, i, to) then play(STEPS[math.random(#STEPS)], g:GetPos(), ear, rate, false) end
            g.zcStep = stepAt
        end
    end
end

----------------------------------------------------------------- playback
-- A downed attacker sees from the head of their ragdoll, not from a point 64 units above their feet: the gamemode's
-- camera follows the body's "eyes" attachment (hg.eye), and the body is already posed from the recorded bones by the
-- time a frame is drawn. Falls back to the head bone, then to the standing eye, on a body that has neither.
local function ragdollEye(clip)
    local g = L and L.ghosts and L.ghosts[clip.pov or 0]
    local body = IsValid(g) and g.zcRag
    if not IsValid(body) or body:GetNoDraw() then return end -- hidden = it could not be posed at this moment: never look from a stale body
    body:SetupBones()
    local id = body:LookupAttachment("eyes")
    local eyes = id and id > 0 and body:GetAttachment(id)
    if eyes then return eyes.Pos, eyes.Ang end
    local head = body:LookupBone("ValveBiped.Bip01_Head1")
    local m = head and body:GetBoneMatrix(head)
    if m then return m:GetTranslation() end
end

local EYE_MINS, EYE_MAXS = Vector(-2, -2, -2), Vector(2, 2, 2) -- PROVISIONAL(2026-09-21, hg.hullCheck's own box was not read, ratify-by: 2026-10-21)

-- The camera of last resort. No attacker side was captured at all, which the HUD already says - but a replay must
-- never hand the frame back to the SPECTATOR camera, which is pointed wherever the player last left it, usually
-- nowhere near the death. Look at the victim from a fixed quarter view instead: not anyone's eyes, but the right place.
local function vantage(clip, cs)
    local o = clip.origin
    local tx, ty, tz = 0, 0, 64
    local vic = clip.actors[clip.victim or 0]
    if vic and vic.s and #vic.s > 0 then
        local a, b, c = V.StateAt(vic, math.Clamp(cs, vic.s[1][1], vic.s[#vic.s][1]))
        if a then tx, ty, tz = a, b, c end
    end
    local target = Vector(o[1] + tx, o[2] + ty, o[3] + tz + 40)
    local from = target + Vector(-150, -150, 120)
    return from, (target - from):Angle()
end

-- === The killing round ==========================================================================================
-- Owner, 2026-09-22: "if the death was caused by a bullet ... render and center the object, and follow it to the
-- impact spot." Sniper Elite and War Thunder both do the same two things - hold the world still, and TRAVEL with the
-- round instead of cutting to a view of it - so that is what this does.
--
-- The line is never invented. It is the fatal hit's landing point (events [9..11]) paired with the shot that produced
-- it, by the SAME rule the hit lines in the draw pass use: that shooter's latest shot, no older than 30 cs. A clip
-- missing either half - a melee kill, a weapon whose shots are not recorded, a clip cut before [9..11] existed - gets
-- no bullet cam at all rather than a plausible guess. Staff make bans from these.
local bulletOn = CreateClientConVar("zc_killcam_bulletcam", "1", true, false, "Follow the killing round to the impact (0 = off)")
local BULLET_FLY, BULLET_HOLD, BULLET_BLEND = 1.25, 0.8, 0.25 -- real seconds: the flight, the beat held on the impact, the ease in and out
local BULLET_MIN, FATAL_SLACK = 140, 5 -- a point-blank kill has no flight worth travelling; the fatal hit can round a few cs past the death
-- Helpers live on V to stay below LuaJIT's 200-local limit in this viewer scope.
function V.BulletEase(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end
function V.BulletBody(hit, origin, from, impact)
    if V.Penetration and hit.penetration then return V.Penetration.Body(hit,origin,from,impact) end
    local a = hit.body
    if hit.ballistic ~= 1 or not istable(a) or #a ~= 6 then return end
    for i = 1, 6 do
        if type(a[i]) ~= "number" or a[i] ~= a[i] or math.abs(a[i]) > 1e8 then return end
    end
    local first = Vector(origin[1] + a[1] / 10, origin[2] + a[2] / 10, origin[3] + a[3] / 10)
    local last = Vector(origin[1] + a[4] / 10, origin[2] + a[5] / 10, origin[3] + a[6] / 10)
    local delta = last - first
    local length = delta:Length()
    -- The owner can redirect its internal trace. Do not join a bent/reversed corridor to
    -- the incoming flight, or a mismatched impact to another body's endpoints.
    if length < 1 or length > 100 or first:Distance(impact) > 24 then return end
    local dir = (impact - from):GetNormalized()
    if delta:GetNormalized():Dot(dir) < 0.97 then return end
    return {first = first, last = last, span = length}
end
function V.BulletDuration(b)
    return b and b.cinematic and 3.6 or BULLET_FLY + BULLET_HOLD
end
function V.BulletWeight(b)
    if not b or b.done or not b.at then return 0 end
    return V.BulletEase(math.min(b.t, V.BulletDuration(b) - b.t) / BULLET_BLEND)
end
function V.ShotRound(clip)
    -- BOTH ends of the hit are checked. clip.events is not scoped to this pair: K.Cut keeps an event when EITHER side
    -- is a captured actor (sv_clips.lua, `if index[a] or index[b]`), so in a crossfire a third party's hit on the same
    -- victim sits in the same array - and the server re-filters on the attacker for exactly this reason when it counts
    -- damage (sv_life.lua, `e[3] == clip.pov and e[4] == clip.target`). Matching on the victim alone picks up someone
    -- else's round and then pairs it with their shot, which flies a real, self-consistent, WRONG trajectory labelled
    -- as the kill. clip.pov is this instance's killer (sv_life / sv_highlight set it from role "killer").
    local vi, ki = clip.victim, clip.pov or clip.killer
    if not vi or not ki then return end
    local hit, at
    for i, e in ipairs(clip.events) do
        if e[1] > FATAL_SLACK then break end
        if e[2] == 2 and e[3] == ki and e[4] == vi then hit, at = e, i end
    end
    if not hit or not hit[9] or hit.ballistic == 0 then return end
    local shot
    for k = at - 1, math.max(at - 12, 1), -1 do
        local s = clip.events[k]
        if s[2] == 1 and s[3] == hit[3] then
            if s[9] and hit[1] - s[1] <= 30 then shot = s end
            break
        end
    end
    if not shot or shot[1] > hit[1] then return end
    local o = clip.origin
    local from = Vector(o[1] + shot[9] / 10, o[2] + shot[10] / 10, o[3] + shot[11] / 10)
    local rec = Vector(o[1] + hit[9] / 10, o[2] + hit[10] / 10, o[3] + hit[11] / 10)
    local to = V.HitPoint(clip, hit) -- A1: on the body when anchored, else the recorded point
    local span = from:Distance(to)
    if span < 0.1 then return end
    local dir = (to - from):GetNormalized()
    -- Reject a ricochet or wrong rapid-fire pairing instead of presenting a straight flight as fact.
    if shot[12] and shot[13] and Angle(shot[13] / 100, shot[12] / 100, 0):Forward():Dot(dir) < 0.98 then return end
    local side = dir:Cross(Vector(0, 0, 1))
    if side:LengthSqr() < 0.01 then side = dir:Cross(Vector(1, 0, 0)) end -- fired straight up or down: any perpendicular will do
    side:Normalize()
    -- A1r: the recorded wound corridor is checked where it was recorded (the recorded point and flight, as shipped),
    -- then carried onto the anchored point by the same offset, so the bore starts where the tracer ends.
    local body = V.BulletBody(hit, o, from, rec)
    if body and (to - rec):LengthSqr() > 0.0001 then V.ShiftBody(body, to - rec) end
    return {cs = shot[1], t = 0, from = from, to = to, dir = dir, side = side, up = side:Cross(dir):GetNormalized(),
        span = span, shot = shot, hit = hit, body = body}
end

local function killingRound(clip)
    local b = V.ShotRound(clip)
    return b and (b.span >= BULLET_MIN or (b.body and b.body.recorded)) and b or nil
end

-- Travel alongside the round and a little behind it, looking just ahead of it and easing onto the impact point as it
-- arrives. Sniper Elite frames the round as a silhouette against what it is about to hit rather than a dot in the
-- middle of the screen, so the round rides off-centre and the shot is composed around where it lands.
local BULLET_BACK, BULLET_SIDE, BULLET_RISE = 46, 30, 11
local function bulletView(b)
    if not b.at then return end
    if b.cinematic and V.Cinema then return V.Cinema.Camera(b) end
    -- A short flight gets a tighter rig, or the camera would start well behind the muzzle - inside the shooter. The
    -- floor matters as much as the scaling: unclamped, a flight at BULLET_MIN puts the camera ~13 units off the round
    -- and the round fills the screen.
    local near = math.Clamp(b.span / 600, 0.45, 1)
    local rig = b.at - b.dir * (BULLET_BACK * near) + b.side * (BULLET_SIDE * near) + b.up * (BULLET_RISE * near)
    -- Ease to a side-on inspection of the recorded wound corridor on impact.
    local settle = V.BulletEase((b.t - BULLET_FLY + 0.15) / 0.35)
    local focus = b.body and LerpVector(0.5, b.body.first, b.body.last) or b.to
    rig = LerpVector(settle, rig, focus - b.dir * 18 + b.side * 52 + b.up * 16)
    local tr = util.TraceHull({start = b.at, endpos = rig, mins = EYE_MINS, maxs = EYE_MAXS, mask = MASK_SOLID_BRUSHONLY})
    if tr.StartSolid then return end
    if tr.Hit then rig = tr.HitPos end
    local look = LerpVector(settle, LerpVector(math.min((b.p or 0) + 0.3, 1), b.at, b.to), focus)
    if look:DistToSqr(rig) < 1 then return end
    return rig, (look - rig):Angle()
end

-- A bullet's whole flight fits inside one recorded sample, so the clip's own clock cannot show it: the world is HELD
-- at the instant of the shot while the round crosses the recorded line in real time. That is the existing clock
-- stopped, the same way the curtain stops it - not a second slow-motion system.
local CRAWL, CRAWL_AT = 0.7, 0.85 -- the round holds a steady pace for the first CRAWL of the time, covering CRAWL_AT of the way
local function flight(cs)
    if L.bullet == nil then
        -- A highlight is a montage: stopping it dead on every kill in the reel would wreck its pace, so there the round
        -- is flown on the LAST cut only - the one the reel is built to arrive at. A killcam is one death, and gets it.
        local want = bulletOn:GetBool() and (not L.highlight or L.index >= #L.seq.instances)
        L.bullet = (want and killingRound(L.clip)) or false
        if L.bullet and V.Cinema then L.bullet.cinematic = V.Cinema.Eligible(L) end
    end
    local b = L.bullet
    if not b or b.done or cs < b.cs then return false end
    if not bulletOn:GetBool() then b.done, b.at = true, nil return false end
    if L.curtainTo == 1 or L.pending or L.dialog then return b.at ~= nil end
    b.t = b.t + math.min(RealFrameTime(), 0.05) -- a single hitch must not consume the whole reveal
    if b.t >= V.BulletDuration(b) then b.done, b.at = true, nil return false end
    local t = math.min(b.t / BULLET_FLY, 1)
    -- Steady, then a crawl into the target over the last stretch. A plain ease-out spends most of the flight already
    -- arrived, which leaves the camera still easing in while the round lands; the arrival is the moment, not the launch.
    if V.ShotVisual and V.ShotVisual.Active() then b.p = V.ShotVisual.Progress(t)
    elseif t < CRAWL then b.p = t / CRAWL * CRAWL_AT
    else b.p = CRAWL_AT + (1 - CRAWL_AT) * (1 - (1 - (t - CRAWL) / (1 - CRAWL)) ^ 2) end
    b.at = LerpVector(b.p, b.from, b.to)
    b.landed = t >= 1
    b.bodyP = b.landed and V.BulletEase((b.t - BULLET_FLY) / 0.45) or 0
    if b.body and b.body.recorded and V.Penetration then
        b.bodyP = b.landed and V.Penetration.Progress(b) or 0
        -- organs_20260925: the organ boxes are read off the victim ghost on the impact frame, once per bullet
        if b.landed and V.Penetration.Hits then V.Penetration.Hits(L, b) end
    end
    return true
end

local function eyeView(clip, cs)
    local actor = clip.actors[clip.pov or 0]
    if not actor then return vantage(clip, cs) end
    local x, y, z, yaw, pitch, flags, wep, _, eye, ex, ey, ez = V.StateAt(actor, cs)
    if not x then
        -- V.StateAt answers NOTHING outside the actor's recorded rows (cl_analysis.lua, no clamping), and an attacker
        -- whose rows start after the clip does - they arrived late, or their first samples were trimmed - leaves the
        -- opening seconds with no camera. Returning nothing here gave the frame back to the spectator camera, which is
        -- the "killcam loaded in the wrong place" the owner saw. Hold at the nearest end of what WAS recorded instead.
        local rows = actor.s
        if rows and #rows > 0 then
            x, y, z, yaw, pitch, flags, wep, _, eye, ex, ey, ez = V.StateAt(actor, math.Clamp(cs, rows[1][1], rows[#rows][1]))
        end
        if not x then return vantage(clip, cs) end
    end
    local o = clip.origin
    local kick = L and L.kick or 0
    local pos, ang = Vector(o[1] + x + (ex or 0), o[2] + y + (ey or 0), o[3] + z + (ez or eye or 64)), Angle(pitch - kick * 1.6, yaw, 0)
    local body = L and L.ghosts and L.ghosts[clip.pov or 0]
    local onBody = IsValid(body) and body.zcEye and body.zcEyeCs and math.abs(body.zcEyeCs - cs) < 1
    if onBody then pos = Vector(body.zcEye) end -- posed this frame: the visible body's own eye (see pose)
    if ez or onBody then -- hg.eye's hull check, done here because the viewer has the map: pressed against a wall, the eye stays on this side of it
        local tr = util.TraceHull({start = Vector(o[1] + x, o[2] + y, o[3] + z + (eye or 64) - 10), endpos = pos, mins = EYE_MINS, maxs = EYE_MAXS, mask = MASK_SOLID_BRUSHONLY})
        if tr.Hit and not tr.StartSolid then pos = tr.HitPos end
    end
    local alive = V.HasFlag(flags, 1)
    if V.HasFlag(flags, 4) or not alive then
        local headPos, headAng = ragdollEye(clip)
        if headPos then
            -- knocked down but alive, the player still looks where they like (the recorded view angles); the dead look where the head points
            if not alive and headAng then ang = headAng end
            return headPos, ang
        end
    end
    -- Aiming down sights (sample flag 64, SWEP:IsZoom). The gamemode leaves the gun where it is held and moves the camera
    -- onto it: SWEP.ZoomPos from the gun along the aim, then slid along the aim until it is level with the eye
    -- (homigrad_base/cl_camera.lua SWEP:GetZoomPos, the branch without an optic). L.zoom eases in and out in Think.
    local zoom = L and L.zoom or 0
    if zoom > 0 and not V.Unarmed(clip, wep) then
        local w = weaponTable(clip.weaponName[wep])
        if w and isvector(w.ZoomPos) then
            local me = L.ghosts and L.ghosts[clip.pov or 0]
            local _, _, _, _, base = heldTransform(w, pos, ang.p, yaw, IsValid(me) and me.zcMotion or nil, IsValid(me) and me.zcRestNow or nil) -- the sights ride the same bob as the gun
            local aim = Angle(ang.p, yaw, 0)
            local sight = LocalToWorld(w.ZoomPos, angle_zero, base, aim)
            local optic = IsValid(me) and me.zcSight
            if optic then -- a fitted sight: SWEP:GetCameraOverride puts the eye at its offsetView, measured in the sight's own turned frame
                local turned = Angle(aim.p, aim.y, aim.r)
                turned:RotateAroundAxis(turned:Forward(), 90)
                sight = LocalToWorld(Vector(-optic.view[3], -optic.view[1], -optic.view[2]), angle_zero, LocalToWorld(optic.at, angle_zero, base, aim), turned)
            end
            local forward = aim:Forward()
            sight = sight + forward * ((pos - sight):Dot(forward) - 1)
            pos = LerpVector(zoom, pos, sight)
        end
    end
    return pos, ang
end

V.Life.eyeView = eyeView -- replay_v1 P3: first person in the round viewer

-- The replay's one camera chooser. Everything in eyeView answers "where were this player's eyes"; the bullet cam is
-- the one shot that is nobody's eyes, so it is blended over the top - eased in and out over BULLET_BLEND so the cut
-- to the round and the cut back to the killer are moves, not jumps - rather than bolted on as a second camera system.
-- killcam_kinds (2026-09-25, owner: "prop kills and grenade kills that follow the prop/grenade to impact"). The recorder
-- already keeps the thrown object's flight (clip.gibs rows tagged k = "throw" | "prop", sv_recorder K.ObjectRows, 20 Hz,
-- cs from the death, tenths from clip.origin) and labels the killing hit with it (K.LabelOf: "prop:<model>" or the
-- grenade's class). There is no round to fly, so the camera rides behind the object on the clip's own clock - the
-- slow-motion window around the death (SLOW_FROM..SLOW_TO) already slows the last second - frames the victim as it
-- arrives, holds on the impact, then hands back to the killer's eyes. All state on V / L: no new file-scope locals.
V.ObjectCamOn = CreateClientConVar("zc_killcam_objectcam", "1", true, false, "Follow a thrown prop or grenade to the impact on prop and explosive kills (0 = off)")
-- PROVISIONAL(2026-09-25, framing by reasoning from the bullet cam's rig, not seen in game: lead = how long before the
-- impact the ride starts (cs), hold = the beat on the impact (cs), blend = the ease in / out (cs), back / rise / side =
-- the chase offset in units, ratify-by: 2026-10-09)
V.OBJ = {lead = 350, hold = 90, blend = 30, back = 52, rise = 14, side = 10, reach = 160, stale = 50}
function V.ObjectPos(track, clip, cs)
    local f = track.f
    local a, b, t = V.Gore.GibAt(track, math.Clamp(cs, f[1][1], f[#f][1]))
    if not a then return end
    local o = clip.origin
    return Vector(o[1] + Lerp(t, a[2], b[2]) / 10, o[2] + Lerp(t, a[3], b[3]) / 10, o[3] + Lerp(t, a[4], b[4]) / 10)
end
-- The killing hit (same pairing rule as V.ShotRound: this killer on this victim, the last one up to the death) when it
-- was made by an object, and the tracked object that was at the victim when it landed.
function V.ObjectRound(clip)
    local vi, ki = clip.victim, clip.pov or clip.killer
    if not vi or not ki or not istable(clip.gibs) or not (V.Gore and V.Gore.GibAt) then return end
    local hit
    for _, e in ipairs(clip.events) do
        if e[1] > FATAL_SLACK then break end
        if e[2] == 2 and e[3] == ki and e[4] == vi then hit = e end
    end
    if not hit then return end
    local label = clip.weaponName and clip.weaponName[hit[7]]
    if not isstring(label) or not (string.sub(label, 1, 5) == "prop:" or string.sub(label, 1, 4) == "ent_") then return end
    local actor = clip.actors[vi]
    local x, y, z
    if actor then x, y, z = V.StateAt(actor, hit[1]) end -- not `actor and V.StateAt(...)`: `and` keeps only the first return
    if not x then return end
    local o = clip.origin
    local target = Vector(o[1] + x, o[2] + y, o[3] + z + 36)
    -- the label says which object: "prop:<name>" is the prop model's file name without .mdl (sv_recorder K.LabelOf), the
    -- track keeps the full path; a grenade class ("ent_hg_...") comes from a thrown projectile track
    local model = string.sub(label, 1, 5) == "prop:" and string.sub(label, 6) or nil
    -- The clip does not say which thrower's object a track is (K.ObjectRows sends model + kind only), so a guess is never
    -- shown as fact: the object must still be moving (or just gone off) at the hit, and be the only candidate - or at
    -- least twice as close as the next one. Otherwise the kill replays from the killer's eyes as before.
    local best, bestD, nextD
    for _, track in ipairs(clip.gibs) do
        local stem = istable(track) and isstring(track.m) and string.gsub(string.GetFileFromFilename(track.m), "%.mdl$", "")
        local kindOk = istable(track) and (model and stem == model or (not model and track.k == "throw"))
        local f = kindOk and isstring(track.k) and istable(track.f) and track.f
        if f and #f >= 2 and istable(f[1]) and istable(f[#f]) and tonumber(f[1][1]) and tonumber(f[#f][1])
            and f[1][1] < hit[1] and f[#f][1] >= hit[1] - V.OBJ.stale then
            local p = V.ObjectPos(track, clip, math.min(hit[1], f[#f][1]))
            local d = p and p:Distance(target)
            if d and d < V.OBJ.reach then
                if not bestD or d < bestD then best, bestD, nextD = track, d, bestD
                elseif not nextD or d < nextD then nextD = d end
            end
        end
    end
    if not best or (nextD and nextD < bestD * 2) then return end
    return {track = best, from = math.max(best.f[1][1], hit[1] - V.OBJ.lead), hit = hit[1], target = target, label = label}
end
function V.ObjectWeight(ob, cs)
    if not ob then return 0 end
    return V.BulletEase(math.min((cs - ob.from) / V.OBJ.blend, (ob.hit + V.OBJ.hold - cs) / V.OBJ.blend))
end
function V.ObjectView(clip, ob, cs)
    local p = V.ObjectPos(ob.track, clip, cs)
    if not p then return end
    local before = V.ObjectPos(ob.track, clip, cs - 6)
    local dir = before and (p - before) or Vector(0, 0, 0)
    if dir:LengthSqr() < 0.25 then dir = ob.dir or (ob.target - p) end -- at rest, or gone (a grenade that went off): keep the last heading
    dir = dir:GetNormalized()
    ob.dir = dir
    local flat = Vector(dir.x, dir.y, 0)
    if flat:LengthSqr() < 0.01 then flat = Vector(1, 0, 0) end
    flat:Normalize()
    local cam = p - dir * V.OBJ.back + Vector(0, 0, V.OBJ.rise) + flat:Cross(Vector(0, 0, 1)) * V.OBJ.side
    local tr = util.TraceLine({start = p, endpos = cam, mask = MASK_SOLID_BRUSHONLY})
    if tr.Hit then cam = tr.HitPos + tr.HitNormal * 3 end
    -- over the last half second the look slides from the object onto the victim: the impact is framed, not chased
    local near = V.BulletEase((cs - (ob.hit - 50)) / 50)
    local look = LerpVector(near * 0.6, p + dir * 16, ob.target)
    if look:DistToSqr(cam) < 1 then return end
    return cam, (look - cam):Angle()
end
function V.ObjectBlend(clip, cs, pos, ang)
    if not L or V.ObjectCamBroken or not V.ObjectCamOn:GetBool() then return pos, ang end
    if L.objectFor ~= clip then
        L.objectFor = clip
        -- a highlight reel gets it on its last cut only, like the bullet cam
        local want = not L.highlight or (L.seq and L.index >= #L.seq.instances)
        local ok, ob = pcall(V.ObjectRound, clip)
        L.object = want and ok and ob or false
    end
    local ob = L.object
    if not ob then return pos, ang end
    local w = V.ObjectWeight(ob, cs)
    if w <= 0 then return pos, ang end
    local ok, opos, oang = pcall(V.ObjectView, clip, ob, cs)
    if not ok then
        V.ObjectCamBroken = true -- a camera error must never take the replay down: off for the session, said once
        print("[Killcam] object camera disabled: " .. tostring(opos))
        return pos, ang
    end
    if not opos then return pos, ang end
    if not pos then return opos, oang end
    return LerpVector(w, pos, opos), LerpAngle(w, ang, oang)
end

local function eyeOf(clip, cs)
    if L and L.round then return V.Round.Camera(clip, cs) end -- replay_v1 P3: the round viewer's cameras (cl_part_09)
    local pos, ang = eyeView(clip, cs)
    local b = L and L.bullet
    if not b or b.done or not b.at then return V.ObjectBlend(clip, cs, pos, ang) end -- killcam_kinds: prop / grenade kills
    local bpos, bang = bulletView(b)
    if not bpos then return pos, ang end
    if not pos then return bpos, bang end
    local w = V.BulletWeight(b)
    return LerpVector(w, pos, bpos), LerpAngle(w, ang, bang)
end

-- Scene changes (spectating -> replay, hit -> hit, replay -> spectating) all pass through a curtain:
-- fade to black, do the switch while nothing is visible, hold a title card, fade back in.
local function through(hold, fade, switch)
    if L.pending then return end
    if V.UIActive() then -- P3 seam: the panel draws the transition, so the switch happens now
        L.curtain, L.curtainTo, L.card = 0, 0, nil
        switch()
        if L then L.card = nil end
        return
    end
    L.curtainTo, L.curtainTime, L.cardHold, L.pending = 1, fade, hold, switch
end
local function go(index)
    through(index <= #L.seq.instances and 0.7 or 0, 0.15, function() -- P6 2026-09-24: was 1.25 s / 0.25 s
        L.waiting, L.card = false, L.seq.instances[index] and index or nil
        if L.lat and not L.lat.sent then L.lat.sent = true V.LifeLat(L) end -- M1: the next frame is the replay
        load(index)
    end)
end
local function leave()
    if L.leaving then return end
    L.leaving = true
    L.pending = nil
    -- Leaving is a fade, and a fade needs frames to accumulate: `through` only hands the screen back once the curtain
    -- reaches 1. If that never happens the replay is left up with nothing able to end it, so the fade gets a deadline
    -- of its own and stop() is called outright when it passes.
    L.leaveBy = RealTime() + 2
    through(0, 0.2, stop)
end

-- The player's own switch, reachable from the killcam itself as well as Settings > Gameplay. Same convar either way.
local function optOut()
    RunConsoleCommand("zc_killcam_show", "0")
    say("Killcams are off for you. Settings > Gameplay turns them back on (or: zc_killcam_show 1).")
    return leave()
end
local function curtain()
    if L.pending and V.UIActive() then -- P3 seam (review): a curtain queued a frame before the panel claimed the screen
        local switch = L.pending
        L.pending, L.curtain, L.curtainTo = nil, 0, 0
        switch()
        if not L then return false end
        L.card = nil
        return true
    end
    L.curtain = math.Approach(L.curtain or 0, L.curtainTo or 0, RealFrameTime() / (L.curtainTime or 0.25))
    if L.pending and L.curtain >= 1 then
        local switch = L.pending
        L.pending = nil
        switch()
        if not L then return false end
        L.cardUntil = RealTime() + (L.cardHold or 0)
        if L.over then L.curtainTo, L.curtainTime = 0.6, 0.2 end -- the end card sits on a dimmed view of where you are spectating (P6: 0.4 -> 0.2 s)
        -- P6 2026-09-24: a quiet cue as a card or the end card comes up (zc_killcam_ui_sounds 0 turns it off)
        if (L.card or L.over) and V.UISounds:GetBool() and not V.UISide() then surface.PlaySound(L.over and "ui/buttonclickrelease.wav" or "ui/buttonrollover.wav") end
    elseif not L.pending and not L.over and L.curtainTo == 1 and RealTime() >= (L.cardUntil or 0) then
        L.curtainTo, L.curtainTime, L.card = 0, 0.2, nil -- P6: 0.35 -> 0.2 s
    end
    return true
end

-- Presentation seam for GoobOS Afterlife. Camera/input/net ownership stays here.
function V.ObserverState()
    local me = LocalPlayer()
    local recent = V.ObserverLife
    if recent and (not IsValid(me) or me:Alive() or recent.round ~= (zb and zb.ROUND_START) or recent.seq.map ~= game.GetMap()) then
        V.ObserverLife = nil; recent = nil
    end
    return {
        active = L ~= nil, highlight = L and L.highlight == true,
        waiting = L and L.waiting == true, playing = L and not L.waiting and not L.over,
        over = L and L.over == true, index = L and L.index,
        id = recent and recent.id, seq = recent and recent.seq,
        readyAt = recent and recent.readyAt or 0,
        saved = L and L.saved == true,
    }
end

function V.ObserverAction(action, index)
    local state = V.ObserverState()
    local me = LocalPlayer()
    if not IsValid(me) or me:Alive() or state.highlight then return false, "Unavailable during live play or highlights." end
    if deathPending or (L and not L.highlight) then return false, "The killcam has control until its replay ends." end
    if action == "skip" then if L then leave() end return true end
    if not state.seq or not state.id then return false, "No replay is available for this life." end
    local show = GetConVar("zc_killcam_show")
    if not show or not show:GetBool() then return false, "Killcams are disabled in your settings." end
    if RealTime() < state.readyAt then return false, "The replay is still arriving." end
    index = tonumber(index) or 1
    if index ~= math.floor(index) or not state.seq.instances[index] then return false, "This moment is unavailable." end
    if action == "watch" then
        if L and (L.pending or L.dialog) then return false, "Finish the current transition or report first." end
        if not L then
            L = {id=state.id,seq=state.seq,reported={},waiting=true,startAt=RealTime(),wall=RealTime()+60*#state.seq.instances+WALL}
        end
        L.over, L.leaving = nil, nil
        go(index)
        return true
    elseif action == "tactical" then
        stop(true); V.OpenSequence(state.id, state.seq)
        return true
    elseif action == "save" then
        net.Start("zckc_save"); net.SendToServer()
        return true
    elseif action == "report" then
        local inst = state.seq.instances[index]
        if not inst.reportable then return false, "This moment is not eligible for a replay report." end
        if L and IsValid(L.dialog) then return false, "A report is already open." end
        local dialog = V.ReportDialog(state.id, index, inst, function() if L then L.dialog = nil end end)
        if L then L.dialog = dialog end
        return true
    end
    return false, "Unknown replay action."
end

local keys = {}
local function pressed(code)
    if code == V.VoiceKey() then keys[code] = input.IsKeyDown(code) return false end -- postround_20260925: voice first
    local down = input.IsKeyDown(code)
    local edge = down and not keys[code]
    keys[code] = down
    return edge
end

-- P1 (killcam_revitalize, 2026-09-24): tell the server a death sequence it sent did not reach the screen, and why
-- (sv_life.lua zckc_life_drop: 1 respawned before it started, 2 respawned while it played, 3 another map's, 4 replaced
-- by a newer sequence or the highlight). Fields on V, not locals: this file is at the 200-locals line.
function V.LifeDrop(reason, id)
    if util.NetworkStringToID("zckc_life_drop") == 0 then return end
    net.Start("zckc_life_drop") net.WriteUInt(reason, 3) net.WriteString(tostring(id or "")) net.SendToServer()
end
-- A death replay still on its way to the screen or on it: not the highlight, not its end card, not already leaving.
function V.LifeUnfinished(l) return l ~= nil and not l.highlight and not l.over and not l.leaving and not l.round end -- P3: a round is not a death replay
-- M1 (killcam_polish, 2026-09-24): the client's three spans of the death-to-screen wait, for sv_life.lua's
-- zckc_life_lat rows: first->last chunk received, decode, last chunk->the frame the replay takes the screen (that
-- one includes the fade-through). Death sequences only, once per sequence, milliseconds. On V: locals line.
function V.LifeLat(l)
    local lat = l.lat
    if not lat or l.highlight or util.NetworkStringToID("zckc_life_lat") == 0 then return end
    local function ms(s) return math.Clamp(math.floor((s or 0) * 1000 + 0.5), 0, 65535) end
    net.Start("zckc_life_lat") net.WriteString(tostring(l.id or "")) net.WriteUInt(ms(lat.xfer), 16) net.WriteUInt(ms(lat.decode), 16) net.WriteUInt(ms(SysTime() - lat.at), 16) net.SendToServer()
end
-- A1 (killcam_polish, 2026-09-24): where a hit landed ON THE BODY. The server records the landing point in world space
-- from the lag-compensated body (the victim rewound to where the shooter saw them); the replay draws the body where the
-- samples put it, so the two can sit apart by the rewind. e.anchor carries the same point relative to the victim's root
-- (body space) and to the hit bone; this returns it from the ghost on screen. zc_killcam_impact_anchor 0 = the recorded
-- point (as shipped), 1 = body-anchored, 2 = bone-anchored (falls back to 1 when the bone is missing). The print (once
-- per hit) is what the owner reads to decide: recorded vs body vs bone, plus the server's rewind distance and sample age.
-- PROVISIONAL(2026-09-25, default 2 before the owner compared the modes in game; the print below is the check, ratify-by: 2026-10-09)
V.ImpactAnchor = CreateClientConVar("zc_killcam_impact_anchor", "2", true, false, "Replay impacts: 0 recorded point, 1 anchored to the body, 2 anchored to the hit bone")
V.ImpactPrint = CreateClientConVar("zc_killcam_impact_print", "1", true, false, "Print replay diagnostics to the console: impact anchoring, weapon model fallbacks, missing animation sequences")
V.HitBones = {"ValveBiped.Bip01_Head1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine", "ValveBiped.Bip01_L_UpperArm",
    "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh"} -- same list as sv_recorder.lua HIT_BONES
V.ImpactCap = 40 -- A1r: an anchored point further than this from the recorded one is not trusted; the recorded point is drawn
function V.HitPoint(clip, e)
    local o = clip.origin
    local rec = Vector(o[1] + e[9] / 10, o[2] + e[10] / 10, o[3] + e[11] / 10)
    local an = e.anchor
    local g = an and L and L.ghosts and L.ghosts[e[4]]
    if not an or not IsValid(g) then return rec end
    -- A1r (2026-09-25): the body ON SCREEN. A downed actor is drawn as its replay ragdoll (g.zcRag, the rule in
    -- cl_part_01), while the ghost it replaces stays, hidden, where the samples put it: the bone is looked up on the
    -- ragdoll then. A bone offset holds on either body (same skeleton); body space only on a standing one.
    local rag = IsValid(g.zcRag) and not g.zcRag:GetNoDraw() and g.zcRag or nil
    local host = rag or g
    local body, bone
    if an.b and not rag then
        body = LocalToWorld(Vector(an.b[1] / 10, an.b[2] / 10, an.b[3] / 10), angle_zero, g:GetPos(), Angle(0, g:GetAngles().y, 0))
    end
    if an.k and an.l then
        local id = V.HitBones[an.k] and host:LookupBone(V.HitBones[an.k])
        local m = id and host:GetBoneMatrix(id)
        if m then bone = LocalToWorld(Vector(an.l[1] / 10, an.l[2] / 10, an.l[3] / 10), angle_zero, m:GetTranslation(), m:GetAngles()) end
    end
    local db, dn = body and rec:Distance(body), bone and rec:Distance(bone)
    if V.ImpactPrint:GetBool() and not e.zcAnchorSaid then
        e.zcAnchorSaid = true
        MsgN(string.format("[Killcam] impact cs %d hitgroup %s on the %s%s: recorded vs body-anchored %s, vs bone-anchored %s | server: body sat %.1f u from the newest sample (%d ms old)",
            e[1], tostring(e[6]), rag and "ragdoll" or "standing body", an.r and " (hit while down)" or "",
            db and string.format("%.1f u (%.1f in)", db, db * 0.75) or "n/a", dn and string.format("%.1f u (%.1f in)", dn, dn * 0.75) or "n/a",
            (an.rw or 0) / 10, (an.age or 0) * 10))
    end
    if db and db > V.ImpactCap then body = nil end
    if dn and dn > V.ImpactCap then bone = nil end
    local mode = V.ImpactAnchor:GetInt()
    if mode >= 2 then return bone or body or rec end
    if mode == 1 then return body or bone or rec end
    return rec
end
-- A1r: moves a decoded wound corridor (V.BulletBody / V.Penetration.Body) by `d`; the distances along it are unchanged.
function V.ShiftBody(body, d)
    body.first, body.last = body.first + d, body.last + d
    if istable(body.path) then for i, p in ipairs(body.path) do body.path[i] = p + d end end
    if istable(body.v2) and istable(body.v2.events) then
        for _, ev in ipairs(body.v2.events) do if isvector(ev.pos) then ev.pos = ev.pos + d end end
    end
    body.zcShifted = true
end

-- P3 seam (killcam_revitalize, 2026-09-24; contract in work/loader/killcam_revitalize/P3_SEAM.txt). zc_killcam_ui 1
-- hands the SCREEN to a panel (the GoobOS death / round-end panel): this file then draws nothing of its own - no
-- blackout, no cards, no curtains, no fades, no key handling - renders the replay only where the panel asks
-- (V.RenderInset) and is driven through V.Play/Next/Skip/Report/Save. Timers and failsafes (the highlight deadline,
-- the end card's 8 s, the wall clock, stop-on-respawn) are unchanged. It only takes effect while a panel has claimed
-- it (V.SetUIOwner) and says it is on screen, so the switch alone can never leave a player looking at nothing.
V.UIConVar = V.UIConVar or CreateClientConVar("zc_killcam_ui", "0", true, false, "Killcam presentation: 0 the killcam draws its own replay screens (default), 1 a panel (GoobOS) draws them and embeds the replay", 0, 1)
function V.SetUIOwner(fn) V.UIOwner = isfunction(fn) and fn or nil end
function V.UIActive()
    if V.UIConVar:GetInt() ~= 1 or not V.UIOwner then return false end
    local ok, on = pcall(V.UIOwner)
    return ok and (on == true or on == "side")
end
-- postround_20260925: true while the replay must stay OUT of the player's own view (a side card, or a living player's
-- highlight). Cached per frame: PrePlayerDraw asks once per player drawn.
function V.UISide()
    local now = RealTime()
    if V.sideAt == now then return V.sideVal end
    local side
    if V.UIConVar:GetInt() == 1 and V.UIOwner then
        local ok, on = pcall(V.UIOwner)
        if ok and on == "side" then side = true elseif ok and on == true then side = false end
    end
    if side == nil then
        local me = LocalPlayer()
        side = L ~= nil and L.highlight == true and IsValid(me) and me:Alive()
    end
    V.sideAt, V.sideVal = now, side
    return side
end
-- postround_20260925 (owner: "voice chat input takes precedence during killcams"): push-to-talk is never swallowed, and
-- the key bound to +voicerecord is never a replay hotkey. The engine's own lookup (lua/vgui/dadjustablemodelpanel.lua),
-- re-read every 2 s.
function V.IsVoiceBind(bind) return isstring(bind) and string.find(bind, "voicerecord", 1, true) ~= nil end
-- T1 (killcam_polish, 2026-09-25): owner: "the scoreboard should ALWAYS take precedence over those screens". The bind
-- lock below lets +showscores through, the screen takeover (RenderScene / CalcView) stands down while it is open, and
-- ZCKillcamView.ScoreboardUp() tells the GoobOS panels (deathpanel.lua / roundend.lua) to hide. The key, when one is
-- bound, is the authority (a missed ScoreboardHide can never leave the replay hidden); the Show/Hide hooks cover an
-- unbound or remapped scoreboard. No arguments, plain boolean, one answer per frame: cheap in Think and Paint.
function V.IsScoreBind(bind) return isstring(bind) and string.find(bind, "showscores", 1, true) ~= nil end
hook.Add("ScoreboardShow", "ZCKillcam.ScoreUp", function() V.ScoreOpen = true end)
hook.Add("ScoreboardHide", "ZCKillcam.ScoreUp", function() V.ScoreOpen = false end)
function V.ScoreKey()
    local now = RealTime()
    if now - (V.scoreKeyAt or -math.huge) < 2 then return V.scoreKey end
    V.scoreKeyAt, V.scoreKey = now, nil
    local last = rawget(_G, "BUTTON_CODE_LAST") or 171
    for code = 1, last do
        local ok, bind = pcall(input.LookupKeyBinding, code)
        if ok and V.IsScoreBind(bind) then V.scoreKey = code break end
    end
    return V.scoreKey
end
function V.ScoreboardUp()
    local frame = FrameNumber()
    if V.scoreFrame == frame then return V.scoreUp end
    -- T1r (2026-09-25): US1's scoreboard (addons/scoreboard, ZCScoreboard) answers first - its frame exists exactly
    -- while the board is open, however it was opened (key, goobos_scoreboard) and however long it stays. Its
    -- ScoreboardShow hook returns true, which can stop the ZCKillcam.ScoreUp hook above from ever running.
    local sb = rawget(_G, "ZCScoreboard")
    local up = istable(sb) and IsValid(sb.Frame) and sb.Frame:IsVisible() or false
    if not up then
        local key = V.ScoreKey()
        if key then
            up = input.IsButtonDown(key)
            if not up then V.ScoreOpen = false end
        else
            up = V.ScoreOpen == true
        end
    end
    V.scoreFrame, V.scoreUp = frame, up
    return up
end
function V.VoiceKey()
    local now = RealTime()
    if now - (V.voiceKeyAt or -math.huge) < 2 then return V.voiceKey end
    V.voiceKeyAt, V.voiceKey = now, nil
    local last = rawget(_G, "BUTTON_CODE_LAST") or 171
    for code = 1, last do
        local ok, bind = pcall(input.LookupKeyBinding, code)
        if ok and V.IsVoiceBind(bind) then V.voiceKey = code break end
    end
    return V.voiceKey
end

local function lifeThink()
    local me = LocalPlayer()
    if L.round then return V.Life.RoundThink(me) end -- replay_v1 P3: the round viewer's frame (below), inside the same fence
    -- A death replay never hijacks a living player's view. The round highlight is for everyone, between rounds only:
    -- it lets go by itself if the next round starts under it.
    if not IsValid(me) or (me:Alive() and not L.highlight) then
        if IsValid(me) and V.LifeUnfinished(L) then V.LifeDrop(L.waiting and 1 or 2, L.id) end -- P1: counted, never silent
        return stop()
    end
    if L.highlight and RealTime() > (L.deadline or 0) then return leave() end -- fade out like every other ending, never snap
    local typing = vgui.GetKeyboardFocus() ~= nil or gui.IsConsoleVisible() or gui.IsGameUIVisible()
    local r, f, space, tab, q = pressed(KEY_G), pressed(KEY_V), pressed(KEY_SPACE), pressed(KEY_B), pressed(KEY_Q)
    local off = pressed(KEY_N)
    if V.UIActive() or V.UISide() then r, f, space, tab, q, off = false, false, false, false, false, false end -- P3 seam: the panel owns input; a living player's keys are their own
    if not curtain() then return end
    if L.leaving then return end
    if space and L.card and not L.pending and L.curtainTo == 1 then L.cardUntil, space = 0, false end
    if L.waiting then -- the blackout and input/voice lock stay owned until the replay starts
        if L.highlight then
            if RealTime() >= L.startAt then pcall(endMenu, false) go(1) end
            return
        end
        if off then return optOut() end -- reachable WITHOUT sitting through a replay first, which is the point of it
        if q then return leave() end
        if RealTime() >= L.startAt then go(1) end
        return
    end
    if not typing then
        -- Opting out. Offered on the END CARD only, never mid-replay: a single key that silently switches a feature off
        -- must not be something you can fat-finger while watching. It sets the same convar the settings menu does.
        if off and (L.over or L.highlight) then return optOut() end
        if q or (L.highlight and space) then return leave() end
        if L.highlight then tab, f, r, space = false, false, false, false end -- nothing to save, report or step through
        if tab and V.OpenSequence then local id, seq = L.id, L.seq stop(true) return V.OpenSequence(id, seq) end
        if f and not L.saved then net.Start("zckc_save") net.SendToServer() end
        if r and not L.over and not L.dialog then
            if L.inst.reportable then
                L.dialog = V.ReportDialog(L.id, L.index, L.inst, function() if L then L.dialog = nil end end)
            else say(REPLY[3]) end
        end
        if space and not L.over then return go(L.index + 1) end
    end
    if L.over then
        if L.highlight or RealTime() - L.overAt > 8 then leave() end
        return
    end
    V.UpdateReplaySounds((L.bullet and not L.bullet.done and L.bullet.at and 0.15) or L.rate or 1, L.dialog or L.curtainTo == 1 or L.pending)
    if L.dialog then return end -- paused while writing a report
    local slow = L.seq.slow -- a highlight brings its own, shorter, slow-motion window
    local from, to, least = slow and slow[1] or SLOW_FROM, slow and slow[2] or SLOW_TO, slow and slow[3] or SLOW
    local want = (L.cs >= from and L.cs <= to) and least or 1
    L.rate = Lerp(math.min(RealFrameTime() * 5, 1), L.rate or 1, want)
    local rate = (L.curtainTo == 1 or L.pending) and 0 or L.rate -- nothing moves while the card is up
    local before = L.cs
    L.cs = math.min(L.cs + RealFrameTime() * 100 * rate, L.clip.last)
    if flight(L.cs) then rate, L.cs = 0, L.bullet.cs end -- the killing round is in the air: the world holds where the shot left it
    if L.cs >= L.clip.last then go(L.index + 1) end
    L.hitFlash = math.max((L.hitFlash or 0) - RealFrameTime() * 1.6, 0)
    L.kick = math.max((L.kick or 0) - RealFrameTime() * rate * 9, 0)
    local shooter = L.clip.actors[L.clip.pov or 0]
    local aiming = false
    if shooter then
        local _, _, _, _, _, flags = V.StateAt(shooter, L.cs)
        aiming = flags ~= nil and V.HasFlag(flags, 64)
    end
    L.zoom = math.Approach(L.zoom or 0, aiming and 1 or 0, RealFrameTime() * rate * 5) -- about a fifth of a second, in replay time
    L.eye = function() return eyeOf(L.clip, L.cs) end
    fireEvents(before, L.cs, rate)
    -- Everyone but the eyes we look through is shown where THAT player's screen had them: `lag` cs behind the server
    -- (actor.lag, sv_clips K.LagOf). The game's bullets are lag compensated, so this is also where they were hit.
    local seer = L.clip.actors[L.clip.pov or 0]
    local lag = seer and tonumber(seer.lag) or 0
    for i, g in pairs(L.ghosts) do
        if IsValid(g) then
            local at, rows = L.cs, L.clip.actors[i] and L.clip.actors[i].s
            if i ~= L.clip.pov and lag > 0 then
                at = L.cs - lag
                if rows and rows[1] and at < rows[1][1] and L.cs >= rows[1][1] then at = rows[1][1] end -- not hidden for the clip's first moments
            end
            V.Gore.Apply(g, L.clip.actors[i], L.cs)
            pose(g, L.clip.actors[i], at, L.clip.origin, L.clip)
            if IsValid(g.zcRag) then V.Gore.Apply(g.zcRag, L.clip.actors[i], L.cs) end
            local host = IsValid(g.zcRag) and not g.zcRag:GetNoDraw() and g.zcRag or g
            local hand = host:LookupBone("ValveBiped.Bip01_R_Hand")
            if hand and host.zcGoreHidden and host.zcGoreHidden[hand] and IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
        end
    end
end

-- replay_v1 P3: a frame of the ROUND viewer (cl_part_09 V.Round). The whole round is one clip and the playhead is the
-- viewer's transport, so none of the death replay's machinery runs: no curtain, slow motion, bullet or object cam,
-- go(index + 1), end card, report or save keys. Only the ghosts the viewer culls in are posed; the rest are hidden.
-- On V.Life: this block is at the 200-locals line.
function V.Life.RoundThink(me)
    local began = SysTime()
    local R = V.Round
    if not IsValid(me) or not R then return stop() end
    local rs, before = L.round, L.cs
    if R.Advance(L, me) == false or not L then return end
    local rate = (rs.playing and not rs.buffering) and rs.speed or 0
    V.UpdateReplaySounds(rate, rate == 0)
    local pov = L.clip.actors[L.clip.pov or 0]
    local aiming = false
    if pov then
        local _, _, _, _, _, flags = V.StateAt(pov, L.cs)
        aiming = flags ~= nil and V.HasFlag(flags, 64)
    end
    L.zoom = math.Approach(L.zoom or 0, aiming and 1 or 0, RealFrameTime() * 5)
    if not rs.eye then rs.eye = function() return eyeOf(L.clip, L.cs) end end -- one closure for the round, not one a frame
    L.eye = rs.eye
    if rs.jumped then rs.jumped = false elseif L.cs > before then fireEvents(before, L.cs, rate) end -- a seek is silent
    local show = rs.show
    for i, g in pairs(L.ghosts) do
        if IsValid(g) then
            local actor = L.clip.actors[i]
            if show[i] and actor then
                g.zcCulled = nil
                R.Dress(g, actor, L.cs)
                V.Gore.Apply(g, actor, L.cs)
                pose(g, actor, L.cs, L.clip.origin, L.clip)
                if IsValid(g.zcRag) then V.Gore.Apply(g.zcRag, actor, L.cs) end
                local host = IsValid(g.zcRag) and not g.zcRag:GetNoDraw() and g.zcRag or g
                local hand = host:LookupBone("ValveBiped.Bip01_R_Hand")
                if hand and host.zcGoreHidden and host.zcGoreHidden[hand] and IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
                if g.zcPov and not povGun:GetBool() then -- the player's own "no body in first person" setting
                    g:SetNoDraw(true)
                    if IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
                end
            elseif not g.zcCulled then
                g.zcCulled, g.zcBeam = true, 0
                g:SetNoDraw(true)
                if IsValid(g.zcRag) then g.zcRag:SetNoDraw(true) end
                if IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
            end
        end
    end
    R.BookThink(began)
end

-- Two failsafes wrap the whole state machine, because a replay that cannot end is the worst thing this file can do:
-- the screen stays behind a curtain, input stays swallowed, and the player's only way out is a map change (owner,
-- 2026-09-22, after a round highlight).
--
--  * the WALL. Every other exit can decline: the highlight deadline needs L.highlight, leave() needs its fade to
--    finish, and the "you are alive again" exit needs a valid player. The wall is plain wall-clock, fixed when the
--    sequence arrived, and it calls stop() outright rather than asking for a fade.
--  * the FENCE. GMod does not pcall hook callbacks, so an error in here threw at the same line every single frame and
--    nothing below it ever ran - including every line that would have cleared L. One bad frame is now one log line.
local complained = false
hook.Add("Think", "ZCKillcam.Life", function()
    if not L then return end
    if L.wall and RealTime() > L.wall then
        print("[Killcam] replay ran past its wall clock; handing the screen back")
        return stop()
    end
    if L.leaving and L.leaveBy and RealTime() > L.leaveBy then return stop() end -- the fade never completed
    local ok, err = pcall(lifeThink)
    if not ok then
        if not complained then complained = true print("[Killcam] replay think: " .. tostring(err)) end
        stop()
    end
end)

-- The gamemode has CalcView hooks of its own and hook order is not ours to choose, so the replay
-- renders the frame itself. CalcView stays as the fallback if the render call fails.
-- The gamemode's first person runs at hg_fov clamped to 75-100. A normal view is then widened by the
-- engine for screens wider than 4:3; render.RenderView takes the number as given, so the same widening is applied here.
-- PROVISIONAL(2026-09-21, the widening is reasoned from the owner's "FOV a little low" report, not measured: zc_killcam_fov overrides, ratify-by: 2026-10-05)
local fovOverride = CreateClientConVar("zc_killcam_fov", "0", true, false, "Replay field of view (0 = follow hg_fov)")
local function replayFov(widen)
    -- killcam_kinds (2026-09-25, owner: "FOV should be raised a little bit"): a flat lift on top of hg_fov (and the bullet
    -- cam's framing below), clamp raised to match. An explicit zc_killcam_fov is left exactly as set.
    -- PROVISIONAL(2026-09-25, +8 degrees on the eye view, +6 on the bullet cam: a guess at "a little", ratify-by: 2026-10-09)
    V.FovBoost = V.FovBoost or CreateClientConVar("zc_killcam_fov_boost", "8", true, false, "Degrees added to the replay field of view (0 = as before)")
    local boost = math.Clamp(V.FovBoost:GetFloat(), 0, 30)
    local fov = fovOverride:GetFloat()
    if fov <= 0 then
        local hgFov = GetConVar("hg_fov")
        fov = math.Clamp((hgFov and hgFov:GetFloat() or 90) + boost, 75, 110)
    else
        boost = 0
    end
    -- PROVISIONAL(2026-09-21, a tenth narrower when aiming: the gamemode's own zoom depends on sights and attachments that are not recorded, ratify-by: 2026-10-05)
    fov = fov * (1 - 0.1 * (L and L.zoom or 0))
    fov = Lerp(V.BulletWeight(L and L.bullet), fov, (L and L.bullet and L.bullet.cinematic and V.Cinema and V.Cinema.Fov(L.bullet) or 64) + boost * 0.75)
    if not widen then return fov end
    return math.deg(2 * math.atan(math.tan(math.rad(fov) / 2) * (ScrW() / ScrH()) / (4 / 3)))
end

local drawOverlay -- defined with the overlay, below
-- postround_20260925: a side card leaves the live world on screen, and the replay's bodies, guns and ragdolls are real
-- client entities at the replay's positions. They are hidden for the live pass (from RenderScene), shown inside the
-- replay's own pass (V.WithReplayScene) and handed back at PostRender, so the pose code's state is untouched.
function V.HideReplayFromLive()
    if V.LiveHidden then return end
    local list = {}
    for ent in pairs(V.ReplayOwned or {}) do
        if IsValid(ent) and not ent:GetNoDraw() then ent:SetNoDraw(true) list[#list + 1] = ent end
    end
    V.LiveHidden = list
end
hook.Add("PostRender", "ZCKillcam.SideLive", function()
    local list = V.LiveHidden
    if not list then return end
    V.LiveHidden = nil
    for i = 1, #list do if IsValid(list[i]) then list[i]:SetNoDraw(false) end end
end)
local rendering = false
hook.Add("RenderScene", "ZCKillcam.Life", function()
    -- P3 seam: while a replay plays under a panel, the live world is not drawn at all (the panel covers the screen
    -- and draws the replay inset); otherwise the live world renders normally under the panel - no blackout.
    -- replay_v1 P3: the round viewer owns the screen; only the scoreboard outranks it. PROVISIONAL(2026-09-26, a GoobOS panel
    -- claiming the screen (zc_killcam_ui 1) does not black out a round replay: GoobOS has no round mode yet, ratify-by: 2026-10-10)
    local round = L ~= nil and L.round ~= nil
    if V.UISide() and not round then V.HideReplayFromLive() return end -- postround_20260925: the player's own world renders; the replay lives in the card
    if V.ScoreboardUp() then V.HideReplayFromLive() return end -- T1: the live view and its HUD pass draw, so the scoreboard shows
    if V.UIActive() and not round then
        if L and not L.over and not L.waiting then render.Clear(0, 0, 0, 255, true, true) return true end
        return
    end
    -- Do not let the live spectator camera render underneath a death replay's handoff or end card.
    -- P6 2026-09-24: only the instant a replay is being set up (under 0.2 s now). The 5 s death wait and the end card
    -- used to be pure black here; they now sit on a dimmed view of the live spectator camera (HUDPaint/drawOverlay).
    if L and not L.highlight and L.waiting then return true end
    if not L or L.over or L.waiting or rendering then return end
    local origin, angles = eyeOf(L.clip, L.cs)
    if not origin then return end
    local looker = L.ghosts and L.ghosts[L.clip.pov or 0]
    if V.BulletWeight(L.bullet) == 0 and IsValid(looker) and looker.zcScope and (L.zoom or 0) > 0.01 then -- only while aiming: a second view of the world every frame is not free
        rendering = true
        V.WithReplayScene(function() renderScope(looker, origin, angles, replayFov(true), L.cs) end)
        rendering = false
    end
    rendering = true
    local began = SysTime() -- P3 seam: timed, to compare with V.RenderInset (zc_killcam_render_stats)
    local restoreCutaway = V.Cinema and V.Cinema.BeginCutaway(L)
    local ok = V.WithReplayScene(function() render.RenderView({origin = origin, angles = angles, x = 0, y = 0, w = ScrW(), h = ScrH(), fov = replayFov(true), znear = 1,
        drawhud = false, drawviewmodel = false, drawmonitors = false, dopostprocess = false}) end)
    if restoreCutaway then restoreCutaway() end
    rendering = false
    V.BookRender(V.FullStats, began)
    L.ownsFrame = ok
    if ok then
        -- The spectator HUD ("Spectating player: ...") describes the live round, not the replay, so it is
        -- off (drawhud = false) and the replay paints its own overlay on the finished frame.
        cam.Start2D()
        local fine, err = pcall(drawOverlay)
        cam.End2D()
        if not fine and not L.overlayErr then L.overlayErr = true print("[Killcam] overlay: " .. tostring(err)) end
        return true
    end
end)
hook.Add("CalcView", "ZCKillcam.Life", function()
    if not L or L.over or L.waiting or (V.UISide() and not L.round) or V.ScoreboardUp() then return end -- T1: the scoreboard sits on the live camera
    local origin, angles = eyeOf(L.clip, L.cs)
    if not origin then return end
    L.ownsFrame = false
    return {origin = origin, angles = angles, fov = replayFov(false), znear = 1, drawviewer = false}
end)

-- === P3 seam: the replay as a component (killcam_revitalize, 2026-09-24; P3_SEAM.txt) ============================
V.InsetStats = V.InsetStats or {n = 0, sum = 0, max = 0}
V.FullStats = V.FullStats or {n = 0, sum = 0, max = 0}
function V.BookRender(s, began)
    local ms = (SysTime() - began) * 1000
    s.n, s.sum = s.n + 1, s.sum + ms
    if ms > s.max then s.max = ms end
    return ms
end
-- inset_bloom_20260926 (owner: "a superbright blur behind the killcam/highlight panel, over the Round End title"):
-- V.RenderInset runs from a panel's Paint, i.e. mid-VGUI. The Z-City post-processing that the view render triggers
-- (RenderScreenspaceEffects -> "Post Processing": berserk/noradrenaline/fear bloom, pain/brain toytown, colour modify,
-- motion blur) works on the WHOLE framebuffer, so it bloomed and blurred every panel part painted before the inset
-- (the title, the left column) and brightened the world behind. For the inset render those calls are no-ops; each
-- muted call is counted in V.MutedPost (zc_killcam_impact_print prints them).
local POST_FUNCS = {"DrawBloom", "DrawToyTown", "DrawMotionBlur", "DrawSunbeams", "DrawColorModify", "DrawSharpen", "DrawSobel", "DrawTexturize", "DrawMaterialOverlay"}
V.MutedPost = V.MutedPost or {}
local mutedFns = {}
local function mutedFor(name)
    local fn = mutedFns[name]
    if not fn then
        fn = function() V.MutedPost[name] = (V.MutedPost[name] or 0) + 1 end
        mutedFns[name] = fn
    end
    return fn
end
-- The whole RenderScreenspaceEffects event is skipped as well: most of Z-City's screen effects (O2/unconscious noise,
-- berserk, noradrenaline, fear) paint the full screen with render.DrawScreenQuad from inside it. hook.Call is read from
-- the global table on every engine call, so the swap covers the gamemode and every hook for the inset render only; it
-- chains whatever hook.Call is installed (ulx_zchat_bridge replaces it) and is put back right after.
local SKIP_EVENTS = {RenderScreenspaceEffects = true}
local mutedCall
function V.MutePostProcess()
    local saved = {}
    local call = hook.Call
    if isfunction(call) and call ~= mutedCall then
        local original = call
        mutedCall = function(event, ...)
            if SKIP_EVENTS[event] then V.MutedPost[event] = (V.MutedPost[event] or 0) + 1 return end
            return original(event, ...)
        end
        saved.hookCall = original
        hook.Call = mutedCall
    end
    for i = 1, #POST_FUNCS do
        local name = POST_FUNCS[i]
        local fn = rawget(_G, name)
        if isfunction(fn) and fn ~= mutedFns[name] then
            saved[name] = fn
            _G[name] = mutedFor(name)
        end
    end
    return function()
        if saved.hookCall then
            if hook.Call == mutedCall then hook.Call = saved.hookCall end
            saved.hookCall = nil
        end
        for name, fn in pairs(saved) do _G[name] = fn end
        if V.ImpactPrint and V.ImpactPrint:GetBool() and next(V.MutedPost) and RealTime() - (V.MutedSaidAt or -math.huge) > 10 then
            V.MutedSaidAt = RealTime()
            local parts = {}
            for name, n in pairs(V.MutedPost) do parts[#parts + 1] = name .. "=" .. n end
            MsgN("[Killcam] inset post-processing muted: " .. table.concat(parts, " "))
        end
    end
end
-- Renders the replay's current frame into a SCREEN-space rect (pixels; from a panel's Paint use its LocalToScreen),
-- exactly as the fullscreen path does: same camera, ghosts, scope, cinematic cutaway, live entities hidden. Returns
-- (true, ms) when it drew, false when there is nothing to draw (no replay, waiting, end card, or a render in progress).
-- The field of view is the replay's, widened for the rect's own aspect.
function V.RenderInset(x, y, w, h)
    if not L or L.over or L.waiting or rendering or not L.clip or not w or not h or w < 8 or h < 8 then return false end
    local origin, angles = eyeOf(L.clip, L.cs)
    if not origin then return false end
    local began = SysTime()
    local fov = math.deg(2 * math.atan(math.tan(math.rad(replayFov(false)) / 2) * (w / h) / (4 / 3)))
    local looker = L.ghosts and L.ghosts[L.clip.pov or 0]
    rendering = true
    if V.BulletWeight(L.bullet) == 0 and IsValid(looker) and looker.zcScope and (L.zoom or 0) > 0.01 then
        V.WithReplayScene(function() renderScope(looker, origin, angles, fov, L.cs) end)
    end
    local restoreCutaway = V.Cinema and V.Cinema.BeginCutaway(L)
    local restorePost = V.MutePostProcess()
    local ok = V.WithReplayScene(function() render.RenderView({origin = origin, angles = angles, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h), fov = fov, znear = 1,
        drawhud = false, drawviewmodel = false, drawmonitors = false, dopostprocess = false}) end)
    restorePost()
    if restoreCutaway then restoreCutaway() end
    rendering = false
    return ok, V.BookRender(V.InsetStats, began)
end
-- What a panel needs to draw its own HUD. ONE table, refilled on every call: read it, do not keep it.
-- kind "life" | "highlight"; phase "waiting" | "playing" | "over" | "leaving"; index/count: which hit of how many;
-- cs/first/last: replay time and the clip's bounds in centiseconds (the hit is at cs 0); inst = seq.instances[index]
-- ({attacker, wep, dmg, hits, ago, tag, reportable, clip}); seq.h2h is the server's head-to-head (P2) when present.
function V.State()
    if not L then return nil end
    local out = V.StateOut or {}
    V.StateOut = out
    local seq = L.seq
    out.kind = L.highlight and "highlight" or (L.round and "round" or "life") -- P3: PROVISIONAL(2026-09-26, new kind "round" for panels, ratify-by: 2026-10-10)
    out.phase = (L.leaving and "leaving") or (L.over and "over") or (L.waiting and "waiting") or "playing"
    out.id, out.seq, out.h2h = L.id, seq, seq and seq.h2h
    out.index, out.count = L.index, seq and seq.instances and #seq.instances or 0
    out.inst = seq and seq.instances and seq.instances[L.index or 0]
    out.cs, out.first, out.last = L.cs, L.clip and L.clip.first, L.clip and L.clip.last
    out.rate, out.saved, out.reported = L.rate or 1, L.saved == true, L.reported
    return out
end
-- Playback, for the panel. Each returns true when it acted.
function V.Play(index)
    if not L or L.leaving then return false end
    L.over, L.overAt = nil, nil
    go(math.max(1, math.floor(tonumber(index) or 1)))
    return true
end
function V.Next()
    if not L or L.over or L.waiting or L.leaving then return false end
    go((L.index or 0) + 1)
    return true
end
function V.Skip()
    if not L then return false end
    leave()
    return true
end
function V.Save()
    if not L or L.highlight or L.saved then return false end
    net.Start("zckc_save") net.SendToServer()
    return true
end
-- With `text` it files the report directly (the panel drew its own box); without, it opens the killcam's report box.
function V.Report(index, text)
    if not L or L.highlight or not L.seq then return false end
    index = math.floor(tonumber(index) or L.index or 1)
    local inst = L.seq.instances[index]
    if not inst or not inst.reportable then return false end
    if isstring(text) then
        V.lastReport = {id = L.id, index = index}
        net.Start("zckc_report") net.WriteString(L.id) net.WriteUInt(index, 5) net.WriteString(string.sub(text, 1, 240)) net.SendToServer()
        return true
    end
    if IsValid(L.dialog) then return false end
    L.dialog = V.ReportDialog(L.id, index, inst, function() if L then L.dialog = nil end end)
    return true
end
concommand.Add("zc_killcam_render_stats", function()
    for _, row in ipairs({{"fullscreen", V.FullStats}, {"inset", V.InsetStats}}) do
        local s = row[2]
        MsgN(string.format("[Killcam] %s render: frames=%d avg=%.2fms max=%.2fms", row[1], s.n, s.n > 0 and s.sum / s.n or 0, s.max))
    end
    MsgN("[Killcam] zc_killcam_ui=" .. V.UIConVar:GetInt() .. " panel=" .. tostring(V.UIActive()))
end)

-- Living players are hidden while the replay runs: it shows the past, not where people are now.
hook.Add("PrePlayerDraw", "ZCKillcam.LifeHide", function() if L and not L.over and not L.waiting and (rendering or not V.UISide()) then return true end end)

-- A death replay owns the spectator camera from the first death frame through its end card.
hook.Add("PlayerBindPress", "ZCKillcam.LifeBinds", function(_, bind)
    if (deathPending or (L and not L.highlight)) and not V.IsVoiceBind(bind) and not V.IsScoreBind(bind) then return true end -- postround_20260925: push-to-talk always passes; T1: so does the scoreboard
end)

-- === Out of the round while a killcam has the screen ==============================================================
-- A killcam takes the screen for a few seconds, so for that moment the watcher is out of the round: the spectator
-- camera is pinned and their voice is cut both ways. Both end the instant the killcam does.
--
-- HIGHLIGHTS ARE EXCLUDED FROM BOTH. The owner asked for the voice carve-out by name; the input lock follows it for
-- the same reason. The reel plays at round end, over the map vote and the scoreboard, and `ClearButtons` would take
-- IN_SCORE with it - freezing a player out of the scoreboard and their own camera for a 15 s reel would fight the
-- very vote flow the carve-out exists to protect. "Restore both after the killcam is over" scopes this to killcams.
local function immersed() return deathPending or (L ~= nil and not L.highlight) end

-- The lock clears movement and command buttons; replay controls are read with input.IsKeyDown (raw keyboard state,
-- see pressed()), so Q / N / Space still work. PlayerBindPress separately swallows binds so no other control can
-- change the spectator target or view while the death replay owns the screen. Highlights retain their carve-out.
local heldAngles, lockErr
-- Named, so the pcall below costs no closure per frame - this runs on every user command.
local function lockMove(cmd)
    heldAngles = heldAngles or cmd:GetViewAngles()
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetViewAngles(heldAngles)
end
hook.Add("CreateMove", "ZCKillcam.LifeLock", function(cmd)
    if not immersed() then heldAngles = nil return end
    -- Guarded because this is the one hook where a fault costs the player their INPUT. It fails OPEN: if the lock
    -- throws, the command is left untouched and the player simply keeps control, which is the right way round.
    local ok, err = pcall(lockMove, cmd)
    if not ok and not lockErr then lockErr = true print("[Killcam] input lock: " .. tostring(err)) end
end)

-- Telling the server we are inside one, so it can cut our voice (sv_life.lua, K.InKillcam / "ZCKillcam.Hush").
-- The server's claim LAPSES on its own, so this re-asserts it about twice as often as it expires rather than
-- trusting a single message to survive; the explicit "stopped" only makes the restore instant.
local watchSaid, watchAt, watchOff = false, 0, false
local function tellWatch(on)
    if watchOff or (on == watchSaid and (not on or RealTime() < watchAt + 2)) then return end
    -- "zckc_watch" was added to an already-running server, and a client that joined before that happened has no
    -- such name in its string table, so net.Start throws. Try once, then stop: a missing mute is worth far less
    -- than an error twice a second, and the next map change fixes it for good.
    if not pcall(function() net.Start("zckc_watch") net.WriteBool(on) net.SendToServer() end) then watchOff = true return end
    watchSaid, watchAt = on, RealTime()
end
timer.Create("ZCKillcam.Watch", 0.5, 0, function() tellWatch(immersed()) end)

-- The barrel on the true line. The gun is posed from a copy of the game's hold maths, so its barrel lands near, not on, the
-- line the bullet really took (events [12] [13]). Approaching a shot, the error between the drawn barrel and the true
-- direction (carried along with the view since the shot's own sample) is fed back into the gun's aim - the GUN's only, never
-- the camera's - and released again over 15 cs after it, so the recoil the replay draws stays visible.
local function aimFix(g, actor, index, clip, cs)
    local ahead, behind
    local events = clip.events
    for k = V.EvFrom(clip, cs - 15), #events do -- replay_v1 P3: from event 1 for a death clip, as before
        local e = events[k]
        if e[1] > cs + 15 then break end
        if e[2] == 1 and e[3] == index and e[9] and e[1] >= cs - 15 then
            if e[1] >= cs - 1 then ahead = ahead or e else behind = e end
        end
    end
    local e = ahead or behind
    if not e then g.zcFixW = 0 return end
    local weight = 1 - math.abs(e[1] - cs) / 15
    g.zcFixW = math.max(weight, 0)
]========], 2)