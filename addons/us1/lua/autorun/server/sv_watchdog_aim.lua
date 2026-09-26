-- ============================================================
--  Watchdog module: AIM  (snap-onto-target detection)
-- ------------------------------------------------------------
--  The aimbot signature: a LARGE one-tick view jump that LANDS
--  precisely on a player it was NOT already tracking, repeatedly.
--  Uses the core's shared per-tick track + excuse + latency gate,
--  so every ZCity forced-camera state is subtracted upstream.
--  WATCH MODE: dossiers only.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

-- snap magnitude / landing tolerance / target range all moved to WD.Config
-- (live-tunable via wd_config or the panel's AIM TUNING group), below.
local THRESHOLD    = 100       -- dossier fires at this score
local ANG0         = Angle(0, 0, 0)  -- player hulls are world-axis-aligned

-- Live-tunable via wd_config (persists to config.json). Defaults are LOOSE so
-- detection catches reliably; tighten later if real play ever false-positives.
--   wd_config aimConeDeg 6       tighter landing cone (deg)
--   wd_config aimSnapDeg 40      require a bigger snap (deg)
--   wd_config aimFireFollow 1    shorter snap->shoot window (s)
--   wd_config aimHullMargin 10   less hull slop (units)
--   wd_config aimRecentFire 2.5  shorter shoot->snap window (s)
WD.Config.aimSnapDeg    = WD.Config.aimSnapDeg    or 25    -- one-tick view jump that counts as a snap (deg)
WD.Config.aimConeDeg    = WD.Config.aimConeDeg    or 12    -- center-cone landing tolerance, backstop to the hull test (deg)
WD.Config.aimHullMargin = WD.Config.aimHullMargin or 18    -- target hull inflation for "on body" (units)
WD.Config.aimFireFollow = WD.Config.aimFireFollow or 2.0   -- a snap scores if a shot follows within this (s)
WD.Config.aimRecentFire = WD.Config.aimRecentFire or 3.5   -- ...or if a shot happened within this before it (s)
WD.Config.aimNearDist   = WD.Config.aimNearDist   or 150   -- ignore targets closer than this (point-blank brawls FP-storm)
WD.Config.aimFarDist    = WD.Config.aimFarDist    or 4000  -- ignore targets beyond this
WD.Config.aimHitScore   = WD.Config.aimHitScore   or 12    -- suspicion per confirmed snap (vs threshold 100: 12=~8-9 snaps, 25=4, 50=2)

-- ---- diagnostic (superadmin, runtime-only, never persisted / networked) ----
-- `wd_debug_aim 1` logs, for EVERY 35°+ snap, exactly which gate stopped it from
-- scoring (or that it scored) - the fastest way to see why a test aimbot isn't
-- tripping. `wd_debug_aim 0` to stop. Safe to leave loaded; off by default.
local DEBUG = false
concommand.Add("wd_debug_aim", function(p, _, a)
	if IsValid(p) and not p:IsSuperAdmin() then return end
	DEBUG = (a[1] == "1" or a[1] == "true")
	print("[wd/aim] debug logging -> " .. tostring(DEBUG))
end, nil, "Superadmin: Watchdog aim-module debug logging: wd_debug_aim 1|0.")
local function dbg(msg) print("[wd/aim] " .. msg) end

-- Did the aim ray from `eye` along `dir` land on `other`'s body? True if it
-- passes through the (inflated) body hull OR falls within the loose center-cone.
-- Hull-first means head/limb aim counts as a hit at any range; the cone is the
-- backstop. Both tolerances are live-tunable (aimHullMargin / aimConeDeg).
local function onBody(eye, dir, other)
	local m = WD.Config.aimHullMargin
	local hit = util.IntersectRayWithOBB(eye, dir * WD.Config.aimFarDist, other:GetPos(), ANG0,
		other:OBBMins() - Vector(m, m, m), other:OBBMaxs() + Vector(m, m, m))
	if hit then return true end
	local to = (other:WorldSpaceCenter() - eye):GetNormalized()
	return dir:Dot(to) > math.cos(math.rad(WD.Config.aimConeDeg))
end

local function sample(ply, cmd, t)
	if t.jump < WD.Config.aimSnapDeg then return end   -- no snap-sized jump this tick
	if not t.latStable then
		if DEBUG then dbg(string.format("%s: %.0f snap ignored - latency unstable (ping %d)", ply:Nick(), t.jump, ply:Ping())) end
		return
	end
	local ex, reason = WD.Excused(ply, "view")
	if ex then
		if DEBUG then dbg(string.format("%s: %.0f snap ignored - excused (%s)", ply:Nick(), t.jump, reason)) end
		return
	end

	local eye     = ply:EyePos()
	local dirNow  = t.ang:Forward()
	local dirPrev = t.prev:Forward()
	local firing  = WD.RecentFire(ply, WD.Config.aimRecentFire) or bit.band(t.buttons, IN_ATTACK) ~= 0

	-- find a target the snap LANDED ON this tick but was OFF the tick before
	local NEARc, FARc = WD.Config.aimNearDist, WD.Config.aimFarDist
	local landed, landedDist
	local nTargets, bestDot, bestNick, bestDist = 0, -1, "none", 0
	for _, other in player.Iterator() do
		if other ~= ply and IsValid(other) and other:Alive() and other:Team() ~= TEAM_SPECTATOR then
			local to = other:WorldSpaceCenter() - eye
			local dist = to:Length()
			if dist > NEARc and dist < FARc then
				nTargets = nTargets + 1
				local d = dirNow:Dot(to:GetNormalized())
				if d > bestDot then bestDot, bestNick, bestDist = d, other:Nick(), math.Round(dist) end
				if onBody(eye, dirNow, other) and not onBody(eye, dirPrev, other) then
					landed, landedDist = other, math.Round(dist)
					break
				end
			end
		end
	end

	if landed then
		if firing then
			WD.AddSuspicion(ply, "aim", WD.Config.aimHitScore, {
				jump = math.Round(t.jump, 1), target = landed:Nick(), dist = landedDist,
				from = tostring(t.prev), to = tostring(t.ang), latency = ply:Ping(),
			})
			t.pendSnap = nil
			if DEBUG then dbg(string.format("%s: SCORED snap onto %s @%du (+%d, need %d)", ply:Nick(), landed:Nick(), landedDist, WD.Config.aimHitScore, THRESHOLD)) end
		else
			-- snapped onto a body but not shooting yet: hold it for a follow-up shot
			t.pendSnap = { target = landed, jump = math.Round(t.jump, 1), dist = landedDist,
				from = tostring(t.prev), to = tostring(t.ang), time = CurTime() }
			if DEBUG then dbg(string.format("%s: %.0f snap ONTO %s @%du - held %.1fs for a follow-up shot", ply:Nick(), t.jump, landed:Nick(), landedDist, WD.Config.aimFireFollow)) end
		end
		return
	end

	if DEBUG then
		if nTargets == 0 then
			-- name every nearby player and the exact reason they were excluded
			local why = {}
			for _, other in player.Iterator() do
				if other ~= ply and IsValid(other) then
					local d = math.Round(other:WorldSpaceCenter():Distance(eye))
					local r
					if not other:Alive() then r = "dead"
					elseif other:Team() == TEAM_SPECTATOR then r = "spectator"
					elseif d <= NEARc then r = "TOO CLOSE (min " .. NEARc .. "u - back up or lower aimNearDist)"
					elseif d >= FARc then r = "too far (max " .. FARc .. "u)"
					end
					if r then why[#why + 1] = string.format("%s @%du: %s", other:Nick(), d, r) end
				end
			end
			dbg(string.format("%s: %.0f snap ignored - 0 valid targets. %s", ply:Nick(), t.jump,
				#why > 0 and table.concat(why, " | ") or "(no other players on the server at all)"))
		else
			dbg(string.format("%s: %.0f snap did NOT land on a body - closest %s @%du (center %.1f off; cone %d deg + %du hull)",
				ply:Nick(), t.jump, bestNick, bestDist,
				math.deg(math.acos(math.Clamp(bestDot, -1, 1))), WD.Config.aimConeDeg, WD.Config.aimHullMargin))
		end
	end
end

-- snap-then-shoot: a snap onto a body that wasn't firing yet is held on the
-- track; if a shot follows within aimFireFollow seconds, it scores here. Covers
-- aimbots that snap-then-click (the fire lands a tick or two after acquisition).
hook.Add("EntityFireBullets", "WD_Aim_FireFollow", function(ent, data)
	if not WD.Config.enabled or not WD.ModuleEnabled("aim") then return end
	local ply = (IsValid(ent) and ent:IsPlayer()) and ent
		or (data and IsValid(data.Attacker) and data.Attacker:IsPlayer() and data.Attacker)
		or (IsValid(ent) and ent.GetOwner and ent:GetOwner())
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	if WD.IsExempt(ply) then return end
	local t = WD.track[ply:SteamID()]
	if not t or not t.pendSnap then return end
	local ps = t.pendSnap
	t.pendSnap = nil
	if not IsValid(ps.target) or (CurTime() - ps.time) > WD.Config.aimFireFollow then return end
	WD.AddSuspicion(ply, "aim", WD.Config.aimHitScore, {
		jump = ps.jump, target = ps.target:Nick(), dist = ps.dist,
		from = ps.from, to = ps.to, latency = ply:Ping(), note = "snap-then-fire",
	})
	if DEBUG then dbg(string.format("%s: SCORED snap-then-fire onto %s @%du (+%d, need %d)", ply:Nick(), ps.target:Nick(), ps.dist, WD.Config.aimHitScore, THRESHOLD)) end
end)

WD.RegisterModule("aim", {
	threshold = THRESHOLD,
	decay = 0.5,
	desc = "snap-onto-target, homigrad-aware",
	Sample = sample,
})
