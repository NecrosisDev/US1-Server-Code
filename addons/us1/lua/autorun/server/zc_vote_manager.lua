-- US1 Round System v2, Stage 1: vote arbiter (server). work/loader/round_v2/BLUEPRINT.md S1.3.
-- Dark by default (zc_vote_manager 0). Chains the EXISTING vote systems; rewrites none of them.
--
-- Blueprint-vs-reality notes (read before touching this file):
--   * `zb.StartRTV` (the seam the blueprint names for solidmapvote, sv_hooks.lua:47) is vestigial
--     once solidmapvote is active: solidmapvote's zb.PreRound override (M.preRoundOverride,
--     sv_hooks.lua:22-45) replaces zb:PreRound WHOLESALE and never calls zb.StartRTV at all - only
--     the vanilla zb:PreRound (sv_roundsystem.lua:52) does, and that body never runs once
--     solidmapvote installs. The real, reachable "does the ballot actually open" seam is
--     SolidMapVote.openBallot (sv_mapvote.lua:169-184, a genuine global field), so that is what
--     is wrapped here instead. SolidMapVote.start (sv_mapvote.lua:186-190) only sets a `pending`
--     flag; the round system's own preRoundOverride retries openBallot() every PreRound tick
--     while pending is true, so declining to open here (return false, leave M.pending alone)
--     produces the queued-retry behaviour for free, with no separate expiry timer needed.
--   * sh_mode_vote.lua's StartVote/ApplyLeader (the blueprint's "line ~447"/"line ~282") are LOCAL
--     functions inside an `if SERVER then ... end` block - there is no global slot to monkey-patch.
--     ZC_MODEVOTE_ACTIVE, which solidmapvote already reads defensively
--     (`ZC_MODEVOTE_ACTIVE and ZC_MODEVOTE_ACTIVE()`) at sv_hooks.lua:36 and sv_mapvote.lua:166,
--     was never defined anywhere in this tree (confirmed: lua/zc_bots/sv_lowpop.lua:52 has a
--     comment noting exactly this). The smallest possible edit - patch/addons/admin_max_karma/
--     lua/autorun/sh_mode_vote.lua - defines it (fixing that pre-existing dead check as a side
--     effect) and adds one gate line to StartVote. See STAGE1_REPORT.md for the exact diff.
--   * ulx.votemap (per-player incremental map voting, votemap.lua) has no discrete "start" call -
--     votes just accumulate. Only ulx.votemap2 and ulx.vote (both admin-started, both already
--     self-excluding via `ulx.voteInProgress`) are wrapped. Casting an ordinary "!votemap <map>"
--     vote is left alone; see STAGE1_REPORT.md for why.
--   * ulx.command() (sh_base.lua:58-76) stores the function object directly on the returned
--     ulxCommand (`self.fn = fn`, `ulib/shared/commands.lua:1097`, called via `self.fn(...)` at
--     :1215) - reassigning the GLOBAL `ulx.votemap2`/`ulx.vote` after votemap.lua/vote.lua already
--     ran would not be seen by the registered command at all. This file instead finds the
--     registered ulxCommand object in `ulx.cmdsByCategory` and patches its `.fn` field, which is
--     what actually executes on "!votemap2"/"!vote" - still no ULX file touched.
if not SERVER then return end

ZCVoteManager = ZCVoteManager or {}
local VM = ZCVoteManager
VM.Version = "20260924.s4"
VM.active = VM.active or nil
VM.queue = VM.queue or {}
VM.wraps = VM.wraps or {}
VM.nextToken = VM.nextToken or 0

local cvVM = CreateConVar("zc_vote_manager", "0", FCVAR_ARCHIVE,
    "One active vote/poll at a time across map vote, mode vote, ULX votes, forfeit and reinforcements. 0 off (current behaviour), 1 on.", 0, 1)

-- work/loader/killcam_20260924/BRIEF_VOTES.md: early voting for players who won't see the
-- round-end killcam highlight (killcams off, or not sent one at all). Dark by default and only
-- meaningful once zc_vote_manager is also on (both convars gate every line below).
local cvEarly = CreateConVar("zc_vote_early", "0", FCVAR_ARCHIVE,
    "Open the pending map/mode ballot immediately for players who will not see the round-end killcam highlight, instead of making them wait for it. 0 off, 1 on.", 0, 1)
local cvMinWindow = CreateConVar("zc_vote_min_window", "8", FCVAR_ARCHIVE,
    "Minimum seconds a vote must stay open after the killcam highlight ends; its deadline is extended by the shortfall if needed.", 0, 60)
