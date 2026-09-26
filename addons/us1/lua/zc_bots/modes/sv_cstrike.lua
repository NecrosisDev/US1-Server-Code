-- Cstrike mode profile + bomb logic for the US1 "cstrike" round
-- (folder gamemodes/zcity/gamemode/modes/tdm_cstrike, MODE.name = "cstrike",
-- MODE.base = "tdm"). Server-only, safe to re-run under Lua autorefresh.
--
-- UNVERIFIED (needs owner confirmation):
--   * Whether Player:PickupObject (stock GMod, called from the bomb's own
--     ENT:Use, entities/bomb/init.lua:145) behaves correctly for a bot
--     (ply:IsBot() == true) the same way it does for a human player -- this
--     package never traced PickupObject's own implementation, and nothing
--     else in zc_bots drives it. If a bot cannot actually carry the bomb
--     this way, mode.cstrike_bomb's plant path will path bots toward the
--     bomb forever without ever picking it up.
--   * Whether a PickupObject-held prop reliably tracks a bot's position as
--     it walks (assumed by analogy with human play; not confirmed against
--     GMod's implementation or this codebase).
--   * There is no source precedent for a non-human entity acquiring bomb
--     carry state outside the "bomb_enter"/ENT:Use net flow, so the
--     "become carrier" step below (calling bomb:Use(bot) when unheld) is a
--     bridge this file adds, not a function the brief named. It calls only
--     verified entity methods (ENT:Use, ENT:ActivateBomb, ENT:DisableBomb),
--     but the bridge concept itself is unverified.
--
-- VERIFIED against the US1 reference tree:
--   * modes/tdm_cstrike/sh_cstrike.lua:3-6 -- MODE.base = "tdm",
--     MODE.name = "cstrike"; loader.lua:59 (local name = MODE.name) means
--     zb.modes["cstrike"] is the registry key regardless of the tdm_cstrike
--     folder name, and zb.CROUND_MAIN resolves to that same string. No alias
--     is needed in RegisterModeProfile.
--   * loader.lua:62-73 -- table.Inherit(MODE, zb.modes[MODE.base]) copies
--     tdm's BuyItems/buymenu/BuyTime onto cstrike, so
--     hg.botdriver.TDMBotBuy (sv_tdm.lua, this package) applies unchanged --
--     duplicating it here would drift from the real catalogue for no
--     benefit, so this file reuses it directly (behaviour choice).
--   * modes/tdm_cstrike/sv_cstrike.lua:107-118 -- zb.bomb is the live bomb
--     entity, spawned team-0-side in MODE:Intermission() only when
--     zb.rtype == "bomb"; zb.rtype == "hostage" spawns a hostage prop
--     instead and never sets zb.bomb, so bomb logic is naturally inert on
--     hostage rounds even without an explicit check (the brief also asks to
--     skip bomb logic outright on hostage rounds, and CanRun below does).
--   * lua/entities/bomb/init.lua:29-43 -- global BombInSite(pos, site):
--     site 1 = zone "BOMB_ZONE_A", site 2 = "BOMB_ZONE_B"; AABB from
--     zb.GetMapPoints(group)[1].pos / [2].pos (verified .pos field, see
--     sv_tdm.lua's citation of the same accessor).
--   * init.lua:91-130 ENT:ActivateBomb() -- the plant function; takes no
--     arguments, arms the timer and immobilizes the prop. The net.Receive
--     handler (init.lua:61) gates this call on
--     `isSandbox or BombInSite(ent:GetPos(),1) or BombInSite(ent:GetPos(),2)`
--     before calling it -- this file performs the same zone gate itself
--     since it calls ActivateBomb() directly, not through that handler.
--   * init.lua:77-87 ENT:DisableBomb() -- the defuse function; takes no
--     arguments, clears the timer and re-enables motion. The net handler
--     applies no distance/dwell gate of its own (only requires
--     ply.bomb == ent, itself gated behind ENT:Use's pickup flow) -- the
--     70-unit/6s-still/abort-on-damage rule below is the bot-AI substitute
--     for a player having to walk up and interact, per the porting brief.
--   * init.lua:132-152 ENT:Use(activator) -- what a human pressing E on the
--     bomb triggers: PickupObject, self.user/activator.bomb bookkeeping,
--     and a "bomb_look" net message (UI-only, harmless to skip for a bot).
--   * zb.rtype ("bomb"/"hostage") set in sv_cstrike.lua:65-84 Intermission().
--   * Team ids 0 = Terrorist, 1 = Counter-Terrorist, inherited from tdm
--     (same citation as sv_tdm.lua).

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

----------------------------------------------------------------------
-- Buy: cstrike inherits tdm's BuyItems catalogue wholesale (verified above),
-- so this reuses hg.botdriver.TDMBotBuy from sv_tdm.lua rather than
-- duplicating the buy-item/category logic (behaviour choice, logged).
----------------------------------------------------------------------

local pendingBuy = {}

hook.Add("ZB_StartRound", "zc_bots_cstrike_schedule_buys", function()
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	if roundKey ~= "cstrike" then return end

	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:IsBot() and ply.zcBot and ply:Alive() then
			local team = hg.botdriver.TeamOf(ply)
			if team == 0 or team == 1 then
				pendingBuy[ply] = CurTime() + math.Rand(0.5, 3)
			end
		end
	end
end)

hg.botdriver.Every("cstrike_buy_tick", 0.5, function()
	if not hg.botdriver.Enabled() then return end
	if not hg.botdriver.TDMBotBuy then return end -- sv_tdm.lua not loaded (standalone safety)
	local now = CurTime()
	for bot, due in pairs(pendingBuy) do
		if not IsValid(bot) or not bot:Alive() then
			pendingBuy[bot] = nil
		elseif now >= due then
			pendingBuy[bot] = nil
			hg.botdriver.TDMBotBuy(bot)
		end
	end
end)

----------------------------------------------------------------------
-- Bomb (MODE band). zb.rtype == "hostage" -> CanRun refuses outright and
-- bots just fight normally, per brief.
----------------------------------------------------------------------

local PLANT_DWELL = 4
local DEFUSE_DWELL = 6
local DEFUSE_RANGE = 70
local DEFUSE_RANGE_SQR = DEFUSE_RANGE * DEFUSE_RANGE
-- PROVISIONAL(2026-09-21, no engine/UI concept of "pickup range" exists for
-- a direct ENT:Use() call -- +use is normally range-gated by the engine
-- before the net message ever fires. This is a bot-authored substitute,
-- ratify-by: 2026-10-15)
local BOMB_PICKUP_RANGE_SQR = 80 * 80

hg.botdriver.DeclareBrainState("mode.cstrike_bomb", { fields = { "csPlantSince", "csDefuseSince" } })

local function bombCarrier(bomb)
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply.bomb == bomb then return ply end
	end
	return nil
end

RB({
	name = "mode.cstrike_bomb",
	band = "MODE",
	order = 5,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "cstrike" then return false end
		if zb.rtype ~= "bomb" then return false end -- hostage rounds: fight normally (brief)
		if not IsValid(zb.bomb) then return false end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		local team = hg.botdriver.TeamOf(ctx.bot)
		return team == 0 or team == 1
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local bomb = zb.bomb
		local team = hg.botdriver.TeamOf(bot)

		----------------------------------------------------------------
		-- Defuse: CT within DEFUSE_RANGE of an armed bomb, standing still
		-- for DEFUSE_DWELL seconds; abort (reset the dwell) if damaged
		-- during the window.
		----------------------------------------------------------------
		if team == 1 and bomb.active then
			if bot:GetPos():DistToSqr(bomb:GetPos()) <= DEFUSE_RANGE_SQR then
				if not brain.csDefuseSince or (brain.damageAt or 0) > brain.csDefuseSince then
					brain.csDefuseSince = now
				end
				brain.actionPolicy = { owner = "cstrike:defuse", lockMove = true }
				hg.botdriver.lib.LookAt(bot, brain, bomb:GetPos(), "cstrike:defuse", true)
				if now - brain.csDefuseSince >= DEFUSE_DWELL then
					bomb:DisableBomb()
					brain.csDefuseSince = nil
				end
				return true
			end
			brain.csDefuseSince = nil
			hg.botdriver.lib.PathTo(bot, brain, bomb:GetPos(), now, 1)
			return true
		end

		----------------------------------------------------------------
		-- Plant: T only, bomb not yet active.
		----------------------------------------------------------------
		if team == 0 and not bomb.active then
			local carrier = bombCarrier(bomb)

			if carrier == bot then
				local onSite = isfunction(BombInSite)
					and (BombInSite(bomb:GetPos(), 1) or BombInSite(bomb:GetPos(), 2))
				if onSite then
					if not brain.csPlantSince then brain.csPlantSince = now end
					brain.actionPolicy = { owner = "cstrike:plant", lockMove = true }
					if now - brain.csPlantSince >= PLANT_DWELL then
						bomb:ActivateBomb()
						brain.csPlantSince = nil
					end
					return true
				end

				brain.csPlantSince = nil
				local ptsA = zb.GetMapPoints("BOMB_ZONE_A")
				local pts = (istable(ptsA) and #ptsA > 0) and ptsA or zb.GetMapPoints("BOMB_ZONE_B")
				local point = istable(pts) and pts[1]
				if istable(point) and isvector(point.pos) then
					hg.botdriver.lib.PathTo(bot, brain, point.pos, now, 1)
					return true
				end
				return false
			end

			if not IsValid(carrier) then
				if bot:GetPos():DistToSqr(bomb:GetPos()) <= BOMB_PICKUP_RANGE_SQR then
					brain.path = nil
					if isfunction(bomb.Use) then bomb:Use(bot) end
					return true
				end
				hg.botdriver.lib.PathTo(bot, brain, bomb:GetPos(), now, 1)
				return true
			end
		end

		return false
	end,
})

----------------------------------------------------------------------
-- Item B5 (hold logic): post-plant T hold near the bomb watching approaches,
-- pre-plant CT spread between sites. Order 8: runs only when
-- mode.cstrike_bomb (order 5) declined the tick -- i.e. not the carrier/
-- planter/defuser and no direct target (mode.cstrike_bomb's own CanRun
-- already requires IsValid(ctx:AcquireTarget()) == false, so this behavior
-- inherits that same "nothing to fight right now" gate implicitly by running
-- after it in the same band).
--
-- PROVISIONAL(2026-09-21, "bomb site entrance" has no verified map-point
-- group of its own on US1 -- BOMB_ZONE_A/B (init.lua:29-43, cited above) are
-- the zone volumes themselves, not an entrance point. The hold spot is
-- therefore lib.FindCover relative to the bomb's own position (post-plant)
-- or the nearest CT contact when one is known, not a dedicated entrance
-- point, ratify-by: 2026-10-15)
----------------------------------------------------------------------

local HOLD_RANGE = 600
local SITE_GROUPS = { "BOMB_ZONE_A", "BOMB_ZONE_B" }

hg.botdriver.DeclareBrainState("mode.cstrike_hold", { fields = { "csHoldAt", "csHoldPos", "csSpreadSite" } })

-- lib.FindCover needs a threat ENTITY (it traces LOS from its eyes), so this
-- returns the contact entity squad.FreshestContact already tracks, not just
-- its last-known position (squad.FreshestContact's own return shape is
-- `pos, ent, time` -- sv_squad.lua's FreshestContact).
local function nearestCTContactEnt(bot)
	local squad = hg.botdriver.squad
	if not squad or not squad.FreshestContact then return nil end
	local _pos, ent = squad.FreshestContact(bot)
	return IsValid(ent) and ent or nil
end

RB({
	name = "mode.cstrike_hold",
	band = "MODE",
	order = 8,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx.roundKey ~= "cstrike" then return false end
		if zb.rtype ~= "bomb" then return false end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		local team = hg.botdriver.TeamOf(ctx.bot)
		return team == 0 or team == 1
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local bomb = zb.bomb
		local team = hg.botdriver.TeamOf(bot)

		-- T, bomb already planted: hold within HOLD_RANGE watching approaches.
		if team == 0 and IsValid(bomb) and bomb.active then
			local anchor = nearestCTContactEnt(bot) or bomb
			if now >= (brain.csHoldAt or 0) then
				-- PERSONALITY: patience biases the re-scan cadence, not the
				-- decision itself -- a patient bot commits to a hold spot longer
				-- before re-rolling it.
				local patience = (brain.personality and brain.personality.patience) or 1
				brain.csHoldAt = now + 1.5 * patience
				brain.csHoldPos = lib.KeepCover and lib.KeepCover(bot, brain, "cs_hold", anchor, HOLD_RANGE) or nil
			end
			if isvector(brain.csHoldPos) then
				hg.botdriver.SetObjective(bot, brain.csHoldPos, 96, 4, "soft", "cstrike_hold")
				hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
				return true
			end
			return false
		end

		-- CT, pre-plant: spread between the two bomb sites instead of stacking
		-- one entrance. Assigned once per bot-life, alternating by EntIndex.
		if team == 1 and (not IsValid(bomb) or not bomb.active) then
			local group = brain.csSpreadSite or SITE_GROUPS[(bot:EntIndex() % 2) + 1]
			brain.csSpreadSite = group
			local points = zb.GetMapPoints(group)
			if istable(points) and #points > 0 then
				local point = points[math.random(#points)]
				if istable(point) and isvector(point.pos) then
					hg.botdriver.SetObjective(bot, point.pos, 128, 5, "soft", "cstrike_spread")
					hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
					return true
				end
			end
		end

		return false
	end,
})

----------------------------------------------------------------------
-- Mode profile: mode key is "cstrike" (verified, see header); no alias
-- needed. Reuses sv_tdm.lua's squad-push behavior (mode-agnostic).
----------------------------------------------------------------------

hg.botdriver.RegisterModeProfile("cstrike", {
	behaviors = { "mode.tdm_squad_push", "mode.cstrike_bomb", "mode.cstrike_hold" },
})
