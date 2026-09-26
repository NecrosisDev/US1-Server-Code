-- Part A.1 (2026-09-21) + humans-first revision (2026-09-22): shared
-- shooter-round Intermission wrap, generalised out of modes/sv_masscasualty.lua's
-- own wrap (the first mode file to need this shape) so modes/sv_activeshooter.lua
-- can reuse the promote/backstop plumbing instead of duplicating it. Every
-- caller still supplies its OWN verified needed-shooter-count formula and its
-- own TraitorLoot/role-name pairing -- this file assumes nothing is identical
-- between callers beyond the wrap shape itself.
--
-- Owner decision (2026-09-22): humans get priority for the shooter/traitor
-- role; bots fill only what humans do not take; and at least one shooter slot
-- is always a bot once the mode wants more than one, so the role can never go
-- entirely unfilled or entirely bot-only-by-force. This is the OPPOSITE of
-- the original A.1 shape, which forced every shooter to be a bot and parked
-- every surplus bot as a spectator:
--   * No more pre-parking. The real Intermission (`original`) now runs
--     COMPLETELY UNMODIFIED first -- no bots benched beforehand, no humans
--     forced to isTraitor=false afterward. Its own selection already draws
--     from every non-spectator player, bots included, with no :IsBot() filter
--     anywhere in the chain (verified, see modes/sv_masscasualty.lua and
--     modes/sv_activeshooter.lua's own header citations) -- so a human keeps
--     whatever shooter slot that selection gives them.
--   * Sequencing note (verified this session, US1
--     modes/zz_masscasualty/sv_zz_masscasualty.lua:27-59 and
--     modes/homicide/sv_homicide.lua:1133-1240): hmcd's own inner Intermission
--     assigns isTraitor SYNCHRONOUSLY (three RandomPairs passes, the last two
--     with no karma gate, so `traitors_needed` is always fully assigned by the
--     time the function returns) -- masscasualty's OUTER MODE:Intermission
--     additionally schedules its own timer.Simple(0.5, ...) top-up using the
--     IDENTICAL `math.min(3, floor(playerCount/2))` formula this file's own
--     `opts.needed` reproduces for masscasualty. Reading/topping-up isTraitor
--     immediately after `original(self)` returns (as the pre-existing A.1
--     code already did) is therefore safe: this wrap's own top-up already
--     satisfies that formula before masscasualty's internal timer fires, so
--     the internal timer's own `needed = target - current` sees current >=
--     target and no-ops -- never a double top-up. activeshooter delegates its
--     WHOLE selection synchronously to hmcd (no inner timer at all), and its
--     own `opts.needed` is the exact same formula hmcd computes internally, so
--     `original(self)` alone almost always already satisfies it.
--   * Removed: the spectator-parking table and its ZB_EndRound un-park hook.
--     They existed only to cap a forced all-bot shooter squad at `needed`
--     bots by hiding the surplus; with humans now eligible and no forced
--     all-bot selection, there is no surplus to hide -- every non-shooter
--     zcBot simply stays an ordinary civilian for the round (the generic
--     ACQUIRE/COMBAT/IDLE bands modes/sv_masscasualty.lua's and
--     modes/sv_activeshooter.lua's own targeting-band comments already assumed
--     for "bots that are not shooters this round").
--
-- Idempotent per modeKey: a repeat include (autorefresh) checks the live
-- zb.modes[modeKey].Intermission against the exact wrapper function this
-- module installed last time for that key, the same guard-token idiom
-- sv_lowpop.lua/modes/sv_masscasualty.lua already use.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver._shooterWraps = hg.botdriver._shooterWraps or {}

local function livingEligibleBots()
	local list = {}
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply.zcBot and ply:Team() ~= TEAM_SPECTATOR then
			list[#list + 1] = ply
		end
	end
	table.sort(list, function(a, b) return a:EntIndex() < b:EntIndex() end)
	return list
end

-- Every currently-live shooter (ply.isTraitor, non-spectator), split by
-- human/bot -- read fresh each call since the real Intermission and this
-- wrap's own top-up both mutate isTraitor in between calls.
local function currentShooters()
	local bots, humans = {}, {}
	for _, ply in ipairs(player.GetAll()) do
		if IsValid(ply) and ply.isTraitor and ply:Team() ~= TEAM_SPECTATOR then
			if ply.zcBot then bots[#bots + 1] = ply else humans[#humans + 1] = ply end
		end
	end
	return bots, humans
end

-- opts:
--   modeKey  (string, required)  -- zb.modes[modeKey] round key
--   needed   (function(playerCount) -> integer, required) -- verified per-mode
--   typesKey (string, optional, defaults to modeKey) -- self.Types[typesKey].TraitorLoot
--   roleName / roleColor (optional) -- zb.GiveRole(bot, roleName, roleColor) per
--                                       shooter when the real mode does this too;
--                                       omit when the source mode never calls
--                                       GiveRole for this role (verify per-mode).
function hg.botdriver.WrapShooterIntermission(opts)
	local modeKey = opts and opts.modeKey
	if not isstring(modeKey) or not isfunction(opts.needed) then return false end
	if not (zb and zb.modes and zb.modes[modeKey]) then return false end

	local state = hg.botdriver._shooterWraps[modeKey]
	if not state then
		state = {}
		hg.botdriver._shooterWraps[modeKey] = state
	end

	if zb.modes[modeKey].Intermission == state.wrapped then return true end -- already installed

	-- Live function is not our wrapper, so it is the real original: re-capture
	-- rather than keeping a stale one from before a mode-table rebuild.
	state.original = zb.modes[modeKey].Intermission
	local original = state.original
	if not isfunction(original) then return false end

	local function wrapped(self)
		local enabled = hg.botdriver.cv_enable and hg.botdriver.cv_enable:GetBool()
		if not enabled then return original(self) end -- exact pass-through when disabled

		local needed = math.max(0, math.floor(tonumber(opts.needed(#player.GetAll())) or 0))

		-- Humans-first: run the real Intermission completely unmodified. See
		-- file header's sequencing note for why reading isTraitor immediately
		-- after this call is safe even for masscasualty's async top-up.
		local a, b, c, d, e, f = original(self)
		if needed <= 0 then return a, b, c, d, e, f end

		local types = istable(self) and self.Types
		local typesKey = opts.typesKey or modeKey

		local function promote(bot)
			bot.isTraitor = true
			bot.MainTraitor = false
			if types and types[typesKey] and isfunction(types[typesKey].TraitorLoot) then
				types[typesKey].TraitorLoot(bot)
			end
			if opts.roleName then
				zb.GiveRole(bot, opts.roleName, opts.roleColor or Color(190, 0, 0))
			end
		end

		local shooterBots, shooterHumans = currentShooters()

		-- Top up: bots fill only what the real (human-eligible) selection left
		-- unfilled.
		if #shooterBots + #shooterHumans < needed then
			for _, bot in ipairs(livingEligibleBots()) do
				if #shooterBots + #shooterHumans >= needed then break end
				if not bot.isTraitor then
					promote(bot)
					shooterBots[#shooterBots + 1] = bot
				end
			end
		end

		-- Never zero bot shooters once the mode wants more than a single one:
		-- humans keep priority for the role (above), but one slot is always
		-- reserved for a bot so an all-human pick never leaves the shooter
		-- squad bot-free.
		if needed > 1 and #shooterBots == 0 and #shooterHumans > 0 then
			local bot = livingEligibleBots()[1]
			if IsValid(bot) then
				local demoted = shooterHumans[1]
				demoted.isTraitor = false
				demoted.MainTraitor = false
				table.remove(shooterHumans, 1)
				promote(bot)
				shooterBots[#shooterBots + 1] = bot
			end
		end

		-- Exactly one shooter should carry MainTraitor for display; the real
		-- Intermission already sets this for whoever it picked, so only fix up
		-- the case where this wrap's own churn (the backstop demotion above)
		-- could have left the flag on nobody live.
		local hasMain = false
		for _, ply in ipairs(player.GetAll()) do
			if IsValid(ply) and ply.isTraitor and ply.MainTraitor then hasMain = true break end
		end
		if not hasMain then
			local anyShooter = shooterHumans[1] or shooterBots[1]
			if IsValid(anyShooter) then anyShooter.MainTraitor = true end
		end

		return a, b, c, d, e, f
	end

	state.wrapped = wrapped
	zb.modes[modeKey].Intermission = wrapped
	return true
end

hg.botdriver._shooterReinstall = hg.botdriver._shooterReinstall or {}
hook.Add("ZB_PreRoundStart", "zc_bots_shooter_modes_reinstall", function()
	for _, fn in pairs(hg.botdriver._shooterReinstall) do fn() end
end)
