-- ============================================================
--  ZC NETOPT - stop broadcasting netvars that did not change
-- ------------------------------------------------------------
--  MEASURED (zc_perf auto-capture, gm_prison, 31 players):
--    zbNetVarSet = 16.8 MB of 21 MB total wire traffic - EIGHTY
--    PERCENT of everything the server sends - 4202 sends x ~32
--    recipients at 69 sends/sec.
--
--  WHY IT IS THAT BIG (sh_networking.lua:210 entityMeta:SetNetVar):
--      if (zb.net.list[self][key] != value) then
--          zb.net.list[self][key] = value
--      end
--      self:SendNetVar(key, receiver)   <-- OUTSIDE the if
--  The change test only guards the TABLE WRITE. The broadcast fires
--  unconditionally, so setting a var to the value it already holds
--  still ships a message to all 32 players. The gamemode's own
--  dedup (hg.IsChanged) sits commented out one line above.
--
--  THE FIX: skip the send when the value is UNCHANGED. Verified safe
--  before writing a line:
--   * the client stores every netvar by ENTITY INDEX on arrival and
--     keeps it even when the entity does not exist yet (:18, sets
--     .waiting) - so a redundant send heals nothing, the client
--     already holds the value
--   * SetNetVar sends RELIABLE (no unreliable flag) - nothing is
--     silently dropped in transit
--   * fresh/reconnecting clients are served by playerMeta:SyncVars(),
--     which walks the whole table - untouched by this
--
--  STRICT SAFETY RULES:
--   * ONLY strings/numbers/booleans are deduped. NEVER tables. The
--     codebase is full of read-modify-write on table netvars
--     (local inv = ply:GetNetVar("Inventory") ... SetNetVar(inv)) -
--     the stored value IS the same table reference, so a reference
--     compare would wrongly skip a real change. Colors are tables
--     too, so they always send.
--   * ONLY broadcasts (receiver == nil) are deduped. A targeted send
--     to one player is usually a deliberate resync - always honoured.
--
--  FULL SAFETY AUDIT (every OnNetVarSet consumer in the gamemode was
--  read before shipping this):
--   * client 'waiting' flag - when a netvar arrives for an entity that
--     does not exist clientside yet, the value is STORED and the hook is
--     deferred; it is replayed by the NetworkEntityCreated hook
--     (cl_utility.lua:222) which walks every stored key when the entity
--     spawns. It does NOT wait for a later send, so dedup cannot strand it.
--   * joiners - player_activate -> ply:SyncVars() (sh_utility.lua:705,
--     plus sv_roundsystem.lua:198) walks the whole table and sends every
--     key directly. SyncVars uses net.Start itself, not SetNetVar, so
--     this wrapper never touches the join path.
--   * consumers - Tourniquets / bandaged_limbs / wounds / Inventory /
--     Armor / attachments / modeValues are all TABLE netvars = never
--     deduped. The primitive ones (Karma, extinguishermode) are pure
--     state assignments where re-assigning an identical value is a no-op.
--     No consumer uses an unchanged primitive as an event trigger.
--
--  zc_netopt 0 = TRUE MEASURE-ONLY MODE: redundancy is still counted, so
--  zc_netopt_stats shows exactly what WOULD be saved with zero behaviour
--  change. Flip to 1 once the numbers look right.
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCNETOPT = ZCNETOPT or {}
ZCNETOPT.sent = ZCNETOPT.sent or {}
ZCNETOPT.skip = ZCNETOPT.skip or {}
ZCNETOPT.since = ZCNETOPT.since or CurTime()

local cv_on = CreateConVar("zc_netopt", "1", FCVAR_ARCHIVE, "Skip netvar broadcasts whose value did not change (0 = stock behaviour)", 0, 1)

