if not CLIENT then return end
local S=ZCScoreboard
local H,K=S.Services,S.Skin
local u=H.Scale
-- Live speaking level for a row's mic cell (2026-09-25): 0 while silent, muted, or hidden by the voice identity rule
-- (hg.CanIdentifyVoicePanel, the same gate the voice orbs use), else the smoothed VoiceVolume. Your own volume is
-- reported as 0 by the engine without voice_loopback, so the local player shows a steady half level.
local function speakLevel(p,ply,muted)
 local raw=0
 if not muted and IsValid(ply) and ply:IsSpeaking() and hg and isfunction(hg.CanIdentifyVoicePanel) and hg.CanIdentifyVoicePanel(ply)==true then
  raw=ply==LocalPlayer() and 0.5 or math.Clamp(ply:VoiceVolume()*1.5+0.2,0.2,1)
 end
 local s=p.SpeakLevelPly==ply and p.SpeakLevel or 0 -- rows are recycled between players on resort: never inherit a level
 s=s+(raw-s)*math.Clamp(FrameTime()*(raw>s and 16 or 6),0,1)
 p.SpeakLevel,p.SpeakLevelPly=s,ply
 return s
end
local speakTint=Color(90,210,130,60)
local function columns(w)return w-u(326),w-u(220),w-u(150),w-u(48)end
function S.Context(p)
 if not IsValid(p)then return end
 local menu=DermaMenu()
 menu:AddOption("Copy SteamID",function()if IsValid(p)then SetClipboardText(H.SteamID(p))end end)
 menu:AddOption("Copy SteamID64",function()if IsValid(p)then SetClipboardText(H.SteamID64(p))end end)
 if H.Bool("enable_profile_button",true)then
  menu:AddOption("Steam profile",function()if IsValid(p)then gui.OpenURL("https://steamcommunity.com/profiles/"..H.SteamID64(p))end end)
 end
 if H.VoiceAllowed(p) and H.Bool("show_voice_buttons",true)then menu:AddOption("Voice controls",function()H.Voice(p)end)end
 H.Staff(menu,p)
 if LocalPlayer():IsAdmin()then
  local sub=menu:AddSubMenu("ZCity tools")
  for key,prop in SortedPairsByMemberValue(properties.List or {},"Order")do
   local ok,allowed=pcall(function()return prop.Filter and prop:Filter(p,LocalPlayer())end)
   if ok and allowed then
    local tr={Entity=p,HitPos=p:WorldSpaceCenter(),Hit=true,HitNonWorld=true}
    local item=sub:AddOption(prop.MenuLabel and language.GetPhrase(prop.MenuLabel)or key,function()
     if IsValid(p) and prop.Action then local ok,err=pcall(prop.Action,prop,p,tr);if not ok then ErrorNoHalt("[GoobOS roster] "..tostring(err).."\n")end end
    end)
    if prop.MenuIcon then item:SetImage(prop.MenuIcon)end
    if prop.MenuOpen then local ok,err=pcall(prop.MenuOpen,prop,item,p,tr);if not ok then ErrorNoHalt("[GoobOS roster] "..tostring(err).."\n")end end
   end
  end
 end
 menu:Open()
end

