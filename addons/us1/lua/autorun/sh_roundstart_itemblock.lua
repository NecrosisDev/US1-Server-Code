-- Round-start grace: blocks all item/weapon usage for the first few
-- seconds of every round (attack inputs stripped - guns, meds,
-- grenades, melee all route through them).
--
-- v2: anchors its own timestamp on ZB_StartRound instead of trusting
-- zb.ROUND_START (which is stamped earlier in the round lifecycle, so
-- the old grace window expired before anyone could even move).
-- Networked via SetGlobalFloat so client prediction agrees.

local GRACE = 10     -- from ZB_StartRound: ~2s pre-play gap + 8 felt
local GRACE_PRE = 18 -- from ZB_PreRoundStart: intermission + gap + 8 felt

-- per-mode window adjustments (seconds, applied to the final stamp)
local MODE_ADJUST = {
	["tdm"] = -4,
}
                 -- equip/spawn dead time, so the felt block is ~5s of
                 -- actual play

if SERVER then
	-- cover stamp BEFORE the round opens: ZB_StartRound arrives ~2s
-- after players can act, and a quick-switched grenade beats it.
-- PreRoundStart lays a wide blanket; StartRound tightens the tail.
-- both stamps aim at the SAME ~8 felt seconds from their own
-- vantage point, so whichever fires last (zcity's order proved
-- unreliable) produces the same window
hook.Add("ZB_PreRoundStart", "RoundStart_ItemBlock_PreStamp", function()
	SetGlobalFloat("RS_GraceUntil", CurTime() + GRACE_PRE)
end)

hook.Add("ZB_StartRound", "RoundStart_ItemBlock_Stamp", function()
		SetGlobalFloat("RS_GraceUntil", CurTime() + GRACE)
		-- authoritative mode-adjusted stamp a beat later: wins over
		-- any late-firing PreRoundStart blanket, and CROUND is
		-- reliably the new round by now
		timer.Simple(0.3, function()
			local adj = MODE_ADJUST[zb.CROUND or ""] or 0
			SetGlobalFloat("RS_GraceUntil", CurTime() + GRACE - 0.3 + adj)
		end)
	end)
end

-- medical items stay usable during grace - only violence waits
-- every throwable weapon class on the server (from the live
-- weapons.GetList dump) - smokes and flashes included: a flashbang
-- opener is as much a round-start grief as a frag
GRENADE_WEPS = {
	["weapon_hg_eihandgranat_tpik"] = true,
	["weapon_hg_f1_tpik"] = true,
	["weapon_hg_flashbang_tpik"] = true,
	["weapon_hg_gebalteladung_tpik"] = true,
	["weapon_hg_grenade_tpik"] = true,
	["weapon_hg_hl2nade_tpik"] = true,
	["weapon_hg_m18_tpik"] = true,
	["weapon_hg_mk2_tpik"] = true,
	["weapon_hg_molotov_tpik"] = true,
	["weapon_hg_nebelgranate_tpik"] = true,
	["weapon_hg_pipebomb_tpik"] = true,
	["weapon_hg_rgd_tpik"] = true,
	["weapon_hg_rudg1_tpik"] = true,
	["weapon_hg_smokenade_tpik"] = true,
	["weapon_hg_stilya_tpik"] = true,
	["weapon_hg_type59_tpik"] = true,
	["weapon_handmadegrn"] = true,
}

