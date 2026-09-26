-- ============================================================
--  Watchdog module: SILENTAIM  (magic-bullet detection)
-- ------------------------------------------------------------
--  The one aimbot class that leaves the VIEW untouched: the shot
--  direction is rerouted onto a target at fire time while the
--  networked eye angles stay where the player was looking.
--  Server derives both vectors independently, so this is robust.
--
--  Signature: EntityFireBullets.Dir points PRECISELY at an enemy,
--  while the player's EyeAngles are far OFF that same enemy.
--  (Normal spread only deviates a few degrees NEAR the aim vector -
--   it never reroutes 20 deg onto a specific player.)
--  No traces: uses direction dots, so it is cheap.
--  WATCH MODE: dossiers only.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local ONTARGET_SHOT = 0.9990   -- shot dir must lock this precisely onto an enemy (~2.5 deg)
local VIEW_OFF_DEG  = 20       -- ...while the eye is at least this far off that enemy
local NEAR          = 120
local FAR           = 4500
local HIT_SCORE     = 26       -- ~4 magic bullets => dossier
local THRESHOLD     = 100

local COS_VIEW_OFF = math.cos(math.rad(VIEW_OFF_DEG))
local ANG0 = Angle(0, 0, 0)

-- ---- pSilent (usercmd-swap silent aim) knobs: live-tunable, persist ----
-- The OTHER silent-aim class: the cheat swaps the usercmd angles onto the
-- victim for exactly the fire tick, then restores them. At fire time view and
-- shot AGREE (so the Dir-vs-view check above stays quiet), but the view does a
-- one-tick OUT-AND-BACK: big jump out, shot, big jump back landing within a
-- fraction of a degree of where it started. Humans never return to origin in
-- one tick - a real flick stays where it landed. Detected in Sample below.
WD.Config.psSnapDeg   = WD.Config.psSnapDeg   or 25    -- both the out and the back jump must exceed this (deg)
WD.Config.psReturnDeg = WD.Config.psReturnDeg or 4     -- ...and the view must return within this of its origin (deg)
WD.Config.psFireWin   = WD.Config.psFireWin   or 0.12  -- a shot must have fired within this window (s)
WD.Config.psScore     = WD.Config.psScore     or 34    -- score when the middle tick was on a body (half when not)

-- ---- HIT-BASED check (the strongest signature; mechanism-independent) ----
-- Ground truth: a bullet HIT a player. If the shooter's view on the ticks
-- BEFORE the shot was far off the impact point, the hit landed somewhere the
-- shooter never aimed - silent aim, whatever trick produced it. (The fire tick
-- itself can't be trusted: usercmd-swap makes that one tick "look" at the
-- victim.) Legit flicks are on-target for a tick or two before a hit; scoring
-- needs BOTH prior ticks off, and accumulates - one lucky same-tick flick
-- won't dossier, every-shot silent aim will.
WD.Config.psHitOffDeg = WD.Config.psHitOffDeg or 20    -- view must be at least this off the impact, on BOTH prior ticks
WD.Config.psHitScore  = WD.Config.psHitScore  or 34    -- ~3 such hits => dossier

-- diagnostic: wd_debug_silent 1/0 (superadmin) - logs every out-and-back and why it did/didn't score
local DEBUG = false
concommand.Add("wd_debug_silent", function(p, _, a)
	if IsValid(p) and not p:IsSuperAdmin() then return end
	DEBUG = (a[1] == "1" or a[1] == "true")
	print("[wd/silent] debug logging -> " .. tostring(DEBUG))
end, nil, "Superadmin: Watchdog silent-aim debug logging: wd_debug_silent 1|0.")
local function dbg(msg) print("[wd/silent] " .. msg) end

