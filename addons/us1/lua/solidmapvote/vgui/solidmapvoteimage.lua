
local PANEL = {}

AccessorFunc( PANEL, 's_imageurl', 'ImageURL', FORCE_STRING )

function PANEL:Init()
    self.imageWidth = 1
    self.imageHeight = 1

    self:SetImageURL( '' )
    self:SetText( '' )
    
    self:SetCursor( 'hand' )
end

function PANEL:SetImageSize( w, h )
    self.imageWidth = math.max(1, tonumber(w) or 1)
    self.imageHeight = math.max(1, tonumber(h) or 1)
end

function PANEL:Paint( w, h )
    local adjustedWidth = (self.imageWidth/self.imageHeight) * h
    local offset = w*0.5 - adjustedWidth*0.5

    SolidMapVote.DrawWebImage( self:GetImageURL(), offset, 0, adjustedWidth, h, Color( 255, 255, 255 ) )
end

function PANEL:DoClick()
    self:GetParent():DoClick()
end

vgui.Register( 'SolidMapVoteImage', PANEL, 'DButton' )
