-- Nativized 2026-09-24 from addons/pats_text_presence/lua/autorun/server/sv_pat_textpresence_bridge.lua (verbatim; only
-- this header added). Loaded by lua/autorun/zc_text_presence.lua.
-- PAT TextPresence <-> ZCity bridge (v2)
-- Relays from PlayerCanSeePlayersChat: ZChat calls it per-recipient AFTER
-- all HG_PlayerSay mutations (brain-damage jumble included), so the
-- overhead text always matches what chat actually shows. Gagged and
-- unconscious speakers never reach this hook, so those stay silent free.
if not SERVER then return end

util.AddNetworkString("PAT_TextPresence_Speech")

local RELAY_RANGE = 1400
local lastRelay = {} -- ply -> { text, t } dedupe (hook fires per recipient)

hook.Add("PlayerCanSeePlayersChat", "PAT_TextPresence_Relay", function(text, teamOnly, listener, speaker)
    if not IsValid(speaker) or not speaker:IsPlayer() then return end
    if not isstring(text) or text == "" then return end

    -- commands stay off heads
    local first = string.sub(text, 1, 1)
    if first == "!" or first == "/" then return end

    -- fires once per recipient; relay once per message
    local last = lastRelay[speaker]
    if last and last.text == text and CurTime() - last.t < 0.2 then return end
    lastRelay[speaker] = { text = text, t = CurTime() }

    local origin = speaker:GetPos()
    local targets = {}
    for _, p in player.Iterator() do
        if p:GetPos():DistToSqr(origin) <= RELAY_RANGE * RELAY_RANGE then
            targets[#targets + 1] = p
        end
    end
    if #targets == 0 then return end

    net.Start("PAT_TextPresence_Speech")
        net.WriteEntity(speaker)
        net.WriteString(string.sub(text, 1, 240))
        net.WriteBool(speaker.ChatWhisper == true)
    net.Send(targets)

    -- IMPORTANT: return nothing - this is a passive tap on a query hook
end)

timer.Create("PAT_TextPresence_DedupeTrim", 60, 0, function()
    local now = CurTime()
    for ply, d in pairs(lastRelay) do
        if not IsValid(ply) or now - d.t > 5 then lastRelay[ply] = nil end
    end
end)

print("[TextPresence] ZCity chat relay v2 loaded (post-mutation tap)")
