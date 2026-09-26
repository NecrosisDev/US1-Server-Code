SWEP.PrintName = "Defibrilator"
if CLIENT then
	SWEP.WepSelectIcon = Material("materials/entities/weapon_defibrilator.png")
	SWEP.IconOverride = "materials/entities/weapon_defibrilator.png"
	SWEP.BounceWeaponIcon = false
end
SWEP.PrintName = "Defibrilator"
SWEP.Category = "ZCity Medicine"
SWEP.Instructions = "A defibrilator. Can be used to resuscitate unconscious or near death players. LMB / RMB to use on others."
SWEP.Spawnable = true
SWEP.AdminSpawnable = true
SWEP.AdminOnly = false

SWEP.ViewModelFOV = 75
SWEP.ViewModel = "models/weapons/defib/v_defibrillator.mdl"
SWEP.WorldModel = "models/weapons/defib/w_eq_defibrillator.mdl"
SWEP.ViewModelFlip = false
SWEP.BobScale = 1
SWEP.SwayScale = 1
SWEP.UseHands = true
SWEP.modeValues = SWEP.modeValues or {}
SWEP.modeValuesdef = SWEP.modeValuesdef or {}

SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false
SWEP.Weight = 0
SWEP.Slot = 5
SWEP.SlotPos = 10
SWEP.HoldType = "duel"
SWEP.FiresUnderwater = true
SWEP.DrawCrosshair = true
SWEP.DrawAmmo = true
SWEP.CSMuzzleFlashes = 1
SWEP.Base = "weapon_base"
SWEP.ShowViewModel = true
SWEP.ShowWorldModel = false
SWEP.WorkWithFake = false

SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Primary.Delay = 0.2

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"
SWEP.Secondary.Delay = 0.2

SWEP.usetime = 4.0
SWEP.DefibCooldown = 1.25

local STATE_NONE, STATE_PROGRESS, STATE_ERROR = 0, 1, 2
local color_red = Color(255, 0, 0)
local color_green = Color(0, 200, 80)
local color_white = Color(255, 255, 255)

if CLIENT then
    surface.CreateFont("ZB_DefibText", {
        font = "Tahoma",
        size = 13,
        weight = 700,
        shadow = true
    })
end

local function IsDefibSecondaryEnabled()
    if secondary_attack_enabled == nil then
        return true
    end

    if IsValid and IsValid(secondary_attack_enabled) and secondary_attack_enabled.GetBool then
        return secondary_attack_enabled:GetBool()
    end

    if type(secondary_attack_enabled) == "table" and secondary_attack_enabled.GetBool then
        return secondary_attack_enabled:GetBool()
    end

    if isbool(secondary_attack_enabled) then
        return secondary_attack_enabled
    end

    return true
end

function SWEP:SetupDataTables()
    self:NetworkVar("Int", 0, "DefibState")
    self:NetworkVar("Float", 0, "DefibStartTime")
    self:NetworkVar("String", 0, "StateText")
end

function SWEP:Initialize()
    self:SetWeaponHoldType(self.HoldType)
    self:SetHoldType(self.HoldType)
    self.Incm = 75
    self.ZCLastOwner = self:GetOwner()
    self.ZCIntentionalDrop = false

    if not IsValid(self.Owner) then
        self.WorldModel = "models/weapons/defib/w_eq_defibrillator.mdl"
    else
        self.WorldModel = "models/weapons/defib/w_eq_defibrillator_paddles.mdl"
    end

    self.Idle = 0
    self.IdleTimer = CurTime() + 1

    if SERVER then
        self:SetDefibState(STATE_NONE)
        self:SetDefibStartTime(0)
        self:SetStateText("")
    end
end

function SWEP:CancelDefib()
	if SERVER then
		self.TargetEnt = nil
		self.TargetBone = nil
		self.TargetMode = nil
		self:SetDefibState(STATE_NONE)
		self:SetDefibStartTime(0)
		self:SetStateText("")
		self:StopDefibLoop()
	end
