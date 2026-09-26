-- US1 core entry point. Everything US1-owned that is new or migrated boots from here.
-- Autorun is alphabetical across all addons: "us1_" runs after sh_/sv_ files and before zc_/zz_ files,
-- so US1.OnReady / US1.Wrap exist before any zc_* entry point that wants them.
-- See docs/ARCHITECTURE.md for the load-order rules.
AddCSLuaFile()

US1 = US1 or {}
US1.Version = "0.1.0"

local function load(path, realm)
    if realm ~= "cl" and SERVER then AddCSLuaFile(path) end
    if realm == "sv" and CLIENT then return end
    if realm == "cl" and SERVER then return end
    include(path)
end

-- Core is loaded unguarded on purpose: if core fails, nothing that depends on it should run.
if SERVER then AddCSLuaFile("us1/core/sh_core.lua") end
include("us1/core/sh_core.lua")
load("us1/core/sv_net.lua", "sv")

US1.LoadModules("us1/modules")

-- Which release the server is running: tools/server/us1_update.sh writes data/us1_version.txt (RELEASE.json) on each
-- install. Absent on a hand-deployed server; then nothing is printed.
if SERVER then
    local raw = file.Read("us1_version.txt", "DATA")
    local info = raw and util.JSONToTable(raw)
    if istable(info) and isstring(info.main) then
        US1.Release = info
        MsgN("[US1] running release " .. string.sub(info.main, 1, 7) .. (isstring(info.built) and (" built " .. info.built) or ""))
    end
end
