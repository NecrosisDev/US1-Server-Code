-- ============================================================
--  ZC ABNO NEWBIE v1.0 - makes the Abnormalties system learnable
-- ------------------------------------------------------------
--  Joey: "rn its hard to figure out anything." Approved scope:
--  failure coaching, zone perception, /myabno from the start,
--  ritual proximity hints, warm/cold, witnesses learn, zone
--  echoes, ritual completion broadcast, HUD-notify mirror.
--  (The 6-chant reveal threshold stays STOCK by request.)
--
--  DESIGN RULES:
--   * everything speaks through ONE whisper channel with a
--     per-player rate limit (zc_abno_hintcd) - chat never floods
--   * hints that solve the puzzle are EARNED: ritual hints go only
--     to players who have chanted into that zone; coaching only
--     after 3 repeats of the same failed phrase (stock's full
--     reveal still needs its 6)
--   * NOTHING in the gamemode is edited. Three PLUGIN functions
--     are wrapped (ShowMessage family -> HUD mirror;
--     AddConsequencesToZoneChanters -> the single choke point every
--     ritual calls exactly once at fire time = completion detector)
--     with a 1s self-healing sync, hotload-safe via the persistent
--     ZCABNONEWBIE table.
--   * NO overlap with zcity_traitor_picker's abno hooks (it owns
--     the blood-trace gate, the resurrection swarm gate and the
--     symptom wrap - this addon touches none of those slots).
--
--  PERF: with the system disabled everything early-outs on the
--  global flag; enabled, the only recurring work is a 2s proximity
--  timer that exits immediately when no zones exist.
--
--  Convars (all FCVAR_ARCHIVE, live):
--    zc_abno_hints          1   master for every whisper below
--    zc_abno_hintcd         2   min seconds between hints per player
--    zc_abno_coach          1   whisper WHY a phrase failed (after 3 repeats)
--    zc_abno_warmcold       1   "closer..." / "further..." between attempts
--    zc_abno_zonesense      1   zone entry whispers + chant growth progress
--    zc_abno_ritualhints    1   pattern + resource hints in ready hot zones
--    zc_abno_startpage      1   grant page-8 knowledge (/myabno) on join
--    zc_abno_witnesses      1   ritual completion teaches everyone in the zone
--    zc_abno_echoes         1   last round's hot-zone spots whisper once
--    zc_abno_announce       1   server-wide broadcast when a ritual completes
--    zc_abno_announce_names 0   include the ritual's name in the broadcast
--    zc_abno_notifyhud      1   mirror every abno message into the HUD notify
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCABNONEWBIE = ZCABNONEWBIE or {}
local K = ZCABNONEWBIE
K.echoes = K.echoes or {}
K.hotSnap = K.hotSnap or {}

local cv_hints    = CreateConVar("zc_abno_hints", "1", FCVAR_ARCHIVE, "Master switch for all beginner whispers", 0, 1)
local cv_hintcd   = CreateConVar("zc_abno_hintcd", "2", FCVAR_ARCHIVE, "Minimum seconds between hints per player", 0, 30)
local cv_coach    = CreateConVar("zc_abno_coach", "1", FCVAR_ARCHIVE, "Whisper why a phrase failed (after 3 repeats)", 0, 1)
local cv_warmcold = CreateConVar("zc_abno_warmcold", "1", FCVAR_ARCHIVE, "Closer/further feedback between attempts", 0, 1)
local cv_sense    = CreateConVar("zc_abno_zonesense", "1", FCVAR_ARCHIVE, "Zone entry whispers + chant growth progress", 0, 1)
local cv_rhints   = CreateConVar("zc_abno_ritualhints", "1", FCVAR_ARCHIVE, "Pattern/resource hints in ready hot zones (chanters only)", 0, 1)
local cv_start    = CreateConVar("zc_abno_startpage", "1", FCVAR_ARCHIVE, "Grant page-8 knowledge (/myabno) on join", 0, 1)
local cv_witness  = CreateConVar("zc_abno_witnesses", "1", FCVAR_ARCHIVE, "Ritual completion grants page-8 knowledge to everyone in the zone", 0, 1)
local cv_echoes   = CreateConVar("zc_abno_echoes", "1", FCVAR_ARCHIVE, "Last round's hot-zone spots whisper once next round", 0, 1)
local cv_announce = CreateConVar("zc_abno_announce", "1", FCVAR_ARCHIVE, "Server-wide broadcast when a ritual completes", 0, 1)
local cv_annames  = CreateConVar("zc_abno_announce_names", "0", FCVAR_ARCHIVE, "Broadcast includes the ritual's name", 0, 1)
local cv_hud      = CreateConVar("zc_abno_notifyhud", "1", FCVAR_ARCHIVE, "Mirror abno messages into the homigrad HUD notify", 0, 1)

