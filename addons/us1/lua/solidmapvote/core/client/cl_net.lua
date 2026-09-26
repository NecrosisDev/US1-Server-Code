local M = SolidMapVote
-- work/loader/killcam_20260924/BRIEF_VOTES.md V5: don't pop the map-vote panel on top of a
-- running killcam replay. Coded against ZCKillcamView with nil-guards, per the brief - none of
-- these names existed anywhere in lua/zc_killcam/ (or its patch copies) at the time this file was
-- written, since that contract belongs to the concurrently-worked killcam builder; every branch
-- falls through to "not playing" (open immediately), matching today's behaviour, until it lands.
--
-- Adversarial review fix (2026-09-23): the defer had no off switch and no upper bound. Both are
-- fixed here:
--  * `zc_vote_defer_killcam` (client convar, default 1) - the owner's stated reason default-on is
--    acceptable at all is that the defer is bounded (below), not open-ended.
--  * `DEFER_TIMEOUT` (20s, RealTime()-based - a UI wall-clock bound, not tied to game simulation):
--    if IsPlaying() (or whichever flag answers) stays true this long, open anyway rather than
--    risk never opening because the killcam contract's flag got stuck.
local cvDeferKillcam = CreateClientConVar("zc_vote_defer_killcam", "1", true, false,
    "Wait for a running killcam replay to finish before opening the map-vote panel (bounded to 20s). 0 = never wait.", 0, 1)
local DEFER_TIMEOUT = 20

local function killcamPlaying()
    if not cvDeferKillcam:GetBool() then return false end
    local V = ZCKillcamView
    if not istable(V) then return false end
    if isfunction(V.IsPlaying) then
        local ok, playing = pcall(V.IsPlaying)
        if ok then return playing == true end
    end
    if V.Playing ~= nil then return V.Playing == true end
    if V.playing ~= nil then return V.playing == true end
    if V.Life and V.Life.playing ~= nil then return V.Life.playing == true end
    return false
end

local deferredOpen -- {maps, finish, length, armedAt}: held back while killcamPlaying() is true

net.Receive("SolidMapVote.start", function()
    local maps, finish, length = net.ReadTable(), net.ReadFloat(), net.ReadFloat()
    M.allowExtend, M.allowRandom = net.ReadBool(), net.ReadBool()
    local _,bits=net.BytesLeft()
    M.ballotRevision=bits and bits>=32 and net.ReadUInt(32) or 0
    M.rerollState=nil;M.sendVotes={};M.sendPlayCounts={}
    M.receivedSync = true
    if killcamPlaying() then
        deferredOpen = {maps = maps, finish = finish, length = length, armedAt = RealTime()}
        return
    end
    deferredOpen = nil
    M.open(maps, finish, length)
end)
-- Adversarial review fix (2026-09-23): a vote that ends (reset/cancelled) while a client is mid-
-- defer must never open afterward - dropping deferredOpen here, rather than only when the Think
-- hook next runs, means the stale panel is discarded even if that hook is what fires next tick.
net.Receive("SolidMapVote.cancel", function() deferredOpen = nil; M.receivedSync = true; M.close() end)
-- Adversarial review fix (2026-09-23): update the countdown of an ALREADY-open panel (or a still-
-- deferred one) in place; never treat a deadline extension as a new ballot (that was defect 2 -
-- see sv_mapvote.lua's M.extendDeadline / sv_net.lua's M.sendDeadline).
net.Receive("SolidMapVote.deadline", function()
    local finish, length = net.ReadFloat(), net.ReadFloat()
    if deferredOpen then
        deferredOpen.finish, deferredOpen.length = finish, length
        return
    end
    if M.isOpen and IsValid(M.Menu) then
        M.Menu:SetTime(finish, length)
    end
end)
hook.Add("Think", "SolidMapVote.DeferredOpen", function()
    if not deferredOpen then return end
    local timedOut = RealTime() - deferredOpen.armedAt >= DEFER_TIMEOUT
    if not timedOut and killcamPlaying() then return end
    local d = deferredOpen
    deferredOpen = nil
    -- Stale-drop: the deadline (kept current by the "SolidMapVote.deadline" handler above,
    -- including any V3 extension) already passed while we waited - the vote is over, so opening
    -- a panel to "vote" on it now would show a dead ballot. Covers both an ordinary timeout past
    -- the vote's own end and a vote that closed/reset without a "SolidMapVote.cancel" (results
    -- already sent) reaching this deferred entry specifically.
    if CurTime() >= d.finish then return end
    M.open(d.maps, d.finish, d.length)
end)
for name, event in pairs({sendVotes="UpdateVotes", sendNominations="UpdateNominations", sendPlayCounts="MapPlayCounts"}) do
    local cacheKey, hookName = name, event
    net.Receive("SolidMapVote." .. name, function()
        local data = net.ReadTable()
        M[cacheKey] = data
        hook.Run("SolidMapVote." .. hookName, data)
    end)
end
net.Receive("SolidMapVote.sendMessage", function() chat.AddText(unpack(net.ReadTable())) end)
net.Receive("SolidMapVote.end", function()
    hook.Run("SolidMapVote.WinningMaps", net.ReadTable(), net.ReadString(), net.ReadString())
end)
net.Receive("SolidMapVote.sound", function() surface.PlaySound(net.ReadBool() and "rtv.wav" or "nortv.wav") end)
local incoming
net.Receive("SolidMapVote.sendMapPool", function()
    local version, page, pages, names = net.ReadUInt(16), net.ReadUInt(16), net.ReadUInt(16), net.ReadTable()
    if pages < 1 or pages > 100 or page < 1 or page > pages or #names > 100 then return end
    if not incoming or incoming.version ~= version or incoming.total ~= pages then
        incoming = {version=version, total=pages, chunks={}}
    end
    incoming.chunks[page] = names
    local pool = {}
    for i = 1, pages do
        if not incoming.chunks[i] then return end
        for _, name in ipairs(incoming.chunks[i]) do pool[#pool + 1] = name end
    end
    M.mapPool = pool
    hook.Run("SolidMapVote.UpdateMapPool", pool)
end)
hook.Add("InitPostEntity", "SolidMapVote.ClientReady", function()
    M.receivedSync = false
    RunConsoleCommand("solidmapvote_ready")
    timer.Create("SolidMapVote.ReadyRetry", 3, 3, function()
        if not M.receivedSync then RunConsoleCommand("solidmapvote_ready") end
    end)
end)

M.RerollClientVersion="20260915.1"
function M.SendBallotVote(choice)
    RunConsoleCommand("solidmapvote_vote",choice,tostring(M.ballotRevision or 0))
end
net.Receive("SolidMapVote.rerollState",function()
    local state=net.ReadTable()
    if not istable(state) or state.revision~=M.ballotRevision then return end
    M.rerollState=state
end)
function M.RerollButtonState(finished)
    local s=M.rerollState
    if not s then return "REROLL",false,"Waiting for the current ballot." end
    if finished then return "REROLL",false,"Voting has finished." end
    if s.used>=s.limit then return "REROLL LIMIT",false,"This vote has reached its reroll limit." end
    if s.available<1 then return "NO NEW MAPS",false,"No other eligible maps are available." end
    local label=string.format("REROLL  %d/%d",s.count,s.needed)
    local tip="Vote to replace these maps for everyone. Existing map votes reset when it passes. Click again to withdraw."
    return label,s.enabled==true and CurTime()>=(s.ready or 0),tip
end