end

function SWEP:Think()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    self.ZCLastOwner = owner

    if owner:KeyDown(IN_ATTACK) then
        if self.Incm < 85 then
            self.Incm = self.Incm + 3
            self.ViewModelFOV = self.Incm
        end
    else
        if self.Incm > 75 then
            self.Incm = self.Incm - 3
            self.ViewModelFOV = self.Incm
        end
    end

    if self.Idle == 0 and self.IdleTimer <= CurTime() then
        if SERVER then
            self:SendWeaponAnim(ACT_VM_IDLE)
        end
        self.Idle = 1
    end

    if CLIENT then return end
    if self:GetDefibState() ~= STATE_PROGRESS then return end

    local ent = self.TargetEnt
    if not IsValid(ent) then
        self:FireError("ERROR - TARGET LOST")
        return
    end

    if self.TargetMode == 2 then
        local tr = hg.eyeTrace(owner)
        local curEnt = IsValid(tr.Entity) and tr.Entity or nil
        if curEnt ~= ent then
            self:FireError("ERROR - TARGET LOST")
            return
        end
    end

    local ok, err = self:CanDefib(ent)
    if not ok then
        self:FireError(err or "ERROR")
        return
    end

    if CurTime() >= self:GetDefibStartTime() + self.usetime then
	    local success = self:Heal(ent, self.TargetMode, self.TargetBone)

	    if success then
		    self.TargetEnt = nil
		    self.TargetBone = nil
		    self.TargetMode = nil
		    self:FireSuccess(ent)
		    return
	    else
		    self:FireError("FAILURE - RESUSCITATION FAILED")
		    return
        end
    end
end

function SWEP:GetUseTarget()
    local owner = self:GetOwner()
    if not IsValid(owner) then return nil, nil end

    local tr = hg.eyeTrace(owner)
    if not tr or not IsValid(tr.Entity) then return nil, nil end

    local ent = tr.Entity
    local hitpos = tr.HitPos or ent:GetPos()
    if owner:GetShootPos():DistToSqr(hitpos) > (90 * 90) then
        return nil, nil
    end

    if ent == owner or ent == hg.GetCurrentCharacter(owner) then
        return nil, nil
    end

    if ent.organism or ent:IsPlayer() or ent:IsRagdoll() then
        return ent, tr.HitBone
    end

    return nil, nil
end

function SWEP:CanDefib(ent)
    if not IsValid(ent) then
        return false, "FAILURE - INVALID TARGET"
    end

    local org = ent.organism
    if not org then
        return false, "FAILURE - NO VITALS"
    end

    if not org.otrub then
        return false, "FAILURE - SUBJECT CONSCIOUS"
    end
    if org.critical then
        return false, "FAILURE - SUBJECT CRITICAL"
    end

    if org.pulse and org.pulse > 180 then
        return false, "FAILURE - UNSTABLE RHYTHM"
    end

    return true
end

function SWEP:StopDefibLoop()
	local owner = self:GetOwner()
	if IsValid(owner) then
		owner:StopSound("ambient/energy/electric_loop.wav")
	end
end

function SWEP:GetInfo()
    local info = self.modeValues

    if istable(info) then
        return info
    end

    local fallback = self.modeValuesdef

    if istable(fallback) then
        local out = {}
        for i, val in ipairs(fallback) do
            out[i] = istable(val) and val[1] or val
        end
        return out
    end

    return {}
end

function SWEP:SetInfo(info)
    info = istable(info) and info or {}
    self:SetNetVar("modeValues", info)
    self.modeValues = info
end

