-- Preparation only: no SpecDM rules, heats, scoring hooks or automatic markets.
if not SERVER then return end
local A = ZCGoobArcade
A.SpecDM = A.SpecDM or {}
local D = A.SpecDM
local Q, S = A.Query, A.Quote
local enabled = CreateConVar("zc_goobos_specdm_betting", "0", FCVAR_ARCHIVE, "Enable approved SpecDM event betting only after its owner registers the versioned isolation contract.")
D.Version = 1
local unavailable = "SpecDM betting is being prepared. Endless deathmatch has no winner; a finite wager event and its isolation contract must be implemented first."
local function scopeValid(scope)
    return isstring(scope) and #scope <= 48 and scope:match("^specdm:[%w_%-]+$") ~= nil
end
function D.Register(provider)
    A.Require(istable(provider) and provider.version == 1 and type(provider.Audience) == "function" and type(provider.CanBet) == "function", "SpecDM betting contract v1 is required.")
    -- Audience must be installed before the owner admits ANY isolated player.
    -- CanBet attests this account is a non-competing observer for the event.
    D.provider = provider
end
function A.ArcadeAudience(ply)
    if not D.provider then return ZCSpecDM and "blocked" or "main" end
    local ok, scope = pcall(D.provider.Audience, ply)
    if ok and (scope == "main" or scopeValid(scope)) then return scope end
    return "blocked"
end
function A.ArcadeMain(ply) return A.ArcadeAudience(ply) == "main" end
function D.Ready() return D.provider ~= nil and enabled:GetBool() end
function D.Storage()
    if D.storageReady then return end
    Q("CREATE TABLE IF NOT EXISTS zc_arcade_specdm (id TEXT PRIMARY KEY, event TEXT UNIQUE NOT NULL, scope TEXT NOT NULL, closes INTEGER NOT NULL, resultby INTEGER NOT NULL, roster TEXT NOT NULL, title TEXT NOT NULL)")
    Q("CREATE INDEX IF NOT EXISTS zc_arcade_specdm_scope ON zc_arcade_specdm(scope)")
    Q("CREATE TABLE IF NOT EXISTS zc_arcade_specdm_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, scope TEXT NOT NULL, entry TEXT NOT NULL)")
    Q("CREATE INDEX IF NOT EXISTS zc_arcade_specdm_ledger_scope ON zc_arcade_specdm_ledger(scope,id)")
    D.storageReady = true
end
function D.Row(id)
    local rows = Q("SELECT * FROM zc_arcade_specdm WHERE id=" .. S(id))
    return rows and rows[1]
end
local function atomic(fn)
    local begun = false
    local ok, result = pcall(function()
        A.Storage(); Q("BEGIN IMMEDIATE"); begun = true
        local out = fn(); Q("COMMIT"); begun = false; return out
    end)
    if begun then sql.Query("ROLLBACK") end
    if not ok then return nil, tostring(result) end
    return result
