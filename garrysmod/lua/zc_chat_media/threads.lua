if not CLIENT then return end
local T = {Version = "20260923.bot-social1", pending = {}, serial = 0}
ZCChatThreads = T
local ink, muted, blue = Color(243,240,240), Color(163,160,160), Color(150,0,0)
local function valid(p) return IsValid(p) end
local notificationSound = "buttons/button15.wav"
local soundPreferences = {}
local function soundKey(key) return "zchat_sound_mute_" .. util.CRC(tostring(key or "main")) end
function T.SoundMuted(key)
    key=key or "main"
    if soundPreferences[key]==nil then soundPreferences[key]=cookie.GetNumber(soundKey(key),1)==1 end
    return soundPreferences[key]
end
function T.SetSoundMuted(key, value)
    soundPreferences[key or "main"]=value and true or false
    cookie.Set(soundKey(key), value and "1" or "0")
end
function T.PlayNotification(key)
    if not T.SoundMuted(key) then surface.PlaySound(notificationSound) end
end
local scrollTrack,scrollGrip,scrollHover=Color(24,22,24,130),Color(91,72,75,210),Color(151,88,93,240)
local searchFill,searchEdge=Color(24,22,24,250),Color(91,72,75)
function T.StyleScroll(panel)
    local bar=panel:GetVBar()
    bar:SetWide(8); bar:SetHideButtons(true)
    bar.Paint=function(_,w,h) draw.RoundedBox(4,2,0,w-4,h,scrollTrack) end
    bar.btnGrip.Paint=function(grip,w,h)
        draw.RoundedBox(4,1,0,w-2,h,(grip:IsHovered() or grip.Depressed) and scrollHover or scrollGrip)
    end
end
local function fitLabel(text,width)
    surface.SetFont("DermaDefaultBold")
    if surface.GetTextSize(text)<=width then return text end
    local length=string.utf8len(text)
    repeat length=length-1 until length<=0 or surface.GetTextSize(string.utf8sub(text,1,length).."…")<=width
    return string.utf8sub(text,1,math.max(0,length)).."…"
end
function T.Identity(p)
    return p:IsBot() and p:GetNWString("zcBotChatID", "") or p:SteamID64()
end
function T.Player(id)
    if not id or id == "" then return end
    for _, p in ipairs(player.GetAll()) do if T.Identity(p) == id then return p end end
end
-- Reuse the scoreboard's established name-keyed avatar in every chat surface.
function T.BindBotAvatar(avatar, id, name, isBot)
    if not valid(avatar) or not (isBot or (isstring(id) and id:match("^bot:"))) then return false end
    local peer = T.Player(id)
    name = (valid(peer) and peer:Nick()) or name or ""
    -- AvatarImage has native Steam drawing. Overlay it after that drawing,
    -- including while the bot's session ID has not reached this client yet.
    avatar.PaintOver = function(_,w,h)
        local services = ZCScoreboard and ZCScoreboard.Services
        if services and services.BotAvatar then services.BotAvatar(w,h,name)
        else
            surface.SetDrawColor(101,98,98,255)
            surface.DrawRect(0,0,w,h)
        end
        return true
    end
    return true
end
local function setAvatar(avatar, id, size, name)
    if T.BindBotAvatar(avatar,id,name) then return end
    local p = T.Player(id)
    if valid(p) then avatar:SetPlayer(p,size)
    elseif not id:match("^bot:") then avatar:SetSteamID(id,size) end
end
function T.IsMain(chat) return not chat.ZCThreads or chat.ZCThreadKey == "main" end
function T.Visible(row)
    if not valid(row) then return false end
    local c = hg and hg.chat
    if row.ZCSpectator and not row.ZCCensored and ZCChatGroupUI and ZCChatGroupUI.IsGroup(row.ZCConversation) and not ZCChatGroupUI.Spectator() then
        local m=ZCChatGroupUI.meta[row.ZCConversation]
        if row.ZCConversation~="main" and not (m and m.peek) then return false end
    end
    return valid(c) and (not row.ZCConversation or row.ZCConversation == (c.ZCThreadKey or "main"))
        and (row.ZCConversation == nil or row.ZCConversation == "main" or c:GetActive())
end
function T.Status(chat, text)
    if not valid(chat) then return end
    chat.ZCPMStatus, chat.ZCPMStatusUntil = text, RealTime() + 5
end
function T.Save(chat)
    local s = chat.ZCThreads and chat.ZCThreads[chat.ZCThreadKey]
    if not s then return end
    s.entries, s.recall = chat.entries, chat.messageHistory
    s.draft, s.reply = chat.entry:GetText(), chat.ZCReplyID
    s.scroll = chat.history:GetVBar():GetScroll()
    s.scrollStart, s.scrollFrom = chat.scrollStart, chat.scrollFrom
end
local function bind(chat, s)
    chat.history, chat.historySpacer, chat.entries = s.history, s.spacer, s.entries
    chat.messageHistory, chat.ZCReplyID = s.recall, s.reply
    chat.scrollStart, chat.scrollFrom = s.scrollStart, s.scrollFrom
