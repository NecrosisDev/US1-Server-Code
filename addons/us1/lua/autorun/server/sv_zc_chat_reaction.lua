if not SERVER then return end

util.AddNetworkString("zcChatReact")
util.AddNetworkString("zcChatReactionState")

ZCChatReactionStore = ZCChatReactionStore or {records={},order={},nextID=math.random(1,2147483647)}
local store = ZCChatReactionStore
local reactions = store.records
local order = store.order
-- A legacy registry export shares these tables while chat remains live.
-- Follow its newest ID even if messages arrived between export and reload.
store.nextID = order[#order] or store.nextID
local MAX_MESSAGES = 256
local MAX_AGE = 600
local EMOJI_COUNT = 6

local function trim()
    local now = CurTime()
    while #order > 0 do
        local id = order[1]
        local record = reactions[id]
        if #order <= MAX_MESSAGES and record and record.expires > now then break end
        table.remove(order, 1)
        reactions[id] = nil
    end
end

function ZCChatReaction_Register(speaker, recipients)
    if not IsValid(speaker) or not speaker:IsPlayer() then return 0 end
    trim()
    store.nextID = store.nextID % 4294967295 + 1
    local nextID = store.nextID
    local viewers = {}
    for _, ply in ipairs(recipients or {}) do
        if IsValid(ply) and ply:IsPlayer() then viewers[ply:SteamID64()] = true end
    end
    reactions[nextID] = {
        expires = CurTime() + MAX_AGE,
        viewers = viewers,
        recipients = recipients,
        byPlayer = {},
        counts = {0, 0, 0, 0, 0, 0},
    }
    order[#order + 1] = nextID
    trim()
    if ZCChatModeration_Register then ZCChatModeration_Register(nextID, speaker, recipients) end
    return nextID
end

net.Receive("zcChatReact", function(_, ply)
    if not IsValid(ply) then return end
    local id = net.ReadUInt(32)
    local emoji = net.ReadUInt(3)
    local record = reactions[id]
    if ZCChatModeration and ZCChatModeration.records[id] and ZCChatModeration.records[id].deleted then return end
    if not record or record.expires <= CurTime() or emoji < 1 or emoji > EMOJI_COUNT then return end
    local steam = ply:SteamID64()
    if not record.viewers[steam] then return end
    if record.groupID and ZCChatGroups and ZCChatGroups.Inspecting(ply,record.groupID) then return end
    if ZCChatAudienceCanAccess and not ZCChatAudienceCanAccess(ply,record) then return end
    if CurTime() < (ply.zcNextChatReaction or 0) then return end
    ply.zcNextChatReaction = CurTime() + 0.25

    local previous = record.byPlayer[steam]
    if previous then record.counts[previous] = math.max(0, record.counts[previous] - 1) end
    local selected = previous == emoji and 0 or emoji
    record.byPlayer[steam] = selected ~= 0 and selected or nil
    if selected ~= 0 then record.counts[selected] = record.counts[selected] + 1 end

    local viewers = {}
    for _, recipient in ipairs(record.recipients or {}) do
        if IsValid(recipient) and (not ZCChatAudienceCanAccess or ZCChatAudienceCanAccess(recipient,record)) then viewers[#viewers + 1] = recipient end
    end
    if #viewers == 0 then return end
    net.Start("zcChatReactionState")
        net.WriteUInt(id, 32)
        for i = 1, EMOJI_COUNT do net.WriteUInt(math.min(record.counts[i], 255), 8) end
        net.WriteString(steam)
        net.WriteUInt(selected, 3)
    net.Send(viewers)
end)
