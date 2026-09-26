-- ============================================================
--  ZC BEARTRAP SNARE - trap pins the leg instead of taking it
-- ------------------------------------------------------------
--  Pat's Bear Trap stock behavior: snap -> hg.organism.AmputateLimb
--  (leg gone) + light stun. Joey's redesign:
--
--    * NO amputation. Heavy slash damage to the trapped leg
--      instead (wounds the organism -> natural homigrad bleeding).
--      Damage is CAPPED below the gamemode's 100-per-hitgroup
--      amputation stack threshold, so the trap alone can never
--      take the limb.
--    * The victim is knocked down (stock light stun) and their
--      leg is BALLSOCKETED to the trap - registered in the
--      ragdoll's Nails table, so the HAMMER-NAIL "Should Fake Up"
--      machinery keeps them pinned: they cannot stand while the
--      trap holds them, and struggling to rise slowly tears them
--      free at the cost of extra slash damage (same rules as
--      being nailed).
--    * Release: anyone ELSE +uses the trap (picks it up ->
--      trap entity removes -> constraint dies -> free). The
--      trapped player cannot pick up the trap holding them.
--      A hammer's nail-pull on the leg also works (rescue path).
--
--  Convars (FCVAR_ARCHIVE):
--    zc_beartrap_snare        1    master toggle (0 = stock amputation behavior)
--    zc_beartrap_snap_damage  35   slash damage per snap (max 90 - amputation threshold is 100)
--    zc_beartrap_struggle     3    struggle budget, hammer-nail units:
--                                  1 =~ 20s of constant struggling to tear free,
--                                  0 = can NEVER tear free (pickup/hammer only)
--    zc_beartrap_holdforce    0    ballsocket force limit (0 = physically unbreakable)
--
--  Runtime override of the workshop entity (no gma edits);
--  serverside = hotloadable live. Quiet no-op if the trap addon
--  is absent. Part of zc_beartrap_rarity.
-- ============================================================
if not SERVER then return end

ZCBTSNARE = ZCBTSNARE or {}

local cv_on       = CreateConVar("zc_beartrap_snare", "1", FCVAR_ARCHIVE,
	"Bear trap pins the leg (1) instead of amputating it (0 = stock behavior)")
local cv_damage   = CreateConVar("zc_beartrap_snap_damage", "35", FCVAR_ARCHIVE,
	"Slash damage dealt to the trapped leg per snap", 0, 90)
local cv_struggle = CreateConVar("zc_beartrap_struggle", "3", FCVAR_ARCHIVE,
	"Struggle budget to tear free (hammer-nail units; 0 = never)", 0, 20)
local cv_force    = CreateConVar("zc_beartrap_holdforce", "0", FCVAR_ARCHIVE,
	"Ballsocket force limit holding the leg (0 = unbreakable)", 0, 50000)

-- ---- local copies of the trap addon's helpers (they are locals there) ----
local function setSequenceSafe(ent, sequenceName)
	local sequence = ent:LookupSequence(sequenceName)
	if sequence and sequence >= 0 then
		ent:SetSequence(sequence)
		ent:SetCycle(0)
		ent:SetPlaybackRate(1)
		ent:ResetSequenceInfo()
	end
end

local function paintBlood(pos, source)
	for _ = 1, 5 do
		local jitter = VectorRand() * 16
		jitter.z = math.abs(jitter.z) + 4
		if util.PaintDown then
			util.PaintDown(pos + jitter, "Blood", source)
		else
			local startPos = pos + jitter
			local tr = util.TraceLine({start = startPos, endpos = startPos - Vector(0, 0, 96), filter = source})
			if tr.Hit then
				util.Decal("Blood", tr.HitPos + tr.HitNormal, tr.HitPos - tr.HitNormal, source)
			end
		end
	end
end

local function getBonePos(ent, boneName)
	if not IsValid(ent) or not boneName then return end
	local bone = ent:LookupBone(boneName)
	if not bone then return end
	local pos = select(1, ent:GetBonePosition(bone))
	if isvector(pos) and not pos:IsZero() then return pos end
	local matrix = ent:GetBoneMatrix(bone)
	if matrix then return matrix:GetTranslation() end
