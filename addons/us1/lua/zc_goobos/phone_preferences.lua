if not CLIENT then return end
ZCPhoneSettings = {Version="20260923.settings2"}
local S=ZCPhoneSettings
local A,T=ZCGoobApps,ZCGoobApps.Theme
local defaults={
    zc_phone_avatar_size={40,32,48,"Chat avatar size"},
    zc_phone_sender_gap={12,6,24,"Space between different chat senders"},
    zc_phone_bubble_opacity={58,20,90,"Chat bubble opacity"},
    zc_phone_message_duration={4,2,15,"Seconds to show new messages while chat is closed"},
    zc_phone_reduce_motion={0,0,1,"Reduce phone movement effects; keep gentle fades"},
    zc_phone_scroll_wave={100,0,150,"Chat scroll wave strength in percent"},
    zc_phone_typewriter={1,0,1,"Reveal new messages letter by letter"},
    zc_phone_private_alerts={1,0,1,"Show private conversation notification banners"}
}
for name,d in pairs(defaults)do CreateClientConVar(name,tostring(d[1]),true,false,d[4],d[2],d[3]) end
function S.Number(name,fallback)
    local cv=GetConVar(name)
    return cv and cv:GetFloat() or fallback
end
function S.ReducedMotion()return S.Number("zc_phone_reduce_motion",0)==1 end
function S.AvatarSize()return math.Clamp(S.Number("zc_phone_avatar_size",40),32,48)end
S.Sections={"Reading","Motion","Notifications","Media","Privacy"}
S.Options={
    {id="text",section="Reading",label="Text size",help="Adjust message text and the compose bar together.",cv="zchat_fontsize",kind="number",min=5,max=10,step=.5,default=7,reload=false},
    {id="avatar",section="Reading",label="Avatar size",help="Names, avatars and badges still appear once per message chain.",cv="zc_phone_avatar_size",kind="number",min=32,max=48,step=2,default=40,unit=" px"},
    {id="gap",section="Reading",label="Space between senders",help="Keep consecutive messages compact; give different people more room.",cv="zc_phone_sender_gap",kind="number",min=6,max=24,step=2,default=12,unit=" px"},
    {id="opacity",section="Reading",label="Bubble opacity",help="Lower values reveal more of the game behind messages.",cv="zc_phone_bubble_opacity",kind="number",min=20,max=90,step=5,default=58,unit="%"},
    {id="duration",section="Reading",label="New message visibility",help="How long new messages stay visible when the phone is closed.",cv="zc_phone_message_duration",kind="number",min=2,max=15,step=1,default=4,unit=" sec"},
    {id="smoothing",section="Reading",label="Smooth text edges",help="Font anti-aliasing for easier reading.",cv="zchat_fontaa",kind="bool",default=1},
    {id="timestamps",section="Reading",label="Message timestamps",help="Show when messages arrived.",cv="zc_chat_timestamps",kind="bool",default=0},
    {id="group",section="Reading",label="Group consecutive messages",help="Show one name and avatar for a conversation chain.",cv="zc_chat_group",kind="bool",default=1},
    {id="reduce",section="Motion",label="Reduce motion",help="Disable scrolling waves, movement effects and typewriter reveal. Gentle fades remain.",cv="zc_phone_reduce_motion",kind="bool",default=0},
    {id="wave",section="Motion",label="Scroll wave strength",help="0 turns waves off. Every wheel notch still moves exactly one text line.",cv="zc_phone_scroll_wave",kind="number",min=0,max=150,step=10,default=100,unit="%"},
    {id="typewriter",section="Motion",label="Typewriter reveal",help="Fill new messages letter by letter. Reduced motion takes priority.",cv="zc_phone_typewriter",kind="bool",default=1},
    {id="drop",section="Motion",label="Falling letters while deleting",help="Decorative letters when editing your draft. Reduced motion takes priority.",cv="zchat_dropcharacters",kind="bool",default=1},
    {id="banners",section="Notifications",label="System banners",help="Matches the bell in Chat. Vote and moderation prompts remain available.",cookie="zchat_mute_banners",kind="bool",default=1},
    {id="ping",section="Notifications",label="Mention sounds",help="Play a quiet sound when someone mentions you.",cv="zc_chat_ping",kind="bool",default=0},
    {id="private",section="Notifications",label="Private conversation alerts",help="Show PM and group notification banners. Unread tabs still update when disabled.",cv="zc_phone_private_alerts",kind="bool",default=1},
    {id="inline",section="Media",label="Inline media and links",help="When off, replace media links with [media hidden] and stop embedded playback.",cv="zc_chat_inline_media",kind="bool",default=1},
    {id="gif",section="Media",label="Images and animated GIFs",help="Allow image and GIF cards inside messages.",cv="zc_chat_gifs",kind="bool",default=1},
    {id="video",section="Media",label="Video players",help="Allow videos to play inside chat cards.",cv="zc_chat_videos",kind="bool",default=1},
    {id="volume",section="Media",label="Video volume",help="Only affects media played through chat.",cv="zc_chat_video_volume",kind="number",min=0,max=100,step=5,default=40,unit="%"}
}
S.ByID={};for _,spec in ipairs(S.Options)do S.ByID[spec.id]=spec end
function S.Get(id)
    local spec=S.ByID[id];if not spec then return end
    if spec.cookie then return cookie.GetNumber(spec.cookie,0)==1 and 0 or 1 end
    return S.Number(spec.cv,spec.default)
