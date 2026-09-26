-- Server-owned, once-per-round forfeit vote: dead humans on a side that has
-- only bots left alive may end the round early. Sibling to
-- reinforce/sv_zc_reinforcement_vote.lua (mirrors its roster/eligibility/
-- single-use shape); never edits that file or any gamemode/addon file.
-- Ships inert: zc_forfeit_enable defaults to 0.
if not SERVER then return end

ZCForfeitVote = ZCForfeitVote or {}
local R = ZCForfeitVote
R.Version = 1

local enabled = CreateConVar("zc_forfeit_enable", "0", FCVAR_ARCHIVE,
    "Allow dead humans on a side with only bots left alive to vote to forfeit the round.", 0, 1)

local PREFIX = "[Forfeit] "
local POLL = "ZCForfeitVote_Poll"
local ENGAGE_WINDOW = 10  -- owner's rule, verbatim ("over 10 seconds")
local VOTE_DEADLINE = 45  -- reused verbatim from sv_zc_reinforcement_vote.lua:241
local RETRY_COOLDOWN = 30 -- reused verbatim from sv_zc_reinforcement_vote.lua:149
local AFK_LIMIT = 60      -- reused verbatim from sv_zc_reinforcement_vote.lua:57
local TALLY_THROTTLE = 3  -- reused verbatim from sv_zc_reinforcement_vote.lua:248

R.Cooldowns = R.Cooldowns or setmetatable({}, {__mode = "k"})

-- Family (a): team-vs-team modes. Alive/bot split is read generically from
-- zb:CheckAliveTeams(true) (shared.lua:90) -- the exact same call tdm
-- (sv_tdm.lua:41), gwars (sv_gwars.lua:41), wildcard (sv_wildcard.lua:360),
-- hl2dm (sv_hl2dm.lua:33) and cstrike (sv_cstrike.lua:352) already use for
-- their own ShouldRoundEnd. criresp/riot/uncontainedriot additionally treat
-- a handcuffed player as not-contesting inside their own CheckAlivePlayers;
-- that extra nuance is NOT replicated here (documented scope limitation --
-- it only makes the trigger fire slightly later, never spuriously). coop and
-- defense place every human on a single team (sv_coop.lua:193,
-- sv_defense.lua:265) with no adversarial human/bot team on the other side,
-- so this generic per-team check degenerates correctly to the family-(c)
-- shape for them: forfeit becomes available once that one team is bot-only.
local TEAM_MODES = {
    tdm = true, cstrike = true, hl2dm = true, gwars = true, criresp = true,
    riot = true, uncontainedriot = true, wildcard = true, coop = true, defense = true,
}

-- Family (b): homicide's traitor/innocent split via ply.isTraitor, not
-- ply:Team(). zb.modes.hmcd:CheckAlivePlayers() (sv_homicide.lua:1370-1394)
-- returns {[0]=innocents (excludes traitors and police), [1]=traitors
-- (excludes handcuffed)}. activeshooter/masscasualty declare
-- MODE.base="hmcd" (sh_zz_activeshooter.lua:3, sh_zz_masscasualty.lua) and
-- define no CheckAlivePlayers of their own, so loader.lua:63's
-- table.Inherit(MODE, zb.modes[MODE.base]) copies hmcd's own function
-- reference into them verbatim -- proven by inheritance, not re-guessed.
-- "wildwest" is a sub-round self.Type of hmcd (sv_homicide.lua:1142), not a
-- separate mode.name, so keying on mode.name == "hmcd" already covers it.
local TRAITOR_MODES = { hmcd = true, activeshooter = true, masscasualty = true }

-- Family (c): true FFA modes. All three define ShouldRoundEnd as
-- `#zb:CheckAlive(true) <= 1` verbatim (dm/sv_dm.lua:74, sfd/sv_sfd.lua:57,
-- zz_mayhem/sv_zz_mayhem.lua:51); zb:CheckAlive (shared.lua:109) is the flat,
-- team-less alive list this reuses. MODE.name for sfd is "superfighters"
-- (sfd/sv_sfd.lua:3), matching the owner's "superfighters" by name.
local FFA_MODES = { dm = true, superfighters = true, mayhem = true }

local function human(ply)
    return IsValid(ply) and ply:IsPlayer() and not ply:IsBot()
end

local function context()
    if not enabled:GetBool() or not zb or zb.ROUND_STATE ~= 1 or not isfunction(CurrentRound) then return end
    local mode = CurrentRound()
    if not istable(mode) or not isstring(mode.name) then return end
    if not TEAM_MODES[mode.name] and not TRAITOR_MODES[mode.name] and not FFA_MODES[mode.name] then return end
    return mode