function SWEP:BeginDefib(ent, bone, fromSecondary)
    local ok, err = self:CanDefib(ent)
    if not ok then
        self:FireError(err)
        return
    end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local displayName = (ent.GetPlayerName and ent:GetPlayerName() ~= "" and ent:GetPlayerName()) or
        (ent:IsPlayer() and ent:Name()) or
        "SUBJECT"

    self.TargetEnt = ent
    self.TargetBone = bone
    self.TargetMode = fromSecondary and 2 or 1

    self:SetStateText("DEFIBRILLATING - " .. string.upper(displayName))
    self:SetDefibState(STATE_PROGRESS)
    self:SetDefibStartTime(CurTime())

    local vm = owner:GetViewModel()
    if IsValid(vm) then
        local seq = vm:LookupSequence("charge")
        if not seq or seq < 0 then seq = vm:LookupSequence("deploy") end
        if not seq or seq < 0 then seq = ACT_VM_PRIMARYATTACK end
        vm:SendViewModelMatchingSequence(seq)
    end

    owner:EmitSound("ambient/energy/electric_loop.wav", 55, 100, 0.6)
    owner:EmitSound("defibl/warmup.wav", 70, 100)
    self:SetNextPrimaryFire(CurTime() + self.usetime + 0.15)
    self:SetNextSecondaryFire(CurTime() + self.usetime + 0.15)
    self.Idle = 0
    self.IdleTimer = CurTime() + self.usetime
end

function SWEP:FireError(err)
    self:StopDefibLoop()
    self:SetStateText(err or "")
    self:SetDefibState(STATE_ERROR)
    self:SetDefibStartTime(0)

    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:EmitSound("buttons/button10.wav", 55, 95, 0.7)
    end

    timer.Simple(1, function()
        if IsValid(self) then
            self:SetDefibState(STATE_NONE)
            self:SetStateText("")
        end
    end)

    self:SetNextPrimaryFire(CurTime() + 1.2)
    self:SetNextSecondaryFire(CurTime() + 1.2)
end

function SWEP:FireSuccess(ent)
    self:StopDefibLoop()

    self.TargetEnt = nil
    self.TargetBone = nil
    self.TargetMode = nil

    self:SetDefibState(STATE_NONE)
    self:SetStateText("SUCCESS - RESUSCITATION COMPLETE")
    self:SetDefibStartTime(0)

    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:EmitSound("defibl/defibrillator_use.wav", 75, 100)
        owner:EmitSound("ambient/energy/newspark04.wav", 55, 110, 0.6)
        owner:EmitSound("ambient/energy/zap1.wav", 60, 100, 0.6)
    end

    local oldpos = ent:WorldSpaceCenter()
    local spark = ents.Create("env_spark")
    if IsValid(spark) then
        spark:SetPos(oldpos)
        spark:SetKeyValue("spawnflags", "192")
        spark:SetKeyValue("traillength", "1")
        spark:SetKeyValue("magnitude", "2")
        spark:Spawn()
        spark:Fire("SparkOnce", "", 0)
        spark:Fire("Kill", "", 0.1)
    end

    self:SetClip1(0)

    timer.Simple(0.9, function()
        if IsValid(self) then
            self:SetStateText("")
        end
    end)

    timer.Simple(self.DefibCooldown, function()
        if IsValid(self) then
            self:SetClip1(1)
            if IsValid(self:GetOwner()) then
                self:GetOwner():EmitSound("defibl/charged.wav", 70, 100)
            end
        end
    end)

    self:SetNextPrimaryFire(CurTime() + self.DefibCooldown)
    self:SetNextSecondaryFire(CurTime() + self.DefibCooldown)
end

