-- Gore V2's torso reset treats FakeUp's internal Spawn as a real respawn, and
-- clears only half of the crawler state on a real one.
--
-- z_podgruz.lua:830 registers PlayerSpawn "ZCity Gore V2_ResetTorso" with no
-- OverrideSpawn guard. hg.FakeUp (fake/sv_tier_0.lua:805) sets OverrideSpawn,
-- calls ply:Spawn(), then clears it; zcity's own convention is to early-return
-- on OverrideSpawn, and it registers blocker hooks under "!!!!!!" and "z" that
-- return false. Those blockers only win if hook iteration reaches them first,
-- which Lua does not guarantee, so the gore reset can fire mid-life and strip a
-- living crawler's state: ZCityTorsoSevered goes false, so "Should Fake Up"
-- stops refusing, IN_DUCK comes back, and __zcGoreLowerTorso is forgotten so
-- MakeCrawler can no longer remove the lower half.
--
-- The reset also never clears organism.torsoamputated or the flag Gore V2 set
-- on the RAGDOLL (z_podgruz.lua:542). Either one surviving makes a player read
-- as already amputated forever - MakeCrawler short-circuits with "already" and
-- hg.ZCityGore_AmputateTorso refuses at z_podgruz.lua:661.
--
-- This replaces that one listener in place (same event + same name). It keeps
-- the original's behaviour on a real respawn, skips FakeUp's internal Spawn,
-- and clears the two fields the original left behind. torsoStates is a local of
-- the addon and unreachable from here, but the addon's own Think loop prunes it
-- whenever the flag is false, so clearing the flag still retires the entry.
--
-- zc_gore_torsoreset 0 restores Gore V2's own listener (kept below).

if not SERVER then return end

local VERSION = "20260922.1"
if ZCGoreTorsoReset and ZCGoreTorsoReset.Version == VERSION then return end

ZCGoreTorsoReset = ZCGoreTorsoReset or {}
local M = ZCGoreTorsoReset
M.Version = VERSION
M.stats = M.stats or {real = 0, skippedFakeUp = 0, clearedOrganism = 0, clearedRagdoll = 0, installs = 0}

local ADDON_TAG = "ZCity Gore V2"
local HOOK = ADDON_TAG .. "_ResetTorso"

local enabled = CreateConVar("zc_gore_torsoreset", "1", FCVAR_ARCHIVE,
    "Keep crawler torso state across FakeUp's internal Spawn, and clear it fully on a real respawn", 0, 1)

M.marks = M.marks or setmetatable({}, {__mode = "k"})

local function current()
    local t = hook.GetTable()["PlayerSpawn"]
    return t and t[HOOK] or nil
end

function M.Reset(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    -- FakeUp's internal Spawn is not a new life. Leave the crawler intact.
    if OverrideSpawn then
        M.stats.skippedFakeUp = M.stats.skippedFakeUp + 1
        if enabled:GetBool() then return end
    else
        M.stats.real = M.stats.real + 1
    end

    ply:SetNWBool("ZCityTorsoSevered", false)
    ply.__zcGoreTorsoPending = nil
    ply.__zcGoreBlastQueued = nil
    ply.__zcGoreLowerTorso = nil
    ply.__zcGoreLastInitialPhrase = nil
    ply.__zcGoreLastPainPhrase = nil
    timer.Remove(ADDON_TAG .. "_PainPhrases_" .. ply:EntIndex())

    if not enabled:GetBool() then return end

    -- Left behind by Gore V2: either survivor makes the player read as already
    -- amputated for the rest of the session.
    local rag = ply.FakeRagdoll

    if IsValid(rag) and rag:GetNWBool("ZCityTorsoSevered", false) then
        rag:SetNWBool("ZCityTorsoSevered", false)
        M.stats.clearedRagdoll = M.stats.clearedRagdoll + 1
    end

    local org = ply.organism

    if type(org) == "table" and org.torsoamputated then
        org.torsoamputated = false
        M.stats.clearedOrganism = M.stats.clearedOrganism + 1
    end
end

M.marks[M.Reset] = true

-- Gore V2 registers this hook at file-load time, inside the top-level
-- `if SERVER then` of its own lua/autorun file (z_podgruz.lua:23, :830) - not
-- from HomigradRun, which it uses only for InstallServerCompatibility (:933).
-- Load order between two autorun files is not guaranteed, so claim the name
-- again after boot; the timer below closes the window either way.
function M.Install()
    local live = current()

    if live == M.Reset then return false end
    if isfunction(live) and not M.marks[live] then M.Stock = live end

    hook.Add("PlayerSpawn", HOOK, M.Reset)
    M.stats.installs = M.stats.installs + 1

    return true
end

local function installSoon()
    timer.Simple(0, M.Install)
end

M.Install()
hook.Add("HomigradRun", "ZCGoreTorsoReset_Install", installSoon)
hook.Add("InitPostEntity", "ZCGoreTorsoReset_Install", installSoon)
timer.Create("ZCGoreTorsoReset_Install", 1, 30, M.Install)

concommand.Add("zc_gore_torsoreset_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local line = string.format(
        "[zc_gore_torsoreset] %s enabled=%s installed=%s stock=%s real=%d skippedFakeUp=%d clearedOrg=%d clearedRag=%d installs=%d",
        VERSION, tostring(enabled:GetBool()), tostring(current() == M.Reset), tostring(M.Stock ~= nil),
        M.stats.real, M.stats.skippedFakeUp, M.stats.clearedOrganism, M.stats.clearedRagdoll, M.stats.installs)

    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)

concommand.Add("zc_gore_torsoreset_restore", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    if not isfunction(M.Stock) then print("[zc_gore_torsoreset] no stock listener captured") return end

    timer.Remove("ZCGoreTorsoReset_Install")
    hook.Remove("HomigradRun", "ZCGoreTorsoReset_Install")
    hook.Remove("InitPostEntity", "ZCGoreTorsoReset_Install")
    hook.Add("PlayerSpawn", HOOK, M.Stock)
    print("[zc_gore_torsoreset] restored Gore V2's own listener")
end)

print("[zc_gore_torsoreset] Loaded " .. VERSION)
