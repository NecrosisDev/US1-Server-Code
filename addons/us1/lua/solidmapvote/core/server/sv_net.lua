local M = SolidMapVote
for _, name in ipairs({"start", "end", "cancel", "sendVotes", "sendNominations", "sendMessage", "sendPlayCounts", "sendMapPool", "sound", "deadline"}) do
    util.AddNetworkString("SolidMapVote." .. name)
end
local function deliver(all, ply) if all then net.Broadcast() elseif IsValid(ply) then net.Send(ply) end end
local function sendTable(name, data, all, ply)
    net.Start("SolidMapVote." .. name); net.WriteTable(data); deliver(all, ply)
end
function M.sendVotes(all, ply) sendTable("sendVotes", M.votes, all, ply) end
function M.sendNominations(all, ply) sendTable("sendNominations", M.nominations, all, ply) end
function M.sendMessage(data, all, ply) sendTable("sendMessage", data, all, ply) end
function M.sendPlayCounts(data, all, ply) sendTable("sendPlayCounts", data, all, ply) end
function M.sendStart(all, ply)
    net.Start("SolidMapVote.start"); net.WriteTable(M.maps)
    net.WriteFloat(CurTime() + math.max(0, (M.deadline or RealTime()) - RealTime()))
    net.WriteFloat(M.ballotLength or M.number("Length", 25, 5, 120)) -- the final intermission's ballot is longer (sv_mapvote.lua M.openFinalBallot)
    net.WriteBool(M.ballotSet.extend == true); net.WriteBool(M.ballotSet.random == true); net.WriteUInt(M.ballotRevision or 0,32); deliver(all, ply)
    if M.sendReroll then M.sendReroll(all,ply) end
end
-- Adversarial review fix (2026-09-23): a deadline extension (M.extendDeadline, sv_mapvote.lua)
-- must NOT reuse M.sendStart - that resends the full maps/length/reroll packet, which cl_net.lua
-- treats as a brand-new ballot (resets its reroll/vote caches and, via the V5 defer wrapper,
-- reopens the panel even for someone already voting). This carries only the new deadline.
function M.sendDeadline(all, ply)
    local finish = CurTime() + math.max(0, (M.deadline or RealTime()) - RealTime())
    net.Start("SolidMapVote.deadline")
    net.WriteFloat(finish)
    net.WriteFloat(finish - (M.startTime or finish)) -- new total length, so the panel's progress bar stays consistent
    deliver(all, ply)
end
function M.sendResult(all, ply)
    net.Start("SolidMapVote.end"); net.WriteTable(M.winningMaps)
    net.WriteString(M.realWinner); net.WriteString(M.fixedWinner); deliver(all, ply)
    if M.sendReroll then M.sendReroll(all,ply) end
end
function M.sendMapPool(all, ply)
    local pages = math.max(1, math.ceil(#M.mapPool / 100))
    for page = 1, pages do
        local names = {}
        for i = (page - 1) * 100 + 1, math.min(page * 100, #M.mapPool) do names[#names + 1] = M.mapPool[i] end
        net.Start("SolidMapVote.sendMapPool")
        net.WriteUInt(M.poolVersion or 0, 16); net.WriteUInt(page, 16); net.WriteUInt(pages, 16)
        net.WriteTable(names); deliver(all, ply)
    end
end
function M.acceptRequest(ply, kind, delay)
    if not M.initialized or not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return false end
    M.requestTimes = M.requestTimes or setmetatable({}, {__mode = "k"})
    local t = M.requestTimes[ply] or {}; M.requestTimes[ply] = t
    local now = RealTime()
    if (t[kind] or 0) > now then return false end
    t[kind] = now + delay; return true
end
function M.sync(ply)
    if M.isOpen then
        M.sendStart(false, ply)
        M.sendPlayCounts(M.createWeightedPool(M.maps, M.mapPlayCounts), false, ply)
        M.sendVotes(false, ply); M.sendNominations(false, ply)
        if M.finished then M.sendResult(false, ply) end
    else
        net.Start("SolidMapVote.cancel"); net.Send(ply)
        M.sendNominations(false, ply)
    end
end
-- work/loader/killcam_20260924/BRIEF_VOTES.md V1: per-player ballot send for
-- lua/autorun/server/zc_vote_manager.lua's early-voting arbiter (a player who won't see the
-- round-end killcam highlight). Reuses the same packet builders as M.sync's isOpen branch; the
-- vote's own global start/deadline is untouched by sending to one more player.
function M.sendBallotTo(ply)
    if not M.isOpen or not IsValid(ply) then return false end
    M.sendStart(false, ply)
    M.sendPlayCounts(M.createWeightedPool(M.maps, M.mapPlayCounts), false, ply)
    M.sendVotes(false, ply); M.sendNominations(false, ply)
    return true
end
concommand.Add("solidmapvote_vote", function(ply, _, args)
    if not M.acceptRequest(ply, "vote", 0.5) then return end
    local revision=tonumber(args[2])
    if revision~=M.ballotRevision then
        -- Existing clients may vote only on the initial, never-rerolled ballot.
        if args[2]~=nil or (M.rerolls or 0)>0 then return end
    end
    M.vote(ply:SteamID64(), args[1])
end, nil, "Internal (map vote window): vote for a map.")
concommand.Add("solidmapvote_nominate", function(ply, _, args)
    if not M.acceptRequest(ply, "nominate", 1) or not M.Config["Nomination Permissions"](ply) then return end
    local changed = M.playerHasNominated(ply:SteamID64()) ~= nil
    if M.nominate(ply:SteamID64(), args[1]) then
        M.sendMessage({color_white, ply:Nick() .. (changed and " changed their nomination to " or " nominated ") .. args[1]}, true)
    else M.sendMessage({color_white, "That nomination is unavailable, unchanged, or the six nomination slots are full."}, false, ply) end
end, nil, "Internal (map vote window): nominate a map.")
concommand.Add("solidmapvote_request_mappool", function(ply)
    if M.acceptRequest(ply, "pool", 3) then M.sendMapPool(false, ply) end
end, nil, "Internal (map vote window): request the map pool.")
concommand.Add("solidmapvote_request_nominations", function(ply)
    if M.acceptRequest(ply, "nominations", 1) then M.sendNominations(false, ply) end
end, nil, "Internal (map vote window): request the nominations.")
concommand.Add("solidmapvote_ready", function(ply)
    if M.acceptRequest(ply, "sync", 2) then M.sync(ply) end
end, nil, "Internal (map vote window): request the current vote state.")