-- Integration 7 (owner, 2026-09-24): the last intermission before a map change; see the block below.
local cvFinal = CreateConVar("zc_final_intermission", "60", FCVAR_ARCHIVE,
    "Seconds the last intermission before a map change lasts: the map vote opens at round end and runs inside it. 0 = old flow (ballot at PreRound).", 0, 300)

-- Shares data/zc_round_v2/ with zc_round_guard.lua. file.Append (verified live elsewhere in this
-- tree: lua/zc_killcam/sv_tape.lua:174, lua/autorun/server/zc_make_crawler.lua:56, 17+ more call
-- sites) for the hot per-line path; a 200-line rotation (keep last 100, needs a full
-- file.Read/file.Write) runs at most once per map instead of on every append.
local DIR = "zc_round_v2"
local ROTATE_CAP, ROTATE_KEEP = 200, 100

local function appendLine(rel, line)
    file.CreateDir(DIR)
    file.Append(DIR .. "/" .. rel, line .. "\n")
end

local function rotateBootLogOncePerMap()
    file.CreateDir(DIR)
    local path = DIR .. "/boot.txt"
    local existing = file.Read(path, "DATA")
    if not existing or existing == "" then return end
    local lines, n = {}, 0
    for line in existing:gmatch("([^\n]*)\n") do n = n + 1 lines[n] = line end
    if n <= ROTATE_CAP then return end
    local kept, first = {}, n - ROTATE_KEEP + 1
    for i = first, n do kept[#kept + 1] = lines[i] end
    file.Write(path, table.concat(kept, "\n") .. "\n")
end
hook.Add("PostCleanupMap", "ZCVoteManager_RotateBootLog", rotateBootLogOncePerMap)

local function receipt(line) appendLine("boot.txt", os.date("%Y-%m-%d %H:%M:%S") .. " " .. line) end

-- ---------------------------------------------------------------------------------------------
-- Core arbiter: one active slot, a queue behind it. Round-end priority: map > mode > others
-- (re-sorted at ZB_EndRound). In-round: first come, others queued. Requests are idempotent per
-- (kind, ownerId) so a caller that retries every tick (solidmapvote's preRoundOverride does)
-- does not pile up duplicate queue entries.
local PRIORITY = { map = 1, mode = 2, ulx = 3, forfeit = 4, reinforcement = 5 }
local function priorityOf(kind) return PRIORITY[kind] or 9 end

local function findQueued(kind, ownerId)
    for i, q in ipairs(VM.queue) do
        if q.kind == kind and q.owner == ownerId then return i, q end
    end
end

local function net_broadcastState() end -- forward-declared below, after util.AddNetworkString

-- VM.Request(kind, ownerId, opts) -> token | false
--   opts.title: string shown in zc_vm_status / zc_vm_state (cosmetic only in Stage 1)
--   opts.endsAt: CurTime() deadline, if known
--   opts.allowedStates: {[0]=true, ...} - entry expires at ZB_EndRound/ZB_StartRound if the new
--     ROUND_STATE is not a key in this table. Omit to never auto-expire by state.
--   opts.noQueue: true -> refuse instead of queueing when busy (used for ULX: "the other gets a
--     chat refusal", not a silent queue entry)
function VM.Request(kind, ownerId, opts)
    opts = opts or {}
    if VM.active and VM.active.kind == kind and VM.active.owner == ownerId then
        return VM.active.token -- already holds the slot
    end
    local qi = findQueued(kind, ownerId)
    if qi then return false end -- already queued, still waiting

    if not VM.active then
        VM.nextToken = VM.nextToken + 1
        local token = "vm" .. VM.nextToken
        VM.active = { kind = kind, owner = ownerId, opts = opts, token = token, startedAt = CurTime(), allowedStates = opts.allowedStates }
        net_broadcastState()
        return token
    end

    if opts.noQueue then return false end

    VM.nextToken = VM.nextToken + 1
    local token = "vm" .. VM.nextToken
    table.insert(VM.queue, { kind = kind, owner = ownerId, opts = opts, token = token, queuedAt = CurTime(), allowedStates = opts.allowedStates })
    if zb and zb.ROUND_STATE == 3 then
        table.sort(VM.queue, function(a, b) return priorityOf(a.kind) < priorityOf(b.kind) end)
    end
    net_broadcastState()
    return false
end

function VM.Release(token)
    if not token then return false end
    if VM.active and VM.active.token == token then
        VM.active = nil
        if #VM.queue > 0 then
            local nxt = table.remove(VM.queue, 1)
            VM.active = { kind = nxt.kind, owner = nxt.owner, opts = nxt.opts, token = nxt.token, startedAt = CurTime(), allowedStates = nxt.allowedStates }
        end
        net_broadcastState()
        return true
    end
    for i, q in ipairs(VM.queue) do
        if q.token == token then
            table.remove(VM.queue, i)
            net_broadcastState()
            return true
        end
    end
    return false
end

function VM.Active() return VM.active end
function VM.Queue() return VM.queue end

local function pruneQueue()
    if not zb then return end
    local state = zb.ROUND_STATE
    for i = #VM.queue, 1, -1 do
        local q = VM.queue[i]
        if q.allowedStates and not q.allowedStates[state] then table.remove(VM.queue, i) end
    end
    if VM.active and VM.active.allowedStates and not VM.active.allowedStates[state] then
        VM.Release(VM.active.token)
    end
    if zb and zb.ROUND_STATE == 3 and #VM.queue > 1 then
        table.sort(VM.queue, function(a, b) return priorityOf(a.kind) < priorityOf(b.kind) end)
    end
end
hook.Add("ZB_EndRound", "ZCVoteManager_Prune", pruneQueue)
hook.Add("ZB_StartRound", "ZCVoteManager_Prune", pruneQueue)

-- ---------------------------------------------------------------------------------------------
-- Net: zc_vm_state, server->client, sent on change and to new joiners. Stage 2's client vote
-- manager renders this; until then it is inert (existing panels keep rendering). Content is
-- deliberately minimal in Stage 1 - kind/title/endsAt only, no per-option payload yet.
util.AddNetworkString("zc_vm_state")

local function serializeEntry(e, queued)
    return { kind = e.kind, title = (e.opts and e.opts.title) or e.kind, endsAt = (e.opts and e.opts.endsAt) or 0, queued = queued or false }
end

local function serializeState()
    local list = {}
    if VM.active then list[#list + 1] = serializeEntry(VM.active, false) end
    for _, q in ipairs(VM.queue) do list[#list + 1] = serializeEntry(q, true) end
    return list
end

net_broadcastState = function()
    if not cvVM:GetBool() then return end
    net.Start("zc_vm_state")
        net.WriteTable(serializeState())
    net.Broadcast()
end

hook.Add("PlayerInitialSpawn", "ZCVoteManager_SyncNewJoiner", function(ply)
    if not cvVM:GetBool() then return end
    timer.Simple(1, function()
        if not IsValid(ply) then return end
        net.Start("zc_vm_state")
            net.WriteTable(serializeState())
        net.Send(ply)
    end)
end)

-- ---------------------------------------------------------------------------------------------
-- Integration 1: solidmapvote. Wraps SolidMapVote.openBallot (the call that actually flips
-- M.isOpen=true), identity-checked and re-wrapped every second like zc_round_guard.lua's zb
-- wraps. Release: reconciled every Think tick below, not by editing M.reset - when solidmapvote's
-- own state shows the vote is no longer open/pending (M.reset() ran, or the ballot resolved and
-- changed level), the "map" slot is released automatically.
local function wrapMapVoteOpen()
    local M = SolidMapVote
    if not M or not isfunction(M.openBallot) then return end
    local rec = VM.wraps.mapvote_open
    if rec and rec.wrapper == M.openBallot then return end
    local original = (rec and M.openBallot == rec.wrapper) and rec.original or M.openBallot
    M.openBallot = function(...)
        if not cvVM:GetBool() then return original(...) end
        -- the final intermission's ballot (Integration 7) opens in ROUND_STATE 3 and lives there until the map changes
        local token = VM.Request("map", "solidmapvote", { title = "Map Vote", allowedStates = M.finalOpen and { [0] = true, [3] = true } or { [0] = true } })
        if not token then return false end
        return original(...)
    end
    VM.wraps.mapvote_open = { original = original, wrapper = M.openBallot }
end

local function reconcileMapVote()
    if not cvVM:GetBool() then return end
    local M = SolidMapVote
    if VM.active and VM.active.kind == "map" and VM.active.owner == "solidmapvote" then
        if not M or not M.initialized or (not M.isOpen and not M.pending) then
            VM.Release(VM.active.token)
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Integration 2: sh_mode_vote (admin_max_karma). ZC_VoteManagerGate is the global the patched
-- StartVote calls (patch/addons/admin_max_karma/lua/autorun/sh_mode_vote.lua); permissive (true)
-- when the convar is off or this file has not loaded, matching the file's existing defensive
-- `X and X()` style. Release is reconciled from ZC_MODEVOTE_ACTIVE(), defined by that same edit.
--
-- Owner rule (2026-09-23 follow-up to BRIEF_VOTES.md): the mode vote must only run in an
-- intermission where NO map vote is starting - refused outright (never queued) rather than
-- queued behind it, whenever (a) a map vote is active, (b) one is queued, or (c) solidmapvote
-- will open one at the next PreRound tick per its own SolidMapVote.mapVoteDue() (sv_mapvote.lua
-- patch copy - the single source of truth for that decision; never duplicated here). `ply` is
-- optional - sh_mode_vote.lua's StartVote has no triggering player today (it fires from
-- PlayerDeath/ZB_EndRound, not an admin command), so it is always nil in practice; the parameter
-- exists so a future caller with a real player gets the chat refusal for free.
function ZC_VoteManagerGate(kind, ply)
    if not cvVM:GetBool() then return true end
    if kind == "mode" then
        local mapActive = VM.active and VM.active.kind == "map"
        local mapQueued = findQueued("map", "solidmapvote") ~= nil
        local mapDue = SolidMapVote and isfunction(SolidMapVote.mapVoteDue) and SolidMapVote.mapVoteDue() or false
        -- Owner 2026-09-24: also the round that is ENDING now (PlayerDeath fires while ROUND_STATE is still 1): a mode
        -- vote is pointless in the round a map vote follows, and the final intermission (Integration 7) has no room for it.
        if not mapDue and SolidMapVote and isfunction(SolidMapVote.mapVoteDueAtRoundEnd) then mapDue = SolidMapVote.mapVoteDueAtRoundEnd() == true end
        if mapActive or mapQueued or mapDue then
            local why = mapActive and "a map vote is active" or mapQueued and "a map vote is queued" or "solidmapvote will open a map vote this intermission"
            print(string.format("[VoteManager] refused mode vote: %s", why))
            if IsValid(ply) then ply:ChatPrint("[VoteManager] Mode vote skipped - a map vote is happening this round instead.") end
            return false
        end
    end
    local token = VM.Request(kind, kind, { title = "Mode Vote", allowedStates = { [0] = true, [1] = true } })
    return token ~= false
end

local function reconcileModeVote()
    if not cvVM:GetBool() then return end
    if VM.active and VM.active.kind == "mode" and VM.active.owner == "mode" then
        if not (isfunction(ZC_MODEVOTE_ACTIVE) and ZC_MODEVOTE_ACTIVE()) then
            VM.Release(VM.active.token)
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Integration 3: ULX votemap2 / vote. Patches the registered ulxCommand object's .fn (see the
-- header note - reassigning the global ulx.votemap2/ulx.vote would not be seen by the already-
-- registered command). Refuses outright (opts.noQueue) rather than queueing, and chat-refuses
-- the caller, per the blueprint's acceptance line ("the other gets a chat refusal").
local ULX_TARGETS = { ["ulx votemap2"] = "Map Vote", ["ulx vote"] = "Vote" }

local function findUlxCommand(cmdName)
    if not ulx or not ulx.cmdsByCategory then return nil end
    for _, cmds in pairs(ulx.cmdsByCategory) do
        for i = 1, #cmds do
            if cmds[i].cmd == cmdName then return cmds[i] end
        end
    end
end

local function wrapUlxCommands()
    for cmdName, title in pairs(ULX_TARGETS) do
        local obj = findUlxCommand(cmdName)
        if obj and isfunction(obj.fn) then
            local rec = VM.wraps["ulx:" .. cmdName]
            if not (rec and rec.wrapper == obj.fn) then
                local original = (rec and obj.fn == rec.wrapper) and rec.original or obj.fn
                obj.fn = function(calling_ply, ...)
                    if not cvVM:GetBool() then return original(calling_ply, ...) end
                    local token = VM.Request("ulx", cmdName, { title = title, noQueue = true })
                    if not token then
                        if IsValid(calling_ply) then
                            calling_ply:ChatPrint("[VoteManager] Another vote is active; try again after it finishes.")
                        end
                        return
                    end
                    VM.wraps["ulx_active:" .. cmdName] = token
                    return original(calling_ply, ...)
                end
                VM.wraps["ulx:" .. cmdName] = { original = original, wrapper = obj.fn }
            end
        end
    end
end

-- ULX votes are fire-and-forget from here (no clean "vote closed" callback to chain without
-- editing vote.lua). Reconciled the same way as the others: ulx.voteInProgress is ULX's own
-- flag, already set/cleared by ulx.doVote/ulx.voteDone for votemap2/vote, so the "ulx" slot is
-- released the moment ULX itself reports the vote is over.
local function reconcileUlx()
    if not cvVM:GetBool() then return end
    if VM.active and VM.active.kind == "ulx" and not (ulx and ulx.voteInProgress) then
        VM.Release(VM.active.token)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Integration 6: early voting for non-viewers (work/loader/killcam_20260924/BRIEF_VOTES.md V1-V6).
-- Killcam contract (owned by the killcam builder, lua/zc_killcam/sv_highlight.lua): coded against
-- with nil-guards only - `ZCKillcam.HighlightAudience()` -> {[ply]=true}, hooks
-- `ZCKillcam_HighlightStarted(audience, expectedSeconds)`, `ZCKillcam_HighlightDone(ply)`,
-- `ZCKillcam_HighlightEnded()`. None of those names are defined yet anywhere in this tree at the
-- time this file was written (confirmed by grep of lua/zc_killcam/ and its round_v2/killcam_20260924
-- patch copies); every call site below is guarded so this whole feature is a silent no-op - same
-- as a normal killcam-absent round - until that contract lands, per the brief's own instruction.
--
-- Per-round state. `audience` is nil until known (HighlightStarted fired, or the 1s arm timer
-- decided no highlight is coming this round); while nil nothing sends. `sentMap`/`sentMode` make
-- every send idempotent per round per player (V2's requirement), keyed by player Entity.
local early = {
    audience = nil,
    sentMap = {},
    sentMode = {},
    statsEarly = 0,
    statsLate = 0,
}

local function earlyResetForRound()
    early.audience, early.sentMap, early.sentMode = nil, {}, {}
end

-- true once the player has actually gotten a ballot (native broadcast or this file), so a
-- send that arrives while it is already false is a genuine "still missing it" case for V2's
-- HighlightEnded catch-all, not a re-send of something already delivered.
local function isEarlyRecipient(ply)
    if not early.audience then return false end
    return early.audience[ply] ~= true
end

-- kind: "early" (sent ahead of/without a highlight) or "late" (sent because their own highlight
-- just finished) - purely for zc_vm_status (V6); the send itself is identical either way.
local function trySendMap(ply, kind)
    if not cvEarly:GetBool() or not IsValid(ply) then return end
    if early.sentMap[ply] then return end
    if not isEarlyRecipient(ply) then return end
    local M = SolidMapVote
    if not M or not M.isOpen or not isfunction(M.sendBallotTo) then return end
    if not M.sendBallotTo(ply) then return end
    early.sentMap[ply] = true
    if kind == "late" then early.statsLate = early.statsLate + 1 else early.statsEarly = early.statsEarly + 1 end
end

local function trySendMode(ply, kind)
    if not cvEarly:GetBool() or not IsValid(ply) then return end
    if early.sentMode[ply] then return end
    if not isEarlyRecipient(ply) then return end
    if not (isfunction(ZC_MODEVOTE_ACTIVE) and ZC_MODEVOTE_ACTIVE()) then return end
    if not isfunction(ModeVote_SendTo) then return end
    if not ModeVote_SendTo(ply) then return end
    early.sentMode[ply] = true
    if kind == "late" then early.statsLate = early.statsLate + 1 else early.statsEarly = early.statsEarly + 1 end
end

-- V1/V2: retried from every angle (armed at ZB_EndRound, HighlightStarted, the 1Hz think tick,
-- and HighlightDone/HighlightEnded below) instead of a single precise trigger - trySendMap/Mode's
-- sentMap/sentMode/isOpen/ZC_MODEVOTE_ACTIVE guards make every extra call a cheap no-op, so this
-- stays correct across whatever order the map vote, mode vote and highlight actually happen in.
local function sendEarlyToMissing(kind)
    if not cvEarly:GetBool() or not early.audience then return end
    for _, ply in ipairs(player.GetHumans()) do
        trySendMap(ply, kind)
        trySendMode(ply, kind)
    end
end

hook.Add("ZB_EndRound", "ZCVoteManager_EarlyVoteArm", function()
    if not cvEarly:GetBool() then return end
    earlyResetForRound()
    timer.Simple(1, function()
        if not cvEarly:GetBool() then return end
        -- V1: "plus everyone if no highlight starts within 1s" - an empty audience excludes
        -- nobody, so isEarlyRecipient() is true for every player.
        if not early.audience then early.audience = {} end
        sendEarlyToMissing("early")
    end)
end)

hook.Add("ZCKillcam_HighlightStarted", "ZCVoteManager_EarlyVoteAudience", function(audience, expectedSeconds)
    if not cvEarly:GetBool() then return end
    early.audience = istable(audience) and audience or {}
    sendEarlyToMissing("early")

    -- V3: the vote must not expire less than zc_vote_min_window after the highlight ends. Uses
    -- each system's own extend API (never END_TIME) and the predicted end; HighlightEnded below
    -- re-checks against the real end in case the prediction ran short.
    local seconds = tonumber(expectedSeconds)
    if not seconds or seconds < 0 then return end
    local predictedEnd, need = CurTime() + seconds, cvMinWindow:GetInt()
    local M = SolidMapVote
    if M and M.isOpen and isfunction(M.extendDeadline) and isnumber(M.endTime) then
        local shortfall = need - (M.endTime - predictedEnd)
        if shortfall > 0 then M.extendDeadline(shortfall) end
    end
    if isfunction(ZC_MODEVOTE_ACTIVE) and ZC_MODEVOTE_ACTIVE() and isfunction(ModeVote_ExtendDeadline) and isfunction(ModeVote_EndsAt) then
        local shortfall = need - (ModeVote_EndsAt() - predictedEnd)
        if shortfall > 0 then ModeVote_ExtendDeadline(shortfall) end
    end
end)

hook.Add("ZCKillcam_HighlightDone", "ZCVoteManager_EarlyVoteViewerDone", function(ply)
    if not cvEarly:GetBool() or not IsValid(ply) then return end
    -- A player whose highlight just ended is, by definition, no longer withheld - treat them as
    -- not-in-audience from here so trySendMap/Mode's isEarlyRecipient() check passes for them.
    if early.audience then early.audience[ply] = nil end
    trySendMap(ply, "late")
    trySendMode(ply, "late")
end)

hook.Add("ZCKillcam_HighlightEnded", "ZCVoteManager_EarlyVoteAllDone", function()
    if not cvEarly:GetBool() then return end
    early.audience = early.audience or {}
    local now = CurTime()
    local need = cvMinWindow:GetInt()
    local M = SolidMapVote
    if M and M.isOpen and isfunction(M.extendDeadline) and isnumber(M.endTime) then
        local shortfall = need - (M.endTime - now)
        if shortfall > 0 then M.extendDeadline(shortfall) end
    end
    if isfunction(ZC_MODEVOTE_ACTIVE) and ZC_MODEVOTE_ACTIVE() and isfunction(ModeVote_ExtendDeadline) and isfunction(ModeVote_EndsAt) then
        local shortfall = need - (ModeVote_EndsAt() - now)
        if shortfall > 0 then ModeVote_ExtendDeadline(shortfall) end
    end
    for _, ply in ipairs(player.GetHumans()) do
        if early.audience[ply] then early.audience[ply] = nil end -- everyone's highlight is over now
        trySendMap(ply, "late")
        trySendMode(ply, "late")
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Integration 7: the FINAL intermission (owner, 2026-09-24). When solidmapvote will run a map vote after this
-- round (SolidMapVote.mapVoteDue()), the intermission that follows is the last thing anyone sees on this map:
-- the mode vote and the map pre-vote are pointless, and the old flow (a 5 s intermission plus the killcam hold,
-- then the round system's transition - which RESPAWNS everyone, stopping every replay - and only then a 25 s
-- ballot on a frozen round) left no room for anything. Now, at ZB_EndRound: zb.END_TIME is pushed
-- zc_final_intermission seconds out and the ballot opens at once (sv_mapvote.lua M.openFinalBallot, in
-- ROUND_STATE 3), sized so its result and the post-vote map change land INSIDE that window. The round system
-- never leaves state 3 before the map changes, so nothing respawns or cleans up under the highlight reel
-- (sv_highlight.lua plays the whole map's reel in this intermission) or the stats. If the ballot resets instead
-- (extend won, winning map unavailable, no eligible maps) the rest of the window is cut to 5 s and the old
-- PreRound path takes over. This block only ever moves END_TIME LATER at ZB_EndRound and EARLIER on an idle
-- ballot; the killcam hold (sv_highlight.lua) and the round guard are untouched by construction.
VM.Final = VM.Final or { armed = false }
local function finalIdle()
    local M = SolidMapVote
    return not M or not M.initialized or (M.phase or "idle") == "idle"
end
-- Adversarial pass (2026-09-24, second): the old flow RESPAWNED AND FROZE everyone (PrepareReplayRound, then
-- zb:Freeze when the mode declares shouldfreeze) before its ballot. This window skips that transition, so without
-- this the survivors stood blind under the fullscreen panel, movable and shootable, with karma off (it only counts
-- ROUND_STATE 1). Freeze the living the way the mode itself asks for (same shouldfreeze gate, same zb:Freeze) and
-- release them when the window is cut short or the round moves on; nobody is respawned - the map is about to
-- change, or the ordinary transition after an "extend" does it.
local function finalFreeze(f)
    local mode = isfunction(CurrentRound) and CurrentRound() or nil
    if not (istable(mode) and mode.shouldfreeze == true and zb and isfunction(zb.Freeze)) then return false end
    zb:Freeze()
    f.frozen = true
    return true
end
local function finalRelease(f)
    if f and f.frozen and zb and isfunction(zb.Unfreeze) then zb:Unfreeze() end
    if f then f.frozen = false end
end
hook.Add("ZB_EndRound", "ZCVoteManager_FinalIntermission", function()
    finalRelease(VM.Final)
    VM.Final = { armed = false }
    local seconds = cvFinal:GetInt()
    local M = SolidMapVote
    if seconds <= 0 or not zb or zb.ROUND_STATE ~= 3 then return end
    if not M or not isfunction(M.mapVoteDue) or not isfunction(M.openFinalBallot) or not M.mapVoteDue() then return end
    zb.END_TIME = CurTime() + seconds
    local opened = M.openFinalBallot(seconds) == true
    VM.Final = { armed = true, endsAt = zb.END_TIME, opened = opened, round = zb.Roundscount, frozen = false }
    local frozen = finalFreeze(VM.Final)
    receipt(string.format("final intermission: %ds, ballot %s (round %s)%s", seconds, opened and "open" or "NOT opened", tostring(zb.Roundscount), frozen and ", players frozen" or ""))
    print(string.format("[VoteManager] final intermission: %ds, map vote %s%s", seconds, opened and "open now" or "did not open yet", frozen and ", players frozen" or ""))
end)
local function finalThink()
    local f = VM.Final
    if not f or not f.armed or not zb then return end
    if zb.ROUND_STATE ~= 3 then finalRelease(f) f.armed = false return end
    local M = SolidMapVote
    local left = isnumber(zb.END_TIME) and (zb.END_TIME - CurTime()) or 0
    if not f.opened then
        -- it did not open at round end (a mode vote decided mid-round was still running, or the vote-manager slot
        -- was still held by the forfeit vote that ended the round): keep trying while the window is worth it; past
        -- that the idle rule below hands the intermission back to the PreRound path.
        -- Adversarial pass (2026-09-24): this branch used to fall through to the idle rule on the very same tick,
        -- which cut the window 1 s after the first failed open - the retry loop never got a second attempt. While
        -- the retry window is open, a ballot that has not opened yet is not an idle ballot.
        if M and isfunction(M.openFinalBallot) and left > 15 then
            f.opened = M.openFinalBallot(left) == true
            if f.opened then print("[VoteManager] final intermission: map vote opened late") end
            return
        end
    end
    if finalIdle() and left > 6 then
        zb.END_TIME = CurTime() + 5
        f.armed = false
        finalRelease(f)
        print("[VoteManager] final intermission: no map vote is running any more; the intermission ends in 5 s")
    end
end
timer.Create("ZCVoteManager_Final", 1, 0, finalThink)
hook.Add("ZB_StartRound", "ZCVoteManager_FinalReset", function() finalRelease(VM.Final) VM.Final = { armed = false } end)

-- ---------------------------------------------------------------------------------------------
-- Integration 4 + 5: forfeit / reinforcements. Both already exclude themselves and each other by
-- ROUND_STATE and phase (forfeit calls zb:EndRound; see BLUEPRINT.md S1.3). Polled, not wrapped:
-- ZCForfeitVote.State / ZCReinforcementVote.State are global tables (sv_zc_forfeit_vote.lua:7-8,
-- sv_zc_reinforcement_vote.lua:4-5) created in R.BeginRound and cleared in R.EndRound - their
-- presence is used as the busy signal instead of reaching into their ballot-deadline internals.
local function reconcileForfeitReinforcement()
    if not cvVM:GetBool() then return end
    local forfeitBusy = ZCForfeitVote and ZCForfeitVote.State ~= nil
    local reinforceBusy = ZCReinforcementVote and ZCReinforcementVote.State ~= nil

    if forfeitBusy then
        VM.Request("forfeit", "forfeit", { title = "Forfeit Vote", noQueue = true })
    elseif VM.active and VM.active.kind == "forfeit" then
        VM.Release(VM.active.token)
    end

    if reinforceBusy then
        VM.Request("reinforcement", "reinforcement", { title = "Reinforcement Vote", noQueue = true })
    elseif VM.active and VM.active.kind == "reinforcement" then
        VM.Release(VM.active.token)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Adversarial pass (2026-09-24, the "default RTV menu"): solidmapvote's sv_hooks.lua installs its round-system
-- overrides (zb.PreRound / zb.StartRTV / zb.RTVMenu replaced, COMMANDS.rtv removed) ONCE, at PostGamemodeLoaded and
-- InitPostEntity. Physgun autorefresh re-runs any edited file, and both sv_roundsystem.lua and rtv/sv_rtv.lua are
-- edited on the live box: a hot edit puts the vanilla functions back until the next map, and vanilla PreRound then
-- calls zb.StartRTV(20) EVERY think once Roundscount passes 15 (sv_roundsystem.lua:51-54) - the old ballot, the old
-- menu, and ROUND_STATE forced to 0 under whatever the killcam is showing. M.install is idempotent (it re-captures
-- whatever PreRound now is as the original), so it is re-run whenever the overrides have drifted, and counted:
-- VM.Reinstalls > 0 in zc_vm_status is the evidence that this actually happened on the box.
VM.Reinstalls = VM.Reinstalls or 0
local smvSeen = {}
local function reinstallSolidMapVote()
    local M = SolidMapVote
    if not (istable(M) and isfunction(M.install) and zb and isfunction(zb.PreRound) and isfunction(M.preRoundOverride)) then return end
    local drift = zb.PreRound ~= M.preRoundOverride
        or (smvSeen.startRTV ~= nil and zb.StartRTV ~= smvSeen.startRTV)
        or (smvSeen.rtvMenu ~= nil and zb.RTVMenu ~= smvSeen.rtvMenu)
        or (smvSeen.startRTV ~= nil and istable(COMMANDS) and COMMANDS.rtv ~= nil)
    if not drift then
        if smvSeen.startRTV == nil then smvSeen.startRTV, smvSeen.rtvMenu = zb.StartRTV, zb.RTVMenu end -- first consistent sight: remember what "installed" looks like
        return
    end
    M.install()
    smvSeen.startRTV, smvSeen.rtvMenu = zb.StartRTV, zb.RTVMenu
    VM.Reinstalls = VM.Reinstalls + 1
    receipt("solidmapvote round-system overrides re-installed (a re-included file had put the vanilla RTV back)")
    print("[VoteManager] solidmapvote's round-system overrides had drifted (vanilla RTV was back); re-installed")
end
local function ensureInstalled()
    if cvVM:GetBool() then
        wrapMapVoteOpen()
        wrapUlxCommands()
        reinstallSolidMapVote()
    end
end

local function think()
    if not cvVM:GetBool() then return end
    reconcileMapVote()
    reconcileModeVote()
    reconcileUlx()
    reconcileForfeitReinforcement()
end

-- Early voting (Integration 6) is independent of zc_vote_manager (cvVM) - it only needs its own
-- cvEarly, which sendEarlyToMissing already checks - so it gets its own unconditional 1Hz tick
-- rather than piggybacking on think(), which returns early whenever zc_vote_manager is off.
local function earlyThink() sendEarlyToMissing("early") end

hook.Add("InitPostEntity", "ZCVoteManager_Install", function()
    ensureInstalled()
    rotateBootLogOncePerMap()
    receipt(string.format("boot version=%s vote_manager=%d", VM.Version, cvVM:GetInt()))
end)
timer.Create("ZCVoteManager_Install", 1, 0, ensureInstalled)
timer.Create("ZCVoteManager_Think", 1, 0, think)
timer.Create("ZCVoteManager_EarlyThink", 1, 0, earlyThink)

cvars.AddChangeCallback("zc_vote_manager", function(_, _, new)
    ensureInstalled()
    receipt(string.format("convar zc_vote_manager changed to %s", tostring(new)))
end, "ZCVoteManager_Toggle")

if hook.GetULibTable then ensureInstalled() end

-- ---------------------------------------------------------------------------------------------
concommand.Add("zc_vm_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local function reply(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end
    reply(string.format("[VoteManager] %s enabled=%d", VM.Version, cvVM:GetInt()))
    if VM.active then
        reply(string.format("  active: kind=%s owner=%s title=%s token=%s since=%.0fs ago",
            VM.active.kind, tostring(VM.active.owner), tostring(VM.active.opts and VM.active.opts.title),
            VM.active.token, CurTime() - VM.active.startedAt))
    else
        reply("  active: none")
    end
    if #VM.queue == 0 then
        reply("  queue: empty")
    else
        for i, q in ipairs(VM.queue) do
            reply(string.format("  queue[%d]: kind=%s owner=%s title=%s waiting=%.0fs",
                i, q.kind, tostring(q.owner), tostring(q.opts and q.opts.title), CurTime() - q.queuedAt))
        end
    end
    reply(string.format("  early voting: enabled=%d min_window=%ds early_sent=%d late_sent=%d audience_known=%s",
        cvEarly:GetInt(), cvMinWindow:GetInt(), early.statsEarly, early.statsLate, tostring(early.audience ~= nil)))
    local f = VM.Final or {}
    reply(string.format("  solidmapvote overrides: installed=%s reinstalls=%d", tostring(istable(SolidMapVote) and zb and zb.PreRound == SolidMapVote.preRoundOverride), VM.Reinstalls or 0))
    reply(string.format("  final intermission: seconds=%d armed=%s ballot_opened=%s ends_in=%s map_vote_due=%s",
        cvFinal:GetInt(), tostring(f.armed == true), tostring(f.opened == true),
        f.endsAt and string.format("%.0fs", f.endsAt - CurTime()) or "-",
        tostring(SolidMapVote and isfunction(SolidMapVote.mapVoteDue) and SolidMapVote.mapVoteDue() or false)))
end)
