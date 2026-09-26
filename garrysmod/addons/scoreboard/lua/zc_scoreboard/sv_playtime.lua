if not SERVER then return end
local function getPlaytimeKey(ply)
    if not IsValid(ply) or ply:IsBot() then return nil end

    local sid64 = ply:SteamID64()
    if sid64 and sid64 ~= "" then
        return sid64
    end

    local sid = ply:SteamID()
    if sid and sid ~= "" then
        return sid
    end

    return nil
end

local function getStoredPlaytime(ply)
    local key = getPlaytimeKey(ply)
    if not key then return 0 end

    return math.max(0, math.floor(tonumber(PATSB.PlaytimeData[key]) or 0))
end

local function setStoredPlaytime(ply, seconds)
    local key = getPlaytimeKey(ply)
    if not key then return end

    PATSB.PlaytimeData[key] = math.max(0, math.floor(seconds or 0))
end

local function assignJoinTime(ply)
    if not IsValid(ply) then return end
    if ply:GetNWInt("PATSB_SessionUnix", 0) <= 0 then ply:SetNWInt("PATSB_SessionUnix", ply:GetNWInt("PATSB_JoinUnix", os.time())) end
    if ply:GetNWInt("PATSB_JoinUnix", 0) > 0 then return end
    ply:SetNWInt("PATSB_JoinUnix", os.time())
end

local function assignPlaytimeBase(ply)
    if not IsValid(ply) then return end
    ply:SetNWInt("PATSB_TotalPlayBase", getStoredPlaytime(ply))
end

local function getCurrentSessionSeconds(ply)
    if not IsValid(ply) then return 0 end

    local joined = ply:GetNWInt("PATSB_JoinUnix", 0)
    if joined <= 0 then return 0 end

    return math.max(0, os.time() - joined)
end

local function persistPlaytimeFor(ply, refreshSessionBase)
    if not IsValid(ply) then return end

    local total = getStoredPlaytime(ply) + getCurrentSessionSeconds(ply)
    setStoredPlaytime(ply, total)

    -- Advance the accounting checkpoint on every flush, including shutdown/leave.
    ply:SetNWInt("PATSB_JoinUnix", os.time())
    ply:SetNWInt("PATSB_TotalPlayBase", total)
end

hook.Add("PlayerInitialSpawn", "PATSB_SendSettingsOnJoin", function(ply)
    assignJoinTime(ply)
    assignPlaytimeBase(ply)
    timer.Simple(2, function()
        if IsValid(ply) then
            PATSB:BroadcastSettings(ply)
        end
    end)
end)

timer.Simple(0, function()
    for _, ply in ipairs(player.GetHumans()) do
        assignJoinTime(ply)
        assignPlaytimeBase(ply)
    end
end)

hook.Add("PlayerDisconnected", "PATSB_SavePlaytimeOnLeave", function(ply)
    persistPlaytimeFor(ply, false)
    PATSB:SavePlaytimeData()
end)

timer.Create("PATSB_PlaytimeFlush", 120, 0, function()
    for _, ply in ipairs(player.GetHumans()) do
        persistPlaytimeFor(ply, true)
    end
    PATSB:SavePlaytimeData()
end)

hook.Add("ShutDown", "PATSB_SavePlaytimeOnShutdown", function()
    for _, ply in ipairs(player.GetHumans()) do
        persistPlaytimeFor(ply, false)
    end
    PATSB:SavePlaytimeData()
end)

