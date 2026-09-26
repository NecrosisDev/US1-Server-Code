return string.sub([========[x        if matrix then pos, ang = matrix:GetTranslation(), matrix:GetAngles() end
    end
    pos, ang = LocalToWorld(w.weaponPos or vector_origin, w.weaponAng or angle_zero, pos, ang)
    put(model, pos, ang)
    model:DrawModel()
end

local function drawDress(g)
    V.DrawWeaponMesh(g)
    -- Body accessories follow whichever body is ACTUALLY on screen. While a player is down, the ghost is hidden and
    -- g.zcRag is drawn in its place (poseRagdoll), so a hat parented to the ghost went with it and every corpse in
    -- the game lost its accessories. Re-parent to the visible body instead - only when it changes, since SetParent
    -- every frame would re-seat the bone attachment constantly. The ragdoll may be a different model than the ghost,
    -- so the bone is looked up again on the new host; LookupBone gives NO value on a miss, hence the -1 fallback.
    if g.zcAccess then
        local rag = g.zcRag
        local host = (IsValid(rag) and not rag:GetNoDraw()) and rag or g
        local onBody = not host:GetNoDraw()
        for _, a in ipairs(g.zcAccess) do
            if IsValid(a) then
                if a.zcHost ~= host then
                    a.zcHost = host
                    a:SetParent(host, a.zcBone and host:LookupBone(a.zcBone) or -1)
                end
                local bone = a.zcBone and host:LookupBone(a.zcBone)
                local severed = bone and host.zcGoreHidden and host.zcGoreHidden[bone]
                a:SetNoDraw(not onBody or severed == true)
            end
        end
    end
    local gun, w = g.zcGun, g.zcWeapon
    local shown = IsValid(gun) and not gun:GetNoDraw()
    local atts = g.zcAtts or NOATTS -- a ghost can reach here with accessories but no attachments at all
    for _, a in ipairs(atts) do if a.merged and IsValid(a.model) then a.model:SetNoDraw(not shown) end end
    g.zcLaserPos = nil
    if not shown then return end
    gun:SetupBones()
    local pos, ang = muzzleOf(gun, w)
    g.zcMuzzle = ang
    if g.zcScope and not g.zcScopeOn then g.zcScopePos = pos end
    local sight
    for _, a in ipairs(atts) do
        local model, data, list = a.model, a.data, a.list
        if a.place == "underbarrel" and a.merged and IsValid(model) then g.zcLaserPos, g.zcLaserAng, g.zcLaserData = model:GetPos(), model:GetAngles(), data end
        if IsValid(model) and not a.merged then
            local add = Vector(0, 0, 0)
            if isvector(a.att[2]) then add:Add(a.att[2]) end
            local mount, turn = list and list.mount, list and list.mountAngle
            if isvector(mount) then add:Add(mount) elseif istable(mount) and isvector(mount[data.mountType]) then add:Add(mount[data.mountType]) end
            if isvector(data.offset) then add:Add(data.offset) end
            add:Rotate(ang)
            add:Add(pos)
            local _, out = LocalToWorld(vector_origin, (data[3] or angle_zero) + (isangle(turn) and turn or istable(turn) and turn[data.mountType] or angle_zero), vector_origin, ang)
            if data.transformFunction and not a.plain then -- written for a live SWEP: the first failure turns it off for this fitting
                a.plain = not pcall(data.transformFunction, w, model, add, out)
            end
            put(model, add, out)
            model:DrawModel()
            if a.place == "underbarrel" then g.zcLaserPos, g.zcLaserAng, g.zcLaserData = add, out, data end
            if g.zcScopeOn == a then g.zcScopePos = add end
            if IsValid(a.glass) then put(a.glass, add, out) end
            if IsValid(a.rail) and isvector(data.mountVec) then
                local at = Vector(data.mountVec)
                at:Rotate(out)
                at:Add(add)
                local _, railAng = LocalToWorld(vector_origin, data.mountAng or angle_zero, vector_origin, out)
                put(a.rail, at, railAng)
                a.rail:DrawModel()
            end
            if isvector(data.offsetView) and (a.place == "sight" or (a.place == "underbarrel" and not sight)) and g.zcBasePos then
                sight = {at = WorldToLocal(add, angle_zero, g.zcBasePos, g.zcAimAng), view = data.offsetView} -- kept relative to the gun: eyeOf runs before the next pose
            end
        end
    end
    g.zcSight = sight
end
local function reticle(a, barrel)
    local view = render.GetViewSetup()
    local mark = (view.origin + barrel:Forward() * 2624):ToScreen()
    local size = 36 * math.Remap(view.fov, 0, 100, 1.8, 1) * math.Remap(a.model:GetPos():Distance(view.origin), 6, 14, 1.2, 0.9) * (a.data.holo_size or 1)
    render.SetStencilWriteMask(0xFF)
    render.SetStencilTestMask(0xFF)
    render.SetStencilReferenceValue(1)
    render.SetStencilCompareFunction(STENCIL_NOTEQUAL)
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.ClearStencil()
    render.SetStencilEnable(true)
    render.SetBlend(0)
    a.glass:DrawModel()
    render.SetBlend(1)
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    cam.Start2D()
    surface.SetDrawColor(255, 255, 255)
    surface.SetMaterial(a.data.holo)
    surface.DrawTexturedRect(mark.x - size / 2, mark.y - size / 2, size, size)
    cam.End2D()
end

-- The weapon an actor held at this moment. Swapped when they switch.
local function arm(g, clip, wep, actor, ragged)
    local class = clip.weaponName[wep]
    ragged = ragged == true
    local same = g.zcGunId == wep and g.zcGunClass == class and g.zcGunRag == ragged
    if same and (IsValid(g.zcGun) or V.Unarmed(clip, wep)) then return end
    if same and (g.zcGunRetry or 0) > RealTime() then return end
    g.zcGunId, g.zcGunClass, g.zcGunRag = wep, class, ragged
    g.zcGunRetry = nil
    strip(g)
    if IsValid(g.zcGun) then g.zcGun:Remove() end
    if IsValid(g.zcExchange) then g.zcExchange:Remove() end
    g.zcExchange, g.zcExchangeRetry = nil, nil
    g.zcGun, g.zcWeapon, g.zcFingers, g.zcReloadFrom, g.zcReloadSeq = nil, nil, nil, nil, nil
    g.zcPistol, g.zcRest, g.zcRestOn, g.zcRestAt, g.zcFamily, g.zcItem, g.zcAct = nil, nil, nil, nil, nil, nil, nil
    if V.Unarmed(clip, wep) then return end
    local model, w = heldModel(class, ragged)
    if not model then g.zcGunRetry = RealTime() + 0.5 return end
    local gun = V.OwnReplayEntity(ClientsideModel(model, RENDERGROUP_OPAQUE))
    if not IsValid(gun) then g.zcGunRetry = RealTime() + 0.5 return end
    gun:SetNoDraw(true) -- revealed only once pose() has positioned it
    g.zcNoIK = nil
    if w.WorldModelFake then
        if w.FakeScale then gun:SetModelScale(w.FakeScale, 0) end
        if w.FakeBodyGroups then gun:SetBodyGroups(w.FakeBodyGroups) end
        local idle = gun:LookupSequence(w.AnimList and w.AnimList.idle or "base_idle")
        if idle and idle >= 0 then gun:ResetSequence(idle) end
    end
    g.zcGun, g.zcWeapon = gun, w
    if isstring(w.WorldModelExchange) and w.WorldModelExchange ~= "" then
        gun.RenderOverride = function() end -- animation/IK still reads its bones; draw the exchange mesh below
    end
    g.zcFamily = heldFamily(clip.weaponName[wep])
    g.zcItem = g.zcFamily == "item"
    if g.zcFamily == "melee" or g.zcFamily == "tpik" then
        local idle = gun:LookupSequence("idle")
        if idle and idle >= 0 then gun:ResetSequence(idle) end
    end
    local ok, err = pcall(dress, g, actor, clip.weaponName[wep])
    if not ok and not L.dressErr then L.dressErr = true print("[Killcam] attachments: " .. tostring(err)) end
end

-- Arms are bent onto the weapon with the gamemode's own two-bone solver, the way its TPIK does it
-- (hg.Solve2PartIK + hg.bone_apply_matrix, cl_tpik.lua / cl_bones.lua). Runs inside BuildBonePositions.
local ARM = {
    [-1] = {"ValveBiped.Bip01_R_UpperArm", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Hand"},
    [1] = {"ValveBiped.Bip01_L_UpperArm", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Hand"},
}
-- `release` (0..1) lets the hand go back to where the body's own animation has it. The game switches the left hand's IK
-- off while a gun is rested on its bipod (sh_worldmodel.lua:170, setlhik = not IsResting() and ...) and eases between the
-- two; here the ease is the same one that settles the gun onto its rest point (restPoint's lerp).
local function solveArm(g, sign, targetPos, targetAng, release)
    local names = ARM[sign]
    local upper, fore, hand, head = g:LookupBone(names[1]), g:LookupBone(names[2]), g:LookupBone(names[3]), g:LookupBone("ValveBiped.Bip01_Head1")
    if not (upper and fore and hand and head) then return end
    local upperM, foreM, handM, headM = g:GetBoneMatrix(upper), g:GetBoneMatrix(fore), g:GetBoneMatrix(hand), g:GetBoneMatrix(head)
    if not (upperM and foreM and handM and headM) then return end
    if release and release > 0 then
        if release >= 1 then return end
        targetPos, targetAng = LerpVector(release, targetPos, handM:GetTranslation()), LerpAngle(release, targetAng, handM:GetAngles())
    end
    local shoulder = upperM:GetTranslation()
    local len0, len1 = shoulder:Distance(foreM:GetTranslation()), foreM:GetTranslation():Distance(handM:GetTranslation())
    handM:SetTranslation(targetPos)
    handM:SetAngles(targetAng)
    -- The elbow's swing comes from the solver's last arguments, and cl_tpik.lua:401-407 feeds it the SPINE matrix and the
    -- head's angles turned -90 about up and -90 about forward (owner, 2026-09-21: "elbows bend incorrectly" - the raw head
    -- angles were being passed for both).
    local spine = g:LookupBone("ValveBiped.Bip01_Spine4")
    local torsoM = spine and g:GetBoneMatrix(spine) or headM
    local swing = headM:GetAngles()
    swing:RotateAroundAxis(swing:Up(), -90)
    swing:RotateAroundAxis(swing:Forward(), -90)
    local elbow, wrist, upperAng, foreAng = hg.Solve2PartIK(shoulder, targetPos, len0, len1, upperM, handM, sign, torsoM, swing, targetAng)
    if not elbow then return end
    foreAng:RotateAroundAxis(foreAng:Forward(), -45)
    upperM:SetAngles(upperAng)
    foreM:SetAngles(foreAng)
    foreM:SetTranslation(elbow)
    handM:SetTranslation(wrist)
    hg.bone_apply_matrix(g, upper, upperM, fore)
    hg.bone_apply_matrix(g, fore, foreM, hand)
    hg.bone_apply_matrix(g, hand, handM)
end

do
local function carryHands(g)
    if g.zcCarry and hg and hg.Solve2PartIK and hg.bone_apply_matrix then
        local c = g.zcCarry
        local spine = g:LookupBone("ValveBiped.Bip01_Spine4")
        local m = spine and g:GetBoneMatrix(spine)
        if m then
            local pos, aim = c.pos, c.aim
            local dot = (pos - m:GetTranslation()):GetNormalized():Dot(m:GetAngles():Forward()) * -50
            local mul = math.Clamp(dot / 20, 0.1, 1.5)
            local mul2, mul3 = math.Clamp(-dot / 20, -1, 1), math.Clamp((-dot + 30) / 20, 1, 2)
            -- Native DragHands clamps each hand's reach before applying its offsets.
            for side = 2, 1, -1 do
                if V.HasFlag(c.mask, side) then
                    local bone = g:LookupBone(side == 1 and "ValveBiped.Bip01_L_Hand" or "ValveBiped.Bip01_R_Hand")
                    local hand = bone and g:GetBoneMatrix(bone)
                    if hand then
                        local old = hand:GetTranslation()
                        local at = Vector(math.Clamp(pos.x, old.x - 38, old.x + 38), math.Clamp(pos.y, old.y - 38, old.y + 38), math.Clamp(pos.z, old.z - 38, old.z + 38))
                        pos = at -- native two-hand carry clamps the right hand first, then the left
                        local off = side == 2 and Vector(0, -2, 0) or (c.mask == 3 and Vector(0, 2, 0) or vector_origin)
                        local angle = side == 2 and Angle(-30 * mul, -5, 120 * mul3) or Angle(-30 * mul, 5, -70 * mul2)
                        local target, rotation = LocalToWorld(off, angle, at, aim)
                        solveArm(g, side == 1 and 1 or -1, target, rotation)
                    end
                end
            end
        end
        return
    end
end
local function weaponHands(g)
    local gun, w = g.zcGun, g.zcWeapon
    if not g.zcHandPos or not IsValid(gun) or not w or not (hg and hg.Solve2PartIK and hg.bone_apply_matrix) then return end
    if g.zcItem then return end -- carried by the animation's own hand
    if w.WorldModelFake or g.zcFamily == "melee" or g.zcFamily == "tpik" then
        -- These models carry the hands' bones, posed for this weapon: hands and fingers are copied from them.
        gun:SetupBones()
        local rh, lh = gun:LookupBone("ValveBiped.Bip01_R_Hand"), gun:LookupBone("ValveBiped.Bip01_L_Hand")
        local rhM, lhM = rh and gun:GetBoneMatrix(rh), lh and gun:GetBoneMatrix(lh)
        if rhM then solveArm(g, -1, rhM:GetTranslation(), rhM:GetAngles()) end
        local off = math.max(g.zcRestNow and g.zcRestNow.lerp or 0, g.zcMotion and g.zcMotion.hand or 0) -- rested on the bipod: the left hand comes off the gun
        if lhM then solveArm(g, 1, lhM:GetTranslation(), lhM:GetAngles(), off) end
        local map = g.zcFingers
        if not map then
            map = {}
            for bone = 0, gun:GetBoneCount() - 1 do
                local name = gun:GetBoneName(bone)
                if name and string.find(name, "Finger", 1, true) and ((rhM and string.find(name, "_R_", 1, true)) or (lhM and string.find(name, "_L_", 1, true))) then
                    -- LookupBone gives NO value on a miss, and SetBoneMatrix on an INVALID id throws an error that
                    -- pcall cannot catch, so the wiki's own "__INVALIDBONE__" test is made here, once, at map time.
                    local mine = g:LookupBone(name)
                    if mine and g:GetBoneName(mine) ~= "__INVALIDBONE__" then map[#map + 1] = {bone, mine, string.find(name, "_L_", 1, true) ~= nil} end
                end
            end
            g.zcFingers = map
        end
        -- Fingers are a nicety, but getting them wrong was not: an unwriteable bone throws an error PCALL CANNOT CATCH.
        -- It unwound this callback, holdWeapon's pcall and render.RenderView's, so the scene stopped being drawn part
        -- way through - after the body, before the gun was placed. That is what "no weapon in the replay" was.
        --
        -- Two defences. First, do not provoke it: a bone is writeable only once the engine has set it up THIS FRAME,
        -- and the entity that must be ready is the one being WRITTEN. The check was being made against the GUN, which
        -- is a different model, so a finger the gun had built and the ghost had not went straight through it. Guard the
        -- ghost, exactly as the gamemode's own writer does before every write (homigrad/cl_bones.lua:81).
        -- Second, bound it: the latch is set BEFORE the attempt and cleared only on the far side, so a throw - which by
        -- definition never reaches that line - leaves fingers off for this ghost instead of aborting every frame.
        if not g.zcNoFingers then
            g.zcNoFingers = true
            for _, pair in ipairs(map) do
                local m = not (pair[3] and off > 0.5) and gun:GetBoneMatrix(pair[1]) -- a hand that has let go keeps its own fingers
                if m and g:GetBoneMatrix(pair[2]) then g:SetBoneMatrix(pair[2], m) end
            end
            g.zcNoFingers = false
        end
    else
        -- SWEP:SetHandPos, the branch for ordinary world models.
        local base, ang = g.zcHandPos - g.zcHandAng:Up(), g.zcHandAng
        local rhPos, rhAng = LocalToWorld(w.RHPosOffset or vector_origin, w.RHAngOffset or angle_zero, base, ang)
        solveArm(g, -1, rhPos, rhAng)
        local lhBase = Angle(ang.p, ang.y, ang.r)
        lhBase:RotateAroundAxis(ang:Forward(), -90)
        local lhPos, lhAng = LocalToWorld(w.LHPos or Vector(15, 0, -4), w.LHAng or Angle(-110, -90, -90), base, lhBase)
        lhPos, lhAng = LocalToWorld(w.LHPosOffset or vector_origin, w.LHAngOffset or angle_zero, lhPos, lhAng)
        solveArm(g, 1, lhPos, lhAng, g.zcRestNow and g.zcRestNow.lerp or 0)
    end
end

function holdWeapon(g)
    weaponHands(g)
    carryHands(g)
end
end

-- Player models pick their animation set by hold type (idle_ar2, run_pistol, cwalk_smg1 ...).
local function holdType(clip, wep)
    if V.Unarmed(clip, wep) then return "all" end
    local stored = weaponTable(clip.weaponName[wep])
    local ht = stored and isstring(stored.HoldType) and stored.HoldType ~= "" and string.lower(stored.HoldType) or "ar2"
    return ht
end
local PASSIVE = {idle = "idle_all_01", walk = "walk_all", run = "run_all_01", cidle = "cidle_all", cwalk = "cwalk_all"}
local function sequenceFor(g, ht, move)
    if ht ~= "all" then
        local seq = g:LookupSequence(move .. "_" .. ht)
        if seq and seq >= 0 then return seq end
        seq = g:LookupSequence(move .. "_ar2")
        if seq and seq >= 0 then return seq end
    end
    return g:LookupSequence(PASSIVE[move])
end

-- The ghost's own pose parameter names, in the order the recorder recorded them - the recorder stores by INDEX and
-- the indices agree because the ghost wears the recorded model. Cached against the model, because building the list
-- is a call per parameter and the list only ever changes when the model does. `where` locates the handful the replay
-- used to derive for itself, so each can step aside only when the clip really carried it.
local DERIVED = {move_x = true, move_y = true, aim_pitch = true, head_pitch = true, aim_yaw = true}
local function poseNames(g)
    local model = g:GetModel()
    if g.zcPoseNames and g.zcPoseFor == model then return g.zcPoseNames, g.zcPoseWhere end
    local names, where = {}, {}
    for i = 0, g:GetNumPoseParameters() - 1 do
        local n = g:GetPoseParameterName(i)
        names[i + 1] = n
        if n and DERIVED[n] then where[n] = i + 1 end
    end
    g.zcPoseNames, g.zcPoseWhere, g.zcPoseFor = names, where, model
    g.zcPose = g.zcPose or {}
    return names, where
end

-- A downed or dead actor with recorded poses is shown as a real ragdoll, every physics bone placed where it was.
local RAG_REACH = Vector(96, 96, 96)
local function poseRagdoll(g, actor, cs, origin)
    local a, b, f = V.RagAt(actor, cs)
    if not a then return false end
    if g.zcRagBad then return false end
    local body = g.zcRag
    if not IsValid(body) then
        local want = actor.rag.m
        local model = want and want ~= "" and util.IsValidModel(want) and want or g:GetModel() -- what the body IS, which is what its clothes have to fit
        body = V.OwnReplayEntity(ClientsideRagdoll(model))
        if not IsValid(body) then return false end
        -- Recorded bones are indexed by physics object: on a different skeleton they would twist the body, so fall back to the mannequin.
        if body:GetPhysicsObjectCount() ~= (actor.rag.n or 0) then body:Remove() g.zcRagBad = true return false end
        -- The corpse wears what the body wore. Its own record wins, and the standing actor's skin and bodygroups fill in
        -- only when the body really is that model - bodygroup ids mean different things on a different skeleton. It
        -- usually IS: a body with no recorded model of its own is built from the actor's. Colour is the player's own and
        -- rides on any figure, because the PlayerColor proxy tints only materials that asked to be tinted.
        -- Submaterials are not recorded off the body itself: the corpse is the player's own model in practice, so the
        -- actor's clothes are the right ones whenever the models agree, and meaningless when they do not.
        local same = model == actor.m
        wear(body, actor.rag.sk or (same and actor.sk or nil), actor.rag.bg or (same and actor.bg or nil), actor.col,
             same and actor.sm or nil)
        body:SetNoDraw(false)
        body:DrawShadow(true)
        if g.zcPov then -- seen from its own eyes: the head would fill the screen, as it would on the standing body
            local head = body:LookupBone("ValveBiped.Bip01_Head1")
            if head then body:ManipulateBoneScale(head, Vector(0.01, 0.01, 0.01)) end
        end
        body:AddCallback("BuildBonePositions", V.Gore.Bones)
        g.zcRag = body
    end
    local n = math.min(actor.rag.n or 0, body:GetPhysicsObjectCount())
    for bone = 0, n - 1 do
        local phys = body:GetPhysicsObjectNum(bone)
        local i = 1 + bone * 6
        if IsValid(phys) and a[i + 6] and b[i + 6] then
            phys:EnableMotion(false)
            phys:SetPos(Vector(origin[1] + a[i + 1] + (b[i + 1] - a[i + 1]) * f, origin[2] + a[i + 2] + (b[i + 2] - a[i + 2]) * f, origin[3] + a[i + 3] + (b[i + 3] - a[i + 3]) * f), true)
            phys:SetAngles(LerpAngle(f, Angle(a[i + 4], a[i + 5], a[i + 6]), Angle(b[i + 4], b[i + 5], b[i + 6])))
        end
    end
    local grip = V.HandsAt and V.HandsAt(actor, cs) or 0
    if body.zcGrip ~= grip then
        for side = 1, 2 do
            for finger = 1, 4 do
                local bone = body:LookupBone("ValveBiped.Bip01_" .. (side == 1 and "L" or "R") .. "_Finger" .. finger .. "1")
                if bone then body:ManipulateBoneAngles(bone, V.HasFlag(grip, side) and Angle(0, -45, 0) or angle_zero) end
            end
        end
        body.zcGrip = grip
    end
    local root = body:GetPhysicsObjectNum(0)
    if IsValid(root) then
        local at = root:GetPos()
        body:SetRenderBoundsWS(at - RAG_REACH, at + RAG_REACH)
    end
    body:SetNoDraw(false)
    return true
end

-- Living fake-ragdolls still hold their active weapon. Place it on the
-- recorded body's hand without running a SWEP or moving recorded physics.
-- Dead actors intentionally do not retain an attached gun: dropped weapons
-- require their own recorded entity track, not a guess from the last loadout.
function V.PoseRagdollWeapon(g, actor, cs, clip, flags, body)
    local gun, w = g.zcGun, g.zcWeapon
    body = body or g.zcRag
    if not IsValid(gun) then return end
    gun:SetNoDraw(true)
    if not w or not V.HasFlag(flags, 1) or not IsValid(body) then return end
    body:SetupBones() -- this ragdoll has no standing ghost's IK callback
    local bone = body:LookupBone("ValveBiped.Bip01_R_Hand")
    local matrix = bone and body:GetBoneMatrix(bone)
    if not matrix then
        bone = body:LookupBone("ValveBiped.Bip01_R_Forearm")
        matrix = bone and body:GetBoneMatrix(bone)
    end
    if not matrix then return end
    local pos, ang = matrix:GetTranslation(), matrix:GetAngles()
    if g.zcFamily == "gun" then
        pos, ang = LocalToWorld(w.WorldPos or WORLD_POS, (w.WorldAng or WORLD_ANG) + (w.WorldAng2 or angle_zero), pos, ang)
        ang:RotateAroundAxis(ang:Forward(), 180)
        if w.WorldModelFake then pos, ang = LocalToWorld(w.FakePos or vector_origin, w.FakeAng or angle_zero, pos, ang) end
    else
        pos, ang = LocalToWorld(w.lpos or w.offsetVec or vector_origin, w.lang or w.offsetAng or angle_zero, pos, ang)
    end
    gun:SetPos(pos) gun:SetAngles(ang)
    gun:SetRenderOrigin(pos) gun:SetRenderAngles(ang)
    g.zcBasePos, g.zcAimAng = pos, ang
    g.zcPoseCs = cs
    gun:SetNoDraw(false)
end

local function pose(g, actor, cs, origin, clip)
    local x, y, z, yaw, _, flags, wep, _, eye, ex, ey, ez = V.StateAt(actor, cs)
    if x and (V.HasFlag(flags, 4) or not V.HasFlag(flags, 1)) and poseRagdoll(g, actor, cs, origin) then
        g:SetNoDraw(true)
        g.zcFlat, g.zcCarry, g.zcBeam = true, nil, 0
        arm(g, clip, V.HasFlag(flags, 1) and wep or 0, actor, true)
        V.PoseRagdollWeapon(g, actor, cs, clip, flags)
        return
    end
    if IsValid(g.zcRag) then g.zcRag:SetNoDraw(true) end
    if not x then
        g:SetNoDraw(true)
        if IsValid(g.zcGun) then g.zcGun:SetNoDraw(true) end
        return
    end
    g.zcCarry = nil
    if V.HandsAt then
        local _, mask, cx, cy, cz, cp, cyaw = V.HandsAt(actor, cs)
        if mask > 0 then g.zcCarry = {mask = mask, pos = Vector(origin[1] + cx, origin[2] + cy, origin[3] + cz), aim = Angle(cp, cyaw, 0)} end
    end
    arm(g, clip, V.HasFlag(flags, 1) and wep or 0, actor, V.HasFlag(flags, 4) or not V.HasFlag(flags, 1))
    if IsValid(g.zcGun) then g.zcGun:SetNoDraw(false) end
    local pitch = select(5, V.StateAt(actor, cs))
    -- Velocity. The recorder carries the real one now; only a clip cut before 2026-09-22 falls back to differencing
    -- two positions 100 ms apart, which lags the truth by 50 ms and is simply wrong through any change of direction.
    -- `V.MotionAt and` is not defensive noise: V.MotionAt and V.PoseAt live in cl_analysis.lua, which ships as its
    -- own client file rather than inside this bundle, so a half-finished deploy really can leave them nil. Missing,
    -- the replay falls back to what it did before instead of throwing on the first frame.
    local vx, vy, vz, recSeq, recCyc = nil, nil, nil, nil, nil
    if V.MotionAt then vx, vy, vz, recSeq, recCyc = V.MotionAt(actor, cs) end
    if not vx then
        local px, py = V.StateAt(actor, cs - 10)
        vx, vy, vz = px and (x - px) * 10 or 0, py and (y - py) * 10 or 0, 0
    end
    local speed = math.sqrt(vx * vx + vy * vy)
    g.zcSpeed, g.zcVz = speed, vz or 0
    local alive, down, crouch = V.HasFlag(flags, 1), V.HasFlag(flags, 4), V.HasFlag(flags, 2)
    -- The sequence the server was really playing beats guessing between five by speed - a jump, a vault, a ladder or
    -- any animation Z-City drives itself replayed as a walk before this. It is an index into the RECORDED model's
    -- sequence list, so it is only meaningful on a ghost wearing that model; a mannequin stand-in still guesses.
    local exact = recSeq and actor.m and g:GetModel() == actor.m and recSeq < g:GetSequenceCount()
    local move = crouch and (speed > 20 and "cwalk" or "cidle") or (speed > 170 and "run" or (speed > 20 and "walk" or "idle"))
    local seq = exact and recSeq or sequenceFor(g, holdType(clip, wep), move)
    if seq and seq >= 0 and g:GetSequence() ~= seq then g:ResetSequence(seq) end
    -- Pose parameters, as the server had them. Recorded BY INDEX, which is exact on the same model and meaningless on
    -- any other, so they are applied only when the ghost wears the one the clip names. Whatever the clip does not
    -- carry keeps the old derivation below, so an old clip animates exactly as it used to.
    local names, where = poseNames(g)
    local poses = g.zcPose
    local np = (V.PoseAt and actor.m and g:GetModel() == actor.m) and V.PoseAt(actor, cs, poses) or 0
    for k = 1, np do
        local name = names[k]
        if name then g:SetPoseParameter(name, poses[k]) end
    end
    g.zcPoseN = np
    -- The walk and run sequences are nine-way blends: without move_x / move_y they play frozen on the spot. These four
    -- are the ones the replay used to derive; each is left alone where the clip supplied the real thing.
    local rad = math.rad(yaw)
    local fx, fy = math.cos(rad), math.sin(rad)
    local scale = speed > 1 and 1 / speed or 0
    if np < (where.move_x or 1e9) then g:SetPoseParameter("move_x", (vx * fx + vy * fy) * scale) end
    if np < (where.move_y or 1e9) then g:SetPoseParameter("move_y", (vx * fy - vy * fx) * scale) end
    if np < (where.aim_pitch or 1e9) then g:SetPoseParameter("aim_pitch", math.Clamp(pitch or 0, -89, 89)) end
    if np < (where.head_pitch or 1e9) then g:SetPoseParameter("head_pitch", math.Clamp(pitch or 0, -60, 60)) end
    -- Gait follows distance covered, so feet keep pace at any playback speed (and hold still when paused). With the
    -- real sequence AND its real cycle there is nothing to keep pace with: play the frame the server was on.
    g.zcStride = (g.zcStride or 0) + (g.zcLastCs and math.max(cs - g.zcLastCs, 0) / 100 * speed or 0)
    g.zcLastCs = cs
    if exact and recCyc then
        g:SetCycle(recCyc)
    else
        g:SetCycle(speed > 20 and (g.zcStride / (move == "run" and 190 or 95)) % 1 or (cs / 100 * 0.25) % 1)
    end
    -- Punches (recorder event kind 6; how 2 = right). The game plays range_fists_r / range_fists_l as a GESTURE over the
    -- legs (weapon_hands_sh.lua:1441). A client-side model has no gesture layers, so for the length of the punch the
    -- gesture is the body's whole sequence: the arms are right, the legs stand still for that moment even if running.
    -- PROVISIONAL(2026-09-21, no gesture layers on a ClientsideModel; not yet seen in-game, ratify-by: 2026-10-21)
    g.zcPunching = false
    g.zcPoseCs = cs
    local okLean, leanErr = pcall(leanOver, g, flags, g.zcLeanCs and math.max(cs - g.zcLeanCs, 0) / 100 or 1, alive and not down)
    g.zcLeanCs = cs
    if not okLean and not L.leanErr then L.leanErr = true print("[Killcam] lean: " .. tostring(leanErr)) end
    if alive and not down and V.Unarmed(clip, wep) then
        local index = g.zcIndex
        if not index then
            for i = 1, #clip.actors do if L.ghosts[i] == g then index = i end end
            g.zcIndex = index or 0
        end
        local at, right
        local events = clip.events
        for k = V.EvFrom(clip, cs - 500), #events do -- replay_v1 P3: from event 1 for a death clip, as before
            local e = events[k]
            if e[1] > cs then break end
            if e[2] == 6 and e[3] == index then at, right = e[1], e[5] == 2 end
        end
        if at then
            local punch = g:LookupSequence(right and "range_fists_r" or "range_fists_l")
            local length = punch and punch >= 0 and g:SequenceDuration(punch) or 0
            if length > 0 and cs - at < length * 100 then
                local d = g.zcDouble
                if not g.zcNoDouble and (not IsValid(d) or d:GetModel() ~= g:GetModel()) then
                    if IsValid(d) then d:Remove() end
                    d = V.OwnReplayEntity(ClientsideModel(g:GetModel(), RENDERGROUP_OPAQUE))
                    if IsValid(d) then d:SetNoDraw(true) end
                    g.zcDouble = d
                end
                if IsValid(d) and not g.zcNoDouble then
                    if d:GetSequence() ~= punch then d:ResetSequence(punch) end
                    d:SetCycle((cs - at) / (length * 100))
                    d:SetPos(Vector(origin[1] + x, origin[2] + y, origin[3] + z))
                    d:SetAngles(Angle(0, yaw, 0))
                    d:InvalidateBoneCache()
                    d:SetupBones() -- the double has no bone callback: safe outside a draw
                    g.zcPunching = true
                else -- no double: the punch takes the whole body for its length, legs included
                    if g:GetSequence() ~= punch then g:ResetSequence(punch) end
                    g:SetCycle((cs - at) / (length * 100))
                end
            end
        end
    end
    -- killcam_kinds: a melee swing's body gesture over the legs, through the punch double (V.MeleeGesture, cl_part_04)
    -- Not on the killer's own first-person body: the eye hangs off its neck (zcNeckPos, read after punchOver), and live
    -- play never shakes your own view with your swing. Its own latch, so a failure here never costs the punches.
    if alive and not down and not g.zcPov and g.zcFamily == "melee" and g.zcSwingFrom and not g.zcNoSwing and not g.zcNoDouble and V.MeleeGesture then
        local okG, errG = pcall(V.MeleeGesture, g, cs, origin, x, y, z, yaw)
        if not okG then g.zcNoSwing = true print("[Killcam] melee body swing disabled for a ghost: " .. tostring(errG)) end
    end
    g:InvalidateBoneCache()
    g:SetPos(Vector(origin[1] + x, origin[2] + y, origin[3] + z + ((down or not alive) and 8 or 0)))
    -- Feet, not eyes. `aim_yaw` is the twist of the aim against the FEET (CBasePlayerAnimState keeps it as
    -- eyeYaw - goalFeetYaw), so a body drawn at the eye yaw with aim_yaw applied on top is turned twice. Standing the
    -- body on eyeYaw - aim_yaw puts the legs where the game had them and lets the recorded twist do the rest; without
    -- the recorded value aim_yaw is 0 and this is exactly the old behaviour.
    --
    -- The SIGN is checked against the engine, not guessed. CBasePlayerAnimState::ComputePoseParam_BodyYaw does
    --     flCurrentTorsoYaw = AngleNormalize(m_flEyeYaw - m_flCurrentFeetYaw)  -> SetOuterBodyYaw(flCurrentTorsoYaw)
    --     m_angRender[YAW] = m_flCurrentFeetYaw
    -- so the model is RENDERED at the feet yaw and the pose parameter is eyeYaw - feetYaw. Rearranged, the body
    -- belongs at eyeYaw - aim_yaw, which is what this does. GMod agrees on the second half: Player:GetRenderAngles
    -- is documented as carrying only the yaw, and it is the body yaw, not EyeAngles.
    --
    -- Two things are NOT settled, which is why this is a convar and not a constant:
    --   * that formula comes from the CS:GO-era SDK mirrors; it is not in source-sdk-2013, and GMod's player
    --     animation being the same lineage is inference rather than documentation;
    --   * nothing documents that `aim_yaw` on a non-HL2 playermodel means the same thing as `body_yaw` on an HL2 one.
    --     This server's models use aim_yaw (measured 2026-09-22), and that equivalence is community lore.
    -- Getting it backwards points the legs the wrong way by twice the twist, so it stays one console command away:
    -- 1 = feet behind the aim (the engine's convention, default), -1 = the other way, 0 = body drawn straight at the
    -- aim, which is exactly how replays looked before this.
    -- PROVISIONAL(2026-09-22, formula verified against engine source but not yet seen in game, ratify-by: 2026-10-22)
    local bodyYaw = V.AnimationAt and V.AnimationAt(actor, cs)
    local feet = yaw
    local lean = V.FeetCV and V.FeetCV:GetInt() or 1
    if lean ~= 0 and np >= (where.aim_yaw or 1e9) then feet = yaw - poses[where.aim_yaw] * (lean < 0 and -1 or 1) end
    if bodyYaw ~= nil then feet = bodyYaw end
    g:SetAngles((down or not alive) and Angle(-90, feet, 0) or Angle(0, feet, 0)) -- down or dead: laid flat
    g:SetNoDraw(false)
    g.zcFlat = down or not alive
    -- The eyes the replay looks through sit where the game would put them on THIS body: hg.eye (homigrad/sh_utility.lua:767)
    -- is the neck bone + 2 up the aim + 4 to the bone's right + 4 along it. The eye recorded from the server's skeleton
    -- came out about six units behind the body the replay draws (owner, 2026-09-21) - the server does not run the client's
    -- animation layers - so the visible body is the authority and the recorded eye is only the fallback. The gun hangs
    -- off the same point, as it does in the game (sh_worldmodel.lua:173).
    g.zcEye, g.zcEyeCs = nil, nil
    g.zcBeam = g.zcFlat and 0 or ((V.HasFlag(flags, 256) and 1 or 0) + (V.HasFlag(flags, 512) and 2 or 0)) -- laser 1, light 2 (recorder flags)
    if g.zcPov and not g.zcFlat and g.zcNeckPos then
        -- The neck as the last drawn frame had it, carried to where the body stands NOW. Forcing a bone setup here instead
        -- ran the arm IK outside a draw, where bones cannot be written (the owner's "Bone is unwriteable" errors).
        local neckAt, na = LocalToWorld(g.zcNeckPos, g.zcNeckAng, g:GetPos(), g:GetAngles())
        g.zcEye = neckAt + Angle(pitch or 0, yaw, 0):Up() * 2 + na:Right() * 4 + na:Forward() * 4
        g.zcEyeCs = cs
    end
    if IsValid(g.zcGun) then
        if g.zcFlat then
            -- Old clips or unavailable ragdoll skeletons use the visible fallback body.
            V.PoseRagdollWeapon(g, actor, cs, clip, flags, g)
        else
            local step = g.zcMotionCs and math.max(cs - g.zcMotionCs, 0) / 100 or 0 -- replay seconds since the last pose: nothing drifts while paused
            g.zcMotionCs = cs
            local motion = gunMotion(g, cs, speed, V.HasFlag(flags, 8), crouch, V.HasFlag(flags, 64), step, flags, pitch)
            reloadCycle(g, g.zcWeapon, cs, V.HasFlag(flags, 32), actor)
            local okAct, actErr = pcall(actionCycle, g, g.zcWeapon, clip, cs)
            if not okAct and not L.actErr then L.actErr = true print("[Killcam] swing / throw: " .. tostring(actErr)) end
            local okFire, fireErr = pcall(V.FireCycle, g, g.zcWeapon, clip, cs) -- G1: fenced like the swing
            if not okFire and not L.fireErr then L.fireErr = true print("[Killcam] fire cycle: " .. tostring(fireErr)) end
            local eyeAt = g.zcEye or Vector(origin[1] + x + (ex or 0), origin[2] + y + (ey or 0), origin[3] + z + (ez or eye or 64))
            local fix = g.zcFixW or 0
            local aimNow = Angle((pitch or 0) + (g.zcFixP or 0) * fix, yaw + (g.zcFixY or 0) * fix, 0) -- recorded aim + the barrel-line correction (aimFix): the game's recoil is already in it (sh_spray.lua SetEyeAngles)
            local held = motion
            local okShot, rp, ra = pcall(shotRecoil, g, g.zcWeapon, clip, cs)
            if okShot and rp then held = {pos = motion.pos + rp, ang = motion.ang + ra, relax = motion.relax} end -- the sights (eyeOf) keep the un-kicked motion: the gun jumps in front of a steady eye
            local rest
            if isvector(g.zcWeapon.RestPosition) then
                local _, _, hp0, ha0 = heldTransform(g.zcWeapon, eyeAt, aimNow.p, yaw, motion)
                rest = restPoint(g, g.zcWeapon, V.HasFlag(flags, 128), hp0 - ha0:Up(), Angle(pitch or 0, yaw, 0), step, actor, cs, origin)
            end
            g.zcRestNow = rest -- eyeOf lines the sights up on the rested gun
            local gp, ga, hp, ha, base = heldTransform(g.zcWeapon, eyeAt, aimNow.p, yaw, held, rest)
            if g.zcFamily == "melee" then
                gp, ga = LocalToWorld(g.zcWeapon.HoldPos or vector_origin, g.zcWeapon.HoldAng or angle_zero, eyeAt, aimNow)
            elseif g.zcFamily == "tpik" then
                local hold = g.zcWeapon.HoldPos or vector_origin
                gp = eyeAt + aimNow:Forward() * (hold[1] - 4) + aimNow:Right() * hold[2] + aimNow:Up() * hold[3]
                _, ga = LocalToWorld(vector_origin, g.zcWeapon.HoldAng or angle_zero, vector_origin, aimNow)
            end
            g.zcBasePos, g.zcAimAng = base, aimNow
            g.zcGun:SetPos(gp) g.zcGun:SetAngles(ga)
            g.zcGun:SetRenderOrigin(gp) g.zcGun:SetRenderAngles(ga)
            g.zcHandPos, g.zcHandAng = hp, ha
        end
    end
end

----------------------------------------------------------------- sound and flash
-- Played with no engine attenuation and our own distance falloff: the audio listener is not
-- guaranteed to follow a replay camera, so positional playback could come out silent.
local FLESH = {"physics/flesh/flesh_impact_bullet1.wav", "physics/flesh/flesh_impact_bullet2.wav", "physics/flesh/flesh_impact_bullet3.wav", "physics/flesh/flesh_impact_bullet4.wav", "physics/flesh/flesh_impact_bullet5.wav"}
local STEPS = {"player/footsteps/concrete1.wav", "player/footsteps/concrete2.wav", "player/footsteps/concrete3.wav", "player/footsteps/concrete4.wav"}
local FALLBACK_SHOT = "weapons/ar2/fire1.wav"
local shotSound = {}
local function fireSound(class, actor)
    -- a fitted suppressor changes the report (homigrad_base/shared.lua:698)
    local barrel = actor and istable(actor.att) and istable(actor.att[class]) and actor.att[class].barrel
    local quiet = isstring(barrel) and string.find(barrel, "supressor", 1, true) ~= nil
    local stored = weaponTable(class)
    if quiet and stored then
        local pistol = isfunction(stored.IsPistolHoldType) and select(2, pcall(stored.IsPistolHoldType, stored)) == true
        return isstring(stored.SupressedSound) and stored.SupressedSound or pistol and "homigrad/weapons/pistols/sil.wav" or "m4a1/m4a1_suppressed_fp.wav"
    end
    if shotSound[class] ~= nil then return shotSound[class] end
    local snd = stored and stored.Primary and stored.Primary.Sound
    if istable(snd) then snd = snd[1] end
    if not isstring(snd) or snd == "" then snd = FALLBACK_SHOT end
    shotSound[class] = snd
    return snd
end

local function worldPos(clip, actor, cs, up)
    local x, y, z = V.StateAt(actor, cs)
    if not x then return end
    local o = clip.origin
    return Vector(o[1] + x, o[2] + y, o[3] + z + (up or 0))
end

local function play(path, pos, ear, rate, loud)
    if not pos or not ear then return end
    if V.UISide and V.UISide() then return end -- postround_20260925: a side card is silent (no phantom shots in the live world)
    local vol = math.Clamp(1 - pos:Distance(ear) / (loud and 4000 or 1200), loud and 0.2 or 0, 1)
    if vol <= 0 then return end
    -- slow motion drops the pitch with it, which is most of what sells it
    sound.Play(path, ear, 0, math.Clamp(38 + rate * 62, 50, 100), vol) -- pitch follows the slow-motion ramp
end

-- Sound metadata is optional. Missing assets and old clips retain the original fallbacks.
V.SoundCV = CreateClientConVar("zc_killcam_live_sounds", "1", true, false, "Play captured gameplay effects in replays")
function V.ReplaySoundDuration(path)
    if not isstring(path) or #path > 180 or string.find(path, "..", 1, true) or string.find(path, "[%c:]" ) then return end
    if not (string.match(path, "%.wav$") or string.match(path, "%.mp3$") or string.match(path, "%.ogg$")) then return end
]========], 2)
