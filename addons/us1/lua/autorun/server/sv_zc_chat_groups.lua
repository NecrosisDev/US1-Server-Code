if not SERVER then return end
AddCSLuaFile("zc_chat_media/groups.lua")
ZCChatGroups = ZCChatGroups or {groups={},nextID=0,ready={},watch={},phase={}}
local G=ZCChatGroups
G.active=G.active or {}
G.Version="20260923.groups1a"
G.Hidden="[Spectator message hidden]"
util.AddNetworkString("zcGroupAction")
util.AddNetworkString("zcGroupEvent")
ULib.ucl.registerAccess("zc groupchat peek",ULib.ACCESS_OPERATOR,"Inspect group conversations for moderation","Chat")
function G.Spectator(p) return not p:Alive() or p:Team()==1002 end
function G.CanPeek(p)
 return IsValid(p) and ZCChatModeration and ZCChatModeration.CanDelete(p) and ULib.ucl.query(p,"zc groupchat peek") == true
end
local function sid(p)return p:SteamID64()end
local function resolve(id)return ZCChatPM.Resolve(id)end
local function emit(p,e)
 if not IsValid(p) or not G.ready[p] then return end
 net.Start("zcGroupEvent");net.WriteString(util.TableToJSON(e));net.Send(p)
end
local function status(p,text,nonce,ok)emit(p,{kind="status",text=text,nonce=nonce,ok=ok==true})end
local function validSteam(id)return isstring(id) and id:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$")end
local function decodeStore(raw)
 if not raw or #raw>262144 then return end
 local data=util.JSONToTable(raw)
 if not istable(data) or data.version~=1 or not istable(data.groups) or #data.groups>64 then return end
 local groups,nextID={},0
 for _,saved in ipairs(data.groups)do
  if not isnumber(saved.id) or saved.id<1 or saved.id>1000000000 or saved.id%1~=0 or groups[saved.id] or not isstring(saved.name) or #saved.name>128 or not utf8.len(saved.name) or utf8.len(saved.name)>32 or not validSteam(saved.owner) or not istable(saved.members) or #saved.members>12 then return end
  local members={}
  for _,m in ipairs(saved.members)do
   if not istable(m) or not validSteam(m.id) or not isstring(m.name) or #m.name>128 then return end
   members[m.id]={name=m.name,joined=1}
  end
  if not members[saved.owner] then return end
  groups[saved.id]={id=saved.id,name=saved.name,owner=saved.owner,members=members,messages={},invites={},seq=0,last=CurTime(),sensitiveName=saved.sensitiveName==true}
  nextID=math.max(nextID,saved.id)
 end
 return groups,nextID