end

local function current(state)
    return state and R.State == state and context() == state.mode and zb.ROUND_BEGIN == state.round
end

local function tell(ply, message)
    if human(ply) then ply:ChatPrint(PREFIX .. message) end
end

local function notifyVoters(info, message)
    for _, entry in ipairs(info.voters) do tell(entry.player, message) end
end

-- Every living entry in `list` must be a real bot (ply:IsBot(), realm-
-- standalone -- never gated on zc_bots or ply.zcBot per the brief).
local function allBots(list)
    if not istable(list) or #list == 0 then return false end
    for _, ply in ipairs(list) do
        if not IsValid(ply) or not ply:IsBot() then return false end
    end
    return true
end

-- Returns the list of currently populated "sides" for the mode, each as
-- {key=<string>, family=<"team"|"traitor"|"ffa">, teamId=<num|nil>, ready=<bool>}.
-- ready = "only bots alive on this side" (plus the 10s idle check for ffa).
local function computeSides(mode)
    local sides = {}
    if TEAM_MODES[mode.name] then
        local tbl = zb:CheckAliveTeams(true)
        for teamId, list in pairs(tbl) do
            if teamId ~= TEAM_UNASSIGNED and teamId ~= TEAM_SPECTATOR and istable(list) and #list > 0 then
                sides[#sides + 1] = { key = "team:" .. tostring(teamId), family = "team", teamId = teamId, ready = allBots(list) }
            end
        end
    elseif TRAITOR_MODES[mode.name] then
        local ok, list = pcall(function() return mode:CheckAlivePlayers() end)
        if ok and istable(list) then
            if istable(list[0]) and #list[0] > 0 then
                sides[#sides + 1] = { key = "innocent", family = "traitor", ready = allBots(list[0]) }
            end
            if istable(list[1]) and #list[1] > 0 then
                sides[#sides + 1] = { key = "traitor", family = "traitor", ready = allBots(list[1]) }
            end
        end
    elseif FFA_MODES[mode.name] then
        local list = zb:CheckAlive(true)
        if #list > 0 then
            local idle = (CurTime() - (R.LastEngagement or 0)) > ENGAGE_WINDOW
            sides[#sides + 1] = { key = "ffa", family = "ffa", ready = allBots(list) and idle }
        end
    end
    return sides
end

local function sideMatches(ply, side)
    if side.family == "team" then return ply:Team() == side.teamId end
    if side.family == "traitor" then return (ply.isTraitor == true) == (side.key == "traitor") end
    return true -- ffa: single shared side, no sub-split
end

local function sideKeyForPlayer(mode, ply)
    if TEAM_MODES[mode.name] then return "team:" .. tostring(ply:Team()) end
    if TRAITOR_MODES[mode.name] then return ply.isTraitor and "traitor" or "innocent" end
    if FFA_MODES[mode.name] then return "ffa" end
end

function R.EndRound()
    R.TrackEngagement = false
    R.State = nil
end

function R.BeginRound()
    local mode = context()
    if not mode then R.EndRound(); return end
    -- Repeated start notifications and file refreshes must not reset a spent vote.
    if R.LastRound and R.LastRound.mode == mode and R.LastRound.round == zb.ROUND_BEGIN then return end
    R.EndRound()
    local state = { mode = mode, round = zb.ROUND_BEGIN, roster = {}, ballots = {}, used = false }
    for _, ply in ipairs(player.GetHumans()) do
        local id = ply:SteamID64()
        if ply:Team() ~= TEAM_SPECTATOR and isstring(id) and id ~= "" and id ~= "0" then
            state.roster[id] = { id = id, player = ply, session = ply:UserID(), seenAlive = ply:Alive() }
        end
    end
    R.State = state
    R.LastRound = { mode = mode, round = state.round }
    -- Baseline the idle clock at round start, not at server boot/previous
    -- round's last hit -- otherwise a fresh FFA round could read as already
    -- "10s idle" before anyone has had a chance to fight.
    R.LastEngagement = CurTime()
    R.TrackEngagement = FFA_MODES[mode.name] == true
end

function R.RecordSpawn(ply)
    local state = R.State
    if not current(state) or not human(ply) then return end
    local entry = state.roster[ply:SteamID64()]
    if not entry or entry.player ~= ply or entry.session ~= ply:UserID() then return end
    entry.seenAlive = true
end

-- info.ballot is the per-side vote tally; multiple sides can be polled
-- independently in the same round (e.g. one TDM team goes bot-only while the
-- other still has humans), but state.used is round-global -- one forfeit
-- ends the whole round, so no other side's ballot can also fire afterward.
function R.Inspect(sideKey)
    local state = R.State
    if not current(state) then return nil, "No forfeit vote is available right now." end
    local side
    for _, s in ipairs(computeSides(state.mode)) do
        if s.key == sideKey then side = s break end
    end
    if not side then return nil, "Your side is not eligible to forfeit right now." end
    local ballot = state.ballots[sideKey]
    if not ballot then
        ballot = { votes = {}, notified = {}, deadline = nil, retryAt = 0, nextTallyAt = 0 }
        state.ballots[sideKey] = ballot
    end
    local result = { state = state, side = side, ballot = ballot, voters = {}, voterSet = {}, yes = 0 }
    for id, entry in pairs(state.roster) do
        local ply = entry.player
        if human(ply) and ply:SteamID64() == id and ply:UserID() == entry.session and entry.seenAlive
            and not ply:Alive() and ply:Team() ~= TEAM_SPECTATOR
            and (tonumber(ply.afkTime2) or 0) <= AFK_LIMIT and sideMatches(ply, side) then
            result.voters[#result.voters + 1] = entry
            result.voterSet[id] = entry
            if ballot.votes[id] then result.yes = result.yes + 1 end
        else
            ballot.votes[id] = nil
        end
    end
    -- Simple majority of currently-eligible dead humans on this side, reused
    -- verbatim from sv_zc_reinforcement_vote.lua:119 -- same math as the
    -- already-shipped reinforcement vote, so a sibling system does not
    -- invent a different fairness bar without reason.
    result.required = math.floor(#result.voters / 2) + 1
    result.available = side.ready and #result.voters > 0 and not state.used
    return result
end

function R.Poll()
    local state = R.State
    if not state then return end
    if not current(state) then R.EndRound(); return end
    if state.used then return end
    for _, side in ipairs(computeSides(state.mode)) do
        local info = R.Inspect(side.key)
        if info then
            local ballot = info.ballot
            if ballot.deadline and CurTime() >= ballot.deadline then
                ballot.votes = {}
                ballot.deadline = nil
                ballot.retryAt = CurTime() + RETRY_COOLDOWN
                notifyVoters(info, "Forfeit vote expired. A new vote can start in " .. RETRY_COOLDOWN .. " seconds.")
            end
            if not info.available then
                -- Cancels cleanly if the situation resolved itself (a human
                -- respawned, a bot died leaving a human survivor, or in FFA
                -- engagement resumed) -- next Poll simply stops offering it.
                ballot.votes = {}
            elseif CurTime() >= ballot.retryAt then
                for _, entry in ipairs(info.voters) do
                    if not ballot.notified[entry.id] then
                        ballot.notified[entry.id] = true
                        tell(entry.player, "Your side has only bots left. Type !forfeit to vote to end the round (" .. info.required .. " votes needed).")
                    end
                end
            end
        end
    end
end

local function pass(info)
    local state = info.state
    -- Re-validate at pass time, not just at vote time: recompute the side
    -- fresh (not the possibly-already-stale `info`) right before acting.
    local side
    for _, s in ipairs(computeSides(state.mode)) do
        if s.key == info.side.key then side = s break end
    end
    if not side or not side.ready then
        notifyVoters(info, "Forfeit cancelled -- the situation changed before the vote could take effect.")
        if state.ballots[info.side.key] then state.ballots[info.side.key].votes = {} end
        return
    end
    -- Consume before acting: command spam or a re-entrant hook cannot double-fire.
    state.used = true
    -- Side-agnostic on purpose: naming which side forfeited in the homicide
    -- family would be a mid-round tell beyond what the mode's own EndRound
    -- already reveals a couple seconds later regardless of cause.
    PrintMessage(HUD_PRINTTALK, PREFIX .. "The round has been forfeited by vote.")
    -- The single verified end-of-round path (libraries/sv_roundsystem.lua:74-91);
    -- same call site COMMANDS.endround/AdminEndRound already use to end a
    -- round early without a natural ShouldRoundEnd() winner. Each mode's own
    -- EndRound() decides "who won" from its own CheckAlivePlayers() at that
    -- instant, exactly as it would for any other manual early end -- this
    -- does not compute or force a winner itself.
    zb:EndRound()
end

function R.Command(ply, action)
    if not human(ply) then return end
    local now = CurTime()
    if (R.Cooldowns[ply] or 0) > now then return end
    R.Cooldowns[ply] = now + 1
    action = string.lower(tostring(action or ""))
    if action ~= "" and action ~= "yes" and action ~= "no" and action ~= "status" then
        tell(ply, "Use !forfeit [yes|no|status]."); return
    end
    local state = R.State
    if not current(state) then tell(ply, "No forfeit vote is available right now."); return end
    R.Poll()
    local sideKey = sideKeyForPlayer(state.mode, ply)
    local info, reason
    if sideKey then
        info, reason = R.Inspect(sideKey)
    else
        reason = "No forfeit vote is available right now."
    end
    if not info then tell(ply, reason); return end
    if state.used then tell(ply, "This round has already been forfeited."); return end
    local id = ply:SteamID64()
    if not info.voterSet[id] or info.voterSet[id].player ~= ply then
        tell(ply, "Only eligible dead participants on a bot-only side can vote to forfeit."); return
    end
    if not info.available then
        tell(ply, "Forfeit voting requires your side to be down to bots only, with no human left alive on it."); return
    end
    local ballot = info.ballot
    if action == "status" then
        tell(ply, info.yes .. "/" .. info.required .. " forfeit votes."); return
    end
    if now < ballot.retryAt then
        tell(ply, "A new vote can start in " .. math.ceil(ballot.retryAt - now) .. " seconds."); return
    end
    if action == "no" then
        ballot.votes[id] = nil
        tell(ply, "Your forfeit vote has been withdrawn.")
        return
    end
    ballot.deadline = ballot.deadline or now + VOTE_DEADLINE
    if ballot.votes[id] then
        tell(ply, "Your vote is already counted (" .. info.yes .. "/" .. info.required .. ").")
    else
        ballot.votes[id] = true
        info.yes = info.yes + 1
        if now >= (ballot.nextTallyAt or 0) then
            ballot.nextTallyAt = now + TALLY_THROTTLE
            notifyVoters(info, info.yes .. "/" .. info.required .. " votes to forfeit. Type !forfeit to vote; !forfeit no to withdraw.")
        else
            tell(ply, "Vote recorded (" .. info.yes .. "/" .. info.required .. ").")
        end
    end
    -- Passage happens only on an explicit yes request, never just because someone leaves.
    if info.yes >= info.required then pass(info) end
end

-- FFA "successful engagement" reset, from real damage/death events -- never
-- proximity. HomigradDamage(ply, dmgInfo, hitgroup, ent, harm) signature and
-- dmgInfo:GetAttacker() confirmed via libraries/guilt/sv_guilt.lua:118-119
-- (ply there is the Victim). Cheapest possible early-return: a single
-- upvalue boolean set by BeginRound/EndRound, no function calls, before any
-- other work -- this fires on every damage/death event server-wide.
hook.Add("HomigradDamage", "ZCForfeitVote_Engagement", function(victim, dmgInfo)
    if not R.TrackEngagement then return end
    local attacker = dmgInfo and dmgInfo:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
    R.LastEngagement = CurTime()
end)

hook.Add("PlayerDeath", "ZCForfeitVote_EngagementDeath", function(victim, _, attacker)
    if not R.TrackEngagement then return end
    if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
    R.LastEngagement = CurTime()
end)

hook.Add("ZB_StartRound", "ZCForfeitVote_Start", R.BeginRound)
hook.Add("ZB_EndRound", "ZCForfeitVote_End", R.EndRound)
hook.Add("ZB_PreRoundStart", "ZCForfeitVote_Prepare", R.EndRound)
hook.Add("PreCleanupMap", "ZCForfeitVote_Cleanup", R.EndRound)
hook.Add("PlayerSpawn", "ZCForfeitVote_Spawn", R.RecordSpawn)
hook.Add("PlayerDisconnected", "ZCForfeitVote_Disconnect", function(ply)
    R.Cooldowns[ply] = nil
    local state = R.State
    if not state then return end
    local id = ply:SteamID64()
    for _, ballot in pairs(state.ballots) do ballot.votes[id] = nil end
end)

-- No client HUD receiver exists in the pulled trees for ZCReinforcementHUD
-- (grepped both us1/reinforce and the whole us1 addon tree -- only the
-- server file references it, no cl_zc_reinforcement_hud.lua anywhere), so
-- this does not invent a new net protocol against an unseen client: chat
-- only, same shape as zc_reinforcements_vote.
hook.Add("HG_PlayerSay", "ZCForfeitVote_Chat", function(ply, buffer)
    if not istable(buffer) or not isstring(buffer[1]) then return end
    local text = string.Trim(string.lower(buffer[1]))
    local command, action = string.match(text, "^(%S+)%s*(.-)$")
    if command ~= "!forfeit" then return end
    buffer[1] = ""
    R.Command(ply, action)
    return true -- only consume our own command; do not restore other modifiers' text.
end)
concommand.Add("zc_forfeit_vote", function(ply, _, args) R.Command(ply, args[1] or "yes") end)
timer.Create(POLL, 1, 0, R.Poll)
