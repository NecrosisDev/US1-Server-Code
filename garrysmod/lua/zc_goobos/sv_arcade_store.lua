if not SERVER then return end
local A = ZCGoobArcade
local function query(text)
    local result = sql.Query(text)
    if result == false then error("Arcade database: " .. tostring(sql.LastError())) end
    return result
end
A.Query = query
A.Quote = sql.SQLStr
function A.Require(test, message) if not test then error("USER:" .. message, 0) end end
function A.Storage()
    A.Require(mysql and mysql.module == "sqlite", "Arcade needs the server's SQLite point-shop connection.")
    A.Require(sql.TableExists("hg_pointshop"), "Point shop is still loading.")
    if A.DuelStorage then A.DuelStorage() end
    if A.SpecDM then A.SpecDM.Storage() end
    if A.storageReady then return end
    query("CREATE TABLE IF NOT EXISTS zc_arcade_sessions (steamid TEXT PRIMARY KEY, revision INTEGER NOT NULL, state TEXT NOT NULL)")
    query("CREATE TABLE IF NOT EXISTS zc_arcade_rounds (id TEXT PRIMARY KEY, mode TEXT NOT NULL, status TEXT NOT NULL, winner TEXT, pools TEXT NOT NULL, created INTEGER NOT NULL)")
    -- An interrupted server cannot honestly reconstruct the previous round's winner.
    query("UPDATE zc_arcade_rounds SET status='void' WHERE status IN ('open','locked')")
    A.storageReady = true
end
function A.History(s, game, result, delta, privateOnly)
    if A.Ledger and not privateOnly then A.Ledger({game = game, result = result, players = {{id = s.account, name = s.displayName or "Player", delta = delta}}}) end
    s.history = s.history or {}
    table.insert(s.history, 1, {game = game, result = result, delta = delta, time = os.time()})
    while #s.history > 12 do table.remove(s.history) end
end
function A.Day(s)
    local day = os.date("!%Y-%m-%d")
    if s.day ~= day then s.day = day; s.wagered = 0; s.mineStarts = 0; return true end
    return false
end
function A.Wager(s, stake)
    A.Require(isnumber(stake) and stake >= 1 and stake <= 1000000 and stake == math.floor(stake), "Choose a stake from 1 to 1,000,000 ZP.") -- 2026-09-26 owner: custom bets
    s.wagered = (s.wagered or 0) + stake
end
function A.Finish(s)
    local g = s.game
    if not g or not g.done or g.paid then return 0 end
    g.paid = true
    local payout = g.payout or 0
    A.History(s, g.kind, g.result, payout - (g.stake or 0))
    return payout
end
function A.Transaction(ply, revision, mutate)
    local begun, changedCache = false, nil
    local ok, result = xpcall(function()
        A.Storage()
        A.Require(IsValid(ply) and not ply:IsBot() and ply.PS_IsReady and ply:PS_IsReady(), "Your point-shop profile is still loading.")
        local scope = A.ArcadeAudience and A.ArcadeAudience(ply) or "main"
        A.Require(scope ~= "blocked", "Arcade is isolated until SpecDM authorizes this audience.")
        local id = ply:SteamID64()
        A.Require(isstring(id) and id:match("^%d+$"), "Player account unavailable.")
        local vars = ply:GetPointshopVars()
        query("BEGIN IMMEDIATE"); begun = true
        local wallet = query("SELECT points FROM hg_pointshop WHERE steamid=" .. sql.SQLStr(id))
        local balance = wallet and tonumber(wallet[1].points)
        A.Require(balance and balance == balance and balance >= 0 and balance < 1000000000 and balance == vars.points, "Point balance is synchronizing. Try again shortly.")
        local rows = query("SELECT revision,state FROM zc_arcade_sessions WHERE steamid=" .. sql.SQLStr(id))
        local s = rows and util.JSONToTable(rows[1].state, false, true) or {version = 1, revision = 0, history = {}}
        A.Require(istable(s) and s.version == 1, "Arcade profile version needs staff attention.")
        s.revision = rows and tonumber(rows[1].revision) or 0
        -- JSON object keys must not turn mine positions into strings on readback.
        if s.game and s.game.mines then local m = {}; for k, v in pairs(s.game.mines) do m[tonumber(k)] = v end; s.game.mines = m end
        s.account = id
        if A.ArcadeName then s.displayName = A.ArcadeName(ply) end
        local newDay = A.Day(s)
        local delta, systemChanged = 0, false
        if scope == "main" and s.game and s.game.kind == "blackjack" and not s.game.done and os.time() >= s.game.expires then
            A.Blackjack(s.game, "stand"); delta = delta + A.Finish(s); systemChanged = true
        end
        local hadBet = s.bet ~= nil
        if scope == "main" and A.ReconcileBet then delta = delta + A.ReconcileBet(s) end
        systemChanged = systemChanged or (hadBet and not s.bet)
        local hadDuel = s.duel ~= nil
        if scope == "main" and A.ReconcileDuel then delta = delta + A.ReconcileDuel(s) end
        systemChanged = systemChanged or (hadDuel and not s.duel)
        local hadSpecBet = s.specBet ~= nil
        if A.SpecDM then delta = delta + A.SpecDM.Reconcile(s, scope) end
        systemChanged = systemChanged or (hadSpecBet and not s.specBet)
        local stale = revision ~= nil and (revision ~= s.revision or systemChanged)
        if mutate and not stale then delta = delta + (mutate(s, balance + delta) or 0) end
        A.Require(balance + delta >= 0 and balance + delta < 1000000000, "Insufficient points or balance limit reached.")
        if mutate and not stale or systemChanged then s.revision = s.revision + 1 end
        local json = util.TableToJSON(s)
        A.Require(isstring(json) and #json < 30000, "Arcade profile could not be saved.")
        if delta ~= 0 then query("UPDATE hg_pointshop SET points=" .. string.format("%.17g", balance + delta) .. " WHERE steamid=" .. sql.SQLStr(id)) end
        if not rows or newDay or systemChanged or (mutate and not stale) then
            query("INSERT OR REPLACE INTO zc_arcade_sessions VALUES (" .. sql.SQLStr(id) .. "," .. s.revision .. "," .. sql.SQLStr(json) .. ")")
        end
        query("COMMIT"); begun = false
        vars.points = balance + delta; changedCache = delta ~= 0
        ply.GoobArcadeDuel = s.duel
        return {state = s, balance = vars.points, stale = stale, audience = scope}
    end, function(err) return tostring(err) end)
    if begun then sql.Query("ROLLBACK") end
    if not ok then
        local friendly = result:match("USER:(.*)")
        if not friendly then ErrorNoHalt("[GoobOS Arcade] " .. result .. "\n") end
        return nil, friendly or "The database did not confirm this action. Refresh before trying again."
    end
    if changedCache and hg.Pointshop and hg.Pointshop.NET_SendPointShopVars then
        local sent, err = pcall(hg.Pointshop.NET_SendPointShopVars, hg.Pointshop, ply)
        if not sent then ErrorNoHalt("[GoobOS Arcade] Profile refresh deferred: " .. tostring(err) .. "\n") end
    end
    return result
end
