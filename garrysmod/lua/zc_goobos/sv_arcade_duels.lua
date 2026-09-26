if not SERVER then return end
local A = ZCGoobArcade
local Q, S = A.Query, A.Quote
A.DuelKinds = {"Rock-Paper-Scissors", "Tic-Tac-Toe"}
function A.ArcadeName(ply)
    local name, size = {}, 0
    for char in tostring(ply:Nick()):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if not char:find("[%z\1-\31\127]") and size + #char <= 80 then name[#name + 1] = char; size = size + #char end
    end
    return table.concat(name)
end
function A.DuelStorage()
    if A.duelStorageReady then return end
    Q("CREATE TABLE IF NOT EXISTS zc_arcade_duels (id INTEGER PRIMARY KEY AUTOINCREMENT, status TEXT NOT NULL, deadline INTEGER NOT NULL, state TEXT NOT NULL)")
    Q("CREATE TABLE IF NOT EXISTS zc_arcade_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, time INTEGER NOT NULL, entry TEXT NOT NULL)")
    Q("CREATE INDEX IF NOT EXISTS zc_arcade_duel_deadlines ON zc_arcade_duels(status,deadline)")
    -- Persisted participants keep their escrow entitlement across an interrupted server.
    Q("UPDATE zc_arcade_duels SET status='interrupted' WHERE status IN ('waiting','playing')")
    A.duelStorageReady = true
end
function A.Ledger(entry)
    entry.time = os.time()
    Q("INSERT INTO zc_arcade_ledger(time,entry) VALUES (" .. entry.time .. "," .. S(util.TableToJSON(entry)) .. ")")
