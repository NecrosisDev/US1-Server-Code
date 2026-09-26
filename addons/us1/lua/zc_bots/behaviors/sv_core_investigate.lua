-- SUPPORT band: investigate a last-known position when no target is visible.
-- SUPPORT already sits between COMBAT and IDLE in BAND_ORDER (sv_arbiter.lua),
-- so no new band is needed.
--
-- Consumes three memory sources, freshest/most-specific first: direct sight
-- (brain.lastSeenPos, up to 12s), gunfire heard (brain.heardPos, sv_hearing.lua,
-- up to 8s), and the damage-source memory sv_brain.lua's HomigradDamage
-- listener already seeds (brain.damagePos, up to brain.damageUntil, a 4s
-- window). This is a superset of behaviors/sv_core_idle.lua's
-- "idle.investigate" (IDLE band, damagePos only), which stays in place as a
-- narrower defence-in-depth fallback -- it will rarely fire on its own while
-- this file is loaded, since SUPPORT runs before IDLE and this file's window
-- always covers idle.investigate's.
--
-- Patience trait (sv_personality.lua) scales the look-around sweep duration.

local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("investigate", { fields = {
	"investigatePos", "investigateSource", "investigatePhase", "investigateSweepUntil",
	"investigateSweepBaseYaw",
} })

local SIGHT_MEMORY = 12
local SOUND_MEMORY = 8
local ARRIVE_RADIUS = 48
local WALK_RADIUS = 300

local function pickMemory(brain, now)
	if isvector(brain.lastSeenPos) and now - (brain.lastSeenTime or -math.huge) < SIGHT_MEMORY then
		return brain.lastSeenPos, "sight"
	end
	if isvector(brain.heardPos) and now - (brain.heardAt or -math.huge) < SOUND_MEMORY then
		return brain.heardPos, "sound"
	end
	if isvector(brain.damagePos) and now < (brain.damageUntil or 0) then
		return brain.damagePos, "damage"
	end
	return nil
end

RB({
	name = "support.investigate",
	band = "SUPPORT",
	order = 30,
	stateLabel = "investigate",
	finalize = false,
	CanRun = function(ctx)
		if ctx:HardObjective() then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		return pickMemory(ctx.brain, ctx.now) ~= nil
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		local pos, source = pickMemory(brain, now)
		if not pos then
			brain.investigatePhase = nil
			return false
		end

		if brain.investigatePos ~= pos or brain.investigateSource ~= source then
			brain.investigatePos = pos
			brain.investigateSource = source
			brain.investigatePhase = "approach"
			brain.investigateSweepUntil = nil
		end

		local patience = (brain.personality and brain.personality.patience) or 1
		local dist = bot:GetPos():Distance(pos)

		if brain.investigatePhase == "approach" then
			brain.sprint = dist > WALK_RADIUS + 100
			lib.LookAt(bot, brain, pos + Vector(0, 0, 40), "investigate", false)
			lib.PathTo(bot, brain, pos, now, 1)
			if dist <= WALK_RADIUS then brain.investigatePhase = "walk" end
			return true, { path = true }
		end

		if brain.investigatePhase == "walk" then
			-- Last stretch: walk (no sprint) so fists/weapon stay up, matching
			-- the brief's "walking the last 300 u".
			brain.sprint = false
			lib.LookAt(bot, brain, pos + Vector(0, 0, 40), "investigate", false)
			lib.PathTo(bot, brain, pos, now, 0.8)
			if dist <= ARRIVE_RADIUS then
				brain.investigatePhase = "sweep"
				brain.investigateSweepUntil = now + math.Rand(2, 4) * patience
				brain.investigateSweepBaseYaw = bot:EyeAngles().y
			end
			return true, { path = true }
		end

		-- sweep: hold position, look left/right across ~70 degrees, then give
		-- up and clear the memory that triggered this.
		brain.forward, brain.side = 0, 0
		brain.path = nil
		local baseYaw = brain.investigateSweepBaseYaw or bot:EyeAngles().y
		-- DESYNC FIX (2026-09-21 immersion pass): this used to read plain
		-- math.sin(now * 1.4), a GLOBAL-clock sine with no per-bot phase, so
		-- any two bots investigating at once swept their heads in perfect
		-- lockstep -- the exact "scripted" tell sv_brain.lua's own strafe sine
		-- (+bot:EntIndex()) and sv_aim.lua's drift model (personality
		-- noisePhaseA/B) already avoid. Reuses that same trait instead of
		-- adding a new one.
		local phase = (brain.personality and brain.personality.noisePhaseA) or bot:EntIndex()
		local yaw = baseYaw + math.sin(now * 1.4 + phase) * 70
		lib.SetLookAngles(brain, Angle(0, yaw, 0), "investigate", false)

		if now >= (brain.investigateSweepUntil or 0) then
			brain.investigatePos = nil
			brain.investigatePhase = nil
			brain.lastSeenPos = nil
			brain.heardPos = nil
			brain.damageUntil = 0
		end
		return true, false
	end,
})
