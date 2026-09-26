ENT.Type = 'anim'
ENT.Base = 'base_anim'
ENT.PrintName = 'Intestine'
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.ZCIntestineSegment = true
ENT.ZCIntestineVersion = '20260920.intestines1'
ENT.HalfLength = 5
ENT.Radius = 1.2
ENT.BoxMin = Vector(-5, -1.2, -1.2)
ENT.BoxMax = Vector(5, 1.2, 1.2)

function ENT:SetupDataTables()
    self:NetworkVar('Entity', 0, 'IntestineBody')
    self:NetworkVar('Float', 0, 'BornAt')
    self:NetworkVar('Bool', 0, 'IntestineTip')
end

-- Identical targeting bounds on both realms; no client physics simulation.
function ENT:TestCollision(startpos, delta, isbox, extents)
    local expand = isbox and extents:Length() or 0
    local v = Vector(expand, expand, expand)
    local pos, normal, fraction = util.IntersectRayWithOBB(startpos, delta,
        self:GetPos(), self:GetAngles(), self.BoxMin - v, self.BoxMax + v)
    if pos then return {HitPos = pos, Normal = normal, Fraction = fraction} end
    return false
end