local function createRow(parent,data)
 local row=vgui.Create("DButton",parent);row:SetText("");row:SetTall(u(82));row:Dock(TOP);row:DockMargin(0,0,u(5),u(6));row.Player=data.entity
 row.Paint=function(p,w,h)
  K.Card(w,h,K.Hover(p),p.Player==LocalPlayer())
  if p.Player==LocalPlayer()then K.Text("YOU","Label",u(18),h-u(15),K.Colors().accent)end
 end
 row.Avatar=vgui.Create(data.bot and "DPanel" or "AvatarImage",row);row.Avatar:SetSize(u(42),u(42));row.Avatar:SetMouseInputEnabled(false)
 if data.bot then row.Avatar.Paint=function(_,w,h)H.BotAvatar(w,h,row.Data and row.Data.name or data.name)return true end else row.Avatar:SetPlayer(data.entity,64)end
 row.Name=K.Label(row,"Name",data.name);row.Detail=K.Label(row,"Label","",K.Colors().muted)
 row.Stats={}
 for _,title in ipairs({"Public karma","Ping","Playtime","Session"})do
  row.Stats[#row.Stats+1]={title=K.Label(row,"Label",title,K.Colors().muted),value=K.Label(row,"Body","")}
 end
 row.Stats[1].value:SetFont("ZCRoster.Number")
 row.Stats[3].value:SetTooltip("Total playtime");row.Stats[4].value:SetTooltip("Current connection")
 row.Stats[4].value:SetFont("ZCRoster.Label");row.Stats[4].value:SetTextColor(K.Colors().muted)
 row.Voice=K.Button(row,"",function()H.Voice(row.Player)end)
 row.Voice:SetTooltip("Voice volume and mute")
 row.Voice.Paint=function(p,w,h)
  local c=K.Colors();draw.RoundedBox(4,0,0,w,h,K.Mix(K.Hover(p),c.soft,c.hover))
  local muted=H.Muted(row.Player)or row.Player:IsMuted()
  local level=speakLevel(p,row.Player,muted)
  if level>0.01 then speakTint.a=40+math.floor(120*level);draw.RoundedBox(4,0,0,w,h,speakTint) end
  K.Speaker(w*.25,h*.25,w*.5,muted)
 end
 row.DoClick=function()S.Context(row.Player)end;row.DoRightClick=row.DoClick
 row.PerformLayout=function(p,w,h)
  local karma,ping,time,voice=columns(w)
  p.Avatar:SetPos(u(16),u(15));p.Name:SetPos(u(76),u(17));p.Name:SetSize(math.max(u(40),karma-u(95)),u(25))
  p.Detail:SetPos(u(76),u(44));p.Detail:SetSize(p.Name:GetWide(),u(19))
  local xs={karma,ping,time,time};local ys={u(26),u(29),u(18),u(44)};local ws={u(86),u(72),u(94),u(94)}
  for i,item in ipairs(p.Stats)do item.title:SetPos(xs[i],ys[i]);item.value:SetPos(xs[i],ys[i]);item.value:SetSize(ws[i],u(i==4 and 18 or 25))end
  p.Voice:SetPos(voice,(h-u(32))/2);p.Voice:SetSize(u(32),u(32))
 end
 return row
end
local function updateRow(row,data,index)
 row.Data=data
 if row.Order~=index then row.Order=index;row:SetZPos(index)end
 K.SetText(row.Name,data.name);row.Name:SetTooltip(data.name)
 local detail={}
 if H.Bool("show_ulx_ranks",true)then detail[#detail+1]=data.rank end
 if data.character~=""and data.character~=data.name then detail[#detail+1]=data.character end
 if data.spectator then detail[#detail+1]="Spectating"end
 K.SetText(row.Detail,table.concat(detail,"  /  "));row.Detail:SetTooltip(row.Detail:GetText())
 local values={S.PublicKarmaText(data.karma),tostring(data.ping).." ms",data.playtime or"—",data.session.." session"}
 K.SetText(row.Stats[1].title,data.entity==LocalPlayer()and"Your karma"or"Public karma")
 local visible={H.Bool("show_karma",true),true,H.Bool("show_playtime",true),H.Bool("show_session",true)}
 for i,item in ipairs(row.Stats)do item.title:SetVisible(false);item.value:SetVisible(visible[i]);K.SetText(item.value,values[i])end
 row.Stats[1].value:SetTooltip(data.entity==LocalPlayer()and"Your current karma"or"Public karma; hidden-round changes settle later. This is not proof of guilt.")
 local voice=H.Bool("show_voice_buttons",true)and H.VoiceAllowed(data.entity)
 row.Voice:SetVisible(voice)
end
local function section(parent,height)
 local p=vgui.Create("DPanel",parent);p:Dock(TOP);p:SetTall(u(height));p:DockMargin(0,0,0,u(14));p:DockPadding(u(18),u(16),u(18),u(16))
 p.Paint=function(_,w,h)K.Card(w,h,false,false)end
 return p
end
local function buildSidebar(parent,width)
 local scroll=vgui.Create("DScrollPanel",parent);scroll:SetWide(width);scroll:Dock(RIGHT);scroll:DockMargin(u(18),0,0,0);K.Scrollbar(scroll)
 local round=section(scroll,270)
 local heading=K.Label(round,"Label","ROUND",K.Colors().accent);heading:Dock(TOP);heading:SetTall(u(23))
 local mode=K.Label(round,"Title","");mode:Dock(TOP);mode:SetTall(u(38));mode:SetWrap(true)
 local state=K.Label(round,"Label","",K.Colors().muted);state:Dock(TOP);state:SetTall(u(24))
 local clock=K.Label(round,"Hero","");clock:Dock(TOP);clock:SetTall(u(59));clock:SetWrap(true)
 local mutationHead=K.Label(round,"Label","MUTATION",K.Colors().muted);mutationHead:Dock(TOP);mutationHead:DockMargin(0,u(9),0,0);mutationHead:SetTall(u(23))
 local mutation=K.Label(round,"Body","");mutation:Dock(TOP);mutation:SetTall(u(38));mutation:SetWrap(true)
 local self=section(scroll,164)
 local selfTitle=K.Label(self,"Label","YOUR KARMA",K.Colors().accent);selfTitle:Dock(TOP);selfTitle:SetTall(u(24))
 local karma=K.Label(self,"Hero","");karma:Dock(TOP);karma:SetTall(u(47))
 local health=K.Label(self,"Body","");health:Dock(TOP);health:SetTall(u(49));health:SetWrap(true)
 local linkCount=(H.Bool("command_1_enabled",true)and 1 or 0)+(H.Bool("command_2_enabled",true)and 1 or 0)
 local links=section(scroll,60+linkCount*39);links:SetVisible(linkCount>0);local linkTitle=K.Label(links,"Label","QUICK LINKS",K.Colors().muted);linkTitle:Dock(TOP);linkTitle:SetTall(u(27))
 for i=1,2 do if H.Bool("command_"..i.."_enabled",true)then
  local command=H.String("command_"..i.."_say",i==1 and"!store"or"!motd")
  local b=K.Button(links,H.String("command_"..i.."_text",i==1 and"Store"or"Guide"),function()RunConsoleCommand("say",command)end)
  b:Dock(TOP);b:SetTall(u(32));b:DockMargin(0,0,0,u(7))
 end end
 local note=K.Label(scroll,"Label","@message → staff",K.Colors().muted);note:Dock(TOP);note:SetTall(u(24));note:SetTooltip("Start a chat message with @ to contact staff.")
 function scroll:UpdatePublicInfo()
  local raw=zb.CROUND or"Lobby";local name=tostring(raw):gsub("_"," "):gsub("^%l",string.upper)
  K.SetText(mode,name);mode:SetTooltip(name)
  K.SetText(state,H.RoundState():upper())
  local time=H.Clock();K.SetText(clock,time);clock:SetTooltip(time)
  clock:SetFont(#time>12 and"ZCRoster.Title"or"ZCRoster.Hero")
  local title=GetGlobalString("PATSB_MutationTitle","None");K.SetText(mutation,title);mutation:SetTooltip(title)
  local own=ZCScoreboardSelfView and ZCScoreboardSelfView.Get()
  K.SetText(karma,own and own.karma and tostring(math.floor(own.karma))or"Syncing…")
  local text="No active karma penalty"
  if not own then text="Waiting for your private status"
  elseif own.seizureActive then text="Karma seizure active"
  elseif own.lowKarmaBrainRisk then text="Low-karma brain risk"
  elseif own.seizureRisk then text="Low-karma seizure risk"
  elseif own.brainInjury then text="Existing brain injury"end
  K.SetText(health,text);health:SetTextColor(own and(own.seizureActive or own.seizureRisk or own.lowKarmaBrainRisk)and K.Colors().warm or K.Colors().muted)
  health:SetTooltip(ZCScoreboardSelfView and ZCScoreboardSelfView.Text()or text)
 end
 return scroll
end
local function buildLegacyView()
 K.Fonts()
 local frame=vgui.Create("DFrame");S.Frame=frame;H.SetFrame(frame)
 frame:SetSize(math.min(ScrW()-u(48),u(H.Int("frame_width",1500))),math.min(ScrH()-u(48),u(H.Int("frame_height",900))))
 frame:SetPos((ScrW()-frame:GetWide())/2,math.max(116,(ScrH()-frame:GetTall())/2));frame:SetTitle("");frame:ShowCloseButton(false);frame:SetDraggable(false);frame:MakePopup();frame:SetKeyboardInputEnabled(false)
 frame:DockPadding(u(24),u(105),u(24),u(18))
 frame.Paint=function(p,w,h)
  H.Blur(p,100);local c=K.Colors();draw.RoundedBox(6,0,0,w,h,c.bg)
  draw.RoundedBox(6,0,0,w,u(84),c.panel)
  K.Text("Roster","Title",u(24),u(17),c.white)
  K.Text("PLAYERS & CONNECTIONS","Label",u(25),u(49),c.muted)
  K.Text("[GoobOS]","Title",w*.5,u(29),c.accent,TEXT_ALIGN_CENTER)
  K.Text(p.Summary or"","Label",w-u(78),u(35),c.muted,TEXT_ALIGN_RIGHT)
  surface.SetDrawColor(c.line);surface.DrawRect(u(24),u(83),w-u(48),1)
 end
 local close=K.Button(frame,"×",S.Close);close:SetTooltip("Close scoreboard");close:SetSize(u(36),u(34))
 frame.PerformLayout=function(_,w)close:SetPos(w-u(60),u(23))end
 local footer=vgui.Create("DPanel",frame);footer:Dock(BOTTOM);footer:SetTall(u(76));footer:DockMargin(0,u(14),0,0);footer.Paint=function()end
 local note=K.Label(footer,"Label","Others show public karma · hidden-round changes settle later",K.Colors().muted)
 note:Dock(TOP);note:SetTall(u(29));note:SetTooltip("Public karma is not proof of guilt or permission to attack. Your private score appears in Your status.")
 local actions=vgui.Create("DPanel",footer);actions:Dock(FILL);actions.Paint=function()end
 local function action(text,fn,width)local b=K.Button(actions,text,fn);b:Dock(LEFT);b:SetWide(u(width or 120));b:DockMargin(0,0,u(8),0);return b end
 if H.Bool("show_bottom_mute_buttons",true)then
  local all;all=action(hg.muteall and"Unmute all"or"Mute all",function()hg.muteall=not hg.muteall;for _,p in ipairs(player.GetAll())do H.ApplyVoice(p)end;all.Caption=hg.muteall and"Unmute all"or"Mute all"end)
  all.Selected=function()return hg.muteall end
  local specs;specs=action(hg.mutespect and"Unmute spectators"or"Mute spectators",function()hg.mutespect=not hg.mutespect;for _,p in ipairs(player.GetAll())do H.ApplyVoice(p)end;specs.Caption=hg.mutespect and"Unmute spectators"or"Mute spectators"end,160)
  specs.Selected=function()return hg.mutespect end
 end
 if H.Bool("show_team_button",true)then action(LocalPlayer():Team()==TEAM_SPECTATOR and"Join game"or"Spectate",function()
  net.Start("ZB_SpecMode");net.WriteBool(LocalPlayer():Team()~=TEAM_SPECTATOR);net.SendToServer();S.Close()
 end)end
 if LocalPlayer():IsAdmin()then action("Admin settings",H.Settings,135)end
 local sidebarWidth=math.Clamp(frame:GetWide()*H.Float("sidebar_width_frac",.24),u(H.Int("sidebar_width_min",220)),u(H.Int("sidebar_width_max",420)))
 local sidebar=buildSidebar(frame,math.min(frame:GetWide()*.29,sidebarWidth))
 local main=vgui.Create("DPanel",frame);main:Dock(FILL);main.Paint=function()end
 local toolbar=vgui.Create("DPanel",main);toolbar:Dock(TOP);toolbar:SetTall(u(48));toolbar.Paint=function()end
 local sort=vgui.Create("DComboBox",toolbar);sort:Dock(RIGHT);sort:SetWide(u(134));sort:DockMargin(u(12),0,0,u(10));sort:SetFont("ZCRoster.Body")
 for _,item in ipairs({{"Name","name"},{"Playtime","playtime"},{"Ping","ping"}})do sort:AddChoice(item[1],item[2],(S.State.sort or"name")==item[2])end
 sort.OnSelect=function(_,_,_,value)S.State.sort=value;frame.NextPoll=0 end
 sort.Paint=function(p,w,h)K.Card(w,h,p:IsHovered(),false)end;sort:SetTextColor(K.Colors().text)
 local clear=K.Button(toolbar,"×",function(button)if IsValid(frame.Search)then frame.Search:SetText("");button:SetVisible(false);S.State.query="";frame.NextPoll=0;frame.Search:RequestFocus()end end)
 clear:Dock(RIGHT);clear:SetWide(u(34));clear:DockMargin(u(8),0,0,u(10));clear:SetTooltip("Clear search");clear:SetVisible((S.State.query or"")~="")
 local search=vgui.Create("DTextEntry",toolbar);frame.Search=search;search:Dock(FILL);search:DockMargin(0,0,0,u(10));search:SetFont("ZCRoster.Body");search:SetPlaceholderText("Search players…");search:SetText(S.State.query or"");search:SetUpdateOnType(true)
 search.Paint=function(p,w,h)
  K.Card(w,h,false,p:HasFocus());p:DrawTextEntryText(K.Colors().text,K.Colors().accent,K.Colors().text)
  if p:GetValue()==""and not p:HasFocus()then K.Text("Search players…","Body",u(12),h/2,K.Colors().muted,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)end
 end
 search.OnValueChange=function(_,value)S.State.query=value;clear:SetVisible(value~="");frame.NextPoll=0 end
 search.OnGetFocus=function()frame:SetKeyboardInputEnabled(true)end
 search.OnLoseFocus=function()if IsValid(frame)then frame:SetKeyboardInputEnabled(false)end end
 search.OnKeyCodeTyped=function(p,key)if key==KEY_ESCAPE or key==KEY_TAB then S.Close()elseif key==KEY_ENTER then p:KillFocus()end end
 local tabs=vgui.Create("DPanel",main);tabs:Dock(TOP);tabs:SetTall(u(45));tabs.Paint=function()end
 local tabButtons={}
 for _,item in ipairs({{"Everyone","all"},{"Playing","players"},{"Spectating","spectators"}})do
  local name,key=item[1],item[2]
  if key~="spectators"or H.Bool("show_spectators",true)then
   local b=K.Button(tabs,name,function()S.State.filter=key;frame.NextPoll=0 end);b:Dock(LEFT);b:SetWide(u(148));b:DockMargin(0,0,u(8),u(8))
   b.Selected=function()return(S.State.filter or"all")==key end;tabButtons[key]={button=b,name=name}
  end
 end
 local headers=vgui.Create("DPanel",main);headers:Dock(TOP);headers:SetTall(u(28))
 headers.Paint=function(_,w,h)
  local karma,ping,time=columns(IsValid(frame.List)and frame.List:GetCanvas():GetWide()-u(5)or w-u(15));local c=K.Colors()
  K.Text("PLAYER","Label",u(16),u(5),c.muted)
  if H.Bool("show_karma",true)then K.Text("KARMA","Label",karma,u(5),c.muted)end
  K.Text("PING","Label",ping,u(5),c.muted)
  if H.Bool("show_session",true)or H.Bool("show_playtime",true)then K.Text("TIME","Label",time,u(5),c.muted)end
 end
 local list=vgui.Create("DScrollPanel",main);list:Dock(FILL);frame.List=list;frame.Rows={}
 K.Scrollbar(list)
 local empty=K.Label(main,"Body","No matching players",K.Colors().muted);empty:SetVisible(false);empty:SetSize(u(320),u(32));empty:SetPos(u(16),u(138))
 function frame:PollRoster()
  local source={};local counts={all=0,players=0,spectators=0}
  for _,p in ipairs(player.GetAll())do local data=S.ReadPlayer(p);if data then source[#source+1]=data;counts.all=counts.all+1;local key=data.spectator and"spectators"or"players";counts[key]=counts[key]+1 end end
  local rows=S.SelectRows(source,S.State.query,S.State.filter or"all",S.State.sort or"name")
  S.Reconcile(rows,self.Rows,function(data)return createRow(list,data)end,updateRow,function(row)if IsValid(row)then row:Remove()end end)
  empty:SetVisible(#rows==0)
  for key,item in pairs(tabButtons)do item.button.Caption=item.name.."  "..counts[key]end
  local summary=counts.all.." connected"
  if H.Bool("show_tickrate",true)then local dt=engine.ServerFrameTime();if dt>0 then summary=summary.."  /  "..math.Round(1/dt).." tick"end end
  self.Summary=summary;sidebar:UpdatePublicInfo()
 end
 frame.Think=function(p)if(p.NextPoll or 0)<=RealTime()then p.NextPoll=RealTime()+math.Clamp(H.Float("refresh_interval",1),.25,5);p:PollRoster()end end
 frame.OnKeyCodePressed=function(_,key)if key==KEY_ESCAPE or key==KEY_TAB then S.Close()end end
 frame.OnRemove=function()if S.Frame==frame then S.Frame=nil;H.SetFrame(nil)end end
 frame:PollRoster()
 timer.Simple(0,function()if IsValid(list)then list:InvalidateLayout(true);list:GetVBar():SetScroll(S.State.scroll or 0)end end)
 return frame
end

-- =================================================================================================
-- Kit view (GoobOS rework, Phase 4): rebuilt on ZCGoobApps.Kit, behind zc_goobos_scoreboard=1 with
-- the kit mounted (see S.BuildView below). Same data and actions as buildLegacyView above; only the
-- chrome differs. Target: mockups/10_scoreboard.html.
local KK = S.KitSkin
local KIT_ROW_H, KIT_HEADER_H = 56, 30
-- Column boxes, right to left, that never overlap (owner 2026-09-24: karma, ping, voice and playtime clipped
-- through each other - columns() put the karma box 22 units under the ping box and the time box under the mic
-- and past the row edge). Pixel x/width pairs; ping and time are right-aligned in their boxes and the header
-- labels sit on the same edges as the values.
local function kitColumns(w)
    local voiceW, timeW, pingW, karmaW = u(28), u(150), u(58), u(78)
    local voiceX = w - u(16) - voiceW
    local timeX = voiceX - u(10) - timeW
    local pingX = timeX - u(12) - pingW
    local karmaX = pingX - u(14) - karmaW
    return karmaX, karmaW, pingX, pingW, timeX, timeW, voiceX, voiceW
end

local function createKitHeader(parent)
    local p = vgui.Create("DPanel", parent)
    p:SetTall(u(KIT_HEADER_H))
    p:Dock(TOP)
    p:DockMargin(u(8), u(6), u(8), u(2))
    p.Paint = function(s, w, h)
        local T2 = ZCGoobApps.Theme
        surface.SetDrawColor(T2.accent)
        surface.DrawRect(u(6), h / 2 - 1, u(14), 2)
        ZCGoobApps.Kit.Text(ZCGoobApps.Kit.Fit(s.Label or "", ZCGoobApps.Kit.Font(12, 700), w - u(40)), 12, 700, u(28), h / 2, T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return p
end

local function updateKitHeader(head, label, count)
    head.Label = string.upper(label) .. "  ·  " .. tostring(count)
end

local function createKitRow(parent)
    local row = vgui.Create("DButton", parent)
    row:SetText("")
    row:SetTall(u(KIT_ROW_H))
    row:Dock(TOP)
    row:DockMargin(u(6), 0, u(6), u(8))
    row.DoClick = function() S.Context(row.Player) end
    row.DoRightClick = row.DoClick
    row.Paint = function(p, w, h)
        local K2, T2 = ZCGoobApps.Kit, ZCGoobApps.Theme
        local you = p.Player == LocalPlayer()
        local hover = K2.Hover(p)
        if you then
            K2.Card(0, 0, w, h, K2.Alpha(T2.main, 22))
            surface.SetDrawColor(T2.main)
            surface.DrawRect(0, 0, 3, h)
        elseif hover > 0.01 then
            K2.Card(0, 0, w, h, K2.Alpha(T2.white, 6 + 8 * hover))
        end
    end
    local K2, T2 = ZCGoobApps.Kit, ZCGoobApps.Theme
    row.Avatar = K2.Avatar(row, u(36))
    local function label(size, weight, color, align)
        local l = vgui.Create("DLabel", row)
        l:SetText("")
        l:SetFont(K2.Font(size, weight))
        l:SetTextColor(color)
        if align then l:SetContentAlignment(align) end
        return l
    end
    row.Name = label(18, 600, T2.text)
    row.Detail = label(12, 500, T2.muted)
    row.KarmaValue = label(14, 500, T2.text, 4)
    row.KarmaBar = K2.Bar(row, 0, T2.main)
    row.Ping = label(15, 600, T2.text, 6)
    row.Time = label(13, 500, T2.text, 6)
    row.Voice = vgui.Create("DButton", row)
    row.Voice:SetText("")
    row.Voice:SetTooltip("Voice volume and mute")
    row.Voice.DoClick = function() H.Voice(row.Player) end
    row.Voice.Paint = function(p, w, h)
        local muted = IsValid(row.Player) and (H.Muted(row.Player) or row.Player:IsMuted())
        local hover = K2.Hover(p)
        if hover > 0.01 then K2.Card(0, 0, w, h, K2.Alpha(T2.white, 10 * hover)) end
        local level = speakLevel(p, row.Player, muted)
        if level > 0.01 then K2.Card(0, 0, w, h, K2.Alpha(T2.green or T2.text, 30 + 110 * level)) end
        K2.Glyph("mic", w / 2, h / 2, u(15), muted and T2.red or (level > 0.01 and T2.text or T2.muted))
    end
    row.PerformLayout = function(p, w, h)
        local karmaX, karmaW, pingX, pingW, timeX, timeW, voiceX, voiceW = kitColumns(w)
        p.Avatar:SetPos(u(10), (h - u(36)) / 2)
        local nameW = math.max(u(40), karmaX - u(66))
        p.Name:SetPos(u(56), u(7)); p.Name:SetSize(nameW, u(22))
        p.Detail:SetPos(u(56), u(31)); p.Detail:SetSize(nameW, u(18))
        p.KarmaValue:SetPos(karmaX, u(9)); p.KarmaValue:SetSize(karmaW, u(18))
        p.KarmaBar:SetPos(karmaX, u(30)); p.KarmaBar:SetSize(karmaW, u(6))
        p.Ping:SetPos(pingX, u(18)); p.Ping:SetSize(pingW, u(20))
        p.Time:SetPos(timeX, u(18)); p.Time:SetSize(timeW, u(20))
        p.Voice:SetPos(voiceX, (h - voiceW) / 2); p.Voice:SetSize(voiceW, voiceW)
    end
    return row
end

local function updateKitRow(row, data)
    row.Player = data.entity
    local K2, T2 = ZCGoobApps.Kit, ZCGoobApps.Theme
    row.Avatar:SetPlayer(data.entity)
    local _, _, ring = KK.TeamInfo(data)
    row.Avatar.Ring = ring
    row.Name:SetText(K2.Fit(data.name, row.Name:GetFont(), u(220)))
    row.Name:SetTooltip(data.name)
    local detail = {}
    if H.Bool("show_ulx_ranks", true) then detail[#detail + 1] = data.rank end
    if data.character ~= "" and data.character ~= data.name then detail[#detail + 1] = data.character end
    if data.spectator then detail[#detail + 1] = "Spectating" end
    local detailText = table.concat(detail, "  /  ")
    row.Detail:SetText(K2.Fit(detailText, row.Detail:GetFont(), u(220)))
    row.Detail:SetTooltip(detailText)
    local showKarma = H.Bool("show_karma", true)
    row.KarmaValue:SetVisible(showKarma)
    row.KarmaValue:SetText(S.PublicKarmaText(data.karma))
    row.KarmaValue:SetTooltip(data.entity == LocalPlayer() and "Your current karma" or "Public karma; hidden-round changes settle later. This is not proof of guilt.")
    local hasKarma = showKarma and isnumber(data.karma)
    row.KarmaBar:SetVisible(hasKarma)
    if hasKarma then row.KarmaBar:SetFraction(math.Clamp(data.karma, 0, 100) / 100) end
    row.Ping:SetText(tostring(data.ping) .. " ms")
    row.Ping:SetTextColor(KK.PingColor(T2, data.ping))
    local showTime = H.Bool("show_playtime", true) or H.Bool("show_session", true)
    row.Time:SetVisible(showTime)
    local timeParts = {}
    if H.Bool("show_playtime", true) then timeParts[#timeParts + 1] = data.playtime or "—" end
    if H.Bool("show_session", true) then timeParts[#timeParts + 1] = data.session end
    row.Time:SetText(table.concat(timeParts, "  ·  "))
    local voice = H.Bool("show_voice_buttons", true) and H.VoiceAllowed(data.entity)
    row.Voice:SetVisible(voice)
end

-- Poll + reconcile: rows are only created/removed when the underlying player set changes (S.Reconcile's
-- identity rule below), same as buildLegacyView's PollRoster. Team headers are pooled the same way.
local function kitPollRoster(frame, list)
    local source, counts = {}, {all = 0, players = 0, spectators = 0}
    for _, p in ipairs(player.GetAll()) do
        local data = S.ReadPlayer(p)
        if data then
            source[#source + 1] = data
            counts.all = counts.all + 1
            local key = data.spectator and "spectators" or "players"
            counts[key] = counts[key] + 1
        end
    end
    local rows = S.SelectRows(source, S.State.query, S.State.filter or "all", S.State.sort or "name")
    local order, groups = {}, {}
    for _, data in ipairs(rows) do
        local key, groupLabel = KK.TeamInfo(data)
        if not groups[key] then
            groups[key] = {label = groupLabel, rows = {}}
            order[#order + 1] = key
        end
        local g = groups[key]
        g.rows[#g.rows + 1] = data
    end
    for i, key in ipairs(order) do
        if key == "spectators" then
            table.remove(order, i)
            order[#order + 1] = key
            break
        end
    end
    frame.KitHeaders = frame.KitHeaders or {}
    local zpos, headerIndex, seen = 0, 0, {}
    for _, key in ipairs(order) do
        local g = groups[key]
        headerIndex = headerIndex + 1
        zpos = zpos + 1
        local head = frame.KitHeaders[headerIndex]
        if not head then
            head = createKitHeader(list)
            frame.KitHeaders[headerIndex] = head
        end
        head:SetVisible(true)
        head:SetZPos(zpos)
        updateKitHeader(head, g.label, #g.rows)
        for _, data in ipairs(g.rows) do
            zpos = zpos + 1
            local row = frame.Rows[data.entity]
            if row and row.joinID ~= data.id then
                row:Remove()
                frame.Rows[data.entity] = nil
                row = nil
            end
            if not row then
                row = createKitRow(list)
                row.joinID = data.id
                frame.Rows[data.entity] = row
            end
            row:SetZPos(zpos)
            updateKitRow(row, data)
            seen[data.entity] = true
        end
    end
    for i = headerIndex + 1, #frame.KitHeaders do
        frame.KitHeaders[i]:SetVisible(false)
    end
    for entity, row in pairs(frame.Rows) do
        if not seen[entity] then
            row:Remove()
            frame.Rows[entity] = nil
        end
    end
    return rows, counts
end

local function buildKitSidebar(parent, width)
    local K2, T2 = ZCGoobApps.Kit, ZCGoobApps.Theme
    local scroll = vgui.Create("DScrollPanel", parent)
    scroll:SetWide(width)
    scroll:Dock(RIGHT)
    scroll:DockMargin(u(14), u(10), 0, u(10))
    KK.Scrollbar(scroll, T2)
    local function card(height)
        local c = vgui.Create("DPanel", scroll)
        c:Dock(TOP)
        c:SetTall(u(height))
        c:DockMargin(0, 0, 0, u(10))
        c:DockPadding(u(12), u(10), u(12), u(10))
        c.Paint = function(_, w, h) K2.Card(0, 0, w, h, K2.Alpha(T2.white, 6)) end
        return c
    end
    local function heading(host, text)
        local l = vgui.Create("DLabel", host)
        l:SetText(string.upper(text))
        l:SetFont(K2.Font(12, 600))
        l:SetTextColor(T2.gold)
        l:Dock(TOP)
        l:SetTall(u(20))
        return l
    end
    local round = card(122)
    heading(round, "Round")
    local mode = vgui.Create("DLabel", round); mode:SetFont(K2.Font(14, 600)); mode:SetTextColor(T2.text); mode:Dock(TOP); mode:SetTall(u(22))
    local state = vgui.Create("DLabel", round); state:SetFont(K2.Font(12, 500)); state:SetTextColor(T2.muted); state:Dock(TOP); state:SetTall(u(20))
    local clock = vgui.Create("DLabel", round); clock:SetFont(K2.Font(20, 700)); clock:SetTextColor(T2.text); clock:Dock(TOP); clock:SetTall(u(30))
    local mutationCard = card(66)
    heading(mutationCard, "Mutation")
    local mutation = vgui.Create("DLabel", mutationCard); mutation:SetFont(K2.Font(13, 500)); mutation:SetTextColor(T2.muted); mutation:Dock(TOP); mutation:SetTall(u(36)); mutation:SetWrap(true)
    local selfCard = card(98)
    heading(selfCard, "Your karma")
    local karma = vgui.Create("DLabel", selfCard); karma:SetFont(K2.Font(24, 700)); karma:SetTextColor(T2.text); karma:Dock(TOP); karma:SetTall(u(30))
    local health = vgui.Create("DLabel", selfCard); health:SetFont(K2.Font(12, 500)); health:SetTextColor(T2.green); health:Dock(TOP); health:SetTall(u(36)); health:SetWrap(true)
    local linkCount = (H.Bool("command_1_enabled", true) and 1 or 0) + (H.Bool("command_2_enabled", true) and 1 or 0)
    local links = card(30 + linkCount * 36)
    links:SetVisible(linkCount > 0)
    heading(links, "Quick links")
    for i = 1, 2 do
        if H.Bool("command_" .. i .. "_enabled", true) then
            local text = H.String("command_" .. i .. "_text", i == 1 and "Store" or "Guide")
            local say = H.String("command_" .. i .. "_say", i == 1 and "!store" or "!motd")
            local b = vgui.Create("DButton", links)
            b:SetText("")
            b:Dock(TOP); b:SetTall(u(30)); b:DockMargin(0, 0, 0, u(6))
            b.DoClick = function() RunConsoleCommand("say", say) end
            b.Paint = function(p, w, h)
                local hover = K2.Hover(p)
                K2.Card(0, 0, w, h, T2.card)
                if hover > 0.01 then K2.Card(0, 0, w, h, K2.Alpha(T2.white, 10 * hover)) end
                K2.Text(text, 13, 500, w / 2, h / 2, T2.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end
    local note = vgui.Create("DLabel", scroll)
    note:SetText("@message  →  sends to online staff")
    note:SetFont(K2.Font(12, 500))
    note:SetTextColor(T2.muted)
    note:Dock(TOP)
    note:SetTall(u(30))
    note:SetTooltip("Start a chat message with @ to contact staff.")
    function scroll:UpdatePublicInfo()
        local raw = zb.CROUND or "Lobby"
        local name = tostring(raw):gsub("_", " "):gsub("^%l", string.upper)
        mode:SetText(name); mode:SetTooltip(name)
        state:SetText(string.upper(H.RoundState()))
        local time = H.Clock()
        clock:SetText(time); clock:SetTooltip(time)
        local title = GetGlobalString("PATSB_MutationTitle", "None")
        mutation:SetText(title); mutation:SetTooltip(title)
        local own = ZCScoreboardSelfView and ZCScoreboardSelfView.Get()
        karma:SetText(own and own.karma and tostring(math.floor(own.karma)) or "Syncing…")
        local text = "No active karma penalty"
        if not own then text = "Waiting for your private status"
        elseif own.seizureActive then text = "Karma seizure active"
        elseif own.lowKarmaBrainRisk then text = "Low-karma brain risk"
        elseif own.seizureRisk then text = "Low-karma seizure risk"
        elseif own.brainInjury then text = "Existing brain injury" end
        health:SetText(text)
        health:SetTextColor((own and (own.seizureActive or own.seizureRisk or own.lowKarmaBrainRisk)) and T2.gold or T2.muted)
        health:SetTooltip(ZCScoreboardSelfView and ZCScoreboardSelfView.Text() or text)
    end
    return scroll
end

-- prevote_sb_20260925 (owner 2026-09-25: "Add the map pre-vote menu to the bottom right of the scoreboard"). The state
-- is the round-end panel's (lua/zc_goobos/roundend.lua RE.Prevote: its receiver is the only one for zc_map_prevote_state,
-- a second net.Receive would replace it); this card asks and casts through RE.PrevoteAsk / RE.PrevoteCast. Server rules
-- (lua/autorun/server/zc_map_prevote.lua): anyone may vote, one pick per round, one message a second, never the current
-- map. The list is ONE painted panel over the whole pool (up to 400 maps; a button per map would hitch every Tab),
-- ranked picks first with their counts, then the pool A-Z. Without the round-end module there is no card.
local function prevoteName(map)
    local M = rawget(_G, "SolidMapVote")
    if istable(M) and isfunction(M.GetMapConfigInfo) then
        local ok, info = pcall(M.GetMapConfigInfo, map)
        if ok and istable(info) and isstring(info.displayname) and info.displayname ~= "" then return info.displayname end
    end
    return (string.gsub(map, "_", " "))
end
local function buildKitPrevote(parent, frameH)
    local A = rawget(_G, "ZCGoobApps")
    local RE = A and A.RoundEnd
    if not (istable(RE) and isfunction(RE.PrevoteCast) and isfunction(RE.PrevoteAsk)) then return nil end
    local K2, T2 = ZCGoobApps.Kit, ZCGoobApps.Theme
    local function ask()
        local zbT = rawget(_G, "zb")
        local round = istable(zbT) and zbT.ROUND_START or nil
        local pv = RE.Prevote
        -- no pool yet, or a new round (the server resets the one-pick limit at round start); at most every 5 s
        if (not pv or not pv.pool or RE.PrevoteAskRound ~= round) and RealTime() - (RE.PrevoteAskedAt or -60) >= 5 then RE.PrevoteAsk() end
    end
    ask()
    local card = vgui.Create("DPanel", parent)
    card:Dock(BOTTOM)
    card:SetTall(math.Clamp(math.floor((frameH - u(149)) * 0.42), u(190), u(300)))
    card:DockMargin(u(14), 0, 0, u(10))
    card:DockPadding(u(12), u(10), u(12), u(8))
    card.Paint = function(_, w, h) K2.Card(0, 0, w, h, K2.Alpha(T2.white, 6)) end
    card.Think = function(pnl) if (pnl.NextAsk or 0) <= RealTime() then pnl.NextAsk = RealTime() + 1 ask() end end
    local head = vgui.Create("DPanel", card)
    head:Dock(TOP)
    head:SetTall(u(40))
    head.Paint = function()
        K2.Text("MAP PRE-VOTE", 12, 600, 0, 0, T2.gold)
        K2.Text("Top picks seed the next map vote", 11, 500, 0, u(20), T2.muted)
    end
    local foot = vgui.Create("DPanel", card)
    foot:Dock(BOTTOM)
    foot:SetTall(u(20))
    local list = vgui.Create("DScrollPanel", card)
    list:Dock(FILL)
    KK.Scrollbar(list, T2)
    local canvas = vgui.Create("DPanel", list)
    canvas:Dock(TOP)
    canvas:SetCursor("hand")
    card.List, card.Canvas, card.Foot = list, canvas, foot
    local rowH, rows, key = u(24), {}, nil
    local current = string.lower(game.GetMap())
    local function refresh()
        local pv = RE.Prevote
        local k = pv and (tostring(pv.ranked) .. "|" .. tostring(pv.pool)) or "none"
        if k == key then return end
        key, rows = k, {}
        local seen = {}
        for _, r in ipairs(pv and pv.ranked or {}) do
            if isstring(r.map) and r.map ~= "" and not seen[r.map] then
                seen[r.map] = true
                rows[#rows + 1] = {map = r.map, name = prevoteName(r.map), count = tonumber(r.count) or 0, ranked = true}
            end
        end
        local rest = {}
        for _, m in ipairs(pv and pv.pool or {}) do
            if isstring(m) and m ~= "" and not seen[m] then seen[m] = true rest[#rest + 1] = {map = m, name = prevoteName(m)} end
        end
        table.sort(rest, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
        for _, r in ipairs(rest) do rows[#rows + 1] = r end
        for _, r in ipairs(rows) do r.current = string.lower(r.map) == current end
        card.Rows = rows
        canvas:SetTall(math.max(rowH, #rows * rowH))
        list:InvalidateLayout()
    end
    card.Refresh = refresh
    -- a pick is open only on this client's own state (the ask reply carries the pool) and before this round's pick
    local function open(pv) return pv ~= nil and pv.pool ~= nil and pv.canChange ~= false end
    canvas.Paint = function(pnl, w)
        refresh()
        local pv = RE.Prevote
        if #rows == 0 then
            K2.Text(pv and pv.pool and "No maps in the pool" or "Loading maps…", 12, 500, u(6), rowH / 2, T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end
        local mine, canPick = pv and pv.yourVote or "", open(pv)
        local hover
        if pnl:IsHovered() then local _, cy = pnl:CursorPos() hover = math.floor(cy / rowH) + 1 end
        local first = math.max(1, math.floor(list:GetVBar():GetScroll() / rowH) + 1)
        local last = math.min(#rows, first + math.ceil(list:GetTall() / rowH) + 1)
        local nameW = w - u(52)
        for i = first, last do
            local r, y = rows[i], (i - 1) * rowH
            local isMine = r.map == mine
            if isMine then K2.Card(0, y + 1, w, rowH - 2, K2.Alpha(T2.main, 70))
            elseif i == hover and canPick and not r.current then K2.Card(0, y + 1, w, rowH - 2, K2.Alpha(T2.white, 10)) end
            local weight = r.ranked and 600 or 500
            local label = r.current and (r.name .. "  (current)") or r.name
            K2.Text(K2.Fit(label, K2.Font(12, weight), nameW), 12, weight, u(8), y + rowH / 2, (r.ranked or isMine) and T2.text or T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if r.ranked then K2.Text(tostring(r.count), 12, 700, w - u(8), y + rowH / 2, T2.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        end
    end
    canvas.OnMousePressed = function(pnl, mc)
        if mc ~= MOUSE_LEFT then return end
        local pv = RE.Prevote
        if not open(pv) then return end
        refresh()
        local _, cy = pnl:CursorPos()
        local r = rows[math.floor(cy / rowH) + 1]
        if not r or r.current or r.map == pv.yourVote then return end
        RE.PrevoteCast(r.map)
        surface.PlaySound("ui/buttonclick.wav")
    end
    foot.Paint = function(_, w, h)
        local pv = RE.Prevote
        local mine = pv and pv.yourVote ~= "" and pv.yourVote or nil
        local text
        if not pv or not pv.pool then text = "Loading maps…"
        elseif pv.canChange == false then text = mine and ("Your pick: " .. prevoteName(mine) .. "  ·  locked until next round") or "Locked until next round"
        elseif mine then text = "Your pick: " .. prevoteName(mine) .. "  ·  one change per round"
        else text = "Click a map to vote  ·  one pick per round" end
        K2.Text(K2.Fit(text, K2.Font(11, 500), w), 11, 500, 0, h / 2, T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return card
end

local function buildKitView()
    local K2, T2 = ZCGoobApps.Kit, ZCGoobApps.Theme
    local frame = vgui.Create("DFrame")
    S.Frame = frame
    H.SetFrame(frame)
    local w = math.min(ScrW() - u(48), u(H.Int("frame_width", 1500)))
    local h = math.min(ScrH() - u(48), u(H.Int("frame_height", 900)))
    frame:SetSize(w, h)
    frame:SetPos((ScrW() - w) / 2, math.max(math.min(116, ScrH() - h - u(24)), u(24)))
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetDraggable(false)
    frame:MakePopup()
    frame:SetKeyboardInputEnabled(false)
    frame.Rows = {}
    frame:DockPadding(0, u(85), 0, 0)
    frame.Paint = function(s, ww, hh)
        H.Blur(s, 100)
        draw.RoundedBox(6, 0, 0, ww, hh, T2.bg)
        draw.RoundedBox(6, 0, 0, ww, u(84), T2.card)
        K2.Text("PLAYERS & CONNECTIONS", 12, 600, u(26), u(20), T2.gold)
        K2.Text("Roster", 24, 700, u(24), u(36), T2.text)
        K2.Text(s.Summary or "", 13, 500, s.RightEdge or (ww - u(250)), u(30), T2.muted, TEXT_ALIGN_RIGHT)
        surface.SetDrawColor(T2.hair or T2.line)
        surface.DrawRect(u(24), u(83), ww - u(48), 1)
    end
    local close = vgui.Create("DButton", frame)
    close:SetText("")
    close:SetSize(u(28), u(28))
    close.DoClick = S.Close
    close:SetTooltip("Close scoreboard")
    close.Paint = function(p, ww, hh)
        local hover = K2.Hover(p)
        if hover > 0.01 then K2.Card(0, 0, ww, hh, K2.Alpha(T2.white, 10 * hover)) end
        K2.Text("×", 18, 600, ww / 2, hh / 2, T2.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    local search = vgui.Create("DTextEntry", frame)
    frame.Search = search
    search:SetFont(K2.Font(14, 500))
    search:SetPlaceholderText("Search players…")
    search:SetText(S.State.query or "")
    search:SetUpdateOnType(true)
    search:SetSize(u(200), u(32))
    search.Paint = function(p, ww, hh)
        K2.Card(0, 0, ww, hh, T2.card, p:HasFocus() and T2.main or nil)
        p:DrawTextEntryText(T2.text, T2.main, T2.text)
        if p:GetValue() == "" and not p:HasFocus() then
            K2.Text("Search players…", 13, 500, u(10), hh / 2, T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    search.OnValueChange = function(_, value) S.State.query = value; frame.NextPoll = 0 end
    search.OnGetFocus = function() frame:SetKeyboardInputEnabled(true) end
    search.OnLoseFocus = function() if IsValid(frame) then frame:SetKeyboardInputEnabled(false) end end
    search.OnKeyCodeTyped = function(p, key) if key == KEY_ESCAPE or key == KEY_TAB then S.Close() elseif key == KEY_ENTER then p:KillFocus() end end
    local filterOptions, filterKeys = {"Everyone", "Playing"}, {"all", "players"}
    if H.Bool("show_spectators", true) then
        filterOptions[3] = "Spectating"
        filterKeys[3] = "spectators"
    end
    local filterSelected = 1
    for i, key in ipairs(filterKeys) do if key == (S.State.filter or "all") then filterSelected = i end end
    local segmented = K2.Segmented(frame, filterOptions, filterSelected, function(index) S.State.filter = filterKeys[index]; frame.NextPoll = 0 end)
    segmented:SetSize(u(220), u(28))
    local sortOptions, sortKeys = {"Name", "Playtime", "Ping"}, {"name", "playtime", "ping"}
    local sortSelected = 1
    for i, key in ipairs(sortKeys) do if key == (S.State.sort or "name") then sortSelected = i end end
    local sortSeg = K2.Segmented(frame, sortOptions, sortSelected, function(index) S.State.sort = sortKeys[index]; frame.NextPoll = 0 end)
    sortSeg:SetSize(u(180), u(28))
    local tag = vgui.Create("DPanel", frame)
    tag:SetSize(u(70), u(22))
    tag.Paint = function(_, ww, hh)
        surface.SetDrawColor(T2.hair or T2.line)
        surface.DrawOutlinedRect(0, 0, ww, hh, 1)
        K2.Text("[GoobOS]", 11, 600, ww / 2, hh / 2, T2.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    frame.PerformLayout = function(s, ww)
        local y = u(28)
        local x = ww - u(24) - u(70)
        tag:SetPos(x, y + u(3))
        x = x - u(10) - u(180); sortSeg:SetPos(x, y)
        x = x - u(10) - u(220); segmented:SetPos(x, y)
        x = x - u(10) - u(200); search:SetPos(x, y)
        s.RightEdge = x - u(14)
        close:SetPos(ww - u(38), u(14))
    end
    local bottom = vgui.Create("DPanel", frame)
    bottom:Dock(BOTTOM)
    bottom:SetTall(u(64))
    bottom.Paint = function(_, ww, hh)
        draw.RoundedBox(6, 0, 0, ww, hh, T2.card)
        surface.SetDrawColor(T2.hair or T2.line)
        surface.DrawRect(0, 0, ww, 1)
    end
    local function bottomButton(text, fn, width, primary)
        local b = vgui.Create("DButton", bottom)
        b:SetText("")
        b.Label = text
        b:Dock(primary and RIGHT or LEFT)
        b:SetWide(u(width or 120))
        b:DockMargin(primary and u(8) or 0, u(13), primary and u(16) or u(8), u(13))
        b.DoClick = fn
        b.Paint = function(p, ww2, hh2)
            local hover = K2.Hover(p)
            K2.Card(0, 0, ww2, hh2, primary and T2.main or T2.card)
            if hover > 0.01 then K2.Card(0, 0, ww2, hh2, K2.Alpha(T2.white, primary and 14 * hover or 10 * hover)) end
            K2.Text(p.Label, 14, primary and 600 or 500, ww2 / 2, hh2 / 2, primary and T2.white or T2.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return b
    end
    if H.Bool("show_bottom_mute_buttons", true) then
        local all
        all = bottomButton(hg.muteall and "Unmute all" or "Mute all", function()
            hg.muteall = not hg.muteall
            for _, p in ipairs(player.GetAll()) do H.ApplyVoice(p) end
            all.Label = hg.muteall and "Unmute all" or "Mute all"
        end, 120)
        local specs
        specs = bottomButton(hg.mutespect and "Unmute spectators" or "Mute spectators", function()
            hg.mutespect = not hg.mutespect
            for _, p in ipairs(player.GetAll()) do H.ApplyVoice(p) end
            specs.Label = hg.mutespect and "Unmute spectators" or "Mute spectators"
        end, 170)
    end
    if H.Bool("show_team_button", true) then
        bottomButton(LocalPlayer():Team() == TEAM_SPECTATOR and "Join game" or "Spectate", function()
            net.Start("ZB_SpecMode")
            net.WriteBool(LocalPlayer():Team() ~= TEAM_SPECTATOR)
            net.SendToServer()
            S.Close()
        end, 130)
    end
    if LocalPlayer():IsAdmin() then
        bottomButton("Admin settings", H.Settings, 150, true)
    end
    local sidebarWidth = math.Clamp(w * H.Float("sidebar_width_frac", .24), u(H.Int("sidebar_width_min", 220)), u(H.Int("sidebar_width_max", 420)))
    -- prevote_sb_20260925: the right column holds the map pre-vote card at its foot (the scoreboard's bottom right, just
    -- above the action bar) and the sidebar cards above it; without the round-end module it is the sidebar alone.
    local sidebarW = math.min(w * .29, sidebarWidth)
    local rightCol = vgui.Create("DPanel", frame)
    rightCol:Dock(RIGHT)
    rightCol:SetWide(sidebarW + u(14))
    rightCol.Paint = function() end
    frame.Prevote = buildKitPrevote(rightCol, h)
    local sidebar = buildKitSidebar(rightCol, sidebarW)
    local main = vgui.Create("DPanel", frame)
    main:Dock(FILL)
    main:DockMargin(u(14), u(10), 0, u(14))
    main.Paint = function() end
    local colHead = vgui.Create("DPanel", main)
    colHead:Dock(TOP)
    colHead:SetTall(u(24))
    colHead.Paint = function(_, ww, hh)
        local karmaX, _, pingX, pingW, timeX, timeW = kitColumns(ww)
        K2.Text("PLAYER", 12, 600, u(10), hh / 2, T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if H.Bool("show_karma", true) then K2.Text("KARMA", 12, 600, karmaX, hh / 2, T2.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        K2.Text("PING", 12, 600, pingX + pingW, hh / 2, T2.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if H.Bool("show_session", true) or H.Bool("show_playtime", true) then K2.Text("TIME", 12, 600, timeX + timeW, hh / 2, T2.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
    end
    local list = vgui.Create("DScrollPanel", main)
    list:Dock(FILL)
    frame.List = list
    KK.Scrollbar(list, T2)
    local empty = vgui.Create("DLabel", main)
    empty:SetText("No matching players")
    empty:SetFont(K2.Font(14, 500))
    empty:SetTextColor(T2.muted)
    empty:SetVisible(false)
    empty:SetSize(u(320), u(30))
    empty:SetPos(u(14), u(60))
    function frame:PollRoster()
        local rows, counts = kitPollRoster(self, list)
        empty:SetVisible(#rows == 0)
        local summary = counts.all .. " players"
        if H.Bool("show_tickrate", true) then
            local dt = engine.ServerFrameTime()
            if dt > 0 then summary = summary .. "  ·  " .. math.Round(1 / dt) .. " tick" end
        end
        self.Summary = summary
        sidebar:UpdatePublicInfo()
    end
    frame.Think = function(p)
        if (p.NextPoll or 0) <= RealTime() then
            p.NextPoll = RealTime() + math.Clamp(H.Float("refresh_interval", 1), .25, 5)
            p:PollRoster()
        end
    end
    frame.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE or key == KEY_TAB then S.Close() end end
    frame.OnRemove = function() if S.Frame == frame then S.Frame = nil; H.SetFrame(nil) end end
    frame:PollRoster()
    timer.Simple(0, function() if IsValid(list) then list:InvalidateLayout(true); list:GetVBar():SetScroll(S.State.scroll or 0) end end)
    return frame
end

-- Dispatch: chosen every time the frame is (re)built (S.Open / S.Rebuild in cl_controller.lua both
-- funnel through S.BuildView), never at file load. Convar 0, or a missing convar, or the kit not
-- being mounted (ZCGoobApps/ZCGoobApps.Kit absent) all fall back to buildLegacyView unchanged.
local function kitRequested()
    local cv = GetConVar("zc_goobos_scoreboard")
    return cv ~= nil and cv:GetBool() and ZCGoobApps ~= nil and ZCGoobApps.Kit ~= nil
end

function S.BuildView()
    if kitRequested() then return buildKitView() end
    return buildLegacyView()
end
