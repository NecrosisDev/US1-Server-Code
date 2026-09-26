-- ============================================================
--  ZC WATCHDOG - core (v1)  |  ZCity-native serverside anticheat
-- ------------------------------------------------------------
--  Standalone. No dependency on LSAC or any other AC.
--
--  DESIGN LAWS
--   1. WATCH MODE by default: detections file DOSSIERS and ping
--      staff. Nothing kicks or bans. Humans judge. (WD.Config.watchMode)
--   2. Excuse-first: every ZCity state that legitimately produces
--      cheat-like data (KO/otrub, fake-ragdoll, stun, viewpunch,
--      vehicles, teleports, berserk speed, spectate, lag) is
--      subtracted BEFORE suspicion accrues. See WD.Excused().
--   3. Invisible to cheaters: pure serverside. The only client file
--      is the staff panel - a dumb net-driven renderer, superadmin
--      gated, containing ZERO thresholds or detection logic.
--   4. Cheap: ONE StartCommand sampler here builds a per-player
--      "track" each tick; modules read it instead of re-sampling.
--
--  Modules register via WD.RegisterModule(name, tbl). A module may
--  provide tbl.Sample(ply, cmd, track) for per-tick work; event-based
--  modules (fire, noclip, net) add their own hooks in their own file.
--
--  Commands (superadmin / console): wd_status  wd_dossiers  wd_config
-- ============================================================
if not SERVER then return end

WD = WD or {}
WD.VERSION      = "1.1"
WD.Modules      = WD.Modules or {}      -- name -> module tbl
WD.Suspicion    = WD.Suspicion or {}    -- sid -> { module -> score }
WD.track        = WD.track or {}        -- sid -> per-tick shared state
WD.evidence     = WD.evidence or {}     -- sid -> ring buffer {items,pos}
WD._lastDamage  = WD._lastDamage or {}  -- sid -> CurTime of last damage taken
WD._lastSpawn   = WD._lastSpawn or {}   -- sid -> CurTime of last spawn
WD._lastTP      = WD._lastTP or {}      -- sid -> CurTime of last suspected teleport
WD._lastFire    = WD._lastFire or {}    -- sid -> CurTime the player last fired bullets
WD._suppress    = WD._suppress or {}    -- sid -> { until=t, reason=s }
WD._ping        = WD._ping or {}        -- sid -> last ping sample
WD._dcool       = WD._dcool or {}       -- "sid|module" -> { until=t, held=n } dossier cooldown
WD._warn        = WD._warn or {}        -- "sid|module" -> { active, cool } early climb warning state

-- ---------------- CONFIG (server-only, NEVER networked) ----------------
WD.Config = WD.Config or {
	enabled       = true,
	watchMode     = true,     -- true => never auto-punish, dossiers only
	dossierDir    = "watchdog",
	pingStaff     = true,     -- chat-ping online staff (operator+) on a dossier
	logConsole    = true,
	evidenceRing  = 48,       -- snapshots kept per player for dossiers
	recentSpawn   = 3.0,      -- s after spawn where view/move is excused
	viewpunchWin  = 0.4,      -- s after taking damage where view is excused
	teleportWin   = 0.5,      -- s after a suspected teleport where move/view excused
	postExcuse    = 0.75,     -- s of grace right after a KO/ragdoll/vehicle state clears
	pingCeil      = 300,      -- ping above this => latency not "stable"
	pingJump      = 90,       -- ping delta above this => not "stable" this sample
	dossierCool   = 45,       -- s min between dossiers for the same player+module (anti-flood)
	dossierMax    = 500,      -- keep at most this many dossier files (oldest pruned)
	modules       = {},       -- name -> bool override (nil = module default)

	-- ---- staff / elevated-role exemption (ULX / ULib) ----
	exemptElevated = true,    -- ignore anyone ranked above regular "user"
	exemptMinGroup = "operator", -- ULX rank at/above which players are ignored (by inheritance)
	exemptGroups   = {},      -- extra group names to ALWAYS ignore  (e.g. { mymod = true })
	watchGroups    = {},      -- group names to ALWAYS watch even if elevated (testing/override)

	-- ---- staff alerts (who hears about a detection, and how) ----
	-- (pingStaff above = the chat line; both alerts go to operator-and-above)
	alertToast     = true,    -- on-screen corner toast + sound to staff on a dossier
	alertMinGroup  = "operator", -- lowest ULX rank that receives alerts ("operator and above")
	warnStaff      = true,    -- early chat line to staff when a score is CLIMBING (pre-dossier)
	warnPct        = 50,      -- ...at this % of the module's threshold
}

