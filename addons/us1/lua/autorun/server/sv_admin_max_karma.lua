-- AdminMaxKarma v2: personal static values, using the existing three-second timer.
if not SERVER then return end
local PATH = "admin_max_karma/settings.json"
local K = {Version = "2.0.0"}
ZC_ADMIN_KARMA = K
local settings, loadError = {}, nil
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function staff(p) return IsValid(p) and (p:IsAdmin() or p:IsSuperAdmin()) end
local function identity(p)
    if not IsValid(p) or p:IsBot() then return end
    local id = p:SteamID64()
    if type(id) == "string" and #id == 17 and id:match("^%d+$") and id ~= "00000000000000000" then return id end
end
function K.Maximum()
    local n = zb and zb.MaxKarma
    return finite(n) and n >= 1 and math.floor(n) or 120
end
local function decode(raw)
    -- Keep SteamID64 keys as strings: numeric conversion loses account identity.
    local ok, data = pcall(util.JSONToTable, raw, false, true)
    if not ok or type(data) ~= "table" or data.version ~= 1 or type(data.values) ~= "table" then return end
    for id, value in pairs(data.values) do
        if type(id) ~= "string" or #id ~= 17 or not id:match("^%d+$") or id == "00000000000000000"
            or not finite(value) or value < 0 or value ~= math.floor(value) then return end
    end
    return data.values
end
local raw = file.Read(PATH, "DATA")
if raw then
    settings = decode(raw)
    if not settings then settings = {}; loadError = "Saved admin karma settings are invalid. Restore settings.json before changing preferences." end
end
function K.Apply(p)
    if not staff(p) then return end
    local id = identity(p)
    local desired = id and settings[id]
    if desired == nil then desired = 100 end
    desired = math.min(desired, K.Maximum())
    if p.Karma ~= desired then p.Karma = desired; p:SetNetVar("Karma", desired) end
end
function K.Status(p)
    local id = identity(p)
    local chosen = id and settings[id]
    return {available = true, current = finite(p.Karma) and p.Karma or 0, maximum = K.Maximum(),
        target = math.min(chosen == nil and 100 or chosen, K.Maximum()), custom = chosen ~= nil,
        stored = chosen, canSave = staff(p) and id ~= nil and loadError == nil, error = loadError or (not id and "A connected human Steam account is required." or "")}
end
local function write(path, value)
    local ok = pcall(file.Write, path, value)
    return ok and file.Read(path, "DATA") == value
end
function K.SetOwn(p, value)
    if not staff(p) then return false, "Admin access required." end
    local id = identity(p)
    if not id then return false, "A connected human Steam account is required." end
    if loadError then return false, loadError end
    if value ~= nil and (not finite(value) or value < 0 or value > K.Maximum() or value ~= math.floor(value)) then
        return false, "Choose a whole karma value from 0 to " .. K.Maximum() .. "."
    end
    local nextValues = table.Copy(settings)
    nextValues[id] = value -- nil restores this account's default; never accepts a target identity.
    local nextRaw = util.TableToJSON({version = 1, values = nextValues}, true)
    local previous = util.TableToJSON({version = 1, values = settings}, true)
    if not nextRaw or #nextRaw > 524288 or not decode(nextRaw) then return false, "Admin karma settings are too large to save." end
    file.CreateDir("admin_max_karma")
    if not write("admin_max_karma/pending.json", nextRaw) or not write("admin_max_karma/settings-backup.json", previous) then
        return false, "Could not prepare the saved preference. Your current setting is unchanged."
    end
    if not write(PATH, nextRaw) then
        local restored = write(PATH, previous)
        return false, restored and "Save failed; previous preferences restored." or "Save failed; previous preferences are in settings-backup.json."
    end
    settings = nextValues
    K.Apply(p)
    return true, value == nil and "Your static karma is reset to the default of " .. math.min(100, K.Maximum()) .. "."
        or "Your static karma is now " .. value .. ". Saved for this account across restarts."
end
-- Same timer name/cadence as the original addon: there is no competing second enforcer.
timer.Create("AdminMaxKarma", 3, 0, function()
    for _, p in player.Iterator() do K.Apply(p) end
end)
