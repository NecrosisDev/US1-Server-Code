if not SERVER then return end
local A = ZCGoobArcade
-- Keys are the mode owner's result IDs, not client team numbers or guessed labels.
A.Markets = {
    tdm = {kind = "teams", options = {{id = "0", name = "Terrorists"}, {id = "1", name = "Counter-Terrorists"}}},
    cstrike = {kind = "native", options = {{id = "0", name = "Terrorists"}, {id = "1", name = "Counter-Terrorists"}}},
    gwars = {kind = "teams", options = {{id = "0", name = "Bloodz"}, {id = "1", name = "Groove"}}},
    criresp = {kind = "teams", options = {{id = "1", name = "Response team"}, {id = "2", name = "Criminals"}}},
    riot = {kind = "teams", options = {{id = "1", name = "Rioters"}, {id = "2", name = "Law enforcement"}}},
    uncontainedriot = {kind = "teams", options = {{id = "1", name = "Law enforcement"}, {id = "2", name = "Rioters"}}},
    hmcd = {kind = "teams", options = {{id = "0", name = "Innocents"}, {id = "1", name = "Traitors"}}},
    fear = {kind = "teams", options = {{id = "0", name = "Innocents"}, {id = "1", name = "Traitors"}}},
    activeshooter = {kind = "teams", options = {{id = "0", name = "Bystanders / response"}, {id = "1", name = "Shooter"}}},
    masscasualty = {kind = "teams", options = {{id = "0", name = "Bystanders / response"}, {id = "1", name = "Shooters"}}},
    hl2dm = {kind = "count", options = {{id = "0", name = "Rebels"}, {id = "1", name = "Combine"}}},
    wildcard = {kind = "count", options = {{id = "0", name = "Blue team"}, {id = "1", name = "Red team"}}},
    shitterhunt = {kind = "hunt", options = {{id = "hunters", name = "Hunters"}, {id = "shitters", name = "Shitters"}}},
    defense = {kind = "defense", options = {{id = "defenders", name = "Defenders clear every wave"}, {id = "attackers", name = "Defenders eliminated"}}}
}
A.Unavailable = {
    dm = "Solo deathmatch has no team winner.", superfighters = "Superfighters has an individual winner.",
    scugarena = "Scug Arena has an individual winner.", event = "Event results have no stable team contract.",
    mayhem = "Mayhem has an individual winner.", coop = "Co-op ends through lives and map transitions, not opposing team victories.",
    pathowogen = "Pathowogen can award several independent extraction outcomes; no single team winner."
}
function A.Mode()
    if not CurrentRound or not zb then return end
    local mode = CurrentRound()
    if not mode then return end
    return mode, tostring(zb.CROUND or mode.name), A.Markets[mode.name]
end
function A.RoundRow(id)
    local rows = A.Query("SELECT * FROM zc_arcade_rounds WHERE id=" .. A.Quote(id))
    return rows and rows[1]
end
function A.VoidMarket()
    if A.market then A.Query("UPDATE zc_arcade_rounds SET status='void' WHERE id=" .. A.Quote(A.market.id) .. " AND status IN ('open','locked')") end
    A.market = nil
end
function A.MarketThink()
    if not zb or not CurrentRound or not mysql or mysql.module ~= "sqlite" or not sql.TableExists("hg_pointshop") then return end
    A.Storage()
    local mode, variant, spec = A.Mode()
    if not mode then return end
    if A.market and (A.market.mode ~= mode.name or A.market.variant ~= variant) then A.VoidMarket() end
    if zb.ROUND_STATE == 0 then
        if A.lastRoundState ~= 0 or (A.market and A.market.closed) then A.VoidMarket() end
        if not A.market and spec then
            local id = util.SHA256(tostring(os.time()) .. ":" .. tostring(SysTime()) .. ":" .. tostring(math.random())):sub(1, 32)
            A.Query("INSERT INTO zc_arcade_rounds VALUES (" .. A.Quote(id) .. "," .. A.Quote(mode.name) .. ",'open',NULL,'{}'," .. os.time() .. ")")
            A.market = {id = id, mode = mode.name, variant = variant, title = mode.PrintName or mode.name, options = table.Copy(spec.options)}
        end
    elseif zb.ROUND_STATE == 1 and A.market then
        A.Query("UPDATE zc_arcade_rounds SET status='locked' WHERE id=" .. A.Quote(A.market.id) .. " AND status='open'")
        A.market.started = true
    elseif zb.ROUND_STATE == 3 and A.market and not A.market.closed then
        A.CloseMarket()
    end
    A.lastRoundState = zb.ROUND_STATE
end
function A.PublicMarket()
    local mode, variant = A.Mode()
    if not mode then return {reason = "Waiting for the next round."} end
    if not A.market or A.market.mode ~= mode.name or A.market.variant ~= variant then
        return {title = mode.PrintName or mode.name, reason = A.Unavailable[mode.name] or "Next market opens during intermission."}
    end
    local row = A.RoundRow(A.market.id)
    if not row then return {reason = "Market unavailable."} end
    local pools = util.JSONToTable(row.pools, false, true) or {}
    local total = 0; for _, value in pairs(pools) do total = total + value end
    local out = table.Copy(A.market)
    out.pools, out.total, out.status = pools, total, row.status
    out.remaining = math.max(0, (zb.START_TIME or CurTime()) - CurTime())
    out.open = row.status == "open" and zb.ROUND_STATE == 0 and (not zb.START_TIME or CurTime() < zb.START_TIME)
    return out
