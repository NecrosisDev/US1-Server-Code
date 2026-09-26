include('shared.lua')

function ENT:Initialize()
    self:SetCollisionBounds(self.BoxMin, self.BoxMax)
    self:SetSolid(SOLID_OBB)
    self:EnableCustomCollisions()
    self:SetRenderBounds(Vector(-7, -3, -3), Vector(7, 3, 3))
end

function ENT:Draw()
    local v = ZCityGoreIntestinesVisuals
    if v then v.DrawSegment(self) end
end
