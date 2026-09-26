-- ============================================================
--  Watchdog module: CSLUA  (foreign / injected clientside Lua)
-- ------------------------------------------------------------
--  Detects a client running Lua that did NOT come from your server.
--  Legit clientside code is loaded from files the server sent via
--  AddCSLuaFile; a cheat runs code injected in memory or pulled from
--  files the server never sent. We can see this through the native
--  GM:OnClientLuaError relay (no binary module, no client file):
--
--   Tier 1 (high) - the error comes from code EXECUTED in memory, not
--     loaded from a file: RunString / CompileString / lua_run / a
--     runtime-compiled chunk. With sv_allowcslua 0 a normal client
--     never does this, so it's injected execution.
--   Tier 2 (medium, conservative) - an UNATTRIBUTED error whose source
--     file the server never AddCSLuaFile'd and isn't a stock engine /
--     gamemode path: clientside Lua from a file your server didn't send.
--     Runs only once the sent-file whitelist is populated, and skips
--     stock paths, to stay false-positive-safe.
--
--  Known-cheat-NAME errors (kefir/zxc/...) are owned by the `luaerror`
--  module; this one defers to it to avoid double-filing.
--  WATCH MODE: dossiers only. Staff exempt.
-- ============================================================
if not SERVER then return end
if not WD then include("autorun/server/sv_watchdog_core.lua") end

local C = WD.Config
if C.csluaForeign == nil then C.csluaForeign = true end   -- Tier 2 toggle

-- ---- best-effort record of the clientside files the server sends ----
WD.csFiles  = WD.csFiles or {}
WD._csCount = WD._csCount or 0
if not WD._csWrapped then
	WD._csWrapped = true
	local realAdd = AddCSLuaFile
	function AddCSLuaFile(f)
		if isstring(f) then
			local k = string.lower(f)
			if not WD.csFiles[k] then WD.csFiles[k] = true WD._csCount = WD._csCount + 1 end
		end
		return realAdd(f)
	end
end

-- code executed in memory rather than loaded from a server file
local INJECTED_SRC = { "runstring", "compilestring", "lua_run", "rawlua" }
-- stock engine / gamemode / addon source fragments we never flag
local STOCK = {
	"gamemode/", "gamemodes/", "lua/includes/", "lua/derma/", "lua/vgui/",
	"lua/entities/", "lua/weapons/", "lua/effects/", "lua/autorun/",
	"lua/matproxy/", "lua/postprocess/", "addons/", "includes/extensions/",
}

local INJECT_SCORE  = 100   -- one hit => dossier
local FOREIGN_SCORE = 70
local THRESHOLD     = 100

local function lc(s) return string.lower(tostring(s or "")) end
local function srcPath(e) return string.match(e, "@([%w%._%-/\\]+)") end

hook.Add("OnClientLuaError", "WD_CSLua", function(err, ply, stack, name)
	if not WD.Config.enabled or not WD.ModuleEnabled("cslua") then return end
	if not IsValid(ply) or not ply:IsPlayer() then return end
	if WD.IsExempt(ply) then return end

	local e = lc(err)

	-- let the brand module own known-cheat-name errors
	for _, sig in ipairs(C.luaerrSignatures or {}) do
		if sig ~= "" and e:find(lc(sig), 1, true) then return end
	end

	-- Tier 1: injected in-memory execution
	for _, s in ipairs(INJECTED_SRC) do
		if e:find(s, 1, true) then
			WD.AddSuspicion(ply, "cslua", INJECT_SCORE, {
				tier = "injected-exec", via = s,
				error = string.sub(tostring(err), 1, 400),
				addon = tostring(name),
			})
			return
		end
	end

	-- Tier 2: unattributed error from a file the server never sent
	if C.csluaForeign and WD._csCount > 20 then
		local unattributed = (name == nil or name == "" or lc(name) == "error")
		local src = srcPath(e)
		if unattributed and src then
			local stock = false
			for _, frag in ipairs(STOCK) do
				if src:find(frag, 1, true) then stock = true break end
			end
			if not stock and not WD.csFiles[src] then
				WD.AddSuspicion(ply, "cslua", FOREIGN_SCORE, {
					tier = "foreign-source", src = src,
					error = string.sub(tostring(err), 1, 400),
					addon = tostring(name),
				})
			end
		end
	end
end)

WD.RegisterModule("cslua", {
	threshold = THRESHOLD,
	decay = 0,
	desc = "foreign / injected clientside Lua",
})