local ABNO_CLR = Color(150, 0, 0)

local function PL() return hg and hg.Abnormalties end
local function enabled() return GetGlobalBool("AbnormaltiesEnabled", false) end

-- ------------------------------------------------------------
--  THE WHISPER CHANNEL - one voice, rate-limited per player.
--  `force` bypasses the cooldown for messages that must land
--  (ritual completion, witness moments).
-- ------------------------------------------------------------
local function whisper(ply, msg, force)
	if not cv_hints:GetBool() then return end
	local P = PL()
	if not (P and IsValid(ply)) then return end
	local now = CurTime()
	if not force and (ply.zcn_nexthint or 0) > now then return end
	ply.zcn_nexthint = now + cv_hintcd:GetFloat()
	P.ShowMessage(ply, msg) -- wrapped below: red chat + HUD notify
end

-- ------------------------------------------------------------
--  WRAP 1: ShowMessage family -> HUD notify mirror
--  (In/ToAll variants write net directly in stock, so each gets
--  its own wrap. Notify signature: msg, delay(anti-repeat key CD),
--  msgKey(defaults to msg), showTime, func, color - sv_notification)
-- ------------------------------------------------------------
local function hudNotify(ply, msg)
	if not cv_hud:GetBool() then return end
	if not (IsValid(ply) and ply.Notify) then return end
	ply:Notify(msg, 2, nil, 0, nil, ABNO_CLR)
end

local wraps = {} -- name -> our wrapped fn (identity for the sync)

local function installWraps()
	local P = PL()
	if not P then return end

	-- capture originals exactly once, never our own wrappers
	local function capture(name)
		local cur = P[name]
		if isfunction(cur) and cur ~= wraps[name] and cur ~= K["my_" .. name] then
			K["orig_" .. name] = cur
		end
	end

	capture("ShowMessage")
	wraps.ShowMessage = wraps.ShowMessage or function(ply, msg)
		K.orig_ShowMessage(ply, msg)
		hudNotify(ply, msg)
	end

	capture("ShowMessageInSphere")
	wraps.ShowMessageInSphere = wraps.ShowMessageInSphere or function(msg, pos, radius)
		K.orig_ShowMessageInSphere(msg, pos, radius)
		if cv_hud:GetBool() then
			for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
				if ent:IsPlayer() then hudNotify(ent, msg) end
			end
		end
	end

	capture("ShowMessageToAll")
	wraps.ShowMessageToAll = wraps.ShowMessageToAll or function(msg)
		K.orig_ShowMessageToAll(msg)
		if cv_hud:GetBool() then
			for _, ply in player.Iterator() do hudNotify(ply, msg) end
		end
	end

	capture("ShowMessageToAllExcept")
	wraps.ShowMessageToAllExcept = wraps.ShowMessageToAllExcept or function(msg, exc)
		K.orig_ShowMessageToAllExcept(msg, exc)
		if cv_hud:GetBool() then
			for _, ply in player.Iterator() do
				if ply ~= exc then hudNotify(ply, msg) end
			end
		end
	end

	for name, fn in pairs(wraps) do
		if K["orig_" .. name] and P[name] ~= fn then
			K["my_" .. name] = fn
			P[name] = fn
		end
	end
end

