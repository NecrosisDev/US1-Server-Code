-- Gunfire awareness. Verified against the US1 reference tree (rule: no
-- invented APIs):
--   main-design-source/lua/homigrad/sh_luabullets.lua:942-943 --
--   `function ENTITY:FireLuaBullets(tInfo) if hook.Run("EntityFireBullets",
--   self, tInfo) == false then return end ...`, called as
--   `weapon:FireLuaBullets(pellet)` from
--   main-design-source/lua/weapons/homigrad_base/sh_bullet.lua:437 (and the
--   two non-weapon call sites at lines 186/261 are ricochet/penetration
--   continuations of the same shot, not a second distinct fire event per
--   trigger pull). So `self` in the hook is the WEAPON, and `tInfo` is the
--   bullet table -- `tInfo.Attacker` (sh_bullet.lua:792) is the shooter,
--   `tInfo.Src` (sh_bullet.lua:791) the muzzle/trace-origin position,
--   `tInfo.Dir` (sh_bullet.lua's own `bullet.Dir = dir` literal, same table)
--   the fire direction -- both fields are set on the identical table this
--   hook already reads for Src/Attacker, so no second verification pass was
--   needed for the suppression line-distance term below. US1's firearm base
--   therefore does fire through the hookable path; no custom projectile hook
--   is needed.
--   Supressor field (verified, note the repo's own misspelling):
--   `SWEP.Supressor`, read at sh_bullet.lua:809 as a plain truthy/falsy flag.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}

hg.botdriver.DeclareBrainState("hearing", {
	fields = {
		"heardPos", "heardAt", "suppressedUntil", "suppressedFrom", "combatAwareUntil",
		-- Item 2 (2026-09-22, DM third-partying): rolling "sustained gunfire"
		-- tracker, see the SUSTAIN_* block below.
		"heardSustainPos", "heardSustainAt", "heardSustainCount",
	},
})

local HEAR_RANGE_SQR = 2500 * 2500
local HEAR_RANGE_SUPPRESSED_SQR = 1200 * 1200
local SHOOTER_THROTTLE = 0.5

-- Item 2: "sustained" gunfire is repeated hostile shots landing within
-- SUSTAIN_RADIUS of one another inside a SUSTAIN_WINDOW rolling window --
-- explicitly not a single shot (that only ever reaches count 1). Tracked per
-- LISTENING bot (not per shooter) so modes/sv_dm.lua's third-party behavior
-- can tell "a real fight is happening over there" from a single stray round.
local SUSTAIN_RADIUS = 400
local SUSTAIN_RADIUS_SQR = SUSTAIN_RADIUS * SUSTAIN_RADIUS
local SUSTAIN_WINDOW = 6
local SUSTAIN_MIN_EVENTS = 3

hg.botdriver.hearing = hg.botdriver.hearing or {}

-- The current sustained-gunfire position for this bot's brain, or nil if
-- nothing qualifies right now. Pure field reads, no scan -- safe to call from
-- a MODE-band CanRun every decision.
function hg.botdriver.hearing.SustainedPos(brain, now)
	if not brain or (brain.heardSustainCount or 0) < SUSTAIN_MIN_EVENTS then return nil end
	if now - (brain.heardSustainAt or -math.huge) > SUSTAIN_WINDOW then return nil end
	return brain.heardSustainPos
end

-- Item B2: a hostile shot whose line (Src + Dir) passes within this many
-- units of a bot that has no LOS on the shooter counts as "suppressing fire".
local SUPPRESSION_LINE_DIST = 90
local SUPPRESSION_DURATION = 1.2
-- How long "heard/seen combat" (the REFLEX grenade-dodge gate, item B1) stays
-- true after any hostile gunfire is heard -- reuses this same throttled event
-- instead of a second scan.
local COMBAT_AWARE_WINDOW = 10

local lastEventAt = setmetatable({}, { __mode = "k" }) -- shooter -> time, one event per 0.5s

-- Point-to-line-segment distance (Src, Src + Dir*Distance), used only for the
-- suppression check below -- no trace, pure vector math, so it costs nothing
-- extra per shot beyond what the existing per-shooter 0.5s throttle already
-- pays for the hearing scan.
local function distToShotLine(point, src, dir, maxDist)
	local toPoint = point - src
	local t = toPoint:Dot(dir)
	t = math.Clamp(t, 0, maxDist or 8192)
	local closest = src + dir * t
	return point:Distance(closest)
end

hook.Add("EntityFireBullets", "zc_bots_hearing", function(wep, tInfo)
	if not hg.botdriver.Enabled() then return end
	local shooter = tInfo and tInfo.Attacker
	if not IsValid(shooter) or not shooter:IsPlayer() then return end

	local now = CurTime()
	-- Every real shot, humans included (2026-09-25): sv_brain.lua's "a firing
	-- target is noticed at once" awareness rule and the spawn-grace "they
	-- started it" check read this table, but only bots' own Engage wrote it,
	-- so neither ever applied to a human shooter. Stamped before the throttle.
	if hg.botdriver.lastFireAt then hg.botdriver.lastFireAt[shooter] = now end
	if now - (lastEventAt[shooter] or -math.huge) < SHOOTER_THROTTLE then return end
	lastEventAt[shooter] = now

	local pos = (tInfo.Src and isvector(tInfo.Src)) and tInfo.Src or shooter:GetPos()
	local dir = tInfo.Dir and isvector(tInfo.Dir) and tInfo.Dir or nil
	local dist = tInfo.Distance and isnumber(tInfo.Distance) and tInfo.Distance or 8192
	local suppressed = IsValid(wep) and wep.Supressor and true or false
	local rangeSqr = suppressed and HEAR_RANGE_SUPPRESSED_SQR or HEAR_RANGE_SQR

	local ffa = hg.botdriver.IsFFA()
	local shooterTeam = hg.botdriver.TeamOf(shooter)
	local lib = hg.botdriver.lib
	for bot, brain in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot ~= shooter and bot:Alive() and bot:IsBot() and bot.zcBot
			and bot:GetPos():DistToSqr(pos) <= rangeSqr then
			local hostile = ffa or hg.botdriver.TeamOf(bot) ~= shooterTeam
			if hostile then
				brain.heardPos = pos
				brain.heardAt = now
				brain.combatAwareUntil = now + COMBAT_AWARE_WINDOW

				-- Item 2: extend or start this bot's sustained-gunfire streak.
				local anchor = brain.heardSustainPos
				if anchor and now - (brain.heardSustainAt or -math.huge) <= SUSTAIN_WINDOW
					and anchor:DistToSqr(pos) <= SUSTAIN_RADIUS_SQR then
					brain.heardSustainCount = (brain.heardSustainCount or 1) + 1
				else
					brain.heardSustainPos = pos
					brain.heardSustainCount = 1
				end
				brain.heardSustainAt = now

				-- Item B2: suppression only when the bot cannot already see the
				-- shooter (a bot with LOS just fights back through COMBAT/ACQUIRE
				-- as normal) and the shot line passed close enough to feel aimed
				-- at/near it.
				if dir and lib and lib.CanSeeTarget and not lib.CanSeeTarget(bot, shooter) then
					local lineDist = distToShotLine(bot:GetPos(), pos, dir, dist)
					if lineDist <= SUPPRESSION_LINE_DIST then
						brain.suppressedUntil = now + SUPPRESSION_DURATION
						brain.suppressedFrom = pos
					end
				end
			end
		end
	end
end)

local DOOR_HEAR_MIN, DOOR_HEAR_SPAN, DOOR_OWN_RADIUS_SQR = 250, 900, 130 * 130

hook.Add("SwingDoors_Noise", "zc_bots_hearing_doors", function(door, _, loudness)
	if not hg.botdriver.Enabled() or not IsValid(door) then return end
	local pos = door:WorldSpaceCenter()
	local range = DOOR_HEAR_MIN + DOOR_HEAR_SPAN * math.Clamp(loudness or 0, 0, 1)
	local now = CurTime()
	for bot, brain in pairs(hg.botdriver.brains) do
		if IsValid(bot) and bot:Alive() and bot.zcBot then
			local distSqr = bot:GetPos():DistToSqr(pos)
			-- a door right next to the bot is almost certainly the one it just opened itself
			if distSqr > DOOR_OWN_RADIUS_SQR and distSqr <= range * range then
				brain.heardPos = pos
				brain.heardAt = now
			end
		end
	end
end)