-- Backfill any keys added in a newer version, so HOTLOADING core over an
-- already-running watchdog (where WD.Config already exists, so the literal
-- above was skipped) still picks up new settings instead of leaving them nil.
do
	local defaults = {
		enabled = true, watchMode = true, dossierDir = "watchdog", pingStaff = true,
		logConsole = true, evidenceRing = 48, recentSpawn = 3.0, viewpunchWin = 0.4,
		teleportWin = 0.5, postExcuse = 0.75, pingCeil = 300, pingJump = 90,
		dossierCool = 45, dossierMax = 500, exemptElevated = true,
		exemptMinGroup = "operator", alertToast = true, alertMinGroup = "operator",
		warnStaff = true, warnPct = 50,
	}
	for k, v in pairs(defaults) do
		if WD.Config[k] == nil then WD.Config[k] = v end  -- (== nil keeps an explicit false)
	end
	WD.Config.modules      = WD.Config.modules or {}
	WD.Config.exemptGroups = WD.Config.exemptGroups or {}
	WD.Config.watchGroups  = WD.Config.watchGroups or {}
end

file.CreateDir(WD.Config.dossierDir)

-- ---------------- config persistence ----------------
-- Anything set through wd_config OR the panel's Settings tab is written here
-- and re-applied on boot, so tuning survives the 2am restart (the disk-vs-RAM
-- law applies to config too). Delete the file to reset to defaults.
-- The VPN api key is deliberately NOT saved (it lives in the vpn file /
-- data/watchdog_vpnkey.txt, never in this json and never on the network).
local CONFIG_FILE = WD.Config.dossierDir .. "/config.json"

function WD.SaveConfig()
	local out = {}
	for k, v in pairs(WD.Config) do
		local ty = type(v)
		if k ~= "vpnApiKey" and (ty == "boolean" or ty == "number" or ty == "string") then
			out[k] = v
		end
	end
	out.modules          = WD.Config.modules
	out.exemptGroups     = WD.Config.exemptGroups
	out.watchGroups      = WD.Config.watchGroups
	out.luaerrSignatures = WD.Config.luaerrSignatures
	out.vpnExempt        = WD.Config.vpnExempt        -- VPN whitelist (wd_vpn_exempt)
	out.backdoorNets     = WD.Config.backdoorNets     -- net defence lists
	out.honeypotNets     = WD.Config.honeypotNets
	out.httpBlock        = WD.Config.httpBlock         -- HTTP blocklist
	file.Write(CONFIG_FILE, util.TableToJSON(out, true))
end

do
	local raw = file.Read(CONFIG_FILE, "DATA")
	if raw then
		local t = util.JSONToTable(raw)
		if istable(t) then
			for k, v in pairs(t) do WD.Config[k] = v end
			file.CreateDir(WD.Config.dossierDir)   -- in case dossierDir itself was overridden
			if WD.Config.logConsole then print("[Watchdog] loaded saved config (data/" .. CONFIG_FILE .. ")") end
		end
	end
	if WD.Config.exemptElevated == false then
		print("[Watchdog] !! exemptElevated is FALSE - STAFF ARE BEING WATCHED (testing mode). `wd_config exemptElevated true` to restore.")
	end
end

-- ---------------- module registry ----------------
function WD.RegisterModule(name, tbl)
	tbl.name = name
	if tbl.enabled == nil then tbl.enabled = true end
	tbl.threshold = tbl.threshold or 100
	WD.Modules[name] = tbl
	if WD.Config.logConsole then print("[Watchdog] module registered: " .. name) end
end

function WD.ModuleEnabled(name)
	local ov = WD.Config.modules[name]
	if ov ~= nil then return ov end
	local m = WD.Modules[name]
	return m and m.enabled ~= false
end

-- ---------------- staff / elevated-role exemption (ULX / ULib) ----------------
-- "Above regular user" = admin/superadmin, operator (and anything inheriting
-- from it), or a custom ULX group that actually grants permissions beyond the
-- default "user" group. Walks the ULib inheritance/allow data to catch custom
-- roles. Falls back to admin checks if ULib data isn't present.
local function groupHasPermsAboveUser(g)
	if not (ULib and ULib.ucl and ULib.ucl.groups) then return false end
	local seen = {}
	while g and g ~= "" and g ~= "user" and not seen[g] do
		seen[g] = true
		local data = ULib.ucl.groups[g]
		if not data then return true end                    -- unknown non-user group => treat elevated
		if data.allow and next(data.allow) ~= nil then return true end  -- has its own granted perms
		g = data.inherit_from or "user"                     -- climb toward the base
	end
	return false
