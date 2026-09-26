hg.achievements = hg.achievements or {}
hg.achievements.achievements_data = hg.achievements.achievements_data or {}
hg.achievements.achievements_data.player_achievements = hg.achievements.achievements_data.player_achievements or {}
hg.achievements.achievements_data.created_achevements = {}

hg.achievements.MenuPanel = hg.achievements.MenuPanel or nil

local curent_panel_ach  
concommand.Add("hg_achievements",function()
    if ZCGoobApps and ZCGoobApps.Launch("progress") then return end
    --hg.DrawAchievmentsMenu() doesn't work as for 15.02.2026 | from bogler with love 🥴
    print('use esc menu')
end)

BlurBackground = BlurBackground or hg.DrawBlur
local gradient_u = Material("vgui/gradient-u")
gradient_r = Material("vgui/gradient-r")

local function PaintButton(self,w,h)
    surface.SetDrawColor(155, 0, 0, 108)
    surface.SetMaterial(gradient_l)
    surface.DrawTexturedRect( 0, 0, w, h )
end

local function createButton(frame, ach, text, func)
    local button = vgui.Create("DButton", frame)

    ach.img = isstring(ach.img) and Material(ach.img) or ach.img
    
    local localach = hg.achievements.GetLocalAchievements()
    local desc = markup.Parse("<font=HomigradFontMedium>"..ach.description.."<font>", 500 )
    
    local x,y = frame:LocalToScreen(button:GetPos())
    function button:Paint(w,h)
		PaintButton(self,w,h)
        local view = render.GetViewSetup(true)
        local pos,ang = view.origin,view.angles
        ang:RotateAroundAxis( ang:Up(), -90 )
	    ang:RotateAroundAxis( ang:Forward(), 90 )
        
        self.lerpcolor = Lerp(FrameTime() * 10,self.lerpcolor or 0,self:IsHovered() and 255 or 0)
       
        local val = localach[ach.key] and localach[ach.key].value or ach.start_value
        local amt = ScreenScale(1)

        surface.SetFont("HomigradFont") 
        local txt = ach.name..(ach.showpercent and " | " or "")..(ach.showpercent and (val / ach.needed_value * 100).."%" or "")
        local wt,ht = surface.GetTextSize(txt)
        surface.SetTextColor(255,255,255)
        surface.SetTextPos(w / 2 - (wt / 2), (ht / 2) * (1-(self.lerpcolor / 255)*5))
        surface.DrawText(txt)

        desc:Draw(w / 2,(h + desc:GetHeight()) - ((h/2) + desc:GetHeight()) * (self.lerpcolor / 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        surface.SetDrawColor(255,255,255,10)
        draw.NoTexture()
        surface.DrawTexturedRectRotated(w - self.lerpcolor / 255 * 100 + 50,0,10,400,-30)
        surface.DrawTexturedRectRotated(w - self.lerpcolor / 255 * 100 + 80,0,10,400,-30)
    end

    button:SetText("")
    button:SetSize(0,ScreenScale(22))
    button:Dock(TOP)
    button:DockMargin(0,0,0,ScreenScale(2.5))
    button.DoClick = function(self) func(self) end
    return button
end

local function createButton_2(frame, ach, text, func, y)
    local button = vgui.Create("DButton", frame)

    ach.img = isstring(ach.img) and Material(ach.img) or ach.img
    
    local localach = hg.achievements.GetLocalAchievements()
    local desc = markup.Parse("<font=HomigradFontMedium>"..ach.description.."<font>", 500 )
    
    function button:Paint(w,h)
        PaintButton(self,w,h)
        local view = render.GetViewSetup(true)
        local pos,ang = view.origin,view.angles
        ang:RotateAroundAxis( ang:Up(), -90 )
        ang:RotateAroundAxis( ang:Forward(), 90 )
                
        local val = localach[ach.key] and localach[ach.key].value or ach.start_value
        local amt = ScreenScale(1)

        surface.SetFont("HomigradFont") 
        
        self.HoverLerp = LerpFT(0.2, self.HoverLerp or 0, curent_panel_ach == ach and 1 or 0)
        
        local base = (curent_panel_ach == ach and string.upper(ach.name) or ach.name)..(ach.showpercent and " | " or "")..(ach.showpercent and (val / ach.needed_value * 100).."%" or "")
        
        local result = ""
        for i = 1, #base do
            result = result .. (i <= math.ceil(#base * self.HoverLerp) and string.upper(base:sub(i,i)) or base:sub(i,i))
        end
        
        local wt,ht = surface.GetTextSize(result)
        surface.SetTextColor(255,255,255)
        surface.SetTextPos(3, (ht / 2))
        surface.DrawText(result)
    end

    button:SetText("")
    button:SetSize(frame:GetWide(),ScreenScale(22))

    button:SetPos(0,y)
    button.DoClick = function(self) 
        curent_panel_ach = ach
        func(self)
		for i = 1, 3 do
			surface.PlaySound("shitty/tap_depress.wav")
		end
    end
    return button
end

local gradient_d = Material("vgui/gradient-d")
local function PaintFrame(self,w,h)
	BlurBackground(self)
    surface.SetDrawColor(50, 0, 0, 155)
    surface.SetMaterial(gradient_d)
    surface.DrawTexturedRect( 0, 0, w, h )

	surface.SetDrawColor( 150, 0, 0, 128)
    surface.DrawOutlinedRect( 0, 0, w, h, 2.5 )
end

function hg.DrawAchievmentsMenu(ParentPanel)
    hg.achievements.LoadAchievements()

    if IsValid(hg.achievements.MenuPanel) then
        hg.achievements.MenuPanel:Remove()
        hg.achievements.MenuPanel = nil
    end

    local frame
    if ParentPanel then
        ParentPanel:SetAlpha(0)
        ParentPanel.Paint = function(self,w,h)
            surface.SetDrawColor(28,28,28,255)
            surface.DrawRect(0, 0, w, h)

            surface.SetDrawColor(107, 107, 107,20)
            for i = 1, (ybars + 1) do
                surface.DrawRect((sw / ybars) * i - (CurTime() * 30 % (sw / ybars)), 0, ScreenScale(1), sh)
            end

            for i = 1, (xbars + 1) do
                surface.DrawRect(0, (sh / xbars) * (i - 1) + (CurTime() * 30 % (sh / xbars)), sw, ScreenScale(1))
            end

            local border_size = ScreenScale(2)

            surface.SetDrawColor(0, 0, 0)
            surface.SetMaterial(gradient_l)
            surface.DrawTexturedRect(0, 0, border_size, sh)
        end

    end
    hg.DrawBlur(ParentPanel, 5)
    ParentPanel:AlphaTo(255,0.15,0)
    local frame = vgui.Create('DPanel', ParentPanel)
    frame:SetSize(ParentPanel:GetWide()/2.5, ScreenScale(22)*8.25+ScreenScale(2.5))
    frame:SetPos(5, ParentPanel:GetTall()/2 - frame:GetTall()/2)
    frame.Paint = function()
    end

    hg.achievements.MenuPanel = frame

    local scroll = vgui.Create("DScrollPanel",frame)
    scroll:SetSize(frame:GetWide(),frame:GetTall())
    scroll:SetPos(0,0)

    frame.scroll = scroll

    local sbar = scroll:GetVBar()
    sbar:SetWide(0)
    sbar:SetHideButtons(true)
    function sbar:Paint(w, h)
        draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 100))
    end
    function sbar.btnGrip:Paint(w, h)
        self.lerpcolor = Lerp(FrameTime() * 10, self.lerpcolor or 0.2,(self:IsHovered() and 0.8 or 0.6))
        draw.RoundedBox(0, 0, 0, w, h, Color(100 * self.lerpcolor, 10, 10))
    end

    function frame:UpdateValues()
        local scroll = self.scroll
        scroll:Clear()
        
        local y = 0
        for i,ach in pairs(hg.achievements.achievements_data.created_achevements) do
            local bbb = createButton_2(scroll, ach, ach.name, function() end,y)
            y = bbb:GetTall() + y + 3
            scroll:AddItem(bbb)
            curent_panel_ach = ach
        end

    end
    local y = 0
    for i,ach in pairs(hg.achievements.achievements_data.created_achevements) do
        local bbb = createButton_2(scroll, ach, ach.name, function() end,y)
        y = bbb:GetTall() + y + 3
        scroll:AddItem(bbb)
        curent_panel_ach = ach
    end
    local frame2 = vgui.Create('DPanel', ParentPanel)
    frame2:SetSize(ParentPanel:GetWide()/2, ScreenScale(22)*8.25+ScreenScale(2.5))
    frame2:Center()
    frame2:SetPos(frame:GetX()+frame:GetWide(),frame:GetY())
    frame2.Paint = function(self,w,h)
        surface.SetDrawColor(92,0,0,108)
        surface.SetMaterial(gradient_d)
        surface.DrawTexturedRect(0,0,w,h)
        surface.SetDrawColor(40,36,36,255)
        surface.DrawRect(0,h-h/6,w,h/6)
        surface.SetDrawColor(22,21,21)
        surface.DrawRect(0,h-3,w,3)
        
        if curent_panel_ach then
            self.HoverLerp = LerpFT(0.2,self.HoverLerp or 0,1)
            
            surface.SetDrawColor(255,255,255,255)
            surface.SetMaterial(curent_panel_ach.img)
            surface.DrawTexturedRect(w/2-w/10,h/2-w/5,w/5,w/5)
            
            surface.SetFont("ZCity_Small")
            local name = curent_panel_ach.name
            local res = ""
            for i=1,#name do
                res=res..(i<=math.ceil(#name*self.HoverLerp)and name:sub(i,i)or "")
            end
            local wt,ht=surface.GetTextSize(res)
            surface.SetTextColor(255,255,255)
            surface.SetTextPos(w/2-wt/2,h-h/6)
            surface.DrawText(res)
            
            surface.SetFont("ZCity_Tiny")
            local desc = curent_panel_ach.description
            local res2 = ""
            for i=1,#desc do
                res2=res2..(i<=math.ceil(#desc*self.HoverLerp)and desc:sub(i,i)or "")
            end
            local lines=string.Explode("\n",res2:gsub("\\n","\n"))
            surface.SetTextColor(170,170,170)
            local lnh=ht/2
            for i,line in ipairs(lines) do
                local wt,ht=surface.GetTextSize(line)
                surface.SetTextPos(w/2-wt/2,h-h/12+(i-1)*lnh)
                surface.DrawText(line)
            end
        end
    end
end

local time_wait = 0
function hg.achievements.LoadAchievements()
    if time_wait > CurTime() then return end
    time_wait = CurTime() + 2

    net.Start("req_ach")
    net.SendToServer()
end

function hg.achievements.GetLocalAchievements()
    return hg.achievements.achievements_data.player_achievements[tostring(LocalPlayer():SteamID())]
end

net.Receive("req_ach",function()
    hg.achievements.achievements_data.created_achevements = net.ReadTable()
    hg.achievements.achievements_data.player_achievements[tostring(LocalPlayer():SteamID())] = net.ReadTable()
    
    if IsValid(hg.achievements.MenuPanel) then
        hg.achievements.MenuPanel:UpdateValues()
    end
end)

hg.achievements.NewAchievements = hg.achievements.NewAchievements or {}
local AchTable = hg.achievements.NewAchievements 
net.Receive("hg_NewAchievement",function()
    local Ach = {time = CurTime() + 7.5,name = net.ReadString(),img = net.ReadString(),born = RealTime(),dies = RealTime() + 7.5}
    table.insert(AchTable,1,Ach)
	surface.PlaySound("homigrad/vgui/achievement_earned.wav")
end)

local ach_clr1 , ach_clr2 = Color(200,25,25), Color(100,25,25)
-- Toasts (2026-09-25 HUD pass): GoobOS plates stacked top-left from y 72 (below the restart strip), newest on top.
-- Each slides in from the left and fades in over 0.25 s, fades out in place over 0.25 s (RealTime); the stack offset is
-- the sum of the eased heights above, so the stack closes smoothly.
local TOAST_FADE = 0.25
local function toastEase(t)
    t = math.Clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end
-- Pre-restyle drawing, verbatim from the live A+B file; used when the GoobOS kit is not loaded.
local legacyDraw = function()
    local count = #AchTable
    if count == 0 then return end
    local rnow = RealTime()
    local scrW, scrH = ScrW(), ScrH()
    local HSize = scrH * 0.05
    local offset = 0
    surface.SetFont("HomigradFontMedium")
    for i = 1, count do
        local ach = AchTable[i]
        if not ach then continue end
        ach.born = ach.born or rnow
        ach.dies = ach.dies or (ach.born + math.max((ach.time or 0) - CurTime(), 0))
        if not ach.txt then
            ach.txt = "Achievement! " .. ach.name
            ach.wt = surface.GetTextSize(ach.txt)
        end
        if isstring(ach.img) then ach.img = Material(ach.img) end
        local txt, wt = ach.txt, ach.wt
        local visIn = toastEase((rnow - ach.born) / TOAST_FADE)
        local vis = visIn * toastEase((ach.dies - rnow) / TOAST_FADE)

        local WSize = (scrW * 0.1) + wt
        local HPos = math.floor(scrH - HSize - offset + HSize * (1 - visIn))
        offset = offset + HSize * vis
        surface.SetAlphaMultiplier(vis)
        draw.RoundedBox( 0, 2, HPos + 2, WSize - 4, HSize - 4, ach_clr2 )
		
		surface.SetDrawColor(155, 0, 0, 255)
		surface.SetMaterial(gradient_u)
		surface.DrawTexturedRect( 0, HPos, WSize, HSize )
	
		surface.SetDrawColor( 150, 0, 0, 255)
		surface.DrawOutlinedRect( 0, HPos, WSize, HSize, 2.5 )

        surface.SetFont("HomigradFontMedium")
        surface.SetTextColor(255,255,255)
        surface.SetTextPos(HSize*1.25,(HPos + ( HSize/2 ) - ( HSize/4 )) )
        surface.DrawText(txt)
        surface.SetDrawColor(255,255,255)
        surface.SetMaterial(ach.img)
        surface.DrawTexturedRect(2,HPos+2,HSize-4,HSize-4)
        surface.SetAlphaMultiplier(1)
    end
    for i = count, 1, -1 do
        local ach = AchTable[i]
        if ach and ach.dies and ach.dies < rnow then table.remove(AchTable, i) end
    end
end

hook.Add("HUDPaint","hg_NewAchievement", function()
    local rnow = RealTime()
    -- expiry runs whether or not the kit is loaded
    for i = #AchTable, 1, -1 do
        local ach = AchTable[i]
        if ach and ach.dies and ach.dies < rnow then table.remove(AchTable, i) end
    end
    local count = #AchTable
    if count == 0 then return end
    local K = ZCGoobApps and ZCGoobApps.Kit
    local T = ZCGoobApps and ZCGoobApps.Theme
    if not (K and K.HudPlate and T) then return legacyDraw() end
    local s = K.HudScale()
    local HSize, gap = math.floor(54 * s), math.floor(8 * s)
    local icon = math.floor(40 * s)
    local labelFont, nameFont = K.HudFont(11, 700), K.HudFont(18, 600)
    local offset = 0
    for i = 1, count do
        local ach = AchTable[i]
        if not ach then continue end
        ach.born = ach.born or rnow
        ach.dies = ach.dies or (ach.born + math.max((ach.time or 0) - CurTime(), 0))
        if isstring(ach.img) then ach.img = Material(ach.img) end
        if ach.font ~= nameFont then
            surface.SetFont(nameFont)
            ach.font, ach.wt = nameFont, surface.GetTextSize(ach.name)
        end
        local visIn = toastEase((rnow - ach.born) / TOAST_FADE)
        local vis = visIn * toastEase((ach.dies - rnow) / TOAST_FADE)

        local w = math.max(math.floor(300 * s), math.floor(7 * s) + icon + math.floor(28 * s) + ach.wt)
        local x = math.floor(16 * s - (1 - visIn) * 24 * s)
        local y = math.floor(72 * s + offset)
        offset = offset + (HSize + gap) * vis
        K.HudPlate(x, y, w, HSize, vis)
        local ix, iy = x + math.floor(7 * s), y + math.floor((HSize - icon) / 2)
        draw.RoundedBox(3, ix, iy, icon, icon, K.Alpha(T.main, 70 * vis))
        surface.SetDrawColor(255, 255, 255, 255 * vis)
        surface.SetMaterial(ach.img)
        surface.DrawTexturedRect(ix + math.floor(4 * s), iy + math.floor(4 * s), icon - math.floor(8 * s), icon - math.floor(8 * s))
        local tx = ix + icon + math.floor(12 * s)
        draw.SimpleText("ACHIEVEMENT", labelFont, tx, y + math.floor(HSize / 2) - math.floor(2 * s), K.Alpha(T.muted, 255 * vis), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        K.HudText(ach.name, nameFont, tx, y + math.floor(HSize / 2), nil, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, vis)
    end
end)