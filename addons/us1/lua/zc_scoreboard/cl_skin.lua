if not CLIENT then return end
local S=ZCScoreboard
local H=S.Services
local K={};S.Skin=K
function K.Fonts()
 local face=H.String("font_body","Bahnschrift")
 local title=H.String("font_title","Bahnschrift")
 local key=face..title..tostring(H.Scale(100))
 if K.FontKey==key then return end
 K.FontKey=key
 for name,spec in pairs({Hero={34,750},Title={22,650},Name={18,650},Body={15,500},Label={12,650},Number={20,650}})do
  surface.CreateFont("ZCRoster."..name,{font=(name=="Hero"or name=="Title")and title or face,size=H.Scale(spec[1]),weight=spec[2],antialias=true,extended=true})
 end
end
K.Fonts()
function K.Colors()
 if K.Palette and K.Source==PATSB.Settings then return K.Palette end
 K.Source=PATSB.Settings
 local c=H.Colors()
 local function warm(v,r,g,b)return Color(math.min(v.r+r,255),math.max(v.g+g,0),math.max(v.b+b,0),v.a)end
 local accent=c.accent
 K.Palette={bg=c.bg,panel=c.card,hover=warm(c.hover,14,-4,-6),
  text=c.text,muted=c.muted,accent=accent,line=Color(accent.r,accent.g,accent.b,45),soft=Color(accent.r,accent.g,accent.b,16),
  warm=Color(236,192,122),white=c.text}
 return K.Palette
end
function K.Hover(panel)
 panel.HoverAmount=Lerp(math.Clamp(FrameTime()*14,0,1),panel.HoverAmount or 0,panel:IsHovered()and 1 or 0)
 return panel.HoverAmount
end
function K.Mix(t,a,b)
 return Color(Lerp(t,a.r,b.r),Lerp(t,a.g,b.g),Lerp(t,a.b,b.b),Lerp(t,a.a,b.a))
end
function K.Card(w,h,hover,selected)
 local c=K.Colors()
 local background=selected and c.soft or isnumber(hover)and K.Mix(hover,c.panel,c.hover)or hover and c.hover or c.panel
 draw.RoundedBox(4,0,0,w,h,c.line)
 draw.RoundedBox(3,1,1,w-2,h-2,background)
 if selected then draw.RoundedBox(2,0,14,3,h-28,c.accent)end
end
function K.Text(text,font,x,y,color,ax,ay)
 draw.SimpleText(text,"ZCRoster."..font,x,y,color or K.Colors().text,ax or TEXT_ALIGN_LEFT,ay or TEXT_ALIGN_TOP)
end
function K.Label(parent,font,text,color)
 local p=vgui.Create("DLabel",parent);p:SetFont("ZCRoster."..font);p:SetText(text or "");p:SetTextColor(color or K.Colors().text)
 return p
end
function K.SetText(panel,text)
 text=tostring(text or "");if panel.LastText~=text then panel.LastText=text;panel:SetText(text)end
