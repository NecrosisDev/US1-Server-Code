-- Give Up server side: validates the sender is genuinely unconscious
-- (server-authoritative organism state), then kills them.
if not SERVER then return end

util.AddNetworkString("zc_giveup")

local lastGiveUp = {}

net.Receive("zc_giveup", function(len, ply)
    if not IsValid(ply) or not ply:Alive() then return end

    -- rate limit
    if (lastGiveUp[ply] or 0) > CurTime() - 2 then return end
    lastGiveUp[ply] = CurTime()

    -- must actually be unconscious - no chat-suicide bypass
    local org = ply.organism
    if not org or org.otrub ~= true then return end

    print("[GiveUp] " .. ply:Nick() .. " gave up while unconscious.")
    local justice=ZCJusticeV3Integration
                if justice and justice.enabled and justice.WithTerminal then
                    justice:WithTerminal(ply,"giveup",function()ply:Kill()end)
                else ply:Kill()end
end)

hook.Add("PlayerDisconnected", "GiveUp_Cleanup", function(ply)
    lastGiveUp[ply] = nil
end)