end

local function chooseLimb(ply, trapPos)
	local org = ply.organism
	if not org then return end
	local char = PAT_BEARTRAP.GetCharacterEntity(ply)
	local leftPos = getBonePos(char, "ValveBiped.Bip01_L_Foot") or getBonePos(char, "ValveBiped.Bip01_L_Calf")
	local rightPos = getBonePos(char, "ValveBiped.Bip01_R_Foot") or getBonePos(char, "ValveBiped.Bip01_R_Calf")
	local chosen
	if isvector(leftPos) and isvector(rightPos) then
		chosen = leftPos:DistToSqr(trapPos) <= rightPos:DistToSqr(trapPos) and "lleg" or "rleg"
	else
		local localPos = char:WorldToLocal(trapPos)
		chosen = localPos.y >= 0 and "lleg" or "rleg"
	end
	local other = chosen == "lleg" and "rleg" or "lleg"
	if org[chosen .. "amputated"] and not org[other .. "amputated"] then
		chosen = other
	end
	return chosen
end

local function resolveVictim(ent)
	if not IsValid(ent) then return end
	if ent:IsPlayer() then return ent end
	if ent:IsRagdoll() and hg and hg.RagdollOwner then
		return hg.RagdollOwner(ent)
	end
end

-- ---- the snare: ballsocket the trapped leg to the trap, hammer-nail style ----
local function attachSnare(trap, victim, limb, tries)
	tries = tries or 0
	if tries > 20 then return end -- gave the ragdoll ~3s to exist
	if not IsValid(trap) or not IsValid(victim) or not victim:Alive() then return end

	local rag = victim.FakeRagdoll
	if not IsValid(rag) then
		timer.Simple(0.15, function() attachSnare(trap, victim, limb, tries + 1) end)
		return
	end

	local footName = limb == "lleg" and "ValveBiped.Bip01_L_Foot" or "ValveBiped.Bip01_R_Foot"
	local calfName = limb == "lleg" and "ValveBiped.Bip01_L_Calf" or "ValveBiped.Bip01_R_Calf"
	local bone = rag:LookupBone(footName) or rag:LookupBone(calfName)
	if not bone then return end
	local phys = rag:TranslateBoneToPhysBone(bone)
	if not phys or phys < 0 then return end

	-- one snare per bone; never stack on an existing nail
	rag.Nails = rag.Nails or {}
	if rag.Nails[phys] then return end

	local c = constraint.Ballsocket(rag, trap, phys, 0, Vector(0, 0, 3), cv_force:GetFloat(), 0, 0)
	if not IsValid(c) then return end

	rag.Nails[phys] = {c, cv_struggle:GetFloat(), nil}
	c:CallOnRemove("zc_beartrap_snare_free", function()
		if IsValid(rag) and rag.Nails then rag.Nails[phys] = nil end
		if IsValid(victim) and victim:Alive() and victim.Notify then
			victim:Notify("The bear trap is off your leg.", true, "pat_beartrap_free", 3)
		end
	end)

	trap.SnareVictim = victim
	trap.SnareConstraint = c
end