end
function S.Set(id,value)
    local spec=S.ByID[id];value=tonumber(value)
    if not spec or not value or value~=value or math.abs(value)==math.huge then return false end
    if spec.kind=="bool" then value=value>=.5 and 1 or 0
    else value=math.Clamp(math.Round(value,2),spec.min,spec.max) end
    if spec.cookie then
        cookie.Set(spec.cookie,value==1 and "0" or "1")
        local chat=hg and hg.chat
        if IsValid(chat) then
            chat.bannerMuted=value~=1
            if IsValid(chat.bannerMuteButton)then chat.bannerMuteButton:SetTooltip(value==1 and "Mute system banners" or "Unmute system banners")end
            if chat.bannerMuted then
                for _,notice in ipairs(chat.bannerNotices or {})do if IsValid(notice)then notice:Remove()end end
                chat.bannerNotices={}
            end
        end
    else
        local cv=GetConVar(spec.cv)
        if not cv or cv:IsFlagSet(FCVAR_REPLICATED) then return false end
        RunConsoleCommand(spec.cv,tostring(value))
        if id=="private" and value==0 then
            local chat=hg and hg.chat
            if IsValid(chat)then
                chat.ZCPMNotice=nil
                if IsValid(chat.ZCPMNoticeButton)then chat.ZCPMNoticeButton:Remove()end
            end
        end
    end
    return true
end
function S.Reset()
    for _,spec in ipairs(S.Options)do S.Set(spec.id,spec.default)end
end
function S.ResetLayout(phone)
    local width=math.Clamp(ScrW()*.42,384,ScrW()-64)
    local height=math.Clamp(ScrH()*.4,180,ScrH()*.65)
    cookie.Set("zchat_width",width);cookie.Set("zchat_height",height)
    if not IsValid(phone)then return end
    phone.goobGeometry=nil
    phone:SetSize(width,height);phone:SetPos(48,ScrH()-48-height)
    phone:InvalidateLayout(true)
end
function S.RefreshHistory()
    timer.Create("ZCPhoneSettings.Refresh",.12,1,function()
        if hg and IsValid(hg.chat)then RunConsoleCommand("zchat_reload")end
    end)
end
for _,name in ipairs({"zc_phone_avatar_size","zc_phone_sender_gap","zc_chat_group","zc_chat_timestamps"})do
    cvars.AddChangeCallback(name,S.RefreshHistory,"ZCPhoneSettings")
end