end

local function computeExempt(ply)
	if not WD.Config.exemptElevated then return false end
	local g = ply:GetUserGroup() or "user"
	if WD.Config.watchGroups[g] then return false end        -- forced watch (override)
	if WD.Config.exemptGroups[g] then return true end        -- explicit exempt
	if ply:IsAdmin() or ply:IsSuperAdmin() then return true end          -- admin/superadmin (+CAMI inheritors)
	if ply.CheckGroup and ply:CheckGroup(WD.Config.exemptMinGroup) then return true end  -- operator+ (ULib inheritance)
	if g ~= "user" and groupHasPermsAboveUser(g) then return true end    -- custom role above user
	return false
end

-- Cached: IsExempt is on the per-tick sampler AND the net hot path, and the
-- inner ULib inheritance walk isn't free. Cache per player for a few seconds
-- (a rank change reflects within the TTL). Cache lives on the player entity so
-- it's dropped automatically on disconnect.
function WD.IsExempt(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	local now = CurTime()
	if ply._wdExT and ply._wdExT > now then return ply._wdEx end
	local v = computeExempt(ply)
	ply._wdEx, ply._wdExT = v, now + 5
	return v
end

-- Staff who should be told about detections = operator and above (by rank/
-- inheritance). Stricter than IsExempt on purpose: a cosmetic elevated group
-- (e.g. a donator perk) is exempt from detection but should NOT get cheat alerts.
function WD.IsStaff(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if ply:IsAdmin() or ply:IsSuperAdmin() then return true end
	if ply.CheckGroup and ply:CheckGroup(WD.Config.alertMinGroup or "operator") then return true end
	return false
end

-- ---------------- helpers ----------------
local function org(ply) return ply.organism end

-- Is a homigrad stun/lightstun timer currently active?
-- (org.stun / org.lightstun store an absolute CurTime() expiry.)
local function stunned(o)
	if not o then return false end
	if type(o.stun) == "number" and (o.stun - CurTime()) > 0 then return true end
	if type(o.lightstun) == "number" and (o.lightstun - CurTime()) > 0 then return true end
	return false
end

-- ---------------- rich context snapshot ----------------
function WD.Context(ply)
	local o = org(ply)
	local wep = ply:GetActiveWeapon()
	return {
		alive      = ply:Alive(),
		team       = ply:Team(),
		otrub      = o and o.otrub or false,
		fakerag    = IsValid(ply.FakeRagdoll),
		stun       = stunned(o),
		invehicle  = ply:InVehicle(),
		berserk    = o and o.berserk or 0,
		superfight = o and o.superfighter or false,
		noradren   = o and o.noradrenaline or 0,
		health     = ply:Health(),
		movetype   = ply:GetMoveType(),
		velocity   = math.Round(ply:GetVelocity():Length()),
		speed2d    = math.Round(ply:GetVelocity():Length2D()),
		runspeed   = math.Round(ply:GetRunSpeed()),
		weapon     = IsValid(wep) and wep:GetClass() or "none",
		round      = (zb and zb.CROUND) or "?",
		isTraitor  = ply.isTraitor == true,
		ping       = ply:Ping(),
		timingout  = ply:IsTimingOut(),
	}
end

-- ---------------- EXCUSE SYSTEM ----------------
-- Returns excused(bool), reason(string). category is one of:
--   "view"  - angle snaps / spins / fake-angles / trigger view checks
--   "move"  - speed / position / noclip / teleport
--   "fire"  - shot-direction (silent aim)
--   "any"   - baseline (dead, timing out, bot, recent spawn, suppression)
function WD.Excused(ply, category)
	if not IsValid(ply) or not ply:IsPlayer() then return true, "invalid" end
	if ply:IsBot() then return true, "bot" end

	-- baseline (applies to every category)
	if not ply:Alive() then return true, "dead" end
	if ply:Team() == TEAM_SPECTATOR then return true, "spectator" end
	if ply:IsTimingOut() then return true, "timingout" end

	local sid = ply:SteamID()
	local now = CurTime()

	local sp = WD._lastSpawn[sid]
	if sp and (now - sp) < WD.Config.recentSpawn then return true, "recentspawn" end

	local su = WD._suppress[sid]
	if su and su["until"] > now then return true, "suppressed:" .. (su.reason or "?") end

	local o = org(ply)

	if category == "view" then
		if o and o.otrub then return true, "otrub" end
		if IsValid(ply.FakeRagdoll) then return true, "fakeragdoll" end
		if stunned(o) then return true, "stun" end
		if ply:InVehicle() then return true, "vehicle" end
		local dmg = WD._lastDamage[sid]
		if dmg and (now - dmg) < WD.Config.viewpunchWin then return true, "viewpunch" end
		local tp = WD._lastTP[sid]
		if tp and (now - tp) < WD.Config.teleportWin then return true, "teleport" end
	elseif category == "move" then
		if o and o.otrub then return true, "otrub" end
		if IsValid(ply.FakeRagdoll) then return true, "fakeragdoll" end
		if ply:InVehicle() then return true, "vehicle" end
		local mt = ply:GetMoveType()
		if mt == MOVETYPE_LADDER or mt == MOVETYPE_NONE or mt == MOVETYPE_OBSERVER then return true, "movetype" end
		local dmg = WD._lastDamage[sid]
		if dmg and (now - dmg) < WD.Config.viewpunchWin then return true, "knockback" end
		local tp = WD._lastTP[sid]
		if tp and (now - tp) < WD.Config.teleportWin then return true, "teleport" end
	elseif category == "fire" then
		if o and o.otrub then return true, "otrub" end
		if IsValid(ply.FakeRagdoll) then return true, "fakeragdoll" end
		if stunned(o) then return true, "stun" end
		if ply:InVehicle() then return true, "vehicle" end   -- seat orientation offsets aim vs gun
		local dmg = WD._lastDamage[sid]
		if dmg and (now - dmg) < WD.Config.viewpunchWin then return true, "viewpunch" end
	end

	return false, ""
end

-- did this player fire bullets within the last `secs` seconds?
function WD.RecentFire(ply, secs)
	local f = WD._lastFire[ply:SteamID()]
	return f and (CurTime() - f) < (secs or 2)
end

-- Manual suppression window - our own gamemode code (e.g. fear camera-locks)
-- can call this to tell Watchdog "ignore this player's checks for N seconds".
function WD.Suppress(ply, secs, reason)
	if not IsValid(ply) then return end
	WD._suppress[ply:SteamID()] = { ["until"] = CurTime() + (secs or 1), reason = reason or "manual" }
end

-- Latency stable enough to trust per-tick deltas this sample?
-- PERF: the per-tick sampler already holds the player's SteamID, so the
-- internal form takes it instead of asking the engine for it a second time
-- every usercmd. `sid or ply:SteamID()` is only reached on the path that
-- needed it anyway, so the engine calls happen in exactly the same order and
-- on exactly the same samples as before. The public WD.LatencyStable(ply)
-- signature is unchanged (prevent.lua and silentaim.lua call it).
local function latencyStable(ply, sid)
	if ply:IsTimingOut() then return false end
	local p = ply:Ping()
	if p > WD.Config.pingCeil then return false end
	local prev = WD._ping[sid or ply:SteamID()]
	if prev and math.abs(p - prev) > WD.Config.pingJump then return false end
	return true
end

function WD.LatencyStable(ply)
	return latencyStable(ply, nil)
end

-- ---------------- EVIDENCE RING ----------------
-- PERF: the ring is a FIXED-SIZE buffer (Config.evidenceRing slots), so the
-- slot about to be written already holds an entry table of the same shape.
-- Recycle it in place rather than handing a fresh table to the GC on every
-- usercmd of every player. The values written are identical -- only table
-- identity changes -- and the ONLY reader (WD.DumpEvidence, called once, from
-- WriteDossier, straight into util.TableToJSON on the same line) serialises
-- synchronously and keeps no reference.
function WD.PushEvidence(ply, kind, data)
	local sid = ply:SteamID()
	local ring = WD.evidence[sid]
	if not ring then ring = { items = {}, pos = 0 } WD.evidence[sid] = ring end
	ring.pos = (ring.pos % WD.Config.evidenceRing) + 1
	local e = ring.items[ring.pos]
	if e then
		e.t, e.kind, e.data = math.Round(CurTime(), 2), kind, data
	else
		ring.items[ring.pos] = { t = math.Round(CurTime(), 2), kind = kind, data = data }
	end
end

-- Per-tick sampler fast path. Writes exactly what
--   WD.PushEvidence(ply, "tick", { p = p, y = y, r = r, v = v, dy = dy })
-- wrote, but recycles the outgoing slot's `data` sub-table as well, so the
-- sampler allocates NO table per usercmd. The recycled tables live in a
-- private per-ring `tickdata` array, never by inspecting entry.data, so this
-- can never mutate a table that some other caller of the public PushEvidence
-- owns. The array holds one DISTINCT table per slot, so the rolling history a
-- dossier prints is exactly as long and as varied as before. `tickdata` is
-- invisible to WD.DumpEvidence (which walks ring.items) and is dropped with
-- the ring on disconnect.
local function pushTickEvidence(sid, p, y, r, v, dy)
	local ring = WD.evidence[sid]
	if not ring then ring = { items = {}, pos = 0 } WD.evidence[sid] = ring end
	local slots = ring.tickdata
	if not slots then slots = {} ring.tickdata = slots end
	local pos = (ring.pos % WD.Config.evidenceRing) + 1
	ring.pos = pos
	local d = slots[pos]
	if d then
		d.p, d.y, d.r, d.v, d.dy = p, y, r, v, dy
	else
		d = { p = p, y = y, r = r, v = v, dy = dy }
		slots[pos] = d
	end
	local e = ring.items[pos]
	if e then
		e.t, e.kind, e.data = math.Round(CurTime(), 2), "tick", d
	else
		ring.items[pos] = { t = math.Round(CurTime(), 2), kind = "tick", data = d }
	end
end

function WD.DumpEvidence(ply)
	local sid = ply:SteamID()
	local ring = WD.evidence[sid]
	if not ring then return {} end
	-- return chronological-ish (ring order is fine for a dossier)
	local out = {}
	for i = 1, #ring.items do out[i] = ring.items[i] end
	return out
end

-- ---------------- suspicion + dossier ----------------
-- action: what happened to the player alongside this dossier - "logged"
-- (default, watch mode), "kicked", or "banned". Enforcing callers pass it;
-- it lands in the dossier file, the WD_Dossier hook, and the Staff Logs tab.
function WD.AddSuspicion(ply, module, amount, evidence, action)
	if not IsValid(ply) then return end
	if not WD.Config.enabled then return end
	if WD.IsExempt(ply) then return end   -- single chokepoint: elevated roles never accrue suspicion
	local sid = ply:SteamID()
	WD.Suspicion[sid] = WD.Suspicion[sid] or {}
	local s = WD.Suspicion[sid]
	s[module] = (s[module] or 0) + amount

	local m = WD.Modules[module]
	local threshold = (m and m.threshold) or 100

	if s[module] >= threshold then
		s[module] = 0
		WD.WriteDossier(ply, module, evidence, action)
		return
	end

	-- EARLY CLIMB WARNING: one quiet chat line to staff the first time a score
	-- crosses warnPct% of the threshold, so they can start watching BEFORE the
	-- dossier fires. Chat line only - the toast/sound stays reserved for real
	-- dossiers. Re-arms when the score decays back under the line (decay timer);
	-- a 60s floor stops spam from a score hovering right at the line.
	if WD.Config.warnStaff then
		local warnAt = threshold * (WD.Config.warnPct or 50) / 100
		if s[module] >= warnAt then
			local key = sid .. "|" .. module
			local w = WD._warn[key]
			local now = CurTime()
			if not (w and w.active) and not (w and (w.cool or 0) > now) then
				WD._warn[key] = { active = true, cool = now + 60 }
				WD.Notify(string.format("climbing: %s  [%s] %d/%d - keep an eye on them",
					ply:Nick(), module, math.floor(s[module]), threshold))
				if WD.Config.logConsole then
					print(string.format("[Watchdog] climb warning: %s (%s) %s %d/%d",
						ply:Nick(), sid, module, math.floor(s[module]), threshold))
				end
			end
		end
	end
end

-- prune the dossier dir down to Config.dossierMax (oldest first)
local function pruneDossiers()
	local files = file.Find(WD.Config.dossierDir .. "/*.txt", "DATA")
	if not files then return end
	local over = #files - WD.Config.dossierMax
	if over <= 0 then return end
	-- filenames end in _<os.time>.txt, so lexical sort ~= chronological enough;
	-- sort by the trailing timestamp to be safe.
	table.sort(files, function(a, b)
		return (tonumber(string.match(a, "_(%d+)%.txt$")) or 0) < (tonumber(string.match(b, "_(%d+)%.txt$")) or 0)
	end)
	for i = 1, over do file.Delete(WD.Config.dossierDir .. "/" .. files[i]) end
end

function WD.WriteDossier(ply, module, evidence, action)
	action = action or "logged"   -- "logged" | "kicked" | "banned"
	-- anti-flood: one dossier per player+module per dossierCool window
	local key = ply:SteamID() .. "|" .. module
	local cd = WD._dcool[key]
	local now = CurTime()
	if cd and cd["until"] > now then
		cd.held = (cd.held or 0) + 1   -- count suppressed repeats; surfaced on the next write
		return
	end
	local held = cd and cd.held or 0
	WD._dcool[key] = { ["until"] = now + WD.Config.dossierCool, held = 0 }

	local sid64 = ply:SteamID64() or "unknown"
	local fname = string.format("%s/%s_%s_%d.txt", WD.Config.dossierDir, module, sid64, os.time())
	local out = {
		"===== WATCHDOG DOSSIER =====",
		"time:   " .. os.date("%Y-%m-%d %H:%M:%S"),
		"player: " .. ply:Nick() .. " (" .. ply:SteamID() .. ")",
		"module: " .. module,
		"action: " .. string.upper(action) .. (action == "logged" and " (watch mode - no punishment)" or ""),
		"map:    " .. game.GetMap(),
		"context:" .. util.TableToJSON(WD.Context(ply)),
		held > 0 and ("note:   " .. held .. " similar hit(s) were suppressed since the last dossier") or "",
		"",
		"--- trigger evidence ---",
		istable(evidence) and util.TableToJSON(evidence, true) or tostring(evidence),
		"",
		"--- recent evidence ring ---",
		util.TableToJSON(WD.DumpEvidence(ply), true),
	}
	file.Write(fname, table.concat(out, "\n"))
	if WD.Config.logConsole then
		print("[Watchdog] DOSSIER: " .. ply:Nick() .. " / " .. module .. " -> data/" .. fname)
	end
	pruneDossiers()
	hook.Run("WD_Dossier", ply, module, evidence, action)  -- staff UI + cmdlog listen
	WD.Notify("dossier filed: " .. ply:Nick() .. "  [" .. module .. "]"
		.. (action ~= "logged" and ("  - " .. string.upper(action)) or ""))
end

-- quiet ping to online superadmins
function WD.Notify(msg)
	if not WD.Config.pingStaff then return end
	for _, a in player.Iterator() do
		if WD.IsStaff(a) then
			a:ChatPrint("[Watchdog] " .. msg)
		end
	end
end

-- ---------------- damage / spawn / teleport trackers ----------------
hook.Add("EntityTakeDamage", "WD_Core_Damage", function(ent, dmg)
	if IsValid(ent) and ent:IsPlayer() then
		WD._lastDamage[ent:SteamID()] = CurTime()
	end
end)

hook.Add("PlayerSpawn", "WD_Core_Spawn", function(ply)
	if IsValid(ply) then WD._lastSpawn[ply:SteamID()] = CurTime() end
end)
-- gameevent fires independently of the gamemode hook chain, so a ZCity
-- PlayerSpawn hook returning early can't rob us of the spawn stamp.
gameevent.Listen("player_spawn")
hook.Add("player_spawn", "WD_Core_SpawnEvt", function(d)
	local ply = Player(d.userid)
	if IsValid(ply) then WD._lastSpawn[ply:SteamID()] = CurTime() end
end)

-- track when a player last fired bullets (owner- or weapon-sourced)
hook.Add("EntityFireBullets", "WD_Core_Fire", function(ent)
	local ply = ent
	if not (IsValid(ply) and ply:IsPlayer()) then
		-- IsValid(ent) FIRST: ZCity's lua-bullet callback (sh_bullet.lua) fires
		-- this hook on a delayed timer, by which point the weapon/bullet ent can
		-- be NULL - and a NULL entity still exposes :GetOwner, so calling it
		-- errored ("Tried to use a NULL entity!") and aborted the bullet callback.
		ply = (IsValid(ent) and ent.GetOwner and ent:GetOwner()) or nil
	end
	if IsValid(ply) and ply:IsPlayer() then WD._lastFire[ply:SteamID()] = CurTime() end
end)

-- ---------------- the ONE per-tick sampler ----------------
-- Builds WD.track[sid] and feeds every enabled module's Sample().
hook.Add("StartCommand", "WD_Core_Sample", function(ply, cmd)
	if not WD.Config.enabled then return end
	if not IsValid(ply) or not ply:Alive() then return end
	if cmd:IsForced() then return end   -- engine backup command (choke) - ignore
	if WD.IsExempt(ply) then return end -- skip elevated roles entirely (no sampling, no modules)

	local sid = ply:SteamID()
	local now = CurTime()
	local ang = cmd:GetViewAngles()
	local t = WD.track[sid]

	if not t then
		WD.track[sid] = {
			ang = ang, prev = ang, dPitch = 0, dYaw = 0, jump = 0,
			pos = ply:EyePos(), vel = ply:GetVelocity(),
			speed2d = ply:GetVelocity():Length2D(),
			t = now, dt = 0, onground = ply:OnGround(),
			buttons = cmd:GetButtons(), latStable = false,
		}
		WD._ping[sid] = ply:Ping()
		return
	end

	local prev = t.ang
	local pos = ply:EyePos()
	-- suspected teleport: eye moved far more than a tick could allow
	local posDelta = pos:Distance(t.pos)
	local dt = now - t.t
	if dt <= 0 then dt = engine.TickInterval() end
	local maxStep = (ply:GetMaxSpeed() + 400) * dt + 64  -- generous
	if posDelta > maxStep and posDelta > 200 then
		WD._lastTP[sid] = now
	end

	t.prev2    = t.prev   -- angle two ticks back (pSilent out-and-back detection)
	t.jumpPrev = t.jump   -- last tick's jump size
	t.prev     = prev
	t.ang      = ang
	t.dPitch   = math.AngleDifference(ang.p, prev.p)
	t.dYaw     = math.AngleDifference(ang.y, prev.y)
	t.jump     = math.sqrt(t.dPitch * t.dPitch + t.dYaw * t.dYaw)
	t.pos      = pos
	t.vel      = ply:GetVelocity()
	t.speed2d  = t.vel:Length2D()
	t.dt       = dt
	t.t        = now
	t.onground = ply:OnGround()
	t.buttons  = cmd:GetButtons()
	t.latStable = latencyStable(ply, sid)
	WD._ping[sid] = ply:Ping()

	-- post-excuse grace: when a transient physical state (KO / fake-ragdoll /
	-- stun / vehicle) CLEARS, the view + velocity snap around for a few ticks
	-- during get-up. Grant a short suppression on that falling edge. This
	-- covers un-KO, get-up, vehicle-exit and teleport-end generically.
	local o = org(ply)
	local exNow = (o and o.otrub) or IsValid(ply.FakeRagdoll) or stunned(o) or ply:InVehicle()
	if t.wasEx and not exNow then
		WD.Suppress(ply, WD.Config.postExcuse, "post-excuse")
	end
	t.wasEx = exNow

	-- lightweight rolling evidence (view + speed), for dossier context
	-- (same values as WD.PushEvidence(ply, "tick", {...}); the fast path just
	-- recycles this slot's tables instead of allocating two per usercmd)
	pushTickEvidence(sid,
		math.Round(ang.p, 1), math.Round(ang.y, 1), math.Round(ang.r, 1),
		math.Round(t.speed2d), math.Round(t.dYaw, 1))

	for name, m in pairs(WD.Modules) do
		if m.Sample and WD.ModuleEnabled(name) then
			-- isolate each module: one module erroring must NOT stop the others
			-- (this loop also runs WriteDossier -> the cmdlog/UI consumers).
			local ok, err = pcall(m.Sample, ply, cmd, t)
			if not ok and WD.Config.logConsole then
				print("[Watchdog] module '" .. name .. "' Sample error: " .. tostring(err))
			end
		end
	end
end)

-- ---------------- global decay (modules can rely on this) ----------------
-- Each module sets m.decay (per second). Core decays all scores once/sec.
timer.Create("WD_Core_Decay", 1, 0, function()
	for sid, mods in pairs(WD.Suspicion) do
		for mod, score in pairs(mods) do
			if score > 0 then
				local m = WD.Modules[mod]
				local d = (m and m.decay) or 0.5
				mods[mod] = math.max(0, score - d)
			end
			-- re-arm the early climb warning once the score has fallen back
			-- under the warn line (also covers the reset-to-0 after a dossier)
			local w = WD._warn[sid .. "|" .. mod]
			if w and w.active then
				local m2 = WD.Modules[mod]
				local warnAt = ((m2 and m2.threshold) or 100) * (WD.Config.warnPct or 50) / 100
				if mods[mod] < warnAt then w.active = false end
			end
		end
	end
end)

-- ---------------- cleanup ----------------
hook.Add("PlayerDisconnected", "WD_Core_Cleanup", function(ply)
	if not IsValid(ply) then return end
	local sid = ply:SteamID()
	WD.track[sid]       = nil
	WD.evidence[sid]    = nil
	WD._lastDamage[sid] = nil
	WD._lastSpawn[sid]  = nil
	WD._lastTP[sid]     = nil
	WD._lastFire[sid]   = nil
	WD._suppress[sid]   = nil
	WD._ping[sid]       = nil
	for k in pairs(WD._dcool) do
		if string.sub(k, 1, #sid + 1) == sid .. "|" then WD._dcool[k] = nil end
	end
	for k in pairs(WD._warn) do
		if string.sub(k, 1, #sid + 1) == sid .. "|" then WD._warn[k] = nil end
	end
	-- keep WD.Suspicion so a rejoin doesn't wipe accrued score within the map
end)

-- ---------------- commands ----------------
concommand.Add("wd_status", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local n = 0 for _ in pairs(WD.Modules) do n = n + 1 end
	local mode = WD.Config.watchMode and "WATCH (no enforcement)" or "ENFORCE"
	print(string.format("[Watchdog] v%s | modules: %d | mode: %s | enabled: %s",
		WD.VERSION, n, mode, tostring(WD.Config.enabled)))
	for name, m in pairs(WD.Modules) do
		print(string.format("  - %-12s enabled=%s threshold=%s decay=%s  %s",
			name, tostring(WD.ModuleEnabled(name)), tostring(m.threshold), tostring(m.decay or 0.5), m.desc or ""))
	end
	print("[Watchdog] live suspicion:")
	local any = false
	for sid, mods in pairs(WD.Suspicion) do
		for mod, score in pairs(mods) do
			if score > 0 then
				any = true
				print(string.format("   %s | %s: %.1f", sid, mod, score))
			end
		end
	end
	if not any then print("   (clean)") end

	print("[Watchdog] players:")
	for _, p in ipairs(player.GetAll()) do
		print(string.format("   %-22s %-11s %s", p:Nick(), p:GetUserGroup(),
			WD.IsExempt(p) and "EXEMPT (ignored)" or "watched"))
	end
end)

-- quick check: does Watchdog watch or ignore a given player?  wd_check <partial name>
concommand.Add("wd_check", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local q = string.lower(args[1] or "")
	for _, p in ipairs(player.GetAll()) do
		if q == "" or string.find(string.lower(p:Nick()), q, 1, true) then
			print(string.format("[Watchdog] %s (%s) group=%s -> %s",
				p:Nick(), p:SteamID(), p:GetUserGroup(),
				WD.IsExempt(p) and "EXEMPT" or "WATCHED"))
		end
	end
end)

concommand.Add("wd_dossiers", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local files = file.Find(WD.Config.dossierDir .. "/*.txt", "DATA")
	print("[Watchdog] " .. #files .. " dossiers in data/" .. WD.Config.dossierDir .. "/")
	for i = math.max(1, #files - 20), #files do print("  " .. files[i]) end
end)

concommand.Add("wd_config", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local key, val = args[1], args[2]
	if not key then
		print("[Watchdog] config: usage  wd_config <key> <value>")
		print("  keys: enabled, watchMode, pingStaff, logConsole  (true/false)")
		print("  module toggle:  wd_config module <name> <true/false>")
		for k, v in pairs(WD.Config) do
			if type(v) ~= "table" then print(string.format("   %-12s = %s", k, tostring(v))) end
		end
		return
	end
	if key == "module" then
		local mn, mv = args[2], args[3]
		if mn and mv then
			WD.Config.modules[mn] = (mv == "true" or mv == "1")
			print(string.format("[Watchdog] module %s -> %s", mn, tostring(WD.Config.modules[mn])))
			WD.SaveConfig()
		end
		return
	end
	if WD.Config[key] ~= nil and type(WD.Config[key]) ~= "table" then
		if val == "true" or val == "1" then WD.Config[key] = true
		elseif val == "false" or val == "0" then WD.Config[key] = false
		else WD.Config[key] = tonumber(val) or val end
		print(string.format("[Watchdog] config %s -> %s", key, tostring(WD.Config[key])))
		WD.SaveConfig()
	end
end)

print("[Watchdog] core v" .. WD.VERSION .. " loaded - WATCH MODE (standalone)")
