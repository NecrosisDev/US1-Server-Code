-- Engine console writes are queued. Keep the lease through their acknowledgements,
-- including cancellation/reload, so an old queued write cannot escape cleanup.
local M = ZC_HMCD_MUTATORS
local GRAVITY = 600 * 0.3
local COMMAND = "zc_moon_gravity_internal"
ZC_HMCD_MOON_GRAVITY_STATE = ZC_HMCD_MOON_GRAVITY_STATE or {serial = 0}
local state = ZC_HMCD_MOON_GRAVITY_STATE
local function copy(v) return Vector(v.x, v.y, v.z) end
local function same(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
-- This journal outlives the map's Lua state. It is written before sv_gravity.
-- Normal round rollback still uses the existing ordered write/ack protocol.
local JOURNAL = "zc_hmcd_mutators/moon_gravity_lease.json"
state.version = "20260919.maprestore1"
state.session = state.session or string.format("%d_%.0f", os.time(), SysTime() * 1000000)
local function nextToken()
    state.serial = state.serial + 1
    return state.session .. "_" .. tostring(state.serial)
end
local function vectorOK(v)
    return type(v) == "table" and M.Finite(v[1]) and M.Finite(v[2]) and M.Finite(v[3])
end
local function readJournal()
    local text = file.Read(JOURNAL, "DATA")
    if not text then return nil end
    if #text > 4096 then return false end
    local ok, record = pcall(util.JSONToTable, text)
    if not ok or type(record) ~= "table" or record.version ~= 1
        or record.applied ~= GRAVITY or not M.Finite(record.previous)
        or not vectorOK(record.physics) or type(record.token) ~= "string"
        or #record.token > 96 or not record.token:match("^[%d_]+$") then return false end
    return record
end
local function writeJournal(lease, previous, physics)
    assert(not file.Exists(JOURNAL, "DATA"), "A previous gravity recovery record still exists")
    local text = assert(util.TableToJSON({version = 1, token = lease.token,
        applied = GRAVITY, previous = previous, physics = {physics.x, physics.y, physics.z}}))
    file.CreateDir("zc_hmcd_mutators")
    file.Write(JOURNAL, text)
    assert(file.Read(JOURNAL, "DATA") == text, "Could not persist the gravity recovery record")
    lease.journal = true
end
local function clearJournal(token)
    local record = readJournal()
    if record and record.token == token then
        file.Delete(JOURNAL)
        assert(not file.Exists(JOURNAL, "DATA"), "Could not clear the gravity recovery record")
    end
end
local function queueRecovery(recovery, action, value)
    local command = value and ("sv_gravity " .. string.format("%.9g", value) .. "\n") or ""
    game.ConsoleCommand(command .. COMMAND .. " " .. recovery.token .. " " .. action .. "\n")
end
local function initializeRecovery()
    if state.lease or state.recovery or state.recoveryError then return end
    local record = readJournal()
    if record == nil then return end
    if record == false then
        state.recoveryError = "Invalid Moon Gravity recovery record; refusing to guess the original gravity"
        ErrorNoHalt("[MoonGravity] " .. state.recoveryError .. "\n")
        return
    end
    local recovery = {token = nextToken(), phase = "pending", owns = true, record = record}
    state.recovery = recovery
    local cv = GetConVar("sv_gravity")
    local applied = Vector(0, 0, -GRAVITY)
    local original = Vector(record.physics[1], record.physics[2], record.physics[3])
    local callback = "ZCMoonGravity_Recovery"
    local function finish()
        cvars.RemoveChangeCallback("sv_gravity", callback)
        clearJournal(record.token)
        if state.recovery == recovery then state.recovery = nil end
        recovery.phase = "done"
    end
    local function restorePhysics()
        local current = physenv.GetGravity()
        if same(current, applied) or same(current, Vector(0, 0, -record.previous))
            or (recovery.beforePhysics and same(current, recovery.beforePhysics)) then
            physenv.SetGravity(recovery.wantedPhysics or original)
        end
    end
    recovery.dispatch = function(action)
        if state.recovery ~= recovery or state.shuttingDown then return end
        if action == "recover" and recovery.phase == "queued" then
            local current = cv:GetFloat()
            -- A different map/admin setting wins; never blindly force 600.
            if current ~= record.applied and current ~= record.previous then finish(); return end
            recovery.beforePhysics = copy(physenv.GetGravity())
            local before = recovery.beforePhysics
            recovery.wantedPhysics = (same(before, applied) or same(before, Vector(0, 0, -record.previous)))
                and original or before
            if current == record.previous then restorePhysics(); finish(); return end
            recovery.phase = "restoring"
            cvars.AddChangeCallback("sv_gravity", function(_, old, new)
                if tonumber(old) ~= tonumber(new) and tonumber(new) ~= record.previous then recovery.owns = false end
            end, callback)
            queueRecovery(recovery, "recovered", record.previous)
        elseif action == "recovered" and recovery.phase == "restoring" then
            if recovery.owns and cv:GetFloat() == record.previous then
                restorePhysics(); finish()
            elseif not recovery.owns then finish()
            else
                recovery.phase = "failed"
                ErrorNoHalt("[MoonGravity] Restore was not acknowledged; recovery record retained\n")
            end
        end
    end
end
local function beginRecovery()
    if state.shuttingDown then return end
    initializeRecovery()
    local recovery = state.recovery
    if recovery and recovery.phase == "pending" then
        recovery.phase = "queued"
        queueRecovery(recovery, "recover")
    end
end
initializeRecovery()
hook.Add("ShutDown", "ZCMoonGravity_ShutDown", function()
    -- Do not depend on a console command executing before this Lua state is destroyed.
    -- The already-written record remains until the next map acknowledges restoration.
    state.shuttingDown = true
end)
hook.Add("InitPostEntity", "ZCMoonGravity_Recovery", beginRecovery)
timer.Simple(0, beginRecovery) -- Also supports safe reload after a pending recovery.

local function Requirements()
    local cv = GetConVar("sv_gravity")
    if state.shuttingDown or state.recovery or state.recoveryError then return false, "Gravity recovery is pending." end
    if state.lease then return false, "Waiting for the previous gravity change to finish." end
    if not cv or not game or type(game.ConsoleCommand) ~= "function" or not physenv then
        return false, "Gravity controls are unavailable."
    end
    local v = physenv.GetGravity()
    return M.Finite(cv:GetFloat()) and M.Finite(v.x) and M.Finite(v.y) and M.Finite(v.z),
        "Gravity settings must be finite."
end
-- Console-only, fixed actions and an exact active token; no client data becomes code.
-- The shared lease also lets a full framework reload finish an earlier rollback.
concommand.Add(COMMAND, function(ply, _, args)
    if IsValid(ply) then return end
    local recovery = state.recovery
    if recovery and args[1] == recovery.token then recovery.dispatch(args[2]); return end
    local lease = state.lease
    if lease and args[1] == lease.token then lease.dispatch(args[2]) end
end)
M:Register({
    ID = "moon_gravity", Title = "Moon Gravity",
    Description = "Gravity is 30% of normal for players, props and ragdolls. Combat karma loss is halved.",
    Types = {standard = true, gunfreezone = true, soe = true, wildwest = true},
    MinPlayers = 2, Weight = 1, MidRound = true, CanStart = Requirements,
    Start = function(ctx)
        local ready, reason = Requirements(); assert(ready, reason)
        local cv = GetConVar("sv_gravity")
        local previous, previousPhysics = cv:GetFloat(), copy(physenv.GetGravity())
        local applied = Vector(0, 0, -GRAVITY)
        local lease = {token = nextToken(), phase = "queued", owns = true}
        state.lease = lease
        local callback = ctx.prefix .. "moon_gravity"
        local function release()
            if lease.journal then clearJournal(lease.token) end
            cvars.RemoveChangeCallback("sv_gravity", callback)
            if state.lease == lease then state.lease = nil end
            lease.phase = "done"
        end
        local function queue(action, value)
            -- Both commands share one buffer submission, preserving write/ack order.
            local command = value and ("sv_gravity " .. string.format("%.9g", value) .. "\n") or ""
            game.ConsoleCommand(command .. COMMAND .. " " .. lease.token .. " " .. action .. "\n")
        end
        local function rollback()
            lease.cancelled = true
            if lease.phase == "queued" then release() -- no engine write submitted yet
            elseif lease.phase == "active" then
                lease.phase = "restore_queued"
                queue("restore") -- recheck after any already queued external commands
            end -- a submitted write must acknowledge before we restore it
        end
        ctx:Cleanup(rollback)
        cvars.AddChangeCallback("sv_gravity", function(_, old, new)
            if tonumber(old) == tonumber(new) then return end
            local expected = (lease.phase == "writing" and GRAVITY)
                or (lease.phase == "restoring" and previous)
            if tonumber(new) ~= expected then
                lease.owns = false
                if lease.journal then clearJournal(lease.token) end
            end
        end, callback)
        lease.dispatch = function(action)
            if state.lease ~= lease then return end
            if action == "apply" and lease.phase == "queued" then
                if state.shuttingDown or not ctx:Valid() then release(); return end
                if not lease.owns or cv:GetFloat() ~= previous then
                    release(); ctx:Call(function() error("Gravity changed before activation") end); return
                end
                local ok, err = pcall(writeJournal, lease, previous, previousPhysics)
                if not ok then
                    release(); ctx:Call(function() error(tostring(err)) end); return
                end
                lease.phase = "writing"
                queue("applied", GRAVITY)
            elseif action == "applied" and lease.phase == "writing" then
                if not lease.owns or cv:GetFloat() ~= GRAVITY then
                    release(); ctx:Call(function() error("Could not apply Moon Gravity") end); return
                end
                lease.phase = "active"
                if lease.cancelled or not ctx:Valid() then rollback(); return end
                local current = physenv.GetGravity()
                if same(current, previousPhysics) or same(current, applied) then physenv.SetGravity(applied) end
                ctx.data.gravityApplied = true
            elseif action == "restore" and lease.phase == "restore_queued" then
                if not lease.owns or cv:GetFloat() ~= GRAVITY then release(); return end
                lease.beforeRestore = copy(physenv.GetGravity())
                lease.restorePhysics = same(lease.beforeRestore, applied) and previousPhysics or lease.beforeRestore
                lease.phase = "restoring"
                queue("restored", previous)
            elseif action == "restored" and lease.phase == "restoring" then
                if lease.owns and cv:GetFloat() ~= previous then
                    ErrorNoHalt("[MoonGravity] Normal rollback was not acknowledged; recovery record retained\n")
                    return
                end
                if lease.owns and cv:GetFloat() == previous then
                    local current = physenv.GetGravity()
                    if same(current, Vector(0, 0, -previous)) or same(current, lease.beforeRestore) then
                        physenv.SetGravity(lease.restorePhysics)
                    end
                end
                release()
            end
        end
        queue("apply")
    end
})