-- Row: label (+ optional muted help line) on the left, a fixed-width control slot on the right.
-- Caller attaches its control(s) to the returned row and repositions them in row.PerformLayout.
local function statRow(parent,label,help,rightWidth)
    local K,TT=A.Kit,A.Theme
    local row=K.Panel(parent)
    row:Dock(TOP)
    row:DockMargin(0,0,0,4)
    local hasHelp=help and help~=""
    local tall=hasHelp and 42 or 34
    row:SetTall(tall)
    row.Paint=function(_,w,h)
        local textW=math.max(10,w-rightWidth-14)
        K.Text(K.Fit(label,K.Font(13.5,600),textW),13.5,600,0,hasHelp and 3 or h/2,TT.text,TEXT_ALIGN_LEFT,hasHelp and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
        if hasHelp then K.Text(K.Fit(help,K.Font(11,500),textW),11,500,0,22,TT.muted) end
        surface.SetDrawColor(K.Alpha(TT.hair,120))
        surface.DrawRect(0,h-1,w,1)
    end
    return row
end
S.Row=statRow

-- Stepper half-button: transparent except a hover wash, so the box's own "-"/"+" and value show
-- (a bare DButton paints the Derma skin over them).
local function stepPaint(s,w,h)
    local K,TT=A.Kit,A.Theme
    if K.Hover(s)>0.01 then draw.RoundedBox(4,0,0,w,h,K.Alpha(TT.white,18*s.GoobHover))end
end

-- Secondary full-width action button (kit style, replaces the old A.Button look for footer actions).
local function footerButton(parent,label,onClick)
    local K,TT=A.Kit,A.Theme
    local b=vgui.Create("DButton",parent)
    b:Dock(TOP)
    b:DockMargin(0,4,0,0)
    b:SetTall(34)
    b:SetText("")
    b.DoClick=onClick
    b.Paint=function(s,w,h)
        local hover=K.Hover(s)
        draw.RoundedBox(4,0,0,w,h,TT.card)
        if hover>0.01 then draw.RoundedBox(4,0,0,w,h,K.Alpha(TT.white,14*hover))end
        K.Text(label,13,600,w/2,h/2,TT.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    end
    return b
end
S.FooterButton=footerButton

-- Builds the rows for the phone section currently selected in state.phoneSection (or, while
-- searching, every section's matches). Section switching itself now lives in settings.lua's
-- sidebar / SegmentedControl+Tabs; this only renders the option rows and the footer actions.
function S.BuildPhone(list,root,phone,state,message)
    local K=A.Kit
    state.phoneSection=state.phoneSection or "Reading"
    A.Status(list,"Saved on this device. Changes affect only your phone.")
    local count=0
    for _,spec in ipairs(S.Options)do
        if (state.query~="" or spec.section==state.phoneSection) and A.Matches(spec.label.." "..spec.help.." "..spec.section,state.query)then
            count=count+1
            if spec.kind=="bool" then
                local row=statRow(list,spec.label,spec.help,42)
                local toggle=K.Toggle(row,S.Get(spec.id)==1,function(v)S.Set(spec.id,v and 1 or 0)end)
                toggle.Think=function(t)t.Value=S.Get(spec.id)==1 end
                row.PerformLayout=function(_,w,h)toggle:SetPos(w-38,(h-22)/2)end
            else
                local row=statRow(list,spec.label,spec.help,96)
                local box=K.Panel(row)
                box:SetSize(92,26)
                local dec=vgui.Create("DButton",box);dec:SetText("");dec:SetPos(0,0);dec:SetSize(30,26);dec.Paint=stepPaint
                local inc=vgui.Create("DButton",box);inc:SetText("");inc:SetPos(62,0);inc:SetSize(30,26);inc.Paint=stepPaint
                dec:SetTooltip("Less");inc:SetTooltip("More")
                dec.DoClick=function()S.Set(spec.id,S.Get(spec.id)-spec.step)end
                inc.DoClick=function()S.Set(spec.id,S.Get(spec.id)+spec.step)end
                -- Value label rebuilt only when the value changes (no string building every frame).
                local shown,label
                box.Paint=function(_,w,h)
                    local value=S.Get(spec.id)
                    if value~=shown then
                        shown=value
                        label=(spec.step<1 and string.format("%.1f",value) or tostring(math.Round(value)))..(spec.unit or "")
                    end
                    draw.RoundedBox(4,0,0,w,h,T.card)
                    local lo,hi=value<=spec.min,value>=spec.max
                    K.Text("\226\136\146",13,700,10,h/2,lo and K.Alpha(T.muted,90) or T.muted,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
                    K.Text("+",13,700,w-10,h/2,hi and K.Alpha(T.muted,90) or T.muted,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)
                    K.Text(label,13,500,w/2,h/2,T.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
                end
                row.PerformLayout=function(_,w,h)box:SetPos(w-92,(h-26)/2)end
            end
        end
    end
    if state.phoneSection=="Privacy" and state.query=="" then
        -- Same row style as the options above: one row per hidden sender with an "Unhide" pill.
        statRow(list,"Hidden media senders","Players whose media you chose to hide. PM/group access and spectator rules are unchanged.",0)
        local M=ZCChatMedia
        local ids={};for id in pairs(M and M.Hidden or {})do ids[#ids+1]=id end;table.sort(ids)
        if #ids==0 then statRow(list,"No hidden senders","",0)end
        for _,id in ipairs(ids)do
            local name="Steam "..id
            for _,ply in ipairs(player.GetHumans())do if ply:SteamID64()==id then name=ply:Nick();break end end
            local row=statRow(list,name,"Media hidden",86)
            local unhide=vgui.Create("DButton",row)
            unhide:SetText("")
            unhide.DoClick=function()M.SetHidden(id,false);list:RefreshSettings()end
            unhide.Paint=function(s,w,h)
                draw.RoundedBox(4,0,0,w,h,K.Hover(s)>0.01 and T.hover or T.card)
                K.Text("Unhide",12,600,w/2,h/2,T.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
            end
            row.PerformLayout=function(_,w,h)unhide:SetPos(w-82,(h-26)/2);unhide:SetSize(82,26)end
        end
        A.Status(list,"Private conversations remain private. Staff inspection and spectator protections are controlled by the server.")
        count=count+1
    end
    if count==0 then A.Status(list,"No matching phone settings.")end
    footerButton(list,"Reset window size",function()
        K.Modal(root,"Reset window size?","Restore the default size at the 48 px screen anchor. Messages and drafts stay intact.",{
            {"Cancel"},
            {"Reset",function()S.ResetLayout(phone)end,primary=true}
        })
    end)
    footerButton(list,"Restore phone defaults",function()
        K.Modal(root,"Restore phone defaults?","Reset only the options in the Phone view. Chat history, drafts, hidden senders, game settings and keybinds stay intact.",{
            {"Cancel"},
            {"Restore",function()S.Reset();if IsValid(message)then message:SetText("Phone defaults restored.")end end,primary=true}
        })
    end)
end
