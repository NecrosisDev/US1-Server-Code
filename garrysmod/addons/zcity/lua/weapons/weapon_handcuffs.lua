ZCityHostageOwnerCapabilities = ZCityHostageOwnerCapabilities or {}
ZCityHostageOwnerCapabilities["weapons/weapon_handcuffs.lua"] = "20260920.5"
if SERVER then AddCSLuaFile() end
SWEP.Base = "weapon_tpik_base"
SWEP.PrintName = "Handcuffs"
SWEP.Instructions = "Restraint devices designed to secure an individual's wrists in proximity to each other. For the rulers of order in the form of police helps to avoid unnecessary problems when transporting detainees. Sometimes they may not be enough."
SWEP.Category = "ZCity Other"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Wait = 2
SWEP.Primary.Next = 0
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"
SWEP.HoldType = "slam"
SWEP.ViewModel = ""

SWEP.WorldModel = "models/grinchfox/weapons/handcuffs/dropped_handcuffs.mdl"
SWEP.WorldModelReal = "models/grinchfox/weapons/handcuffs/c_handcuffs.mdl"
SWEP.WorldModelExchange = false

if CLIENT then
	SWEP.WepSelectIcon = Material("vgui/wep_jack_hmcd_handcuffs")
	SWEP.IconOverride = "vgui/wep_jack_hmcd_handcuffs"
	SWEP.BounceWeaponIcon = false
end

SWEP.Weight = 0
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.Slot = 3
SWEP.SlotPos = 4
SWEP.WorkWithFake = true

SWEP.setlh = true
SWEP.setrh = true

SWEP.AnimList = {
    -- self:PlayAnim( anim,time,cycling,callback,reverse,sendtoclient )
	["deploy"] = { "anim_draw", 1, false },
    ["attack"] = { "anim_fire", 2.5, false, false, function(self)
		if CLIENT then return end
		local tr = self:GetEyeTrace()
		self:Tie(tr)
	end },
	["idle"] = {"anim_idle", 5, true}
}

SWEP.HoldPos = Vector(0,-1,0)
SWEP.HoldAng = Angle(0,0,0)

SWEP.CallbackTimeAdjust = 0.5

if SERVER then
    function SWEP:OnRemove() end
end

function SWEP:SetHold(value)
	self:SetWeaponHoldType(value)
	self:SetHoldType(value)
	self.holdtype = value
end

function SWEP:SetupDataTables()
	self:NetworkVar("Float", 0, "Holding")
end

function SWEP:Animation()
end

function SWEP:Think()
	self:SetHold(self.HoldType)
end

SWEP.traceLen = 5

function SWEP:GetEyeTrace()
	return hg.eyeTrace( self:GetOwner())
end

if CLIENT then
	function SWEP:DrawHUD()
		if GetViewEntity() ~= LocalPlayer() then return end
		if LocalPlayer():InVehicle() then return end
        local tr = self:GetEyeTrace()
        local toScreen = tr.HitPos:ToScreen()

        surface.SetDrawColor(255,255,255,155)
        surface.DrawRect(toScreen.x-2.5, toScreen.y-2.5, 5, 5)
	end
end

function SWEP:SecondaryAttack()
end

function SWEP:Initialize()
	self:SetHold(self.HoldType)
end

-- Native cuff state is shared by posture, ragdolls, weapons and game modes.
function hg.IsHandcuffed(ent)
    return IsValid(ent) and (ent.handcuffed==true or (ent.organism and ent.organism.handcuffed==true)
        or ent:GetNetVar("handcuffed",false)==true) or false
end
function hg.SetHandcuffed(ent,value)
    if not SERVER or not IsValid(ent) then return false end
    value=value==true
    local owner=ent:IsPlayer() and ent or hg.RagdollOwner(ent)
    local bodies={[ent]=true}
    if IsValid(owner) then
        bodies[owner]=true
        if IsValid(owner.FakeRagdoll) then bodies[owner.FakeRagdoll]=true end
        local fake=owner:GetNWEntity("FakeRagdoll")
        if IsValid(fake) then bodies[fake]=true end
    end
    local changed=false
    for body in pairs(bodies) do
        changed=hg.IsHandcuffed(body)~=value or changed
        body.handcuffed=value
        if body.organism then body.organism.handcuffed=value end
        body:SetNetVar("handcuffed",value)
        if not value and body.handcuffs then
            local parts=body.handcuffs body.handcuffs=nil
            for _,part in pairs(parts) do if IsValid(part) then part:Remove() end end
        end
    end
    if changed then
        local g=ZCityHostage and ZCityHostage.Gameplay
        if g and g.RestraintChanged and IsValid(owner) then g.RestraintChanged(owner) end
    end
    return changed
end

local function handcuff(ragdoll)
    if not SERVER or not IsValid(ragdoll) or not ragdoll:IsRagdoll() then return false end
    if ragdoll.handcuffs and IsValid(ragdoll.handcuffs[1]) and IsValid(ragdoll.handcuffs[2]) then return true end
	local body = ragdoll:GetPhysicsObjectNum(0)
	local lh = ragdoll:GetPhysicsObjectNum(hg.realPhysNum(ragdoll,5))
    local rh = ragdoll:GetPhysicsObjectNum(hg.realPhysNum(ragdoll,7))
    if not IsValid(body) or not IsValid(lh) or not IsValid(rh) then return false end
	lh:SetPos(body:GetPos())

	rh:SetPos(body:GetPos())

	local weld = constraint.Weld(ragdoll, ragdoll, hg.realPhysNum(ragdoll,7), hg.realPhysNum(ragdoll,5), 0, true, false)

    if not IsValid(weld) then return false end
	local handcuffs = ents.Create("prop_physics")
    if not IsValid(handcuffs) then weld:Remove() return false end
	handcuffs:SetModel("models/weapons/spy/w_handcuffs.mdl")
	handcuffs:SetPos(rh:GetPos())

	local ang = rh:GetAngles()
	ang:RotateAroundAxis(ang:Right(),-20)
	handcuffs:SetAngles(ang)

	handcuffs:FollowBone(ragdoll,ragdoll:TranslatePhysBoneToBone(hg.realPhysNum(ragdoll,7)))
	handcuffs:SetMoveType(MOVETYPE_VPHYSICS)
	handcuffs:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
	handcuffs:Spawn()

	ragdoll.handcuffs = {weld, handcuffs}
    hg.SetHandcuffed(ragdoll,true)
    return true