end
function K.StyleButton(b,text)
 b:SetText("");b.Caption=text
 b.Paint=function(p,w,h)
  local c=K.Colors();local selected=p.Selected and p:Selected()
  draw.RoundedBox(4,0,0,w,h,selected and c.soft or K.Mix(K.Hover(p),c.panel,c.hover))
  K.Text(p.Caption,"Body",w/2,h/2,selected and c.accent or c.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
 end
 return b
end
function K.Button(parent,text,action)
 local b=K.StyleButton(vgui.Create("DButton",parent),text);b.DoClick=action;return b
end
function K.Scrollbar(scroll)
 local bar=scroll:GetVBar();bar:SetWide(H.Scale(10));bar.Paint=function()end
 bar.btnUp.Paint=function()end;bar.btnDown.Paint=function()end
 bar.btnGrip.Paint=function(p,w,h)draw.RoundedBox(w/2,2,0,math.max(1,w-4),h,K.Mix(K.Hover(p),K.Colors().line,K.Colors().accent))end
end
function K.VoicePopup(frame,player,slider,hint,reset,close)
 frame:SetTitle("");frame:ShowCloseButton(false)
 frame.Paint=function(_,w,h)K.Card(w,h,false,false)end
 local title=K.Label(frame,"Name","Voice · "..player:Nick())
 title:SetPos(H.Scale(12),H.Scale(10));title:SetSize(frame:GetWide()-H.Scale(24),H.Scale(24));title:SetTooltip(player:Nick())
 hint:SetText("Only you hear these changes.");hint:SetTextColor(K.Colors().muted)
 K.StyleButton(reset,"Reset volume");K.StyleButton(close,"Done")
end
function K.Speaker(x,y,size,muted)
 local c=K.Colors();surface.SetDrawColor(muted and c.muted or c.accent)
 surface.DrawRect(x,y+size*.35,size*.22,size*.3)
 surface.DrawLine(x+size*.22,y+size*.35,x+size*.5,y+size*.13)
 surface.DrawLine(x+size*.5,y+size*.13,x+size*.5,y+size*.87)
 surface.DrawLine(x+size*.5,y+size*.87,x+size*.22,y+size*.65)
 if muted then
  surface.DrawLine(x+size*.7,y+size*.32,x+size,y+size*.68)
  surface.DrawLine(x+size,y+size*.32,x+size*.7,y+size*.68)
 else
  surface.DrawLine(x+size*.72,y+size*.3,x+size*.9,y+size*.5)
  surface.DrawLine(x+size*.9,y+size*.5,x+size*.72,y+size*.7)
 end
end

-- =================================================================================================
-- Kit skin (GoobOS rework, Phase 4): scoreboard-specific helpers built on ZCGoobApps.Kit /
-- ZCGoobApps.Theme. Used only by cl_view.lua's kit builder, behind zc_goobos_scoreboard=1 with the
-- kit mounted. The legacy K above (PATSB.Settings-themed) is untouched and stays the skin for
-- convar 0 -- see mockups/10_scoreboard.html ("What changed vs live").
local KK = {}
S.KitSkin = KK

-- Ping colour thresholds carried from the mockup notes (green < 60, gold < 120, red >= 120): not
-- sourced from a live constant, flagged there as unverified against any live threshold.
function KK.PingColor(T, ping)
    ping = tonumber(ping) or 0
    if ping < 60 then return T.green end
    if ping < 120 then return T.gold end
    return T.red
end

-- Spectator ring colour (mockup's ring-spec token, #B4B4B4): spectating is a status, not a team.
KK.SpectatorRing = Color(180, 180, 180)

-- Team key/label/ring for a roster row. Team assignment already lives on data.entity (existing,
-- public roster data -- no hidden role or new data source); team.GetName/team.GetColor are the
-- stock GMod team library. Spectators are grouped by status instead of by team.
function KK.TeamInfo(data)
    if data.spectator then return "spectators", "Spectators", KK.SpectatorRing end
    local id = IsValid(data.entity) and data.entity:Team() or 0
    local name = (team.GetName and team.GetName(id)) or "Players"
    local color = (team.GetColor and team.GetColor(id)) or KK.SpectatorRing
    return "team" .. tostring(id), name, color
end

-- Restyle a DScrollPanel's vbar to kit tokens (same shape as K.Scrollbar above, off T instead of
-- the legacy PATSB palette).
function KK.Scrollbar(scroll, T)
    local bar = scroll:GetVBar()
    bar:SetWide(6)
    bar.Paint = function() end
    bar.btnUp.Paint = function() end
    bar.btnDown.Paint = function() end
    bar.btnGrip.Paint = function(p, w, h)
        local hover = ZCGoobApps.Kit.Hover(p)
        draw.RoundedBox(w / 2, 1, 0, math.max(1, w - 2), h, hover > 0.01 and T.main or T.line)
    end
end
