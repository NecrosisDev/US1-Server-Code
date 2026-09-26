-- WFA TPIK fix v1.0.0. Based on the user's exported WFA DoTPIK.
-- Only hg.DoTPIK is replaced; the existing WFA solver is passed in unchanged.
return function(hg, solve, record)
local math_Clamp = math.Clamp
local LocalToWorld = LocalToWorld
local vecUpX, vecUpZ, vecUpY = Vector(1, 0, 0), Vector(0, 0, 1), Vector(0, 1, 0)

local function Finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function GoodVector(value)
    return isvector(value) and Finite(value.x) and Finite(value.y) and Finite(value.z)
end

local function GoodChain(chain)
    if type(chain) ~= "table" or #chain ~= 3 then return false end
    for i = 1, 3 do
        local joint = chain[i]
        if type(joint) ~= "table" or not GoodVector(joint.Pos)
            or not Finite(joint.Len) or joint.Len < 0 then return false end
    end
    return true
end

local function Reset(ply)
    ply.segmentsr, ply.segmentsl = nil, nil
    ply.last_rh, ply.last_lh = nil, nil
    ply.nextrebuild, ply.BonesLength = nil, nil
    ply.lerpedsegmenthit, ply.lerpedsegmenthit2 = nil, nil
    ply.oldhitnormal, ply.oldhitnormal2 = nil, nil
end

local function Skip(ply, weapon, reason)
    Reset(ply)
    ply.rhold, ply.lhold = nil, nil
    if IsValid(weapon) then weapon.rhandik, weapon.lhandik = false, false end
    record(reason)
end

local function Seed(upper, forearm, hand, length)
    return {
        {Pos = upper:GetTranslation(), Len = length},
        {Pos = forearm:GetTranslation(), Len = length},
        {Pos = hand:GetTranslation(), Len = length},
    }
end

