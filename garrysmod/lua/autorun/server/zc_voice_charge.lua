-- Loud-talker orb charge (owner 2026-09-24): the GoobOS voice orbs on each client grow while a player keeps
-- talking loud (75% for ~15 s, full volume for ~7.5 s); when an orb hits its limit the listening client reports it
-- here, the server blocks that player's voice for 3 s (PlayerCanHearPlayersVoice) and broadcasts the explosion
-- so every client plays it. Loudness exists only on clients, so the report is the only source; the server
-- sanity-checks it against its own IsSpeaking() history (the talker must really have been talking a while) and
-- rate-limits reporters. Nothing here touches ULX gags: a separate hook id, any false wins.
if not SERVER then return end
util.AddNetworkString("zc_voice_charge")
util.AddNetworkString("zc_voice_explode")
local cv = CreateConVar("zc_voice_charge", "1", FCVAR_ARCHIVE, "Loud-talker orb explosion + 3 s voice block (0/1)")
local BLOCK_S, MIN_TALK_S = 3, 5 -- MIN_TALK raised with the client fill rate (owner 2026-09-24 evening: full level now ~7.5 s)

local talkTime = setmetatable({}, {__mode = "k"}) -- seconds of recent speaking, decays while silent
timer.Create("ZCVoiceCharge.Track", 0.25, 0, function()
    for _, p in ipairs(player.GetAll()) do
        local t = talkTime[p] or 0
        talkTime[p] = p:IsSpeaking() and math.min(20, t + 0.25) or math.max(0, t - 0.25)
    end
end)

hook.Add("PlayerCanHearPlayersVoice", "ZCVoiceCharge.Block", function(_, talker)
    if IsValid(talker) and (talker.zcVoiceBlownUntil or 0) > CurTime() then return false end
end)

local lastReport = setmetatable({}, {__mode = "k"})
net.Receive("zc_voice_charge", function(len, reporter)
    if len > 32 or not cv:GetBool() or not IsValid(reporter) or reporter:IsBot() then return end
    local uid = net.ReadUInt(16)
    local talker = Player(uid)
    if not IsValid(talker) or talker == reporter then return end
    if (talker.zcVoiceBlownUntil or 0) > CurTime() then return end
    if (talkTime[talker] or 0) < MIN_TALK_S then return end
    if (lastReport[reporter] or 0) > CurTime() - 2 then return end
    lastReport[reporter] = CurTime()
    talker.zcVoiceBlownUntil = CurTime() + BLOCK_S
    net.Start("zc_voice_explode")
    net.WriteUInt(uid, 16)
    net.Broadcast()
    print(string.format("[GoobOS voice] %s reported %s's orb at its limit: voice blocked %d s", reporter:Nick(), talker:Nick(), BLOCK_S))
end)

hook.Add("InitPostEntity", "ZCVoiceCharge.Boot", function()
    print("[GoobOS] zc_voice_charge.lua on=" .. (cv:GetBool() and 1 or 0))
end)