-- ------------------------------------------------------------
--  WRAP 2: AddConsequencesToZoneChanters = ritual completion.
--  Every successful Try* calls it exactly once, at fire time, with
--  (zone, amt_mul). The mul identifies the ritual; -1 is Heal OR
--  Thaumaturgic Arm - disambiguated by the fresh (Time > now+4)
--  entry each Try* schedules BEFORE this call.
-- ------------------------------------------------------------
local function ritualName(mul)
	local P = PL()
	if mul == -1 then
		if P and P.ConjureTA then
			for _, info in pairs(P.ConjureTA.ToConjure or {}) do
				if (info.Time or 0) > CurTime() + 4 then return "Thaumaturgic Arm" end
			end
		end
		return "Heal"
	end
	return ({ [-2] = "Resurrection", [2] = "Invisibility", [1] = "Broadcast",
		[3] = "Equalizer", [-3] = "Bleeding Musket" })[mul] or "unknown"
end

-- additive page-8 grant - NEVER overwrites existing pages
local function grantPage8(ply)
	local P = PL()
	if not (P and IsValid(ply)) then return end
	if ply.AbnormaltiesReady then
		local k = ply.AbnormaltiesKnowledge or {}
		if not k.consequences then
			k.consequences = true
			P.SetKnowledge(ply, k)
		end
	else
		-- stock merges StoredKnowledge into the DB row on load (additive)
		ply.AbnormaltiesStoredKnowledge = ply.AbnormaltiesStoredKnowledge or {}
		ply.AbnormaltiesStoredKnowledge.consequences = true
		P.LoadConsequences(ply)
	end
end

local myAddCons
myAddCons = function(zone, amt_mul)
	K.orig_AddCons(zone, amt_mul)

	-- a ritual just fired in `zone`
	local P = PL()
	if not P then return end
	local name = ritualName(amt_mul)

	if cv_announce:GetBool() then
		local msg = cv_annames:GetBool()
			and ("Something wicked stirs... the " .. name .. " ritual has been completed.")
			or "Something wicked stirs... a ritual has been completed."
		P.ShowMessageToAll(msg)
	end

	if cv_witness:GetBool() and zone and zone.Pos then
		for _, ent in ipairs(ents.FindInSphere(zone.Pos, zone.Radius or 200)) do
			if ent:IsPlayer() and ent:Alive() then
				local hadIt = ent.AbnormaltiesReady and ent.AbnormaltiesKnowledge
					and ent.AbnormaltiesKnowledge.consequences
				grantPage8(ent)
				if not hadIt then
					whisper(ent, "You saw something you cannot unsee. (/myabno)", true)
				end
			end
		end
	end
end

local function installConsWrap()
	local P = PL()
	if not P then return end
	local cur = P.AddConsequencesToZoneChanters
	if cur == myAddCons then return end
	if isfunction(cur) and cur ~= K.myAddCons then
		K.orig_AddCons = cur
	end
	if K.orig_AddCons then
		K.myAddCons = myAddCons
		P.AddConsequencesToZoneChanters = myAddCons
	end
end

timer.Create("zc_abno_newbie_sync", 1, 0, function()
	if not PL() then return end
	installWraps()
	installConsWrap()
end)

-- ------------------------------------------------------------
--  RITUAL DEFINITIONS (mirrors the abnormalty_* modules) for the
--  proximity hints: thresholds on zone.Abnormalties, the 5-chant
--  pattern spelled out, and the resource check.
-- ------------------------------------------------------------
local RITUALS = {
	{ name = "Heal", thr = { sacrifice = 10, help = 20 },
	  chant = "help, sacrifice, help, sacrifice, help",
	  blood = 2500 },
	{ name = "Invisibility", thr = { shield = 10, help = 20 },
	  chant = "five strong shield phrases",
	  eq = 50 },
	{ name = "Broadcast", thr = { help = 20, ritual = 10 },
	  chant = "five strong help phrases",
	  eq = 15 },
	{ name = "Resurrection", thr = { sacrifice = 50, help = 30, ritual = 10 },
	  chant = "five strong ritual phrases",
	  blood = 3500 },
	{ name = "Thaumaturgic Arm", thr = { ritual = 20, harm = 10, sacrifice = 10 },
	  chant = "ritual, sacrifice, ritual, sacrifice, ritual (a melee weapon must lie in the zone)",
	  eq = 5, blood = 250 },
	{ name = "Equalizer", thr = { shield = 20, ritual = 10, help = 10 },
	  chant = "strong shield, help, sacrifice, strong shield, help",
	  eq = 400 },
	{ name = "Bleeding Musket", thr = { harm = 20, ritual = 10, sacrifice = 10 },
	  chant = "strong harm, ritual, sacrifice, strong harm, ritual",
	  blood = 25000 },
}