-- verified GMod IN_ enums only, nil-filtered at load
STRIP_KEYS = {}
for _, k in ipairs({ IN_ATTACK, IN_ATTACK2, IN_RELOAD, IN_ZOOM }) do
	if isnumber(k) then STRIP_KEYS[#STRIP_KEYS + 1] = k end
end

local MEDICAL = {
	"bandage", "medkit", "tourniquet", "splint", "fent", "morphine",
	"hemostat", "bloodbag", "pills", "syringe", "medical", "medicine",
	"defib", "adrenaline",
}

local function IsMedical(wep)
	if not IsValid(wep) then return false end
	local cls = wep:GetClass():lower()
	for _, pat in ipairs(MEDICAL) do
		if cls:find(pat, 1, true) then return true end
	end
	return false
end

hook.Add("StartCommand", "RoundStart_ItemBlock", function(ply, cmd)
	local untilT = GetGlobalFloat("RS_GraceUntil", 0)
	if untilT <= 0 or CurTime() >= untilT then return end
	if not ply:Alive() then return end

	-- holding a medical item: hands free (heal away)
	local wep = ply:GetActiveWeapon()
	if IsMedical(wep) then return end

	-- strip every non-movement action. Only enums verified to exist
	-- in GMod; the loop skips anything nil so a bad name can never
	-- error the hook again.
	for _, k in ipairs(STRIP_KEYS) do
		cmd:RemoveKey(k)
	end
end)

-- THE grenade fix: every tpik grenade's throw funnels through its
-- SWEP:Throw method server-side (anim callbacks call it; input path
-- is irrelevant). Wrap it on every registered grenade class: during
-- grace the throw is simply refused - pin stays conceptual, nothing
-- spawns. Derived classes copy the base's Throw at registration, so
-- each class table gets wrapped individually.
if SERVER then
	local gatedCount = 0

	local function GateInstance(ent)
		if not IsValid(ent) then return end
		if not GRENADE_WEPS[ent:GetClass()] then return end
		if ent.RS_ThrowGated then return end
		local orig = ent.Throw
		if not orig then return end
		ent.RS_ThrowGated = true
		ent.Throw = function(self, ...)
			local untilT = GetGlobalFloat("RS_GraceUntil", 0)
			if untilT > 0 and CurTime() < untilT then
				print("[ItemBlock] refused grace-period throw: " .. self:GetClass())
				return
			end
			return orig(self, ...)
		end
		gatedCount = gatedCount + 1
	end

	-- every grenade weapon gets gated the moment it exists
	hook.Add("OnEntityCreated", "RoundStart_GateThrow", function(ent)
		timer.Simple(0, function() GateInstance(ent) end)
	end)

	-- and everything already in the world right now
	timer.Simple(1, function()
		for cls in pairs(GRENADE_WEPS) do
			for _, ent in ipairs(ents.FindByClass(cls)) do
				GateInstance(ent)
			end
		end
		print("[ItemBlock] throw gate armed (" .. gatedCount .. " live grenades gated)")
	end)

	-- diagnostic: rs_graceinfo prints grace state + gate census
	concommand.Add("rs_graceinfo", function(ply)
		if IsValid(ply) and not ply:IsAdmin() then return end
		local untilT = GetGlobalFloat("RS_GraceUntil", 0)
		local left = untilT - CurTime()
		print(string.format("[ItemBlock] grace %s (%.1fs left) | grenades gated: %d",
			left > 0 and "ACTIVE" or "inactive", math.max(0, left), gatedCount))
	end, nil, "Admin: print the round-start item grace state.")
end

-- backstop: any grenade projectile born during grace is unmade -
-- catches intermission-cooked releases, quickthrow binds, and any
-- input path the key strip can't see
if SERVER then
	hook.Add("OnEntityCreated", "RoundStart_NadeBackstop", function(ent)
		local untilT = GetGlobalFloat("RS_GraceUntil", 0)
		if untilT <= 0 or CurTime() >= untilT then return end
		timer.Simple(0, function()
			if not IsValid(ent) then return end
			local cls = ent:GetClass()
			-- ent_hg_grenade_* covers every fuse type (rgd5, f1, mk2,
			-- flash, smokes, pipebomb, impact...); molotov, smokenade
			-- and the generic throwable ride separately
			if ent.ishggrenade
				or cls:sub(1, 14) == "ent_hg_grenade"
				or cls == "ent_hg_molotov"
				or cls == "ent_hg_smokenade"
				or cls == "ent_throwable" then
				-- neuter first (in case anything delays the removal),
				-- then unmake
				ent.Explode = function() end
				ent.Arm = function() end
				ent:Remove()
				print("[ItemBlock] unmade a grace-period " .. cls)
			end
		end)
	end)
end


-- ======================= CLIENT =======================
if CLIENT then
	surface.CreateFont("Grace_Text", {
		font = "Bahnschrift", size = 22, weight = 700, antialias = true,
	})

	hook.Add("HUDPaint", "RoundStart_GraceHUD", function()
		local untilT = GetGlobalFloat("RS_GraceUntil", 0)
		local left = untilT - CurTime()
		if left <= 0 then return end

		local ply = LocalPlayer()
		if not IsValid(ply) or not ply:Alive() then return end

		-- gentle pulse; countdown in the final seconds
		local a = 200 + math.sin(CurTime() * 3) * 55
		local txt = "GRACE PERIOD ACTIVE"
		if left <= 5 then
			txt = txt .. "  (" .. math.ceil(left) .. ")"
		end

		draw.SimpleText(txt, "Grace_Text", ScrW() / 2 + 1, ScrH() - 119,
			Color(0, 0, 0, a * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(txt, "Grace_Text", ScrW() / 2, ScrH() - 120,
			Color(140, 255, 140, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end)
end
