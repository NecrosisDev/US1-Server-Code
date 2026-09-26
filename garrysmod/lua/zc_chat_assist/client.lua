if not CLIENT then return end
if ZCChatAssist and ZCChatAssist.Uninstall then ZCChatAssist.Uninstall() end
local A=include('zc_chat_assist/model.lua')
ZCChatAssist=A
A.commands={}
A.entries=setmetatable({}, {__mode='k'})
local ink=Color(230,230,235)
local ghost=Color(150,155,170)
local red=Color(255,150,140)
local function charCount(s) return utf8.len(s) or #s end
local function byteCaret(s,n) return #(utf8.sub(s,1,n) or '') end
local function wrap(text,width)
    local lines,line={},''
    surface.SetFont('DermaDefault')
    for word in text:gmatch('%S+') do
        local nextLine=line=='' and word or line..' '..word
        if surface.GetTextSize(nextLine)>width and line~='' then lines[#lines+1]=line;line=word else line=nextLine end
    end
    if line~='' then lines[#lines+1]=line end
    return lines
end
net.Receive('zcChatAssistCatalog',function()
    local n=net.ReadUInt(16)
    if n>60000 then return end
    local raw=util.Decompress(net.ReadData(n),512000)
    local data=raw and util.JSONToTable(raw)
    if type(data)=='table' then A.commands=data;A.ready=true end
end)
local function request()
    if util.NetworkStringToID('zcChatAssistCatalog')==0 then return end
    net.Start('zcChatAssistCatalog');net.SendToServer()
end
function A.AllowSend(entry,commandMode)
    if not commandMode or not IsValid(entry) then return true end
    if entry:GetText():sub(1,1)=='!' and not A.ready then
        entry.ZCAssistError='Loading command hints. Try again in a moment.'
        request()
        return false
    end
    local ok,err=A.Validate(entry:GetText(),A.commands)
    if not ok then
        entry.ZCAssistError=err
        entry:RequestFocus()
        surface.PlaySound('buttons/button10.wav')
    end
    return ok
end
function A.Attach(entry,commandMode)
    if not IsValid(entry) or A.entries[entry] then return end
    local saved={OnKeyCodeTyped=rawget(entry:GetTable(),'OnKeyCodeTyped'),Think=rawget(entry:GetTable(),'Think')}
    local baseKey,baseThink=entry.OnKeyCodeTyped,entry.Think
    local state={saved=saved,index=1,rows={},mode=commandMode}
    A.entries[entry]=state
    -- Parent to the chat/app root rather than the short composer, to avoid clipping.
    local root=entry:GetParent()
    while IsValid(root:GetParent()) and root:GetParent()~=vgui.GetWorldPanel() do root=root:GetParent() end
    local panel=vgui.Create('DPanel',root)
    state.panel=panel
    panel:SetZPos(32760);panel:SetVisible(false);panel:SetMouseInputEnabled(false)
    panel.Think=function(self) if not IsValid(entry) then self:Remove() end end
    panel.Paint=function(_,w,h)
        draw.RoundedBox(5,0,0,w,h,Color(25,25,30,248))
        local y=6
        for _,line in ipairs(state.hintLines or {}) do
            draw.SimpleText(line,'DermaDefault',8,y,entry.ZCAssistError and red or ghost)
            y=y+18
        end
        for i,row in ipairs(state.rows) do
            if i==state.index then draw.RoundedBox(3,4,y-2,w-8,22,Color(65,55,75)) end
            draw.SimpleText(row.label,'DermaDefault',10,y,ink)
            y=y+24
        end
        if #state.rows>0 then draw.SimpleText('Tab: insert  |  Up/Down: choose  |  Esc: dismiss','DermaDefault',8,y,ghost) end
    end
    local function accept()
        local row=state.rows[state.index]
        if not row or not state.ctx then return false end
        local value,caret=A.Apply(entry:GetText(),state.ctx,row.value)
        if charCount(value)>256 then entry.ZCAssistError='Completion would exceed 256 characters.';return true end
        entry:SetText(value);entry:SetCaretPos(charCount(value:sub(1,caret)))
        -- DTextEntry:SetText does not guarantee OnValueChange (Messages owns a draft).
        if entry.OnValueChange then entry:OnValueChange(value) end
        state.rows={};state.last=nil;state.dismiss=nil
        return true
    end
    state.key=function(self,key,...)
        if panel:IsVisible() and #state.rows>0 then
            if key==KEY_TAB then return accept() end
            if key==KEY_DOWN then state.index=state.index%#state.rows+1;return true end
            if key==KEY_UP then state.index=(state.index-2)%#state.rows+1;return true end
            if key==KEY_ESCAPE then state.dismiss=self:GetText();panel:SetVisible(false);return true end
        end
        if baseKey then return baseKey(self,key,...) end
    end
    entry.OnKeyCodeTyped=state.key
    state.think=function(self,...)
        if baseThink then baseThink(self,...) end
        if not IsValid(panel) then return end
        if not self:HasFocus() or not self:IsVisible() then panel:SetVisible(false);return end
        local text=self:GetText()
        local caret=byteCaret(text,self:GetCaretPos())
        local mode=type(state.mode)=='function' and state.mode() or state.mode==true
        local stamp=text..'\0'..caret..tostring(mode)
        if stamp~=state.last or RealTime()>(state.next or 0) then
            if text~=state.text then self.ZCAssistError=nil;state.dismiss=nil end
            state.text=text;state.last=stamp;state.next=RealTime()+0.5
            state.ctx=A.Context(text,caret,A.commands,mode)
            local names={}
            for _,p in ipairs(player.GetAll()) do if IsValid(p) then names[#names+1]=p:Nick() end end
            state.rows=A.Suggestions(state.ctx,A.commands,names,ZCChatMedia and ZCChatMedia.Emojis or {})
            state.index=math.Clamp(state.index,1,math.max(1,#state.rows))
            local cmd=mode and A.commands[(text:match('^!%S+') or ''):lower()]
            local ok,err=true,nil
            if mode then ok,err=A.Validate(text,A.commands) end
            state.hint=self.ZCAssistError or (cmd and cmd.usage)
            if not ok and self.ZCAssistError then state.hint=err end
        end
        state.hint=self.ZCAssistError or state.hint
        local show=(state.hint or #state.rows>0) and state.dismiss~=text
        panel:SetVisible(show and true or false)
        if not show then return end
        local w=math.min(math.max(self:GetWide(),340),root:GetWide()-8)
        state.hintLines=state.hint and wrap(state.hint,w-16) or {}
        local h=12+#state.hintLines*18+#state.rows*24+(#state.rows>0 and 20 or 0)
        local x,y=self:LocalToScreen(0,0);x,y=root:ScreenToLocal(x,y)
        panel:SetSize(w,h);panel:SetPos(math.Clamp(x,4,math.max(4,root:GetWide()-w-4)),math.max(4,y-h-4))
    end
    entry.Think=state.think
end
function A.Uninstall()
    for entry,state in pairs(A.entries) do
        if IsValid(state.panel) then state.panel:Remove() end
        if IsValid(entry) then
            if entry.OnKeyCodeTyped==state.key then entry.OnKeyCodeTyped=state.saved.OnKeyCodeTyped end
            if entry.Think==state.think then entry.Think=state.saved.Think end
        end
    end
end
hook.Add('Think','ZCChatAssist.Attach',function()
    local chat=hg and hg.chat
    if IsValid(chat) and IsValid(chat.entry) then
        A.Attach(chat.entry,function() return chat.ZCThreadKey=='main' end)
        if RealTime()>(A.nextRequest or 0) and chat:GetActive() then A.nextRequest=RealTime()+15;request() end
    end
    for entry,state in pairs(A.entries) do
        if not IsValid(entry) then
            if IsValid(state.panel) then state.panel:Remove() end
            A.entries[entry]=nil
        end
    end
end)