end
-- The future owner calls this for an explicitly chosen finite event. It never
-- derives a winner, roster or lifecycle from the living round or global kills.
function D.Open(event)
    return atomic(function()
        A.Require(D.Ready(), unavailable)
        A.Require(istable(event) and event.version == 1 and scopeValid(event.scope), "Invalid SpecDM event scope/version.")
        A.Require(isstring(event.id) and #event.id >= 8 and #event.id <= 96 and event.id:match("^[%w_%-]+$"), "Use a durable, globally unique event ID.")
        A.Require(isstring(event.title) and #event.title > 0 and #event.title <= 80 and not event.title:find("[%z\1-\31]"), "Invalid event title.")
        A.Require(type(event.closes) == "number" and event.closes == math.floor(event.closes) and event.closes > os.time() and event.closes <= os.time() + 300, "Betting closes within five minutes.")
        A.Require(type(event.resultBy) == "number" and event.resultBy == math.floor(event.resultBy) and event.resultBy > event.closes and event.resultBy <= event.closes + 1800, "A finite result deadline is required.")
        A.Require(istable(event.entrants) and #event.entrants >= 2 and #event.entrants <= 7, "Freeze two to seven entrants.")
        local roster, seen = {}, {}
        for _, entrant in ipairs(event.entrants) do
            A.Require(istable(entrant) and isstring(entrant.account) and entrant.account:match("^%d+$") and #entrant.account <= 20 and not seen[entrant.account], "Invalid or repeated entrant account.")
            A.Require(isstring(entrant.alias) and #entrant.alias > 0 and #entrant.alias <= 40 and not entrant.alias:find("[^ -~]"), "Use a short arena callsign, not living identity data.")
            seen[entrant.account] = true; roster[#roster + 1] = {account = entrant.account, alias = entrant.alias}
        end
        local existing = Q("SELECT id FROM zc_arcade_specdm WHERE event=" .. S(event.id))
        A.Require(not existing, "Event IDs cannot be reused, even after settlement.")
        local active = Q("SELECT m.id FROM zc_arcade_specdm m JOIN zc_arcade_rounds r ON r.id=m.id WHERE m.scope=" .. S(event.scope) .. " AND r.status IN ('open','locked')")
        A.Require(not active, "This arena already has an unsettled betting event.")
        local id = util.SHA256("specdm:" .. event.id):sub(1, 32)
        Q("INSERT INTO zc_arcade_rounds VALUES (" .. S(id) .. ",'specdm','open',NULL,'{}'," .. os.time() .. ")")
        Q("INSERT INTO zc_arcade_specdm VALUES (" .. S(id) .. "," .. S(event.id) .. "," .. S(event.scope) .. "," .. event.closes .. "," .. event.resultBy .. "," .. S(util.TableToJSON(roster)) .. "," .. S(event.title) .. ")")
        return id
    end)
end
function D.Lock(id)
    return atomic(function()
        local meta = D.Row(id)
        A.Require(meta ~= nil, "Unknown SpecDM market.")
        local r = A.RoundRow(id)
        A.Require(r and (r.status == "open" or r.status == "locked"), "Event already closed.")
        A.Require(r.status == "locked" or os.time() <= tonumber(meta.closes), "Missed lock deadline; void this event.")
        Q("UPDATE zc_arcade_rounds SET status='locked' WHERE id=" .. S(id)); return true
    end)
end
-- nil winner means draw/no-contest/cancellation. Frozen roster changes must void.
function D.Resolve(id, winner)
    return atomic(function()
        local meta, r = D.Row(id), A.RoundRow(id)
        A.Require(meta and r, "Unknown SpecDM market.")
        local choice
        for i, entrant in ipairs(util.JSONToTable(meta.roster, false, true)) do if entrant.account == winner then choice = tostring(i) end end
        A.Require(winner == nil or choice ~= nil, "Winner must belong to the frozen roster.")
        if r.status == "finished" or r.status == "void" then
            A.Require((r.status == "void" and winner == nil) or (r.status == "finished" and r.winner == choice), "Result is already final.")
            return true
        end
        A.Require(winner == nil or (r.status == "locked" and os.time() < tonumber(meta.resultby)), "Lock before play; expired events cannot award a winner.")
        Q("UPDATE zc_arcade_rounds SET status=" .. S(choice and "finished" or "void") .. ",winner=" .. S(choice or "") .. " WHERE id=" .. S(id))
        return true
    end)
end
function D.Current(scope)
    local rows = Q("SELECT m.id FROM zc_arcade_specdm m JOIN zc_arcade_rounds r ON r.id=m.id WHERE m.scope=" .. S(scope) .. " AND r.status IN ('open','locked') ORDER BY m.closes DESC LIMIT 1")
    return rows and D.Row(rows[1].id)
end
function D.View(ply, scope)
    local out = {title = "SpecDM", reason = unavailable}
    if not scopeValid(scope) or not D.provider then return out end
    local meta = D.Current(scope)
    if not meta then return out end
    local r = A.RoundRow(meta.id)
    local ok, allowed = pcall(D.provider.CanBet, ply, meta.event)
    local options, entrant = {}, false
    for i, p in ipairs(util.JSONToTable(meta.roster, false, true)) do
        options[i] = {id = tostring(i), name = p.alias}
        if p.account == ply:SteamID64() then entrant = true end
    end
    local pools, total = util.JSONToTable(r.pools, false, true) or {}, 0
    for _, value in pairs(pools) do total = total + value end
    return {id = meta.id, title = "SpecDM · " .. meta.title, options = options, pools = pools, total = total,
        open = D.Ready() and A.Enabled() and r.status == "open" and os.time() < tonumber(meta.closes) and ok and allowed == true and not entrant,
        notice = entrant and "Entrants cannot bet on their event." or "SpecDM-only event. Stakes refund on draw, cancellation or missing result.",
        remaining = math.max(0, tonumber(meta.closes) - os.time()), specdm = true}
end
function D.Place(ply, s, balance, stake, option, id)
    local scope = A.ArcadeAudience(ply)
    A.Require(scopeValid(scope) and D.Ready() and A.Enabled(), unavailable)
    A.Require(not s.specBet, "A previous SpecDM ticket is still awaiting settlement.")
    local market = D.View(ply, scope)
    A.Require(market.open and market.id == id, "SpecDM event closed, changed or unavailable to you.")
    local chosen = market.options[option]
    A.Require(chosen ~= nil and balance >= stake, "Invalid outcome or insufficient points.")
    local alias = "Bettor"
    if D.provider.BettorAlias then
        local ok, value = pcall(D.provider.BettorAlias, ply, D.Row(id).event)
        A.Require(ok and isstring(value) and #value > 0 and #value <= 40 and not value:find("[^ -~]"), "Arena callsign is unavailable.")
        alias = value
    end
    A.Wager(s, stake)
    local pools = market.pools; pools[chosen.id] = (pools[chosen.id] or 0) + stake
    Q("UPDATE zc_arcade_rounds SET pools=" .. S(util.TableToJSON(pools)) .. " WHERE id=" .. S(id))
    s.specBet = {round = id, scope = scope, choice = chosen.id, label = chosen.name, mode = market.title, stake = stake, alias = alias}
    return -stake
end
function D.Reconcile(s, scope)
    local b = s.specBet
    if not b or scope ~= b.scope then return 0 end
    local r = A.RoundRow(b.round)
    if r and (r.status == "open" or r.status == "locked") then return 0 end
    local pools = r and util.JSONToTable(r.pools, false, true) or {}
    local total, sides = 0, 0
    for _, value in pairs(pools) do total = total + value; if value > 0 then sides = sides + 1 end end
    local payout, reason = 0, "Lost"
    if not r or r.status == "void" or sides < 2 or not pools[r.winner] then payout, reason = b.stake, "No contest - stake returned"
    elseif r.winner == b.choice then payout, reason = math.floor(b.stake * total / pools[b.choice]), "Winning ticket" end
    local entry = {account = s.account, game = b.mode .. " · " .. b.label, result = reason, time = os.time(), players = {{name = b.alias or "Bettor", delta = payout - b.stake}}}
    -- No main-world nickname/account or result goes into this audience's ledger.
    Q("INSERT INTO zc_arcade_specdm_ledger(scope,entry) VALUES (" .. S(scope) .. "," .. S(util.TableToJSON(entry)) .. ")")
    s.specHistory = s.specHistory or {}; table.insert(s.specHistory, 1, {scope = scope, game = entry.game, result = reason, delta = payout - b.stake, time = entry.time})
    while #s.specHistory > 12 do table.remove(s.specHistory) end
    s.specBet = nil
    return payout
end
function D.Ledger(scope)
    local rows = {}
    for _, row in ipairs(Q("SELECT id,entry FROM zc_arcade_specdm_ledger WHERE scope=" .. S(scope) .. " ORDER BY id DESC LIMIT 40") or {}) do
        local entry = util.JSONToTable(row.entry, false, true); entry.account = nil
        entry.id = "S-" .. util.SHA256(scope .. ":" .. row.id):sub(1, 8); rows[#rows + 1] = entry
    end
    return rows
end
-- The owner MUST check this before a bettor joins/changes a participating roster.
function D.HasTicket(account)
    A.Storage()
    local rows = Q("SELECT state FROM zc_arcade_sessions WHERE steamid=" .. S(account))
    local s = rows and util.JSONToTable(rows[1].state, false, true)
    return s and s.specBet ~= nil or false
end
function D.PrepareExit(ply)
    -- Best effort while the old audience is authorized; this is NOT permission
    -- to delay/veto a round-owner return. Failure retains the durable obligation.
    -- Proceed with gameplay transition and never flush its result in the new world.
    if not scopeValid(A.ArcadeAudience(ply)) then return nil, "Authorize the existing SpecDM audience before settlement." end
    local result, err = A.Transaction(ply)
    if not result then return nil, err end
    if result.state.specBet then return nil, "SpecDM ticket is still pending; settle or void its event before exit." end
    return true
end
function D.Sweep()
    if not D.storageReady then return end
    -- A missed lock is a no-contest, never permission to accept late wagers.
    Q("UPDATE zc_arcade_rounds SET status='void' WHERE mode='specdm' AND ((status='open' AND id IN (SELECT id FROM zc_arcade_specdm WHERE closes<=" .. os.time() .. ")) OR (status='locked' AND id IN (SELECT id FROM zc_arcade_specdm WHERE resultby<=" .. os.time() .. ")))")
end
function D.Transition(ply)
    -- Call synchronously at the domain boundary, before exposing the new world.
    -- The SpecDM client owner must clear retained app panels and await its own
    -- generation ACK; this server push is not proof that the client cleared them.
    A.Send(ply, nil, "Arcade audience changed. Refresh inside your current world.")
end
