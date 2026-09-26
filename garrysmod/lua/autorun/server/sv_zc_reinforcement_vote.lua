-- Server-owned, once-per-round spectator reinforcement vote.
if not SERVER then return end

ZCReinforcementVote = ZCReinforcementVote or {}
local R = ZCReinforcementVote
R.Version = 2
AddCSLuaFile("autorun/client/cl_zc_reinforcement_hud.lua")
AddCSLuaFile("zc_reinforcements/hud_model.lua")
util.AddNetworkString("ZCReinforcementHUD")
local enabled = CreateConVar("zc_reinforcement_vote_enabled", "1", FCVAR_ARCHIVE,
    "Allow eligible dead round participants to vote for one reinforcement wave.", 0, 1)
local DISPATCH = "ZCReinforcementVote_Dispatch"
local POLL = "ZCReinforcementVote_Poll"
local PREFIX = "[Reinforcements] "
-- Static payload to the stock client notification UI; no addon renderer or input hook.
-- Recheck death on receipt in case an automatic wave spawned this player in transit.
local POPUP = [[local p=LocalPlayer()
if IsValid(p) and not p:Alive() then
    notification.AddLegacy("85% of round participants are dead. Type !reinforcements to vote.", NOTIFY_HINT, 10)
end]]
local allowed = {standard="hmcd", gunfreezone="hmcd", soe="hmcd",
    activeshooter="activeshooter", masscasualty="masscasualty"}
R.Cooldowns = R.Cooldowns or setmetatable({}, {__mode="k"})

local function human(ply)
    return IsValid(ply) and ply:IsPlayer() and not ply:IsBot()
end

local function context()
    if not enabled:GetBool() or not zb or zb.ROUND_STATE ~= 1 or not isfunction(CurrentRound) then return end
    local mode = CurrentRound()
    if not istable(mode) or allowed[mode.Type] ~= mode.name then return end
    local definition = mode.Types and mode.Types[mode.Type]
    if not mode.PoliceAllowed or not definition or not definition.PoliceAllowed then return end
    local spawnOwner = ZCReinforcementVoteSpawn
    if not istable(spawnOwner) or not isfunction(spawnOwner.IsOwned) or not spawnOwner.IsOwned(mode) then return end
    if not isfunction(mode.CheckAlivePlayers) then return end
    if mode.Type == "soe" then
        if not isfunction(mode.EquipNationalGuard) then return end
    elseif not isfunction(definition.PoliceEquipment) then return end
    return mode
end

local function current(state)
    return state and R.State == state and context() == state.mode
        and state.mode.Type == state.kind and zb.ROUND_BEGIN == state.round
end

local function tell(ply, message)
    if human(ply) then ply:ChatPrint(PREFIX .. message) end
end

local function eligible(entry)
    local ply = entry.player
    return human(ply) and ply:SteamID64() == entry.id and ply:UserID() == entry.session and entry.seenAlive
        and not ply:Alive() and ply:Team() ~= TEAM_SPECTATOR
        and not entry.wasTraitor and not ply.isTraitor and (tonumber(ply.afkTime2) or 0) <= 60
end

function R.EndRound()
    timer.Remove(DISPATCH)
    R.State = nil
end

function R.BeginRound()
    local mode = context()
    if not mode then R.EndRound(); return end
    -- Repeated start notifications and file refreshes must not reset a spent wave.
    if R.LastRound and R.LastRound.mode == mode and R.LastRound.round == zb.ROUND_BEGIN then return end
    R.EndRound()
    local state = {mode=mode, kind=mode.Type, round=zb.ROUND_BEGIN,
        roster={}, votes={}, notified={}, used=false, retryAt=0}
    for _, ply in ipairs(player.GetHumans()) do
        local id = ply:SteamID64()
        if ply:Team() ~= TEAM_SPECTATOR and isstring(id) and id ~= "" and id ~= "0" then
            state.roster[id] = {id=id, player=ply, session=ply:UserID(), seenAlive=ply:Alive(),
                wasTraitor=ply.isTraitor == true, generation=0}
        end
    end
    R.State = state
    R.LastRound = {mode=mode, round=state.round}
