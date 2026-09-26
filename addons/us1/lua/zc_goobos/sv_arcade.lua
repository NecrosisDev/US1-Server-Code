if not SERVER then return end
local A = ZCGoobArcade
local enabled = CreateConVar("zc_goobos_arcade", "1", FCVAR_ARCHIVE, "Enable GoobOS Arcade. Existing stakes still settle when disabled.")
A.Enabled = function() return enabled:GetBool() end
util.AddNetworkString("GoobOS.Arcade.Request")
util.AddNetworkString("GoobOS.Arcade.State")
function A.Action(s, balance, op, value, option, marketID)
    if op == 1 or op == 4 or op == 7 then A.Require(enabled:GetBool(), "Arcade is closed by the server.") end
    if op == 1 or op == 4 then
        A.Require(not s.game or s.game.done, "Finish your current game first.")
        A.Require(os.time() >= (s.nextGame or 0), "Please wait a few seconds before another game.")
        s.nextGame = os.time() + 5
        if op == 1 then
            A.Require(balance >= value, "Not enough ZPoints for this stake.")
            A.Wager(s, value)
            s.game = A.Deal(value)
            return -value + A.Finish(s)
        end
        A.Require((s.mineStarts or 0) < 10, "Today's ten Minesweeper challenges are used. Come back tomorrow.")
        s.mineStarts = (s.mineStarts or 0) + 1
        s.game = {kind = "mines", id = tostring(os.time()) .. ":" .. s.mineStarts, shown = {}, cleared = 0, stake = 0}
        for i = 1, 36 do s.game.shown[i] = -1 end
    elseif op == 2 or op == 3 then
        A.Require(s.game and s.game.kind == "blackjack" and not s.game.done, "No active blackjack hand.")
        A.Blackjack(s.game, op == 2 and "hit" or "stand")
        return A.Finish(s)
    elseif op == 5 then
        A.Require(s.game and s.game.kind == "mines" and not s.game.done, "No active minefield.")
        A.Require(value >= 1 and value <= 36 and value == math.floor(value), "Invalid cell.")
        A.Reveal(s.game, value)
        return A.Finish(s)
    elseif op == 6 then
        A.Require(s.game and s.game.kind == "mines" and not s.game.done, "No active minefield.")
        s.game.done = true; s.game.result = "Challenge ended"; s.game.payout = 0
        return A.Finish(s)
    elseif op == 7 then
        A.Require(balance >= value, "Not enough ZPoints for this stake.")
        return A.PlaceBet(s, value, option, marketID)
    else A.Require(false, "Unknown action.") end
    return 0
end
function A.Send(ply, result, err)
    local scope = A.ArcadeAudience and A.ArcadeAudience(ply) or "main"
    if scope == "blocked" or (result and result.audience and result.audience ~= scope) then result = nil end
    local out = {error = err, enabled = enabled:GetBool(), scope = scope, revision = 0, balance = 0,
        wagerLeft = 0, challengesLeft = 0, history = {}, ledger = {}, ready = result ~= nil}
    if result then
        local s = result.state
        out.revision, out.balance, out.wagerLeft = s.revision, result.balance, 999999999 -- 2026-09-26 owner: no daily wager limit
        if scope == "main" then
            out.game, out.bet = A.PublicGame(s.game), s.bet
            if A.DuelView then out.duels = A.DuelView(s); out.ledger = A.PublicLedger() end
            out.history, out.challengesLeft = s.history, 10 - (s.mineStarts or 0)
            local ok, market = pcall(A.PublicMarket)
            out.market = ok and market or {reason = "Market is synchronizing. Refresh shortly."}
            out.specdmNotice = "SpecDM: betting integration is being prepared; its endless game has no round winner."
        elseif scope ~= "blocked" and A.SpecDM then
            out.bet = s.specBet and s.specBet.scope == scope and s.specBet or nil
            out.market = A.SpecDM.View(ply, scope); out.ledger = A.SpecDM.Ledger(scope)
            for _, row in ipairs(s.specHistory or {}) do if row.scope == scope then out.history[#out.history + 1] = row end end
            out.enabled = enabled:GetBool() and A.SpecDM.Ready()
        end
        if result.stale then out.error = "Your screen was refreshed. No repeated action was charged." end
    else out.enabled = false; out.market = {title = "Arcade", reason = err or "Refresh to load your current audience."} end
    net.Start("GoobOS.Arcade.State")
    net.WriteString(util.TableToJSON(out))
    net.Send(ply)
end
net.Receive("GoobOS.Arcade.Request", function(bits, ply)
    if bits < 53 or bits > 341 or not IsValid(ply) or ply:IsBot() then return end
    local now = RealTime()
    if now < (ply.GoobArcadeNext or 0) then return end
    ply.GoobArcadeNext = now + 0.15
    local op = net.ReadUInt(3)
    local revision = net.ReadUInt(32)
    local value = net.ReadUInt(7)
    local option = net.ReadUInt(3)
    local marketID = net.ReadString()
    if #marketID > 32 then return end
    -- 2026-09-26 custom bets: newer clients append the full stake (32 bits); older ones end here.
    if bits - (45 + (#marketID + 1) * 8) >= 32 then local wide = net.ReadUInt(32); if wide > 0 and (op == 1 or op == 7) then value = wide end end
    local result, err = A.Transaction(ply, op ~= 0 and revision or nil, op ~= 0 and function(s, balance)
        if A.ArcadeMain and not A.ArcadeMain(ply) then
            A.Require(op == 7 and A.SpecDM ~= nil, "Only the isolated SpecDM market is available in this world.")
            return A.SpecDM.Place(ply, s, balance, value, option, marketID)
        end
        return A.Action(s, balance, op, value, option, marketID)
    end or nil)
    A.Send(ply, result, err)
end)
local nextThink = 0
hook.Add("Think", "GoobOS.Arcade.Markets", function()
    if RealTime() < nextThink then return end
    nextThink = RealTime() + 1
    local ok, err = pcall(function() A.MarketThink(); if A.SpecDM then A.SpecDM.Sweep() end end)
    if not ok then nextThink = RealTime() + 30; ErrorNoHalt("[GoobOS Arcade] " .. tostring(err) .. "\n") end
end)
-- Resolve offline tickets on the next loaded profile; app refresh resolves them too.
hook.Add("PS_PlayerLoaded", "GoobOS.Arcade.Resume", function(ply)
    if not A.storageReady then return end
    A.Transaction(ply)
end)
