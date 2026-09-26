-- Headshot / organ gore chunks were rendering with the watermelon model's own
-- material (models/props_junk/fruit_objects01 - a green rind sheet) instead of
-- models/flesh.
--
-- zcity's SpawnMeatGore (lua/homigrad/headgib/init_sv.lua:86) sets the material
-- override BEFORE ents.Create'd prop is spawned, and calls Activate() before
-- Spawn(). The material override is networked entity state, so writing it to an
-- unspawned entity is not guaranteed to reach clients; when it is dropped the
-- chunk draws as green melon rind.
--
-- This replaces the global in place: same chunk count, scale, velocity,
-- collision group, cleanup and impact callback, but the entity is spawned
-- first and the material is applied afterwards, through SetMaterial (whole
-- model) as well as SetSubMaterial(0) so a single dropped write cannot put the
-- rind back on screen.
--
-- zc_gore_meatmat 0 + map change restores the stock function.

if not SERVER then return end

local VERSION = "20260922.1"
if ZCGoreMeatMat and ZCGoreMeatMat.Version == VERSION then return end

ZCGoreMeatMat = ZCGoreMeatMat or {}
local M = ZCGoreMeatMat
M.Version = VERSION
M.stats = M.stats or {chunks = 0, failed = 0, installs = 0}

local enabled = CreateConVar("zc_gore_meatmat", "1", FCVAR_ARCHIVE,
	"Apply the flesh material to gore chunks after they spawn", 0, 1)

local MAT = "models/flesh"
local MODELS = {Model("models/props_junk/watermelon01_chunk02a.mdl")}
local REMOVE_TIME = 60
local gamemod = engine.ActiveGamemode()

local squish = {
	Sound("physics/flesh/flesh_squishy_impact_hard1.wav"),
	Sound("physics/flesh/flesh_squishy_impact_hard2.wav"),
	Sound("physics/flesh/flesh_squishy_impact_hard3.wav"),
	Sound("physics/flesh/flesh_squishy_impact_hard4.wav")
}

-- Same impact behaviour as the stock local PhysCallback: one squish plus a
-- blood decal, and only for collisions that are not the settling chatter.
local function PhysCallback(ent, data)
	if data.DeltaTime < 0.2 then return end
	ent:EmitSound(squish[math.random(#squish)])
	util.Decal("Normal.Blood24", data.HitPos - data.HitNormal, data.HitPos + data.HitNormal, ent)
end

local function applyMaterial(ent)
	ent:SetMaterial(MAT)
	ent:SetSubMaterial(0, MAT)
end

M.ApplyMaterial = applyMaterial

function M.Spawn(mainent, pos, count, force, scale)
	force = force or vector_origin
	local base = IsValid(mainent) and mainent:GetVelocity() or vector_origin

	for _ = 1, (count or math.random(8, 10)) do
		local ent = ents.Create("prop_physics")

		if not IsValid(ent) then
			M.stats.failed = M.stats.failed + 1
			return
		end

		ent:SetModel(MODELS[math.random(#MODELS)])
		ent:SetPos(pos)
		ent:SetAngles(AngleRand(-180, 180))
		ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
		ent:SetModelScale(math.Rand(0.8, 1.1) * (scale or 1))
		ent:Spawn()
		ent:Activate()

		-- After Spawn: the entity is networked, so the override reaches clients.
		applyMaterial(ent)

		M.stats.chunks = M.stats.chunks + 1

		local phys = ent:GetPhysicsObject()

		if IsValid(phys) then
			phys:SetVelocity(base + VectorRand(-65, 65) + force / 10)
			phys:AddAngleVelocity(VectorRand(-65, 65))
		end

		if zb and zb.CROUND and zb.CROUND ~= "hmcd" or gamemod == "sandbox" then
			ent:DrawShadow(false)
			ent:SetModelScale(0, REMOVE_TIME)
			SafeRemoveEntityDelayed(ent, REMOVE_TIME)
		end

		ent:AddCallback("PhysicsCollide", PhysCallback)
	end
end

function M.Wrapper(mainent, pos, count, force, scale)
	if not enabled:GetBool() and M.Stock then
		return M.Stock(mainent, pos, count, force, scale)
	end

	return M.Spawn(mainent, pos, count, force, scale)
end

-- lua/autorun/server runs before the gamemode includes headgib/init_sv.lua, so
-- the stock global is reinstalled after this file. Claim it again once the
-- gamemode is up; on an autorefresh reload the gamemode is already loaded and
-- the immediate call below is the one that takes.
-- Every wrapper this file has ever installed, so a hot reload never adopts a
-- previous wrapper as "stock" and chains the override into itself.
M.marks = M.marks or setmetatable({}, {__mode = "k"})
M.marks[M.Wrapper] = true

function M.Install()
	local current = SpawnMeatGore

	if current == M.Wrapper then return false end
	if isfunction(current) and not M.marks[current] then M.Stock = current end

	SpawnMeatGore = M.Wrapper
	M.stats.installs = M.stats.installs + 1

	return true
end

M.Install()
hook.Add("InitPostEntity", "ZCGoreMeatMat.Install", M.Install)
hook.Add("PostGamemodeLoaded", "ZCGoreMeatMat.Install", M.Install)
-- headgib/init_sv.lua reassigns the global whenever it is autorefreshed, which
-- happens during live tuning. Without a self-heal the melon rind comes back
-- silently, so re-claim it for a while after every boot or reload.
timer.Create("ZCGoreMeatMat.Install", 1, 30, M.Install)

concommand.Add("zc_gore_meatmat_status", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	local line = string.format("[zc_gore_meatmat] %s enabled=%s installed=%s chunks=%d failed=%d installs=%d",
		VERSION, tostring(enabled:GetBool()), tostring(SpawnMeatGore == M.Wrapper),
		M.stats.chunks, M.stats.failed, M.stats.installs)

	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end, nil, "Superadmin: print the gore meat-material fix status.")
