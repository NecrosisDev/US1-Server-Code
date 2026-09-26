hg.organism = hg.organism or {}
local empty = {}
local Vector = Vector --ыыы
local vecZero, angZero = Vector(0, 0, 0), Angle(0, 0, 0)
local box, _mins = Vector(0, 0, 0), Vector(0, 0, 0)
local center
local function getTransform(pos, ang, mins, maxs, obbCenter)
	box:Set(mins)
	box:Sub(maxs)
	box:Div(2) --holyshit...
	box:Rotate(ang)
	_mins:Set(mins)
	_mins:Rotate(ang)
	_mins:Sub(box)
	center = pos + _mins
	return center, (obbCenter - center):Length() + box:Length() / 2
end

local LocalToWorld = LocalToWorld
if SERVER then ZCHitboxMatrixPhase2Version = "20260918.1" end

-- Model/organ descriptor cache: these values are static for a given model and
-- organ table. Dynamic bone matrices are still fetched every ShootMatrix call.
local shootDescriptorCache = {}

local function copyVector(v)
    return Vector(v.x, v.y, v.z)
end

local function getShootDescriptor(ent, organs)
    local model = ent:GetModel() or ""
    local byModel = shootDescriptorCache[model]
    if not byModel then
        byModel = {}
        shootDescriptorCache[model] = byModel
    end
    local cached = byModel[organs]
    if cached then return cached end

    local hitboxes = {}
    for i = 0, ent:GetHitBoxCount(0) - 1 do
        local mins, maxs = ent:GetHitBoxBounds(i, 0)
        hitboxes[#hitboxes + 1] = {
            bone = ent:GetHitBoxBone(i, 0),
            mins = copyVector(mins),
            maxs = copyVector(maxs)
        }
    end

    local organBones = {}
    for nameBone, organList in pairs(organs) do
        local bone = ent:LookupBone(nameBone)
        if bone and bone >= 0 then
            local entries = {}
            for key, organ in pairs(organList) do
                local half = organ[5]
                entries[#entries + 1] = {
                    key = key,
                    mins = Vector(-half.x, -half.y, -half.z),
                    maxs = Vector(half.x, half.y, half.z),
                    offsetPos = organ[3],
                    offsetAng = organ[4],
                    additional = organ[7],
                    armorName = organ[1]
                }
            end
            organBones[#organBones + 1] = {
                bone = bone,
                nameBone = nameBone,
                entries = entries
            }
        end
    end

    cached = {hitboxes = hitboxes, organBones = organBones}
    byModel[organs] = cached
    return cached
end

