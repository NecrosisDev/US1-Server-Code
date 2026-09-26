if SERVER then
    AddCSLuaFile()
    util.AddNetworkString("ulx_votemode")
end

ZCITY_ULX_KARMA = ZCITY_ULX_KARMA or {}
ZCITY_ULX_KARMA.Loaded = true
ZCITY_ULX_KARMA.Commands = {
    setkarma = true,
    addkarma = true,
    removekarma = true
}

if not ulx or not ULib then return end

local CATEGORY = "Z-City"

local function SyncGuiltGuard(ply, amount)
    if not IsValid(ply) then return end
    if not istable(ZCITY_GUILT) or not istable(ZCITY_GUILT.KarmaGuard) then return end

    local guard = ZCITY_GUILT.KarmaGuard[ply]
    if not istable(guard) then
        guard = {}
        ZCITY_GUILT.KarmaGuard[ply] = guard
    end

    guard.shadow = amount
    guard.allowedLoss = math.max(0, tonumber(guard.allowedLoss) or 0)
end

local function SetPlayerKarma(ply, amount)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    amount = math.max(0, math.floor(tonumber(amount) or 0))

    ply.Karma = amount
    ply:SetNetVar("Karma", amount)

    if ply.guilt_SetValue then
        ply:guilt_SetValue(amount)
    end

    SyncGuiltGuard(ply, amount)

    return true
end

local function GetPlayerKarma(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return 0 end

    if ply.guilt_GetValue then
        return math.floor(tonumber(ply:guilt_GetValue()) or 0)
    end

    return math.floor(tonumber(ply.Karma) or 0)
end

function ulx.setkarma(calling_ply, target_plys, amount)
    amount = math.floor(tonumber(amount) or 0)

    for _, v in ipairs(target_plys) do
        SetPlayerKarma(v, amount)
    end

    ulx.fancyLogAdmin(calling_ply, "#A set karma for #T to #i", target_plys, math.max(0, amount))
end

local setkarma = ulx.command(CATEGORY, "ulx setkarma", ulx.setkarma, "!setkarma")
setkarma:addParam{ type = ULib.cmds.PlayersArg }
setkarma:addParam{ type = ULib.cmds.NumArg, hint = "amount", min = 0 }
setkarma:defaultAccess(ULib.ACCESS_ADMIN)
setkarma:help("Set a player's karma.")

function ulx.addkarma(calling_ply, target_plys, amount)
    amount = math.floor(tonumber(amount) or 0)

    for _, v in ipairs(target_plys) do
        local newKarma = GetPlayerKarma(v) + amount
        SetPlayerKarma(v, newKarma)
    end

    ulx.fancyLogAdmin(calling_ply, "#A added #i karma to #T", amount, target_plys)
end

local addkarma = ulx.command(CATEGORY, "ulx addkarma", ulx.addkarma, "!addkarma")
addkarma:addParam{ type = ULib.cmds.PlayersArg }
addkarma:addParam{ type = ULib.cmds.NumArg, hint = "amount", min = 0 }
addkarma:defaultAccess(ULib.ACCESS_ADMIN)
addkarma:help("Add karma to a player.")

function ulx.removekarma(calling_ply, target_plys, amount)
    amount = math.floor(tonumber(amount) or 0)

    for _, v in ipairs(target_plys) do
        local newKarma = GetPlayerKarma(v) - amount
        SetPlayerKarma(v, newKarma)
    end

    ulx.fancyLogAdmin(calling_ply, "#A removed #i karma from #T", amount, target_plys)
end

local removekarma = ulx.command(CATEGORY, "ulx removekarma", ulx.removekarma, "!removekarma")
removekarma:addParam{ type = ULib.cmds.PlayersArg }
removekarma:addParam{ type = ULib.cmds.NumArg, hint = "amount", min = 0 }
removekarma:defaultAccess(ULib.ACCESS_ADMIN)
removekarma:help("Remove karma from a player.")

local function SetPlayerSpectator(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if not TEAM_SPECTATOR then return false end

    if ply:Alive() then
        ply:Kill()
    end

    ply:SetTeam(TEAM_SPECTATOR)

    if ply.afkTime then
        ply.afkTime = 0
    end

    if ply.afkTime2 then
        ply.afkTime2 = 0
    end

    return true
end

function ulx.setspectator(calling_ply, target_plys)
    local affected = {}

    for _, v in ipairs(target_plys) do
        if SetPlayerSpectator(v) then
            affected[#affected + 1] = v
        end
    end

    if #affected > 0 then
        ulx.fancyLogAdmin(calling_ply, "#A moved #T to spectators", affected)
    else
        ULib.tsayError(calling_ply, "No valid players were moved to spectators.", true)
    end
end

local setspectator = ulx.command(CATEGORY, "ulx setspectator", ulx.setspectator, "!setspectator")
setspectator:addParam{ type = ULib.cmds.PlayersArg }
setspectator:defaultAccess(ULib.ACCESS_ADMIN)
setspectator:help("Moves a player to the spectator team.")

function ulx.forcemode(calling_ply, modeName)
    local mode = zb.modes[modeName]
    if not (mode and mode.CanLaunch and mode:CanLaunch()) then
        ULib.tsayError(calling_ply, "Mode '" .. modeName .. "' cannot be launched.", true)
        return
    end

    NextRound(modeName)

    local msg = "Next round mode forced to '" .. modeName .. "'."
    ULib.tsay(_, msg)
    ulx.fancyLogAdmin(calling_ply, "#A forced next round mode to #s", modeName)
    ulx.logString(msg)
    Msg(msg .. "\n")
end

local forcemode = ulx.command(CATEGORY, "ulx forcemode", ulx.forcemode, "!forcemode")
forcemode:addParam{
    type = ULib.cmds.StringArg,
    completes = {"tdm", "gwars", "riot", "criresp", "defense", "hl2dm", "dm", "cstrike"},
    hint = "mode",
    ULib.cmds.restrictToCompletes
}
forcemode:defaultAccess(ULib.ACCESS_ADMIN)
forcemode:help("Forces the next round mode without a vote.")