function SWEP:Heal(ent, mode, bone)
    if CLIENT then return false end
    if not IsValid(ent) then return false end

    local targetPly = nil
    local targetChar = nil

    if ent:IsPlayer() then
        targetPly = ent
        targetChar = hg.GetCurrentCharacter(ent)
    else
        targetPly = hg.RagdollOwner(ent)
        targetChar = ent
    end

    if not IsValid(targetPly) or not targetPly:IsPlayer() then
        return false
    end

    if not IsValid(targetChar) then
        targetChar = hg.GetCurrentCharacter(targetPly)
    end

    local org = IsValid(targetChar) and targetChar.organism or targetPly.organism
    if not org then return false end

    org.adrenalineAdd = (org.adrenalineAdd or 0) + 8
    org.heartstop = nil
    org.heartstopped = nil
    org.pulse = math.max(org.pulse or 0, 45)
    org.heartbeat = math.max(org.heartbeat or 0, 45)
    org.blood = math.max(org.blood or 0, 2600)
    org.oxygen = math.max(org.oxygen or 0, 0.55)
    org.otrub = false
    org.incapacitated = false
    org.stunned = math.max((org.stunned or 0) - 5, 0)
    org.pain = math.max((org.pain or 0) - 10, 0)
    org.avgpain = math.max((org.avgpain or 0) - 10, 0)

    targetPly:EmitSound("ambient/energy/zap1.wav", 55, 100, 0.7)

    if targetPly == hg.GetCurrentCharacter(targetPly) and targetPly.SetDSP then
        targetPly:SetDSP(0)
    end

    targetPly.fakecd = nil
    targetPly.bGetUp = true

    if targetPly.Getup then
        targetPly:Getup()
    end

    return true
end

function SWEP:PrimaryAttack()
    if CLIENT then return end
    if (self:Clip1() or 0) <= 0 then
        self:EmitSound("HL2Player.UseDeny")
        self:SetNextPrimaryFire(CurTime() + 0.2)
        return
    end
    if self:GetDefibState() ~= STATE_NONE then return end

    local ent, bone = self:GetUseTarget()
    if not IsValid(ent) then
        self:FireError("FAILURE - INVALID TARGET")
        return
    end

    self:BeginDefib(ent, bone, true)
    self:GetOwner():SetAnimation(PLAYER_ATTACK1)
end

function SWEP:SecondaryAttack()
    if CLIENT then return end
    if (self:Clip1() or 0) <= 0 then
        self:EmitSound("HL2Player.UseDeny")
        self:SetNextSecondaryFire(CurTime() + 0.2)
        return
    end
    if self:GetDefibState() ~= STATE_NONE then return end

    local ent, bone = self:GetUseTarget()
    if not IsValid(ent) then
        self:FireError("FAILURE - INVALID TARGET")
        return
    end

    self:BeginDefib(ent, bone, true)
    self:GetOwner():SetAnimation(PLAYER_ATTACK1)
end

function SWEP:Equip()
    self.ZCIntentionalDrop = false
    self.ZCLastOwner = self:GetOwner()
    self:ApplyHeldState()
    self.Incm = 75
    self:SetClip1(1)
end

function SWEP:ApplyHeldState()
    self.ViewModelFOV = 75
    self.WorldModel = "models/weapons/defib/w_eq_defibrillator_paddles.mdl"
    self:SetModel("models/weapons/defib/w_eq_defibrillator_paddles.mdl")
    self.ShowWorldModel = false
    self:SetNoDraw(false)
    self:SetSolid(SOLID_NONE)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
end

function SWEP:Deploy()
    local owner = self:GetOwner()
    self.ZCIntentionalDrop = false
    self.ZCLastOwner = owner
    if IsValid(owner) then
        local vm = owner:GetViewModel()
        if IsValid(vm) then
            local seq = vm:LookupSequence("deploy")
            if seq and seq >= 0 then
                vm:SendViewModelMatchingSequence(seq)
            end
        end
    end

    self:ApplyHeldState()
    self.Incm = 75
    self:EmitSound("defibl/deploy.wav", 60)
    self:SendWeaponAnim(ACT_VM_DEPLOY)

    self.Idle = 0
    if IsValid(owner) and IsValid(owner:GetViewModel()) then
        self.IdleTimer = CurTime() + owner:GetViewModel():SequenceDuration()
    else
        self.IdleTimer = CurTime() + 1
    end

    if SERVER then
        self:SetClip1(math.max((self:Clip1() or 0), 1))
        self:SetDefibState(STATE_NONE)
        self:SetDefibStartTime(0)
        self:SetStateText("")
    end

    return true
end

