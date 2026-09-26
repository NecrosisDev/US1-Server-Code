-- ============================================================
--  ZC TEMP V - burn the Homelander out (HnS attrition system)
-- ------------------------------------------------------------
--  Joey's design: Temp V vials spawn around the map at roundstart.
--  Inject one and for a while YOUR damage actually hurts Homelander
--  - not his organism (homelander_zcity_fix's keep-alive resets that
--  4x/s and its ETD hook zeroes all damage), but a parallel VITALITY
--  pool this addon owns. Our ETD hook runs at priority -2, BEFORE
--  the fix's block, reads the raw damage from Temp-V-active
--  attackers and drains the pool; the fix still zeroes the organism
--  application afterward (good - no fight with the keep-alive).
--
--  THE VIAL (prop_physics, glowing blue, big client marker): E to
--  take -> you carry a Temp V syringe (weapon_tempv). Injecting:
--   * super strength: your damage vs Homelander drains vitality
--     (punch/any-damage x zc_tempv_dmgmul)
--   * speed boost (Move-hook, engine-level like the jugg cap)
--   * 30% roll (zc_tempv_laserchance, private Park-Miller RNG):
--     HEAT VISION - a neutered "homelander swep": weapon_tempv_laser,
--     LASER EYES ONLY (no grab/flight/punch/invuln). Hold RMB: 0.1s
--     eye-trace, big flat vitality drain vs Homelander, light burn
--     damage vs anyone else (friendly fire is on - it's Temp V).
--   * expiry CRASH: syringe high ends - stamina gutted + pain for
--     zc_tempv_crashtime; zc_tempv_crash_lethal 1 = the V kills you.
--
--  REGEN: vitality recovers after zc_tempv_regendelay without drain
--  (zc_tempv_regen/s) - solo whittling loses; grouped pushes win.
--
--  BURNOUT (vitality 0): announce + STRIP weapon_homelander (laser/
--  grab/stomp/invuln/keep-alive in the fix all gate on HOLDING it -
--  they die at once) AND clear the CRUSHER layer the mode granted at
--  spawn (give_crusher, sv_homelanderhns:185): organism.superfighter
--  nil, CrusherNoLimbLoss nil, zb_is_crusher false, SubRole nil,
--  MaxHealth 100 (remove_crusher semantics, applied directly - per
--  Joey). He is a mortal in a cape: anyone can hurt him, the pin
--  execution is the natural finisher. A watcher re-strips if he
--  somehow re-acquires the SWEP.
--
--  Publishes ZCTEMPV.vit / .vitmax / .burned / .vials for the
--  zc_homelander_pin v2.1 panel broadcast. Serverside core =
--  hotloadable; the two weapon files + client markers ride restarts.
-- ============================================================
if not SERVER then return end

ZCTEMPV = ZCTEMPV or {}

local cv_on          = CreateConVar("zc_tempv_enabled", "1", FCVAR_ARCHIVE, "Temp V attrition system master toggle", 0, 1)
local cv_vitality    = CreateConVar("zc_tempv_vitality", "1500", FCVAR_ARCHIVE, "Homelander vitality pool", 100, 100000)
local cv_vials       = CreateConVar("zc_tempv_vials", "5", FCVAR_ARCHIVE, "Vials spawned at roundstart", 0, 16)
local cv_dur         = CreateConVar("zc_tempv_duration", "40", FCVAR_ARCHIVE, "Seconds Temp V lasts per injection", 5, 300)
local cv_dmgmul      = CreateConVar("zc_tempv_dmgmul", "10", FCVAR_ARCHIVE, "Temp-V attacker damage x this drains vitality", 0, 100)
local cv_laserchance = CreateConVar("zc_tempv_laserchance", "30", FCVAR_ARCHIVE, "% chance an injection grants HEAT VISION", 0, 100)
local cv_laserdrain  = CreateConVar("zc_tempv_laserdrain", "9", FCVAR_ARCHIVE, "Vitality drained per 0.1s laser tick on Homelander (90/s)", 0, 500)
local cv_laserpvp    = CreateConVar("zc_tempv_laserpvp", "4", FCVAR_ARCHIVE, "Burn damage per laser tick vs non-Homelander players (0 = off)", 0, 100)
local cv_speed       = CreateConVar("zc_tempv_speed", "1.25", FCVAR_ARCHIVE, "Movement speed multiplier while on Temp V", 1, 3)
local cv_regen       = CreateConVar("zc_tempv_regen", "10", FCVAR_ARCHIVE, "Vitality regen per second after the delay", 0, 500)
local cv_regendelay  = CreateConVar("zc_tempv_regendelay", "10", FCVAR_ARCHIVE, "Seconds without Temp-V damage before vitality regens", 0, 120)
local cv_crashtime   = CreateConVar("zc_tempv_crashtime", "15", FCVAR_ARCHIVE, "Seconds the post-V crash debuff lasts", 0, 60)
local cv_crashlethal = CreateConVar("zc_tempv_crash_lethal", "0", FCVAR_ARCHIVE, "1 = the Temp V crash kills the user", 0, 1)
-- v1.1 (Joey's playtest additions)
local cv_respawn     = CreateConVar("zc_tempv_respawn", "20", FCVAR_ARCHIVE, "Seconds between replacement vial spawns while below the vial cap (0 = one wave only)", 0, 300)
-- v1.3: mob knockdown
local cv_kd          = CreateConVar("zc_tempv_knockdown", "1", FCVAR_ARCHIVE, "Multiple Temp-V attackers can knock Homelander down", 0, 1)
local cv_kd_attackers = CreateConVar("zc_tempv_kd_attackers", "2", FCVAR_ARCHIVE, "Distinct Temp-V attackers needed within the window", 2, 10)
local cv_kd_window   = CreateConVar("zc_tempv_kd_window", "2", FCVAR_ARCHIVE, "Seconds their hits must land within", 0.5, 10)
local cv_kd_cd       = CreateConVar("zc_tempv_kd_cd", "12", FCVAR_ARCHIVE, "Cooldown between mob knockdowns (seconds)", 0, 120)
local cv_kd_floor    = CreateConVar("zc_tempv_kd_floor", "2", FCVAR_ARCHIVE, "Seconds he cannot get back up after a knockdown", 0, 10)
local cv_punchmul    = CreateConVar("zc_tempv_punchmul", "3", FCVAR_ARCHIVE, "Bare-hands damage multiplier vs everyone (not HL - his drain uses dmgmul) while on Temp V", 1, 20)
local cv_stamina     = CreateConVar("zc_tempv_stamina", "3", FCVAR_ARCHIVE, "Stamina range multiplier while on Temp V", 1, 10)
-- v1.4: SUPERFIGHTER PHYSIOLOGY while dosed (per Joey)
local cv_sf          = CreateConVar("zc_tempv_superfighter", "1", FCVAR_ARCHIVE, "Temp V grants the superfighter organism (no wounds/bleed/KO - engine HP pool instead)", 0, 1)
local cv_sf_hp       = CreateConVar("zc_tempv_hp", "200", FCVAR_ARCHIVE, "Engine HP pool while on superfighter Temp V", 25, 2000)
local cv_sf_arcade   = CreateConVar("zc_tempv_sf_arcade", "1", FCVAR_ARCHIVE, "1 = full superfighter (arcade accel/jump - the V high). 0 = jugg-style flicker: same immunity, normal homigrad movement", 0, 1)

local LASER_SND = "homelander/laser.wav"

util.AddNetworkString("zc_tempv_state")

-- private RNG (Park-Miller - the exact-in-doubles one)
local seedState = (math.floor(SysTime() * 1000) % 2147483646) + 1
local function rnd(n)
	seedState = (seedState * 16807) % 2147483647
	return math.floor(seedState / 2147483647 * n) + 1
end

local function hnsRound()
	return zb and zb.CROUND == "homelanderhns"
end

local function hlPlayer()
	local mode = zb and zb.modes and zb.modes["homelanderhns"]
	local hl = mode and mode.HomelanderPlayer
	return IsValid(hl) and hl or nil
end

-- resolve a damaged entity to the Homelander (himself or his ragdoll)
local function isHLTarget(ent)
	local hl = hlPlayer()
	if not hl then return nil end
	if ent == hl then return hl end
	if IsValid(ent) and not ent:IsPlayer() then
		local org = ent.organism
		if (org and org.owner == hl) or ent.ply == hl then return hl end
	end
	return nil
end

local function onV(ply)
	return IsValid(ply) and (ply.zc_tempv or 0) > CurTime()
end

-- ---- v1.3 MOB KNOCKDOWN: two or more Temp-V attackers landing hits
--      inside the window bring him down (hg.Fake - the fix's own grab
--      idiom), and the Should Fake Up hook keeps him floored for
--      zc_tempv_kd_floor seconds. The knockdown is the choke/nail
--      window the pin system feeds on. ----
local function tryKnockdown()
	if not cv_kd:GetBool() then return end
	if (ZCTEMPV.kdCD or 0) > CurTime() then return end
	local hl = hlPlayer()
	if not hl or not hl:Alive() or IsValid(hl.FakeRagdoll) then return end
	local n, now = 0, CurTime()
	for p, t in pairs(ZCTEMPV.hitters or {}) do
		if IsValid(p) and (now - t) <= cv_kd_window:GetFloat() then
			n = n + 1
		elseif not IsValid(p) or (now - t) > 30 then
			ZCTEMPV.hitters[p] = nil
		end
	end
	if n < cv_kd_attackers:GetInt() then return end
	ZCTEMPV.kdCD = now + cv_kd_cd:GetFloat()
	hl.zc_floorUntil = now + cv_kd_floor:GetFloat()
	if hg and hg.Fake then pcall(hg.Fake, hl) end
	PrintMessage(HUD_PRINTTALK, "[HnS] THE MOB BRINGS HIM DOWN - Homelander is on the ground!")
end

hook.Add("Should Fake Up", "zc_tempv_floor", function(ply)
	if (ply.zc_floorUntil or 0) > CurTime() then return false end
end)

-- ---- vitality ----
local function drain(amount, attacker)
	if not ZCTEMPV.vit or ZCTEMPV.burned then return end
	ZCTEMPV.lastDrain = CurTime()
	ZCTEMPV.vit = math.max(0, ZCTEMPV.vit - amount)
	if IsValid(attacker) then
		ZCTEMPV.hitters = ZCTEMPV.hitters or {}
		ZCTEMPV.hitters[attacker] = CurTime()
		tryKnockdown()
	end
	if ZCTEMPV.vit <= 0 then ZCTEMPV.Burnout() end
end

function ZCTEMPV.Burnout()
	if ZCTEMPV.burned then return end
	ZCTEMPV.burned = true
	local hl = hlPlayer()
	PrintMessage(HUD_PRINTTALK, "[HnS] THE V IS BURNED OUT OF HIM - Homelander is MORTAL. Take him down!")
	if not IsValid(hl) then return end

	-- strip the SWEP: every fix power (laser/grab/stomp/invuln/keep-alive)
	-- gates on HOLDING weapon_homelander - they all die right here
	if hl:HasWeapon("weapon_homelander") then hl:StripWeapon("weapon_homelander") end
	if hl:HasWeapon("weapon_hands_sh") then hl:SelectWeapon("weapon_hands_sh") end

	-- clear the crusher layer the mode granted (remove_crusher semantics,
	-- applied directly to the entity - no nickname console round-trip)
	hl.SubRole = nil
	hl:SetNWBool("zb_is_crusher", false)
	hl.CrusherNoLimbLoss = nil
	if hl.organism then hl.organism.superfighter = nil end
	hl:SetMaxHealth(100)
	if hl:Health() > 100 then hl:SetHealth(100) end

	-- v1.1: the SWEP's laser loop survives the strip as an orphaned
	-- sound - kill it explicitly (x3: looping wav can stack instances)
	hl:StopSound(LASER_SND)
	hl:StopSound(LASER_SND)
	hl:StopSound(LASER_SND)

	pcall(function() hl:EmitSound("homelander/voice_line2.wav", 100, 95) end)
	if hl.ChatPrint then hl:ChatPrint("[Temp V] Your powers are gone. RUN.") end
end

-- ---- vial spawns ----
local function vialList()
	local out = {}
	for _, e in ipairs(ents.FindByClass("prop_physics")) do
		if IsValid(e) and e:GetNWBool("zc_vial") then out[#out + 1] = e end
	end
	return out
end

local function collectPoints()
	local points = {}
	if zb and zb.GetMapPoints then
		for _, grp in ipairs({ "HMCD_CRI_CT", "HMCD_CRI_T" }) do
			local pts = zb.GetMapPoints(grp)
			if istable(pts) then
				for _, p in ipairs(pts) do points[#points + 1] = p.pos end
			end
		end
	end
	if #points == 0 then -- fallback: engine spawn points
		for _, e in ipairs(ents.FindByClass("info_player_start")) do
			points[#points + 1] = e:GetPos()
		end
	end
	return points
end

local function spawnOne(pos)
	local vial = ents.Create("prop_physics")
	if not IsValid(vial) then return end
	vial:SetModel("models/healthvial.mdl")
	vial:SetPos(pos + Vector(0, 0, 16))
	vial:Spawn()
	vial:SetModelScale(1.8, 0)
	vial:SetColor(Color(70, 130, 255))
	vial:SetNWBool("zc_vial", true)
	vial.zc_isVial = true
	local ph = vial:GetPhysicsObject()
	if IsValid(ph) then ph:EnableMotion(false) end
	vial:DropToFloor()
	return vial
end

local function spawnVials()
	local points = collectPoints()
	if #points == 0 then
		print("[Temp V] no spawn points found - no vials this round")
		return
	end
	-- shuffle (private RNG), place the wave, keep the list for the drip
	for i = #points, 2, -1 do
		local j = rnd(i)
		points[i], points[j] = points[j], points[i]
	end
	ZCTEMPV.points = points
	local n = math.min(cv_vials:GetInt(), #points)
	for i = 1, n do
		spawnOne(points[i])
	end
	PrintMessage(HUD_PRINTTALK, "[HnS] " .. n .. " vials of TEMP V are out there. Find them. Fight back.")
end

-- pickup: E on a vial -> carry the syringe (Homelander can't)
hook.Add("PlayerUse", "zc_tempv_pickup", function(ply, ent)
	if not IsValid(ent) or not ent.zc_isVial or ent.zc_taken then return end
	if not IsValid(ply) or not ply:Alive() then return end
	if ply == hlPlayer() then
		ply:ChatPrint("[Temp V] You don't need it. You ARE the V.")
		return
	end
	if ply:HasWeapon("weapon_tempv") then
		ply:ChatPrint("[Temp V] You're already carrying a dose.")
		return
	end
	ent.zc_taken = true
	ent:Remove()
	ply:Give("weapon_tempv")
	ply:SelectWeapon("weapon_tempv")
	ply:EmitSound("items/ammo_pickup.wav", 70, 110)
	ply:ChatPrint("[Temp V] Dose acquired. Fire to inject - there's no going back.")
end)

-- ---- injection (called by weapon_tempv) ----
-- ---- v1.4 SUPERFIGHTER PHYSIOLOGY ----
-- Dosed players get the gamemode's arcade organism flag: sv_input
-- routes ZERO damage to organs, AddWound no-ops (no bleeding), and
-- the blood/hurt accumulation that feeds the collapse conditions
-- never runs - so no wounds, no bleed-out, no limb cripple, no
-- pain KO, no being shot down into a ragdoll. They live on an
-- engine HP pool (zc_tempv_hp) instead: glass cannons.
--   zc_tempv_sf_arcade 1 = flag held for the whole dose, which also
--     hands them sh_inertia's instant accel + 1.5x jump = the V high
--   zc_tempv_sf_arcade 0 = jugg-style FLICKER (flag only inside the
--     damage pipeline) - identical immunity, movement untouched
-- HOMELANDER IS UNAFFECTED BY THIS: his punch/laser call
-- AmputateLimb/ExplodeHead DIRECTLY (bypassing the organ gates) and
-- his raw damage eats the small HP pool - he still deletes a dosed
-- player in one or two signature hits. This only stops his
-- INCIDENTAL violence from crippling them mid-charge.
local function applySF(ply)
	if not cv_sf:GetBool() or not IsValid(ply) then return end
	local hp = cv_sf_hp:GetInt()
	ply:SetMaxHealth(hp)
	ply:SetHealth(hp)
	ply.zc_tempv_sf = true
	if cv_sf_arcade:GetBool() and ply.organism then
		ply.organism.superfighter = true
	end
end

local function clearSF(ply)
	if not IsValid(ply) or not ply.zc_tempv_sf then return end
	ply.zc_tempv_sf = nil
	if ply.organism then
		ply.organism.superfighter = nil
		ply.zc_sfFlick = nil
	end
	ply:SetMaxHealth(100)
	if ply:Health() > 100 then ply:SetHealth(100) end
end

-- flicker path (zc_tempv_sf_arcade 0): flag on just before homigrad's
-- damage handler runs, cleared right after + a next-tick belt, so
-- SetupMove never sees it (the zc_juggernaut movement lesson)
hook.Add("EntityTakeDamage", "zc_tempv_sf_flick", function(ent, dmgInfo)
	if not IsValid(ent) or not ent:IsPlayer() then return end
	if not ent.zc_tempv_sf or cv_sf_arcade:GetBool() then return end
	local org = ent.organism
	if not org or org.superfighter then return end
	org.superfighter = true
	ent.zc_sfFlick = true
	timer.Simple(0, function()
		if IsValid(ent) and ent.zc_sfFlick and ent.organism then
			ent.organism.superfighter = nil
			ent.zc_sfFlick = nil
		end
	end)
end, -2)

hook.Add("EntityTakeDamage", "zc_tempv_sf_flickclear", function(ent)
	if IsValid(ent) and ent.zc_sfFlick and ent.organism then
		ent.organism.superfighter = nil
		ent.zc_sfFlick = nil
	end
end, 2)

function ZCTEMPV.Inject(ply)
	if not cv_on:GetBool() or not IsValid(ply) or not ply:Alive() then return end
	ply.zc_tempv = CurTime() + cv_dur:GetFloat()
	ply.zc_tempv_crashed = nil
	ply:EmitSound("items/medshot4.wav", 75, 90)

	-- v1.1: triple stamina while the V runs (save the ORIGINAL once -
	-- a re-inject while active must not compound the boost)
	-- v1.5 FIX: the gamemode recomputes stamina.max EVERY TICK as
	--   (superfighter and 2 or 1) * (range * ...)   (sv_stamina.lua:85)
	-- but never rescales the CURRENT stamina[1] - so range x3 plus the
	-- superfighter x2 made the ceiling jump ~180 -> ~1080 while the
	-- player's actual stamina stayed put, and the bar read ~17% full the
	-- moment the V hit. Scale [1] by the same factor the ceiling grows
	-- (each part counted ONCE: range only on a fresh dose, x2 only when
	-- arcade superfighter is newly applied - flicker mode's flag is off
	-- outside damage frames and doesn't move the bar). Overfill after
	-- crash/expiry is clamped by the regen line's min(), so the shrink
	-- path needs no counterpart.
	local fillMul = 1
	local org = ply.organism
	if org and org.stamina and isnumber(org.stamina.range) then
		if ply.zc_tempv_prevrange == nil then
			ply.zc_tempv_prevrange = org.stamina.range
			fillMul = fillMul * math.max(cv_stamina:GetFloat(), 1)
		end
		org.stamina.range = ply.zc_tempv_prevrange * cv_stamina:GetFloat()
	end

	local sfDoubles = cv_sf:GetBool() and cv_sf_arcade:GetBool() and org and not org.superfighter
	applySF(ply) -- v1.4: superfighter physiology + engine HP pool
	if sfDoubles then fillMul = fillMul * 2 end
	if fillMul > 1 and org and org.stamina and isnumber(org.stamina[1]) then
		org.stamina[1] = org.stamina[1] * fillMul
	end

	local laser = rnd(100) <= cv_laserchance:GetInt()
	if laser then
		ply.zc_tempv_laser = true
		ply:Give("weapon_tempv_laser")
		timer.Simple(0.1, function()
			if IsValid(ply) and ply:HasWeapon("weapon_tempv_laser") then ply:SelectWeapon("weapon_tempv_laser") end
		end)
		ply:ChatPrint("[Temp V] Your eyes are BURNING - the V gave you HEAT VISION. Hold RMB to fire.")
	else
		ply:ChatPrint("[Temp V] Raw strength floods your veins. HIT HIM - your blows drain his vitality.")
	end
	PrintMessage(HUD_PRINTTALK, "[HnS] " .. ply:Nick() .. " has injected TEMP V!")

	net.Start("zc_tempv_state")
	net.WriteFloat(ply.zc_tempv)
	net.WriteBool(laser)
	net.Send(ply)
end

local function crash(ply)
	ply.zc_tempv = nil
	ply.zc_tempv_laser = nil
	ply.zc_tempv_crashed = true
	clearSF(ply) -- v1.4: physiology back to normal (HP clamps to 100)
	if ply:HasWeapon("weapon_tempv_laser") then ply:StripWeapon("weapon_tempv_laser") end
	if ply.zc_wasLasering then
		ply:StopSound(LASER_SND)
		ply:StopSound(LASER_SND)
		ply:StopSound(LASER_SND)
		ply.zc_wasLasering = nil
	end

	net.Start("zc_tempv_state")
	net.WriteFloat(0)
	net.WriteBool(false)
	net.Send(ply)

	if cv_crashlethal:GetBool() then
		ply:ChatPrint("[Temp V] Your heart is tearing itself apart...")
		local p = ply
		timer.Simple(3, function()
			if IsValid(p) and p:Alive() and p.zc_tempv_crashed then
				if p.organism then p.organism.heart = 1 end
				p:Kill()
			end
		end)
		return
	end

	-- non-lethal crash: gut the stamina + pain for a while (the boost's
	-- saved ORIGINAL range comes back once the crash passes)
	local org = ply.organism
	if org then
		if org.stamina and isnumber(org.stamina.range) then
			if ply.zc_tempv_prevrange == nil then ply.zc_tempv_prevrange = org.stamina.range end
			org.stamina.range = 70
		end
		if isnumber(org.pain) then org.pain = math.min(1, (org.pain or 0) + 0.4) end
	end
	ply:ChatPrint("[Temp V] The V burns out of your veins. You feel hollow...")
	local p = ply
	timer.Simple(cv_crashtime:GetFloat(), function()
		if not IsValid(p) then return end
		if p.zc_tempv then return end -- re-injected mid-crash: the new dose's crash handles restore
		if p.organism and p.organism.stamina and p.zc_tempv_prevrange then
			if p.organism.stamina.range == 70 then p.organism.stamina.range = p.zc_tempv_prevrange end
			p.zc_tempv_prevrange = nil
			p.zc_tempv_crashed = nil
		end
	end)
end

-- ---- speed boost (engine-level, jugg-cap pattern inverted) ----
hook.Add("Move", "zc_tempv_speed", function(ply, mv)
	if not onV(ply) then return end
	local mul = cv_speed:GetFloat()
	if mul <= 1 then return end
	mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mul)
	mv:SetMaxSpeed(mv:GetMaxSpeed() * mul)
end)

-- ---- v1.1 STRONGER PUNCHES: bare-hands damage x punchmul vs everyone
--      EXCEPT the Homelander (his math stays dmgmul-based so the drain
--      balance doesn't silently triple) ----
hook.Add("EntityTakeDamage", "zc_tempv_punch", function(ent, dmgInfo)
	if not cv_on:GetBool() or not hnsRound() then return end
	local attacker = dmgInfo:GetAttacker()
	if not IsValid(attacker) or not attacker:IsPlayer() or not onV(attacker) then return end
	if isHLTarget(ent) then return end
	local wep = attacker:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "weapon_hands_sh" then return end
	dmgInfo:ScaleDamage(cv_punchmul:GetFloat())
end, -1)

-- ---- punch/any-damage drain (priority -2: reads raw damage BEFORE
--      homelander_zcity_fix's invulnerability hook zeroes it) ----
hook.Add("EntityTakeDamage", "zc_tempv_drain", function(ent, dmgInfo)
	if not cv_on:GetBool() or not hnsRound() or ZCTEMPV.burned then return end
	local hl = isHLTarget(ent)
	if not hl then return end
	local attacker = dmgInfo:GetAttacker()
	if not IsValid(attacker) or not attacker:IsPlayer() or not onV(attacker) then return end
	local raw = dmgInfo:GetDamage()
	if raw <= 0 then return end
	drain(raw * cv_dmgmul:GetFloat(), attacker)
end, -2)

-- ---- HEAT VISION: 0.1s eye-trace for Temp-V laser users ----
-- v1.2: heat vision SHATTERS glass. Stock panes never actually broke
-- under the laser - they just soaked damage events every tick, which
-- was the shard-spam source. Fire("Break") is the gamemode's own
-- door-blast idiom for func_breakable_surf (sv_util hgBlastDoors).
local function laserBreakGlass(ent)
	if not IsValid(ent) then return end
	local cls = ent:GetClass()
	if cls == "func_breakable_surf"
		or (cls == "func_breakable" and ent.GetMaterialType and ent:GetMaterialType() == MAT_GLASS) then
		ent:Fire("Break")
	end
end

local function killLaserSnd(ply)
	-- looping wav + possible stacked instances: stop repeatedly
	ply:StopSound(LASER_SND)
	ply:StopSound(LASER_SND)
	ply:StopSound(LASER_SND)
end

timer.Create("zc_tempv_laser", 0.1, 0, function()
	local roundActive = cv_on:GetBool() and hnsRound()
	local hl = roundActive and hlPlayer() or nil

	-- v1.3.3: continuous orphan-sound guard on the Homelander himself -
	-- his SWEP's beam loop can survive strips/switches serverside
	if IsValid(hl) and (ZCTEMPV.hlSndGuard or 0) < CurTime() then
		local w = hl:GetActiveWeapon()
		local beaming = hl:Alive() and hl:KeyDown(IN_ATTACK2)
			and IsValid(w) and w:GetClass() == "weapon_homelander"
		if not beaming then
			ZCTEMPV.hlSndGuard = CurTime() + 1
			hl:StopSound(LASER_SND)
		end
	end

	for _, ply in player.Iterator() do
		-- v1.2: the HOMELANDER's own heat vision pops panes as it sweeps
		if ply == hl and ply:Alive() and ply:KeyDown(IN_ATTACK2) then
			local hwep = ply:GetActiveWeapon()
			if IsValid(hwep) and hwep:GetClass() == "weapon_homelander" then
				local htr = util.TraceLine({
					start = ply:EyePos(),
					endpos = ply:EyePos() + ply:GetAimVector() * 8192,
					filter = ply,
					mask = MASK_SHOT,
				})
				laserBreakGlass(htr.Entity)
			end
		end

		local firing = false
		if roundActive and onV(ply) and ply.zc_tempv_laser and ply:Alive() and ply:KeyDown(IN_ATTACK2) then
			local wep = ply:GetActiveWeapon()
			firing = IsValid(wep) and wep:GetClass() == "weapon_tempv_laser"
		end

		if firing then
			-- v1.3.3 sound: SINGLE INSTANCE always - the wav loops, so a
			-- naive refresh STACKED infinite loops. Stop-then-restart on
			-- each refresh; hard-stopped (x3) the moment firing ends.
			-- The cleanup transition below now also runs when the ROUND
			-- ends mid-beam (the old gate skipped it = the big orphan).
			if not ply.zc_wasLasering or (ply.zc_laserSnd or 0) < CurTime() then
				ply:StopSound(LASER_SND)
				ply.zc_laserSnd = CurTime() + 2.2
				pcall(function() ply:EmitSound(LASER_SND, 82, 100) end)
			end
			ply.zc_wasLasering = true

			local tr = util.TraceLine({
				start = ply:EyePos(),
				endpos = ply:EyePos() + ply:GetAimVector() * 4096,
				filter = ply,
				mask = MASK_SHOT,
			})
			-- beam visuals are CLIENTSIDE now (real homelander laser
			-- materials, drawn from networked key state); server adds the
			-- impact energy burst everyone sees + burns the world
			if (ply.zc_laserFx or 0) < CurTime() then
				ply.zc_laserFx = CurTime() + 0.2
				local ed = EffectData()
				ed:SetOrigin(tr.HitPos)
				ed:SetNormal(tr.HitNormal or vector_up)
				util.Effect("cball_bounce", ed, true, true)
			end
			laserBreakGlass(tr.Entity) -- v1.2: Temp V heat vision breaks panes too
			if IsValid(tr.Entity) then
				if isHLTarget(tr.Entity) and not ZCTEMPV.burned then
					drain(cv_laserdrain:GetFloat(), ply)
				elseif tr.Entity:IsPlayer() and tr.Entity ~= ply and cv_laserpvp:GetFloat() > 0 then
					local d = DamageInfo()
					d:SetDamage(cv_laserpvp:GetFloat())
					d:SetAttacker(ply)
					d:SetInflictor(ply:GetActiveWeapon() or ply)
					d:SetDamageType(DMG_BURN)
					d:SetDamagePosition(tr.HitPos)
					tr.Entity:TakeDamageInfo(d)
				end
			elseif tr.HitWorld then
				util.Decal("FadingScorch", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal)
			end
		elseif ply.zc_wasLasering then
			killLaserSnd(ply)
			ply.zc_wasLasering = nil
			ply.zc_laserSnd = nil
		end
	end
end)

-- ---- sustain tick: expiry/crash, regen, burnout watcher, publish ----
timer.Create("zc_tempv_think", 0.25, 0, function()
	if not hnsRound() then return end

	for _, ply in player.Iterator() do
		if ply.zc_tempv and ply.zc_tempv <= CurTime() then crash(ply) end
	end

	if ZCTEMPV.vit and not ZCTEMPV.burned and ZCTEMPV.vit < (ZCTEMPV.vitmax or 1)
		and (CurTime() - (ZCTEMPV.lastDrain or 0)) > cv_regendelay:GetFloat() then
		ZCTEMPV.vit = math.min(ZCTEMPV.vitmax, ZCTEMPV.vit + cv_regen:GetFloat() * 0.25)
	end

	if ZCTEMPV.burned then
		local hl = hlPlayer()
		if IsValid(hl) and hl:HasWeapon("weapon_homelander") then
			hl:StripWeapon("weapon_homelander") -- watcher: burned means BURNED
		end
	end

	ZCTEMPV.vials = #vialList()

	-- v1.1 DRIP: a replacement vial every zc_tempv_respawn seconds while
	-- the map holds fewer than the cap (covers doses that died with
	-- their carriers). Reuses the roundstart point list, random pick.
	local rs = cv_respawn:GetFloat()
	if rs > 0 and ZCTEMPV.points and #ZCTEMPV.points > 0 and not ZCTEMPV.burned
		and ZCTEMPV.vials < cv_vials:GetInt() then
		if (ZCTEMPV.nextVial or 0) <= CurTime() then
			ZCTEMPV.nextVial = CurTime() + rs
			local v = spawnOne(ZCTEMPV.points[rnd(#ZCTEMPV.points)])
			if v then PrintMessage(HUD_PRINTTALK, "[HnS] A fresh vial of TEMP V has surfaced.") end
		end
	else
		ZCTEMPV.nextVial = CurTime() + rs -- reset the clock while at cap
	end
end)

-- ---- v1.1.1 GLASS SHARD FIX (Joey: "homelander keeps spawning
--      weapon_hg_glassshard when hes being hit... only sometimes"):
--      stock sv_util hook "GlassShards" rolls 1-in-4 on every damaged
--      window pane and spawns the shard AT THE INFLICTOR - during HnS
--      that's usually Homelander (laser through glass, bodies thrown
--      through windows), so shards materialize at his feet. Wrap the
--      named hook: during homelanderhns, HL-caused pane damage spawns
--      nothing; everything else passes through untouched. ----
local function wrapGlassShards()
	local t = hook.GetTable()["PostEntityTakeDamage"]
	local cur = t and t["GlassShards"]
	if not cur then return false end
	if cur == ZCTEMPV.glassWrap then return true end
	ZCTEMPV.origGlass = cur -- capture the stock fn (or whatever runs now)
	local wrap = function(ent, dmginfo)
		if hnsRound() then
			local hl = hlPlayer()
			if hl then
				local atk = dmginfo:GetAttacker()
				local inf = dmginfo:GetInflictor()
				if atk == hl or inf == hl
					or (IsValid(inf) and inf.GetOwner and inf:GetOwner() == hl) then
					return
				end
			end
		end
		return ZCTEMPV.origGlass(ent, dmginfo)
	end
	ZCTEMPV.glassWrap = wrap
	hook.Add("PostEntityTakeDamage", "GlassShards", wrap)
	print("[Temp V] GlassShards hook wrapped - no shards from Homelander-broken glass")
	return true
end
timer.Create("zc_tempv_glasswrap", 2, 15, function()
	if wrapGlassShards() then timer.Remove("zc_tempv_glasswrap") end
end)

-- ---- v1.3 HL PUNCH vs RAGDOLLS (Joey: normal punch only nudged
--      downed bodies): the fix's punch translator early-returns for
--      non-players, so a punch landing on a knocked-down player's
--      RAGDOLL never reached the organism. Same effect as standing:
--      nearest limb amputates, head explodes, heavy wounds. ----
local PUNCH_LIMB = {
	["ValveBiped.Bip01_R_UpperArm"] = "rarm", ["ValveBiped.Bip01_R_Forearm"] = "rarm", ["ValveBiped.Bip01_R_Hand"] = "rarm",
	["ValveBiped.Bip01_L_UpperArm"] = "larm", ["ValveBiped.Bip01_L_Forearm"] = "larm", ["ValveBiped.Bip01_L_Hand"] = "larm",
	["ValveBiped.Bip01_R_Thigh"] = "rleg", ["ValveBiped.Bip01_R_Calf"] = "rleg", ["ValveBiped.Bip01_R_Foot"] = "rleg",
	["ValveBiped.Bip01_L_Thigh"] = "lleg", ["ValveBiped.Bip01_L_Calf"] = "lleg", ["ValveBiped.Bip01_L_Foot"] = "lleg",
}
local PUNCH_HEAD = { ["ValveBiped.Bip01_Head1"] = true, ["ValveBiped.Bip01_Neck1"] = true }

hook.Add("EntityTakeDamage", "zc_tempv_hlpunch_rag", function(ent, dmgInfo)
	if not hnsRound() then return end
	if not IsValid(ent) or ent:GetClass() ~= "prop_ragdoll" then return end
	local hl = hlPlayer()
	if not hl or dmgInfo:GetAttacker() ~= hl then return end
	local wep = hl:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "weapon_homelander" then return end
	if not (dmgInfo:IsDamageType(DMG_CLUB) or dmgInfo:IsDamageType(DMG_CRUSH)) then return end

	-- resolve the rag to its LIVING owner (the fix's laser idiom)
	local victim = ent.ply or ent:GetNWEntity("OwningPlayer")
	if not IsValid(victim) and ent.organism and IsValid(ent.organism.owner) then victim = ent.organism.owner end
	if not IsValid(victim) and hg and hg.RagdollOwner then victim = hg.RagdollOwner(ent) end
	if not IsValid(victim) or not victim:IsPlayer() or victim == hl or not victim:Alive() then return end
	local org = victim.organism
	if not org then return end
	if (victim.zc_hlPunchCD or 0) > CurTime() then return end
	victim.zc_hlPunchCD = CurTime() + 0.2 -- the melee hull can land twice

	local hitPos = dmgInfo:GetDamagePosition()
	if not hitPos or hitPos == vector_origin then hitPos = ent:GetPos() end

	local bestD, bestLimb, bestBone, isHead = math.huge, nil, nil, false
	for name, limb in pairs(PUNCH_LIMB) do
		local b = ent:LookupBone(name)
		local p = b and ent:GetBonePosition(b)
		if p then
			local d = p:DistToSqr(hitPos)
			if d < bestD then bestD, bestLimb, bestBone, isHead = d, limb, b, false end
		end
	end
	for name in pairs(PUNCH_HEAD) do
		local b = ent:LookupBone(name)
		local p = b and ent:GetBonePosition(b)
		if p then
			local d = p:DistToSqr(hitPos)
			if d < bestD then bestD, bestLimb, bestBone, isHead = d, nil, b, true end
		end
	end

	if bestLimb and hg and hg.organism and hg.organism.AmputateLimb and not org[bestLimb .. "amputated"] then
		pcall(hg.organism.AmputateLimb, org, bestLimb)
	end
	if isHead and hg and hg.ExplodeHead then
		pcall(hg.ExplodeHead, victim)
	end
	if bestBone and hg and hg.organism and hg.organism.AddWoundManual then
		for i = 1, 3 do
			pcall(hg.organism.AddWoundManual, victim, 200, vector_origin, angle_zero, bestBone, CurTime() + math.Rand(0, 2))
		end
	end
end, -2) -- v1.3.1: MUST run before homigrad's own ETD handler - it can
         -- return-and-block on ragdoll damage, starving default-priority
         -- hooks (hook chains stop at the first non-nil return)

-- ---- round lifecycle ----
hook.Add("ZB_StartRound", "zc_tempv_round", function()
	if not hnsRound() or not cv_on:GetBool() then return end
	ZCTEMPV.vit = cv_vitality:GetFloat()
	ZCTEMPV.vitmax = cv_vitality:GetFloat()
	ZCTEMPV.burned = false
	ZCTEMPV.lastDrain = 0
	timer.Simple(3, function()
		if hnsRound() and cv_on:GetBool() then spawnVials() end
	end)
end)

local function clearRound()
	ZCTEMPV.vit = nil
	ZCTEMPV.vitmax = nil
	ZCTEMPV.burned = false
	ZCTEMPV.vials = 0
	ZCTEMPV.hitters = nil
	ZCTEMPV.kdCD = nil
	for _, v in ipairs(vialList()) do v:Remove() end
	for _, ply in player.Iterator() do
		clearSF(ply) -- v1.4
		ply.zc_tempv = nil
		ply.zc_tempv_laser = nil
		ply.zc_tempv_crashed = nil
		if ply.zc_wasLasering then
			ply:StopSound(LASER_SND)
			ply:StopSound(LASER_SND)
			ply:StopSound(LASER_SND)
			ply.zc_wasLasering = nil
		end
		if ply.zc_tempv_prevrange and ply.organism and ply.organism.stamina then
			ply.organism.stamina.range = ply.zc_tempv_prevrange
		end
		ply.zc_tempv_prevrange = nil
		if ply:HasWeapon("weapon_tempv_laser") then ply:StripWeapon("weapon_tempv_laser") end
		if ply:HasWeapon("weapon_tempv") then ply:StripWeapon("weapon_tempv") end
	end
	-- v1.3.4: tell every client the dose is over - the chip was
	-- surviving round end because only crash() ever sent the zero
	net.Start("zc_tempv_state")
	net.WriteFloat(0)
	net.WriteBool(false)
	net.Broadcast()
end
hook.Add("ZB_EndRound", "zc_tempv_cleanup", clearRound)
hook.Add("ZB_PreRoundStart", "zc_tempv_cleanup_pre", clearRound)

-- v1.3.4: dying mid-dose ends the dose - clear state, kill the laser
-- sound, and zero the client chip (it counted on through spectate)
hook.Add("PlayerDeath", "zc_tempv_death", function(ply)
	clearSF(ply) -- v1.4: never leave superfighter/HP pool on a corpse
	if not ply.zc_tempv then return end
	ply.zc_tempv = nil
	ply.zc_tempv_laser = nil
	if ply.zc_wasLasering then
		ply:StopSound(LASER_SND)
		ply:StopSound(LASER_SND)
		ply:StopSound(LASER_SND)
		ply.zc_wasLasering = nil
	end
	net.Start("zc_tempv_state")
	net.WriteFloat(0)
	net.WriteBool(false)
	net.Send(ply)
end)

print("[Temp V] loaded - vitality " .. cv_vitality:GetFloat() .. ", " .. cv_vials:GetInt() .. " vials, " .. cv_laserchance:GetInt() .. "% heat vision")
