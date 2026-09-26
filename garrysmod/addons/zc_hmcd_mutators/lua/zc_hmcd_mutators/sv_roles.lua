-- Queues are server-only and consumed only after a successful matching mutation start.
local M = ZC_HMCD_MUTATORS
M.roles = {}
local function key(s) return type(s) == "string" and #s <= 40 and s:match("^[a-z][a-z0-9_]*$") end
local function identity(ply)
    if not IsValid(ply) or not ply.SteamID64 then return end
    local id = ply:SteamID64()
    if type(id) == "string" and #id == 17 and id:match("^%d+$") then return id end
end
M.RolePlayerID = identity
function M:RegisterSpecialRole(def)
    assert(type(def) == "table" and key(def.ID) and not self.roles[def.ID], "invalid or duplicate special role")
    assert(self.definitions[def.Mutator] and type(def.Title) == "string" and #def.Title <= 80 and type(def.Eligible) == "function", "invalid special role definition")
    assert(table.Count(self.roles) < 32, "special role limit reached")
    self.roles[def.ID] = def
end
function M:QueueSpecialRole(id, steamID)
    local def = self.roles[id]
    if not def then return false, "Unknown special role." end
    if steamID == "none" then self.rolePicks[id] = nil; return true, def.Title .. " pick cleared; selection is random." end
    if type(steamID) ~= "string" or #steamID ~= 17 or not steamID:match("^%d+$") then return false, "Use a connected player SteamID64 or none." end
    for _, ply in ipairs(player.GetAll()) do
        if identity(ply) == steamID then
            self.rolePicks[id] = {steamID = steamID, name = ply:Nick():sub(1, 128)}
            return true, "Queued " .. def.Title .. " player. Queue its mutation separately; eligibility is checked at round start."
        end
    end
    return false, "Select a connected player by SteamID64."
end
function M:SpecialRoleCandidates(id, participants)
    local def, out = self.roles[id], {}
    if not def then return out, "Unknown special role." end
    local pick = self.rolePicks[id]
    local connected = false
    for _, ply in ipairs(player.GetAll()) do if pick and identity(ply) == pick.steamID then connected = true end end
    if pick and not connected then return out, "Queued player is disconnected; pick retained." end
    for _, ply in ipairs(participants or self:Players()) do
        if not pick or identity(ply) == pick.steamID then
            local ok, eligible = xpcall(function() return def.Eligible(ply) end, debug.traceback)
            if not ok then self:Log(id .. " role eligibility error: " .. tostring(eligible)) end
            if ok and eligible then out[#out + 1] = ply end
        end
    end
    return out, #out > 0 and "eligible now; rechecked at activation" or (pick and "Queued player is ineligible now; pick retained." or "No eligible recipient now.")
end
function M:SelectSpecialRole(ctx, id, subset)
    assert(ctx:Valid() and self.roles[id] and self.roles[id].Mutator == ctx.definition.ID, "role does not belong to this mutation")
    local participants = ctx.participants
    if subset then
        local allowed, filtered = {}, {}
        for _, ply in ipairs(subset) do allowed[ply] = true end
        for _, ply in ipairs(participants) do if allowed[ply] then filtered[#filtered + 1] = ply end end
        participants = filtered
    end
    local candidates, reason = self:SpecialRoleCandidates(id, participants)
    if #candidates == 0 then error(reason) end
    local selected = candidates[math.floor(self:Random() * #candidates) + 1]
    ctx.roleSelections = ctx.roleSelections or {}
    ctx.roleSelections[id] = self.rolePicks[id] -- nil for random; never clear a newer staff selection.
    return selected
end
function M:CommitSpecialRoles(ctx)
    for id, pick in pairs(ctx.roleSelections or {}) do
        if self.rolePicks[id] == pick then self.rolePicks[id] = nil end
    end
end