local function psSample(ply, cmd, t)
	local C = WD.Config
	if not t.prev2 then return end
	if t.jump < C.psSnapDeg or (t.jumpPrev or 0) < C.psSnapDeg then return end
	if not t.latStable then return end
	local ex, reason = WD.Excused(ply, "view")
	if ex then
		if DEBUG then dbg(string.format("%s: out-and-back ignored - excused (%s)", ply:Nick(), reason)) end
		return
	end

	-- did the view RETURN to (nearly) where it was two ticks ago?
	local rp = math.AngleDifference(t.ang.p, t.prev2.p)
	local ry = math.AngleDifference(t.ang.y, t.prev2.y)
	local returnDeg = math.sqrt(rp * rp + ry * ry)
	if returnDeg > C.psReturnDeg then
		if DEBUG then dbg(string.format("%s: out %.0f back %.0f but returned %.1f off origin (need <%.1f) - flail, not psilent", ply:Nick(), t.jumpPrev, t.jump, returnDeg, C.psReturnDeg)) end
		return
	end

	-- a shot must have gone out around the middle (aimed) tick
	local f = WD._lastFire[ply:SteamID()]
	if not (f and (CurTime() - f) <= C.psFireWin) then
		if DEBUG then dbg(string.format("%s: out-and-back (return %.2f) but NO shot within %.2fs - not scored", ply:Nick(), returnDeg, C.psFireWin)) end
		return
	end

	-- was the middle (aimed) tick pointing at a player's body? (names the victim)
	local eye = ply:EyePos()
	local dirMid = t.prev:Forward()
	local far = C.aimFarDist or 4000
	local m = C.aimHullMargin or 18
	local victim, vdist
	for _, other in player.Iterator() do
		if other ~= ply and IsValid(other) and other:Alive() and other:Team() ~= TEAM_SPECTATOR then
			local d = other:WorldSpaceCenter():Distance(eye)
			if d > 60 and d < far then
				if util.IntersectRayWithOBB(eye, dirMid * far, other:GetPos(), ANG0,
					other:OBBMins() - Vector(m, m, m), other:OBBMaxs() + Vector(m, m, m)) then
					victim, vdist = other, math.Round(d)
					break
				end
			end
		end
	end

	local score = victim and C.psScore or math.floor(C.psScore / 2)
	WD.AddSuspicion(ply, "silentaim", score, {
		note = victim and "psilent out-and-back onto body" or "psilent out-and-back (no confirmed body)",
		outDeg = math.Round(t.jumpPrev, 1), backDeg = math.Round(t.jump, 1),
		returnDeg = math.Round(returnDeg, 2),
		target = victim and victim:Nick() or "unconfirmed", dist = vdist or 0,
		weapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "?",
	})
	if DEBUG then dbg(string.format("%s: SCORED psilent - out %.0f / back %.0f / return %.2f, shot fired, %s (+%d, need 100)",
		ply:Nick(), t.jumpPrev, t.jump, returnDeg,
		victim and ("victim " .. victim:Nick() .. " @" .. vdist .. "u") or "no confirmed victim", score)) end
end

hook.Add("EntityFireBullets", "WD_SilentAim", function(ent, data)
	if not WD.Config.enabled or not WD.ModuleEnabled("silentaim") then return end
	-- ZCity's lua-bullet weapons raise this hook with the WEAPON as `ent`
	-- (hook.Run("EntityFireBullets", self, ...)), so resolve the shooter.
	local ply = (IsValid(ent) and ent:IsPlayer()) and ent
		or (IsValid(data.Attacker) and data.Attacker:IsPlayer() and data.Attacker)
		or (IsValid(ent) and ent.GetOwner and ent:GetOwner())
	if not (IsValid(ply) and ply:IsPlayer()) then return end
	if not ply:Alive() then return end
	if WD.IsExempt(ply) then return end
	if not WD.LatencyStable(ply) then return end
	local ex = WD.Excused(ply, "fire")
	if ex then return end

	local dir = data.Dir
	if not dir then return end
	dir = Vector(dir.x, dir.y, dir.z)
	dir:Normalize()

	local eye = ply:EyePos()
	local aim = ply:EyeAngles():Forward()   -- authoritative networked view
	local src = data.Src or eye

	for _, other in player.Iterator() do
		if other ~= ply and IsValid(other) and other:Alive() and other:Team() ~= TEAM_SPECTATOR then
			local toShot = other:WorldSpaceCenter() - src
			local dist = toShot:Length()
			if dist > NEAR and dist < FAR then
				toShot:Normalize()
				-- shot locked precisely onto this enemy?
				if dir:Dot(toShot) > ONTARGET_SHOT then
					-- was the VIEW pointed well away from that same enemy?
					local toView = other:WorldSpaceCenter() - eye
					toView:Normalize()
					if aim:Dot(toView) < COS_VIEW_OFF then
						local offDeg = math.deg(math.acos(math.Clamp(aim:Dot(toView), -1, 1)))
						WD.AddSuspicion(ply, "silentaim", HIT_SCORE, {
							target = other:Nick(),
							dist = math.Round(dist),
							viewOffDeg = math.Round(offDeg, 1),
							weapon = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or "?",
							eyeAng = tostring(ply:EyeAngles()),
							shotDir = tostring(dir),
						})
						break
					end
				end
			end
		end
	end
end)

