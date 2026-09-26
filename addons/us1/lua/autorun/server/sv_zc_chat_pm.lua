if not SERVER then return end
AddCSLuaFile("zc_chat_media/threads.lua")
ZCChatPM = ZCChatPM or {ready = setmetatable({}, {__mode = "k"})}
local S = ZCChatPM
S.botReady = S.botReady or setmetatable({}, {__mode = "k"})
S.Version = "20260924.cross-pm1"
for _, name in ipairs({"zcPMHello", "zcBotPMHello", "zcPMSend", "zcPMMessage", "zcPMResult"}) do util.AddNetworkString(name) end
net.Receive("zcPMHello", function(bits, ply)
    if bits == 0 and IsValid(ply) then S.ready[ply] = true end
end)
net.Receive("zcBotPMHello", function(bits, ply)
    if bits == 0 and IsValid(ply) and not ply:IsBot() then S.botReady[ply] = true end
end)
function S.Key(a, b)
    if a > b then a, b = b, a end
    return "pm:" .. a .. ":" .. b
end
-- Managed bots need session-scoped IDs: their SteamID64 is not a unique inbox.
S.BotSession = S.BotSession or util.CRC(tostring(SysTime()) .. ":" .. game.GetMap())
function S.Identity(p)
    if not p:IsBot() then return p:SteamID64() end
    if not p.zcBot then return end
    if not p.zcChatBotID then
        p.zcChatBotID = "bot:" .. S.BotSession .. ":" .. p:UserID()
        p:SetNWString("zcBotChatID", p.zcChatBotID)
    end
    return p.zcChatBotID
end
function S.Resolve(id)
    if not isstring(id) or #id > 80 then return end
    local botID = id:match("^bot:%d+:%d+$")
    if not botID and not id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then return end
    for _, p in ipairs(player.GetAll()) do
        if (botID and p:IsBot() and p.zcBot or not botID and not p:IsBot()) and S.Identity(p) == id then return p end
    end
end
hook.Add("PlayerInitialSpawn", "ZCChatPM.BotIdentity", function(p)
    timer.Simple(0, function() if IsValid(p) and p:IsBot() then S.Identity(p) end end)
end)
for _, p in ipairs(player.GetBots()) do S.Identity(p) end
local function response(ply, nonce, ok, detail)
    if not S.ready[ply] then
        if not ok and ULib then ULib.tsayError(ply, detail, true) end
        return
    end
    net.Start("zcPMResult"); net.WriteUInt(nonce or 0, 16); net.WriteBool(ok); net.WriteString(detail); net.Send(ply)