end
function A.PlaceBet(s, stake, option, marketID)
    A.Require(not s.bet, "You already have a match ticket awaiting settlement.")
    local market = A.PublicMarket()
    A.Require(market.open and market.id == marketID, "This market has closed or changed. Refresh first.")
    local chosen = market.options[option]
    A.Require(chosen ~= nil, "Choose a listed outcome.")
    A.Wager(s, stake)
    local row = A.RoundRow(market.id)
    local pools = util.JSONToTable(row.pools, false, true) or {}
    pools[chosen.id] = (pools[chosen.id] or 0) + stake
    A.Query("UPDATE zc_arcade_rounds SET pools=" .. A.Quote(util.TableToJSON(pools)) .. " WHERE id=" .. A.Quote(market.id))
    s.bet = {round = market.id, mode = market.title, choice = chosen.id, label = chosen.name, stake = stake}
    return -stake
end
function A.ReconcileBet(s)
    local b = s.bet
    if not b then return 0 end
    local row = A.RoundRow(b.round)
    if row and (row.status == "open" or row.status == "locked") then return 0 end
    local pools = row and util.JSONToTable(row.pools, false, true) or {}
    local total, sides = 0, 0
    for _, value in pairs(pools) do total = total + value; if value > 0 then sides = sides + 1 end end
    local payout, reason = 0, "Lost"
    if not row or row.status == "void" or sides < 2 or not pools[row.winner] then
        payout, reason = b.stake, "Voided · stake returned"
    elseif b.choice == row.winner then
        payout = math.floor(b.stake * total / pools[b.choice])
        reason = "Winning ticket"
    end
    A.History(s, "Match · " .. b.mode .. " · " .. b.label, reason, payout - b.stake)
    s.bet = nil
    return payout
end
-- Called before the mode's EndRound cleanup. Never calls ShouldRoundEnd (it has side effects).
function A.CaptureOutcome(mode)
    if not A.market or not A.market.started or mode.name ~= A.market.mode then return end
    local spec = A.Markets[mode.name]
    local winner
    if spec.kind == "teams" then
        local ended, value = zb:CheckWinner(mode:CheckAlivePlayers())
        if ended then winner = tostring(value) end
    elseif spec.kind == "count" then
        local counts = {[0] = 0, [1] = 0}
        for _, p in ipairs(player.GetAll()) do if p:Alive() and counts[p:Team()] then counts[p:Team()] = counts[p:Team()] + 1 end end
        winner = counts[0] > counts[1] and "0" or (counts[1] > counts[0] and "1" or nil)
    elseif spec.kind == "hunt" then
        local result = mode:HuntOutcome()
        if result == "Hunters win! All Shitters are out." then winner = "hunters"
        elseif result == "Shitter team wins! No hunters remain." or result == "Shitter team wins by surviving the hunt!" then winner = "shitters" end
    elseif spec.kind == "defense" then
        if mode.VoteInProgress then return end
        if #zb:CheckAlive(true) == 0 then
            for _, p in ipairs(player.GetAll()) do if p.HasVoted ~= nil then return end end
            winner = "attackers"
        elseif mode.WaveCompleted and mode.Wave >= mode.TotalWaves then winner = "defenders" end
    end
    A.market.winner = winner
end
-- Counter-Strike supplies the actual local result after bomb/hostage rules resolve.
function A.NativeOutcome(mode, winner)
    if A.market and A.market.started and A.market.mode == mode.name and mode.name == "cstrike" then A.market.winner = tostring(winner) end
end
function A.SafeCapture(mode)
    if A.market then A.market.winner = nil end
    local ok, err = pcall(A.CaptureOutcome, mode)
    if not ok then ErrorNoHalt("[GoobOS Arcade] Unresolved round; tickets will be voided: " .. tostring(err) .. "\n") end
end
function A.CloseMarket()
    if not A.market then return end
    local valid = false
    for _, option in ipairs(A.market.options) do if option.id == A.market.winner then valid = true end end
    A.Query("UPDATE zc_arcade_rounds SET status=" .. A.Quote(valid and "finished" or "void") .. ",winner=" .. A.Quote(A.market.winner or "") .. " WHERE id=" .. A.Quote(A.market.id) .. " AND status IN ('open','locked')")
    A.market.closed = true
    for _, p in ipairs(player.GetHumans()) do
        if (not A.ArcadeMain or A.ArcadeMain(p)) and p.PS_IsReady and p:PS_IsReady() then A.Transaction(p) end
    end
end
hook.Add("ZB_StartRound", "GoobOS.Arcade.Lock", function() if A.market then A.MarketThink() end end)
hook.Add("ZB_EndRound", "GoobOS.Arcade.Settle", function()
    local ok, err = pcall(A.CloseMarket)
    if not ok then ErrorNoHalt("[GoobOS Arcade] Settlement deferred: " .. tostring(err) .. "\n") end
end)
