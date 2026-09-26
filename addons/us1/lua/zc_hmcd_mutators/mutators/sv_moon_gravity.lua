-- Engine console writes are queued. Keep the lease through their acknowledgements,
-- including cancellation/reload, so an old queued write cannot escape cleanup.
local M = ZC_HMCD_MUTATORS
local GRAVITY = 600 * 0.3
local COMMAND = "zc_moon_gravity_internal"
ZC_HMCD_MOON_GRAVITY_STATE = ZC_HMCD_MOON_GRAVITY_STATE or {serial = 0}
local state = ZC_HMCD_MOON_GRAVITY_STATE
local function copy(v) return Vector(v.x, v.y, v.z) end
local function same(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
local function Requirements()
    local cv = GetConVar("sv_gravity")
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
    local lease = state.lease
    if lease and args[1] == lease.token then lease.dispatch(args[2]) end
end, nil, "Internal (Moon Gravity mutator): server-console acknowledgement of a gravity change.")
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
        state.serial = state.serial + 1
        local lease = {token = tostring(state.serial), phase = "queued", owns = true}
        state.lease = lease
        local callback = ctx.prefix .. "moon_gravity"
        local function release()
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
            if tonumber(new) ~= expected then lease.owns = false end
        end, callback)
        lease.dispatch = function(action)
            if state.lease ~= lease then return end
            if action == "apply" and lease.phase == "queued" then
                if not ctx:Valid() then release(); return end
                if not lease.owns or cv:GetFloat() ~= previous then
                    release(); ctx:Call(function() error("Gravity changed before activation") end); return
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
