if not CLIENT then return end
local G={Version="20260923.groups1a",meta={},index={},invites={},queue={},pending={},serial=0}
ZCChatGroupUI=G
local T=ZCChatThreads
local ink,muted,blue=Color(244,241,241),Color(163,160,160),Color(192,0,0)
function G.IsGroup(key)return isstring(key) and key:sub(1,6)=="group:"end
function G.Key(id)return "group:"..id end
function G.Spectator()local p=LocalPlayer();return not IsValid(p) or not p:Alive() or p:Team()==1002 end
function G.Request(a)
 if #G.queue>=12 then return false end
 G.queue[#G.queue+1]=a;return true
end
timer.Create("ZCChatGroupUI.Requests",.25,0,function()
 if #G.queue==0 or util.NetworkStringToID("zcGroupAction")==0 then return end
 local a=table.remove(G.queue,1);net.Start("zcGroupAction");net.WriteString(util.TableToJSON(a));net.SendToServer()
end)
function G.Hello()if IsValid(LocalPlayer())then G.Request({op="hello"})end end
hook.Add("InitPostEntity","ZCChatGroupUI.Hello",G.Hello)
timer.Simple(1,G.Hello)
local function btn(parent,label,action)
 local b=vgui.Create("DButton",parent);b:SetText("");b.DoClick=action
 b.Paint=function(self,w,h)
  self.blend=Lerp(math.Clamp(FrameTime()*16,0,1),self.blend or 0,self:IsHovered() and 1 or 0)
  draw.RoundedBox(0,0,0,w,h,Color(150,0,0,95+self.blend*90));draw.SimpleText(label,"DermaDefaultBold",w/2,h/2,ink,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
 end
 return b
end
function G.Init(chat)
 local b=btn(chat.ZCTabStrip,"",function()G.Directory(chat)end);chat.ZCGroupsButton=b;b:SetTooltip("Groups and invitations");b:SetKeyboardInputEnabled(false)
 local paint=b.Paint
 b.Paint=function(self,w,h)
  paint(self,w,h)
  draw.RoundedBox(3,7,7,6,6,ink);draw.RoundedBox(3,19,7,6,6,ink)
  draw.RoundedBox(4,5,16,10,8,ink);draw.RoundedBox(4,17,16,10,8,ink)
  if #G.invites>0 then draw.RoundedBox(4,w-9,1,8,8,Color(113,218,187))end
 end
end
function G.Layout(chat,w,h)if IsValid(chat.ZCGroupsButton)then chat.ZCGroupsButton:SetPos(w-118,6);chat.ZCGroupsButton:SetSize(32,32)end end
function G.GroupIcon(parent)
 local p=vgui.Create("DPanel",parent);p:SetSize(24,24);p:SetPos(4,4);p:SetMouseInputEnabled(false)
 p.Paint=function(_,w,h)draw.RoundedBox(0,0,0,w,h,Color(150,0,0));draw.SimpleText("#","DermaDefaultBold",w/2,h/2,ink,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end
 return p
end
function G.Caption(key)
 local m=G.meta[key];return m and (m.peek and "INSPECTING · Read only" or ("GROUP · "..m.name)) or "GROUP · Loading…"
end
function G.Placeholder(key)
 local m=G.meta[key];return m and (m.peek and "Staff inspection is read only" or ("Message "..m.name)) or "Loading group…"
end
function G.OnSelect(chat,key)
 if G.IsGroup(key) and not G.skipSync then G.Request({op="sync",group=tonumber(key:sub(7))})end
end
function G.OnClose(chat,key)
 local m=G.meta[key];if m and m.peek then G.Request({op="unpeek"})end
end
function G.Open(chat,id)
 local key=G.Key(id);local m=G.meta[key];if not m then return end
 G.skipSync=true;T.Open(chat,key,m.name);G.skipSync=nil
end
function G.Send(chat,text)
 local key=chat.ZCThreadKey;local m=G.meta[key];local s=chat.ZCThreads[key]
 if not m or m.peek or not m.member then T.Status(chat,"This conversation is read only.");return true end
 if s.pending then T.Status(chat,"Sending…");return true end
 if not text:find("%S")then return true end
 T.Save(chat);G.serial=G.serial%65535+1;local n=G.serial
 if not G.Request({op="send",group=m.group,text=text,reply=chat.ZCReplyID or 0,nonce=n})then T.Status(chat,"Please wait a moment.");return true end
 s.pending="group:"..n;G.pending[n]={key=key,text=text,reply=chat.ZCReplyID,at=RealTime()};T.Status(chat,"Sending…");return true
end
local function clear(chat,s)
 T.WithState(chat,s,function()
  for _,row in ipairs(s.entries)do if IsValid(row)then ZCChatMedia.Release(row);row:Remove()end end
  s.entries={};chat.entries=s.entries;s.reply=nil
 end)
 if chat.ZCThreadKey==s.key then chat.entries=s.entries;chat.ZCReplyID=nil end
end
G.Clear=clear
local function pane(chat,title)
 T.CloseDirectory(chat);ZCChatMedia.ClosePicker();ZCChatMedia.StopVideo();ZCChatMedia.Stop();chat:SetActive(true)
 local target=math.min(420,ScrH()-96)
 if chat:GetTall()<target then chat.ZCDirectoryHeight=chat:GetTall();chat.ZCDirectoryExpandedHeight=target;chat:SetTall(target);chat:SetY(ScrH()-48-target)end
 local p=vgui.Create("DPanel",chat);chat.ZCDirectory=p;p:DockPadding(14,12,14,12);p:SetAlpha(0);p:AlphaTo(255,.15)
 p.Paint=function(_,w,h)draw.RoundedBox(0,0,0,w,h,Color(36,33,33,253))end
 local h=vgui.Create("DPanel",p);h:Dock(TOP);h:SetTall(34);h.Paint=function()draw.SimpleText(title,"DermaDefaultBold",0,8,ink)end
 local feedback=vgui.Create("DLabel",p);p.ZCGroupFeedback=feedback;feedback:Dock(BOTTOM);feedback:SetTall(0);feedback:SetWrap(true);feedback:SetTextColor(blue);feedback:SetText("")
 local close=btn(h,"×",function()T.CloseDirectory(chat);chat.entry:RequestFocus();if T.IsMain(chat) then hook.Run("StartChat")end end);close:Dock(RIGHT);close:SetWide(28)
 T.Layout(chat,chat:GetSize());p:MoveToFront();hook.Run("FinishChat")
 return p,h
end
local function row(list,title,sub,action)
 local b=btn(list,"",action);b:Dock(TOP);b:SetTall(55);b:DockMargin(0,0,0,5)
 local paint=b.Paint
 b.Paint=function(self,w,h)
  paint(self,w,h);draw.SimpleText(string.utf8sub(title,1,math.max(12,math.floor((w-35)/7))),"DermaDefaultBold",12,11,ink)
  draw.SimpleText(sub,"DermaDefault",12,32,muted)
 end
 return b
end
function G.Directory(chat,staff)
 local p,header=pane(chat,staff and "Group moderation" or "Group conversations")
 local top=vgui.Create("DPanel",p);top:Dock(TOP);top:SetTall(34);top:DockMargin(0,4,0,10);top.Paint=nil
 local create=btn(top,"New group",function()G.CreatePanel(chat)end);create:Dock(LEFT);create:SetWide(100)
 if G.staff then local inspect=btn(top,staff and "My groups" or "Inspect groups",function()G.Directory(chat,not staff)end);inspect:Dock(RIGHT);inspect:SetWide(120)end
 local list=vgui.Create("DScrollPanel",p);list:Dock(FILL)
 local function populate()
  local scroll=list:GetVBar():GetScroll();list:Clear()
  for _,i in ipairs(G.invites)do
   local b=row(list,i.name,"Invitation from "..i.by,function()end)
   local yes=btn(b,"Join",function()G.Request({op="accept",group=i.id})end);yes:Dock(RIGHT);yes:SetWide(50)
   local no=btn(b,"×",function()G.Request({op="decline",group=i.id})end);no:Dock(RIGHT);no:SetWide(26)
  end
  for _,g in ipairs(G.index)do
   row(list,g.name,g.count.." members · "..(staff and "Staff inspection" or "Private group"),function()
    if staff then G.Request({op="peek",group=g.id})else
     local key=G.Key(g.id);local s=T.Ensure(chat,key,g.name);if s then s.closed=false end
     G.Request({op="sync",group=g.id});G.openNext=g.id
    end
   end)
  end
  if #G.index==0 and #G.invites==0 then row(list,"A space for your group","Create a group, then invite players.",function()G.CreatePanel(chat)end)end
  list:InvalidateLayout(true);list:GetVBar():SetScroll(scroll)
 end
 p.ZCGroupPopulate=populate;populate();G.Request({op="list",staff=staff==true})
end
function G.CreatePanel(chat)
 local p=pane(chat,"Create a group")
 local text=vgui.Create("DTextEntry",p);text:Dock(TOP);text:SetTall(36);text:DockMargin(0,10,0,10);text:SetPlaceholderText("Group name · 32 characters")
 local info=vgui.Create("DLabel",p);info:Dock(TOP);info:SetTall(72);info:SetWrap(true);info:SetTextColor(muted)
 info:SetText("Invite up to 11 other players. Spectator messages are hidden from living members. Authorized staff may inspect conversations for moderation.")
 local create=btn(p,"Create group",function()G.Request({op="create",name=text:GetText()})end);create:Dock(TOP);create:SetTall(34)
 text.OnEnter=create.DoClick;text:RequestFocus()
end
function G.Details(chat,key)
 local m=G.meta[key];if not m then return end
 local p,head=pane(chat,m.name)
 local controls=vgui.Create("DPanel",p);controls:Dock(TOP);controls:SetTall(34);controls:DockMargin(0,4,0,10);controls.Paint=nil
 if m.peek then
  local stop=btn(controls,"End inspection",function()G.Request({op="unpeek"});T.CloseDirectory(chat)end);stop:Dock(FILL)
 else
  local leave=btn(controls,"Leave group",function()G.Request({op="leave",group=m.group});T.CloseDirectory(chat)end);leave:Dock(RIGHT);leave:SetWide(100)
  if m.owner==LocalPlayer():SteamID64()then local invite=btn(controls,"Invite player",function()G.InvitePanel(chat,m)end);invite:Dock(LEFT);invite:SetWide(110)end
 end
 local list=vgui.Create("DScrollPanel",p);list:Dock(FILL)
 for _,person in ipairs(m.members)do row(list,person.name,person.id==m.owner and "Owner" or "Member",function()end)end
end
function G.InvitePanel(chat,m)
 local p=pane(chat,"Invite to "..string.utf8sub(m.name,1,24))
 local search=vgui.Create("DTextEntry",p);search:Dock(TOP);search:SetTall(32);search:DockMargin(0,5,0,10);search:SetPlaceholderText("Search online players…")
 local list=vgui.Create("DScrollPanel",p);list:Dock(FILL)
 local included={};for _,v in ipairs(m.members)do included[v.id]=true end
 local function populate()
  list:Clear();local q=string.Trim(search:GetText()):lower()
  for _,person in ipairs(player.GetHumans())do if not included[person:SteamID64()] and (q=="" or person:Nick():lower():find(q,1,true))then
   row(list,person:Nick(),"Send invitation",function()G.Request({op="invite",group=m.group,target=person:SteamID64()})end)
  end end
 end
 search.OnChange=populate;populate();search:RequestFocus()
end
function G.Menu(chat,key,menu)
 if G.meta[key]then menu:AddOption("Group details",function()G.Details(chat,key)end)end
end
function G.Event(e)
 local chat=hg and hg.chat;if not IsValid(chat)then return end
 if e.kind=="index"then
  G.index=e.groups or {};G.invites=e.invites or {};G.staff=e.staff
  if G.IsGroup(chat.ZCThreadKey) and not G.meta[chat.ZCThreadKey] then G.OnSelect(chat,chat.ZCThreadKey)end
  if IsValid(chat.ZCDirectory) and chat.ZCDirectory.ZCGroupPopulate then chat.ZCDirectory.ZCGroupPopulate()end
  return
 end
 if e.kind=="status"then
  local pending=e.nonce and G.pending[e.nonce];if e.nonce then G.pending[e.nonce]=nil end
  if pending then
   T.Save(chat);local s=chat.ZCThreads[pending.key]
   if s then s.pending=nil;if e.ok then
    if s.recall[#s.recall]~=pending.text then s.recall[#s.recall+1]=pending.text end
    while #s.recall>20 do table.remove(s.recall,1)end
    if s.draft==pending.text and s.reply==pending.reply then s.draft="";s.reply=nil;if chat.ZCThreadKey==s.key then chat.entry:SetText("");chat.entry.prevText="";chat.ZCReplyID=nil end end
   end end
  end
  if IsValid(chat.ZCDirectory) and IsValid(chat.ZCDirectory.ZCGroupFeedback) then local label=chat.ZCDirectory.ZCGroupFeedback;label:SetText(e.text or "");label:SetTall(40) end
  T.Status(chat,e.text or "");return
 end
 if not isnumber(e.group)then return end
 local key=G.Key(e.group)
 if e.kind=="state"then
  G.meta[key]=e;T.Ensure(chat,key,e.name)
  if G.openNext==e.group then G.openNext=nil;G.Open(chat,e.group)end
  return
 end
 local s=chat.ZCThreads[key]
 if e.kind=="revoke"then
  if s then if chat.ZCThreadKey==key then T.Select(chat,"main")end;clear(chat,s);s.history:Remove();chat.ZCThreads[key]=nil;table.RemoveByValue(chat.ZCThreadOrder,key)end
  G.meta[key]=nil;T.RebuildTabs(chat);return
 end
 if not s then return end
 if e.kind=="open"then G.Open(chat,e.group);if e.created then G.Details(chat,key)end;return end
 if e.kind=="reset"then clear(chat,s);return end
 if e.kind~="message"then return end
 if e.dead and not G.Spectator() and not (G.meta[key] and G.meta[key].peek) then e.text="[Spectator message hidden]";e.id=0;e.reply=0;e.censored=true end
 local old={CHAT_SPEAKER,CHAT_MESSAGE_ID,CHAT_REPLY_ID,CHAT_CONVERSATION,CHAT_PEER_NAME,CHAT_PRIVATE,CHAT_SENDER_NAME,CHAT_SENDER_STEAM}
 CHAT_SPEAKER=T.Player(e.sender);CHAT_MESSAGE_ID=e.id;CHAT_REPLY_ID=e.reply;CHAT_CONVERSATION=key;CHAT_PEER_NAME=s.name;CHAT_PRIVATE=true;CHAT_SENDER_NAME=e.name;CHAT_SENDER_STEAM=e.sender
 local elements={Color(175,222,221),IsValid(CHAT_SPEAKER) and CHAT_SPEAKER or e.name,color_white,": "..e.text};elements.zcSenderName=e.name;elements.zcPrivate=true
 local restoring=ZCChatMedia.Restoring;ZCChatMedia.Restoring=e.quiet==true or restoring
 local ok,err=pcall(function()
  local r=chat:AddLine(elements)
  if IsValid(r)then
   r.ZCGroupSeq=e.seq;r.ZCSpectator=e.dead;r.ZCCensored=e.censored
   if e.censored or e.quiet then r.ZCTypewriterStart=CurTime()-100;r.ZCRevealed=true;if IsValid(r.ZCReveal)then r.ZCReveal:Remove();r.ZCReveal=nil end end
  end
 end)
 ZCChatMedia.Restoring=restoring
 CHAT_SPEAKER,CHAT_MESSAGE_ID,CHAT_REPLY_ID,CHAT_CONVERSATION,CHAT_PEER_NAME,CHAT_PRIVATE,CHAT_SENDER_NAME,CHAT_SENDER_STEAM=unpack(old,1,8)
 if not ok then ErrorNoHalt("Group rendering: "..tostring(err).."\n")end
end
net.Receive("zcGroupEvent",function()local e=util.JSONToTable(net.ReadString());if istable(e)then G.Event(e)end end)
function G.Think(chat)
 local m=G.meta[chat.ZCThreadKey]
 if m and (m.peek or not m.member)then chat.entry:SetKeyboardInputEnabled(false)end
 local phase=G.Spectator()
 if G.phase~=phase then
  G.phase=phase
  for key,s in pairs(chat.ZCThreads)do
   if G.IsGroup(key) and G.meta[key] and not G.meta[key].peek then clear(chat,s)
   elseif key~="main" and not G.IsGroup(key) and not phase then
    T.WithState(chat,s,function()
     for i=#s.entries,1,-1 do local r=s.entries[i];if IsValid(r) and r.ZCSpectator and not r.ZCCensored then ZCChatMedia.Release(r);r:Remove();table.remove(s.entries,i)end end
     ZCChatMedia.ReflowChains(chat)
    end)
   end
  end
 end
 for n,p in pairs(G.pending)do if RealTime()-p.at>10 then
  G.pending[n]=nil;local s=chat.ZCThreads[p.key];if s then s.pending=nil end;T.Status(chat,"Delivery was not confirmed. Your draft is saved.")
 end end
end