end
function S.Send(sender, target, text, reply, nonce)
    if not IsValid(sender) or not sender:IsPlayer() or sender:IsBot() then return false end
    if S.Preview and not S.Preview[sender:SteamID64()] then return false end
    if not IsValid(target) or not target:IsPlayer() or (target:IsBot() and not target.zcBot) or target == sender then
        response(sender, nonce, false, "That player is no longer available."); return false
    end
    if not (ULib and ULib.ucl and ULib.ucl.query(sender, "ulx psay")) then response(sender, nonce, false, "Private messaging is not available for your account."); return false end
    if sender:GetNWBool("ulx_muted", false) then response(sender, nonce, false, "You are muted and cannot send private messages."); return false end
    if CurTime() < (sender.ZCNextPM or 0) then response(sender, nonce, false, "Wait a moment before sending another message."); return false end
    sender.ZCNextPM = CurTime() + .75
    if not isstring(text) or #text > 2048 or not text:find("%S") or text:find("[%z\1-\8\11\12\14-\31]") then
        response(sender, nonce, false, "Enter a valid message."); return false
    end
    local count = utf8.len(text)
    if not count or count > 256 then response(sender, nonce, false, "Messages may contain up to 256 characters."); return false end
    local a, b = S.Identity(sender), S.Identity(target)
    local function spectator(p) return not p:Alive() or p:Team()==1002 end
    local cross = spectator(sender) ~= spectator(target)
    -- PMs are private conversations, independent of public spectator chat.
    local conversation = S.Key(a, b)
    reply = tonumber(reply) or 0
    if reply ~= 0 then
        local record = ZCChatModeration and ZCChatModeration.records[reply]
        if not record or record.deleted or record.conversation ~= conversation or not record.viewers[a] or (not target:IsBot() and not record.viewers[b]) or (ZCChatAudienceCanAccess and not ZCChatAudienceCanAccess(sender,record)) then
            response(sender, nonce, false, "The message you are replying to is no longer available in this conversation."); return false
        end
    end
    if not ZCChatReaction_Register or not ZCChatModeration then response(sender, nonce, false, "Private messaging is temporarily unavailable."); return false end
    local audience={sender};if not target:IsBot() then audience[#audience+1]=target end
    local id = ZCChatReaction_Register(sender, audience)
    local record = ZCChatModeration.records[id]
    if not record then response(sender, nonce, false, "Private messaging is temporarily unavailable."); return false end
    record.conversation = conversation;record.spectator=false
    local react=ZCChatReactionStore and ZCChatReactionStore.records[id];if react then react.conversation=conversation;react.spectator=false end
    local clients = target:IsBot() and {sender} or {sender, target}
    for _, recipient in ipairs(clients) do
        local body=text
        local quote=reply
        if quote~=0 and ZCChatAudienceCanAccess and not ZCChatAudienceCanAccess(recipient,ZCChatModeration.records[quote]) then quote=0 end
        if S.ready[recipient] and (not target:IsBot() or S.botReady[recipient]) then
            net.Start("zcPMMessage")
            net.WriteString(a); net.WriteString(b)
            net.WriteString(sender:Nick()); net.WriteString(target:Nick())
            net.WriteString(body); net.WriteUInt(id, 32); net.WriteUInt(quote, 32);net.WriteBool(false);net.WriteBool(false)
            net.Send(recipient)
        else
            -- Compatibility for an unrefreshed client: still only its private channel.
            ULib.tsayColor(recipient, false, Color(145, 205, 255), "[PM] " .. sender:Nick() .. " → " .. target:Nick() .. ": ", color_white, body)
        end
    end
    if target:IsBot() then hook.Run("ZCChatPMDelivered", sender, target, text) end
    if cross then
        for _, staff in ipairs(player.GetHumans()) do
            if staff ~= sender and staff ~= target and ZCChatModeration.CanDelete
                and ZCChatModeration.CanDelete(staff) then
                -- A staff audit line, never a third-party PM thread or public broadcast.
                ULib.tsayColor(staff, false, Color(255, 195, 100),
                    "[PM oversight · spectator ↔ living] " .. sender:Nick() .. " → " .. target:Nick() .. ": ", color_white, text)
            end
        end
    end
    response(sender, nonce, true, cross and "Sent · staff oversight" or "Sent")
    return true
end
-- Server-authored social lines only. No client receiver can impersonate a bot.
-- These contain no observed positions/roles or relayed player text, so a dead
-- bot can compliment its living killer; these are not player-authored cross-state PMs.
function S.SendBot(bot, target, text)
    if not IsValid(bot) or not bot:IsBot() or not bot.zcBot or not IsValid(target)
        or not target:IsPlayer() or target:IsBot() or not isstring(text) or #text > 256
        or text:find("[%c<>{}]") or not utf8.len(text) then return false end
    if S.Preview and not S.Preview[target:SteamID64()] then return false end
    if not ZCChatReaction_Register or not ZCChatModeration then return false end
    local a, b = S.Identity(bot), S.Identity(target)
    local id = ZCChatReaction_Register(bot, {target})
    local record = ZCChatModeration.records[id]
    if not record then return false end
    record.speaker = a; record.conversation = S.Key(a,b); record.spectator = false
    local react = ZCChatReactionStore and ZCChatReactionStore.records[id]
    if react then react.conversation = record.conversation; react.spectator = false end
    if S.ready[target] and S.botReady[target] then
        net.Start("zcPMMessage")
        net.WriteString(a); net.WriteString(b)
        net.WriteString(bot:Nick()); net.WriteString(target:Nick())
        net.WriteString(text); net.WriteUInt(id,32); net.WriteUInt(0,32)
        net.WriteBool(false); net.WriteBool(false); net.Send(target)
    elseif ULib then
        ULib.tsayColor(target,false,Color(145,205,255),"[PM] " .. bot:Nick() .. " → " .. target:Nick() .. ": ",color_white,text)
    else return false end
    return true
end
net.Receive("zcPMSend", function(bits, ply)
    if not IsValid(ply) or not S.ready[ply] or bits > 17000 then return end
    local id, text, reply, nonce = net.ReadString(), net.ReadString(), net.ReadUInt(32), net.ReadUInt(16)
    S.Send(ply, S.Resolve(id), text, reply, nonce)
end)
hook.Add("PlayerDisconnected", "ZCChatPM.Cleanup", function(ply) S.ready[ply], S.botReady[ply] = nil, nil end)
