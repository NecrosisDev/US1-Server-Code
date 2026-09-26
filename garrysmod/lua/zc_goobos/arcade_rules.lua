-- Server-owned game rules. No deck, mine positions or dealer hole card go on the wire.
if not SERVER then return end
ZCGoobArcade = ZCGoobArcade or {}
local A = ZCGoobArcade
A.Stakes = {[10] = true, [20] = true, [50] = true}
function A.Total(cards)
    local total, aces = 0, 0
    for _, card in ipairs(cards) do
        local rank = (card - 1) % 13 + 1
        total = total + (rank == 1 and 11 or math.min(rank, 10))
        if rank == 1 then aces = aces + 1 end
    end
    while total > 21 and aces > 0 do total = total - 10; aces = aces - 1 end
    return total
end
function A.Deck()
    local deck = {}
    for i = 1, 52 do deck[i] = i end
    for i = 52, 2, -1 do local j = math.random(i); deck[i], deck[j] = deck[j], deck[i] end
    return deck
end
function A.Deal(stake)
    local deck = A.Deck()
    local g = {kind = "blackjack", stake = stake, deck = deck, player = {}, dealer = {}, expires = os.time() + 900}
    for _ = 1, 2 do table.insert(g.player, table.remove(deck)); table.insert(g.dealer, table.remove(deck)) end
    local p, d = A.Total(g.player), A.Total(g.dealer)
    if p == 21 or d == 21 then
        g.done = true
        g.payout = p == d and stake or (p == 21 and stake * 2.5 or 0)
        g.result = p == d and "Push" or (p == 21 and "Blackjack!" or "Dealer blackjack")
    end
    return g
end
function A.Blackjack(g, action)
    if g.done then return end
    if action == "hit" then
        table.insert(g.player, table.remove(g.deck))
        if A.Total(g.player) > 21 then g.done = true; g.payout = 0; g.result = "Bust"; return end
        if A.Total(g.player) < 21 then return end
    end
    while A.Total(g.dealer) < 17 do table.insert(g.dealer, table.remove(g.deck)) end
    local p, d = A.Total(g.player), A.Total(g.dealer)
    g.done = true
    g.payout = (d > 21 or p > d) and g.stake * 2 or (p == d and g.stake or 0)
    g.result = (d > 21 or p > d) and "You win" or (p == d and "Push" or "Dealer wins")
end
function A.Neighbors(cell)
    local x, y, out = (cell - 1) % 6, math.floor((cell - 1) / 6), {}
    for dy = -1, 1 do for dx = -1, 1 do
        local xx, yy = x + dx, y + dy
        if xx >= 0 and xx < 6 and yy >= 0 and yy < 6 and (dx ~= 0 or dy ~= 0) then out[#out + 1] = yy * 6 + xx + 1 end
    end end
    return out
end
function A.Reveal(g, cell)
    if g.done or g.shown[cell] ~= -1 then return end
    if not g.mines then
        local excluded, bag = {[cell] = true}, {}
        for _, n in ipairs(A.Neighbors(cell)) do excluded[n] = true end
        for i = 1, 36 do if not excluded[i] then bag[#bag + 1] = i end end
        g.mines = {}
        for _ = 1, 6 do g.mines[table.remove(bag, math.random(#bag))] = true end
    end
    if g.mines[cell] then
        g.done = true; g.result = "Mine hit"; g.payout = 0
        for i in pairs(g.mines) do g.shown[tonumber(i)] = 9 end
        return
    end
    local queue = {cell}
    while #queue > 0 do
        local n = table.remove(queue)
        if g.shown[n] == -1 and not g.mines[n] then
            local count, adjacent = 0, A.Neighbors(n)
            for _, near in ipairs(adjacent) do if g.mines[near] then count = count + 1 end end
            g.shown[n] = count; g.cleared = g.cleared + 1
            if count == 0 then for _, near in ipairs(adjacent) do if g.shown[near] == -1 then queue[#queue + 1] = near end end end
        end
    end
    if g.cleared == 30 then g.done = true; g.result = "Field cleared!"; g.payout = 5 end
end
function A.PublicGame(g)
    if not g then return end
    if g.kind == "mines" then
        return {kind = g.kind, id = g.id, shown = g.shown, cleared = g.cleared, done = g.done, result = g.result, payout = g.payout}
    end
    return {kind = g.kind, stake = g.stake, player = g.player, dealer = g.done and g.dealer or {g.dealer[1], 0},
        total = A.Total(g.player), dealerTotal = g.done and A.Total(g.dealer) or nil,
        done = g.done, result = g.result, payout = g.payout, expires = g.expires}
end
