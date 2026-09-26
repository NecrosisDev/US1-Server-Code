-- All game changes belong to a round context, including any scoped native-function wrappers.
local old = ZC_HMCD_MUTATORS
if old and old.Shutdown then old:Shutdown("addon reloaded") end
local M = {
    definitions = {}, current = nil, waiting = nil, generation = (old and old.generation or 0),
    roundIndex = old and old.roundIndex or 0, history = old and old.history or {},
    rolePicks = old and old.rolePicks or {},
    seenMode = old and old.seenMode or nil, seenStamp = old and old.seenStamp or nil,
    usedMode = old and old.usedMode or nil, usedStamp = old and old.usedStamp or nil,
    forced = old and old.forced or nil, hooks = {}, syncNext = setmetatable({}, {__mode = "k"})
}
ZC_HMCD_MUTATORS = M
local seed = old and old.rng or math.floor((SysTime() * 1000000 + os.time()) % 2147483646) + 1
M.rng = seed
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
M.Finite = finite
function M:Random()
    self.rng = (self.rng * 16807) % 2147483647
    return self.rng / 2147483647
end
function M:Log(message)
    local line = "[zc_mutators] " .. tostring(message)
    print(line)
    ServerLog(line .. "\n")
end
function M:Round()
    if not zb or type(CurrentRound) ~= "function" or not zb.modes then return end
    local mode = CurrentRound()
    if mode ~= zb.modes.hmcd or not mode or mode.name ~= "hmcd" then return end
    if not ZC_HMCD_MUTATOR_INFO.AllowedTypes[mode.Type] then return end
    return mode, mode.Type, zb.ROUND_START