end
function A.PublicLedger()
    local result = {}
    for _, row in ipairs(Q("SELECT id,entry FROM zc_arcade_ledger ORDER BY id DESC LIMIT 40") or {}) do
        local entry = util.JSONToTable(row.entry, false, true)
        if entry then
            entry.id = tonumber(row.id)
            -- Keep account attribution in storage; public cards use player names.
            for _, p in ipairs(entry.players or {}) do p.id = nil end
            result[#result + 1] = entry
        end
    end
    return result
end
function A.DuelRow(id)
    local rows = Q("SELECT id,status,deadline,state FROM zc_arcade_duels WHERE id=" .. S(tostring(id)))
    if not rows then return end
    local d = util.JSONToTable(rows[1].state, false, true)
    A.Require(istable(d) and d.version == 1, "Duel needs staff attention.")
    -- A second-player-only choice/claim is a JSON object, not a dense array.
    for _, field in ipairs({"moves", "claimed"}) do
        if d[field] then
            local normalized = {}
            for key, value in pairs(d[field]) do normalized[tonumber(key)] = value end
            d[field] = normalized
        end
    end
    d.id, d.status, d.deadline = tonumber(rows[1].id), rows[1].status, tonumber(rows[1].deadline)
    return d
end
function A.SaveDuel(d)
    Q("UPDATE zc_arcade_duels SET status=" .. S(d.status) .. ",deadline=" .. d.deadline .. ",state=" .. S(util.TableToJSON(d)) .. " WHERE id=" .. d.id)
end
function A.EndDuel(d, winner, reason)
    if d.status == "finished" then return end
    d.status, d.winner, d.reason = "finished", winner, reason
    d.payouts = {winner == 0 and d.stake or winner == 1 and d.stake * 2 or 0,
        winner == 0 and d.stake or winner == 2 and d.stake * 2 or 0}
    if not d.players[2] then d.payouts = {d.stake} end
    local entries = {}
    for i, p in ipairs(d.players) do entries[i] = {id = p.id, name = p.name, delta = d.payouts[i] - d.stake} end
    A.Ledger({game = A.DuelKinds[d.kind], result = reason, players = entries, stake = d.stake, duel = d.id})
    A.SaveDuel(d)
end
function A.ExpireDuel(d)
    if d.status == "interrupted" then A.EndDuel(d, 0, "Server interrupted - stakes returned")
    elseif d.status ~= "finished" and os.time() >= d.deadline then
        if d.status == "waiting" then A.EndDuel(d, 0, "Challenge expired - stake returned")
        elseif d.kind == 2 then A.EndDuel(d, 3 - d.turn, "Turn timed out - opponent wins")
        elseif d.moves[1] and not d.moves[2] then A.EndDuel(d, 1, "Opponent did not choose in time")
        elseif d.moves[2] and not d.moves[1] then A.EndDuel(d, 2, "Opponent did not choose in time")
        else A.EndDuel(d, 0, "Neither player chose - stakes returned") end
    end
end
function A.ReconcileDuel(s)
    if not s.duel then return 0 end
    local d = A.DuelRow(s.duel)
    A.Require(d ~= nil, "Saved duel is missing; contact staff.")
    A.ExpireDuel(d)
    if d.status ~= "finished" then return 0 end
    local slot
    for i, p in ipairs(d.players) do if p.id == s.account then slot = i end end
    A.Require(slot ~= nil, "Saved duel account mismatch.")
    d.claimed = d.claimed or {}
    local payout = d.claimed[slot] and 0 or d.payouts[slot]
    if not d.claimed[slot] then
        -- This result already has one public ledger row covering both players.
        A.History(s, A.DuelKinds[d.kind], d.reason, payout - d.stake, true)
        s.lastDuel = {id = d.id, game = A.DuelKinds[d.kind], result = d.reason, delta = payout - d.stake, time = os.time()}
        d.claimed[slot] = true; A.SaveDuel(d)
    end
    s.duel = nil
    return payout
end
local function slotOf(d, id)
    for i, p in ipairs(d.players) do if p.id == id then return i end end
end
function A.DuelAction(s, balance, op, id, revision, value, kind, enabled)
    if op == 1 or op == 2 then
        A.Require(enabled, "Arcade is closed by the server.")
        A.Require(not s.duel, "Finish your current duel first.")
    end
    if op == 1 then
        A.Require(A.DuelKinds[kind] ~= nil, "Choose a listed game.")
        A.Require(os.time() >= (s.nextDuel or 0), "Wait a few seconds before another challenge.")
        A.Require(balance >= value, "Not enough ZPoints."); A.Wager(s, value)
        local d = {version = 1, kind = kind, stake = value, revision = 0, players = {{id = s.account, name = s.displayName}}, status = "waiting", deadline = os.time() + 120}
        Q("INSERT INTO zc_arcade_duels(status,deadline,state) VALUES ('waiting'," .. d.deadline .. "," .. S(util.TableToJSON(d)) .. ")")
        local row = Q("SELECT last_insert_rowid() AS id")
        s.duel, s.nextDuel = tonumber(row[1].id), os.time() + 5
        return -value
    end
    local d = A.DuelRow(id)
    A.Require(d ~= nil, "This challenge no longer exists.")
    A.Require(d.revision == revision and d.status ~= "finished" and d.status ~= "interrupted" and os.time() < d.deadline, "Game changed or timed out. Refresh before playing.")
    local slot = slotOf(d, s.account)
    if op == 2 then
        A.Require(d.status == "waiting" and not slot, "Challenge already taken or belongs to you.")
        A.Require(value == d.stake, "Stake changed. Review the challenge again.")
        A.Require(balance >= d.stake, "Not enough ZPoints."); A.Wager(s, d.stake)
        d.players[2] = {id = s.account, name = s.displayName}
        d.status, d.deadline, d.turn = "playing", os.time() + 90, math.random(1, 2)
        d.board, d.moves, d.score, d.round = {0,0,0,0,0,0,0,0,0}, {}, {0,0}, 1
        d.revision = d.revision + 1; s.duel = d.id; A.SaveDuel(d)
        return -d.stake
    end
    A.Require(slot ~= nil and s.duel == d.id, "You are not playing this duel.")
    if op == 3 then
        A.Require(d.status == "waiting", "Accepted games cannot be canceled.")
        A.EndDuel(d, 0, "Challenge canceled - stake returned")
    elseif op == 5 then
        A.Require(d.status == "playing", "No active game to concede.")
        A.EndDuel(d, 3 - slot, "Conceded - opponent wins")
    elseif op == 4 then
        A.Require(d.status == "playing", "Wait for another player to accept.")
        if d.kind == 1 then
            A.Require(value >= 1 and value <= 3 and value == math.floor(value), "Choose rock, paper or scissors.")
            A.Require(not d.moves[slot], "Your choice is already locked.")
            d.moves[slot] = value
            if d.moves[1] and d.moves[2] then
                local winner = d.moves[1] == d.moves[2] and 0 or ((d.moves[1] - d.moves[2]) % 3 == 1 and 1 or 2)
                d.last = {d.moves[1], d.moves[2], winner}
                if winner ~= 0 then d.score[winner] = d.score[winner] + 1 end
                d.moves = {}; d.round = d.round + 1; d.revision = d.revision + 1; d.deadline = os.time() + 90
                if d.score[1] == 2 or d.score[2] == 2 or d.round > 9 then
                    winner = d.score[1] == d.score[2] and 0 or (d.score[1] > d.score[2] and 1 or 2)
                    A.EndDuel(d, winner, winner == 0 and "Match drawn - stakes returned" or "Rock-Paper-Scissors match won")
                end
            end
        else
            A.Require(slot == d.turn, "Wait for your turn.")
            A.Require(value >= 1 and value <= 9 and value == math.floor(value) and d.board[value] == 0, "Choose an empty square.")
            d.board[value] = slot; d.turn = 3 - slot; d.revision = d.revision + 1; d.deadline = os.time() + 90
            local won = false
            for _, line in ipairs({{1,2,3},{4,5,6},{7,8,9},{1,4,7},{2,5,8},{3,6,9},{1,5,9},{3,5,7}}) do
                if d.board[line[1]] == slot and d.board[line[2]] == slot and d.board[line[3]] == slot then won = true end
            end
            local full = true; for _, cell in ipairs(d.board) do if cell == 0 then full = false end end
            if won or full then A.EndDuel(d, won and slot or 0, won and "Three in a row - match won" or "Board drawn - stakes returned") end
        end
        A.SaveDuel(d)
    else A.Require(false, "Unknown duel action.") end
    return A.ReconcileDuel(s)
end
function A.PublicDuel(d, id)
    if not d then return end
    local slot = slotOf(d, id)
    return {id = d.id, kind = d.kind, stake = d.stake, revision = d.revision, status = d.status,
        remaining = math.max(0, d.deadline - os.time()), players = d.players, slot = slot,
        board = d.board, turn = d.turn, score = d.score, round = d.round, last = d.last,
        locked = slot and d.moves and d.moves[slot] ~= nil or false}
end
function A.DuelView(s)
    local lobby = {}
    for _, row in ipairs(Q("SELECT id FROM zc_arcade_duels WHERE status='waiting' AND deadline>" .. os.time() .. " ORDER BY id DESC LIMIT 16") or {}) do
        lobby[#lobby + 1] = A.PublicDuel(A.DuelRow(row.id), s.account)
    end
    return {current = s.duel and A.PublicDuel(A.DuelRow(s.duel), s.account), lobby = lobby, recent = s.lastDuel}
end
-- Resolve elapsed games even if both players disconnected. Wallet credits stay
-- durable and are claimed exactly once on the next loaded profile transaction.
function A.DuelSweep()
    A.Storage()
    local begun = false
    local ok, err = pcall(function()
        Q("BEGIN IMMEDIATE"); begun = true
        for _, row in ipairs(Q("SELECT id FROM zc_arcade_duels WHERE status='interrupted' OR (status IN ('waiting','playing') AND deadline<=" .. os.time() .. ")") or {}) do
            A.ExpireDuel(A.DuelRow(row.id))
        end
        Q("COMMIT"); begun = false
    end)
    if begun then sql.Query("ROLLBACK") end
    if not ok then error(err) end
end
