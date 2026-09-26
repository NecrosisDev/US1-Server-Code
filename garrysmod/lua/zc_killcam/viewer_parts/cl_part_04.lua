return string.sub([========[xlocal LEGS = {"Pelvis", "Thigh", "Calf", "Foot", "Toe"}
function punchOver(g)
    local d = g.zcDouble
    if not IsValid(d) then return end
    local pelvis = g:LookupBone("ValveBiped.Bip01_Pelvis")
    if not pelvis then return end
    local mine, theirs = g:GetBoneMatrix(pelvis), d:GetBoneMatrix(pelvis)
    if not mine or not theirs then return end
    local skip = g.zcLegBones
    if not skip then
        skip = {}
        for b = 0, g:GetBoneCount() - 1 do
            local name = g:GetBoneName(b) or ""
            for _, part in ipairs(LEGS) do if string.find(name, part, 1, true) then skip[b] = true end end
        end
        g.zcLegBones = skip
    end
    local carry = mine * theirs:GetInverseTR()
    for b = 0, g:GetBoneCount() - 1 do
        if not skip[b] then
            local m = d:GetBoneMatrix(b)
            if m and g:GetBoneMatrix(b) then g:SetBoneMatrix(b, carry * m) end
        end
    end
end

-- Homicide's end-of-round menu is a vgui popup (global hmcdEndMenu, cl_homicide.lua) and paints over everything.
-- PROVISIONAL(2026-09-21, only homicide's menu is known; other modes' end screens need the owner's eyes, ratify-by: 2026-10-05)
local function endMenu(visible)
    local menu = rawget(_G, "hmcdEndMenu")
    if IsValid(menu) then menu:SetVisible(visible) end
end

-- When the replay handed the screen back, and whether the living see the fade too. Declared up here because stop()
-- is what records them, and stop() is defined long before the transition code that reads them.
local outroAt, outroLive = 0, false
-- `quiet` is for a stop that something else replaces in the same breath - a highlight arriving over a running
-- replay, or the full viewer taking the screen. There is nothing to fade back TO, so the outro is skipped.
local function stop(quiet)
    -- However a replay ends - dismissed, the player respawning underneath it, the round changing - the screen comes
    -- BACK rather than snapping back. This lived only in leave(), so every OTHER way out was a hard cut from a black
    -- or dimmed curtain straight to live play. The commonest of those is respawning while the replay is still up.
    if L and not quiet then
        outroAt = RealTime()
        outroLive = L.highlight == true or (IsValid(LocalPlayer()) and LocalPlayer():Alive())
    end
    if L and L.highlight then pcall(endMenu, true) end
    -- Owner-approved 2026-09-24 (R3 ported from the standalone cl_life.lua, which no client ever ran): tell the server
    -- this player is done with the round highlight, so sv_highlight.lua releases the intermission hold once everyone
    -- has, instead of always waiting the precomputed worst case. Every way a highlight ends passes through here.
    if L and L.highlight and not L.hlDoneSent and util.NetworkStringToID("zckc_hl_done") ~= 0 then
        L.hlDoneSent = true
        net.Start("zckc_hl_done") net.SendToServer()
    end
    if L and IsValid(L.dialog) then L.dialog:Remove() end -- a popup left behind would hold the mouse over live play
    clearGhosts()
    L = nil
end
-- This file is hot-reloaded on the live server: the copy being replaced still owns its ghosts, so it is told to let go first.
if V.StopLife then pcall(V.StopLife) end
V.StopLife = stop
V.Life.stop = stop -- replay_v1 P3

-- How the held gun moves, from homigrad_base/shared.lua (the block that fills AdditionalPosPreLerp / AdditionalAngPreLerp,
-- read from the US1 source 2026-09-21), driven by REPLAY time so slow motion slows it too:
--   walk bob     phase t * 6.6; walk = clamp(speed / 100, 0, 1), doubled when sprinting; lena = speed / 150 (a tenth in the air)
--   idle sway    phase t / 2, about a unit of drift
--   crouch       one unit back
--   sprint       self.pitch goes to 0.65: the gun follows only a third of the aim's pitch. Sprinting = faster than 150 u/s on
--                the ground and not aiming (IN_SPEED itself is not recorded)
-- The gamemode eases toward these by the weapon's Ergonomics; here a plain ease is used. PROVISIONAL(2026-09-21, easing rate
-- and the sprint test are approximations of values that are not recorded, ratify-by: 2026-10-05)
local sin, cos = math.sin, math.cos
local function isPistol(g, w)
    if g.zcPistol == nil then
        g.zcPistol = w.PistolKinda and true or (isfunction(w.IsPistolHoldType) and select(2, pcall(w.IsPistolHoldType, w)) == true)
    end
    return g.zcPistol
end

-- The weapon postures, from hg.postureFunctions2 (homigrad_base/shared.lua:1497, US1 source): what each adds to the gun's
-- offset (x, y, z) and turn (p, yw, r). The game picks 3 while sprinting, else the player's chosen posture; most give way
-- to aiming. Left out: the player's personal hg.GunPositions nudge and the reload fade of the sprint carry (not recorded).
local P3, P3P, P4, P7, P8 = Angle(45, 45, -25), Angle(5, 65, 0), Angle(40, -30, -40), Angle(5, -30, 0), Angle(40, 10, -30)
local HIGH, RUN = Angle(-30, -25, 30), Angle(20, 10, 0)
local clamp = math.Clamp
local function postureOf(g, w, which, sprinting, aiming, crouch, pitch, speed)
    local x, y, z, p, yw, r = 0, 0, 0, 0, 0, 0
    if sprinting then which = 3 end
    if which == 5 then return 0, 0, -1, 0, 0, -20 end
    if which == 2 then
        if isPistol(g, w) then return 0, 0, -6, 0, 0, -15 end
        return 2, 1, -6, -2, 0, -15
    end
    if aiming or which == 0 then return x, y, z, p, yw, r end
    local pistol = isPistol(g, w)
    if which == 1 then
        if pistol then return -4, -3, 0, 2, 5, -20 end
        local a = clamp(-pitch / 65, -1, 1)
        if a > 0.8 or a < -0.95 then return x, y, z, p, yw, r end
        y = -9 * clamp((-pitch + 75) / 45, 0.5, 1) + math.max(10 * a, 0)
        x = -2 + 6 * clamp((pitch - 25) / 25, 0, 1) + 5 * a
        z = 1.5 * clamp((-pitch + 75) / 45, 0.2, 1)
        return x, y, z, 3, 5, -4
    elseif which == 3 then
        local run = (w.CanEpicRun or pistol) and true or false
        local mul = sprinting and clamp((speed - 150) / 300, 0, 1) or 1
        local epic = istable(w.EpicRunPos) and w.EpicRunPos or isvector(w.EpicRunPos) and w.EpicRunPos or nil
        y = -(3 + (run and ((epic and epic[3] or 6) - 6) or -2)) * mul
        x = -(-7 + (run and ((epic and epic[2] or 6) + 3) or 8) + 3 * clamp(-pitch / 20, -1, 0)) * mul
        z = (3 + (run and ((epic and epic[1] or 2) - 2) or 0)) * mul
        local turn = run and P3P or P3
        p, yw, r = turn.p * mul, turn.y * mul, turn.r * mul
        if not run then
            x, y, z = x - 5 * mul, y - 6 * mul, z - 3 * mul -- -9 and the +4 the game adds back while running
            p, yw, r = p + (HIGH.p + RUN.p) * mul, yw + (HIGH.y + RUN.y) * mul, r + (HIGH.r + RUN.r) * mul
        end
        return x, y, z, p, yw, r
    elseif which == 4 then
        local turn = pistol and P7 or (crouch and P8 or P4)
        if pistol then return -3 + 5 * clamp(pitch / 20, -0.5, 0.5), -7, 1, turn.p, turn.y, turn.r end
        return -2 - 5 * clamp(-pitch / 20, 0, 0.5), -8, 1, turn.p, turn.y, turn.r
    elseif which == 6 then
        if pistol then return 0, -2, 6, 0, 0, 10 end
        return 5, -2, 6, 12, 0, 0
    elseif which == 9 then
        if pistol then return -4, 14, 3, 0, 0, -70 end
        return 3, 14, 3, 2, -10, -50
    elseif which == 7 then return 0, 0, 0, 0, 0, -60 -- sh_worldmodel.lua:95: the gun rolled over, one hand
    elseif which == 8 then return 0, 0, 0, 0, 0, -10 end
    return x, y, z, p, yw, r
end

-- Leaning (recorder: (q + 8) * 65536 above the posture bits, q = lean in fifths). The game bends the body with bone turns
-- summed by hg.bone.Set - homigrad_base/sh_anim.lua "homigrad-lean-bone", read from US1: a long gun twists the spine and
-- the right upper arm, anything else tips the spine against the pelvis. amt 0.7, div 0.33 are the game's. The eyes the replay
-- looks through hang off this body's neck, so the view leans with it.
local LEAN_BONES = {"ValveBiped.Bip01_Spine", "ValveBiped.Bip01_Spine1", "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Pelvis",
    "ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_Head1"}
local function leanOver(g, flags, step, alive)
    local q = math.floor(flags / 65536) % 16
    local want = (alive and q > 0) and math.Clamp((q - 8) / 5, -1.3, 1.3) or 0 -- the game never leans past 1.3
    local lean = (g.zcLean or 0) + (want - (g.zcLean or 0)) * math.min(step * 10, 1)
    if lean > -0.01 and lean < 0.01 then lean = 0 end
    g.zcLean = lean
    local key = math.floor(lean * 100 + 0.5)
    if key == g.zcLeanKey then return end
    g.zcLeanKey = key
    local long = g.zcWeapon and g.zcFamily == "gun" and not isPistol(g, g.zcWeapon)
    local a, d = math.abs(lean) * 0.7, 0.33
    local spine, pelvis, rArm, lArm, head = angle_zero, angle_zero, angle_zero, angle_zero, angle_zero
    if lean < 0 then
        if long then spine, rArm, head = Angle(-30, -20, 10) * (a * d), Angle(0, -10, -20) * a, Angle(0, 20, 0) * a
        else spine, pelvis, lArm = Angle(-30, 0, 0) * (a * d), Angle(-30, 0, 0) * (a * -d), Angle(-20, 0, 0) * a end
    elseif lean > 0 then
        if long then spine, rArm, head = Angle(30, 25, 18) * (a * d), Angle(10, 0, 10) * a, Angle(30, 0, 0) * a
        else spine, pelvis, rArm = Angle(35, 0, 0) * (a * d), Angle(-30, 0, 0) * (a * d), Angle(20, 0, 0) * a end
    end
    local turn = {spine, spine, spine, pelvis, rArm, lArm, head}
    for i, name in ipairs(LEAN_BONES) do
        local b = g:LookupBone(name)
        if b then g:ManipulateBoneAngles(b, turn[i]) end
    end
end

local function gunMotion(g, cs, speed, onGround, crouch, aiming, step, flags, pitch)
    local m = g.zcMotion
    if not m then m = {pos = Vector(0, 0, 0), ang = Angle(0, 0, 0), relax = 0} g.zcMotion = m end
    local t = cs / 100
    local sprinting = speed > 150 and onGround and not aiming -- clips from before the sprint key was recorded
    local which = 0
    if flags and V.HasFlag(flags, 1024) then
        sprinting = V.HasFlag(flags, 2048) and speed > 150 -- SWEP:IsSprinting: the key, and faster than 150
        which = math.floor(flags / 4096) % 16
    end
    g.zcPosture, g.zcAds = which, aiming
    local reloading = flags and V.HasFlag(flags, 32)
    local sx, sy, sz, sp, syw, sr = 0, 0, 0, 0, 0, 0
    if IsValid(g.zcWeapon) or istable(g.zcWeapon) then sx, sy, sz, sp, syw, sr = postureOf(g, g.zcWeapon, which, sprinting, aiming, crouch, pitch or 0, speed) end
    local walk = math.Clamp(speed / 100, 0, 1) * (sprinting and 2 or 1)
    local lena = speed / 150 * (onGround and 1 or 0.1)
    local huy, prank = t * 6.6, t / 2
    local x, y = cos(huy) * sin(huy) * walk * 1.5, sin(huy) * walk * 1.5
    local px = -sin(huy) * sin(huy) * walk * lena
    local py = -walk * lena - x * 0.25 * lena * 3 + cos(prank) * sin(prank - 2) * cos(prank + 1) - (crouch and 1 or 0)
    local pz = -y * 0.25 * lena + sin(prank) * sin(prank) * cos(prank + 1) * 0.7
    local ease = math.min(step * 8, 1)
    px, py, pz = px + sx, py + sy, pz + sz
    m.pos.x, m.pos.y, m.pos.z = m.pos.x + (px - m.pos.x) * ease, m.pos.y + (py - m.pos.y) * ease, m.pos.z + (pz - m.pos.z) * ease
    m.ang.p = m.ang.p + (-y * 2 * lena + sp - m.ang.p) * ease
    m.ang.y = m.ang.y + (x * 4 * lena + syw - m.ang.y) * ease
    m.ang.r = m.ang.r + (-y * 3 * lena + sr - m.ang.r) * ease
    local oneHand = (which == 7 or which == 8) and not reloading and not sprinting -- setlhik false: the left hand lets go
    m.hand = (m.hand or 0) + ((oneHand and 1 or 0) - (m.hand or 0)) * ease
    m.relax = m.relax + ((sprinting and 0.65 or 0) - m.relax) * ease
    return m
end

-- What a shot does to the gun (owner, 2026-09-21: "draw the bipod rest and recoil shake"). homigrad_base/shared.lua:1986-2011,
-- read from the US1 source: the offsets are zeroed every frame and rebuilt from the time since the last shot, so they can
-- be copied exactly. c(a) = 1.5a^3 - a^2 over a span that grows with the weapon's weight: the gun jumps back, then
-- overshoots forward a little as it settles. Scaled by Primary.Force, the pellet count and animposmul; pistols and
-- weapons with `podkid` also flip up and roll. Runs in replay time, for every ghost; the jitter is seeded from the shot
-- so a paused replay holds still. Left out: the posture cases that double it (hip fire, postures 7 and 8 - not recorded).
local function settle(since, time, heft)
    local span = time * heft
    local a = math.max(1 - since / span, 0)
    return 1.5 * a ^ 3 - a ^ 2
end
local shotRecoil, restPoint, actionCycle, reloadCycle
do -- Keep playback helpers scoped below LuaJIT's 200-local limit.
-- Known event weapon IDs and contiguous equipped intervals prevent an earlier item
-- from animating a replacement, including switching away and back to the same class.
local function weaponWindow(g, clip, index, cs)
    local actor = clip.actors[index]
    if actor and V.WeaponWindow then return V.WeaponWindow(actor, cs) end
    return g.zcGunId, -math.huge, math.huge
end
local function weaponEvent(e, weapon, first, last)
    return weapon and e[1] >= first and e[1] < last
        and (e[7] == nil or e[7] == 0 or e[7] == weapon)
end
function shotRecoil(g, w, clip, cs)
    if w.norecoil then return end
    local index = g.zcIndex
    if not index then
        for i = 1, #clip.actors do if L.ghosts[i] == g then index = i end end
        g.zcIndex = index or 0
    end
    local weapon, first, last = weaponWindow(g, clip, index, cs)
    local shotAt
    local events = clip.events
    for k = V.EvFrom(clip, cs - 150), #events do -- replay_v1 P3: from event 1 for a death clip, as before
        local e = events[k]
        if e[1] > cs then break end
        if e[2] == 1 and e[3] == index and weaponEvent(e, weapon, first, last) then shotAt = e[1] end
    end
    if not shotAt then return end
    local since = (cs - shotAt) / 100
    if since > 1.5 then return end
    local stance = g.zcPosture or 0 -- shared.lua:1988: hip fire from posture 1 and the one-handed postures kick like a pistol
    local mul = (isPistol(g, w) or (stance == 1 and not g.zcAds) or stance == 7 or stance == 8) and 2 or 0.75
    local weight = math.max((w.weight or 1) + (w.addweight or 0), 0.1)
    local heft = math.max(weight - 1, 0.1) * 2 + 2
    local primary = istable(w.Primary) and w.Primary or {}
    local back = settle(since, 0.09 * mul, heft) * 0.15 * mul * math.min((primary.Force2 or primary.Force or 40) / 40, 3) * (w.NumBullet or 1) * 3 * (w.animposmul or 1)
    local spanWide = 0.2 * mul
    local wide = settle(since, spanWide, heft) / spanWide
    local loose = (1 / weight) * (w.NumBullet or 3) / 3 * 0.5
    local sway = math.sin(wide) * loose
    local pos = -(w.AdditionalAng or angle_zero):Forward() * back * 9
    pos.x, pos.y = pos.x - sway, pos.y + sway
    local seed = shotAt * 12.9898
    local grain = 0.07 * wide * loose
    pos.x, pos.y, pos.z = pos.x + math.sin(seed) * grain, pos.y + math.sin(seed * 1.7) * grain, pos.z + math.sin(seed * 2.3) * grain
    local ang = Angle(0, -2 * sway, 0)
    if w.podkid or g.zcPistol then
        local flip = settle(since, 0.05 * mul, heft) * (w.podkid or 1)
        ang.p, ang.y, ang.r = ang.p - 5 * flip, ang.y + 20 * flip, ang.r + 10 * flip
        pos.y = pos.y - flip
    end
    return pos, ang
end

-- A gun rested on its bipod (sample flag 128, SWEP:IsResting). The gamemode pins the hand to the point the bipod was set
-- on: desiredPos = LocalToWorld(-RestPosition - WorldPos, 0, restpos, desiredAng), eased by restlerp (sh_worldmodel.lua:233).
-- The clip does not carry the point; it is found the way SWEP:CanRest finds it - a trace straight down from the hand +
-- RestPosition + BipodOffset - once, when the flag comes up, against the map only (whatever prop it stood on during the
-- round is not there now; then nothing is drawn). PROVISIONAL(2026-09-21, rest point re-derived in the viewer, not recorded, ratify-by: 2026-10-21)
function restPoint(g, w, resting, hand, aim, step, actor, cs, origin)
    if not isvector(w.RestPosition) then return end
    local row -- the recorded bipod point (actor.rest, tenths from the clip origin): right on props too, where the trace below sees only the map
    if resting and actor and actor.rest then
        for _, r in ipairs(actor.rest) do if r[1] <= cs + 10 then row = r else break end end
    end
    if row and g.zcRestRow ~= row then
        g.zcRestRow = row
        g.zcRestAt = LocalToWorld(-(w.BipodOffset or vector_origin), angle_zero, Vector(origin[1] + row[2] / 10, origin[2] + row[3] / 10, origin[3] + row[4] / 10), aim)
    end
    if not resting then g.zcRestRow = nil end
    if resting and not g.zcRestOn and not row then
        g.zcRestAt = nil
        local offset = w.BipodOffset or vector_origin
        local from = LocalToWorld(w.RestPosition + offset, angle_zero, hand, aim)
        local tr = util.TraceLine({start = from + vector_up * 10, endpos = from - vector_up * 30, mask = MASK_SOLID_BRUSHONLY})
        if tr.Hit and not tr.StartSolid then g.zcRestAt = LocalToWorld(-offset, angle_zero, tr.HitPos, aim) end
    end
    g.zcRestOn = resting
    g.zcRest = math.Clamp((g.zcRest or 0) + (resting and g.zcRestAt and 1 or -1) * step * 6, 0, 1)
    if g.zcRest <= 0 or not g.zcRestAt then return end
    return {pos = g.zcRestAt, lerp = g.zcRest, back = -w.RestPosition - (w.WorldPos or WORLD_POS)}
end

-- Melee swings and grenade throws (recorder event kinds 4 and 5; `how` in field 5: 1 primary / high, 2 alternate / low).
-- Both bases animate their hands-rigged model with SWEP:PlayAnim(name, time): the sequence is AnimList[name] (a string, or
-- {sequence, time, ...} on weapon_tpik_base) and the cycle runs 0..1 over `time` - copied here, in replay time.
--   melee   new events carry the native PlayAnim start and stamina-adjusted duration in optional swing metadata.
--           Older events are hit-test ticks, inferred with AttackTime/AnimTime1 (or alternate equivalents).
--   grenade Throw is called at duration minus AnimList[name][6] (weapon_tpik_base:PlayAnim), before the animation ends.
-- Pull-back/cancel events are retained until throw, cancellation or weapon change. Melee blocking remains
-- unrecorded; rendered client acceptance is still required.
local function animOf(w, name)
    local entry = istable(w.AnimList) and w.AnimList[name]
    if istable(entry) then return entry[1], tonumber(entry[2]) end
    return entry, nil
end
function actionCycle(g, w, clip, cs)
    local family, gun = g.zcFamily, g.zcGun
    if family ~= "melee" and family ~= "tpik" then return end
    local index = g.zcIndex
    if not index then
        for i = 1, #clip.actors do if L.ghosts[i] == g then index = i end end
        g.zcIndex = index or 0
    end
    local weapon, first, last = weaponWindow(g, clip, index, cs)
    local kind = family == "melee" and 4 or 5
    local name, from, length, backwards
    local earliest = first
    if family == "melee" and first and first > -math.huge and V.RowsAt then
        -- A weapon can begin its swing between the last old-weapon sample and first new-weapon sample.
        local before, after = V.RowsAt(clip.actors[index], first - 0.001)
        if before and after and after[1] == first and first - before[1] <= 5 then earliest = before[1] end
    end
    local pulledAt, pulledLow, thrownAt, undoneAt -- grenade: the pull-back (event kind 7) holds until the throw, or until it is put away (kind 8)
    -- replay_v1 P3: where the scan may start. V.EvFrom answers 1 for a death clip, so the lower bound only matters in a
    -- round. PROVISIONAL(2026-09-26, assumes no melee swing / lead is over 20 s, ratify-by: 2026-10-10)
    local lower = (earliest and earliest > -math.huge) and earliest or -math.huge
    if family == "melee" then lower = math.max(lower, cs - 2000) end
    local events = clip.events
    for k = V.EvFrom(clip, lower), #events do
        local e = events[k]
        if e[1] - 150 > cs then break end
        if family == "tpik" and e[3] == index and e[1] <= cs and weaponEvent(e, weapon, first, last) then
            if e[2] == 7 then pulledAt, pulledLow = e[1], e[5] == 2 elseif e[2] == 5 then thrownAt = e[1] elseif e[2] == 8 then undoneAt = e[1] end
        end
        local captured = family == "melee" and e.swing ~= nil
        local matches = weaponEvent(e, weapon, first, last)
            or (captured and weapon and e[7] == weapon and e[1] >= earliest and e[1] < last)
        if e[2] == kind and e[3] == index and matches then
            local alt = e[5] == 2
            local anim = alt and "attack2" or "attack"
            local lead, dur
            if captured then
                local data = e.swing
                local duration = istable(data) and data.v == 1 and tonumber(data.duration)
                lead, dur = 0, duration and duration > 0 and duration <= 10 and duration or nil
            elseif family == "melee" then
                lead, dur = alt and (w.Attack2Time or 0.1) or (w.AttackTime or 0.2), alt and (w.AnimTime2 or 0.6) or (w.AnimTime1 or 0.7)
            else
                dur = select(2, animOf(w, anim)) or 0.8
                local entry = istable(w.AnimList) and w.AnimList[anim]
                -- weapon_tpik_base invokes Throw at duration minus the callback adjustment.
                local adjust = istable(entry) and tonumber(entry[6]) or nil
                lead = math.max(0, dur - (adjust or tonumber(w.CallbackTimeAdjust) or 0))
            end
            local start = e[1] - lead * 100
            if captured and start <= cs then
                -- A newer start replaces the previous swing even after the newer animation finishes.
                name, from, length = nil, nil, nil
            end
            if dur and start <= cs and cs <= start + dur * 100 then name, from, length = anim, start, dur end
        end
    end
    if not name and pulledAt and (not thrownAt or pulledAt > thrownAt) then
        -- "pullbackhigh" / "pullbacklow" run once over 1.5 s and the arm then stays cocked (weapon_hg_grenade_tpik.lua:136)
        name, from = pulledLow and "pullbacklow" or "pullbackhigh", pulledAt
        length = select(2, animOf(w, name)) or 1.5
        if undoneAt and undoneAt > pulledAt then
            -- put away: the same sequence run BACKWARDS over 2 s ("revers_pullbackhigh" = {"pullbackhigh", 2, false, true}), then idle
            if cs - undoneAt < 200 then from, length, backwards = undoneAt, 2, true else name, from, length = nil, nil, nil end
        end
    end
    local wanted = name or "idle"
    if g.zcAct ~= wanted or g.zcActFrom ~= from then
        local seq = gun:LookupSequence(animOf(w, wanted) or wanted)
        if seq and seq >= 0 then
            gun:ResetSequence(seq)
            g.zcAct, g.zcActFrom = wanted, from -- retry a missing sequence; don't cache a failed lookup
        else
            g.zcAct = nil
            if V.ImpactPrint and V.ImpactPrint:GetBool() and V.SaidSeq ~= wanted .. gun:GetModel() then -- G1: say why a swing does not play
                V.SaidSeq = wanted .. gun:GetModel()
                MsgN(string.format("[Killcam] %s: sequence %q (%s) missing on %s", tostring(family), tostring(animOf(w, wanted) or wanted), wanted, gun:GetModel()))
            end
        end
    end
    gun:SetPlaybackRate(0)
    local played = name and math.Clamp((cs - from) / (length * 100), 0, 1)
    gun:SetCycle(played and (backwards and 1 - played or played) or (cs / 100 / 10) % 1) -- idle is PlayAnim("idle", 10, true)
    -- killcam_kinds: the rig's bones are read again in the ghost's bone callback (weaponHands -> gun:SetupBones); a cycle set
    -- after an earlier SetupBones this frame must not be served from the bone cache
    gun:InvalidateBoneCache()
    if family == "melee" then
        local swinging = name == "attack" or name == "attack2"
        if swinging and g.zcSwingFrom ~= from and V.ImpactPrint and V.ImpactPrint:GetBool() and not g.zcSwingSaid then
            g.zcSwingSaid = true -- once per ghost: what the owner reads to confirm the swing is driven
            MsgN(string.format("[Killcam] melee: %s swing %s on %s (%.2f s)", tostring(clip.weaponName[weapon] or weapon), tostring(animOf(w, name) or name), gun:GetModel(), length or 0))
        end
        if swinging then g.zcSwingFrom = from end -- the body half of the swing: see V.MeleeGesture
    else
        g.zcSwingFrom = nil
    end
end

-- killcam_kinds (2026-09-25, owner: "melee animations need to be played properly"). Live, a swing is two things: the
-- weapon's hands rig plays AnimList.attack (weapon_melee.lua SWEP:PlayAnim -> GetWM():SetSequence), AND every other player
-- sees the body play ACT_HL2MP_GESTURE_RANGE_ATTACK_SLAM (weapon_melee.lua:1456 / :1565 / :1676, AnimRestartGesture). The
-- replay only ever did the first. A ClientsideModel has no gesture layers (AddLayeredSequence is server-only), so the body
-- half rides the punch overlay: the hidden double plays the gesture, punchOver carries its upper body onto the ghost inside
-- the bone callback, and holdWeapon's arm IK runs after it, so the hands stay on the rig exactly as TPIK keeps them live.
-- The gesture runs at its own length from the swing's start, like AnimRestartGesture(..., true).
-- PROVISIONAL(2026-09-25, not seen in game; the same double technique as the punch, itself provisional, ratify-by: 2026-10-09)
function V.MeleeGesture(g, cs, origin, x, y, z, yaw)
    local from = g.zcSwingFrom
    if not from or cs < from then return end
    local d = g.zcDouble
    if not IsValid(d) or d:GetModel() ~= g:GetModel() then
        if IsValid(d) then d:Remove() end
        d = V.OwnReplayEntity(ClientsideModel(g:GetModel(), RENDERGROUP_OPAQUE))
        if not IsValid(d) then return end
        d:SetNoDraw(true)
        g.zcDouble = d
    end
    local seq = g.zcSwingSeq
    if seq == nil then
        seq = d:SelectWeightedSequence(ACT_HL2MP_GESTURE_RANGE_ATTACK_SLAM)
        if not seq or seq < 0 then seq = d:LookupSequence("range_slam") end
        seq = (seq and seq >= 0) and seq or false
        g.zcSwingSeq = seq
    end
    if not seq then return end
    local length = d:SequenceDuration(seq)
    local t = length > 0 and (cs - from) / (length * 100) or 2
    if t > 1 then return end
    if d:GetSequence() ~= seq then d:ResetSequence(seq) end
    d:SetCycle(math.Clamp(t, 0, 1))
    d:SetPos(Vector(origin[1] + x, origin[2] + y, origin[3] + z))
    d:SetAngles(Angle(0, yaw, 0))
    d:InvalidateBoneCache()
    d:SetupBones() -- the double has no bone callback: safe outside a draw
    g.zcPunching = true
end

-- G1 (killcam_polish, 2026-09-25): firing on a WorldModelFake. The gamemode plays the weapon's fire animation on its
-- fake world model (shared.lua PlayAnim -> sh_worldmodel.lua SetSequence); the replay only ever played idle and reload
-- on it, so guns stood still while they fired. Each recorded shot (event kind 1 by this actor) plays AnimList.fire /
-- shoot, else the model's own "fire" / "shoot" / "fire1" sequence, for that sequence's length; a reload in progress
-- wins. A model with no such sequence is left alone (zcFireSeq false). On V: this file shares the bundle's locals line.
function V.FireCycle(g, w, clip, cs)
    local gun = g.zcGun
    if not w or not w.WorldModelFake or not IsValid(gun) or g.zcReloadFrom then return end
    if g.zcFireSeq == nil then
        local seq = -1
        for _, name in ipairs({animOf(w, "fire") or false, animOf(w, "shoot") or false, "fire", "shoot", "fire1"}) do
            if name then seq = gun:LookupSequence(name) if seq and seq >= 0 then break end end
        end
        g.zcFireSeq = (seq and seq >= 0) and seq or false
        if g.zcFireSeq then g.zcFireLen = math.max(gun:SequenceDuration(g.zcFireSeq), 0.05) end
    end
    if not g.zcFireSeq then return end
    local index = g.zcIndex
    if not index then
        for i = 1, #clip.actors do if L.ghosts[i] == g then index = i end end
        g.zcIndex = index or 0
    end
    local shot
    local weapon, first, last = weaponWindow(g, clip, index, cs) -- G1r: only shots by the weapon in hand then, as shotRecoil
    local events = clip.events
    for k = V.EvFrom(clip, cs - g.zcFireLen * 100), #events do -- replay_v1 P3: from event 1 for a death clip, as before
        local e = events[k]
        if e[1] > cs then break end
        if e[2] == 1 and e[3] == index and cs - e[1] <= g.zcFireLen * 100 and weaponEvent(e, weapon, first, last) then shot = e[1] end
    end
    if shot then
        if g.zcFireFrom ~= shot then g.zcFireFrom = shot gun:ResetSequence(g.zcFireSeq) end
        gun:SetPlaybackRate(0)
        gun:SetCycle(math.Clamp((cs - shot) / (g.zcFireLen * 100), 0, 1))
    elseif g.zcFireFrom then
        g.zcFireFrom = nil
        local idle = gun:LookupSequence(istable(w.AnimList) and w.AnimList.idle or "idle")
        if idle and idle >= 0 then gun:ResetSequence(idle) gun:SetCycle(0) end
    end
end
-- Reloading (sample flag 32). Weapons drawn with a WorldModelFake play AnimList.reload over ReloadTime on that model
-- (sh_reload.lua:456 -> SWEP:PlayAnim), and the replay's hands are copied from the same model's bones, so they follow.
-- The recorded flag run supplies its start even on a seek. Clips do not carry the exact stamina-adjusted duration
-- or initial magazine state yet: ReloadTime and the non-empty sequence remain fallbacks.
function reloadCycle(g, w, cs, reloading, actor)
    local gun = g.zcGun
    if not w.WorldModelFake or not istable(w.AnimList) then return end
    if not reloading then
        if g.zcReloadFrom then
            g.zcReloadFrom = nil
            local idle = gun:LookupSequence(w.AnimList.idle or "base_idle")
            if idle and idle >= 0 then gun:ResetSequence(idle) gun:SetCycle(0) end
        end
        return
    end
    local from = actor and V.ReloadAt and V.ReloadAt(actor, cs)
    from = from or ((not g.zcReloadFrom or cs < g.zcReloadFrom) and cs or g.zcReloadFrom)
    if g.zcReloadFrom ~= from then
        g.zcReloadFrom = from
        local seq = gun:LookupSequence(w.AnimList.reload or w.AnimList.reload_empty or "")
        g.zcReloadSeq = seq and seq >= 0 and seq or nil
        if g.zcReloadSeq then gun:ResetSequence(g.zcReloadSeq) end
    end
    if not g.zcReloadSeq then return end
    local length = math.max(tonumber(w.ReloadTime) or 2, 0.1) * 100
    gun:SetPlaybackRate(0)
    gun:SetCycle(math.Clamp((cs - g.zcReloadFrom) / length, 0, 1))
end

end -- weapon animation helpers

----------------------------------------------------------------- attachments and optics
-- What is fitted to the gun (owner, 2026-09-21: "draw the optics and attachments"). The clip carries names only
-- (actor.att: class -> {placement = name}, sv_clips.lua); everything else is the gamemode's own data, used the way
-- homigrad_base/sh_attachment.lua uses it (read from the US1 source 2026-09-21):
--   * SWEP:DrawAttachments - the model (hg.attachments[place][name][2]), its submaterials ([4]), the parts of the GUN
--     a fitting hides (availableAttachments[place][name][2] / .removehuy), the rail a sight brings with it (.mount)
--   * SWEP:Attachment_Transform - placed from the MUZZLE attachment: the fitting's own offset + the weapon's mount
--     offset + the attachment's offset, turned by [3] + mountAngle
--   * SWEP:GetCameraOverride - with a sight fitted, aiming puts the eye at the sight's offsetView, not at SWEP.ZoomPos
--   * cl_optics.lua "stencil-test-holo2" - a holographic reticle is drawn 2624 units down the barrel, stencilled to a
--     glass-only copy of the sight
-- NOT drawn, loudly: the picture inside a magnified scope (the gamemode renders the world a second time into the lens),
-- lasers and weapon lights (their on/off state is not recorded), per-attachment drawFunction / viewFunction extras.
-- PROVISIONAL(2026-09-21, attachment drawing copied from the gamemode by eye and not yet seen in-game, ratify-by: 2026-10-21)
function strip(g)
    for _, a in ipairs(g.zcAtts or {}) do
        if IsValid(a.model) then a.model:Remove() end
        if IsValid(a.rail) then a.rail:Remove() end
        if IsValid(a.glass) then a.glass:Remove() end
    end
    g.zcAtts, g.zcSight, g.zcMuzzle, g.zcScope, g.zcScopeOn, g.zcScopePos = nil, nil, nil, nil, nil, nil
    g.zcLaserPos, g.zcLaserAng, g.zcLaserData = nil, nil, nil
    if g.zcLamp and g.zcLamp:IsValid() then g.zcLamp:Remove() end
    g.zcLamp = nil
end
local function fitted(list, name) -- the weapon's own entry for this fitting carries its offset; hg.SetAttachment looks it up the same way
    if istable(list) then
        for _, entry in pairs(list) do if istable(entry) and entry[1] == name then return entry end end
    end
    return {name, {}}
end
local function paint(ent, mats)
    if not istable(mats) then return end
    for index, mat in pairs(mats) do if isnumber(index) then ent:SetSubMaterial(index, mat or "null") end end
end
local function prop(path)
    if not isstring(path) or path == "" or not util.IsValidModel(path) then return end
    local model = V.OwnReplayEntity(ClientsideModel(path, RENDERGROUP_OPAQUE))
    if IsValid(model) then model:SetNoDraw(true) return model end
end
-- The magnified picture inside a scope (owner, 2026-09-21: "draw the magnified scope picture"). SWEP:DoRT
-- (homigrad_base/cl_optics.lua:101, read from the US1 source) renders the world a second time into the render target
-- "huy-glass22" and points the lens material at it (an optic's `mat`, effects/arc9/rt; a built-in scope's SWEP.mat). The
-- replay's scope model wears that same material, so filling the same target is all it takes. Replicated from DoRT: the
-- view starts at the sight + localScopePos and looks down the barrel, turned by how far the eye sits off the scope's
-- axis; fov = ZoomFOV / distance-to-eye * 12; the lens goes dark when the eye is too far off axis; the reticle and
-- three layers of scope shadow are painted over the picture. Screen positions are taken in the replay's own view and
-- scaled to the target, which is what DoRT's scrw / ScrW() arithmetic amounts to.
-- NOT known to a clip: the magnification the player had dialled in (mouse wheel, SWEP:ChangeFOV). The weapon's starting
-- ZoomFOV is used, clamped to the scope's range. PROVISIONAL(2026-09-21, zoom level not recorded; copied by eye, not yet seen in-game, ratify-by: 2026-10-21)
local SCOPE_SIZE = 512
-- Every client tells the server what its own scope is dialled to (see sv_net.lua "zckc_zoom"): only while a scoped
-- weapon is held (sizeperekrestie is what SWEP:DoRT itself requires), only on change, 4 times a second at most.
do
    local lastGun, lastFov
    timer.Create("ZCKillcam.ZoomReport", 0.25, 0, function()
        local me = LocalPlayer()
        if not IsValid(me) or not me:Alive() then return end
        local w = me:GetActiveWeapon()
        if not IsValid(w) or not isnumber(w.ZoomFOV) or not w.sizeperekrestie then return end
        local fov = math.Clamp(math.Round(w.ZoomFOV * 10), 5, 1000)
        if w == lastGun and fov == lastFov then return end
        if util.NetworkStringToID("zckc_zoom") == 0 then return end -- the server side is not there (yet)
        lastGun, lastFov = w, fov
        net.Start("zckc_zoom")
        net.WriteUInt(fov, 10)
        net.SendToServer()
    end)
end
local scopeTarget
local function scopeSpec(w, data)
    data = data or {}
    local size = data.sizeperekrestie or (w.dort and w.sizeperekrestie)
    if not size then return end
    local fixed = data.perekrestieSize
    if fixed == nil then fixed = w.perekrestieSize end
    local mat = data.mat or w.mat or Material("huy-glass")
    local reticleMat, shadow = data.perekrestie or w.perekrestie, data.scopemat or w.scopemat
    if not (mat and reticleMat and shadow) then return end
    return {size = size, mat = mat, reticle = reticleMat, shadow = shadow, fixed = fixed, builtin = w.scopedef and true or false,
        at = data.localScopePos or w.localScopePos or vector_origin, blackout = data.scope_blackout or w.scope_blackout or 400,
        rot = data.rot or w.rot or 0, shade = (data.blackoutsize or w.blackoutsize or 2500) * 0.75,
        fov = math.Clamp(w.ZoomFOV or 20, data.FOVMin or w.FOVMin or 3.5, data.FOVMax or w.FOVMax or 10),
        base = w.ZoomFOV or 20, lo = data.FOVMin or w.FOVMin or 3.5, hi = data.FOVMax or w.FOVMax or 10}
end
local function centred(x, y, size, rot) surface.DrawTexturedRectRotated(x, y, size, size, rot or 0) end
-- Where the picture is taken from, and where things fall on the replay's screen. Worked out BEFORE the render target is
-- pushed: inside it the screen size reads as the target's.
local function aimScope(g, spec, origin, angles, fov)
    local barrel = g.zcMuzzle
    local at = Vector(spec.at)
    at:Rotate(barrel)
    local pos = g.zcScopePos + at
    local forward = barrel:Forward()
    local _, point = util.DistanceToLine(origin, origin + forward * 50, pos)
    local off = WorldToLocal(point, angle_zero, pos, angles)
    local mul = 4 * spec.fov / 7 * (spec.builtin and 400 / spec.blackout or 1)
    local look = barrel + Angle(off.z * mul, -off.y * mul, 0)
    local dist = math.max(pos:Distance(origin), 0.1)
    local dir = (pos - origin):GetNormalized()
    local tr = util.TraceLine({start = origin, endpos = pos + dir * 5, mask = MASK_SOLID_BRUSHONLY}) -- never start the picture behind a wall
    local sw, sh = ScrW(), ScrH()
    cam.Start3D(origin, angles, fov)
    local s1, s2, aim = pos:ToScreen(), point:ToScreen(), (origin + forward * 100000):ToScreen()
    cam.End3D()
    return {origin = tr.HitPos - dir * 5, angles = look, fov = math.max(spec.fov, 0.5) / dist * 12, aim = aim, sw = sw, sh = sh,
        dx = (s1.x - s2.x) / sw * SCOPE_SIZE * 2, dy = (s1.y - s2.y) / sh * SCOPE_SIZE * 2}
end
local function paintScope(spec, shot, cs)
    local dx, dy, aim, sw, sh = shot.dx, shot.dy, shot.aim, shot.sw, shot.sh
    render.Clear(1, 1, 1, 255)
    if dx * dx + dy * dy >= 10000 / (spec.blackout / 400) then return end -- the eye is off the scope's axis: a dark lens
    render.RenderView({x = 0, y = 0, w = SCOPE_SIZE, h = SCOPE_SIZE, origin = shot.origin, angles = shot.angles, fov = shot.fov,
        znear = 1, drawviewmodel = false, drawhud = false, dopostprocess = false, bloomtone = false})
    local spread = math.min(15, 1.2 * 2.5 * (15 / spec.fov))
    if math.sqrt(((aim.x - sw / 2) * spread) ^ 2 + ((aim.y - sh / 2) * spread) ^ 2) > 2048 then render.Clear(0, 0, 0, 255) end
    local x, y, half = aim.x * SCOPE_SIZE / sw, aim.y * SCOPE_SIZE / sh, SCOPE_SIZE / 2
    render.PushFilterMin(TEXFILTER.ANISOTROPIC)
    render.PushFilterMag(TEXFILTER.ANISOTROPIC)
    cam.Start2D()
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(spec.reticle)
    centred(x, y, spec.size / (spec.fixed and 4 or spec.fov / 3), spec.rot)
    surface.SetMaterial(spec.shadow)
    surface.SetDrawColor(100, 100, 100)
    centred((SCOPE_SIZE - x - half) * spread + half, (SCOPE_SIZE - y - half) * spread + half, spec.shade * 2 + 512)
    surface.SetDrawColor(0, 0, 0, 255)
    local t = cs / 100 -- replay time: the shadow's slow drift pauses with the replay
    centred(aim.x * math.atan(math.rad(math.cos(t))) * SCOPE_SIZE / sw * spread + half, aim.y * math.atan(math.rad(math.sin(t))) * SCOPE_SIZE / sh * spread + half, spec.shade * 0.75 + 512)
    centred(-dx * 2 * spread + half, -dy * 2 * spread + half, spec.shade * 0.75 + 512)
    cam.End2D()
    render.PopFilterMin()
    render.PopFilterMag()
end
-- Called from RenderScene BEFORE the replay's own view is drawn (a view cannot be rendered from inside another), so it
-- works from where the last frame put the gun. The looking ghost, its gun and what is fitted to it are hidden meanwhile:
-- the picture starts inside the scope (the gamemode does the same with RENDERING_SCOPE).
local function renderScope(g, origin, angles, fov, cs)
    local spec = g.zcScope
    if not (spec and g.zcMuzzle and g.zcScopePos) or not IsValid(g.zcGun) or g.zcGun:GetNoDraw() then return end
    -- what the player had dialled in at this moment of the clip; the weapon's starting zoom when the clip does not say
    local dialled
    for _, z in ipairs(g.zcActor and g.zcActor.zoom or {}) do
        if z[3] == g.zcClass and z[1] <= cs then dialled = z[2] / 10 end
    end
    spec.fov = math.Clamp(dialled or spec.base, spec.lo, spec.hi)
    scopeTarget = scopeTarget or GetRenderTargetEx("huy-glass22", SCOPE_SIZE, SCOPE_SIZE, RT_SIZE_NO_CHANGE, MATERIAL_RT_DEPTH_SHARED, bit.bor(2, 256), 0, IMAGE_FORMAT_BGR888)
    local fine, shot = pcall(aimScope, g, spec, origin, angles, fov)
    if not fine then
        if not L.scopeErr then L.scopeErr = true print("[Killcam] scope: " .. tostring(shot)) end
        g.zcScope = nil
        return
    end
    local body = g:GetNoDraw()
    g:SetNoDraw(true)
    g.zcGun:SetNoDraw(true)
    render.PushRenderTarget(scopeTarget, 0, 0, SCOPE_SIZE, SCOPE_SIZE)
    local clipping = DisableClipping(true)
    scoping = true
    local ok, err = pcall(paintScope, spec, shot, cs)
    scoping = false
    DisableClipping(clipping)
    render.PopRenderTarget()
    g:SetNoDraw(body)
    g.zcGun:SetNoDraw(false)
    if ok then spec.mat:SetTexture("$basetexture", scopeTarget)
    elseif not L.scopeErr then L.scopeErr = true g.zcScope = nil print("[Killcam] scope: " .. tostring(err)) end
end

local function dress(g, actor, class)
    strip(g)
    g.zcActor, g.zcClass = actor, class
    local gun, w = g.zcGun, g.zcWeapon
    local set = istable(actor.att) and actor.att[class] or {}
    if not IsValid(gun) or not w or not (hg and istable(hg.attachments)) then return end
    local available = istable(w.availableAttachments) and w.availableAttachments or {}
    local worn = {}
    for place, name in pairs(set) do
        if istable(hg.attachments[place]) and istable(hg.attachments[place][name]) then worn[place] = fitted(available[place], name) end
    end
    if istable(available.mount) and istable(hg.attachments.mount) then -- the rail under a sight: chosen by the sight's mountType
        local lead = worn.sight and hg.attachments.sight[worn.sight[1]] or worn.underbarrel and hg.attachments.underbarrel[worn.underbarrel[1]]
        local rail = lead and available.mount[lead.mountType]
        worn.mount = istable(rail) and istable(hg.attachments.mount[rail[1]]) and rail or nil
    end
    local atts = {}
    for place, att in pairs(worn) do
        local data, list = hg.attachments[place][att[1]], istable(available[place]) and available[place] or nil
        local hide = list and (istable(list[att[1]]) and list[att[1]][2] or istable(list.removehuy) and (list.removehuy[data.mountType] or list.removehuy)) or nil
        paint(gun, istable(hide) and hide or att[2])
        local model = prop(data[2])
        if model then
            local a = {att = att, data = data, list = list, model = model, place = place}
            paint(model, data[4])
            if data.fScale then model:SetModelScale(data.fScale, 0) end
            if data.bBonemerge then
                model:SetParent(gun)
                model:AddEffects(EF_BONEMERGE)
                a.merged = true
            end
            a.rail = prop(data.mount)
            if data.holotex and data.holo then -- glass only: the reticle is stencilled to it
                a.glass = prop(data[2])
                if a.glass then
                    a.glass:SetSubMaterial(0, "null")
                    a.glass:SetSubMaterial(1, "white")
                    a.glass:SetModelScale(data.modelscale or 1)
                    model:SetSubMaterial(0, "")
                    model:SetSubMaterial(1, "null")
                end
            end
            atts[#atts + 1] = a
        end
    end
    for _, a in ipairs(atts) do
        local spec = a.place == "sight" and not g.zcScope and scopeSpec(w, a.data)
        if spec then g.zcScope, g.zcScopeOn = spec, a end
    end
    if not g.zcScope then g.zcScope = scopeSpec(w) end -- a scope that is part of the weapon (SWEP.dort)
    if #atts > 0 or g.zcScope then g.zcAtts = atts end
end

-- SWEP:GetMuzzleAtt(gun, true) (sh_bullet.lua:458): everything fitted hangs off this point.
local function muzzleOf(gun, w)
    local attPos, attAng = w.attPos or vector_origin, w.attAng or angle_zero
    local id = gun:LookupAttachment(w.WorldModelFake and w.FakeAttachment or "muzzle")
    local att = id and id > 0 and gun:GetAttachment(id) or nil
    if not att then
        id = gun:LookupAttachment("muzzle_flash")
        att = id and id > 0 and gun:GetAttachment(id) or nil
    end
    local pos, ang
    if att then
        pos, ang = LocalToWorld(attPos, attAng, att.Pos, att.Ang)
        ang:RotateAroundAxis(ang:Forward(), w.rotatehuy or 0)
    else
        ang = gun:GetAngles()
        ang:RotateAroundAxis(ang:Forward(), 90)
        -- select(2, ...) rather than `_, ang = ...`: a bare `_` on the left is a GLOBAL write, and muzzleOf runs
        -- every frame for every armed ghost, so it was quietly stamping _G._ over and over and colliding with
        -- anything else on the server that uses `_` as a throwaway. `local _` here is not an option - `ang` is
        -- an outer local and re-declaring it would shadow the one the rest of the function returns.
        ang = select(2, LocalToWorld(vector_origin, attAng, vector_origin, ang))
        pos = gun:GetPos() + ang:Up() * attPos[1] + ang:Right() * attPos[2] + ang:Forward() * attPos[3]
    end
    if w.WorldModelFake then pos, ang = LocalToWorld(w.AttachmentPos or vector_origin, w.AttachmentAng or angle_zero, pos, ang) end
    return pos, ang
end
local function put(ent, pos, ang)
    ent:SetRenderOrigin(pos) ent:SetRenderAngles(ang)
    ent:SetPos(pos) ent:SetAngles(ang)
    ent:SetupBones()
end
-- Runs while the scene is drawn, after the guns have been posed.
local NOATTS = {} -- shared empty list: this is a per-frame path, and `or {}` here would be garbage every frame
function V.DrawWeaponMesh(g)
    local gun, w = g.zcGun, g.zcWeapon
    if not IsValid(gun) or gun:GetNoDraw() or not w or not isstring(w.WorldModelExchange) or w.WorldModelExchange == "" then return end
    local model = g.zcExchange
    if not IsValid(model) then
        if (g.zcExchangeRetry or 0) > RealTime() then return end
        g.zcExchangeRetry = RealTime() + 0.5
        if not util.IsValidModel(w.WorldModelExchange) then return end
        model = V.OwnReplayEntity(ClientsideModel(w.WorldModelExchange, RENDERGROUP_OPAQUE))
        if not IsValid(model) then return end
        model:SetNoDraw(true) -- drawn only by this hook; never left visible after a hidden pose
        model:SetModelScale(w.modelscale or 1, 0)
        g.zcExchange, g.zcExchangeRetry = model, nil
    end
    gun:SetupBones()
    local pos, ang = gun:GetPos(), gun:GetAngles()
    if gun:GetModel() == w.WorldModelReal then
        local matrix = gun:GetBoneMatrix(w.basebone or 1)
]========], 2)
