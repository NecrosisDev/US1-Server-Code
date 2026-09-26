-- ZCity repair 1.0.1. Original interface by Solid Map Vote / octavu.
local M = SolidMapVote
local function cfg(key) return M.Config[key] end
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
function M.number(key, fallback, low, high)
    local n = tonumber(cfg(key))
    return math.Clamp(finite(n) and n or fallback, low, high)
end
function M.humans() return player.GetHumans() end
function M.playerHasVoted(id) return M.votes[id] end
function M.playerHasNominated(id) return M.nominations[id] end
function M.playerHasRTVed(id) return M.RTVs[id] == true end
function M.getRTVAmount() return math.max(1, math.ceil(#M.humans() * M.number("RTV Percentage", 0.6, 0.01, 1))) end
function M.isAllowed(map)
    if type(map) ~= "string" or #map > 128 or not map:match("^[%w_%.%-]+$") then return false end
    local lower = string.lower(map)
    for blocked, enabled in pairs(cfg("Map Blacklist") or {}) do
        if enabled and string.lower(blocked) == lower then return false end
    end
    local prefix = lower:match("^([^_]+)_")
    return not prefix or (cfg("Allowed Prefixes") or {})[prefix] == true
end
function M.poolMaps()
    local installed, seen, pool = {}, {}, {}
    for _, filename in ipairs(file.Find("maps/*.bsp", "GAME") or {}) do
        local name = filename:sub(1, -5)
        if M.isAllowed(name) then installed[string.lower(name)] = name end
    end
    M.installed = installed
    local candidates = cfg("Manual Map Pool") and cfg("Map Pool") or installed
    for _, name in pairs(type(candidates) == "table" and candidates or {}) do
        local real = type(name) == "string" and installed[string.lower(name)]
        if real and string.lower(real) ~= string.lower(game.GetMap()) and not seen[real] then
            seen[real] = true
            pool[#pool + 1] = real
        end
    end
    table.sort(pool)
    while #pool > 10000 do seen[table.remove(pool)] = nil end
    M.mapPool, M.poolSet = pool, seen
    M.poolVersion = ((M.poolVersion or 0) + 1) % 65536
    for id, map in pairs(M.nominations or {}) do if not seen[map] then M.nominations[id] = nil end end
    return pool
end
function M.selectMaps(exclude,ignoreNominations)
    exclude=exclude or {}
    local selected, taken, remaining = {}, {}, {}
    local limit = math.floor(M.number("Map Limit", 6, 1, 6))
    local ids = {}
    for id in pairs(ignoreNominations and {} or M.nominations) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local name = M.nominations[id]
        if #selected < limit and M.poolSet[name] and not taken[name] and not exclude[name] then
            selected[#selected + 1] = name; taken[name] = true
        end
    end
    for _, name in ipairs(M.mapPool) do if not taken[name] and not exclude[name] then remaining[#remaining + 1] = name end end
    -- Remove a candidate each iteration; duplicates or uneven weights cannot stall a tick.
    while #selected < limit and #remaining > 0 do
        local total, weights = 0, {}
        for i, name in ipairs(remaining) do
            local count = tonumber(M.mapPlayCounts[name]) or 1
            if not finite(count) or count < 1 then count = 1 end
            weights[i] = cfg("Fair Map Recycling") and 1 / math.min(count, 1000000) or 1
            total = total + weights[i]
        end
        local pick, index = math.random() * total, #remaining
        for i, weight in ipairs(weights) do pick = pick - weight; if pick <= 0 then index = i; break end end
        selected[#selected + 1] = table.remove(remaining, index)
    end
    M.maps, M.ballotSet = selected, {}
    for _, name in ipairs(selected) do M.ballotSet[name] = true end
    if cfg("Enable Extend") and M.isAllowed(game.GetMap()) then M.ballotSet.extend = true end
    if cfg("Enable Random") and #M.mapPool > 0 then M.ballotSet.random = true end
    return selected
end
function M.createWeightedPool(pool, weights)
    local out = {}
    for _, name in ipairs(pool) do out[name] = tonumber(weights[name]) or 0 end
    return out
end
function M.initFairMapRecycling()
    M.mapPlayCounts = {}
    if not sql.TableExists("solid_map_vote_data") then
        sql.Query("CREATE TABLE solid_map_vote_data (Map TEXT, PlayCount INTEGER)")
    end
    local name = sql.SQLStr(game.GetMap())
    local rows = sql.Query("SELECT PlayCount FROM solid_map_vote_data WHERE Map=" .. name)
    if rows == false then ErrorNoHalt("[SolidMapVote] Cannot read map history; using equal weights.\n"); return end
    if rows then
        local count = math.max(0, tonumber(rows[1].PlayCount) or 0) + 1
        sql.Query("UPDATE solid_map_vote_data SET PlayCount=" .. tostring(math.min(count, 1000000)) .. " WHERE Map=" .. name)
    else
        sql.Query("INSERT INTO solid_map_vote_data (Map, PlayCount) VALUES (" .. name .. ",1)")
    end
    for _, row in ipairs(sql.Query("SELECT Map, PlayCount FROM solid_map_vote_data") or {}) do
        M.mapPlayCounts[row.Map] = math.max(1, tonumber(row.PlayCount) or 1)
    end
end
function M.vote(id, choice)
    if M.phase ~= "voting" or RealTime() >= M.deadline or not M.ballotSet[choice] or M.votes[id] == choice then return false end
    M.votes[id] = choice; M.sendVotes(true); return true
end
function M.nominate(id, choice)
    if M.isOpen or not cfg("Allow Nominations") or not M.poolSet[choice] or M.nominations[id] == choice then return false end
    for other, map in pairs(M.nominations) do if other ~= id and map == choice then return false end end
    if not M.nominations[id] and table.Count(M.nominations) >= math.min(6, #M.mapPool) then return false end
    M.nominations[id] = choice; M.sendNominations(true); return true
end
function M.getWinningMaps()
    local counts, highest, winners = {}, 0, {}
    for name in pairs(M.ballotSet) do counts[name] = 0 end
    for id, choice in pairs(M.votes) do
        local ply = player.GetBySteamID64(id)
        if IsValid(ply) and not ply:IsBot() and counts[choice] ~= nil then
            local power = cfg("Vote Power")(ply)
            power = finite(power) and math.Clamp(power, 1, 100) or 1
            counts[choice] = counts[choice] + power; highest = math.max(highest, counts[choice])
        end
    end
    -- No votes selects an actual map. Only extend automatically when no map is available.
    for name, count in pairs(counts) do
        if count == highest and (highest > 0 or (name ~= "extend" and name ~= "random")) then winners[#winners + 1] = name end
    end
    if #winners == 0 and M.ballotSet.extend then winners[1] = "extend" end
    table.sort(winners)
    return winners
end
function M.close()
    if M.phase ~= "voting" then return false end
    local winners = M.getWinningMaps()
    local winner = #winners > 0 and winners[math.random(#winners)] or nil
    if not winner then M.reset("No eligible maps; vote cancelled."); return false end
    local fixed = ""
    if winner == "extend" then fixed = game.GetMap()
    elseif winner == "random" then
        local pool = cfg("Random Mode") == 1 and M.maps or M.mapPool
        fixed = #pool > 0 and pool[math.random(#pool)] or ""
    end
    M.winningMaps, M.realWinner, M.fixedWinner = winners, winner, fixed
    M.phase, M.finished, M.changeTime = "results", true, RealTime() + M.number("Post Vote Length", 5, 1, 30)
    M.sendResult(true)
    return true
end
function M.reset(reason)
    M.phase, M.isOpen, M.finished, M.pending = "idle", false, false, false
    M.votes, M.nominations, M.RTVs = {}, {}, {}
    M.maps, M.ballotSet, M.winningMaps = {}, {}, {}
    M.rerolls=0;M.rerollRequests={};M.rerollSeen={}
    M.lengthOverride, M.ballotLength, M.finalOpen = nil, nil, nil -- final intermission (below)
    M.realWinner, M.fixedWinner = "", ""
    M.startVoteAfterRound, M.RTVCompleted, M.mapChangeTriggered = false, false, false
    M.RTVDelayEnd = RealTime() + M.number("RTV Delay", 60, 0, 3600)
    M.autoStartTime = RealTime() + M.number("Vote Autostart Delay", 3600, 30, 86400)
    M.reminded = false
    -- Rearm the automatic map vote without resetting the mode-vote grace/streak counter.
    M.roundBase = zb and (zb.Roundscount or 0) or 0
    if zb then zb.votestarted = false; zb.START_TIME = nil end
    net.Start("SolidMapVote.cancel"); net.Broadcast()
    M.sendVotes(true); M.sendNominations(true)
    if reason then M.sendMessage({color_white, reason}, true) end
end
function M.canOpen()
    if not M.initialized or not zb then return false end
    -- ROUND_STATE 0 (PreRound), or 3 while M.openFinalBallot is opening the final intermission's ballot (below)
    if zb.ROUND_STATE ~= 0 and not (M.finalOpen and zb.ROUND_STATE == 3) then return false end
    if zb.RoundsLeft and zb.CROUND == "cstrike" then return false end
    if ZC_MODEVOTE_ACTIVE and ZC_MODEVOTE_ACTIVE() then return false end
    return true
end
-- work/loader/killcam_20260924/BRIEF_VOTES.md (owner follow-up, 2026-09-23): the single source of
-- truth for "will solidmapvote itself open a ballot at the coming PreRound tick", so
-- zc_vote_manager.lua can refuse the mode vote outright instead of duplicating this arithmetic.
-- Mirrors sv_hooks.lua's M.install/preRoundOverride decision (self.ROUND_STATE == 0 and not
-- blockedSeries and (M.pending or automatic)) - but read-only: unlike preRoundOverride, it never
-- writes M.roundBase, only reads a local, non-persisted floor for THIS answer, so calling it
-- (repeatedly, from another file, before PreRound itself runs) cannot perturb the real timer's
-- own "rounds since last vote" bookkeeping. Deliberately omits preRoundOverride's own
-- `ZC_MODEVOTE_ACTIVE and ZC_MODEVOTE_ACTIVE()` short-circuit - that guard exists so PreRound
-- defers to an ALREADY-open mode ballot, which is a fact about mode vote, not about whether
-- solidmapvote itself would open; answering that here would make this predicate lie the moment a
-- mode vote is (or was) active, exactly the case its caller needs a straight answer for.
--
-- Adversarial review fix (2026-09-23): sh_mode_vote.lua's StartVote (and thus
-- ZC_VoteManagerGate("mode")) runs 0.3-0.5s after hook.Run("ZB_EndRound") - zb:EndRound
-- (sv_roundsystem.lua) sets zb.ROUND_STATE = 3 and increments zb.Roundscount BEFORE running that
-- hook, and ROUND_STATE only becomes 0 later (EndRoundThink + PrepareReplayRound). A caller during
-- that 3-then-0 window must see the SAME answer PreRound will compute once ROUND_STATE actually
-- reaches 0 - Roundscount/roundBase/CROUND do not change across that gap, only ROUND_STATE does -
-- so this accepts 3 as well as 0, not just 0.
function M.mapVoteDue()
    if not M.initialized or not zb then return false end
    if M.isOpen or M.pending then return true end
    if zb.ROUND_STATE ~= 0 and zb.ROUND_STATE ~= 3 then return false end
    if zb.RoundsLeft and zb.CROUND == "cstrike" then return false end -- blockedSeries, sv_hooks.lua's preRoundOverride
    local count = zb.Roundscount or 0
    local base = count < M.roundBase and count or M.roundBase
    return count - base >= math.floor(M.number("Rounds Per Vote", 16, 1, 1000)) and not GetConVar("zb_dev"):GetBool()
end
-- Owner 2026-09-24: the same answer DURING a round (ROUND_STATE 1) for the round that is now ending - zb:EndRound
-- increments Roundscount, so the count is one short here. sh_mode_vote starts its vote from PlayerDeath while the
-- state is still 1; zc_vote_manager's gate asks this so no mode vote starts in the round a map vote will follow.
function M.mapVoteDueAtRoundEnd()
    if not M.initialized or not zb then return false end
    if M.isOpen or M.pending then return true end
    if zb.ROUND_STATE ~= 1 then return M.mapVoteDue() end
    if zb.RoundsLeft and zb.CROUND == "cstrike" then return false end
    local count = (zb.Roundscount or 0) + 1
    local base = count < M.roundBase and count or M.roundBase
    return count - base >= math.floor(M.number("Rounds Per Vote", 16, 1, 1000)) and not GetConVar("zb_dev"):GetBool()
end
-- Owner 2026-09-24: the FINAL intermission. zc_vote_manager.lua (Integration 7) pushes zb.END_TIME `seconds` out at
-- ZB_EndRound and opens the ballot right then, in ROUND_STATE 3, sized so the result and the post-vote map change
-- land inside that window (Post Vote Length + a 3 s margin before END_TIME). Everything else about the ballot -
-- reroll, extend, nominations, the PreRound hold if the window somehow runs out first - is the ordinary path.
function M.openFinalBallot(seconds)
    if M.isOpen then return true end
    seconds = tonumber(seconds) or 0
    local post = M.number("Post Vote Length", 5, 1, 30)
    M.finalOpen = true
    M.lengthOverride = math.Clamp(math.floor(seconds - post - 3), 10, 300)
    local ok = M.openBallot()
    M.finalOpen = nil
    if not ok then M.lengthOverride = nil end
    return ok == true
end
function M.openBallot()
    if M.isOpen or not M.canOpen() then return false end
    M.poolMaps(); M.selectMaps()
    if not next(M.ballotSet) then M.reset("No eligible maps; vote cancelled."); return false end
    M.votes, M.pending = {}, false
    M.rerolls=0;M.rerollSeen={};M.beginBallotRevision()
    M.phase, M.isOpen, M.finished = "voting", true, false
    M.startVoteAfterRound, M.RTVCompleted = false, true
    M.startTime = CurTime()
    M.ballotLength = M.lengthOverride or M.number("Length", 25, 5, 120) -- sv_net.lua sendStart tells clients this length
    M.deadline = RealTime() + M.ballotLength
    M.endTime = CurTime() + (M.deadline - RealTime())
    zb.votestarted = true
    M.sendStart(true); M.sendPlayCounts(M.createWeightedPool(M.maps, M.mapPlayCounts), true)
    M.sendVotes(true); M.sendNominations(true)
    return true
end
-- work/loader/killcam_20260924/BRIEF_VOTES.md V3: extend the ballot's own deadline (M.deadline,
-- RealTime()-based; M.endTime, its CurTime() mirror sent to clients) so a vote never expires
-- before viewers get a fair window after the killcam highlight ends. Never touches zb.END_TIME -
-- that belongs to the round system, not this vote.
-- Adversarial review fix (2026-09-23): was M.sendStart(true), which re-broadcasts the FULL ballot
-- (maps/length/reroll state) to every client - cl_net.lua treats any "SolidMapVote.start" as a
-- brand-new ballot, resetting its reroll/vote caches and, via the V5 defer wrapper, re-opening
-- the panel out from under someone already voting. sv_net.lua's M.sendDeadline sends only the
-- new deadline instead; a client who has not opened the panel yet still gets a normal
-- "SolidMapVote.start" the first time M.sendStart/M.sendBallotTo reaches them.
function M.extendDeadline(extra)
    if M.phase ~= "voting" or not isnumber(extra) or extra <= 0 then return false end
    extra = math.min(extra, 60)
    M.deadline = M.deadline + extra
    M.endTime = M.endTime + extra
    M.sendDeadline(true)
    return true
end
-- All entry paths queue until a safe intermission, including administrator force RTV.
function M.start()
    if not M.initialized or M.isOpen or M.pending then return false end
    M.pending, M.startVoteAfterRound, M.RTVCompleted = true, true, true
    return true
end
function M.checkForRTV()
    if M.initialized and not M.pending and not M.isOpen and table.Count(M.RTVs) >= M.getRTVAmount() and #M.humans() > 0 then
        M.start(); M.sendMessage({color_white, "The map vote will open after the current round."}, true)
    end
end
function M.checkForVoteEnd()
    if M.phase == "voting" and RealTime() >= M.deadline then M.close() end
end
function M.postMapVoteChange()
    if M.phase ~= "results" or RealTime() < M.changeTime or M.mapChangeTriggered then return end
    if M.realWinner == "extend" then M.reset("The map has been extended."); return end
    local target = M.realWinner == "random" and M.fixedWinner or M.realWinner
    -- Re-read installed/allowed names immediately before the consequential command.
    M.poolMaps()
    if not M.poolSet[target] or not M.isAllowed(target) then M.reset("Winning map is unavailable; vote cancelled."); return end
    M.mapChangeTriggered = true
    M.changeRequested = RealTime()
    RunConsoleCommand("changelevel", target)
end
function M.checkForAutostart()
    if not cfg("Enable Vote Autostart") or M.isOpen or M.pending then return end
    local remaining = M.autoStartTime - RealTime()
    if remaining <= 0 then M.start()
    elseif not M.reminded and remaining <= M.number("Autostart Reminder", 180, 0, 86400) then
        M.reminded = true
        M.sendMessage({color_white, "A map vote will be queued in " .. math.ceil(remaining) .. " seconds, then open between rounds."}, true)
    end
end
