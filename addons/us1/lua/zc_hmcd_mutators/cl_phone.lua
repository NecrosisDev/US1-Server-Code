local W = SWEP
local Pose = include("zc_hmcd_mutators/sh_phone_pose.lua")
local up = Vector(0, 0, 1)
local function Bone(ent, name)
    local id = ent:LookupBone("ValveBiped.Bip01_" .. name)
    if not id or id < 0 then return end
    local matrix = ent:GetBoneMatrix(id)
    if not matrix or not Pose.VectorOK(matrix:GetTranslation()) then return end
    return id, Matrix(matrix)
end
local function Turn(matrix, oldDirection, newDirection)
    local a, b = oldDirection:GetNormalized(), newDirection:GetNormalized()
    local dot = math.Clamp(a:Dot(b), -1, 1)
    local axis = a:Cross(b)
    if axis:LengthSqr() < 0.000001 then
        if dot > 0 then return matrix end
        axis = a:Cross(math.abs(a.z) < 0.9 and up or Vector(0, 1, 0))
    end
    local angle = matrix:GetAngles()
    angle:RotateAroundAxis(axis:GetNormalized(), math.deg(math.acos(dot)))
    matrix:SetAngles(angle)
    return matrix
end
function W:PhonePose(ent, owner)
    if not hg or not hg.bone_apply_matrix then return end
    local head, hm = Bone(ent, "Head1")
    local upper, um = Bone(ent, "R_UpperArm")
    local lower, lm = Bone(ent, "R_Forearm")
    local hand, rm = Bone(ent, "R_Hand")
    if not head or not upper or not lower or not hand then return end
    local shoulder, elbow, wrist = um:GetTranslation(), lm:GetTranslation(), rm:GetTranslation()
    local length1, length2 = shoulder:Distance(elbow), elbow:Distance(wrist)
    local yaw = Angle(0, owner:EyeAngles().y, 0)
    local forward, right = yaw:Forward(), yaw:Right()
    local headPos = hm:GetTranslation()
    local rest = headPos + forward * 9 + right * 8 - up * 17
    local ear = headPos + right * 5.5 + forward * 1.5 - up * 4.5
    local blend = Pose.Blend(self:GetCallPhase(), CurTime() - self:GetPhaseStart())
    local joint, target = Pose.Solve(shoulder, LerpVector(blend, rest, ear), right - up, length1, length2)
    if not joint then return end
    local newUpper = Turn(Matrix(um), elbow - shoulder, joint - shoulder)
    local newLower = Turn(Matrix(lm), wrist - elbow, target - joint)
    newLower:SetTranslation(joint)
    local newHand = Matrix(rm)
    newHand:SetTranslation(target)
    newHand:SetAngles(Pose.HandAngle(blend, yaw.y))
    -- DrawWorldModel2 is called after ZCity/WFA TPIK and before the character is drawn.
    -- Only this phone's right arm is posed; no persistent bone manipulation or global replacement.
    hg.bone_apply_matrix(ent, upper, newUpper, lower)
    hg.bone_apply_matrix(ent, lower, newLower, hand)
    hg.bone_apply_matrix(ent, hand, newHand)
end
function W:DrawWorldModel2()
    local owner = self:GetOwner()
    if not IsValid(owner) or owner:GetActiveWeapon() ~= self or not owner:Alive() then return end
    if owner:InVehicle() or (owner.organism and owner.organism.otrub) then return end
    local ent = hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(owner) or owner
    if not IsValid(ent) or ent ~= owner then return end
    self:PhonePose(ent, owner)
    local hand, matrix = Bone(ent, "R_Hand")
    if not hand then return end
    if not IsValid(self.PhoneModel) then
        if self.PhoneModelRetry and self.PhoneModelRetry > CurTime() then return end
        self.PhoneModelRetry = CurTime() + 5
        if not util.IsValidModel(self.WorldModel) then return end
        self.PhoneModel = ClientsideModel(self.WorldModel, RENDERGROUP_OPAQUE)
        if not IsValid(self.PhoneModel) then return end
        self.PhoneModel:SetNoDraw(true)
        self.PhoneModel:SetSkin(1)
    end
    local position, angle = Pose.PhoneTransform(matrix:GetTranslation(), matrix:GetAngles())
    self.PhoneModel:SetPos(position); self.PhoneModel:SetAngles(angle)
    self.PhoneModel:SetupBones(); self.PhoneModel:DrawModel()
end
-- ZCity's character renderer calls DrawWorldModel2 for held items, including its first-person body.
function W:DrawWorldModel() end
function W:DrawHUD()
    local text = self:GetCallPhase() == 0 and "Primary attack: answer   |   Secondary attack: hang up" or "Call in progress   |   Secondary attack: hang up"
    draw.SimpleText(text, "DermaDefault", ScrW() / 2, ScrH() * 0.72, color_white, TEXT_ALIGN_CENTER)
end

concommand.Add("zc_mutator_phone_status", function()
    print("[zc_mutators] Informant phone v1.6.0 model=" .. tostring(util.IsValidModel(W.WorldModel))
        .. " ringtone=" .. tostring(file.Exists("sound/" .. W.RingSound, "GAME"))
        .. " sound=" .. W.RingSound
        .. " pose_api=" .. tostring(hg ~= nil and type(hg.bone_apply_matrix) == "function"))
end, nil, "Print the Informant phone asset check.")
