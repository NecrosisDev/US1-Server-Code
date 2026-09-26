-- !respawn: unbind the target from their old body, then place them at the
-- respawner's camera.
--
-- Bug. zcity's COMMANDS.respawn (gamemodes/zcity/gamemode/libraries/sv_admin_tools.lua:33)
-- is a bare ply:Spawn(). Every writer of ply.FakeRagdoll / hg.ragdollFake lives in
-- homigrad/fake/sv_tier_0.lua and fires on death (PostPlayerDeath "Garbage", :472),
-- on the ragdoll's own removal (RemoveRag, :486), inside hg.FakeUp (:775/:862/:876),
-- or on disconnect (:904). None of them sits on a plain Spawn() path. So respawning
-- a LIVING fake-ragdolled player -- a crawler -- leaves both registries pointing at
-- the old body, and fake/sv_control.lua's Think "Fake" keeps calling
-- hg.SetFreemove(ply, false) (MOVETYPE_NOCLIP + a 1-unit hull, sv_tier_0.lua:651)
-- and ply:SetPos(head bone) (sv_control.lua:296) every tick: the player is welded
-- over their own corpse and cannot move.
--
-- The medical half of the crawler state already clears itself on every real spawn,
-- by two independent mechanisms: ZCGoreTorsoReset.Reset (sv_zc_gore_torsoreset.lua:50)
-- clears ZCityTorsoSevered and the __zcGore* fields, and hg.organism.Clear -- hook
-- "Player Spawn" "homigrad-organism" (organism/tier_0/sv_tier_0.lua:29) -- clears
-- torsoamputated / llegamputated / rlegamputated. So this file adds only the
-- fake-body unbind and the placement.
--
-- Seam. COMMANDS is a plain global (homigrad/sv_commands.lua:1) dispatched from
-- COMMAND_Input via hook "HG_PlayerSay" (:68/:78). Addons already mutate it from
-- outside the gamemode (zc_solidmapvote/lua/solidmapvote/core/server/sv_hooks.lua:54),
-- so this replaces the one entry in place instead of editing the mounted gamemode.

if not SERVER then return end

local VERSION = "20260922.1"

ZCRespawnAtCamera = ZCRespawnAtCamera or {}
local M = ZCRespawnAtCamera
M.Version = VERSION
M.stats = M.stats or {installs = 0, respawns = 0, unbound = 0, noSpot = 0}

local STAND_MINS = Vector(-16, -16, 0)
local STAND_MAXS = Vector(16, 16, 72)

-- Candidate offsets around the camera: the camera itself first, then widening rings
-- so several targets in one !respawn do not spawn inside one another.
local RING = {Vector(0, 0, 0)}

