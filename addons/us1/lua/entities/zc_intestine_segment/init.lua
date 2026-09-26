AddCSLuaFile('shared.lua')
AddCSLuaFile('cl_init.lua')
include('shared.lua')

function ENT:Initialize()
    -- Source traces inherit the model's surface even with a flesh PhysicsInitBox.
    -- A flesh model keeps hammer targeting and impact effects consistent.
    self:SetModel('models/Gibs/HGIBS_rib.mdl') -- Bounds/visuals are defined here.
    self:PhysicsInitBox(self.BoxMin, self.BoxMax, 'flesh')
    self:SetSolid(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:EnableCustomCollisions()
    self:SetCustomCollisionCheck(true)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    self:DrawShadow(false)
    self.DoNotDuplicate = true
    local phys = self:GetPhysicsObject()
    if not IsValid(phys) then self:Remove(); return end
    phys:SetMass(0.35)
    phys:SetMaterial('flesh')
    phys:SetDamping(0.5, 2)
    phys:AddGameFlag(FVPHYSICS_NO_IMPACT_DMG)
end

function ENT:OnTakeDamage(dmg)
    self:TakePhysicsDamage(dmg)
end

function ENT:OnRemove()
    local g = self.ZCIntestineGroup
    if g and ZCityGoreIntestines then ZCityGoreIntestines.RemoveGroup(g) end
end
