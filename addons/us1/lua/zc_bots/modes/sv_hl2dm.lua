-- hl2dm mode profile: sniper subClass bots hold an authored sniper-spawn map
-- point; everyone else pushes toward the freshest squad contact when a squad
-- module exists.
--
-- VERIFIED (US1 tree, main-design-source/lua -> us1/addons/zcity):
--   modes/hl2dm/sv_hl2dm.lua:67-109 -- ply.subClass is set to "sniper" for one
--     Combine (team 1) and one Rebel (team 0) bot when #players_alive > 6,
--     via GiveEquipment(); other subClass values (elite/shotgunner/medic/
--     grenadier) are irrelevant here.
--   modes/hl2dm/sv_hl2dm.lua:83-90, 100-109 -- the sniper subClass assignment
--     also teleports the human player to a random "HL2DM_SNIPERSPAWN" (team
--     1) or "HL2DM_CROSSBOWSPAWN" (team 0) map point. These ARE the map's own
--     authored long-sightline sniper spots (modes/hl2dm/sh_hl2dm.lua:15-21
--     declares both point groups), so this file reuses them instead of
--     inventing a nav-area/trace heuristic -- no PROVISIONAL needed, an
--     existing convention was found.
--   libraries/mappoints/sv_points.lua:15 -- zb.GetMapPoints(pointGroup)
--     returns an array of point tables; sv_hl2dm.lua:88/107 index them as
--     points[i].pos (a Vector), confirming the field name used below.
--   modes/hl2dm/sh_hl2dm.lua:1 -- team 1 is Combine, team 0 is Rebel.
--
-- Squad push: hg.botdriver.squad does not exist anywhere in this package yet
-- (grepped the whole src/lua/zc_bots tree), so the CanRun guard below is the
-- real gate, not defence-in-depth -- this behavior is a no-op until a later
-- phase adds sv_squad.lua.

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local RB = hg.botdriver.RegisterBehavior

local SNIPER_CONTACT_RANGE = 600
local HOLD_RADIUS = 48
local HOLD_TTL = 4

-- Cache the chosen hold point per bot-life; recompute if the team changed
-- (subClass/team reassignment between rounds) or nothing was cached yet.
local function sniperHoldPos(bot, brain)
	local team = bot:Team()
	if brain.hl2dmSniperTeam == team and isvector(brain.hl2dmSniperPos) then
		return brain.hl2dmSniperPos
	end
	if not (zb and zb.GetMapPoints) then return nil end
	local pointGroup = team == 1 and "HL2DM_SNIPERSPAWN" or "HL2DM_CROSSBOWSPAWN"
	local points = zb.GetMapPoints(pointGroup)
	if not istable(points) or #points == 0 then return nil end
	local point = points[math.random(#points)]
	if not istable(point) or not isvector(point.pos) then return nil end
	brain.hl2dmSniperPos = point.pos
	brain.hl2dmSniperTeam = team
	return brain.hl2dmSniperPos
end

RB({
	name = "hl2dm.sniper-hold",
	band = "MODE",
	order = 20,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		return ctx.bot.subClass == "sniper"
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local target, dist = ctx:AcquireTarget()
		if IsValid(target) and dist and dist <= SNIPER_CONTACT_RANGE then
			-- Contact within range: decline the tick so COMBAT band engages.
			-- Crouch-while-stationary-and-firing beyond 900u is already
			-- handled by hg.botdriver.gunhandling.ApplyCrouch (sv_gunhandling.lua,
			-- wired from sv_brain.lua's Engage) -- not duplicated here.
			return false
		end
		local holdPos = sniperHoldPos(bot, brain)
		if not holdPos then return false end
		hg.botdriver.SetObjective(bot, holdPos, HOLD_RADIUS, HOLD_TTL, "soft", "hl2dm.sniper-hold")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

RB({
	name = "hl2dm.squad-push",
	band = "MODE",
	order = 30,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx.bot.subClass == "sniper" then return false end
		return hg.botdriver.squad ~= nil and hg.botdriver.squad.FreshestContact ~= nil
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local contact = hg.botdriver.squad.FreshestContact(bot)
		local pos
		if isvector(contact) then
			pos = contact
		elseif istable(contact) and isvector(contact.pos) then
			pos = contact.pos
		end
		if not pos then return false end
		hg.botdriver.SetObjective(bot, pos, 128, 6, "soft", "hl2dm.squad-push")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

hg.botdriver.RegisterModeProfile("hl2dm", {
	behaviors = { "hl2dm.sniper-hold", "hl2dm.squad-push" },
})