end
G.DecodeStore=decodeStore
function G.Save()
 local data={version=1,groups={}}
 for _,g in pairs(G.groups)do
  local members={};for id,m in pairs(g.members)do members[#members+1]={id=id,name=m.name}end
  data.groups[#data.groups+1]={id=g.id,name=g.name,owner=g.owner,members=members,sensitiveName=g.sensitiveName}
 end
 file.CreateDir("zc_chat_media")
 local path="zc_chat_media/groups.json";local before=file.Read(path,"DATA")
 if decodeStore(before)then file.Write("zc_chat_media/groups_previous.json",before)end
 file.Write(path,util.TableToJSON(data))
end
if not G.loaded then
 G.loaded=true
 local groups,nextID=decodeStore(file.Read("zc_chat_media/groups.json","DATA"))
 if not groups then groups,nextID=decodeStore(file.Read("zc_chat_media/groups_previous.json","DATA"))end
 if groups then G.groups=groups;G.nextID=nextID end
end
local function audit(p,action,id)
 if action=="create" or action=="join" then G.Save()end
 file.CreateDir("zc_chat_media")
 local path="zc_chat_media/group_audit.jsonl"
 if (file.Size(path,"DATA") or 0)>1048576 then file.Write("zc_chat_media/group_audit_previous.jsonl",file.Read(path,"DATA") or "");file.Write(path,"")end
 file.Append(path,util.TableToJSON({at=os.time(),by=sid(p),action=action,group=id,map=game.GetMap()}).."\n")
end
local function peek(p,g)return G.CanPeek(p) and G.watch[p]==g.id end
function G.Inspecting(p,id)return G.watch[p]==id and G.CanPeek(p)end
local function member(p,g)return g.members[sid(p)] end
local function visible(p,g,m)
 if peek(p,g) then return true end
 local mem=member(p,g)
 return mem and m.seq>=mem.joined and (not m.dead or G.Spectator(p)) or false
end
G.Visible=visible
function ZCChatGroupCanAccess(p,record)
 if not record or not record.groupID then return true end
 local g=G.groups[record.groupID]
 if not g then return false end
 return visible(p,g,{seq=record.groupSeq,dead=record.spectator})
end
function ZCChatAudienceCanAccess(p,record)
 if record and record.groupID then return ZCChatGroupCanAccess(p,record) end
 return not (record and record.spectator and record.conversation and record.conversation:sub(1,3)=="pm:") or G.Spectator(p)
end
local function packet(p,g,m)
 local rec=ZCChatModeration.records[m.id]
 local hidden=not visible(p,g,m)
 local deleted=not rec or rec.deleted
 local text=hidden and G.Hidden or (deleted and (rec and "[Message removed]" or "[Message unavailable]") or m.text)
 local reply=0
 if not hidden and not deleted and m.reply~=0 then
  local parent=ZCChatModeration.records[m.reply]
  if parent and not parent.deleted and parent.groupID==g.id and ZCChatGroupCanAccess(p,parent) then reply=m.reply end
 end
 return {kind="message",group=g.id,seq=m.seq,id=(hidden or deleted) and 0 or m.id,sender=m.sender,name=m.name,text=text,reply=reply,censored=hidden or deleted,dead=m.dead,quiet=false}
end
G.Packet=packet
local function grant(p,g,m)
 if not visible(p,g,m) then return end
 local id=sid(p)
 local record=ZCChatModeration.records[m.id]
 if record then record.viewers[id]=true end
 local react=ZCChatReactionStore and ZCChatReactionStore.records[m.id]
 if react then
  react.viewers[id]=true
  local found=false;for _,v in ipairs(react.recipients)do if v==p then found=true end end
  if not found then react.recipients[#react.recipients+1]=p end
 end
end
local function meta(p,g)
 local list={}
 for id,m in pairs(g.members)do local target=resolve(id);list[#list+1]={id=id,name=IsValid(target) and target:Nick() or m.name}end
 table.sort(list,function(a,b)return a.name:lower()<b.name:lower()end)
 return {kind="state",group=g.id,name=g.name,owner=g.owner,members=list,peek=peek(p,g),member=member(p,g)~=nil}
end
function G.Index(p,staff)
 local groups,invites={},{}
 for _,g in pairs(G.groups)do
  if member(p,g) or (staff and G.CanPeek(p))then groups[#groups+1]={id=g.id,name=g.name,count=table.Count(g.members),owner=g.owner,member=member(p,g)~=nil}end
  local invite=g.invites[sid(p)]
  if invite and invite.untilTime>CurTime() then
   local by=resolve(invite.by)
   if IsValid(by) and (not G.Spectator(by) or G.Spectator(p)) then invites[#invites+1]={id=g.id,name=g.name,by=by:Nick()}
   else g.invites[sid(p)]=nil end
  end
 end
 table.sort(groups,function(a,b)return a.id<b.id end)
 emit(p,{kind="index",groups=groups,invites=invites,staff=G.CanPeek(p),inspection=staff==true})
end
local function changed(g)
 for _,p in ipairs(player.GetHumans())do
  if member(p,g) or peek(p,g) then emit(p,meta(p,g));G.Index(p) end
 end
end
function G.Sync(p,g)
 if not member(p,g) and not peek(p,g) then return status(p,"You are not a member of that group.")end
 G.active[p]=g.id
 emit(p,meta(p,g));emit(p,{kind="reset",group=g.id})
 local mem=member(p,g)
 for _,m in ipairs(g.messages)do
  if peek(p,g) or (mem and m.seq>=mem.joined) then
   grant(p,g,m);local e=packet(p,g,m);e.quiet=true;emit(p,e)
  end
 end
end
local function canUse(p)
 return IsValid(p) and not p:IsBot() and ULib.ucl.query(p,"ulx psay") and not p:GetNWBool("ulx_muted",false)
end
local function validText(text,max)
 if not isstring(text) or #text>2048 or not text:find("%S") or text:find("[%z\1-\31\127]")then return false end
 local len=utf8.len(text);return len and len<=max
end
local function countMember(id)
 local n=0;for _,g in pairs(G.groups)do if g.members[id]then n=n+1 end end;return n
end
function G.Create(p,name)
 if not canUse(p) then return status(p,"You cannot create a group right now.")end
 if not validText(name,32)then return status(p,"Use a group name of 1–32 characters.")end
 local owned=0;for _,g in pairs(G.groups)do if g.owner==sid(p)then owned=owned+1 end end
 if owned>=3 or countMember(sid(p))>=6 or table.Count(G.groups)>=64 then return status(p,"Group limit reached. Leave an unused group first.")end
 G.nextID=G.nextID+1
 local g={id=G.nextID,name=string.Trim(name),owner=sid(p),members={[sid(p)]={name=p:Nick(),joined=1}},invites={},messages={},seq=0,sensitiveName=G.Spectator(p),last=CurTime()}
 G.groups[g.id]=g;audit(p,"create",g.id);emit(p,meta(p,g));G.Index(p);emit(p,{kind="open",group=g.id,created=true})
 return g
end
function G.Invite(p,g,target)
 if not canUse(p) or g.owner~=sid(p) then return status(p,"Only the group owner can invite players.")end
 if not IsValid(target) or target:IsBot() or not G.ready[target] then return status(p,"That player does not have group chat available yet.")end
 if (G.Spectator(p) or g.sensitiveName) and not G.Spectator(target) then return status(p,"Spectator group names and invitations cannot be sent to living players.")end
 if g.members[sid(target)]then return status(p,"That player is already a member.")end
 if table.Count(g.members)>=12 or countMember(sid(target))>=6 then return status(p,"This group or player has reached the group limit.")end
 g.invites[sid(target)]={by=sid(p),untilTime=CurTime()+120};G.Index(target);status(p,"Invitation sent.");audit(p,"invite",g.id)
end
function G.Accept(p,g)
 local i=g.invites[sid(p)];local by=i and resolve(i.by)
 if not canUse(p) or not i or i.untilTime<=CurTime() or not IsValid(by)then return status(p,"This invitation has expired.")end
 if (G.Spectator(by) or g.sensitiveName) and not G.Spectator(p)then g.invites[sid(p)]=nil;G.Index(p);return status(p,"This spectator invitation is no longer available.")end
 if table.Count(g.members)>=12 or countMember(sid(p))>=6 then return status(p,"Group limit reached.")end
 g.invites[sid(p)]=nil;g.members[sid(p)]={name=p:Nick(),joined=g.seq+1};g.last=CurTime();audit(p,"join",g.id);changed(g);G.Sync(p,g);emit(p,{kind="open",group=g.id})
end
function G.Leave(p,g)
 if not member(p,g)then return end
 g.members[sid(p)]=nil;g.invites[sid(p)]=nil;audit(p,"leave",g.id);emit(p,{kind="revoke",group=g.id});G.Index(p)
 if not next(g.members)then
  G.groups[g.id]=nil;G.Save()
  for watcher,id in pairs(G.watch)do if id==g.id then G.watch[watcher]=nil;emit(watcher,{kind="revoke",group=g.id})end end
  return
 end
 if g.owner==sid(p)then local ids=table.GetKeys(g.members);table.sort(ids);g.owner=ids[1];g.invites={}end
 G.Save();changed(g)
end
function G.Peek(p,g)
 if not G.CanPeek(p)then return status(p,"Your rank cannot inspect group chats.")end
 if G.watch[p] and G.watch[p]~=g.id then
  local old=G.groups[G.watch[p]];G.watch[p]=nil
  if old then if member(p,old)then G.Sync(p,old)else emit(p,{kind="revoke",group=old.id})end end
 end
 G.watch[p]=g.id;audit(p,"peek_start",g.id);G.Sync(p,g);emit(p,{kind="open",group=g.id})
end
function G.Unpeek(p)
 local g=G.groups[G.watch[p]];G.watch[p]=nil
 if not g then return end
 audit(p,"peek_stop",g.id)
 if member(p,g)then G.Sync(p,g)else emit(p,{kind="revoke",group=g.id})end
end
function G.Send(p,g,text,reply,nonce)
 if not canUse(p) or not member(p,g) or peek(p,g)then return status(p,"You cannot send to this conversation.",nonce,false)end
 if CurTime()<(p.ZCNextPM or 0)then return status(p,"Wait a moment before sending again.",nonce,false)end
 p.ZCNextPM=CurTime()+.75
 if not validText(text,256)then return status(p,"Use 1–256 valid characters.",nonce,false)end
 -- ChatGuard hides links that do not embed (zc_chatguard_hidelinks); fails open, "" = nothing left to send.
 if ZCChatGuard and ZCChatGuard.FilterLinks then local ok,shown=pcall(ZCChatGuard.FilterLinks,p,text," group");if ok and isstring(shown)then if shown==""then return status(p,"Link hidden: chat only shows links to YouTube, Giphy and Steam.",nonce,false)end;text=shown end end
 local parent=ZCChatModeration.records[reply or 0]
 if reply and reply~=0 and (not parent or parent.deleted or parent.groupID~=g.id or not ZCChatGroupCanAccess(p,parent))then return status(p,"That reply is unavailable in this group.",nonce,false)end
 g.seq=g.seq+1;g.last=CurTime()
 local m={seq=g.seq,text=text,reply=reply or 0,sender=sid(p),name=p:Nick(),dead=G.Spectator(p)}
 local recipients={}
 for _,target in ipairs(player.GetHumans())do if G.ready[target] and visible(target,g,m)then recipients[#recipients+1]=target end end
 m.id=ZCChatReaction_Register(p,recipients)
 local rec=ZCChatModeration.records[m.id];rec.conversation="group:"..g.id;rec.groupID=g.id;rec.groupSeq=m.seq;rec.spectator=m.dead
 local react=ZCChatReactionStore and ZCChatReactionStore.records[m.id];if react then react.groupID=g.id;react.groupSeq=m.seq;react.spectator=m.dead end
 g.messages[#g.messages+1]=m;while #g.messages>40 do table.remove(g.messages,1)end
 for _,target in ipairs(player.GetHumans())do
  if G.ready[target] and (member(target,g) or peek(target,g))then emit(target,meta(target,g));emit(target,packet(target,g,m))end
 end
 status(p,"Sent",nonce,true)
 return m
end
function G.Action(p,a)
 if not istable(a) or not isstring(a.op)then return end
 if a.op=="hello"then G.ready[p]=true;G.phase[p]=G.Spectator(p);G.Index(p);return end
 if not G.ready[p]then return end
 if a.op=="create"then return G.Create(p,a.name)end
 if a.op=="list"then return G.Index(p,a.staff==true)end
 if a.op=="unpeek"then return G.Unpeek(p)end
 local id=tonumber(a.group);local g=id and G.groups[id]
 if not g then return status(p,"This group is no longer available.",a.nonce,false)end
 if a.op=="invite"then return G.Invite(p,g,resolve(a.target))end
 if a.op=="accept"then return G.Accept(p,g)end
 if a.op=="decline"then g.invites[sid(p)]=nil;return G.Index(p)end
 if a.op=="leave"then return G.Leave(p,g)end
 if a.op=="peek"then return G.Peek(p,g)end
 if a.op=="sync"then if CurTime()<(p.ZCGroupSyncAt or 0)then return end;p.ZCGroupSyncAt=CurTime()+.75;return G.Sync(p,g)end
 if a.op=="send"then
  if not isnumber(a.nonce) or a.nonce<1 or a.nonce>65535 or a.nonce%1~=0 then return end
  local reply=tonumber(a.reply) or 0;if reply<0 or reply>4294967295 or reply%1~=0 then return end
  return G.Send(p,g,a.text,reply,a.nonce)
 end
end
net.Receive("zcGroupAction",function(bits,p)
 if not IsValid(p) or p:IsBot() or bits>20000 then return end
 if G.Preview and not G.Preview[sid(p)]then return end
 if CurTime()<(p.ZCNextGroupAction or 0)then return end;p.ZCNextGroupAction=CurTime()+.2
 local raw=net.ReadString();if #raw>2400 then return end
 G.Action(p,util.JSONToTable(raw))
end)
timer.Create("ZCChatGroups.Visibility",.5,0,function()
 for _,p in ipairs(player.GetHumans())do if G.ready[p]then
  if G.watch[p] and not G.CanPeek(p)then G.Unpeek(p)end
  local phase=G.Spectator(p)
  if G.phase[p]~=phase then
   G.phase[p]=phase
   for _,g in pairs(G.groups)do if member(p,g) and not peek(p,g)then emit(p,meta(p,g));emit(p,{kind="reset",group=g.id})end end
   local active=G.groups[G.active[p]];if active and member(p,active) and not peek(p,active)then G.Sync(p,active)end
   G.Index(p)
  end
 end end
end)
hook.Add("PlayerDisconnected","ZCChatGroups.Cleanup",function(p)G.ready[p]=nil;G.watch[p]=nil;G.phase[p]=nil;G.active[p]=nil end)
-- Membership survives map changes; transcripts do not. Empty/offline stale groups are bounded.
timer.Create("ZCChatGroups.Expire",60,0,function()
 for id,g in pairs(G.groups)do
  if CurTime()-g.last>3600 then
   local online=false;for steam in pairs(g.members)do if IsValid(resolve(steam))then online=true end end
   if not online then G.groups[id]=nil;G.Save();for watcher,groupID in pairs(G.watch)do if groupID==id then G.watch[watcher]=nil;emit(watcher,{kind="revoke",group=id})end end end
  end
 end
end)