end

function R.RecordSpawn(ply)
    local state = R.State
    if not current(state) or not human(ply) then return end
    local entry = state.roster[ply:SteamID64()]
    if not entry or entry.player ~= ply or entry.session ~= ply:UserID() then return end
    entry.seenAlive = true
    entry.wasTraitor = entry.wasTraitor or ply.isTraitor == true
    entry.generation = entry.generation + 1
    state.votes[entry.id] = nil
end

function R.Inspect()
    local state = R.State
    if not current(state) then return nil, "Available from the next supported round." end
    local result = {state=state, total=0, dead=0, voters={}, voterSet={}, yes=0}
    for id, entry in pairs(state.roster) do
        local ply = entry.player
        if human(ply) and ply:SteamID64() == id and ply:UserID() == entry.session then
            entry.wasTraitor = entry.wasTraitor or ply.isTraitor == true
            if ply:Alive() then entry.seenAlive = true end
            if entry.seenAlive then
                result.total = result.total + 1
                if not ply:Alive() then result.dead = result.dead + 1 end
            end
            if eligible(entry) then
                result.voters[#result.voters + 1] = entry
                result.voterSet[id] = entry
                if state.votes[id] then result.yes = result.yes + 1 end
            else
                state.votes[id] = nil
            end
        else
            state.votes[id] = nil
        end
    end
    result.required = math.floor(#result.voters / 2) + 1
    result.deathsRequired = math.ceil(result.total * 0.85)
    result.deathsLeft = math.max(0, result.deathsRequired - result.dead)
    result.thresholdMet = result.total > 0 and result.dead >= result.deathsRequired
    -- This query is read-only. Never call ShouldRoundEnd: it performs role-selection work.
    local alive = state.mode:CheckAlivePlayers()
    result.contested = istable(alive) and istable(alive[0]) and #alive[0] > 0
        and istable(alive[1]) and #alive[1] > 0
    result.available = result.thresholdMet and result.contested and #result.voters > 0 and not state.used
    return result
end

local function notifyVoters(info, message)
    for _, entry in ipairs(info.voters) do tell(entry.player, message) end
end

local function clearBallot(state)
    state.votes = {}
    state.deadline = nil
end

function R.Poll()
    local state = R.State
    if not state then return end
    if not current(state) then R.EndRound(); return end
    if state.used then return end
    local info = R.Inspect()
    if not info then return end
    if state.deadline and CurTime() >= state.deadline then
        clearBallot(state)
        state.retryAt = CurTime() + 30
        notifyVoters(info, "Vote expired. A new vote can start in 30 seconds.")
    end
    if not info.available then clearBallot(state); return end
    if CurTime() < state.retryAt then return end
    for _, entry in ipairs(info.voters) do
        if not state.notified[entry.id] then
            state.notified[entry.id] = true
            tell(entry.player, "85% of round participants are dead. Type !reinforcements to vote for one respawn wave (" .. info.required .. " votes needed).")
            entry.player:SendLua(POPUP)
        end
    end
end

function R.Dispatch()
    local state = R.State
    if not current(state) or not state.wave then timer.Remove(DISPATCH); return end
    local wave = state.wave
    -- Keep the mode's normal win conditions; do not respawn after victory is decided.
    local info = R.Inspect()
    if not info or not info.contested then state.wave=nil; timer.Remove(DISPATCH); return end
    local item = wave.queue[wave.cursor]
    if not item then
        state.wave=nil
        timer.Remove(DISPATCH)
        PrintMessage(HUD_PRINTTALK, PREFIX .. wave.spawned .. " reinforcements deployed.")
        return
    end
    wave.cursor = wave.cursor + 1
    local entry = item.entry
    -- Scheduled reinforcements, an admin respawn, or reconnect invalidate this queued life.
    if not eligible(entry) or entry.generation ~= item.generation then return end
    local ok, spawned = xpcall(function()
        return state.mode:SpawnForce(wave.teamtype, 1, {entry.player}, wave.context)
    end, debug.traceback)
    if not ok then
        wave.failed = true
        ErrorNoHalt(PREFIX .. "Deployment stopped: " .. tostring(spawned) .. "\n")
        state.wave=nil
        timer.Remove(DISPATCH)
        PrintMessage(HUD_PRINTTALK, PREFIX .. "Deployment stopped because of a server error.")
        return
    end
    wave.spawned = wave.spawned + (tonumber(spawned) or 0)
end

local function pass(info)
    local state = info.state
    -- Consume before the first spawn: callbacks and command spam cannot create a second wave.
    state.used = true
    clearBallot(state)
    local queue = {}
    for _, entry in ipairs(info.voters) do queue[#queue+1] = {entry=entry, generation=entry.generation} end
    for i=#queue,2,-1 do local j=math.random(i); queue[i],queue[j]=queue[j],queue[i] end
    state.wave = {queue=queue, cursor=1, spawned=0, context={spawned=0},
        teamtype=state.kind == "soe" and "nationalguard" or "police"}
    state.deployment = {spawned=0, planned=#queue}
    PrintMessage(HUD_PRINTTALK, PREFIX .. "Spectator vote passed. Reinforcements are deploying.")
    -- At most one player spawn/loadout per 0.2 seconds, under the current round identity.
    timer.Create(DISPATCH, 0.2, 0, R.Dispatch)
end

function R.Command(ply, action)
    if not human(ply) then return end
    local now = CurTime()
    if (R.Cooldowns[ply] or 0) > now then return end
    R.Cooldowns[ply] = now + 1
    action = string.lower(tostring(action or ""))
    if action ~= "" and action ~= "yes" and action ~= "no" and action ~= "status" then
        tell(ply, "Use !reinforcements [yes|no|status]."); return
    end
    R.Poll()
    local info, reason = R.Inspect()
    if not info then tell(ply, reason); return end
    local state = info.state
    if state.used then tell(ply, "This round's voted reinforcement wave has already been used."); return end
    if not info.voterSet[ply:SteamID64()] or info.voterSet[ply:SteamID64()].player ~= ply then
        tell(ply, "Only eligible dead participants can vote; killers, AFK players, voluntary spectators and late joiners are excluded."); return
    end
    if not info.available then
        tell(ply, "Voting requires at least 85% of round participants to be dead while the round is still contested."); return
    end
    if action == "status" then
        tell(ply, info.yes .. "/" .. info.required .. " votes; " .. info.dead .. "/" .. info.total .. " round participants dead."); return
    end
    if now < state.retryAt then tell(ply, "A new vote can start in " .. math.ceil(state.retryAt-now) .. " seconds."); return end
    local id = ply:SteamID64()
    if action == "no" then
        state.votes[id] = nil
        tell(ply, "Your yes vote has been withdrawn.")
        return
    end
    state.deadline = state.deadline or now + 45
    if state.votes[id] then
        tell(ply, "Your vote is already counted (" .. info.yes .. "/" .. info.required .. ").")
    else
        state.votes[id] = true
        info.yes = info.yes + 1
        if now >= (state.nextTallyAt or 0) then
            state.nextTallyAt = now + 3
            notifyVoters(info, info.yes .. "/" .. info.required .. " votes for reinforcements. Type !reinforcements to vote; !reinforcements no to withdraw.")
        else
            tell(ply, "Vote recorded (" .. info.yes .. "/" .. info.required .. ").")
        end
    end
    -- Passage happens only on an explicit yes request, never just because someone leaves.
    if info.yes >= info.required then pass(info) end
end

-- Compact, server-authoritative spectator HUD; no client-to-server receiver.
local hudSent = setmetatable({}, {__mode="k"})
function R.PushHUD()
    local info = R.Inspect()
    local state = info and info.state
    for _, ply in ipairs(player.GetHumans()) do
        local packet = {phase=0}
        if human(ply) and not ply:Alive() and info then
            local entry = info.voterSet[ply:SteamID64()]
            local progress = state.deployment or {spawned=0, planned=0}
            local phase = 1 -- locked
            if state.used then phase = state.wave and 4 or 5
            elseif not info.contested then phase = 6
            elseif info.thresholdMet then
                phase = CurTime() < state.retryAt and 3 or 2
            end
            packet = {phase=phase, total=info.total, dead=info.dead, deathsLeft=info.deathsLeft,
                yes=info.yes, required=info.required, spawned=progress.spawned, planned=progress.planned,
                eligible=entry ~= nil and entry.player == ply, voted=state.votes[ply:SteamID64()] == true,
                guard=state.kind == "soe", stopped=progress.stopped == true,
                seconds=math.max(0, math.ceil((phase == 3 and state.retryAt or state.deadline or 0)-CurTime()))}
        end
        local signature = table.concat({packet.phase,packet.total or 0,packet.dead or 0,packet.deathsLeft or 0,
            packet.yes or 0,packet.required or 0,packet.spawned or 0,packet.planned or 0,
            tostring(packet.eligible),tostring(packet.voted),tostring(packet.guard),tostring(packet.stopped),packet.seconds or 0}, ":")
        local last = hudSent[ply]
        -- Alive/unsupported players receive at most one hide update, never a heartbeat.
        if (not last and packet.phase ~= 0) or (last and (last.signature ~= signature
            or (packet.phase ~= 0 and CurTime()-last.at >= 2))) then
            net.Start("ZCReinforcementHUD")
            net.WriteUInt(packet.phase, 3)
            if packet.phase ~= 0 then
                for _, key in ipairs({"total","dead","deathsLeft","yes","required","spawned","planned","seconds"}) do
                    net.WriteUInt(math.Clamp(packet[key],0,65535),16)
                end
                net.WriteBool(packet.eligible); net.WriteBool(packet.voted)
                net.WriteBool(packet.guard); net.WriteBool(packet.stopped)
            end
            net.Send(ply)
            hudSent[ply] = {signature=signature,at=CurTime()}
        end
    end
end

-- Keep progress after dispatch completes, including skipped or failed candidates.
local dispatch = R.Dispatch
function R.Dispatch()
    local state = R.State
    local wave = state and state.wave
    dispatch()
    if wave and R.State == state then
        state.deployment = {spawned=wave.spawned, planned=#wave.queue,
            stopped=wave.failed == true or (not state.wave and wave.cursor <= #wave.queue)}
    end
    R.PushHUD()
end
local poll = R.Poll
function R.Poll() poll(); R.PushHUD() end
local command = R.Command
function R.Command(ply, action)
    local before = R.Cooldowns[ply]
    command(ply, action)
    if R.Cooldowns[ply] ~= before then R.PushHUD() end
end
local endRound = R.EndRound
function R.EndRound() endRound(); R.PushHUD() end
local beginRound = R.BeginRound
function R.BeginRound() beginRound(); R.PushHUD() end

hook.Add("ZB_StartRound", "ZCReinforcementVote_Start", R.BeginRound)
hook.Add("ZB_EndRound", "ZCReinforcementVote_End", R.EndRound)
hook.Add("ZB_PreRoundStart", "ZCReinforcementVote_Prepare", R.EndRound)
hook.Add("PreCleanupMap", "ZCReinforcementVote_Cleanup", R.EndRound)
hook.Add("PlayerSpawn", "ZCReinforcementVote_Spawn", R.RecordSpawn)
hook.Add("PlayerDisconnected", "ZCReinforcementVote_Disconnect", function(ply)
    R.Cooldowns[ply] = nil
    if R.State then R.State.votes[ply:SteamID64()] = nil end
end)
hook.Add("HG_PlayerSay", "ZCReinforcementVote_Chat", function(ply, buffer)
    if not istable(buffer) or not isstring(buffer[1]) then return end
    local text = string.Trim(string.lower(buffer[1]))
    local command, action = string.match(text, "^(%S+)%s*(.-)$")
    if command ~= "!reinforcements" and command ~= "!reinforce" then return end
    buffer[1] = ""
    R.Command(ply, action)
    return true -- only consume our own commands; stop later modifiers restoring their text.
end)
concommand.Add("zc_reinforcements_vote", function(ply, _, args) R.Command(ply, args[1] or "yes") end)
timer.Create(POLL, 1, 0, R.Poll)
