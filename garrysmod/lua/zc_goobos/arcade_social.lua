if not CLIENT then return end
-- Duel requests and the public ledger feed. The Duels and Ledger tabs are drawn by arcade.lua.
local A = ZCGoobApps
local C = A.State.arcade
function A.ArcadeDuelRequest(op, d, value, kind)
    if not A.ArcadeCanAct() or util.NetworkStringToID("GoobOS.Arcade.Duel") == 0 then return false end
    C.pending, C.sent = true, RealTime()
    net.Start("GoobOS.Arcade.Duel")
    net.WriteUInt(op, 3); net.WriteUInt(C.data.revision, 32)
    net.WriteString(d and tostring(d.id) or ""); net.WriteUInt(d and d.revision or 0, 32)
    net.WriteUInt(math.min(value or 0, 127), 7); net.WriteUInt(kind or 0, 2)
    net.WriteUInt(value or 0, 32) -- 2026-09-26 custom bets: full stake
    net.SendToServer()
    return true
end
net.Receive("GoobOS.Arcade.Ledger", function()
    local raw = net.ReadString()
    if #raw > 24000 or (C.data and C.data.scope and C.data.scope ~= "main") then return end
    local rows = util.JSONToTable(raw, false, true)
    if not istable(rows) then return end
    C.ledger = rows
    if C.data then C.data.ledger = rows end
    -- Other players' results must not recreate an active hand or duel's controls.
    if C.tab == "ledger" then C.dirty = true end
end)
