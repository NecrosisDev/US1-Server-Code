--

----
local PANEL = { ZCUIRecoveryVersion="20260916.1" }
--[[
hg.VGUI.SecondaryColor = Color(155,0,0,240)
hg.VGUI.BackgroundColor = Color(25,25,35,220)]]
local color_blacky = Color(25,25,30,220)
local color_reddy = Color(155,0,0,240)

function PANEL:Init()
    self.Itensens = {}
    self:SetAlpha( 0 )
    self:SetTitle( "" )

    self.DrawBorder = true

    self.ColorBG = Color(color_blacky:Unpack())
    self.ColorBR = Color(color_reddy:Unpack())
    self.BlurStrengh = 2

    timer.Simple(0,function()
        if IsValid(self) and not self.Closing and self.First then
            self:First()
        end
    end)
end

function PANEL:Paint(w,h)
    draw.RoundedBox(0,0,0,w,h,self.ColorBG)
    if hg and isfunction(hg.DrawBlur) then hg.DrawBlur(self, self.BlurStrengh) end

    if self.DrawBorder then
        surface.SetDrawColor(self.ColorBR)
        surface.DrawOutlinedRect(0,0,w,h,1.5)
    end
end

function PANEL:SetBorder( bDraw )
    self.DrawBorder = bDraw
end

function PANEL:SetColorBG( cColor )
    self.ColorBG = cColor
end

function PANEL:SetColorBR( cColor )
    self.ColorBR = cColor
end

function PANEL:SetBlurStrengh( floatVal )
    self.BlurStrengh = floatVal
end

function PANEL:First( ply )
    self:SetY(self:GetY() + self:GetTall())
    self:MoveTo(self:GetX(), self:GetY() - self:GetTall(), 0.4, 0, 0.2, function() end)
    self:AlphaTo( 255, 0.2, 0.1, nil )

    if self.PostInit then
        self:PostInit()
    end
end

function PANEL:Close()
    if self.Closing then return end
    self.Closing=true
    self:SetKeyboardInputEnabled(false)
    self:SetMouseInputEnabled(false)
    local function finish()
        if not IsValid(self) or self.ZCCloseFinished then return end
        self.ZCCloseFinished=true
        local ok,err=true,nil
        if self.OnClose then ok,err=xpcall(function()self:OnClose()end,debug.traceback)end
        if IsValid(self)then self:Remove()end
        if not ok then ErrorNoHalt("[ZCity UI] OnClose failed: "..tostring(err).."\n")end
    end
    -- Also remove when the animation completion callback is interrupted.
    timer.Simple(0.3,finish)
    self:MoveTo(self:GetX(),ScrH()/2+self:GetTall(),5,0,0.3,function()end)
    self:AlphaTo(0,0.2,0,finish)
end

vgui.Register( "ZFrame", PANEL, "DFrame")