local function DoTPIK(ply, ent)
    if not IsValid(ply) or not ply:IsPlayer() or not IsValid(ent) then return end
    local self = ply:GetActiveWeapon()
    if not IsValid(self) then
        Skip(ply, self, "missing_weapon")
        return
    end
    local model = ent:GetModel()
    if ply._zcWFAEntity ~= ent or ply._zcWFAModel ~= model then
        Reset(ply)
        ply._zcWFAEntity = ent
        ply._zcWFAModel = model
    end
    local ply_spine_index = ent:LookupBone("ValveBiped.Bip01_Head1")
    if not ply_spine_index then Skip(ply, self, "missing_bone") return end
    local ply_spine_matrix = ent:GetBoneMatrix(ply_spine_index)

    local ply_pelvis_index = ent:LookupBone("ValveBiped.Bip01_Pelvis")
    if not ply_pelvis_index then Skip(ply, self, "missing_bone") return end
    local ply_pelvis_matrix = ent:GetBoneMatrix(ply_pelvis_index)

    local ply_head_index = ent:LookupBone("ValveBiped.Bip01_Head1")
    if not ply_head_index then Skip(ply, self, "missing_bone") return end
    local ply_head_matrix = ent:GetBoneMatrix(ply_head_index)

    local ply_l_clavicle_index = ent:LookupBone("ValveBiped.Bip01_L_Clavicle")
    local ply_r_clavicle_index = ent:LookupBone("ValveBiped.Bip01_R_Clavicle")
    local ply_l_upperarm_index = ent:LookupBone("ValveBiped.Bip01_L_UpperArm")
    local ply_r_upperarm_index = ent:LookupBone("ValveBiped.Bip01_R_UpperArm")
    local ply_l_forearm_index = ent:LookupBone("ValveBiped.Bip01_L_Forearm")
    local ply_r_forearm_index = ent:LookupBone("ValveBiped.Bip01_R_Forearm")
    local ply_l_hand_index = ent:LookupBone("ValveBiped.Bip01_L_Hand")
    local ply_r_hand_index = ent:LookupBone("ValveBiped.Bip01_R_Hand")
    local ply_l_ulna_index = ent:LookupBone("ValveBiped.Bip01_L_Ulna")
    local ply_r_ulna_index = ent:LookupBone("ValveBiped.Bip01_R_Ulna")
    local ply_l_wrist_index = ent:LookupBone("ValveBiped.Bip01_L_Wrist")
    local ply_r_wrist_index = ent:LookupBone("ValveBiped.Bip01_R_Wrist")

    if not ply_l_upperarm_index then Skip(ply, self, "missing_bone") return end
    if not ply_r_upperarm_index then Skip(ply, self, "missing_bone") return end
    if not ply_l_forearm_index then Skip(ply, self, "missing_bone") return end
    if not ply_r_forearm_index then Skip(ply, self, "missing_bone") return end
    if not ply_l_hand_index then Skip(ply, self, "missing_bone") return end
    if not ply_r_hand_index then Skip(ply, self, "missing_bone") return end

    local _, angarrws = LocalToWorld(vector_origin, ply:InVehicle() and LerpAngle(0.5, ply:EyeAngles(), angle_zero) or ply:EyeAngles(), vector_origin, (IsValid(ply:GetVehicle()) and hg.IsLocal(ply) and ply:GetVehicle():GetAngles() or angle_zero))
    local eyepos, eyeang = ply:EyePos(), angarrws
    if not ply_spine_matrix or not ply_head_matrix then
        Skip(ply, self, "missing_matrix")
        return
    end
    local headpos = ply_head_matrix:GetTranslation()

    local ply_r_upperarm_matrix = ent:GetBoneMatrix(ply_r_upperarm_index)
    local ply_r_forearm_matrix = ent:GetBoneMatrix(ply_r_forearm_index)
    local ply_r_hand_matrix = ent:GetBoneMatrix(ply_r_hand_index)
    local ply_r_hand_matrix_old = ply.rhold
    local ply_r_clavicle_matrix = ply_r_clavicle_index and ent:GetBoneMatrix(ply_r_clavicle_index)
    local ply_l_upperarm_matrix = ent:GetBoneMatrix(ply_l_upperarm_index)
    local ply_l_forearm_matrix = ent:GetBoneMatrix(ply_l_forearm_index)
    local ply_l_hand_matrix = ent:GetBoneMatrix(ply_l_hand_index)
    local ply_l_hand_matrix_old = ply.lhold
    local ply_l_clavicle_matrix = ply_l_clavicle_index and ent:GetBoneMatrix(ply_l_clavicle_index)
    ply.lhold = nil 
    ply.rhold = nil
    if not ply_r_upperarm_matrix or not ply_r_forearm_matrix or not ply_r_hand_matrix
        or not ply_l_upperarm_matrix or not ply_l_forearm_matrix or not ply_l_hand_matrix then
        Skip(ply, self, "missing_matrix")
        return
    end
    for _, mat in ipairs({ply_spine_matrix, ply_r_upperarm_matrix, ply_r_forearm_matrix,
        ply_r_hand_matrix, ply_l_upperarm_matrix, ply_l_forearm_matrix, ply_l_hand_matrix}) do
        if not GoodVector(mat:GetTranslation()) then
            Skip(ply, self, "invalid_position")
            return
        end
    end



    local lhik2 = ((IsValid(self) and self.lhandik) or ply:InVehicle()) and hg.CanUseLeftHand(ply)
    local rhik2 = ((IsValid(self) and self.rhandik) or ply:InVehicle()) and hg.CanUseRightHand(ply)
    
    local shouldrebuild = false
    if (ply.nextrebuild or 0) < CurTime() then
        ply.nextrebuild = CurTime() + 0.0

        shouldrebuild = true
    end

    if rhik2 then
        ply.last_rh = ply_r_hand_matrix
    end

    if lhik2 then
        ply.last_lh = ply_l_hand_matrix
    end

    











    ply.lerp_lh = math.Approach(ply.lerp_lh or 0, lhik2 and 1 or 0, FrameTime() * 2.0 * game.GetTimeScale())
    ply.lerp_rh = math.Approach(ply.lerp_rh or 0, rhik2 and 1 or 0, FrameTime() * 2.0 * game.GetTimeScale())

    local lerp_lh = math.ease.InOutSine(ply.lerp_lh)
    local lerp_rh = math.ease.InOutSine(ply.lerp_rh)

    

    local limblength = ply:BoneLength(ply_l_forearm_index)

    if not Finite(limblength) or limblength <= 0 then limblength = 12 end

    
    
    
    

    -- Seed all three joints from current bones; the original seeded only two.
    if not GoodChain(ply.segmentsr) then
        ply.segmentsr = Seed(ply_r_upperarm_matrix, ply_r_forearm_matrix, ply_r_hand_matrix, limblength)
        shouldrebuild = true
        record("cache_rebuilt")
    end
    if not GoodChain(ply.segmentsl) then
        ply.segmentsl = Seed(ply_l_upperarm_matrix, ply_l_forearm_matrix, ply_l_hand_matrix, limblength)
        shouldrebuild = true
        record("cache_rebuilt")
    end

    if not ply.BonesLength then
        ply.BonesLength = {}

        for i = 0, ent:GetBoneCount() - 1 do
            ply.BonesLength[i] = ply:BoneLength(i)
        end
    end

    local spinepos = ply_spine_matrix:GetTranslation()
    local spineang = ply_spine_matrix:GetAngles()

    local up = spineang:Up()
    local spinetan = -math.deg(math.atan2(up.x, up.y)) + 180
    
    if lerp_rh ~= 0 then
        local segments = ply.segmentsr

        if shouldrebuild then
            local old = segments[2] and ((segments[2].Pos - segments[1].Pos):GetNormalized() * 2) or vector_origin

            local eyeang = -(-eyeang)
            eyeang.p = math.NormalizeAngle(eyeang.p) * 0.5
            segments[1].Pos = ply_r_upperarm_matrix:GetTranslation()
            segments[1].Len = limblength
            segments[2].Pos = spinepos + eyeang:Right() * 25 - eyeang:Up() * 20 - eyeang:Forward() * 20
            segments[2].Len = limblength

            local tr = util.TraceLine({
                start = segments[1].Pos,
                endpos = segments[2].Pos,
                filter = {ent, ply},
                mask = MASK_SOLID_BRUSHONLY,
            })
            
            ply.lerpedsegmenthit = LerpFT(0.1, ply.lerpedsegmenthit or 0, (1 - tr.Fraction))
            ply.oldhitnormal = LerpAngleFT(0.1, ply.oldhitnormal or tr.HitNormal:Angle(), tr.Hit and tr.HitNormal:Angle() or ply.oldhitnormal or Angle())
            
            if ply.lerpedsegmenthit > 0.01 and ply.oldhitnormal then
                local hitnormal = ply.oldhitnormal:Forward()
                local dist = 20
                local new = hitnormal * dist * ply.lerpedsegmenthit * (math.sin(math.acos(math.Clamp(hitnormal:Dot(tr.Normal), -1, 1)))) + segments[2].Pos

                segments[2].Pos = new
            end

            local newpos = hook.Run("IKPoleRightArm", ply, ent, segments[2].Pos, segments)

            if GoodVector(newpos) then
                segments[2].Pos = newpos
            elseif newpos ~= nil then
                record("bad_pole")
            end
            if not GoodChain(segments) then
                Skip(ply, self, "invalid_position")
                return
            end

            ply.leftClicking = LerpFT(0.05, ply.leftClicking or 0, (ishgweapon(self) and hg.KeyDown(ply, IN_ATTACK)) and 1 or 0.05)

            local hand = ply_r_hand_matrix:GetTranslation()

            if false and not ishgweapon(self) and ply.organism and ply.organism.rarm and ply.organism.rarm > 0.99 then
                segments[3] = segments[3] or {Pos = hand, Len = limblength}
                segments[3].Pos = LerpVector(ply.leftClicking, segments[3].Pos + (-vector_up * 0.8 + eyeang:Forward() * 0.4 + ent:GetVelocity() / 400) * 0.5, hand)
            else
                segments[3] = {Pos = LerpVector(1 - lerp_rh, ply.last_rh and ply.last_rh:GetTranslation() or segments[3].Pos, ply_r_hand_matrix_old and ply_r_hand_matrix_old:GetTranslation() or hand), Len = 12}
            end

            if not GoodChain(segments) then
                Skip(ply, self, "invalid_position")
                return
            end
            if IsValid(lply) and lply:IsSuperAdmin() then
                for i = 2, #segments do
                    debugoverlay.Line(segments[i - 1].Pos, segments[i].Pos, 0, color_white, true)
                end
            end

            segments = solve(segments, 4)

            





            ply.segmentsr = segments
        end

        -- Validate before any matrix is modified. SetTranslation copies the
        -- vector; double-negation is unnecessary and is bypassed here.
        if not GoodChain(segments) then
            Skip(ply, self, "invalid_position")
            return
        end
        local new = segments[3].Pos

        ply_r_upperarm_matrix:SetTranslation(segments[1].Pos)
        ply_r_forearm_matrix:SetTranslation(segments[2].Pos)
        ply_r_hand_matrix:SetTranslation(new)


        local diff = (segments[2].Pos - segments[1].Pos):GetNormalized()
        local angrr = diff:Angle()
        local angle2 = math.deg(math.atan2(-math.sqrt(diff.x * diff.x + diff.y * diff.y), diff.z)) - 90
        local angle3 = -math.deg(math.atan2(diff.x, diff.y)) - 90
        angle3 = math.NormalizeAngle(angle3)
        local torsoright = eyeang.y + 120
    
        local q = Quaternion()
        q = q * Quaternion():SetAngleAxis(angrr.y, vecUpZ)
        q = q * Quaternion():SetAngleAxis(angrr.p, vecUpY)
        q = q * Quaternion():SetAngleAxis(-120 + angrr.y - eyeang.y + eyeang.r, vecUpX)

        local ang = q:Angle()

        ply_r_upperarm_matrix:SetAngles(ang)

        local diff = (segments[3].Pos - segments[2].Pos):GetNormalized()
        local angrr = diff:Angle()
        local angle2 = math.deg(math.atan2(-math.sqrt(diff.x * diff.x + diff.y * diff.y), diff.z)) - 90
        local angle3 = -math.deg(math.atan2(diff.x, diff.y)) - 90
        angle3 = math.NormalizeAngle(angle3)
        local torsoright = eyeang.y + 120
    
        local q = Quaternion()
        q = q * Quaternion():SetAngleAxis(angrr.y, vecUpZ)
        q = q * Quaternion():SetAngleAxis(angrr.p, vecUpY)
        q = q * Quaternion():SetAngleAxis(-120 - angrr.r + eyeang.r - math.NormalizeAngle((eyeang.y - angrr.y)) * (math.NormalizeAngle(angrr.p)) / 90, vecUpX)

        local ang = q:Angle()
        ply_r_forearm_matrix:SetAngles(ang)

        if false and ply.organism and ply.organism.rarm and ply.organism.rarm > 0.99 then
            local ang = ang
            ang:RotateAroundAxis(ang:Forward(), -95)
            ply_r_hand_matrix:SetAngles(LerpAngle(math_Clamp(ply.leftClicking * 2, 0, 1), ang, ply_r_hand_matrix:GetAngles()))
        end

        hg.bone_apply_matrix(ent, ply_r_upperarm_index, ply_r_upperarm_matrix, ply_r_forearm_index)
        hg.bone_apply_matrix(ent, ply_r_forearm_index, ply_r_forearm_matrix, ply_r_hand_index)
        hg.bone_apply_matrix(ent, ply_r_hand_index, ply_r_hand_matrix)

        if IsValid(ply.OldRagdoll) then
            hg.bone_apply_matrix(ply, ply_r_upperarm_index, ply_r_upperarm_matrix, ply_r_forearm_index)
            hg.bone_apply_matrix(ply, ply_r_forearm_index, ply_r_forearm_matrix, ply_r_hand_index)
            hg.bone_apply_matrix(ply, ply_r_hand_index, ply_r_hand_matrix)
        end

        local angrotate = math.NormalizeAngle(-eyeang.r + ply_r_hand_matrix:GetAngles().r + math.NormalizeAngle((eyeang.y - ply_r_hand_matrix:GetAngles().y)) * (math.NormalizeAngle(ply_r_hand_matrix:GetAngles().p)) / 90 + -90)
        
        local wrst = ent:LookupBone("ValveBiped.Bip01_R_Ulna")
        local wmat = wrst and ent:GetBoneMatrix(wrst)
        if wrst and wmat then
            ang:RotateAroundAxis(ang:Forward(), angrotate * 0.5 + -30)
            wmat:SetAngles(ang)
            ent:SetBoneMatrix(wrst, wmat)
        end

        local wrst = ent:LookupBone("ValveBiped.Bip01_R_Wrist")
        local wmat = wrst and ent:GetBoneMatrix(wrst)
        if wrst and wmat then
            ang:RotateAroundAxis(ang:Forward(), angrotate * 0.5 - 30)
            wmat:SetAngles(ang)
            ent:SetBoneMatrix(wrst, wmat)
        end
    end
    
    if lerp_lh ~= 0 then
        local segments = ply.segmentsl
        
        if shouldrebuild then
            local old = segments[2] and ((segments[2].Pos - segments[1].Pos):GetNormalized() * 2) or vector_origin
            local eyeang = -(-eyeang)
            eyeang.p = math.NormalizeAngle(eyeang.p) * 0.5
            segments[1].Pos = ply_l_upperarm_matrix:GetTranslation()
            segments[1].Len = limblength
            segments[2].Pos = spinepos + eyeang:Right() * -25 - eyeang:Up() * 20
            segments[2].Len = limblength
            
            local tr = util.TraceLine({
                start = segments[1].Pos,
                endpos = segments[2].Pos,
                filter = {ent, ply},
                mask = MASK_SOLID_BRUSHONLY,
            })

            ply.lerpedsegmenthit2 = LerpFT(0.1, ply.lerpedsegmenthit2 or 0, (1 - tr.Fraction))
            
            ply.oldhitnormal2 = LerpAngleFT(0.1, ply.oldhitnormal2 or tr.HitNormal:Angle(), tr.Hit and tr.HitNormal:Angle() or ply.oldhitnormal2 or Angle())
            if ply.lerpedsegmenthit2 > 0.01 and ply.oldhitnormal2 then
                local hitnormal = ply.oldhitnormal2:Forward()
                local dist = 20
                local new = hitnormal * dist * ply.lerpedsegmenthit2 * (math.sin(math.acos(math.Clamp(hitnormal:Dot(tr.Normal), -1, 1)))) + segments[2].Pos

                segments[2].Pos = new
            end

            local newpos = hook.Run("IKPoleLeftArm", ply, ent, segments[2].Pos, segments)

            if GoodVector(newpos) then
                segments[2].Pos = newpos
            elseif newpos ~= nil then
                record("bad_pole")
            end
            if not GoodChain(segments) then
                Skip(ply, self, "invalid_position")
                return
            end

            local hand = ply_l_hand_matrix:GetTranslation()
            local add = (hand - segments[1].Pos):GetNormalized() * 5 + eyeang:Right() * -5 + eyeang:Forward() * ((ply.lerp_hand or 0) - 0.5) * 10

            if ply.organism and ply.organism.larm and ply.organism.larm > 0.99 and ishgweapon(self) and not self.reload and ishgweapon(self) then
                segments[3] = segments[3] or {Pos = hand, Len = limblength}
                segments[3].Pos = LerpVector(not (ishgweapon(self) and self:IsPistolHoldType()) and 0.05 or 0.01, segments[3].Pos + (-vector_up * 0.6 + eyeang:Forward() * 0.4 + ((ishgweapon(self) and not self:IsPistolHoldType()) and eyeang:Right() * 0.7 or vector_origin) + ent:GetVelocity() / 400) * 0.5, hand)
            else
                segments[3] = {Pos = LerpVector(1 - lerp_lh, ply.last_lh and ply.last_lh:GetTranslation() or segments[3].Pos, ply_l_hand_matrix_old and ply_l_hand_matrix_old:GetTranslation() or hand), Len = 12}
            end

            if not GoodChain(segments) then
                Skip(ply, self, "invalid_position")
                return
            end
            if IsValid(lply) and lply:IsSuperAdmin() then
                for i = 2, #segments do
                    debugoverlay.Line(segments[i - 1].Pos, segments[i].Pos, 0, color_white, true)
                end
            end

            segments = solve(segments, 4)

            




            
            ply.segmentsl = segments
        end

        -- Validate before any matrix is modified. SetTranslation copies the
        -- vector; double-negation is unnecessary and is bypassed here.
        if not GoodChain(segments) then
            Skip(ply, self, "invalid_position")
            return
        end
        local new = segments[3].Pos

        ply_l_upperarm_matrix:SetTranslation(segments[1].Pos)
        ply_l_forearm_matrix:SetTranslation(segments[2].Pos)
        ply_l_hand_matrix:SetTranslation(new)

        local diff = (segments[2].Pos - segments[1].Pos):GetNormalized()
        local angrr = diff:Angle()
        local angle2 = math.deg(math.atan2(-math.sqrt(diff.x * diff.x + diff.y * diff.y), diff.z)) - 90
        local angle3 = -math.deg(math.atan2(diff.x, diff.y)) - 90
        angle3 = math.NormalizeAngle(angle3)
        local torsoright = eyeang.y + 90
    
        local q = Quaternion()
        q = q * Quaternion():SetAngleAxis(angrr.y, vecUpZ)
        q = q * Quaternion():SetAngleAxis(angrr.p, vecUpY)
        q = q * Quaternion():SetAngleAxis(-30 + angrr.y - eyeang.y + eyeang.r, Vector(1, 0, 0))
        
        local ang = q:Angle()
        ply_l_upperarm_matrix:SetAngles(ang)

        local diff = (segments[3].Pos - segments[2].Pos):GetNormalized()
        local angrr = diff:Angle()
        local angle2 = math.deg(math.atan2(-math.sqrt(diff.x * diff.x + diff.y * diff.y), diff.z)) - 90
        local angle3 = -math.deg(math.atan2(diff.x, diff.y)) - 90
        angle3 = math.NormalizeAngle(angle3)
        local torsoright = eyeang.y + 180
    
        local q = Quaternion()
        q = q * Quaternion():SetAngleAxis(angrr.y, vecUpZ)
        q = q * Quaternion():SetAngleAxis(angrr.p, vecUpY)
        q = q * Quaternion():SetAngleAxis(-60 - angrr.r + eyeang.r - math.NormalizeAngle((eyeang.y - angrr.y)) * (math.NormalizeAngle(angrr.p)) / 90, Vector(1, 0, 0))

        local ang = q:Angle()

        ply_l_forearm_matrix:SetAngles(ang)

        if ply.organism and ply.organism.larm and ply.organism.larm > 0.99 and ishgweapon(self) and not self.reload and ishgweapon(self) then
            local ang = ang
            ang:RotateAroundAxis(ang:Forward(), 95)
            ply_l_hand_matrix:SetAngles(LerpAngle(0.5, ply_l_hand_matrix:GetAngles(), ang))
        end

        hg.bone_apply_matrix(ent, ply_l_upperarm_index, ply_l_upperarm_matrix, ply_l_forearm_index)
        hg.bone_apply_matrix(ent, ply_l_forearm_index, ply_l_forearm_matrix, ply_l_hand_index)
        hg.bone_apply_matrix(ent, ply_l_hand_index, ply_l_hand_matrix)

        if IsValid(ply.OldRagdoll) then
            hg.bone_apply_matrix(ply, ply_l_upperarm_index, ply_l_upperarm_matrix, ply_l_forearm_index)
            hg.bone_apply_matrix(ply, ply_l_forearm_index, ply_l_forearm_matrix, ply_l_hand_index)
            hg.bone_apply_matrix(ply, ply_l_hand_index, ply_l_hand_matrix)
        end

        local angrotate = math.NormalizeAngle(-eyeang.r + ply_l_hand_matrix:GetAngles().r + math.NormalizeAngle((eyeang.y - ply_l_hand_matrix:GetAngles().y)) * (math.NormalizeAngle(ply_l_hand_matrix:GetAngles().p)) / 90 - 45)

        local wrst = ent:LookupBone("ValveBiped.Bip01_L_Ulna")
        local wmat = wrst and ent:GetBoneMatrix(wrst)
        if wrst and wmat then
            ang:RotateAroundAxis(ang:Forward(), angrotate * 0.5 + 00)
            wmat:SetAngles(ang)
            ent:SetBoneMatrix(wrst, wmat)
        end

        local wrst = ent:LookupBone("ValveBiped.Bip01_L_Wrist")
        local wmat = wrst and ent:GetBoneMatrix(wrst)
        if wrst and wmat then
            ang:RotateAroundAxis(ang:Forward(), angrotate * 0.5 + 00)
            wmat:SetAngles(ang)
            ent:SetBoneMatrix(wrst, wmat)
        end
    end
    
    self.lhandik = false
    self.rhandik = false
end

return DoTPIK
end