-- ---- replacement ENT:TriggerVictim (mirrors the stock flow, new player path) ----
local function snareTrigger(self, victimEnt)
	if not cv_on:GetBool() and ZCBTSNARE.origTrigger then
		return ZCBTSNARE.origTrigger(self, victimEnt)
	end

	local victim = resolveVictim(victimEnt)
	local owner = self:GetTrapOwner()

	self.NextTrigger = CurTime() + 0.75
	self.LastVictim = victim
	self.LastVictimUntil = CurTime() + 2.5
	self:CloseTrap()

	setSequenceSafe(self, "Snap")
	self:EmitSound(PAT_BEARTRAP.Sound, 75, 100)

	timer.Simple(0.18, function()
		if IsValid(self) then self:CloseTrap() end
	end)

	-- non-player victims: stock behavior
	if not IsValid(victim) or not victim:IsPlayer() or not victim:Alive() or not victim.organism then
		if IsValid(victimEnt) then
			local dmg = DamageInfo()
			dmg:SetDamage(PAT_BEARTRAP.NPCDamage:GetFloat())
			dmg:SetDamageType(DMG_SLASH)
			dmg:SetAttacker(IsValid(owner) and owner or self)
			dmg:SetInflictor(self)
			victimEnt:TakeDamageInfo(dmg)
			paintBlood(self:GetPos(), victimEnt)
		end
		return
	end

	local limb = chooseLimb(victim, self:GetPos())
	local char = PAT_BEARTRAP.GetCharacterEntity(victim)

	-- heavy leg damage + wounds (organism handles the bleeding), NO amputation
	local footName = limb == "lleg" and "ValveBiped.Bip01_L_Foot" or "ValveBiped.Bip01_R_Foot"
	local dmgPos = getBonePos(char, footName) or self:GetPos()
	local dmg = DamageInfo()
	dmg:SetDamage(cv_damage:GetFloat())
	dmg:SetDamageType(DMG_SLASH)
	dmg:SetAttacker(IsValid(owner) and owner or self)
	dmg:SetInflictor(self)
	dmg:SetDamagePosition(dmgPos)
	dmg:SetDamageForce(Vector(0, 0, 1))
	victim:TakeDamageInfo(dmg)

	if victim.Notify then
		victim:Notify("The bear trap snapped shut on your leg! Someone has to pull it off you.", 1, "pat_beartrap", 1, nil, Color(255, 70, 70))
	end

	-- knock them down (stock stun), then pin the leg once the ragdoll exists
	timer.Simple(0, function()
		if IsValid(victim) and hg and hg.LightStunPlayer then
			hg.LightStunPlayer(victim, PAT_BEARTRAP.StunTime:GetFloat())
		end
	end)

	-- only snare a leg that is actually still there
	if limb and not victim.organism[limb .. "amputated"] then
		timer.Simple(0.25, function() attachSnare(self, victim, limb) end)
	end

	paintBlood(self:GetPos(), char)
end

-- ---- replacement ENT:Use - the trapped player can't take the trap off themselves ----
local function snareUse(self, act)
	if IsValid(self.SnareConstraint) and act == self.SnareVictim then
		if act.Notify then
			act:Notify("You can't reach the release - someone else has to pull the trap off.", 1, "pat_beartrap_stuck", 1, nil, Color(255, 170, 70))
		end
		return
	end
	if ZCBTSNARE.origUse then return ZCBTSNARE.origUse(self, act) end
end

-- ---- runtime patch of the workshop entity (class table + live instances) ----
local function patchInstances()
	for _, e in ipairs(ents.FindByClass("ent_pat_beartrap")) do
		e.TriggerVictim = snareTrigger
		e.Use = snareUse
	end
end

local function patch()
	local stored = scripted_ents.GetStored("ent_pat_beartrap")
	local tbl = stored and stored.t
	if not tbl or not tbl.TriggerVictim then return false end
	ZCBTSNARE.origTrigger = ZCBTSNARE.origTrigger or tbl.TriggerVictim
	ZCBTSNARE.origUse = ZCBTSNARE.origUse or tbl.Use
	tbl.TriggerVictim = snareTrigger
	tbl.Use = snareUse
	patchInstances()
	ZCBTSNARE.active = true
	print("[Beartrap Snare] armed - traps now pin the leg (zc_beartrap_snare 0 reverts to stock)")
	return true
end

-- catch traps spawned any way at any time (belt and braces vs table-copy semantics)
hook.Add("OnEntityCreated", "zc_beartrap_snare_new", function(e)
	timer.Simple(0, function()
		if ZCBTSNARE.active and IsValid(e) and e:GetClass() == "ent_pat_beartrap" then
			e.TriggerVictim = snareTrigger
			e.Use = snareUse
		end
	end)
end)

-- patch now (hotload) and keep retrying briefly (fresh boot / late workshop mount)
local function startPatch()
	if patch() then return end
	local tries = 0
	timer.Create("zc_beartrap_snare_patch", 2, 15, function()
		tries = tries + 1
		if patch() or tries >= 15 then
			timer.Remove("zc_beartrap_snare_patch")
		end
	end)
end

hook.Add("InitPostEntity", "zc_beartrap_snare_boot", startPatch)
startPatch()