function hg.organism.ShootMatrix(ent, organs)
    if not organs or not istable(organs) or table.IsEmpty(organs) then return end
    local descriptor = getShootDescriptor(ent, organs)
    local boxs = {}
    local pos, ang, matrix
    local sphereChunk = 0
    local obbCenter = ent:GetPos()
    obbCenter:Add(ent:OBBCenter())

    for i = 1, #descriptor.hitboxes do
        local meta = descriptor.hitboxes[i]
        matrix = ent:GetBoneMatrix(meta.bone)
        if not matrix then continue end
        pos = matrix:GetTranslation()
        ang = matrix:GetAngles()
        local hitCenter, disOfCenter = getTransform(pos, ang, meta.mins, meta.maxs, obbCenter)
        if disOfCenter > sphereChunk then sphereChunk = disOfCenter end
        boxs[#boxs + 1] = {pos, ang, meta.mins, meta.maxs, hitCenter}
    end

    -- Resolve armor owner/value presence once instead of RagdollOwner +
    -- table.HasValue for every armor-backed organ box.
    local armorHolder = ent
    if not ent:IsPlayer() and ent:IsRagdoll() then
        local ragOwner = hg.RagdollOwner(ent)
        if IsValid(ragOwner) then armorHolder = ragOwner end
    end
    local armors = armorHolder and armorHolder.armors
    local armorValues
    if istable(armors) then
        armorValues = {}
        for _, armorName in pairs(armors) do
            armorValues[armorName] = true
        end
    end

    for i = 1, #descriptor.organBones do
        local boneMeta = descriptor.organBones[i]
        matrix = ent:GetBoneMatrix(boneMeta.bone)
        if not matrix then continue end
        local bonePos = matrix:GetTranslation()
        local boneAng = matrix:GetAngles()
        for j = 1, #boneMeta.entries do
            local meta = boneMeta.entries[j]
            if meta.additional and armors and not (armorValues and armorValues[meta.armorName]) then
                continue
            end
            local organCenter, disOfCenter = getTransform(bonePos, boneAng, meta.mins, meta.maxs, obbCenter)
            if disOfCenter > sphereChunk then sphereChunk = disOfCenter end
            local organPos, organAng = LocalToWorld(meta.offsetPos, meta.offsetAng, bonePos, boneAng)
            boxs[#boxs + 1] = {
                organPos, organAng, meta.mins, meta.maxs, organCenter,
                boneMeta.nameBone, meta.key
            }
        end
    end

    return boxs, obbCenter, sphereChunk
end

--local util_IsOBBIntersectingOBB = util.IsOBBIntersectingOBB --huy not server side
local util_IntersectRayWithOBB = util.IntersectRayWithOBB
local math_ceil = math.ceil
local stepDiv = 1
local tracePos = Vector(0, 0, 0)

function hg.organism.Trace_Bullet(organs)
	local organ = box[6] and organs[box[6]][box[7]]
	return organ and organ[2] or 0
end

local models_female = {
	["models/player/group01/female_01.mdl"] = true,
	["models/player/group01/female_02.mdl"] = true,
	["models/player/group01/female_03.mdl"] = true,
	["models/player/group01/female_04.mdl"] = true,
	["models/player/group01/female_05.mdl"] = true,
	["models/player/group01/female_06.mdl"] = true,
	["models/player/group03/female_01.mdl"] = true,
	["models/player/group03/female_02.mdl"] = true,
	["models/player/group03/female_03.mdl"] = true,
	["models/player/group03/female_04.mdl"] = true,
	["models/player/group03/female_05.mdl"] = true,
	["models/player/group03/police_fem.mdl"] = true
}

if SERVER then return end

local render_DrawW
local white, red, blue, black = Color(255, 255, 255), Color(255, 0, 0), Color(0, 0, 255), Color(0, 0, 0)
local hg_show_hitbox = ConVarExists("hg_show_hitbox") and GetConVar("hg_show_hitbox") or CreateClientConVar("hg_show_hitbox", "0", false, false, "shows custom players hitboxes, work only for admins or with sv_cheats 1 enabled")
local hg_show_hitbox_dir = ConVarExists("hg_show_hitbox_dir") and GetConVar("hg_show_hitbox_dir") or CreateClientConVar("hg_show_hitbox_dir", "0", false, false, "work only for admins or with sv_cheats 1 enabled")
render_DrawWireframeBox = render.DrawWireframeBox
hook.Add("PostDrawTranslucentRenderables", "homigrad-organism", function()
	if not hg_show_hitbox:GetBool() then return end
	if not LocalPlayer():IsAdmin() then return end
	for i, ply in player.Iterator() do
		if GetViewEntity() == ply then continue end
		ply = hg.GetCurrentCharacter(ply)
		local organs = hg.organism.GetHitBoxOrgans(ply:GetModel(), ply)
		if not organs then return end
		local boxs, pos, sphere = hg.organism.ShootMatrix(ply, organs)
		if hg_show_hitbox_dir:GetFloat() > 0 and hg.organism.Trace then
			local dir = Vector(hg_show_hitbox_dir:GetFloat(), 0, 0)
			dir:Rotate(LocalPlayer():EyeAngles())
			local distance = math_ceil(dir:Length())
			local start = hg.eyeTrace(lply).HitPos -- Vector(1005.879456,608.151123,-77.997421)
			//pos, dir, size, maxpen, boxs, center, endDis, organs, ricochetable, funcInput, ...
			local endPos, hitBoxs, inputHole, outputHole = hg.organism.Trace(start, dir, 1, 0, boxs, pos, sphere, organs, false, hg.organism.Trace_Bullet, organs)
			--render.DrawWireframeBox(endPos, angZero, -box, box)
			
			render.DrawWireframeBox(start, LocalPlayer():EyeAngles(), -Vector(0,distance / 50,distance / 50),Vector(distance / 1,distance / 50,distance / 50))
			for i = 1, #boxs do
				local box = boxs[i]
				local organ = box[6] and organs[box[6]][box[7]]
				render_DrawWireframeBox(box[1], box[2], box[3], box[4], (hitBoxs[i] and white) or (organ and organ[6]) or black)
			end

			for i = 1, #inputHole do
				render.DrawWireframeSphere(inputHole[i], 1, 16, 16, red)
			end

			for i = 1, #outputHole do
				render.DrawWireframeSphere(outputHole[i], 0.5, 16, 16, blue)
			end
		else
			for i = 1, #boxs do
				local box = boxs[i]
				local organ = box[6] and organs[box[6]][box[7]]
				render_DrawWireframeBox(box[1], box[2], box[3], box[4], (organ and organ[6]) or black)
			end
		end
		--render.DrawWireframeSphere(pos,sphere,16,16,color2)
	end
end)