-- ---- HIT-BASED: bullet lands on a player the shooter's view never pointed at ----
hook.Add("EntityTakeDamage", "WD_SilentAim_Hit", function(victim, dmg)
	if not WD.Config.enabled or not WD.ModuleEnabled("silentaim") then return end
	if not (IsValid(victim) and victim:IsPlayer()) then return end
	local att = dmg:GetAttacker()
	if not (IsValid(att) and att:IsPlayer()) or att == victim then return end
	if att:IsBot() then return end
	if WD.IsExempt(att) then return end

	-- bullet-ish damage only: engine bullet flags, or homigrad's custom damage
	-- pipeline right after the attacker demonstrably fired
	local bullety = dmg:IsBulletDamage() or dmg:IsDamageType(DMG_BUCKSHOT) or WD.RecentFire(att, 0.15)
	if not bullety then return end

	if not WD.LatencyStable(att) then return end
	local ex, reason = WD.Excused(att, "fire")   -- shooter KO/fakeragdoll/stun/vehicle/viewpunch
	if ex then
		if DEBUG then dbg(string.format("%s hit %s - not judged, shooter excused (%s)", att:Nick(), victim:Nick(), reason)) end
		return
	end

	local t = WD.track[att:SteamID()]
	if not (t and t.prev and t.prev2) then return end

	local eye = att:EyePos()
	local hitpos = dmg:GetDamagePosition()
	if not hitpos or hitpos:IsZero() then hitpos = victim:WorldSpaceCenter() end
	local to = hitpos - eye
	local dist = to:Length()
	if dist < 60 then return end   -- point-blank: angles are meaningless
	to:Normalize()

	local offPrev  = math.deg(math.acos(math.Clamp(t.prev:Forward():Dot(to), -1, 1)))
	local offPrev2 = math.deg(math.acos(math.Clamp(t.prev2:Forward():Dot(to), -1, 1)))
	local need = WD.Config.psHitOffDeg

	if offPrev >= need and offPrev2 >= need then
		WD.AddSuspicion(att, "silentaim", WD.Config.psHitScore, {
			note = "bullet hit a player the view never pointed at (silent aim)",
			target = victim:Nick(), dist = math.Round(dist),
			viewOffT1 = math.Round(offPrev, 1), viewOffT2 = math.Round(offPrev2, 1),
			weapon = IsValid(att:GetActiveWeapon()) and att:GetActiveWeapon():GetClass() or "?",
		})
		if DEBUG then dbg(string.format("%s: SCORED hit on %s @%du - view was %.1f / %.1f deg off on the two ticks before the shot (need >=%d on both) (+%d, need 100)",
			att:Nick(), victim:Nick(), math.Round(dist), offPrev, offPrev2, need, WD.Config.psHitScore)) end
	elseif DEBUG then
		dbg(string.format("%s hit %s @%du - legit (view %.1f / %.1f deg off on prior ticks, need >=%d on both to flag)",
			att:Nick(), victim:Nick(), math.Round(dist), offPrev, offPrev2, need))
	end
end)

WD.RegisterModule("silentaim", {
	threshold = THRESHOLD,
	decay = 0.4,
	desc = "silent aim: hit-vs-view truth + reroute + psilent out-and-back",
	Sample = psSample,
})
