if not SERVER then return end
ZCChatModeration = ZCChatModeration or {records={},order={}}
local S=ZCChatModeration
S.Version="20260922.moderation1"
util.AddNetworkString("zcChatDelete")
util.AddNetworkString("zcChatDeleted")
util.AddNetworkString("zcChatDeleteResult")
local function staff(ply)
    if not IsValid(ply) or not ply:IsPlayer() or ply:IsBot() then return false end
    if S.PreviewOnly and ply:SteamID64() ~= S.PreviewOnly then return false end
    if ply:IsAdmin() or ply:IsSuperAdmin() then return true end
    -- US1: Community Manager and admin inherit operator. Moderator is also
    -- accepted if that rank is added; ULib CheckGroup rejects unknown groups.
    return ply.CheckGroup and (ply:CheckGroup("operator") or ply:CheckGroup("moderator")) == true or false
end
S.CanDelete=staff
function ZCChatModeration_Register(id,speaker,recipients)
    if not id or id==0 or not IsValid(speaker) or not speaker:IsPlayer() then return end
    if S.records[id] then return end
    local viewers={}
    for _,ply in ipairs(recipients or {}) do if IsValid(ply) and ply:IsPlayer() then viewers[ply:SteamID64()]=true end end
    S.records[id]={speaker=speaker:SteamID64(),name=speaker:Nick(),viewers=viewers,at=os.time()}
    S.order[#S.order+1]=id
    while #S.order>1024 do S.records[table.remove(S.order,1)]=nil end
end
local function result(ply,ok,detail)
    net.Start("zcChatDeleteResult"); net.WriteBool(ok); net.WriteString(detail); net.Send(ply)
end
net.Receive("zcChatDelete",function(len,ply)
    if len~=32 or not IsValid(ply) then return end
    local id=net.ReadUInt(32)
    if CurTime()<(ply.zcNextDelete or 0) then return end
    ply.zcNextDelete=CurTime()+0.3
    if not staff(ply) then return result(ply,false,"Your rank cannot delete chat messages.") end
    local record=S.records[id]
    if not record or not record.viewers[ply:SteamID64()] then return result(ply,false,"This message is no longer available for moderation.") end
    if ZCChatAudienceCanAccess and not ZCChatAudienceCanAccess(ply,record) then return result(ply,false,"This message is not visible to you.") end
    if record.deleted then return result(ply,false,"This message has already been removed.") end
    record.deleted=true
    local recipients={}
    for _,recipient in ipairs(player.GetHumans()) do
        if record.viewers[recipient:SteamID64()] and (not ZCChatAudienceCanAccess or ZCChatAudienceCanAccess(recipient,record)) then recipients[#recipients+1]=recipient end
    end
    net.Start("zcChatDeleted"); net.WriteUInt(id,32); net.Send(recipients)
    result(ply,true,"Message and attached media removed.")
    local audit={time=os.date("!%Y-%m-%dT%H:%M:%SZ"),action="delete",id=id,by=ply:SteamID64(),speaker=record.speaker,map=game.GetMap()}
    file.CreateDir("zc_chat_media")
    local path="zc_chat_media/deletions.jsonl"
    if (file.Size(path,"DATA") or 0)>1024*1024 then
        file.Write("zc_chat_media/deletions_previous.jsonl",file.Read(path,"DATA") or ""); file.Write(path,"")
    end
    file.Append(path,util.TableToJSON(audit).."\n")
end)

local function permissions()
    for _,ply in ipairs(player.GetHumans()) do ply:SetNWBool("ZCChatCanDelete",staff(ply)) end
end
timer.Create("ZCChatModeration.Permissions",2,0,permissions)
hook.Add("PlayerInitialSpawn","ZCChatModeration.Join",function(ply)
    timer.Simple(2,function() if IsValid(ply) then ply:SetNWBool("ZCChatCanDelete",staff(ply)) end end)
end)
permissions()