end

hg.handcuff = handcuff

SWEP.CoolDown = 0

function SWEP:Tie(tr)
    if not SERVER or not IsValid(self:GetOwner()) or not tr or not IsValid(tr.Entity) then return false end
    local owner=self:GetOwner()
    if not owner:Alive() or owner:GetActiveWeapon()~=self or not owner.organism or owner.organism.otrub
        or hg.IsHandcuffed(owner) or hg.IsHandcuffed(tr.Entity) then return false end
    if hg.SpecDM and (hg.SpecDM.Entity(owner) or hg.SpecDM.Entity(tr.Entity)) then return false end
    if owner:GetPos():DistToSqr(tr.Entity:GetPos())>96*96 then return false end
    local sight=util.TraceLine({start=owner:EyePos(),endpos=tr.Entity:WorldSpaceCenter(),filter=owner,mask=MASK_SHOT})
    if sight.Hit and sight.Entity~=tr.Entity then return false end
    local g = ZCityHostage and ZCityHostage.Gameplay
    if g and IsValid(tr.Entity) and tr.Entity:IsPlayer() and GetConVar("zch_gameplay_enabled") and GetConVar("zch_gameplay_enabled"):GetBool() then
        local s = g.Committing
        if not (s and s.a == self:GetOwner() and s.v == tr.Entity and s.weapons[s.a] == self) then
            local start = g.StartCuffAction or g.StartCuff
            local ok, why = start(self:GetOwner(), tr.Entity)
            if not ok then self:GetOwner():ChatPrint("Hostage: " .. tostring(why)) end
            return
        end
    end
    local ent = tr.Entity
	--self:EmitSound()
	--timer.Simple(1,function()
		if IsValid(ent) and IsValid(self) and IsValid(self:GetOwner()) and self:GetOwner():Alive() and self:GetOwner():GetPos():Distance(ent:GetPos()) < 500 then 
			if IsValid(ent) and (ent:IsRagdoll() or (ent:IsPlayer() and ent:GetVelocity():Length() < 1)) and hg.RagdollOwner(ent) ~= self:GetOwner() then
				--if ent.handcuffed then return end
				self:GetOwner():ChatPrint("Threat handcuffed.")
				
				if ent:IsRagdoll() and not handcuff(ent) then return false end

				ent:EmitSound("weapons/357/357_reload3.wav")
				ent:PhysWake()

				local org = ent.organism
				if IsValid(hg.RagdollOwner(ent)) and hg.RagdollOwner(ent):Alive() then
					local ply = hg.RagdollOwner(ent)
					ply:SelectWeapon("weapon_hands_sh")

				end
				
				if g and g.Committing then g.Selecting = self:GetOwner() end
				self:GetOwner():SelectWeapon("weapon_hands_sh")
				if g then g.Selecting = nil end

				hg.SetHandcuffed(ent,true)
				self:Remove()
                return true
			end
		end
	--end)
end

if SERVER then
	hook.Add("Org Clear","Removehandcuffs",function(org)
        org.handcuffed=false
        if IsValid(org.owner) then hg.SetHandcuffed(org.owner,false) end
	end)

	hook.Add("Ragdoll_Create","Addhandcuffs", function(ply, ragdoll)
		if hg.IsHandcuffed(ply) or hg.IsHandcuffed(ragdoll) then
			handcuff(ragdoll)
			ply:SelectWeapon("weapon_hands_sh")
		end
	end)

	hook.Add("PlayerCanPickupWeapon","handcuffDisallowpickup",function(ply,ent)
		if hg.IsHandcuffed(ply) and IsValid(ent) and ent:GetClass() != "weapon_handcuffs_key" then
			return false
		end
	end)

	hook.Add("PlayerUse","restrictuser",function(ply, ent)
		if hg.IsHandcuffed(ply) then
			return false
		end
	end)
end

hook.Add("PlayerSwitchWeapon","WeaponSwitchExample",function(ply,oldWeapon,newWeapon)
    if not hg.IsHandcuffed(ply) then return end
    if not IsValid(newWeapon) then return true end
    local class=newWeapon:GetClass()
    if class~="weapon_handcuffs_key" and class~="weapon_hands_sh" then return true end
end)

function SWEP:PrimaryAttack()
    local g = ZCityHostage and ZCityHostage.Gameplay
    if SERVER and g and GetConVar("zch_gameplay_enabled") and GetConVar("zch_gameplay_enabled"):GetBool() then
        local tr = self:GetEyeTrace()
        if IsValid(tr.Entity) and tr.Entity:IsPlayer() then self:Tie(tr) return end
    end
	if SERVER then
		if self.CoolDown > CurTime() then return end
        local tr = self:GetEyeTrace()
		--self:SetHolding(math.min(self:GetHolding() + 7, 100))
		self:PlayAnim("attack")
		timer.Simple(0.5,function()
			if not IsValid(self) then return end
			self:EmitSound("weapons/357/357_reload3.wav")
		end)
		--if self:GetHolding() < 100 then return end
		self.CoolDown = CurTime() + 2
	end
end

function SWEP:Reload()
end