end
function M:Players()
    local out = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR and ply:Alive() then out[#out + 1] = ply end
    end
    return out
end
function M:Register(def)
    assert(type(def) == "table" and type(def.ID) == "string" and def.ID:match("^[a-z][a-z0-9_]*$") and #def.ID <= 40, "invalid mutator ID")
    assert(not self.definitions[def.ID], "duplicate mutator ID")
    assert(type(def.Title) == "string" and #def.Title <= 80 and type(def.Description) == "string" and #def.Description <= 350, "invalid public description")
    assert(type(def.Types) == "table" and type(def.Start) == "function", "missing mutator implementation")
    assert(def.CombatKarmaMultiplier == nil or (finite(def.CombatKarmaMultiplier) and def.CombatKarmaMultiplier >= 0 and def.CombatKarmaMultiplier <= 1), "invalid combat karma multiplier")
    def.enabled = CreateConVar("zc_mutator_" .. def.ID .. "_enabled", "1", FCVAR_ARCHIVE, "Allow " .. def.Title, 0, 1)
    def.weight = CreateConVar("zc_mutator_" .. def.ID .. "_weight", tostring(def.Weight or 1), FCVAR_ARCHIVE, "Selection weight for " .. def.Title, 0, 100)
    self.definitions[def.ID] = def
end
function M:KarmaReady()
    local karma = ZCWWKARMA
    if karma and (karma.MultiplierAPI ~= 2 or type(karma.AddMultiplier) ~= "function" or type(karma.RemoveMultiplier) ~= "function") then
        return false, "Install WWKarma v1.2.0 and restart; the legacy callback conflicts with mutation karma"
    end
    return true
end
function M:Eligible(def, mode, variant, ignoreCooldown)
    if not mode then return false, "not an ordinary homicide variant" end
    local karmaReady, karmaReason = self:KarmaReady()
    if not karmaReady then return false, karmaReason end
    if not def.enabled:GetBool() then return false, "disabled" end
    if not def.Types[variant] then return false, "requires another round variant" end
    if #self:Players() < (def.MinPlayers or 2) then return false, "not enough living participants" end
    if not ignoreCooldown and self.history[def.ID] and self.roundIndex - self.history[def.ID] <= self.cooldown:GetInt() then
        return false, "repeat cooldown"
    end
    for id, role in pairs(self.roles or {}) do
        if role.Mutator == def.ID and self.rolePicks[id] then
            local candidates, reason = self:SpecialRoleCandidates(id)
            if #candidates == 0 then return false, reason end
        end
    end
    if def.CanStart then
        local ok, allowed, reason = xpcall(function() return def.CanStart(mode, self) end, debug.traceback)
        if not ok then self:Log(def.ID .. " eligibility error: " .. tostring(allowed)); return false, "eligibility check failed" end
        if not allowed then return false, reason or "requirements not met" end
    end
    return true, "eligible"
end
function M:Sync(ply, notice)
    net.Start(ZC_HMCD_MUTATOR_INFO.Net)
    net.WriteUInt(self.generation % 4294967296, 32)
    net.WriteBool(self.current ~= nil)
    net.WriteString(self.current and self.current.definition.ID or "")
    net.WriteString(self.current and self.current.definition.Title or "")
    net.WriteString(self.current and self.current.definition.Description or "")
    net.WriteString(self.current and self.current.midRound and "mid_round" or (notice or ""))
    if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end
local Context = {}
Context.__index = Context
function Context:Valid()
    local mode, variant, stamp = M:Round()
    return not self.stopped and M.current == self and mode ~= nil and zb and zb.ROUND_STATE == 1
        and mode == self.mode and variant == self.variant and stamp == self.stamp
end
function Context:Call(fn, ...)
    if not self:Valid() then return end
    local args, count = {...}, select("#", ...)
    local ok, value = xpcall(function() return fn(self, unpack(args, 1, count)) end, debug.traceback)
    if not ok then
        M:Log(self.definition.ID .. " callback failed: " .. tostring(value))
        M:Cancel("event stopped after an error")
        return
    end
    return value
end
function Context:Cleanup(fn)
    assert(not self.stopped and type(fn) == "function", "invalid cleanup")
    self.cleanups[#self.cleanups + 1] = fn
end
function Context:Entity(ent)
    assert(IsValid(ent), "cannot track invalid entity")
    self:Cleanup(function() if IsValid(ent) then ent:Remove() end end)
    return ent
end
function Context:Timer(key, delay, repetitions, fn)
    assert(type(key) == "string" and finite(delay) and delay >= 0.05 and finite(repetitions)
        and repetitions >= 0 and repetitions == math.floor(repetitions), "invalid timer")
    local name = self.prefix .. key
    timer.Create(name, delay, repetitions, function()
        if not self:Valid() then timer.Remove(name) return end
        self:Call(fn)
    end)
    self:Cleanup(function() timer.Remove(name) end)
    return name
end
function Context:Hook(event, key, fn)
    local name = self.prefix .. key
    hook.Add(event, name, function(...)
        if self:Valid() then return self:Call(fn, ...) end
    end)
    self:Cleanup(function() hook.Remove(event, name) end)
end
function Context:SetField(target, key, value)
    local previous = target[key]
    target[key] = value
    self:Cleanup(function()
        if target[key] == value then target[key] = previous end
    end)
end
function Context:ApplyCombatKarma()
    local ready, reason = M:KarmaReady()
    assert(ready, reason)
    -- Scale the native charge before its clamp, ban check and refund ledger.
    -- Damage/harm, guilt accumulation and Pat's separate punishments stay intact.
    local scale = self.definition.CombatKarmaMultiplier
    if scale == nil then scale = 0.5 end
    local karma = ZCWWKARMA
    if karma then
        local multiplier = function() return self:Valid() and scale or 1 end
        self:Cleanup(function() karma.RemoveMultiplier("zc_mutators_combat", multiplier) end)
        karma.AddMultiplier("zc_mutators_combat", multiplier)
    else
        local previous = self.mode.GuiltCheck
        self:SetField(self.mode, "GuiltCheck", function(...)
            local multiplier, shouldBan
            if previous then multiplier, shouldBan = previous(...) end
            if self:Valid() then multiplier = (multiplier or 1) * scale end
            return multiplier, shouldBan
        end)
    end
end
function Context:Points(group)
    return M:GetPoints(group)
end
function M:Cancel(reason)
    local ctx = self.current
    local wasWaiting = self.waiting ~= nil
    self.waiting = nil
    self.current = nil -- invalidate every callback before starting cleanup
    if ctx then
        ctx.stopped = true
        if ctx.definition.Stop then
            local ok, err = xpcall(function() ctx.definition.Stop(ctx, reason) end, debug.traceback)
            if not ok then self:Log("Stop failed: " .. tostring(err)) end
        end
        for i = #ctx.cleanups, 1, -1 do
            local ok, err = xpcall(ctx.cleanups[i], debug.traceback)
            if not ok then self:Log("Cleanup failed: " .. tostring(err)) end
        end
        self:Log(ctx.definition.ID .. " ended: " .. tostring(reason))
    end
    if ctx or wasWaiting then self:Sync(nil, ctx and ("Mutator ended: " .. tostring(reason)) or "") end
end
-- Require explicit opt-in: future mutations may depend on fresh spawn state.
function M:RoundToken()
    local _, variant, stamp = self:Round()
    return tostring(stamp) .. ":" .. tostring(variant) .. ":" .. tostring(self.generation) .. ":" .. tostring(zb and zb.ROUND_STATE)
end
function M:CanActivateNow(id)
    local def = self.definitions[id]
    if not def then return false, "Unknown mutation." end
    if not def.MidRound then return false, "Round-start only: this mutation rebuilds starting classes and loadouts." end
    if not self.enabled:GetBool() then return false, "The mutation framework is disabled." end
    local mode, variant, stamp = self:Round()
    if not mode or not zb or zb.ROUND_STATE ~= 1 or not finite(stamp) then return false, "Requires an active Homicide round." end
    if self.current then return false, "A mutation is already active; mutations cannot stack." end
    if self.usedMode == mode and self.usedStamp == stamp then return false, "This round already had a mutation. Wait for the next round." end
    if self.waiting or (mode.RoleChooseRound and mode.StartRoundTime ~= nil)
        or (self.lastSpawn and CurTime() - self.lastSpawn < 0.5) then
        return false, "Wait for round selection, role choices and player spawns to finish."
    end
    if def.MidRoundRequiresUpright then
        for _, p in ipairs(self:Players()) do
            if IsValid(p.FakeRagdoll) or (p.InVehicle and p:InVehicle())
                or (p.organism and (p.organism.otrub or p.organism.incapacitated)) then
                return false, "Wait until living players are conscious, out of ragdolls and outside vehicles."
            end
        end
    end
    return self:Eligible(def, mode, variant, true)
end
function M:ActivateNow(id, actor)
    local ok, reason = self:CanActivateNow(id)
    if not ok then return false, reason end
    local mode, variant, stamp = self:Round()
    local ctx = self:Activate(self.definitions[id], mode, variant, stamp, true)
    if not ctx then return false, "Mutation setup failed; check the server console." end
    -- Do not let a duplicate start hook subsequently roll another mutation.
    self.seenMode, self.seenStamp = mode, stamp
    self:Log("Mid-round activation by " .. tostring(actor or "server console") .. ": " .. id)
    return true, "Started " .. ctx.definition.Title .. " now. Next-round queue unchanged."
end
function M:Activate(def, mode, variant, stamp, midRound)
    self.generation = self.generation + 1
    local ctx = setmetatable({
        definition = def, mode = mode, variant = variant, stamp = stamp,
        participants = self:Players(), cleanups = {}, prefix = "zc_mut_" .. self.generation .. "_",
        started = CurTime(), midRound = midRound == true, data = {}
    }, Context)
    self.current = ctx
    ctx:Call(function(c)
        c:ApplyCombatKarma()
        if c:Valid() then def.Start(c) end
    end)
    if self.current == ctx then
        self.usedMode, self.usedStamp = mode, stamp
        self:CommitSpecialRoles(ctx)
        self.history[def.ID] = self.roundIndex
        self:Sync(nil, "Round mutator: " .. def.Title)
        self:Log("Started " .. def.ID .. " on " .. variant .. " with " .. #ctx.participants .. " participants")
        return ctx
    end
end
function M:Select(mode, variant, stamp)
    if self.forced then
        local def = self.definitions[self.forced]
        local ok, reason = false, "unknown mutator"
        if def then ok, reason = self:Eligible(def, mode, variant, true) end
        if ok then
            self.forced = nil
            self:Activate(def, mode, variant, stamp)
        else
            self:Log("Queued " .. self.forced .. " retained: " .. tostring(reason))
        end
        return -- a queued event does not cause another event to roll
    end
    if not self.auto:GetBool() then self:Log("Ordinary round: automatic selection disabled"); return end
    local pool, total = {}, 0
    local ids = {}
    for id in pairs(self.definitions) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local def = self.definitions[id]
        if self:Eligible(def, mode, variant, false) and def.weight:GetFloat() > 0 then
            total = total + def.weight:GetFloat()
            pool[#pool + 1] = {def = def, limit = total}
        end
    end
    if total == 0 then self:Log("Ordinary round: no eligible mutators"); return end
    if self:Random() >= self.chance:GetFloat() then self:Log("Ordinary round: chance roll"); return end
    local roll = self:Random() * total
    for _, item in ipairs(pool) do
        if roll < item.limit then self:Activate(item.def, mode, variant, stamp); return end
    end
end
function M:Begin()
    local mode, variant, stamp = self:Round()
    if not mode or zb.ROUND_STATE ~= 1 then self:Cancel("unsupported round"); return end
    -- The same start hook may be fired twice by another addon; never roll twice.
    if self.seenMode == mode and self.seenStamp == stamp then return end
    self:Cancel("new round")
    self.seenMode, self.seenStamp = mode, stamp
    if not self.enabled:GetBool() then return end
    self.roundIndex = self.roundIndex + 1
    self.waiting = {mode = mode, variant = variant, stamp = stamp, since = CurTime()}
    self.lastSpawn = CurTime()
end
function M:Tick()
    if not self.current and not self.waiting then return end
    if (self.current or self.waiting) and not self.enabled:GetBool() then self:Cancel("framework disabled"); return end
    local mode, variant, stamp = self:Round()
    if self.current and not self.current:Valid() then self:Cancel("round changed"); return end
    local pending = self.waiting
    if not pending then return end
    if not mode or zb.ROUND_STATE ~= 1 or mode ~= pending.mode or variant ~= pending.variant or stamp ~= pending.stamp then
        self:Cancel("round changed before activation"); return
    end
    if CurTime() - pending.since > self.timeout:GetFloat() then self:Cancel("round readiness timed out"); self:Log("Round readiness timed out"); return end
    if mode.RoleChooseRound and mode.StartRoundTime ~= nil then return end
    if CurTime() - self.lastSpawn < 0.5 then return end
    self.waiting = nil
    self:Select(mode, variant, stamp)
end
function M:AddHook(event, fn)
    local id = "zc_hmcd_mutators"
    hook.Add(event, id, fn)
    self.hooks[#self.hooks + 1] = {event, id}
end
function M:Shutdown(reason)
    if self.StopPhonePreview then self:StopPhonePreview() end
    self:Cancel(reason)
    timer.Remove("zc_hmcd_mutators_tick")
    for _, pair in ipairs(self.hooks) do hook.Remove(pair[1], pair[2]) end
end
function M:Start()
    self.enabled = CreateConVar("zc_mutators_enabled", "1", FCVAR_ARCHIVE, "Enable the homicide mutator framework", 0, 1)
    self.auto = CreateConVar("zc_mutators_auto", "0", FCVAR_ARCHIVE, "Automatically roll homicide mutators", 0, 1)
    self.chance = CreateConVar("zc_mutators_chance", "0.25", FCVAR_ARCHIVE, "Chance per eligible round", 0, 1)
    self.cooldown = CreateConVar("zc_mutators_cooldown", "2", FCVAR_ARCHIVE, "Eligible rounds before a mutator may repeat", 0, 20)
    self.timeout = CreateConVar("zc_mutators_ready_timeout", "90", FCVAR_ARCHIVE, "Seconds to wait for role selection/spawns", 5, 300)
    util.AddNetworkString(ZC_HMCD_MUTATOR_INFO.Net)
    self:AddHook("ZB_StartRound", function() self:Begin() end)
    self:AddHook("ZB_EndRound", function() self:Cancel("round ended") end)
    self:AddHook("ZB_PreRoundStart", function() self:Cancel("round preparation") end)
    self:AddHook("PreCleanupMap", function() self:Cancel("map cleanup") end)
    self:AddHook("PostCleanupMap", function() self:Cancel("map cleanup") end)
    self:AddHook("PlayerSpawn", function(ply)
        self.lastSpawn = CurTime()
        local ctx = self.current
        if ctx and ctx.definition.PlayerSpawn then ctx:Call(ctx.definition.PlayerSpawn, ply) end
    end)
    self:AddHook("PlayerDeath", function(ply, inflictor, attacker)
        local ctx = self.current
        if ctx and ctx.definition.PlayerDeath then ctx:Call(ctx.definition.PlayerDeath, ply, inflictor, attacker) end
    end)
    self:AddHook("PlayerDisconnected", function(ply)
        self.syncNext[ply] = nil
        local ctx = self.current
        if ctx and ctx.definition.PlayerDisconnected then ctx:Call(ctx.definition.PlayerDisconnected, ply) end
    end)
    net.Receive(ZC_HMCD_MUTATOR_INFO.Net, function(len, ply)
        if len ~= 0 or not IsValid(ply) or (self.syncNext[ply] or 0) > CurTime() then return end
        self.syncNext[ply] = CurTime() + 5
        self:Sync(ply)
    end)
    timer.Create("zc_hmcd_mutators_tick", 0.25, 0, function() self:Tick() end)
    self:Sync()
    self:Log("v" .. ZC_HMCD_MUTATOR_INFO.Version .. " loaded; auto=" .. self.auto:GetInt() .. ". Waiting for the next round start.")
end

