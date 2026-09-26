-- Explicitly mount the two local GMAs on this dedicated server.
if not SERVER then return end
local version = "20260915.7"
local addons = {
    { "zcity_drones_compat", "ZCityDronesCompat", "09089e4866987d8443eccc8baa7841995186c355919aa5af5846b0a063d28715", "20260915.6" },
    { "zcity_pillpack_compat", "ZCityPillCompat", "0bb5d4b722264c1ee0540b51803f94e398b5bff98b192a5e0cebdc974b41a92a", "20260915.7" }
}
-- 2026-09-23: one entry per function so a failure in the first GMA no longer skips the second
-- (the old loop-level `return` left the pill pack unloaded whenever the drones pack mismatched).
local function loadEntry(entry)
    game.MountGMA("addons/" .. entry[1] .. ".gma")
    local path = "autorun/" .. entry[1] .. ".lua"
    local source = file.Read(path, "LUA")
    if not source or util.SHA256(source) ~= entry[3] then
        ErrorNoHalt("[ZCityCompatLoader] Missing/mismatched source: " .. path .. "\n")
        return false
    end
    AddCSLuaFile(path)
    local loaded = _G[entry[2]]
    if not loaded or loaded.Version ~= entry[4] then
        local run = CompileString(source, path, false)
        if not isfunction(run) then ErrorNoHalt(tostring(run) .. "\n") return false end
        local ok, err = xpcall(run, debug.traceback)
        if not ok then ErrorNoHalt("[ZCityCompatLoader] " .. path .. " failed: " .. tostring(err) .. "\n") return false end
    end
    if not _G[entry[2]] or _G[entry[2]].Version ~= entry[4] then
        ErrorNoHalt("[ZCityCompatLoader] Runtime version mismatch: " .. path .. "\n") return false
    end
    return true
end
local failed = 0
for _, entry in ipairs(addons) do
    if not loadEntry(entry) then failed = failed + 1 end
end
print("[ZCityCompatLoader] " .. version .. ": " .. (#addons - failed) .. "/" .. #addons .. " compat addons loaded")
