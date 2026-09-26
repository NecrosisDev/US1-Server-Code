-- Automatic arrivals are deliberately gradual, regardless of population deficit.
-- The first arrival and every subsequent attempt wait 45-120 seconds.
-- Round/enable/nav/target guards are owned by sv_fill; no queued deficit is replayed.
if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.presence = hg.botdriver.presence or {}
local presence = hg.botdriver.presence

local JOIN_MIN, JOIN_MAX = 45, 120
local SESSION_MIN, SESSION_MAX = 15 * 60, 70 * 60
-- Keep an existing new-format deadline over hotloads; discard legacy fast-fill state.
function presence.CancelJoin()
	presence.nextJoinAt = nil
end

function presence.RequestJoin(deficit)
	if (tonumber(deficit) or 0) <= 0 then presence.CancelJoin() return false end
	local now = CurTime()
	if not presence.nextJoinAt then
		presence.nextJoinAt = now + math.Rand(JOIN_MIN, JOIN_MAX)
		return false
	end
	if now < presence.nextJoinAt then return false end
	-- Consume this attempt before creation, including failure or reentrant calls.
	-- Never loop over an overdue deadline or replay missed arrivals.
	presence.nextJoinAt = now + math.Rand(JOIN_MIN, JOIN_MAX)
	local bot = hg.botfill.AddBot and hg.botfill.AddBot()
	if not IsValid(bot) then return false end
	bot.zcPresenceLeaveAt = now + math.Rand(SESSION_MIN, SESSION_MAX)
	return true
end

-- Organic session expiry is checked only at the population target and between
-- rounds. A departure creates a fresh deficit; the next Tick starts a new
-- arrival delay instead of immediately replacing the departing bot.
function presence.ChurnTick(bots)
	local now = CurTime()
	local expired
	for _, bot in ipairs(bots) do
		if IsValid(bot) then
			-- Lazy-roll a session for any non-manual bot that predates this
			-- file (already in play when it first loads/autorefreshes) instead
			-- of leaving it permanently exempt from churn.
			bot.zcPresenceLeaveAt = bot.zcPresenceLeaveAt or (now + math.Rand(SESSION_MIN, SESSION_MAX))
			if now >= bot.zcPresenceLeaveAt then
				expired = bot
				break
			end
		end
	end
	if not expired then return false end
	-- NEGATIVE CONTROL / hard guard: never touch a manually-added bot, even if
	-- this function is ever called with a list that was not pre-filtered.
	if expired.zcBotManual then return false end
	expired:Kick("zc_bots population adjustment (session end)")
	return true
end
