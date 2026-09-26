-- ============================================================
--  ZC JUGGERNAUT - hmcd round type: one armored monster vs all
-- ------------------------------------------------------------
--  Injected into zb.modes["hmcd"].Types at runtime (hydroxo/GFZ
--  pattern - NO gamemode file edits). The "traitor" IS the
--  Juggernaut, publicly announced at roundstart; homicide's win
--  conditions (traitor kills all / traitor dies) are the rules.
--
--  THE JUGG (480 HP, v2.3): random LMG (M249/PKM/MG42, 5 mags) +
--  Grizzly .50AE + SOG knife, heavy plates vest5/helmet7/mask1
--  (real positional armor - limbs stay soft). Durability = the
--  SUPERFIGHTER FLICKER: org.superfighter is set only inside the
--  damage pipeline (never permanently - sh_inertia reads it every
--  tick and would arcade-ify his movement), so organs/wounds/blood
--  never take damage and he lives on an engine HP pool
--  (100 x zc_jugg_hp) behind 1/zc_jugg_resist intake+force scaling.
--  Limb/spine/amputation inputs are wrapped to no-op for him
--  (crusher pattern - kills the armor-punch spine leak), stun fns
--  wrapped for pain-KO immunity, iron-will damps trauma pools,
--  Move-hook speed cap. NO sustain: no kill-heal, hpregen 0.
--  OVERWHELM: raw damage feeds a decaying meter (broadcast to all
--  clients as the SUPPRESSION bar); past the threshold = brief
--  legit knockdown via the saved original stun fn, cooldown-gated.
--  While DOWN his ragdoll damage is resolved back to him (resist +
--  flicker still apply - no free executions). ROUND CLOCK: hunters
--  win at zc_jugg_roundtime expiry (jugg killed -> stock end).
--  STATUS HUD (v2.4): the suppression bar grew into a PERSISTENT
--  bottom-center panel everyone sees all round - JUGGERNAUT HP bar
--  (his superfighter engine pool) + VEST/HELM/MASK armor chips +
--  the suppression meter. Fed by the zc_jugg_ow broadcast every
--  0.25s tick while he lives; the client's only show/hide gate is
--  packet freshness, so the panel dies ~2s after he does.
--  ARMOR WEAR (v2.5): his plates genuinely DEGRADE - bullet damage
--  near the chest drains the vest pool, near the skull splits
--  helmet/mask (65/35). protec() multiplies protection by
--  armors_health, so a worn plate stops less long before it breaks;
--  at zero the piece is destroyed, dropped off his body and
--  announced - the HUD chip goes dark. zc_jugg_armorwear scales the
--  wear rate (0 = off); pools vest 3000 / helmet 1000 / mask 600.
--
--  HUNTERS: kitted via our ZB_StartRound pass (GunManLoot only
--  fires for the gunner role - Types entry ships a no-op so the
--  engine call can't nil-error): 15% RPD support roll, else
--  rifle/shotgun split (4 mags), pistol (2), SOG knife, medkit +
--  big bandage, light armor (25% medium vest, helmet rolls).
--  GROUP SPAWNS: hunters cycled across HMCD_CRI_CT points, jugg
--  at HMCD_CRI_T (auto-seeded from CS spawns; quiet fallback).
--  TEAM indicators via the patched indicators addon (announce
--  net carries the jugg entity; ZCJUGG_CL round-stamped).
--  ONE JUGG: homicide_traitoramount clamped to 1 around jugg
--  ballots (ZC_ModeVoteApplied instant hook + 0.25s poll).
--  Ground loot stays on. No police. All picks use a PRIVATE RNG
--  (something reseeds the shared math.random - picks froze).
--
--  Convars (FCVAR_ARCHIVE, all live): zc_jugg_resist(1.5)
--  superfighter(1) hp(4.8=480) hpregen(0) ironwill(1)
--  bleedmul(0.25) bloodregen(40, inert under superfighter)
--  stunimmune(1) maxspeed(330) groupspawns(1) overwhelm(1)
--  overwhelm_threshold(750) overwhelm_time(2.5) overwhelm_cd(10)
--  roundtime(300) armorwear(1).
--
--  Vote-only (Chance 0; in TDM + Customs ballots). Serverside
--  file = hotloadable; the client file (splash/meter/indicator
--  publish) is restart cargo.
-- ============================================================
if not SERVER then return end

ZCJUGG = ZCJUGG or {}

local cv_resist    = CreateConVar("zc_jugg_resist", "1.5", FCVAR_ARCHIVE, "Juggernaut: incoming damage divided by this", 1, 20)
local cv_sf        = CreateConVar("zc_jugg_superfighter", "1", FCVAR_ARCHIVE, "Juggernaut: crusher-style durability (engine HP pool, organism damage off)", 0, 1)
local cv_hp        = CreateConVar("zc_jugg_hp", "4.8", FCVAR_ARCHIVE, "Juggernaut: HP multiplier (x100) for superfighter mode", 1, 50)
local cv_hpregen   = CreateConVar("zc_jugg_hpregen", "0", FCVAR_ARCHIVE, "Juggernaut: HP regen per second in superfighter mode", 0, 100)
local cv_ironwill  = CreateConVar("zc_jugg_ironwill", "1", FCVAR_ARCHIVE, "Juggernaut: damp spine trauma/shock so massed fire can't KO him", 0, 1)
local cv_bleedmul  = CreateConVar("zc_jugg_bleedmul", "0.25", FCVAR_ARCHIVE, "Juggernaut: bleeding multiplier", 0, 1)
local cv_regen     = CreateConVar("zc_jugg_bloodregen", "40", FCVAR_ARCHIVE, "Juggernaut: extra blood per second", 0, 500)
local cv_stunimm   = CreateConVar("zc_jugg_stunimmune", "1", FCVAR_ARCHIVE, "Juggernaut: immune to stun/pain-KO", 0, 1)
local cv_maxspeed  = CreateConVar("zc_jugg_maxspeed", "330", FCVAR_ARCHIVE, "Juggernaut: movement speed cap (0 = off)", 0, 600)
local cv_grpspawn  = CreateConVar("zc_jugg_groupspawns", "1", FCVAR_ARCHIVE, "Juggernaut: hunters spawn together at HMCD_CRI_CT points, jugg at HMCD_CRI_T (0 = normal hmcd spawns)", 0, 1)
local cv_ow        = CreateConVar("zc_jugg_overwhelm", "1", FCVAR_ARCHIVE, "Juggernaut: massed fire can briefly knock him down", 0, 1)
local cv_ow_thresh = CreateConVar("zc_jugg_overwhelm_threshold", "750", FCVAR_ARCHIVE, "Juggernaut: raw damage within ~2s that triggers the knockdown", 20, 2000)
local cv_ow_time   = CreateConVar("zc_jugg_overwhelm_time", "2.5", FCVAR_ARCHIVE, "Juggernaut: knockdown duration (seconds)", 0.5, 10)
local cv_ow_cd     = CreateConVar("zc_jugg_overwhelm_cd", "10", FCVAR_ARCHIVE, "Juggernaut: cooldown between knockdowns (seconds)", 0, 120)
local cv_roundtime = CreateConVar("zc_jugg_roundtime", "300", FCVAR_ARCHIVE, "Juggernaut: round time limit in seconds - hunters win at expiry (0 = no limit)", 0, 1800)
local cv_wear      = CreateConVar("zc_jugg_armorwear", "1", FCVAR_ARCHIVE, "Juggernaut: armor degradation rate multiplier - his plates wear as they eat fire (0 = off)", 0, 20)

util.AddNetworkString("zc_jugg_announce")
util.AddNetworkString("zc_jugg_ow")

local LMGS     = {"weapon_m249", "weapon_pkm", "weapon_mg42"}
local RIFLES   = {"weapon_ak74", "weapon_akm", "weapon_sks", "weapon_m4a1", "weapon_mini14"}
local SHOTGUNS = {"weapon_remington870", "weapon_moss500", "weapon_spas12", "weapon_toz194"}
local PISTOLS  = {"weapon_glock17", "weapon_m9beretta", "weapon_m1911", "weapon_p220", "weapon_makarov"}
local VESTS_M  = {"vest3", "vest7"}
local HELMS_L  = {"helmet2", "helmet3", "helmet4"}

-- PRIVATE RNG: something server-side reseeds the shared math.random
-- (kit picks came out FROZEN - always the same rifle/shotgun/LMG every
-- round). Own LCG state; nothing external can reseed it.
-- v2.5.1: Park-Miller (Lehmer) LCG. The old constants overflowed
-- double precision (product ~2^61, quantized to steps of 512),
-- permanently zeroing the state's LOW bits - and `state % n` reads
-- exactly those bits, so every POWER-OF-2 pool froze at index 1:
-- the 4-gun shotgun roll was always remington870, the 2-vest medium
-- roll always vest3 (caught via wildwest's 8-pool all-Yellowboy).
-- Non-power-of-2 pools (LMGs/rifles/pistols) still varied, which
-- masked it. 16807 * state stays under 2^53 = exact math; the roll
-- scales from the FULL state instead of the low bits.
local seedState = (math.floor(SysTime() * 1000) % 2147483646) + 1
local function rnd(n)
	seedState = (seedState * 16807) % 2147483647
	return math.floor(seedState / 2147483647 * n) + 1
end

local function juggRound()
	local hmcd = zb and zb.modes and zb.modes["hmcd"]
	if not hmcd or hmcd.Type ~= "juggernaut" then return false end
	-- hmcd.Type goes STALE when the next round is a different mode family
	-- (nothing resets it) - zb.CROUND holds the actual current round type
	if zb.CROUND ~= nil and zb.CROUND ~= "juggernaut" then return false end
	return true
end

local function isJugg(ply)
	return IsValid(ply) and ply.zc_isJugg == true
end

local function giveFull(ply, class, magMul)
	local wep = ply:Give(class, true)
	if IsValid(wep) then
		pcall(function()
			wep:SetClip1(wep:GetMaxClip1())
			ply:GiveAmmo(wep:GetMaxClip1() * (magMul or 2), wep:GetPrimaryAmmoType(), true)
		end)
	end
	return wep
end

-- ---- THE JUGG'S KIT (Types entry TraitorLoot) ----
local function JuggLoot(ply)
	ply.zc_isJugg = true
	ZCJUGG.current = ply

	giveFull(ply, LMGS[rnd(#LMGS)], 5)
	giveFull(ply, "weapon_grizzlymkv", 2)
	ply:Give("weapon_sogknife")

	-- heavy plates: real positional armor (limbs stay soft on purpose)
	pcall(hg.AddArmor, ply, "vest5")
	pcall(hg.AddArmor, ply, "helmet7")
	pcall(hg.AddArmor, ply, "mask1")
	-- v2.5: plates start factory-fresh (armors_health persists per-player)
	ply.armors_health = ply.armors_health or {}
	ply.armors_health.vest5, ply.armors_health.helmet7, ply.armors_health.mask1 = nil, nil, nil

	local org = ply.organism
	if org then
		org.bleedingmul = cv_bleedmul:GetFloat()
		-- range, not max: sv_stamina recomputes .max from .range every tick
		if org.stamina then org.stamina.range = 250 end
	end

	-- crusher-style durability: an engine-HP pool. The superfighter flag
	-- itself is NOT set permanently (it would arcade-ify his movement -
	-- sh_inertia reads it every tick); it flickers on only inside the
	-- damage pipeline via the hooks below.
	if cv_sf:GetBool() then
		ply:SetMaxHealth(100 * cv_hp:GetFloat())
		ply:SetHealth(100 * cv_hp:GetFloat())
	end

	-- public announcement + splash data
	timer.Simple(0.6, function()
		if not IsValid(ply) then return end
		local name = ply:Nick()
		for _, p in player.Iterator() do
			if p == ply then
				p:ChatPrint("[JUGGERNAUT] YOU are the Juggernaut. Heavy plates. Big gun. Kill them all.")
			else
				p:ChatPrint("[JUGGERNAUT] " .. name .. " is the Juggernaut. Bring them down - aim for the gaps in the armor.")
			end
		end
		net.Start("zc_jugg_announce")
		net.WriteString(name)
		net.WriteEntity(ply)
		net.Broadcast()
	end)
end

-- ---- HUNTER KITS (our own roundstart pass; GunManLoot not relied on) ----
local function HunterKit(ply)
	-- primary: 15% RPD (squad support roll), rest split rifle/shotgun
	local roll = rnd(100)
	if roll <= 15 then
		giveFull(ply, "weapon_rpd", 3)
	elseif roll <= 57 then
		giveFull(ply, RIFLES[rnd(#RIFLES)], 4)
	else
		giveFull(ply, SHOTGUNS[rnd(#SHOTGUNS)], 4)
	end

	giveFull(ply, PISTOLS[rnd(#PISTOLS)], 2)
	ply:Give("weapon_sogknife")

	-- trauma meds: everyone gets the full kit + a big bandage
	ply:Give("weapon_medkit_sh")
	ply:Give("weapon_bigbandage_sh")

	-- light armor; a lucky few roll medium (argues with the Grizzly +
	-- degraded plates in crossfire). Faces stay bare on purpose.
	if rnd(4) == 1 then
		pcall(hg.AddArmor, ply, VESTS_M[rnd(#VESTS_M)])
	else
		pcall(hg.AddArmor, ply, "vest2")
	end
	local hr = rnd(100)
	if hr <= 15 then
		pcall(hg.AddArmor, ply, "helmet1")
	elseif hr <= 75 then
		pcall(hg.AddArmor, ply, HELMS_L[rnd(#HELMS_L)])
	end
end

-- ---- GROUPED SPAWNS: hunters together at the CRI_CT point group,
--      the jugg off at a CRI_T point. The mappoints library seeds these
--      from CS info_player_terrorist/_counterterrorist ents when a map
--      has no hand-placed group; each point = {pos = Vector, ang = Angle}.
--      Runs 0.8s into the round, under the roundstart fade, so the blink
--      from the normal hmcd spawns is invisible. Quiet fallback to
--      normal spawns when a map has no points.
local function GroupSpawns()
	if not cv_grpspawn:GetBool() then return end
	if not (zb and zb.GetMapPoints) then return end

	local ctPoints = zb.GetMapPoints("HMCD_CRI_CT")
	local tPoints = zb.GetMapPoints("HMCD_CRI_T")
	if not istable(ctPoints) or #ctPoints == 0 or not istable(tPoints) or #tPoints == 0 then
		print("[Juggernaut] no HMCD_CRI_CT/T map points on this map - keeping normal spawns")
		return
	end

	local function place(ply, point, spread)
		if not IsValid(ply) or not ply:Alive() or not point or not isvector(point.pos) then return end
		local off = spread and Vector(rnd(97) - 49, rnd(97) - 49, 4) or Vector(0, 0, 4)
		ply:SetPos(point.pos + off)
		if point.ang then ply:SetEyeAngles(Angle(0, point.ang.y or 0, 0)) end
	end

	-- jugg to a T point
	place(ZCJUGG.current, tPoints[rnd(#tPoints)], false)

	-- hunters cycle across the CT points
	local i = 0
	for _, p in player.Iterator() do
		if IsValid(p) and p:Alive() and p:Team() ~= TEAM_SPECTATOR and not p.isTraitor then
			i = i + 1
			place(p, ctPoints[((i - 1) % #ctPoints) + 1], true)
		end
	end
	print("[Juggernaut] grouped spawns: " .. i .. " hunters at " .. #ctPoints .. " CT points, jugg at a T point")
end

hook.Add("ZB_StartRound", "zc_jugg_hunterkits", function()
	if not juggRound() then return end

	-- round clock: hunters win if the jugg hasn't finished the job in time
	local rt = cv_roundtime:GetFloat()
	ZCJUGG.roundEndsAt = rt > 0 and (CurTime() + rt) or nil
	ZCJUGG.warned60, ZCJUGG.warned10 = nil, nil

	timer.Simple(0.8, function()
		if not juggRound() then return end
		pcall(GroupSpawns)
		for _, p in player.Iterator() do
			if IsValid(p) and p:Alive() and p:Team() ~= TEAM_SPECTATOR and not p.isTraitor then
				pcall(HunterKit, p)
			end
		end
	end)
end)

-- ---- TYPES ENTRY INJECTION (idempotent, hotload-safe) ----
local function inject()
	local hmcd = zb and zb.modes and zb.modes["hmcd"]
	if not hmcd or not hmcd.Types or not hmcd.LootTableStandard then return false end

	hmcd.Types.juggernaut = {
		Chance = 0,
		ChanceFunction = function() return zb.ModesChances and zb.ModesChances["juggernaut"] or 0 end,
		LootTable = hmcd.LootTableStandard,
		Messages = {
			[3] = "Everyone died.",
			[1] = "The Juggernaut slaughtered them all.",
			[0] = "The Juggernaut has fallen. It was",
		},
		Message = "The Juggernaut was ",
		TraitorLoot = JuggLoot,
		GunManLoot = function() end, -- engine calls this if a gunner is rolled; must exist
	}

	hmcd.TypeNames = hmcd.TypeNames or {}
	hmcd.TypeNames.juggernaut = "Juggernaut"

	hmcd.Roles = hmcd.Roles or {}
	hmcd.Roles.juggernaut = {
		traitor  = { name = "Juggernaut", color = Color(255, 120, 0) },
		gunner   = { name = "Hunter",     color = Color(0, 120, 190) },
		innocent = { name = "Hunter",     color = Color(0, 120, 190) },
	}

	-- limb/spine protection at the SOURCE (crusher pattern): protec()'s
	-- armor-punch feeds spine3 via DIRECT input_list calls that bypass
	-- the superfighter gate, and limb-break inputs are what ragdoll him
	-- for "broken legs". No-op them for the jugg. Coexists with the
	-- crusher addon's own wraps (each checks its own flag).
	if hg and hg.organism and hg.organism.input_list and not ZCJUGG.inputWrapped then
		for _, fname in ipairs({"larmup", "rarmup", "llegup", "rlegup", "spine1", "spine2", "spine3"}) do
			local real = hg.organism.input_list[fname]
			if real then
				hg.organism.input_list[fname] = function(org, ...)
					if org and IsValid(org.owner) and org.owner.zc_isJugg then return end
					return real(org, ...)
				end
			end
		end
		ZCJUGG.inputWrapped = true
	end
	if hg and hg.organism and hg.organism.AmputateLimb and not ZCJUGG.ampWrapped then
		local realAmp = hg.organism.AmputateLimb
		hg.organism.AmputateLimb = function(org, ...)
			if org and IsValid(org.owner) and org.owner.zc_isJugg then return end
			return realAmp(org, ...)
		end
		ZCJUGG.ampWrapped = true
	end

	-- stun / pain-KO immunity: wrap once, originals stashed globally
	if hg and hg.StunPlayer and not ZCJUGG.origStun then
		ZCJUGG.origStun = hg.StunPlayer
		hg.StunPlayer = function(p, t, ...)
			if isJugg(p) and cv_stunimm:GetBool() then return end
			return ZCJUGG.origStun(p, t, ...)
		end
	end
	if hg and hg.LightStunPlayer and not ZCJUGG.origLightStun then
		ZCJUGG.origLightStun = hg.LightStunPlayer
		hg.LightStunPlayer = function(p, t, ...)
			if isJugg(p) and cv_stunimm:GetBool() then return end
			return ZCJUGG.origLightStun(p, t, ...)
		end
	end

	print("[Juggernaut] round type injected (vote key: juggernaut)")
	return true
end

local function startInject()
	if inject() then return end
	local tries = 0
	timer.Create("zc_jugg_inject", 2, 15, function()
		tries = tries + 1
		if inject() or tries >= 15 then timer.Remove("zc_jugg_inject") end
	end)
end

hook.Add("InitPostEntity", "zc_jugg_boot", startInject)
startInject()

-- ---- DURABILITY: intake scaling (the crusher-proven lever) ----
-- resolve the jugg from a damage target: the player himself OR his
-- ragdoll (while knocked down, damage lands on the RAGDOLL entity -
-- without this, downed headshots bypassed resist + superfighter
-- entirely, which is how he was getting executed)
local function resolveJugg(ent)
	if isJugg(ent) then return ent end
	if IsValid(ent) and not ent:IsPlayer() then
		local org = ent.organism
		local owner = org and org.owner
		if isJugg(owner) then return owner end
	end
	return nil
end

-- OVERWHELM: raw (pre-resist) damage feeds a fast-decaying meter;
-- concentrated fire past the threshold = brief legit knockdown via the
-- ORIGINAL stun fn (bypasses our immunity wrap), then he gets back up.
local function overwhelm(ply)
	if not IsValid(ply) or not ply:Alive() then return end
	if IsValid(ply.FakeRagdoll) then return end -- already down
	ZCJUGG.owCD = CurTime() + cv_ow_cd:GetFloat()
	ZCJUGG.owMeter = 0
	local stun = ZCJUGG.origLightStun or (hg and hg.LightStunPlayer)
	if stun then stun(ply, cv_ow_time:GetFloat()) end
	if ply.Notify then
		ply:Notify("You're overwhelmed - too much incoming fire!", 1, "zc_jugg_ow", 1, nil, Color(255, 170, 70))
	end
end

-- ARMOR DEGRADATION (v2.5): stock never wears regular armor (only the
-- protovisor ever decrements armors_health) - plates were forever. Now
-- the jugg's pieces wear: protec() already multiplies protection by
-- armors_health, so a worn plate genuinely stops less (rifles start
-- punching through a half-worn vest long before it dies). At zero the
-- piece is DESTROYED: dropped off his body, announced, HUD chip dark.
-- Pools = raw bullet damage a piece can eat at zc_jugg_armorwear 1.
local WEAR_POOL = { torso = 3000, head = 1000, face = 600 }
local WEAR_NAME = { torso = "VEST", head = "HELMET", face = "MASK" }

local function wearPiece(ply, slot, amount)
	local armors = ply.armors
	local id = armors and armors[slot]
	if not id then return end
	ply.armors_health = ply.armors_health or {}
	local cur = (ply.armors_health[id] or 1) - amount / WEAR_POOL[slot]
	if cur <= 0 then
		ply.armors_health[id] = nil -- fresh if the id is ever worn again
		if hg and hg.DropArmorForce then pcall(hg.DropArmorForce, ply, id) end
		if armors[slot] == id then armors[slot] = nil end -- belt: gone even if the drop failed
		PrintMessage(HUD_PRINTTALK, "[JUGGERNAUT] His " .. WEAR_NAME[slot] .. " is destroyed!")
	else
		ply.armors_health[id] = cur
	end
end

-- classify the hit by damage position against the HIT entity's bones
-- (the ragdoll's while he's down): skull radius -> helmet+mask 65/35,
-- chest radius -> vest, anything else (limbs) wears nothing.
local function wearFromHit(ply, ent, dmgInfo, raw)
	local mult = cv_wear:GetFloat()
	if mult <= 0 or raw <= 0 then return end
	if not dmgInfo:IsDamageType(DMG_BULLET + DMG_BUCKSHOT) then return end
	local pos = dmgInfo:GetDamagePosition()
	if not pos or pos == vector_origin then return end
	local amount = raw * mult
	local b = ent:LookupBone("ValveBiped.Bip01_Head1")
	local bp = b and ent:GetBonePosition(b)
	if bp and pos:DistToSqr(bp) < 121 then -- within 11u of the skull
		wearPiece(ply, "head", amount * 0.65)
		wearPiece(ply, "face", amount * 0.35)
		return
	end
	b = ent:LookupBone("ValveBiped.Bip01_Spine2")
	bp = b and ent:GetBonePosition(b)
	if bp and pos:DistToSqr(bp) < 400 then -- within 20u of the chest
		wearPiece(ply, "torso", amount)
	end
end

hook.Add("EntityTakeDamage", "zc_jugg_armor", function(ent, dmgInfo)
	local ply = resolveJugg(ent)
	if not ply then return end
	local raw = dmgInfo:GetDamage()
	local r = cv_resist:GetFloat()
	if r > 1 then
		dmgInfo:ScaleDamage(1 / r)
		-- also scale the FORCE: massed fire shoves/staggers otherwise
		dmgInfo:SetDamageForce(dmgInfo:GetDamageForce() / r)
	end

	-- overwhelm meter (standing only; decays in the sustain tick)
	if cv_ow:GetBool() and ent == ply and raw > 0 then
		ZCJUGG.owMeter = (ZCJUGG.owMeter or 0) + raw
		if ZCJUGG.owMeter >= cv_ow_thresh:GetFloat() and (ZCJUGG.owCD or 0) < CurTime() then
			timer.Simple(0, function() overwhelm(ply) end)
		end
	end

	-- armor wear (v2.5): standing or downed - his plates are on either way
	wearFromHit(ply, ent, dmgInfo, raw)

	-- SUPERFIGHTER FLICKER: on for exactly the duration of homigrad's
	-- damage handler (runs after us at default priority) - organs take
	-- zero damage except the armor hitboxes, no wounds/bleeding, nothing
	-- feeds the collapse pools. Cleared by the priority-2 hook below +
	-- a next-tick belt so SetupMove NEVER sees it -> movement stays normal.
	if cv_sf:GetBool() and ply.organism and not ply.organism.superfighter then
		ply.organism.superfighter = true
		ply.zc_sfFlicker = true
		timer.Simple(0, function()
			if IsValid(ply) and ply.zc_sfFlicker and ply.organism then
				ply.organism.superfighter = nil
				ply.zc_sfFlicker = nil
			end
		end)
	end
end, -2)

hook.Add("EntityTakeDamage", "zc_jugg_sf_clear", function(ent)
	local ply = resolveJugg(ent)
	if ply and ply.zc_sfFlicker and ply.organism then
		ply.organism.superfighter = nil
		ply.zc_sfFlicker = nil
	end
end, 2)

-- ---- speed cap: engine-level, per-command (organism reasserts
--      RunSpeed every tick, so this is the only lever that holds) ----
hook.Add("Move", "zc_jugg_speedcap", function(ply, mv)
	if not isJugg(ply) then return end
	local cap = cv_maxspeed:GetFloat()
	if cap <= 0 then return end
	if mv:GetMaxClientSpeed() > cap then mv:SetMaxClientSpeed(cap) end
	if mv:GetMaxSpeed() > cap then mv:SetMaxSpeed(cap) end
end)

-- ---- sustain tick: blood regen + IRON WILL ----
-- Iron will is what stops the "plinked to death" failure mode: the
-- organism KOs on spine trauma / consciousness / shock (sv_organism:102),
-- NOT via the stun functions - and every bullet the armor STOPS feeds
-- spine3 through the plate-punch feedback. Massed small arms would
-- otherwise collapse him for a ground execution. So we damp those
-- pools every second: he does not fall over from suppression.
-- 0.25s tick: a 1s tick let burst fire spike spine trauma past the
-- collapse thresholds BETWEEN ticks - this stays ahead of the spikes
local SLOTS = { "torso", "head", "face" } -- v2.4 HUD chip order (VEST/HELM/MASK)
timer.Create("zc_jugg_bloodregen", 0.25, 0, function()
	local ply = ZCJUGG.current
	if not isJugg(ply) or not ply:Alive() or not juggRound() then return end
	-- round clock (checked while the jugg lives; his death ends it anyway)
	if ZCJUGG.roundEndsAt then
		local left = ZCJUGG.roundEndsAt - CurTime()
		if left <= 0 then
			ZCJUGG.roundEndsAt = nil
			PrintMessage(HUD_PRINTTALK, "[JUGGERNAUT] TIME'S UP - the hunters survived. The Juggernaut falls.")
			ply:Kill() -- stock end: traitor dead + hunters alive = hunters win
			return
		elseif left <= 10 and not ZCJUGG.warned10 then
			ZCJUGG.warned10 = true
			PrintMessage(HUD_PRINTTALK, "[JUGGERNAUT] 10 seconds left!")
		elseif left <= 60 and not ZCJUGG.warned60 then
			ZCJUGG.warned60 = true
			PrintMessage(HUD_PRINTTALK, "[JUGGERNAUT] One minute remains - survive!")
		end
	end

	local org = ply.organism
	if not org then return end
	if org.blood then org.blood = math.min(5000, org.blood + cv_regen:GetFloat() * 0.25) end
	if cv_sf:GetBool() and ply:Health() < ply:GetMaxHealth() then
		ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + cv_hpregen:GetFloat() * 0.25))
	end
	if ZCJUGG.owMeter and ZCJUGG.owMeter > 0 then
		ZCJUGG.owMeter = ZCJUGG.owMeter * 0.7 -- ~2s memory
		if ZCJUGG.owMeter < 0.5 then ZCJUGG.owMeter = 0 end
	end

	-- v2.4 STATUS BROADCAST: suppression + jugg HP + armor slots, sent
	-- EVERY tick (4x/s) while he lives - no redundancy gating anymore,
	-- because packet freshness IS the client's show/hide gate for the
	-- persistent panel (silence = he's dead / round over = panel fades).
	-- Old (pre-v2.4) clients simply never read past the first 2 fields.
	local owfrac = 0
	if cv_ow:GetBool() then
		owfrac = math.Clamp((ZCJUGG.owMeter or 0) / math.max(cv_ow_thresh:GetFloat(), 1), 0, 1)
	end
	local armors = ply.armors or {}
	local ahp = ply.armors_health or {}
	net.Start("zc_jugg_ow", true)
	net.WriteFloat(owfrac)
	net.WriteBool((ZCJUGG.owCD or 0) > CurTime())
	net.WriteUInt(math.Clamp(math.Round(ply:Health()), 0, 8191), 13)
	net.WriteUInt(math.Clamp(math.Round(ply:GetMaxHealth()), 1, 8191), 13)
	for i = 1, 3 do
		local id = armors[SLOTS[i]]
		if id then
			net.WriteBool(true)
			-- per-piece condition (armors_health; stock only degrades the
			-- protovisor today, but wired through so it's future-proof)
			net.WriteUInt(math.Clamp(math.Round((ahp[id] or 1) * 31), 0, 31), 5)
		else
			net.WriteBool(false)
		end
	end
	net.Broadcast()
	if cv_ironwill:GetBool() then
		if isnumber(org.spine1) then org.spine1 = org.spine1 * 0.75 end
		if isnumber(org.spine2) then org.spine2 = org.spine2 * 0.75 end
		if isnumber(org.spine3) then org.spine3 = org.spine3 * 0.75 end
		if isnumber(org.shock) then org.shock = org.shock * 0.75 end
		if isnumber(org.pain) then org.pain = org.pain * 0.85 end
		if isnumber(org.consciousness) and org.consciousness < 1 then
			org.consciousness = math.min(1, org.consciousness + 0.1)
		end
	end
end)

-- ---- ONE JUGG ONLY: homicide_traitoramount forced to 1 for jugg rounds ----
-- The mode is vote-only (Chance 0), so zb.nextround == "juggernaut" is the
-- reliable early signal (the vote live-applies it well before selection;
-- sv_homicide:1166 reads the convar live at traitor pick). Saved value is
-- restored once selection is done, or if the vote flips away.
local function tamountCheck()
	local cvar = GetConVar("homicide_traitoramount")
	if not cvar or not zb then return end
	if zb.nextround == "juggernaut" then
		if ZCJUGG.savedTAmount == nil and cvar:GetInt() ~= 1 then
			ZCJUGG.savedTAmount = cvar:GetInt()
			cvar:SetInt(1)
			print("[Juggernaut] traitor amount -> 1 for the upcoming round (was " .. ZCJUGG.savedTAmount .. ")")
		end
	elseif ZCJUGG.savedTAmount ~= nil and zb.nextround ~= nil then
		-- vote flipped to something else before the round started
		cvar:SetInt(ZCJUGG.savedTAmount)
		print("[Juggernaut] traitor amount restored to " .. ZCJUGG.savedTAmount)
		ZCJUGG.savedTAmount = nil
	end
end

-- instant, race-free path: the (patched) mode vote announces every apply
hook.Add("ZC_ModeVoteApplied", "zc_jugg_tamount_instant", tamountCheck)
-- fallback poll (covers hand-set zb.nextround / older vote file), 0.25s
timer.Create("zc_jugg_tamount", 0.25, 0, tamountCheck)

hook.Add("ZB_StartRound", "zc_jugg_tamount_restore", function()
	if ZCJUGG.savedTAmount == nil then return end
	timer.Simple(8, function() -- traitor selection long done by now
		if ZCJUGG.savedTAmount ~= nil then
			local cvar = GetConVar("homicide_traitoramount")
			if cvar then cvar:SetInt(ZCJUGG.savedTAmount) end
			print("[Juggernaut] traitor amount restored to " .. ZCJUGG.savedTAmount)
			ZCJUGG.savedTAmount = nil
		end
	end)
end)


-- ---- cleanup ----
local function clearJugg()
	local ply = ZCJUGG.current
	if IsValid(ply) then
		ply.zc_isJugg = nil
		if ply.organism and ply.zc_sfFlicker then ply.organism.superfighter = nil end
		ply.zc_sfFlicker = nil
		ply:SetMaxHealth(100)
		if ply:Health() > 100 then ply:SetHealth(100) end
		-- v2.5: forget wear on whatever he's still wearing (next round's
		-- plates start fresh; armors_health persists per-player)
		if istable(ply.armors_health) and istable(ply.armors) then
			for _, id in pairs(ply.armors) do ply.armors_health[id] = nil end
		end
	end
	ZCJUGG.current = nil
	ZCJUGG.owMeter = nil
	ZCJUGG.owCD = nil
	ZCJUGG.roundEndsAt = nil
	ZCJUGG.warned60, ZCJUGG.warned10 = nil, nil
end
hook.Add("ZB_EndRound", "zc_jugg_cleanup", clearJugg)
hook.Add("ZB_PreRoundStart", "zc_jugg_cleanup_pre", clearJugg)
hook.Add("PlayerDisconnected", "zc_jugg_cleanup_dc", function(ply)
	if ply == ZCJUGG.current then clearJugg() end
end)

print("[Juggernaut] server loaded - resist x" .. cv_resist:GetFloat() .. ", vote key: juggernaut")
