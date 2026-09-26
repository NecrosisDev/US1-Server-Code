if not SERVER then return end
local A = ZCGoobArcade
util.AddNetworkString("GoobOS.Arcade.Duel")
util.AddNetworkString("GoobOS.Arcade.Ledger")
net.Receive("GoobOS.Arcade.Duel", function(bits, ply)
    if bits < 84 or bits > 244 or not IsValid(ply) or ply:IsBot() then return end
    if RealTime() < (ply.GoobArcadeNext or 0) then return end
    ply.GoobArcadeNext = RealTime() + 0.15
    local op, revision = net.ReadUInt(3), net.ReadUInt(32)
    local id, duelRevision = net.ReadString(), net.ReadUInt(32)
    local value, kind = net.ReadUInt(7), net.ReadUInt(2)
    -- 2026-09-26 custom bets: newer clients append the full stake (32 bits).
    if bits - (76 + (#id + 1) * 8) >= 32 then local wide = net.ReadUInt(32); if wide > 0 then value = wide end end
    if #id > 16 or (id ~= "" and not id:match("^%d+$")) or op < 1 or op > 5 then return end
    local result, err = A.Transaction(ply, revision, function(s, balance)
        A.Require(not A.ArcadeMain or A.ArcadeMain(ply), "Player duels are unavailable across isolated worlds.")
        return A.DuelAction(s, balance, op, id, duelRevision, value, kind, A.Enabled())
    end)
    A.Send(ply, result, err)
    if not result then return end
    -- Immediate opponent refresh; an offline opponent retains a durable claim.
    for _, other in ipairs(player.GetHumans()) do
        if other ~= ply and (not A.ArcadeMain or A.ArcadeMain(other)) and other.GoobArcadeDuel and tostring(other.GoobArcadeDuel) == id then
            local state, failure = A.Transaction(other)
            A.Send(other, state, failure)
        end
    end
end)
local nextSweep, ledgerID = 0, 0
hook.Add("Think", "GoobOS.Arcade.Duels", function()
    if RealTime() < nextSweep then return end
    nextSweep = RealTime() + 2
    local ok, err = pcall(function()
        A.DuelSweep()
        for _, ply in ipairs(player.GetHumans()) do
            if (not A.ArcadeMain or A.ArcadeMain(ply)) and ply.GoobArcadeDuel then
                local d = A.DuelRow(ply.GoobArcadeDuel)
                if d and d.status == "finished" then
                    local state, failure = A.Transaction(ply); A.Send(ply, state, failure)
                end
            end
        end
        local rows = A.Query("SELECT MAX(id) AS id FROM zc_arcade_ledger")
        local latest = rows and tonumber(rows[1].id) or 0
        if latest ~= ledgerID then
            net.Start("GoobOS.Arcade.Ledger")
            net.WriteString(util.TableToJSON(A.PublicLedger()))
            local recipients = {}
            for _, ply in ipairs(player.GetHumans()) do
                if not A.ArcadeMain or A.ArcadeMain(ply) then recipients[#recipients + 1] = ply end
            end
            net.Send(recipients)
            ledgerID = latest
        end
    end)
    if not ok then nextSweep = RealTime() + 30; ErrorNoHalt("[GoobOS Arcade] Social refresh deferred: " .. tostring(err) .. "\n") end
end)
