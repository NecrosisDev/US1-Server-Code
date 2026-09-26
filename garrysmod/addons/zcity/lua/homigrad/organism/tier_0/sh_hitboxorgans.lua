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
function hg.organism.ShootMatrix(ent, organs)
	if not organs or not istable(organs) or table.IsEmpty(organs) then return end
	local boxs = {}
	local mins, maxs, matrix, box
	local pos, ang, center
	local sphereChunk = 0
	local obbCenter = ent:GetPos() --да какая же хуйня это))0
	obbCenter:Add(ent:OBBCenter())
	for i = 0, ent:GetHitBoxCount(0) - 1 do
		matrix = ent:GetBoneMatrix(ent:GetHitBoxBone(i, 0))
		if not matrix then continue end
		mins, maxs = ent:GetHitBoxBounds(i, 0)
		pos = matrix:GetTranslation()
		ang = matrix:GetAngles()
		local center, disOfCenter = getTransform(pos, ang, mins, maxs, obbCenter)
		if disOfCenter > sphereChunk then sphereChunk = disOfCenter end
		boxs[#boxs + 1] = {pos, ang, mins, maxs, center}
	end

	for nameBone, organs in pairs(organs) do
		local bone = ent:LookupBone(nameBone)
		--if not bone then continue end
		matrix = ent:GetBoneMatrix(bone)
		if not matrix then continue end
		pos = matrix:GetTranslation()
		ang = matrix:GetAngles()
		for key, organ in pairs(organs) do
			--print(key,organ[1])
			local additional = organ[7]
			if additional then
				local ent = ent:IsPlayer() and ent or ent:IsRagdoll() and IsValid(hg.RagdollOwner(ent)) and hg.RagdollOwner(ent) or ent
				if ent and ent.armors and not table.HasValue(ent.armors,organ[1]) then
					continue
				end
			end
			mins = -organ[5]
			maxs = -mins
			local center, disOfCenter, boxLen = getTransform(pos, ang, mins, maxs, obbCenter)
			if disOfCenter > sphereChunk then sphereChunk = disOfCenter end
			local pos, ang = LocalToWorld(organ[3], organ[4], pos, ang)
			boxs[#boxs + 1] = {pos, ang, mins, maxs, center, nameBone, key}
		end
	end

	//table.sort(boxs, function(a, b) return (organs[a[6]] and organs[a[6]][a[7]][2] or 0) > (organs[b[6]] and organs[b[6]][b[7]][2] or 0) end)
	//PrintTable(boxs)
	return boxs, obbCenter, sphereChunk
end

--local util_IsOBBIntersectingOBB = util.IsOBBIntersectingOBB --huy not server side
local util_IntersectRayWithOBB = util.IntersectRayWithOBB
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

local white, red, blue, black = Color(255, 255, 255), Color(255, 0, 0), Color(0, 0, 255), Color(0, 0, 0)
local grey, yellow = Color(128, 128, 128), Color(255, 255, 0)
local hg_show_hitbox = ConVarExists("hg_show_hitbox") and GetConVar("hg_show_hitbox") or CreateClientConVar("hg_show_hitbox", "0", false, false, "shows custom players hitboxes, work only for admins or with sv_cheats 1 enabled")
local hg_show_hitbox_dir = ConVarExists("hg_show_hitbox_dir") and GetConVar("hg_show_hitbox_dir") or CreateClientConVar("hg_show_hitbox_dir", "0", false, false, "work only for admins or with sv_cheats 1 enabled")
local render_DrawWireframeBox = render.DrawWireframeBox

-- hg_show_hitbox 2: solid translucent organ boxes. Colors depend only on the organ row
-- (bone/armor-ness never changes at runtime), so cache one Color per row instead of
-- allocating one per box per frame.
local solidColorCache = {}
local function solidColor(organ)
	local cached = solidColorCache[organ]
	if cached then return cached end
	local c
	if organ[7] == true then
		c = Color(250, 255, 0, 40)
	else
		local col = organ[6] or white
		if type(organ[2]) == "number" and organ[2] >= 0.2 then
			c = Color(col.r, col.g, col.b, 90)
		else
			c = Color(col.r, col.g, col.b, 55)
		end
	end
	solidColorCache[organ] = c
	return c
end

-- hg_show_hitbox_dir preview: V2 segment/event colours.
local segColors = {
	flesh = red,
	organ = Color(255, 165, 0),
	lung = Color(255, 192, 203),
	bone = white,
	vessel = Color(139, 0, 0),
	armor = yellow,
	air = grey,
	dense = Color(255, 140, 0),
}
local eventStyle = {
	entry = {red, 1},
	deflect = {yellow, 1},
	lodge = {black, 1.5},
	exit = {blue, 0.75},
	armor = {yellow, 0.75},
	maxpen = {grey, 1},
}

-- organs2_20260925: draw an organ box as its shape (V2.TagShapes marks it). Ellipsoids are a unit sphere under a scaled
-- model matrix; capsules are their two end spheres and four side lines (wireframe) or a stretched sphere (solid).
local shapeMatrix = Matrix()
function hg.organism.DrawOrganShape(box, col, solid)
	local s = box.v2shape
	if s ~= "ellipsoid" and s ~= "capsule" then
		if solid then render.SetColorMaterial() render.DrawBox(box[1], box[2], box[3], box[4], col) end
		render_DrawWireframeBox(box[1], box[2], box[3], box[4], col)
		return
	end
	local half = (box[4] - box[3]) / 2
	local centre = LocalToWorld((box[3] + box[4]) / 2, angle_zero, box[1], box[2])
	if s == "ellipsoid" then
		shapeMatrix:Identity()
		shapeMatrix:Translate(centre)
		shapeMatrix:Rotate(box[2])
		shapeMatrix:Scale(half)
		cam.PushModelMatrix(shapeMatrix)
		if solid then render.SetColorMaterial() render.DrawSphere(vector_origin, 1, 16, 12, col)
		else render.DrawWireframeSphere(vector_origin, 1, 16, 12, col, true) end
		cam.PopModelMatrix()
		return
	end
	local f, r, u = box[2]:Forward(), -box[2]:Right(), box[2]:Up()
	local axis, rad, h
	if half.x >= half.y and half.x >= half.z then axis, rad, h = f, math.max(half.y, half.z), half.x
	elseif half.y >= half.z then axis, rad, h = r, math.max(half.x, half.z), half.y
	else axis, rad, h = u, math.max(half.x, half.y), half.z end
	h = math.max(h - rad, 0)
	local a, b = centre - axis * h, centre + axis * h
	if solid then -- a solid capsule: its two end spheres and the box of its middle
		render.SetColorMaterial()
		render.DrawSphere(a, rad, 12, 8, col)
		render.DrawSphere(b, rad, 12, 8, col)
		local mid = Vector(rad, rad, rad)
		if axis == f then mid.x = h elseif axis == r then mid.y = h else mid.z = h end
		render.DrawBox(centre, box[2], -mid, mid, col)
		return
	end
	render.DrawWireframeSphere(a, rad, 10, 8, col, true)
	render.DrawWireframeSphere(b, rad, 10, 8, col, true)
	local side = axis:Cross(math.abs(axis.z) < 0.9 and Vector(0, 0, 1) or Vector(1, 0, 0)):GetNormalized()
	local up = axis:Cross(side)
	for _, o in ipairs({side, -side, up, -up}) do render.DrawLine(a + o * rad, b + o * rad, col, true) end
end

hook.Add("PostDrawTranslucentRenderables", "homigrad-organism", function()
	if not hg_show_hitbox:GetBool() then return end
	if not LocalPlayer():IsAdmin() then return end
	for i, ply in player.Iterator() do
		if GetViewEntity() == ply then continue end
		ply = hg.GetCurrentCharacter(ply)
		local organs = hg.organism.GetHitBoxOrgans(ply:GetModel(), ply)
		if not organs then continue end
		local boxs, pos, sphere = hg.organism.ShootMatrix(ply, organs)
		if hg.organism.BallisticsV2 and hg.organism.BallisticsV2.TagShapes then hg.organism.BallisticsV2.TagShapes(boxs, organs) end
		if hg_show_hitbox_dir:GetFloat() > 0 then
			local V2 = hg.organism.BallisticsV2
			if not V2 then continue end
			local start = hg.eyeTrace(LocalPlayer()).HitPos
			local eyeDir = LocalPlayer():EyeAngles():Forward()
			local ok, result = pcall(V2.Trace, start, eyeDir, hg_show_hitbox_dir:GetFloat(), boxs, organs, pos, sphere, {rng = function() return 0 end, profile = V2.ResolveProfile and V2.ResolveProfile({construction = "fmj", fragChance = 0}) or nil})
			if ok and result then
				for i = 1, #boxs do
					local box = boxs[i]
					local organ = box[6] and organs[box[6]][box[7]]
					hg.organism.DrawOrganShape(box, (result.hitBoxs[i] and white) or (organ and organ[6]) or black)
				end

				for i = 1, #result.segments do
					local seg = result.segments[i]
					render.DrawLine(seg.a, seg.b, segColors[seg.class] or white, true)
				end

				for i = 1, #result.events do
					local ev = result.events[i]
					local style = eventStyle[ev.kind]
					if style then
						render.DrawWireframeSphere(ev.pos, style[2], 16, 16, style[1])
					end
				end
			end
		else
			local mode = hg_show_hitbox:GetInt()
			for i = 1, #boxs do
				local box = boxs[i]
				local organ = box[6] and organs[box[6]][box[7]]
				if mode == 2 and box[6] and organ then
					hg.organism.DrawOrganShape(box, solidColor(organ), true)
				end
				hg.organism.DrawOrganShape(box, (organ and organ[6]) or black)
			end

			if mode == 2 then
				local organism = ply.organism
				local bullets = organism and organism.bullets
				if istable(bullets) then
					for bi = 1, #bullets do
						local entry = bullets[bi]
						if istable(entry) and isstring(entry.bone) and isvector(entry.lpos) then
							local b = ply:LookupBone(entry.bone)
							if b then
								local bp, ba = ply:GetBonePosition(b)
								if bp then
									render.DrawWireframeSphere(LocalToWorld(entry.lpos, angZero, bp, ba), entry.frag and 0.35 or 0.6, 8, 8, entry.frag and grey or black)
								end
							end
						end
					end
				end
			end
		end
	end
end)