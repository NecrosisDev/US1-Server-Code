-- Server-only, shared by explosion fragment producers. One coroutine resume
-- handles at most one fragment candidate. Blast damage and effects stay outside.
if not SERVER then return end
local version = "20260920.1"
local name = "ZCExplosionFragments20260920"
if _G[name] then
    assert(_G[name].version == version, "Explosion fragment scheduler version changed")
    return _G[name]
end

local state = {version=version, stats={pending=0, completed=0, cancelled=0, failed=0, resumes=0}}
local owners = {}
local first, last
local generation, lastTick = 0, nil
local running, stopped = false, false
local BUDGET, LIMIT, PER_JOB, QUANTUM = 0.002, 128, 64, 8

local function push(job)
    job.next = nil
    if last then last.next = job else first = job end
    last = job
end

local function pop()
    local job = first
    first = job.next
    if not first then last = nil end
    job.next = nil
    return job
end

local function release(job, reason)
    if owners[job.owner] ~= job then return end
    owners[job.owner] = nil
    state.stats.pending = state.stats.pending - 1
    state.stats[reason] = state.stats[reason] + 1
end

local function report(err)
    ErrorNoHalt("[ZCity explosion fragments] " .. tostring(err) .. "\n")
end

function state.Add(owner, co, done)
    assert(not stopped, "Explosion fragment scheduler is stopped")
    assert(IsValid(owner), "Invalid explosion fragment owner")
    assert(type(co) == "thread" and coroutine.status(co) == "suspended", "Invalid explosion fragment coroutine")
    assert(type(done) == "function", "Missing explosion fragment cleanup")
    assert(not owners[owner], "Explosion fragment owner already queued")
    local job = {owner=owner, co=co, done=done, ready=engine.TickCount()+1}
    owners[owner] = job
    state.stats.pending = state.stats.pending + 1
    push(job)
end

function state.Clear()
    generation = generation + 1
    state.stats.cancelled = state.stats.cancelled + state.stats.pending
    state.stats.pending = 0
    owners, first, last = {}, nil, nil
end

function state.Step()
    local tick = engine.TickCount()
    if stopped or running or lastTick == tick then return end
    lastTick = tick
    if not first then return end
    running = true
    local started, used, skipped = SysTime(), 0, 0
    local epoch = generation
    while first and used < LIMIT and SysTime()-started < BUDGET do
        local job = pop()
        if job.cancelled or not IsValid(job.owner) then
            release(job, "cancelled")
            skipped = 0
        elseif job.ready > tick or (job.tick == tick and job.used >= PER_JOB) then
            push(job)
            skipped = skipped + 1
            if skipped >= state.stats.pending then break end
        else
            skipped = 0
            if job.tick ~= tick then job.tick, job.used = tick, 0 end
            local finished, failed = false, false
            for _ = 1, QUANTUM do
                if used >= LIMIT or job.used >= PER_JOB or SysTime()-started >= BUDGET then break end
                used, job.used = used+1, job.used+1
                state.stats.resumes = state.stats.resumes+1
                local ok, err = coroutine.resume(job.co)
                -- A damage hook may synchronously clean up the map.
                if epoch ~= generation then running=false; return end
                if not ok then
                    failed, finished = true, true
                    report(debug.traceback(job.co, tostring(err)))
                    break
                end
                if job.cancelled or not IsValid(job.owner) then break end
                if coroutine.status(job.co) == "dead" then finished=true; break end
            end
            if job.cancelled or not IsValid(job.owner) then
                release(job, "cancelled")
            elseif finished then
                release(job, failed and "failed" or "completed")
                local ok, err = xpcall(job.done, debug.traceback)
                if not ok then report(err) end
                if epoch ~= generation then running=false; return end
            else
                push(job)
            end
        end
    end
    running = false
end

hook.Add("Tick", name, state.Step)
hook.Add("EntityRemoved", name, function(ent)
    local job = owners[ent]
    if job then job.cancelled = true end
end)
hook.Add("PreCleanupMap", name, state.Clear)
hook.Add("ShutDown", name, function() stopped=true; state.Clear() end)
_G[name] = state
return state