function SWEP:ApplyDroppedState()
    if IsValid(self:GetOwner()) then return end

    self.WorldModel = "models/weapons/defib/w_eq_defibrillator.mdl"
    self:SetModel(self.WorldModel)
    self.ShowWorldModel = true
    self:SetNoDraw(false)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:PhysicsInit(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
    end
end

function SWEP:Holster()
    self:StopDefibLoop()
    self.Idle = 0
    self.IdleTimer = CurTime()
    self:CancelDefib()
    return true
end

function SWEP:OnDrop()
    self:Holster()
    if CLIENT then return end

    local owner = IsValid(self:GetOwner()) and self:GetOwner() or self.ZCLastOwner
    self.ZCLastOwner = IsValid(owner) and owner or self.ZCLastOwner
    self.ZCIntentionalDrop = IsValid(owner) and owner:Alive() and (not TEAM_SPECTATOR or owner:Team() ~= TEAM_SPECTATOR) or false
    timer.Simple(0, function()
        if IsValid(self) then
            if self.ZCIntentionalDrop and not IsValid(self:GetOwner()) then
                self:ApplyDroppedState()
            end
        end
    end)
end

function SWEP:OwnerChanged()
    local owner = self:GetOwner()
    if IsValid(owner) then
        self.ZCLastOwner = owner
        self.ZCIntentionalDrop = false
        timer.Simple(0, function()
            if IsValid(self) then
                self:ApplyHeldState()
            end
        end)
        return
    end

    if CLIENT then
        timer.Simple(0, function()
            if IsValid(self) and not IsValid(self:GetOwner()) then
                self:ApplyDroppedState()
            end
        end)
        return
    end

    timer.Simple(0.05, function()
        if IsValid(self) then
            if IsValid(self:GetOwner()) then return end

            local previousOwner = self.ZCLastOwner
            local shouldBecomeDropped = self.ZCIntentionalDrop
                and IsValid(previousOwner)
                and previousOwner:Alive()
                and (not TEAM_SPECTATOR or previousOwner:Team() ~= TEAM_SPECTATOR)

            if shouldBecomeDropped then
                self:ApplyDroppedState()
            else
                self:Remove()
            end
        end
    end)
end

function SWEP:OnRemove()
    self:Holster()
end

if CLIENT then
    function SWEP:DrawHUD()
        local owner = self:GetOwner()
        if not IsValid(owner) or owner ~= LocalPlayer() then return end

        local state = self:GetDefibState()
        if state == STATE_NONE then return end

        local progress = 1
        local outlineCol, progressCol, progressText = color_white, color_white, self:GetStateText() or ""

        if state == STATE_PROGRESS then
            local startTime, endTime = self:GetDefibStartTime(), self:GetDefibStartTime() + self.usetime
            progress = math.TimeFraction(startTime, endTime, CurTime())
            if progress <= 0 then return end

            outlineCol = color_green
            progressCol = Color(20, 220, 80, (math.abs(math.sin(RealTime() * 3)) * 100) + 50)
            progressText = self:GetStateText() ~= "" and self:GetStateText() or "DEFIBRILLATING"
        elseif state == STATE_ERROR then
            outlineCol = color_red
            progressCol = Color(255, 20, 20, math.abs(math.sin(RealTime() * 15)) * 255)
            progressText = self:GetStateText() or "ERROR"
        end

        progress = math.Clamp(progress, 0, 1)

        local scrW, scrH = ScrW(), ScrH()
        local barW, barH = 240, 16
        local x = scrW * 0.5 - barW * 0.5
        local y = scrH * 0.55

        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(x - 4, y - 26, barW + 8, 44)

        surface.SetDrawColor(outlineCol)
        surface.DrawOutlinedRect(x - 1, y - 1, barW + 2, barH + 2, 1)

        surface.SetDrawColor(progressCol)
        surface.DrawRect(x, y, barW * progress, barH)

        draw.SimpleTextOutlined(progressText, "ZB_DefibText", scrW * 0.5, y - 12, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 220))
    end
end
