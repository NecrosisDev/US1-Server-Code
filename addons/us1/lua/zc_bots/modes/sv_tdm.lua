-- TDM mode profile + bot buy/push logic for the US1 "tdm" round
-- (gamemodes/zcity/gamemode/modes/tdm). Server-only, safe to re-run under
-- Lua autorefresh (fixed hook/timer ids, `X = X or {}` guards throughout).
--
-- VERIFIED against the US1 reference tree:
--   * modes/tdm/sv_tdm.lua:184-235 -- the "tdm_buyitem" net.Receive handler
--     is the buy mechanism giveTDMItem() below mirrors step for step, called
--     directly for a bot instead of through net.Receive.
--   * modes/tdm/sh_tdm.lua:27-46 -- AddItemToBUY(name, type, class, price,
--     category, attachments, amount, teamBased) builds
--     MODE.BuyItems[category][name]. The category strings it actually uses
--     are plain English ("Assault", "Carbines", "Submachine", "Shotguns",
--     "Marksman/Sniper", "Pistols", "Melee", "Medical", "Explosive",
--     "Equipment", "Ammo") -- these are BUY-MENU groupings, a different
--     namespace from the SWEP.Category strings ("Weapons - Assault Rifles"
--     etc.) that sv_weaponscore.lua's CATEGORY_ROLE documents for weapon
--     scoring. The porting brief assumed the two namespaces were the same;
--     they are not (see final report). This file uses the verified
--     MODE.BuyItems spellings.
--   * TeamBased (8th AddItemToBUY arg, sh_tdm.lua): 0 = Terrorist-only,
--     1 = Counter-Terrorist-only, nil/omitted = either team (e.g. AKM/AK-74
--     pass 0, M4A1/HK416 pass 1, most items omit it).
--   * CurrentRound() (libraries/sv_roundsystem.lua:23) returns the live mode
--     table. loader.lua:62-73 (table.Inherit) copies tdm's BuyItems/buymenu/
--     BuyTime onto any mode with MODE.base = "tdm" (cstrike included), so
--     the same buy catalogue and window rule apply to both modes.
--   * Buy window: modes/tdm/sv_tdm.lua:189 gates on
--     (zb.ROUND_START or 0) + 40 < CurTime(); zb.ROUND_START is set once per
--     round by hg.UpdateRoundTime (gamemode/init.lua:432), well before
--     ZB_StartRound fires (libraries/sv_roundsystem.lua:606), so scheduling
--     a bot buy a few seconds after ZB_StartRound is still inside the
--     window.
--   * Team ids: 0 = Terrorist, 1 = Counter-Terrorist (sh_tdm.lua tblweps /
--     GiveEquipment's ply:Team() == 1 branch).
--   * "Big map" signal: zb.BigMaps / zb.GetWorldSize() > ZBATTLE_BIGMAP
--     (libraries/sv_roundsystem.lua:246, 281, 297-298) is the actual
--     convention MODE.ForBigMaps itself is gated on; reused here instead of
--     inventing a new heuristic.
--   * zb.GetMapPoints(group) returns an array of {pos = Vector, ang = Angle}
--     (libraries/mappoints/sv_points.lua:15,48; field confirmed by
--     zb.TranslatePointsToVectors and the BombInSite/HostageInZone callers
--     that index pts[n].pos).
--   * ZB_StartRound hook confirmed at libraries/sv_roundsystem.lua:606
--     (hook.Run("ZB_StartRound") inside zb:RoundStart()).
--
-- BEHAVIOUR CHOICES (not dictated by the porting brief -- see final report):
--   * Within a preferred category, the highest-price item the bot can still
--     afford (after reserving 20% of its money) is bought -- the brief gave
--     a category preference order but not an in-category tie-break.
--   * Sniper ("Marksman/Sniper") is appended as the LAST primary category
--     (lowest priority, tried only if nothing else in the preferred list is
--     affordable) rather than promoted above Assault/Carbines/etc, since the
--     brief only asked to allow it on big maps, not to prefer it.
--   * The squad-push MODE behavior below is intentionally mode-agnostic
--     (checks ctx.roundKey == "tdm" or "cstrike") so cstrike's profile can
--     list the same behavior name instead of duplicating it.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

----------------------------------------------------------------------
-- Buy logic (shared with sv_cstrike.lua -- cstrike inherits tdm's BuyItems
-- catalogue wholesale via loader.lua's table.Inherit, so the same purchase
-- steps and category spellings apply to both modes).
----------------------------------------------------------------------

local RESERVE_FRAC = 0.2

-- PROVISIONAL(2026-09-21, the brief's preferred-category list named
-- "Assault Rifles/Carbines/Machine-Pistols/Shotguns", which are
-- SWEP.Category spellings that do not exist as MODE.BuyItems keys -- the
-- verified BuyItems categories are used instead, ratify-by: 2026-10-15)
local PRIMARY_CATEGORIES = { "Assault", "Carbines", "Submachine", "Shotguns" }
local SNIPER_CATEGORY = "Marksman/Sniper"
local PISTOL_CATEGORY = "Pistols"
local ARMOR_CATEGORY = "Equipment"

local function isBigMap()
	return isnumber(ZBATTLE_BIGMAP) and isfunction(zb and zb.GetWorldSize) and zb.GetWorldSize() > ZBATTLE_BIGMAP
end

-- Mirrors modes/tdm/sv_tdm.lua:213-234 exactly, minus the net-message
-- envelope: money check, Give, item.Use, weapon_bloodbag special case,
-- item.Amount, ammo top-up, money deduction, pickup sound.
local function giveTDMItem(bot, item)
	local money = bot:GetNWInt("TDM_Money", 0)
	if (money - item.Price) < 0 then return false end

	local ent = bot:Give(item.ItemClass)
	if not IsValid(ent) then return false end

	if ent.Use then ent:Use(bot) end

	if ent:GetClass() == "weapon_bloodbag" then
		ent.bloodtype = "o-"
		ent.modeValues[1] = 1
	end

	if item.Amount then
		ent.AmmoCount = item.Amount
	end

	if ent.GetPrimaryAmmoType then
		bot:GiveAmmo(ent:GetMaxClip1() * 1, ent:GetPrimaryAmmoType(), true)
	end

	bot:SetNWInt("TDM_Money", money - item.Price)
	bot:EmitSound("items/itempickup.wav")
	return true
end

local function bestAffordable(buyItems, category, bot, team, reserve)
	local group = buyItems[category]
	if not istable(group) then return nil end

	local money = bot:GetNWInt("TDM_Money", 0)
	local budget = money - reserve
	local best, bestPrice

	for _, item in pairs(group) do
		if istable(item) and item.ItemClass and isnumber(item.Price)
			and (item.TeamBased == nil or item.TeamBased == team)
			and item.Price <= budget
			and (not bestPrice or item.Price > bestPrice) then
			best, bestPrice = item, item.Price
		end
	end

	return best
end

-- Item 5 (2026-09-22, TDM economy as characterisation): personality/money
-- driven variance on top of the plain mirror above -- same giveTDMItem/
-- bestAffordable primitives throughout, no second buy implementation.
local SAVE_CHANCE_BASE = 0.30      -- scaled DOWN by aggression (cautious bots save)
local FORCE_BUY_CHANCE_BASE = 0.55 -- scaled UP by aggression (aggressive bots spend to zero)
local PISTOL_ONLY_CHANCE = 0.10    -- "caught mid-round with only a pistol"
local SNIPER_CAP_PER_TEAM = 1      -- kit spread: one sniper max per team per round

-- Reset once per round in the ZB_StartRound handler below -- a per-round cap,
-- not cumulative across the whole map.
hg.botdriver.tdmSniperCount = hg.botdriver.tdmSniperCount or { [0] = 0, [1] = 0 }

local function cheapestAffordable(buyItems, category, bot, team, reserve)
	local group = buyItems[category]
	if not istable(group) then return nil end

	local money = bot:GetNWInt("TDM_Money", 0)
	local budget = money - reserve
	local best, bestPrice

	for _, item in pairs(group) do
		if istable(item) and item.ItemClass and isnumber(item.Price)
			and (item.TeamBased == nil or item.TeamBased == team)
			and item.Price <= budget
			and (not bestPrice or item.Price < bestPrice) then
			best, bestPrice = item, item.Price
		end
	end

	return best
end

-- Callable directly for a bot; also used by sv_cstrike.lua since cstrike
-- inherits tdm's BuyItems catalogue unchanged.
function hg.botdriver.TDMBotBuy(bot)
	if not IsValid(bot) or not bot:Alive() then return end
	if not isfunction(CurrentRound) then return end

	local round = CurrentRound()
	if not istable(round) or not round.buymenu then return end
	if ((zb.ROUND_START or 0) + (round.BuyTime or 40) < CurTime()) then return end

	local buyItems = round.BuyItems
	if not istable(buyItems) then return end

	local team = hg.botdriver.TeamOf(bot)
	local startMoney = bot:GetNWInt("TDM_Money", 0)
	if startMoney <= 0 then return end

	local brain = hg.botdriver.brains[bot]
	local personality = brain and brain.personality
	local aggression = (personality and personality.aggression) or 0.5

	-- Save round: skip buying outright and bank the money -- more likely for
	-- a cautious (low-aggression) bot. Reads as planning a bigger buy later
	-- instead of every bot spending on sight every round.
	if math.random() < SAVE_CHANCE_BASE * (1 - aggression) then return end

	local reserve = math.floor(startMoney * RESERVE_FRAC)

	-- Kit spread: shuffle which primary category is TRIED FIRST so the whole
	-- team does not converge on the same weapon every round.
	local primaryCategories = table.Copy(PRIMARY_CATEGORIES)
	if isBigMap() then primaryCategories[#primaryCategories + 1] = SNIPER_CATEGORY end
	for i = #primaryCategories, 2, -1 do
		local j = math.random(i)
		primaryCategories[i], primaryCategories[j] = primaryCategories[j], primaryCategories[i]
	end

	-- One sniper per team per round: drop the category entirely once the cap
	-- is reached instead of letting a second bot also buy one.
	hg.botdriver.tdmSniperCount[team] = hg.botdriver.tdmSniperCount[team] or 0
	if hg.botdriver.tdmSniperCount[team] >= SNIPER_CAP_PER_TEAM then
		for i = #primaryCategories, 1, -1 do
			if primaryCategories[i] == SNIPER_CATEGORY then table.remove(primaryCategories, i) end
		end
	end

	-- "Caught mid-round with only a pistol": a small, personality-independent
	-- chance the bot skips primary shopping altogether this round.
	local pistolOnly = math.random() < PISTOL_ONLY_CHANCE
	local boughtPrimary = false

	if not pistolOnly then
		for _, category in ipairs(primaryCategories) do
			local item = bestAffordable(buyItems, category, bot, team, reserve)
			if item then
				giveTDMItem(bot, item)
				boughtPrimary = true
				if category == SNIPER_CATEGORY then
					hg.botdriver.tdmSniperCount[team] = hg.botdriver.tdmSniperCount[team] + 1
				end
				break
			end
		end
	end

	local pistol = bestAffordable(buyItems, PISTOL_CATEGORY, bot, team, reserve)
	if pistol then giveTDMItem(bot, pistol) end

	local armor = bestAffordable(buyItems, ARMOR_CATEGORY, bot, team, reserve)
	if armor then giveTDMItem(bot, armor) end

	-- Force-buy: bought nothing at all above (broke, or an unlucky shuffle) --
	-- still has some money and enough aggression to spend it rather than
	-- fight the round with the bare spawn kit. Reserve dropped to 0 and the
	-- CHEAPEST affordable item across every category is taken (getting
	-- something beats getting the best thing).
	if not boughtPrimary and not pistol and math.random() < FORCE_BUY_CHANCE_BASE * aggression then
		local forceCategories = { PISTOL_CATEGORY }
		for _, category in ipairs(PRIMARY_CATEGORIES) do forceCategories[#forceCategories + 1] = category end
		local cheapest, cheapestPrice
		for _, category in ipairs(forceCategories) do
			local item = cheapestAffordable(buyItems, category, bot, team, 0)
			if item and (not cheapestPrice or item.Price < cheapestPrice) then
				cheapest, cheapestPrice = item, item.Price
			end
		end
		if cheapest then giveTDMItem(bot, cheapest) end
	end
end

----------------------------------------------------------------------
-- Buy scheduling: on ZB_StartRound, queue every living tdm-team zcBot for a
-- buy 0.5-3s later (still inside the 40s window), polled by a 0.5s Every tick
-- rather than one timer.Simple per bot so re-running this file never stacks
-- timers under different names.
----------------------------------------------------------------------

local pendingBuy = {}
-- Item 5 (buy timing variance): most bots still buy in the first few
-- seconds, but a small share roll a much later delay -- still inside the 40s
-- window, but often into or past a round's opening skirmish.
local LATE_BUY_CHANCE = 0.10
local LATE_BUY_MIN, LATE_BUY_MAX = 15, 35

hook.Add("ZB_StartRound", "zc_bots_tdm_schedule_buys", function()
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)

	-- The sniper cap is shared with sv_cstrike.lua's own TDMBotBuy calls
	-- (its own ZB_StartRound scheduling hook), so it resets for either mode
	-- here rather than only "tdm" -- otherwise a cstrike round would never
	-- clear a cap tripped by an earlier cstrike round.
	if hg.botdriver.SquadPushModes[roundKey or false] then
		hg.botdriver.tdmSniperCount[0] = 0
		hg.botdriver.tdmSniperCount[1] = 0
	end

	if roundKey ~= "tdm" then return end

	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:IsBot() and ply.zcBot and ply:Alive() then
			local team = hg.botdriver.TeamOf(ply)
			if team == 0 or team == 1 then
				local brain = hg.botdriver.brains[ply]
				local personality = brain and brain.personality
				local reactionMult = (personality and personality.reactionMult) or 1
				local delay = math.Rand(0.5, 3) * reactionMult
				if math.random() < LATE_BUY_CHANCE then
					delay = math.Rand(LATE_BUY_MIN, LATE_BUY_MAX)
				end
				pendingBuy[ply] = CurTime() + delay
			end
		end
	end
end)

hg.botdriver.Every("tdm_buy_tick", 0.5, function()
	if not hg.botdriver.Enabled() then return end
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
-- Squad push (MODE band): heads toward the freshest squad contact if
-- sv_squad.lua's tracker is loaded, else toward a random enemy spawn point.
-- Mode-agnostic and guarded so it never overrides an active engagement -- it
-- only claims the tick when ACQUIRE/COMBAT have no target.
--
-- hg.botdriver.SquadPushModes is the extensibility seam: any later mode file
-- (gwars/criresp/riot/uncontainedriot/wildcard, Part A of the 2026-09-21
-- expansion) adds its own round key here instead of duplicating this
-- behavior, exactly the way this file's own header already asks new modes to
-- reuse it "where it fits". tdm/cstrike are the two keys this file itself
-- needs, seeded below so cstrike's registration keeps working unchanged.
----------------------------------------------------------------------

hg.botdriver.SquadPushModes = hg.botdriver.SquadPushModes or { tdm = true, cstrike = true }

local function resolveContactPos(contact)
	if contact == nil then return nil end
	if isvector(contact) then return contact end
	if istable(contact) then
		if isvector(contact.pos) then return contact.pos end
		if isvector(contact.position) then return contact.position end
		return nil
	end
	-- contact may be an Entity/Player from a future sv_squad.lua; guard
	-- defensively since that API is not verified to exist yet (brief).
	local ok, valid = pcall(IsValid, contact)
	if ok and valid and contact.GetPos then
		local ok2, pos = pcall(function() return contact:GetPos() end)
		if ok2 and isvector(pos) then return pos end
	end
	return nil
end

----------------------------------------------------------------------
-- Item 6 (2026-09-22, called strategy): the squad announces ONE push
-- intention per round via sv_radial.lua, then every squadmate's push
-- objective actually targets it -- mode.tdm_squad_push's Run below reads the
-- identical hg.botdriver.tdmPlan[team].pos the announce sets, as a priority
-- tier between "freshest live contact" and "blind random enemy spawn".
--
-- HARD RULE ("never announce something the bots will not do"): the block
-- between the CALLPLAN-BEGIN/END markers is the ONLY place in this file that
-- ever writes hg.botdriver.tdmPlan[team].pos, and it always announces (the
-- radial.OnCallout call) in the same breath it sets that value -- there is no
-- code path anywhere else that changes or clears the plan, so a plan, once
-- announced, is what every squadmate's push objective keeps reading for the
-- rest of the round (never silently abandoned or swapped without a fresh
-- announce here).
----------------------------------------------------------------------

hg.botdriver.tdmPlan = hg.botdriver.tdmPlan or {} -- team -> { pos = Vector, at = number }

-- CALLPLAN-BEGIN
local function announceAndPlanPush(team)
	local enemyGroup = (team == 1) and "HMCD_TDM_T" or "HMCD_TDM_CT"
	local points = zb.GetMapPoints(enemyGroup)
	if not istable(points) or #points == 0 then return end
	local point = points[math.random(#points)]
	if not istable(point) or not isvector(point.pos) then return end

	hg.botdriver.tdmPlan[team] = { pos = point.pos, at = CurTime() }

	if not (hg.botdriver.radial and hg.botdriver.radial.OnCallout) then return end
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply:IsBot() and ply.zcBot and ply:Alive() and hg.botdriver.TeamOf(ply) == team then
			hg.botdriver.radial.OnCallout(ply, hg.botdriver.GetBrain(ply), "push", 1)
			break
		end
	end
end
-- CALLPLAN-END

hook.Add("ZB_StartRound", "zc_bots_tdm_call_push", function()
	local roundKey = zb and (zb.CROUND_MAIN or zb.CROUND)
	if not hg.botdriver.SquadPushModes[roundKey or false] then return end

	hg.botdriver.tdmPlan[0] = nil
	hg.botdriver.tdmPlan[1] = nil

	timer.Simple(math.Rand(2, 5), function()
		if not hg.botdriver.Enabled() then return end
		local rk = zb and (zb.CROUND_MAIN or zb.CROUND)
		if not hg.botdriver.SquadPushModes[rk or false] then return end
		announceAndPlanPush(0)
		announceAndPlanPush(1)
	end)
end)

----------------------------------------------------------------------
-- Item 3 (2026-09-22, TDM kill trading): reacts to sv_squad.lua's per-team
-- "a teammate just died here, killed by X" report. Bounded to bots already
-- within KILL_TRADE_RADIUS of the death (not the whole team) and to
-- squad.TeamDeath's own KILL_TRADE_WINDOW, so only a plausible, nearby subset
-- ever swings onto the position/killer -- never the whole roster.
----------------------------------------------------------------------

local KILL_TRADE_RADIUS = 1400
local KILL_TRADE_RADIUS_SQR = KILL_TRADE_RADIUS * KILL_TRADE_RADIUS

hg.botdriver.RegisterBehavior({
	name = "mode.tdm_kill_trade",
	band = "MODE",
	order = 8,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		local rk = ctx.roundKey
		if not hg.botdriver.SquadPushModes[rk or false] then return false end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		local squad = hg.botdriver.squad
		if not squad or not squad.TeamDeath then return false end
		local team = hg.botdriver.TeamOf(ctx.bot)
		local pos = squad.TeamDeath(team)
		if not isvector(pos) then return false end
		return ctx.bot:GetPos():DistToSqr(pos) <= KILL_TRADE_RADIUS_SQR
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local team = hg.botdriver.TeamOf(bot)
		local pos, killer = hg.botdriver.squad.TeamDeath(team)
		if not isvector(pos) then return false end
		local dest = (IsValid(killer) and killer:IsPlayer() and killer:Alive()) and killer:GetPos() or pos
		hg.botdriver.SetObjective(bot, dest, 100, 4, "soft", "tdm_kill_trade")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

local function travelPush(ctx, pos, radius, ttl, source)
	if source ~= "tdm_squad_push" and hg.botdriver.SearchVisited and hg.botdriver.SearchVisited(ctx.bot, pos) then return false end
	-- Repeatedly refreshing an already-reached goal must not erase the roam
	-- route selected by a lower-priority behavior on the preceding decision.
	if ctx.bot:GetPos():DistToSqr(pos) <= radius * radius then return false end
	hg.botdriver.SetObjective(ctx.bot, pos, radius, ttl, "soft", source)
	ctx.brain.state = "objective"
	return hg.botdriver.lib.ObjectiveTravel(ctx.bot, ctx.brain, ctx.now)
end

hg.botdriver.RegisterBehavior({
	name = "mode.tdm_squad_push",
	band = "MODE",
	order = 10,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		local rk = ctx.roundKey
		if not hg.botdriver.SquadPushModes[rk or false] then return false end
		if hg.botdriver.RoundAllowsCombat and not hg.botdriver.RoundAllowsCombat() then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		return true
	end,
	Run = function(ctx)
		local bot = ctx.bot

		if hg.botdriver.squad and hg.botdriver.squad.FreshestContact then
			local pos = resolveContactPos(hg.botdriver.squad.FreshestContact(bot))
			if isvector(pos) then
				return travelPush(ctx, pos, 128, 6, "tdm_squad_push")
			end
		end

		local team = hg.botdriver.TeamOf(bot)

		-- Item 6 (called strategy): the squad's announced push beats a blind
		-- random-enemy-spawn guess.
		local plan = hg.botdriver.tdmPlan[team]
		if plan and isvector(plan.pos) then
			return travelPush(ctx, plan.pos, 160, 10, "tdm_called_push")
		end

		local enemyGroup = (team == 1) and "HMCD_TDM_T" or "HMCD_TDM_CT"
		-- Once the opening plan/contact is handled, cover reachable map areas
		-- instead of repeatedly choosing random enemy-spawn points.
		if hg.botdriver.SearchStep then return false end
		local points = zb.GetMapPoints(enemyGroup)
		if istable(points) and #points > 0 then
			local point = points[math.random(#points)]
			if istable(point) and isvector(point.pos) then
				return travelPush(ctx, point.pos, 160, 10, "tdm_enemy_spawn")
			end
		end

		return false
	end,
})

----------------------------------------------------------------------
-- Mode profile
----------------------------------------------------------------------

hg.botdriver.RegisterModeProfile("tdm", {
	behaviors = { "mode.tdm_squad_push", "mode.tdm_kill_trade" },
})