-- TABLE netvars (wounds, arterialwounds, Inventory, Armor = ~3/4 of all
-- broadcasts, measured 2026-09-21) cannot be compared by reference: the
-- gamemode mutates the stored table in place. So compare CONTENT: keep a
-- fingerprint string of what was last broadcast per entity+key.
-- 0 = measure only (counts what would be skipped), 1 = skip.
-- PROVISIONAL(2026-09-21, ships measuring until the owner reads zc_netopt_stats with a full server, ratify-by: 2026-10-05)
local cv_tables = CreateConVar("zc_netopt_tables", "0", FCVAR_ARCHIVE, "Skip TABLE netvar broadcasts whose content did not change (0 = measure only)", 0, 1)
-- The client copies wounds onto a player's ragdoll only when the netvar
-- ARRIVES (cl_main.lua wounds_netvar), so a skipped resend must never be
-- the only one: content older than this many seconds is sent again, and
-- a new ragdoll forgets the player's fingerprints outright (hook below).
local cv_refresh = CreateConVar("zc_netopt_tables_refresh", "10", FCVAR_ARCHIVE, "Resend unchanged TABLE netvars at least this often (seconds)", 1, 120)
ZCNETOPT.fpt = ZCNETOPT.fpt or setmetatable({}, { __mode = "k" })
hook.Add("Fake", "zc_netopt_refresh", function(ply)
	if ply then ZCNETOPT.fp[ply] = nil end
end)
ZCNETOPT.tdup = ZCNETOPT.tdup or {}
ZCNETOPT.tcost = ZCNETOPT.tcost or 0
ZCNETOPT.fp = ZCNETOPT.fp or setmetatable({}, { __mode = "k" })

-- nil = cannot fingerprint (too big, too deep, cyclic) -> always send.
-- pairs() order is not sorted: two equal tables built differently may
-- fingerprint differently, which only ever costs a send, never a skip.
local FP_MAX = 600
local function fingerprint(value)
	local out, n, seen = {}, 0, {}
	local function walk(v, depth)
		if n > FP_MAX then return false end
		local t = type(v)
		if t == "table" then
			if depth > 6 or seen[v] then return false end
			seen[v] = true
			n = n + 1 out[n] = "{"
			for k, x in pairs(v) do
				n = n + 1 out[n] = type(k) .. ":" .. tostring(k) .. "="
				if walk(x, depth + 1) == false then return false end
			end
			seen[v] = nil
			n = n + 1 out[n] = "}"
		elseif t == "number" then
			n = n + 1 out[n] = string.format("%.17g;", v)
		elseif t == "function" then
			return false
		else
			n = n + 1 out[n] = t .. ":" .. tostring(v) .. ";"
		end
	end
	if walk(value, 0) == false then return nil end
	return table.concat(out, "", 1, n)
end
ZCNETOPT.fingerprint = fingerprint

local entityMeta = FindMetaTable("Entity")

-- capture the stock function once; a hotload must not wrap our wrapper
if not ZCNETOPT.orig then
	ZCNETOPT.orig = entityMeta.SetNetVar
end

local orig = ZCNETOPT.orig