local function ritualHint(ply, zone, zoneId)
	local P = PL()
	if not (P and cv_rhints:GetBool()) then return end
	if not (zone.Chanters and zone.Chanters[ply]) then return end -- earned: chanters only
	local zoneAbn = zone.Abnormalties or {} -- hand-made zones may lack it
	ply.zcn_rhintAt = ply.zcn_rhintAt or {}

	for _, r in ipairs(RITUALS) do
		local met = true
		for meaning, need in pairs(r.thr) do
			if (zoneAbn[meaning] or 0) < need then met = false break end
		end
		if met then
			local key = zoneId .. ":" .. r.name
			if (ply.zcn_rhintAt[key] or 0) <= CurTime() then
				ply.zcn_rhintAt[key] = CurTime() + 30
				local short = {}
				if r.blood then
					local have = P.GetZoneOrPlyBlood(zone, ply)
					if have < r.blood then short[#short + 1] = ("blood %d/%d"):format(math.floor(have), r.blood) end
				end
				if r.eq then
					local have = P.GetZoneOrPlyEqualizers(zone, ply)
					if have < r.eq then short[#short + 1] = ("equalizers %d/%d"):format(math.floor(have), r.eq) end
				end
				if #short > 0 then
					whisper(ply, "The zone yearns for the " .. r.name .. " - but thirsts: " .. table.concat(short, ", "))
				else
					whisper(ply, "The zone is ready for the " .. r.name .. " - chant " .. r.chant .. ", each within 10 seconds")
				end
				return -- one ritual hint at a time
			end
		end
	end
end

-- ------------------------------------------------------------
--  CHAT LISTENER: coaching, warm/cold, chant progress.
--  Runs ALONGSIDE the stock "Abnormalties" hook (different name,
--  both fire). Zone reads happen NEXT TICK so stock's update -
--  whatever the hook order - has already landed.
-- ------------------------------------------------------------
hook.Add("HG_PlayerSay", "zc_abno_newbie", function(ply, txtTbl, text)
	if not (enabled() and cv_hints:GetBool()) then return end
	local P = PL()
	if not (P and IsValid(ply) and ply:Alive()) then return end
	if string.sub(text, 1, 1) == "/" then return end

	local lowered = P.String.StringLower(text)
	local abnormalty, words, _, uselessness = P.TranslateWordsToAbnormalty(lowered)
	local posCount, posList = 0, {}
	for meaning, amt in pairs(abnormalty) do
		if amt > 0 then
			posCount = posCount + 1
			posList[#posList + 1] = meaning .. " " .. amt
		end
	end
	local pure = (posCount == 1 and uselessness == 0)

	if pure then
		ply.zcn_failText, ply.zcn_failN, ply.zcn_prevScore = nil, nil, nil
		if not cv_sense:GetBool() then return end
		-- read the zone AFTER stock has fed it
		local pos = ply:GetPos()
		local p = ply
		timer.Simple(0, function()
			local P2 = PL()
			if not (P2 and IsValid(p)) then return end
			P2.DoWithinZones(pos, function(zoneId, zone)
				if P2.HotZones[zoneId] then
					ritualHint(p, zone, zoneId)
				else
					whisper(p, ("The zone stirs... (%d/%d)"):format(math.floor(zone.Points or 0), P2.HotZonePoints))
				end
			end)
		end)
		return
	end

	-- ---- failed phrase ----
	-- warm/cold across DIFFERENT attempts (score: lower = closer)
	local score = posCount + uselessness
	if cv_warmcold:GetBool() and ply.zcn_prevText and ply.zcn_prevText ~= lowered and ply.zcn_prevScore then
		if score < ply.zcn_prevScore then
			whisper(ply, "Closer...")
		elseif score > ply.zcn_prevScore then
			whisper(ply, "Further...")
		end
	end
	ply.zcn_prevText, ply.zcn_prevScore = lowered, score

	-- coaching on the 3rd repeat of the SAME failed phrase
	if not cv_coach:GetBool() then return end
	if ply.zcn_failText == lowered then
		ply.zcn_failN = (ply.zcn_failN or 1) + 1
	else
		ply.zcn_failText, ply.zcn_failN = lowered, 1
	end
	if ply.zcn_failN == 3 then
		if uselessness > 0 then
			whisper(ply, ("These letters are too plain - %d of 6 kinds. Weave in more."):format(6 - uselessness))
		elseif posCount > 1 then
			whisper(ply, "Meanings fight within: " .. table.concat(posList, ", ") .. ". One must silence the rest.")
		else
			whisper(ply, "The words cancel themselves to nothing.")
		end
	end
end)

-- ------------------------------------------------------------
--  PROXIMITY TIMER (2s): zone entry whispers + echoes.
--  Exits immediately when there is nothing to check.
-- ------------------------------------------------------------
timer.Create("zc_abno_newbie_sense", 2, 0, function()
	local P = PL()
	if not (P and enabled() and cv_hints:GetBool()) then return end

	-- keep a rolling snapshot of hot-zone positions for the echoes
	K.hotSnap = {}
	for id in pairs(P.HotZones or {}) do
		local z = P.Zones[id]
		if z then K.hotSnap[#K.hotSnap + 1] = z.Pos end
	end

	local anyZones = P.Zones[1] ~= nil
	local anyEchoes = cv_echoes:GetBool() and K.echoes[1] ~= nil
	if not anyZones and not anyEchoes then return end

	for _, ply in player.Iterator() do
		if ply:Alive() then
			local pos = ply:GetPos()

			if anyZones and cv_sense:GetBool() then
				local state = nil -- nil | "zone" | "hot"
				P.DoWithinZones(pos, function(zoneId)
					state = P.HotZones[zoneId] and "hot" or (state or "zone")
				end)
				if state ~= ply.zcn_inzone then
					if state == "hot" then
						whisper(ply, "The air feels heavy here... and it hums.")
					elseif state == "zone" then
						whisper(ply, "The air feels heavy here...")
					end
					ply.zcn_inzone = state
				end
			end

			if anyEchoes then
				ply.zcn_echoed = ply.zcn_echoed or {}
				for i, epos in ipairs(K.echoes) do
					if not ply.zcn_echoed[i] and pos:DistToSqr(epos) < 300 * 300 then
						ply.zcn_echoed[i] = true
						whisper(ply, "Something happened here, once.")
						break
					end
				end
			end
		end
	end
end)

-- round boundary: last round's hot spots become this round's echoes
hook.Add("PostCleanupMap", "zc_abno_newbie", function()
	K.echoes = K.hotSnap or {}
	K.hotSnap = {}
	for _, ply in player.Iterator() do
		ply.zcn_inzone = nil
		ply.zcn_echoed = nil
		ply.zcn_rhintAt = nil
		ply.zcn_failText, ply.zcn_failN = nil, nil
		ply.zcn_prevText, ply.zcn_prevScore = nil, nil
	end
end)

-- ------------------------------------------------------------
--  /myabno FROM THE START - additive page-8 grant on join
-- ------------------------------------------------------------
hook.Add("PlayerInitialSpawn", "zc_abno_newbie", function(ply)
	timer.Simple(15, function()
		if not (IsValid(ply) and cv_start:GetBool() and enabled()) then return end
		grantPage8(ply)
	end)
end)

print("[AbnoNewbie] loaded - beginner whispers arm once the gamemode exists (1s sync); zc_abno_hints 0 silences everything")