end
function T.Ensure(chat, key, name)
    if chat.ZCThreads[key] then
        if name then chat.ZCThreads[key].name = name end
        return chat.ZCThreads[key]
    end
    if #chat.ZCThreadOrder >= 24 then
        local victim
        for _, k in ipairs(chat.ZCThreadOrder) do
            local s = chat.ZCThreads[k]
            if k ~= "main" and s.closed and (s.draft or "") == "" and not s.pending then victim = k; break end
        end
        if not victim then T.Status(chat, "Close an unused conversation before starting another."); return end
        chat.ZCThreads[victim].history:Remove(); chat.ZCThreads[victim] = nil
        table.RemoveByValue(chat.ZCThreadOrder, victim)
    end
    local panel = chat:Add("DScrollPanel")
    T.StyleScroll(panel)
    panel:SetVisible(false); panel:SetSize(chat.history:GetSize()); panel:SetPos(chat.history:GetPos())
    local spacer = panel:GetCanvas():Add("Panel"); spacer:Dock(TOP); spacer:SetTall(0)
    local s = {key=key, name=name or key, history=panel, spacer=spacer, entries={}, recall={}, draft="", unread=0, scroll=0}
    chat.ZCThreads[key] = s; chat.ZCThreadOrder[#chat.ZCThreadOrder+1] = key
    return s
end
function T.Select(chat, key, quiet)
    if not valid(chat) or not chat.ZCThreads then return end
    local s = chat.ZCThreads[key]
    if not s then return end
    if chat.ZCThreadKey ~= key then
        T.Save(chat)
        ZCChatMedia.ClosePicker(); ZCChatMedia.StopVideo(); ZCChatMedia.Stop()
        if valid(ZCChatMedia.Expanded) then ZCChatMedia.Expanded:Remove() end
        local old = chat.ZCThreads[chat.ZCThreadKey]
        old.history:SetVisible(false); old.history:Dock(NODOCK)
        chat.ZCThreadKey = key; bind(chat, s)
        s.history:Dock(FILL); s.history:DockMargin(4,2,4,12)
        chat.entry.History = s.recall; chat.entry.HistoryPos = nil
        chat.entry:SetText(s.draft or ""); chat.entry.prevText = s.draft or ""
        chat.entry:SetCaretPos(#(s.draft or ""))
        chat.entry.droppedCharacters = {} -- Never carry private draft effects into another thread.
        chat.ZCReplyComposerShown = nil;chat.ZCPMHistoryMargin=nil
        ZCChatMedia.Unread = 0; ZCChatMedia.AtBottom = true
        chat:InvalidateLayout(true)
        s.history:GetVBar():SetScroll(s.scroll or 0)
        chat.ZCThreadChanged = RealTime()
        if chat:GetActive() then hook.Run(key=="main" and "StartChat" or "FinishChat") end
        for _, row in ipairs(s.entries) do if valid(row) then row.ZCOpenedAt=nil end end
    end
    s.closed = false
    if chat:GetActive() and chat.phonePage == "chat" then s.unread = 0 end
    if not quiet and chat:GetActive() then chat.entry:RequestFocus() end
    T.RebuildTabs(chat)
    if ZCChatGroupUI then ZCChatGroupUI.OnSelect(chat,key) end
end
function T.WithState(chat, state, fn)
    local active = chat.ZCThreads[chat.ZCThreadKey]
    local history, spacer, entries = chat.history, chat.historySpacer, chat.entries
    local start, from = chat.scrollStart, chat.scrollFrom
    local routing = chat.ZCRoutingInactive
    chat.history, chat.historySpacer, chat.entries = state.history, state.spacer, state.entries
    chat.scrollStart, chat.scrollFrom = state.scrollStart, state.scrollFrom
    chat.ZCRoutingInactive = state ~= active
    local ok, result = pcall(fn)
    state.entries, state.scrollStart, state.scrollFrom = chat.entries, chat.scrollStart, chat.scrollFrom
    chat.history, chat.historySpacer, chat.entries = history, spacer, entries
    chat.scrollStart, chat.scrollFrom, chat.ZCRoutingInactive = start, from, routing
    if state == active then chat.scrollStart, chat.scrollFrom = state.scrollStart, state.scrollFrom end
    if not ok then error(result) end
    return result
end
function T.Append(chat, elements, restored, append)
    if not chat.ZCThreads then
        local row = append(chat,elements,restored)
        if valid(row) then
            if not restored and not row.ZCOwn and not ZCChatMedia.Restoring then T.PlayNotification(CHAT_CONVERSATION or "main") end
            T.BindAvatar(row)
        end
        return row
    end
    local key = CHAT_CONVERSATION or "main"
    local s = T.Ensure(chat,key,CHAT_PEER_NAME)
    if not s then return end
    local row = T.WithState(chat,s,function() return append(chat,elements,restored) end)
    if valid(row) then
        row.ZCConversation = key
        if not ZCChatMedia.Restoring then
            if not restored and not row.ZCOwn then T.PlayNotification(key) end
            s.last = RealTime()
            if key ~= chat.ZCThreadKey or not chat:GetActive() or chat.phonePage ~= "chat" then
                if row.ZCSenderSteam ~= LocalPlayer():SteamID64() then
                    s.unread = math.min(99,(s.unread or 0)+1)
                    if key ~= "main" then T.Notify(chat,s) end
                end
            end
        end
        T.BindAvatar(row)
        T.Trim(chat)
    end
    return row
end
function T.Trim(chat)
    local count = 0
    for _, s in pairs(chat.ZCThreads) do count=count+#s.entries end
    -- Raised alongside cl_zchat.lua's per-thread 500-row cap so a full main
    -- chat scrollback isn't preempted by this shared cross-thread ceiling
    -- (owner request 2026-09-23; headroom for PM/group tabs above main's 500).
    while count > 900 do
        local oldest, state
        for _, s in pairs(chat.ZCThreads) do
            for i, row in ipairs(s.entries) do
                if valid(row) and (not oldest or (row.ZCArrived or 0)<(oldest.row.ZCArrived or 0)) then oldest={row=row,index=i};state=s end
            end
        end
        if not oldest then break end
        table.remove(state.entries,oldest.index); oldest.row:Remove(); count=count-1
        T.WithState(chat,state,function() ZCChatMedia.ReflowChains(chat) end)
    end
end
function T.ForEach(chat, fn)
    if not chat.ZCThreads then return fn({entries=chat.entries,history=chat.history}) end
    for _, s in pairs(chat.ZCThreads) do fn(s) end
end
function T.CloseTab(chat,key)
    if key == "main" then return end
    local s = chat.ZCThreads[key]
    if not s then return end
    if chat.ZCThreadKey == key then T.Select(chat,"main") end
    s.closed=true; T.RebuildTabs(chat)
    if ZCChatGroupUI then ZCChatGroupUI.OnClose(chat,key) end
end
function T.Open(chat,id,name)
    if not valid(chat) or id == LocalPlayer():SteamID64() then return end
    local s = T.Ensure(chat,id,name)
    if not s then return end
    s.closed=false
    chat:SetActive(true); T.CloseDirectory(chat); T.Select(chat,id)
end
function T.Send(chat,text)
    if ZCChatGroupUI and ZCChatGroupUI.IsGroup(chat.ZCThreadKey) then return ZCChatGroupUI.Send(chat,text) end
    local s=chat.ZCThreads[chat.ZCThreadKey]
    if s.key=="main" then return false end
    if s.pending then T.Status(chat,"Sending your message…");return true end
    if not valid(T.Player(s.key)) then T.Status(chat,"This player is offline. Your draft is saved.");return true end
    if not text:find("%S") then return true end
    T.Save(chat)
    T.serial=T.serial%65535+1
    local nonce=T.serial
    T.pending[nonce]={chat=chat,key=s.key,text=text,reply=chat.ZCReplyID,at=RealTime()}
    s.pending=nonce
    net.Start("zcPMSend");net.WriteString(s.key);net.WriteString(text);net.WriteUInt(chat.ZCReplyID or 0,32);net.WriteUInt(nonce,16);net.SendToServer()
    T.Status(chat,"Sending…")
    return true
end
net.Receive("zcPMResult",function()
    local nonce,ok,detail=net.ReadUInt(16),net.ReadBool(),net.ReadString()
    local pending=T.pending[nonce];T.pending[nonce]=nil
    local chat= pending and pending.chat or (hg and hg.chat)
    if not valid(chat) then return end
    if pending then
        T.Save(chat)
        local s=chat.ZCThreads[pending.key]
        if s then
            s.pending=nil
            if ok then
                if s.recall[#s.recall]~=pending.text then s.recall[#s.recall+1]=pending.text end
                while #s.recall>20 do table.remove(s.recall,1) end
                if s.draft==pending.text and s.reply==pending.reply then
                    s.draft="";s.reply=nil
                    if chat.ZCThreadKey==s.key then chat.entry:SetText("");chat.entry.prevText="";chat.ZCReplyID=nil end
                end
            end
        end
    end
    T.Status(chat,detail)
end)
net.Receive("zcPMMessage",function()
    local sender,target,senderName,targetName=net.ReadString(),net.ReadString(),net.ReadString(),net.ReadString()
    local text,id,reply=net.ReadString(),net.ReadUInt(32),net.ReadUInt(32)
    local censored=net.BytesLeft()>0 and net.ReadBool() or false
    local spectator=net.BytesLeft()>0 and net.ReadBool() or false
    -- PM audience is authorized by the server; public/group spectator rules do not apply.
    spectator=false
    local me=LocalPlayer():SteamID64()
    if me~=sender and me~=target then return end
    local peer=sender==me and target or sender
    local peerName=sender==me and targetName or senderName
    local chat=hg and hg.chat
    if not valid(chat) then return end
    local old={CHAT_SPEAKER,CHAT_MESSAGE_ID,CHAT_REPLY_ID,CHAT_CONVERSATION,CHAT_PEER_NAME,CHAT_PRIVATE,CHAT_SENDER_NAME,CHAT_SENDER_STEAM}
    CHAT_SPEAKER=T.Player(sender);CHAT_MESSAGE_ID=id;CHAT_REPLY_ID=reply
    CHAT_CONVERSATION=peer;CHAT_PEER_NAME=peerName;CHAT_PRIVATE=true;CHAT_SENDER_NAME=senderName;CHAT_SENDER_STEAM=sender
    local elements={Color(192,0,0),valid(CHAT_SPEAKER) and CHAT_SPEAKER or senderName,color_white,": "..text}
    elements.zcSenderName=senderName;elements.zcPrivate=true
    local ok,err=pcall(function()
        local row=chat:AddLine(elements)
        if valid(row) then row.ZCSpectator=spectator;row.ZCCensored=censored end
    end)
    CHAT_SPEAKER,CHAT_MESSAGE_ID,CHAT_REPLY_ID,CHAT_CONVERSATION,CHAT_PEER_NAME,CHAT_PRIVATE,CHAT_SENDER_NAME,CHAT_SENDER_STEAM=unpack(old,1,8)
    if not ok then ErrorNoHalt("PM rendering: "..tostring(err).."\n") end
end)
function T.Hello()
    if not hg or not valid(hg.chat) or not valid(LocalPlayer()) then return end
    if util.NetworkStringToID("zcPMHello")>0 then net.Start("zcPMHello");net.SendToServer() end
    if util.NetworkStringToID("zcBotPMHello")>0 then net.Start("zcBotPMHello");net.SendToServer() end
end
hook.Add("InitPostEntity","ZCChatThreads.Hello",T.Hello)
timer.Simple(0,T.Hello)
local function button(parent,label,tip,action)
    local b=vgui.Create("DButton",parent)
    b:SetText("");b:SetTooltip(tip);b:SetKeyboardInputEnabled(false);b.DoClick=action
    b.Paint=function(self,w,h)
        self.blend=Lerp(math.Clamp(FrameTime()*16,0,1),self.blend or 0,self:IsHovered() and 1 or 0)
        draw.RoundedBox(0,0,0,w,h,Color(75,72,72,70+self.blend*110))
        draw.SimpleText(label,"DermaDefaultBold",w/2,h/2,ink,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    end
    return b
end
function T.Init(chat)
    T.StyleScroll(chat.history)
    if chat.ZCThreads then return end
    chat.ZCThreads={main={key="main",name="Main",entries=chat.entries,history=chat.history,spacer=chat.historySpacer,recall=chat.messageHistory,draft="",unread=0}}
    chat.ZCThreadKey="main";chat.ZCThreadOrder={"main"}
    local strip=vgui.Create("DPanel",chat);chat.ZCTabStrip=strip
    strip.Paint=function(_,w,h)
        draw.RoundedBox(0,0,0,w,h,Color(31,28,28,235))
        surface.SetDrawColor(192,0,0,24);surface.DrawRect(10,h-1,w-20,1)
    end
    chat.ZCNewMessage=button(strip,"✎","New private message",function()T.Directory(chat,true)end)
    chat.ZCPlayers=button(strip,"","Players and conversations",function()T.Directory(chat,false)end)
    local base=chat.ZCPlayers.Paint
    chat.ZCPlayers.Paint=function(self,w,h)
        base(self,w,h)
        draw.RoundedBox(4,w/2-9,7,8,8,ink);draw.RoundedBox(5,w/2-12,17,14,9,ink)
        draw.RoundedBox(3,w/2+3,9,6,6,muted);draw.RoundedBox(4,w/2+3,17,9,8,muted)
    end
    if valid(chat.keyOrb) then
        local paint=chat.keyOrb.Paint
        chat.keyOrb.Paint=function(panel,w,h)
            paint(panel,w,h)
            local unread=0
            for key,state in pairs(chat.ZCThreads) do if key~="main" then unread=unread+(state.unread or 0) end end
            if unread>0 then
                draw.RoundedBox(0,w-14,0,14,14,Color(112,213,201))
                draw.SimpleText(unread>9 and "9+" or tostring(unread),"DermaDefault",w-7,7,Color(35,32,32),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
            end
        end
    end
    if ZCChatGroupUI then ZCChatGroupUI.Init(chat) end
    T.RebuildTabs(chat)
    timer.Simple(0,T.Hello)
end
function T.Menu(chat,recents)
    local menu=DermaMenu()
    for _,key in ipairs(chat.ZCThreadOrder) do
        local s=chat.ZCThreads[key]
        menu:AddOption(s.name..((s.unread or 0)>0 and ("  · "..s.unread.." new") or ""),function()T.Select(chat,key)end)
        menu:AddOption((T.SoundMuted(key) and "Unmute " or "Mute ")..s.name.." notifications",function()
            T.SetSoundMuted(key,not T.SoundMuted(key))
            chat.ZCTabSignature=nil; T.RebuildTabs(chat)
        end)
    end
    menu:AddSpacer();menu:AddOption("New message…",function()T.Directory(chat,true)end);menu:Open()
end
function T.RebuildTabs(chat)
    if not valid(chat.ZCTabStrip) then return end
    local signature={tostring(chat:GetWide()),chat.ZCThreadKey}
    for _,key in ipairs(chat.ZCThreadOrder) do local s=chat.ZCThreads[key];signature[#signature+1]=key..":"..s.name..":"..tostring(s.closed)..":"..tostring(s.unread) end
    signature=table.concat(signature,"|")
    if chat.ZCTabSignature==signature then return end
    chat.ZCTabSignature=signature
    for _,b in ipairs(chat.ZCTabs or {}) do if valid(b) then b:Remove() end end
    chat.ZCTabs={}
    local keys={"main"}
    if chat.ZCThreadKey~="main" then keys[#keys+1]=chat.ZCThreadKey end
    for _,key in ipairs(chat.ZCThreadOrder) do
        if key~="main" and key~=chat.ZCThreadKey and not chat.ZCThreads[key].closed then keys[#keys+1]=key end
    end
    local available=chat:GetWide()-(ZCChatGroupUI and 130 or 92)
    local x,hidden=8,0
    for _,key in ipairs(keys) do
        local s=chat.ZCThreads[key];local width=key=="main" and 78 or 132
        local reserve=#keys>2 and 30 or 0
        if x+width > available-reserve and key~=chat.ZCThreadKey and key~="main" then hidden=hidden+1
        else
            width=math.min(width,available-x-(key==chat.ZCThreadKey and #keys>2 and 30 or 0))
            local tab=button(chat.ZCTabStrip,"",s.name,function()T.Select(chat,key)end)
            tab:SetPos(x,6);tab:SetSize(width,32);chat.ZCTabs[#chat.ZCTabs+1]=tab
            if ZCChatGroupUI and ZCChatGroupUI.IsGroup(key) then ZCChatGroupUI.GroupIcon(tab)
            elseif key~="main" then
                local avatar=vgui.Create("AvatarImage",tab);setAvatar(avatar,key,32,s.name);avatar:SetSize(24,24);avatar:SetPos(4,4);avatar:SetMouseInputEnabled(false)
            end
            local tabLabel=fitLabel(key=="main" and "Main" or s.name,math.max(8,width-(key=="main" and 38 or 78)))
            tab.Paint=function(self,w,h)
                local selected=chat.ZCThreadKey==key
                self.blend=Lerp(math.Clamp(FrameTime()*16,0,1),self.blend or 0,selected and 1 or (self:IsHovered() and .35 or 0))
                draw.RoundedBox(0,0,0,w,h,Color(150,0,0,35+self.blend*135))
                if selected then draw.RoundedBox(1,12,h-2,w-24,2,Color(192,0,0)) end
                local label=tabLabel
                draw.SimpleText(label,"DermaDefaultBold",key=="main" and 12 or 34,h/2,selected and ink or muted,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
                if (s.unread or 0)>0 then
                    draw.RoundedBox(0,w-(key=="main" and 24 or 44),3,20,14,blue)
                    draw.SimpleText(s.unread>99 and "99+" or tostring(s.unread),"DermaDefault",w-(key=="main" and 14 or 34),10,color_white,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                end
            end
            tab.DoRightClick=function()
                local m=DermaMenu()
                m:AddOption(T.SoundMuted(key) and "Unmute notification sound" or "Mute notification sound",function()
                    T.SetSoundMuted(key,not T.SoundMuted(key))
                    tab:SetTooltip((T.SoundMuted(key) and "Sound muted · " or "Sound on · ")..s.name.." · right-click for options")
                end):SetIcon(T.SoundMuted(key) and "icon16/sound_mute.png" or "icon16/sound.png")
                if key~="main" then
                    if ZCChatGroupUI then ZCChatGroupUI.Menu(chat,key,m) end
                    m:AddOption("Close conversation tab",function()T.CloseTab(chat,key)end)
                end
                m:Open()
            end
            tab:SetTooltip((T.SoundMuted(key) and "Sound muted · " or "Sound on · ")..s.name.." · right-click for options")
            if key~="main" then
                local close=button(tab,"×","Close tab · history stays in recents",function()T.CloseTab(chat,key)end)
                close:SetPos(width-20,9);close:SetSize(16,16)
            end
            x=x+width+4
        end
    end
    if hidden>0 or #chat.ZCThreadOrder>#keys then
        local more=button(chat.ZCTabStrip,"···","All conversations",function()T.Menu(chat)end)
        more:SetPos(math.min(x,available-28),6);more:SetSize(28,32);chat.ZCTabs[#chat.ZCTabs+1]=more
    end
    chat.ZCTabWidth=chat:GetWide()
end
function T.Layout(chat,w,h)
    if not chat.ZCThreads then return end
    if ZCChatGroupUI then ZCChatGroupUI.Layout(chat,w,h) end
    chat.ZCTabStrip:SetPos(0,44);chat.ZCTabStrip:SetSize(w,44)
    chat.ZCNewMessage:SetPos(w-80,6);chat.ZCNewMessage:SetSize(32,32)
    chat.ZCPlayers:SetPos(w-42,6);chat.ZCPlayers:SetSize(32,32)
    if chat.ZCTabWidth~=w then T.RebuildTabs(chat) end
    if valid(chat.ZCDirectory) then chat.ZCDirectory:SetPos(6,92);chat.ZCDirectory:SetSize(w-12,math.max(80,h-144)) end
end
function T.CloseDirectory(chat)
    if valid(chat.ZCDirectory) then chat.ZCDirectory:Remove() end
    chat.ZCDirectory=nil
    if chat.ZCDirectoryHeight then
        local height=chat.ZCDirectoryHeight;chat.ZCDirectoryHeight=nil
        if chat:GetTall()==chat.ZCDirectoryExpandedHeight then chat:SetTall(height);chat:SetY(ScrH()-48-height) end
        chat.ZCDirectoryExpandedHeight=nil
    end
end
function T.Directory(chat,compose)
    if valid(chat.ZCDirectory) then T.CloseDirectory(chat);chat.entry:RequestFocus();if T.IsMain(chat) then hook.Run("StartChat") end;return end
    chat:SetActive(true);ZCChatMedia.ClosePicker();ZCChatMedia.StopVideo();ZCChatMedia.Stop()
    local targetHeight=math.min(360,ScrH()-96)
    if chat:GetTall()<targetHeight then chat.ZCDirectoryHeight=chat:GetTall();chat.ZCDirectoryExpandedHeight=targetHeight;chat:SetTall(targetHeight);chat:SetY(ScrH()-48-targetHeight) end
    local pane=vgui.Create("DPanel",chat);chat.ZCDirectory=pane;pane:SetAlpha(0);pane:AlphaTo(255,.16)
    pane.Paint=function(_,w,h)draw.RoundedBox(0,0,0,w,h,Color(36,33,33,252))end
    pane:DockPadding(14,12,14,12)
    local header=vgui.Create("DPanel",pane);header:Dock(TOP);header:SetTall(32);header.Paint=function(_,w,h)
        draw.SimpleText(compose and "New message" or "Players & conversations","DermaDefaultBold",0,8,ink)
    end
    local back=button(header,"×","Back to conversation",function()T.CloseDirectory(chat);chat.entry:RequestFocus();if T.IsMain(chat) then hook.Run("StartChat") end end)
    back:Dock(RIGHT);back:SetWide(28)
    local search=vgui.Create("DTextEntry",pane);search:Dock(TOP);search:SetTall(32);search:DockMargin(0,4,0,10);search:SetPlaceholderText("Search players or recent conversations…")
    search:SetFont("DermaDefault");search:SetTextColor(ink);search:SetCursorColor(ink)
    search.Paint=function(entry,w,h)
        draw.RoundedBox(4,0,0,w,h,entry:HasFocus() and scrollHover or searchEdge)
        draw.RoundedBox(4,1,1,w-2,h-2,searchFill)
        entry:DrawTextEntryText(ink,blue,ink)
        if entry:GetText()=="" and not entry:HasFocus() then draw.SimpleText("Search players or conversations…","DermaDefault",6,h/2,muted,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER) end
    end
    search:RequestFocus()
    local list=vgui.Create("DScrollPanel",pane);list:Dock(FILL);T.StyleScroll(list)
    local function populate()
        local scroll = list:GetVBar():GetScroll()
        list:Clear()
        local query=string.Trim(search:GetText()):lower();local people,seen={},{}
        for _,p in ipairs(player.GetAll()) do
            local id=T.Identity(p)
            if p~=LocalPlayer() and id~="" then people[#people+1]={id=id,name=p:Nick(),online=true};seen[id]=true end
        end
        for _,key in ipairs(chat.ZCThreadOrder) do
            if key~="main" and not (ZCChatGroupUI and ZCChatGroupUI.IsGroup(key)) and not seen[key] then people[#people+1]={id=key,name=chat.ZCThreads[key].name,online=false} end
        end
        table.sort(people,function(a,b)if a.online~=b.online then return a.online end return a.name:lower()<b.name:lower()end)
        local shown=0
        for _,person in ipairs(people) do
            if query=="" or person.name:lower():find(query,1,true) then
                shown=shown+1
                local row=button(list,"","Open conversation with "..person.name,function()T.Open(chat,person.id,person.name)end)
                row:Dock(TOP);row:SetTall(56);row:DockMargin(0,0,0,5)
                local avatar=vgui.Create("AvatarImage",row);setAvatar(avatar,person.id,64,person.name);avatar:SetSize(38,38);avatar:SetPos(9,9);avatar:SetMouseInputEnabled(false)
                row.Paint=function(self,w,h)
                    self.blend=Lerp(math.Clamp(FrameTime()*16,0,1),self.blend or 0,self:IsHovered() and 1 or 0)
                    draw.RoundedBox(0,0,0,w,h,Color(73,70,70,65+self.blend*100))
                    if self.ZCNameWidth~=w then self.ZCNameWidth=w;self.ZCName=fitLabel(person.name,math.max(8,w-128)) end
                    local name=self.ZCName
                    draw.SimpleText(name,"DermaDefaultBold",58,12,ink)
                    draw.SimpleText(person.online and "Online · private conversation" or "Offline · saved conversation","DermaDefault",58,31,muted)
                    draw.RoundedBox(3,w-60,17,6,6,person.online and Color(110,219,178) or muted)
                    draw.SimpleText("›","DermaLarge",w-23,h/2,Color(192,0,0),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                    local s=chat.ZCThreads[person.id]
                    if s and (s.unread or 0)>0 then draw.SimpleText(tostring(s.unread),"DermaDefaultBold",w-44,34,blue,TEXT_ALIGN_CENTER) end
                end
            end
        end
        if shown==0 then
            local empty=vgui.Create("DLabel",list);empty:Dock(TOP);empty:SetTall(70);empty:SetText("No matching players. Try another name.");empty:SetTextColor(muted);empty:SetContentAlignment(5)
        end
        list:InvalidateLayout(true);list:GetVBar():SetScroll(scroll)
    end
    search.OnChange=function()list:GetVBar():SetScroll(0);populate()end;populate();pane.nextRefresh=RealTime()+2
    pane.Think=function()
        if RealTime()>pane.nextRefresh then pane.nextRefresh=RealTime()+2;populate() end
    end
    T.Layout(chat,chat:GetSize());pane:MoveToFront();search:RequestFocus();hook.Run("FinishChat")
end
function T.BindAvatar(row)
    if not valid(row.ZCAvatar) then return end
    local speaker = row.ZCSpeaker
    if valid(speaker) and speaker:IsPlayer() and speaker:IsBot() then
        row.ZCBot = true
        row.ZCSenderName = speaker:Nick()
        local id = T.Identity(speaker)
        if id ~= "" then row.ZCSenderSteam = id end
    end
    T.BindBotAvatar(row.ZCAvatar,row.ZCSenderSteam,row.ZCSenderName,row.ZCBot)
    row.ZCAvatar:SetMouseInputEnabled(true)
    row.ZCAvatar.OnMousePressed=function(_,key)
        if not valid(hg.chat) or not hg.chat:GetActive() or not row.ZCSenderSteam or row.ZCSenderSteam==LocalPlayer():SteamID64() then return end
        local menu=DermaMenu()
        menu:AddOption("Message "..(row.ZCSenderName or "player"),function()T.Open(hg.chat,row.ZCSenderSteam,row.ZCSenderName)end)
        menu:AddOption("Mention",function()ZCChatMedia.MentionSender(row)end)
        menu:Open()
    end
end
function T.Notify(chat,s)
    if ZCPhoneSettings and ZCPhoneSettings.Get("private")==0 then return end
    if (s.notified or -10)+3>RealTime() then return end
    s.notified=RealTime()
    chat.ZCPMNotice={key=s.key,name=s.name,untilTime=RealTime()+4}
    if valid(chat.ZCPMNoticeButton) then chat.ZCPMNoticeButton:Remove() end
    local notice=button(chat,"","Open private conversation",function()T.Open(chat,s.key,s.name);chat.ZCPMNotice=nil end)
    chat.ZCPMNoticeButton=notice
    notice.Paint=function(_,w,h)
        local n=chat.ZCPMNotice;if not n then return end
        local fade=math.Clamp((n.untilTime-RealTime())/.25,0,1)*math.Clamp((RealTime()-s.notified)/.15,0,1)
        draw.RoundedBox(0,0,0,w,h,Color(70,67,67,240*fade))
        draw.SimpleText("New message · "..string.utf8sub(n.name,1,28),"DermaDefaultBold",12,10,Color(235,232,232,255*fade))
    end
end
function T.OnActive(chat,active)
    if not chat.ZCThreads then return end
    if not active then
        T.CloseDirectory(chat)
        chat.ZCLastThread=chat.ZCThreadKey
        T.Select(chat,"main",true)
    else
        local s=chat.ZCThreads[chat.ZCThreadKey];if s then s.unread=0 end
    end
end
function T.Think(chat)
    if not chat.ZCThreads then return end
    local open=chat:GetActive() and chat.phonePage=="chat"
    local directory=valid(chat.ZCDirectory)
    local s=chat.ZCThreads[chat.ZCThreadKey]
    chat.ZCTabStrip:SetVisible(open or (chat.frameAlpha>1 and chat.phonePage=="chat"));chat.ZCTabStrip:SetAlpha(chat.frameAlpha);chat.ZCTabStrip:SetMouseInputEnabled(open)
    local top=open and 90 or 44
    if chat.ZCThreadTop~=top then chat.ZCThreadTop=top;chat:DockPadding(0,top,0,0);chat:InvalidateLayout(true) end
    if not open and directory then T.CloseDirectory(chat);directory=false end
    if directory then chat.history:SetVisible(false) end
    local margin=chat.ZCReplyID and open and 44 or (s.key=="main" and 12 or 28)
    if chat.ZCPMHistoryMargin~=margin then chat.ZCPMHistoryMargin=margin;chat.history:DockMargin(4,2,4,margin);chat.history:InvalidateParent(true) end
    chat.entry:SetMouseInputEnabled(not directory)
    chat.entry:SetKeyboardInputEnabled(open and not directory)
    if open and not directory then s.unread=0 end
    local online=s.key=="main" or valid(T.Player(s.key))
    chat.entry:SetPlaceholderText(ZCChatGroupUI and ZCChatGroupUI.IsGroup(s.key) and ZCChatGroupUI.Placeholder(s.key) or s.key=="main" and "Message Main" or (online and ("Message "..s.name) or (s.name.." is offline · draft saved")))
    if RealTime()>(chat.ZCNextThreadRefresh or 0) then
        chat.ZCNextThreadRefresh=RealTime()+1
        for key,state in pairs(chat.ZCThreads) do local p=T.Player(key);if valid(p) then state.name=p:Nick() end end
        T.RebuildTabs(chat)
    end
    for nonce,pending in pairs(T.pending) do
        if RealTime()-pending.at>10 then
            local state=chat.ZCThreads[pending.key];if state and state.pending==nonce then state.pending=nil end
            T.pending[nonce]=nil;T.Status(chat,"Delivery was not confirmed. Your draft is saved.")
        end
    end
    local notice=chat.ZCPMNotice
    if valid(chat.ZCPMNoticeButton) then
        if not notice or notice.untilTime<RealTime() then chat.ZCPMNoticeButton:Remove();chat.ZCPMNoticeButton=nil
        else
            chat.ZCPMNoticeButton:SetSize(math.min(300,chat:GetWide()-55),34)
            chat.ZCPMNoticeButton:SetPos(open and 14 or 50,chat:GetTall()-84)
            chat.ZCPMNoticeButton:SetMouseInputEnabled(open);chat.ZCPMNoticeButton:MoveToFront()
        end
    end
    T.Layout(chat,chat:GetSize())
    if ZCChatGroupUI then ZCChatGroupUI.Think(chat) end
end
function T.Draw(chat,w,h)
    if not chat.ZCThreads or not chat:GetActive() or chat.phonePage~="chat" or valid(chat.ZCDirectory) then return end
    local s=chat.ZCThreads[chat.ZCThreadKey]
    if #s.entries==0 then
        local cy=h<250 and 90 or math.max(128,(h+40)/2-30)
        if h>=250 then
        draw.RoundedBox(0,w/2-24,cy-38,48,40,Color(150,0,0,65))
        draw.SimpleText(s.key=="main" and "#" or "↗","DermaLarge",w/2,cy-18,blue,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        end
        draw.SimpleText(s.key=="main" and "The conversation starts here" or ("Say hello to "..string.utf8sub(s.name,1,24)),"DermaDefaultBold",w/2,cy+18,ink,TEXT_ALIGN_CENTER)
        if h>=250 then draw.SimpleText(s.key=="main" and "Messages from the server appear here." or (ZCChatGroupUI and ZCChatGroupUI.IsGroup(s.key) and "Messages are shared with this group." or "A private conversation, in its own space."),"DermaDefault",w/2,cy+40,muted,TEXT_ALIGN_CENTER) end
    end
    if s.key~="main" then
        local online=valid(T.Player(s.key))
        draw.SimpleText(ZCChatGroupUI and ZCChatGroupUI.IsGroup(s.key) and ZCChatGroupUI.Caption(s.key) or ((online and "PRIVATE · " or "OFFLINE · ")..string.utf8sub(s.name,1,36)),"DermaDefault",12,h-54,Color(192,0,0))
    end
    if (chat.ZCPMStatusUntil or 0)>RealTime() then
        draw.RoundedBox(0,12,96,w-24,26,Color(56,53,53,240))
        draw.SimpleText(string.utf8sub(chat.ZCPMStatus or "",1,math.max(16,math.floor((w-44)/7))),"DermaDefault",22,102,ink)
    end
end
function T.Export(chat,capture)
    if not valid(chat) or not chat.ZCThreads then return capture(chat) end
    T.Save(chat)
    local saved={threads={},order=table.Copy(chat.ZCThreadOrder),selected=chat.ZCThreadKey,last=chat.ZCLastThread,active=chat:GetActive(),page=chat.phonePage}
    for _,key in ipairs(chat.ZCThreadOrder) do
        local s=chat.ZCThreads[key]
        local record=T.WithState(chat,s,function()return capture(chat)end)
        record.draft=s.draft;record.recall=s.recall;record.reply=s.reply;record.active=false
        record.name=s.name;record.unread=s.unread;record.closed=s.closed;record.scroll=s.scroll
        saved.threads[key]=record
    end
    return saved
end
function T.Import(chat,saved,restore)
    if not saved or not saved.threads then
        restore(chat,saved)
        if valid(chat) and chat.ZCThreads then T.Save(chat) end
        return
    end
    local oldConv,oldPeer=CHAT_CONVERSATION,CHAT_PEER_NAME
    for _,key in ipairs(saved.order or {"main"}) do
        local data=saved.threads[key]
        if data then
            local s=T.Ensure(chat,key,data.name)
            if s then
                CHAT_CONVERSATION,CHAT_PEER_NAME=key,data.name
                T.WithState(chat,s,function()restore(chat,data)end)
                s.draft=data.draft or "";s.recall=data.recall or {};s.reply=data.reply;s.unread=data.unread or 0;s.closed=data.closed;s.scroll=data.scroll or 0
                s.history:SetVisible(false);s.history:Dock(NODOCK)
            end
        end
    end
    CHAT_CONVERSATION,CHAT_PEER_NAME=oldConv,oldPeer
    local key=saved.active and saved.selected or "main"
    if not chat.ZCThreads[key] then key="main" end
    chat.ZCThreadKey=key;chat.ZCLastThread=saved.last
    local s=chat.ZCThreads[key];bind(chat,s)
    s.history:Dock(FILL);s.history:DockMargin(4,2,4,12)
    chat.entry.History=s.recall;chat.entry:SetText(s.draft);chat.entry.prevText=s.draft;chat.entry.droppedCharacters={}
    if saved.active then chat:SetActive(true);chat:SetPhonePage(saved.page or "chat",true) end
    chat:InvalidateLayout(true);s.history:GetVBar():SetScroll(s.scroll)
    T.RebuildTabs(chat)
end

function T.AllRows(chat)
    local rows={}
    T.ForEach(chat,function(s)for _,row in ipairs(s.entries)do rows[#rows+1]=row end end)
    return rows
end