function entityMeta:SetNetVar(key, value, receiver)
	-- a nil key already errors inside the stock function; hand it straight
	-- through so we never turn its error into a different one from our
	-- own stats table
	if key == nil then return orig(self, key, value, receiver) end

	-- redundancy is ALWAYS computed (so zc_netopt 0 is a true measure-only
	-- mode: the stats show what WOULD be skipped, with zero behaviour change)
	local redundant = false
	if receiver == nil and (isstring(value) or isnumber(value) or isbool(value)) then
		local tbl = zb and zb.net and zb.net.list and zb.net.list[self]
		local cur = tbl and tbl[key]
		-- note: `cur == false` is handled correctly - false ~= nil is true
		redundant = (cur ~= nil and cur == value)
	elseif receiver == nil and istable(value) then
		local t0 = SysTime()
		local tbl = zb and zb.net and zb.net.list and zb.net.list[self]
		local fps = ZCNETOPT.fp[self]
		if not fps then fps = {} ZCNETOPT.fp[self] = fps end
		local fp = fingerprint(value)
		-- the stored value must still exist: a cleared netvar list means
		-- clients may have dropped it, so the next set has to go out
		local times = ZCNETOPT.fpt[self]
		if not times then times = {} ZCNETOPT.fpt[self] = times end
		local now = CurTime()
		local same = fp ~= nil and fps[key] == fp and tbl ~= nil and tbl[key] ~= nil
			and times[key] ~= nil and now - times[key] < cv_refresh:GetFloat() and now >= times[key]
		fps[key] = fp
		if not same then times[key] = now end
		ZCNETOPT.tcost = ZCNETOPT.tcost + (SysTime() - t0)
		if same then
			ZCNETOPT.tdup[key] = (ZCNETOPT.tdup[key] or 0) + 1
			if cv_on:GetBool() and cv_tables:GetBool() then
				return -- clients already hold this exact content
			end
		end
	end

	if redundant then
		ZCNETOPT.skip[key] = (ZCNETOPT.skip[key] or 0) + 1
		if cv_on:GetBool() then
			return -- client already holds this exact value
		end
	else
		ZCNETOPT.sent[key] = (ZCNETOPT.sent[key] or 0) + 1
	end

	return orig(self, key, value, receiver)
end

concommand.Add("zc_netopt_stats", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local function say(s)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
	end

	local rows, sTot, kTot = {}, 0, 0
	for k, n in pairs(ZCNETOPT.sent) do
		rows[k] = { sent = n, skip = ZCNETOPT.skip[k] or 0 }
	end
	for k, n in pairs(ZCNETOPT.skip) do
		rows[k] = rows[k] or { sent = 0, skip = n }
	end
	local list = {}
	for k, r in pairs(rows) do
		list[#list + 1] = { k = k, r = r }
		sTot = sTot + r.sent
		kTot = kTot + r.skip
	end
	table.sort(list, function(a, b) return (a.r.sent + a.r.skip) > (b.r.sent + b.r.skip) end)

	local span = math.max(CurTime() - ZCNETOPT.since, 0.001)
	local total = sTot + kTot
	say("=== zc_netopt (" .. (cv_on:GetBool() and "ACTIVE" or "measuring only") .. ", " .. math.Round(span) .. "s) ===")
	say("netvar sets: " .. total .. " | sent " .. sTot .. " | SKIPPED " .. kTot
		.. "  (" .. string.format("%.1f", kTot / math.max(total, 1) * 100) .. "% of broadcasts eliminated)")
	say("rate: " .. string.format("%.1f", sTot / span) .. "/s sent vs " .. string.format("%.1f", total / span) .. "/s stock")
	say("--- per key (sent / skipped) ---")
	for i = 1, math.min(20, #list) do
		local e = list[i]
		say(string.format("  %-28s sent %6d   skipped %6d", e.k, e.r.sent, e.r.skip))
	end
	local dupTot = 0
	for _, n in pairs(ZCNETOPT.tdup) do dupTot = dupTot + n end
	say("--- TABLE netvars with unchanged content (" .. (cv_tables:GetBool() and cv_on:GetBool() and "SKIPPED" or "measure only - counted inside 'sent' above")
		.. ", zc_netopt_tables) : " .. dupTot .. " | fingerprint cost " .. string.format("%.1f", ZCNETOPT.tcost * 1000) .. " ms total ---")
	for k, n in pairs(ZCNETOPT.tdup) do
		say(string.format("  %-28s unchanged %6d of %6d", k, n, (ZCNETOPT.sent[k] or 0)))
	end
end)

concommand.Add("zc_netopt_reset", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	ZCNETOPT.sent, ZCNETOPT.skip, ZCNETOPT.since = {}, {}, CurTime()
	ZCNETOPT.tdup, ZCNETOPT.tcost = {}, 0
	print("[NetOpt] counters reset")
end)

print("[NetOpt] loaded - unchanged netvar broadcasts " .. (cv_on:GetBool() and "SKIPPED" or "passing through (zc_netopt 0)")
	.. " | zc_netopt_stats for the breakdown")