for r = 1, 3 do
	for a = 0, 5 do
		local ang = math.rad(a * 60 + r * 23)
		RING[#RING + 1] = Vector(math.cos(ang) * r * 40, math.sin(ang) * r * 40, 0)
	end
end

-- Only snap down to a floor that is within one player height of the camera, i.e. the
-- one the respawner is standing on. A respawner who is flying or spectating high up
-- asked for their CAMERA, not for the ground far below it.
local SNAP_DOWN = 96

-- The respawner is filtered out here: the first thing under their own eye position is
-- their own hull, and tracing to it would find no floor at all.
local function groundUnder(pos, actor)
	local tr = util.TraceLine({
		start = pos,
		endpos = pos - Vector(0, 0, SNAP_DOWN),
		mask = MASK_PLAYERSOLID,
		filter = actor,
	})

	if not tr.Hit or tr.StartSolid then return end

	return tr.HitPos + Vector(0, 0, 2)
end

-- The respawner is NOT filtered out here: they are standing in the very spot this is
-- testing, and dropping a second player into their hull makes the engine shove both
-- of them apart. Filtering only the target lets the ring step aside instead.
local function fits(pos, target)
	return not util.TraceHull({
		start = pos,
		endpos = pos,
		mins = STAND_MINS,
		maxs = STAND_MAXS,
		mask = MASK_PLAYERSOLID,
		filter = target,
	}).Hit
end

-- The respawner's camera. EyePos tracks the view in every state !respawn is used
-- from: on foot, noclipping, spectating, or fake-ragdolled (sv_control.lua:296 keeps
-- the player entity on the ragdoll's head bone).
function M.CameraPos(actor)
	return actor:EyePos()
end

-- Spec: always place the target at the respawner's camera. Stand them on the floor
-- under it when the respawner is standing on one, step aside when the spot is taken,
-- and fall back to the camera position itself when no candidate is clear.
function M.PlaceAtCamera(target, camera, actor)
	for _, off in ipairs(RING) do
		local at = camera + off
		local spot = groundUnder(at, actor) or at

		if fits(spot, target) then
			target:SetPos(spot)
			target:SetVelocity(-target:GetVelocity())

			return true
		end
	end

	M.stats.noSpot = M.stats.noSpot + 1
	target:SetPos(camera)
	target:SetVelocity(-target:GetVelocity())

	return false
end

-- Retire the fake body the way PostPlayerDeath "Garbage" (sv_tier_0.lua:472) and
-- hg.FakeUp's instant branch (:869) do, minus the parts a real Spawn redoes.
function M.UnbindFakeBody(ply)
	local rag = ply.FakeRagdoll

	if not IsValid(rag) then
		rag = hg and hg.ragdollFake and hg.ragdollFake[ply]
	end

	-- Clear the owner links BEFORE removing the body: the ragdoll's CallOnRemove
	-- "Fake" (sv_tier_0.lua:589 -> RemoveRag, :486) kills a LIVING owner whose
	-- FakeRagdoll still points at it.
	ply.FakeRagdoll = nil
	ply.FakeRagdollOld = nil
	ply.OldRagdoll = nil

	if hg and hg.ragdollFake then hg.ragdollFake[ply] = nil end

	ply:SetNWEntity("FakeRagdoll", NULL)
	ply:SetNWEntity("FakeRagdollOld", NULL)
	ply:SetNWEntity("RagdollDeath", NULL)

	ply.fakecd = 0
	ply.lastFake = 0
	ply.lastFakeTime = 0
	ply.jumpedfake = nil
	ply.gottarespawn = nil

	if IsValid(rag) then
		rag.override = true -- second guard: RemoveRag returns early on it
		rag:SetNWEntity("ply", NULL)
		rag:SetNWBool("ZCityTorsoSevered", false)
		rag:Remove()
	end

	-- hg.Fake hid the real body (sv_tier_0.lua:613-622) and hg.SetFreemove(ply,false)
	-- noclipped it with a 1-unit hull. Spawn restores the hull ("Player Spawn"
	-- SetHull, sh_utility.lua:1453) and the collision group ("PlayerSpawn" Fake,
	-- sv_tier_0.lua:420) but not the render mode, world model, shadow or move type.
	ply:SetRenderMode(RENDERMODE_NORMAL)
	ply:DrawWorldModel(true)
	ply:DrawShadow(true)
	ply:SetCollisionGroup(COLLISION_GROUP_PLAYER)
	ply:SetMoveType(MOVETYPE_WALK)

	if ply.oldCanUseFlashlight and not ply:CanUseFlashlight() then
		ply:AllowFlashlight(true)
	end

	-- The crawler's severed lower half is a world prop, not part of the ragdoll.
	local lower = ply.__zcGoreLowerTorso

	if IsValid(lower) and lower:GetNWBool("ZCityTorsoLowerPart", false) then
		lower:Remove()
	end

	ply.__zcGoreLowerTorso = nil

	if IsValid(rag) then
		M.stats.unbound = M.stats.unbound + 1

		return true
	end

	return false
end

function M.Respawn(ply, args)
	if not ply:IsAdmin() then return end

	local plya = #args > 0 and args[1] or ply:Name()
	local camera = M.CameraPos(ply)

	for _, ply2 in pairs(player.GetListByName(plya)) do
		M.UnbindFakeBody(ply2)

		ply2:Spawn()

		if isfunction(ApplyAppearance) then ApplyAppearance(ply2) end

		local hands = ply2:Give("weapon_hands_sh")

		if IsValid(hands) then ply2:SelectWeapon(hands) end

		-- After Spawn: Spawn itself teleports to a map spawn point.
		M.PlaceAtCamera(ply2, camera, ply)
		ply2:SetEyeAngles(Angle(0, ply:EyeAngles().y, 0))

		M.stats.respawns = M.stats.respawns + 1
		ply:ChatPrint(ply2:Name() .. " | Respawned at your camera")
	end
end

-- Load order between lua/autorun/server and the mounted gamemode is not guaranteed,
-- and sv_admin_tools.lua assigns COMMANDS.respawn unconditionally, so claim the entry
-- again after boot the way ZCMakeCrawler.BindReset does.
-- This box has no reachable console and autorefresh cannot be relied on, so the
-- only way to tell loaded-from-disk apart is a receipt the loaded code writes.
local RECEIPT_DIR = "zc_respawn_at_camera"

function M.Receipt(what)
	file.CreateDir(RECEIPT_DIR)
	file.Append(RECEIPT_DIR .. "/loaded.txt",
		os.date("!%Y-%m-%dT%H:%M:%SZ") .. " " .. VERSION .. " " .. what .. "\n")
end

function M.Install()
	if not COMMANDS then return false end
	if COMMANDS.respawn and COMMANDS.respawn[1] == M.Respawn then return false end

	if COMMANDS.respawn then M.Stock = COMMANDS.respawn end

	COMMANDS.respawn = {M.Respawn, 0, "Respawn a player at your camera"}
	M.stats.installs = M.stats.installs + 1
	M.Receipt("installed over " .. (M.Stock and "stock" or "nothing"))

	return true
end

local function installSoon()
	timer.Simple(0, M.Install)
end

M.Install()
hook.Add("HomigradRun", "ZCRespawnAtCamera_Install", installSoon)
hook.Add("InitPostEntity", "ZCRespawnAtCamera_Install", installSoon)
-- OnReloaded is the one that matters after boot: sv_admin_tools.lua reassigns
-- COMMANDS.respawn at file top level, so an autorefresh or gamemode reload that
-- re-includes it silently restores the stock bare-Spawn command once the timer's
-- 30 s window has passed.
hook.Add("OnReloaded", "ZCRespawnAtCamera_Install", installSoon)
timer.Create("ZCRespawnAtCamera_Install", 1, 30, M.Install)

concommand.Add("zc_respawn_at_camera_status", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end

	local installed = COMMANDS and COMMANDS.respawn and COMMANDS.respawn[1] == M.Respawn

	local line = string.format(
		"[zc_respawn_at_camera] %s installed=%s stock=%s installs=%d respawns=%d unbound=%d noSpot=%d",
		VERSION, tostring(installed or false), tostring(M.Stock ~= nil),
		M.stats.installs, M.stats.respawns, M.stats.unbound, M.stats.noSpot)

	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)

concommand.Add("zc_respawn_at_camera_restore", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	if not M.Stock then print("[zc_respawn_at_camera] no stock command captured") return end

	timer.Remove("ZCRespawnAtCamera_Install")
	hook.Remove("HomigradRun", "ZCRespawnAtCamera_Install")
	hook.Remove("InitPostEntity", "ZCRespawnAtCamera_Install")
	hook.Remove("OnReloaded", "ZCRespawnAtCamera_Install")
	COMMANDS.respawn = M.Stock
	print("[zc_respawn_at_camera] restored zcity's own !respawn")
end)

M.Receipt("file loaded")
print("[zc_respawn_at_camera] Loaded " .. VERSION)
