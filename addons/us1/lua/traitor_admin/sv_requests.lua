-- Small per-admin queues preserve ordinary clicks while bounding request work.
-- Loaded independently by each server bridge; never executes arbitrary client code.
return function(interval)
    local states=setmetatable({}, {__mode="k"})
    local function permitted(p) return IsValid(p) and (p:IsAdmin() or p:IsSuperAdmin()) end
    local function notice(p,text)
        if IsValid(p) then p:ChatPrint("[TraitorAdmin] "..text) end
    end
    local pump
    local function schedule(p,s)
        if s.scheduled then return end
        s.scheduled=true
        timer.Simple(math.max(0.01,s.nextAt-CurTime()),function()
            s.scheduled=false
            pump(p,s)
        end)
    end
    pump=function(p,s)
        if not permitted(p) then states[p]=nil; return end
        if #s.pending==0 then return end
        if CurTime()<s.nextAt then schedule(p,s); return end
        local job=table.remove(s.pending,1)
        s.nextAt=CurTime()+interval
        local ok,err=pcall(job.run)
        if not ok then
            -- A failed action may have partially completed. Never replay it.
            s.pending={}
            notice(p,"Action failed; queued actions cancelled. Refresh before trying again.")
            ErrorNoHalt("[TraitorAdmin] Request failed: "..tostring(err).."\n")
        end
        if #s.pending>0 then schedule(p,s) end
    end
    return function(p,run,readOnly)
        if not permitted(p) then return end
        local s=states[p]
        if not s then s={pending={},nextAt=0}; states[p]=s end
        local tail=s.pending[#s.pending]
        if readOnly and tail and tail.readOnly then
            -- Only consecutive unsent reads coalesce; never move a read across a write.
            tail.run=run
        elseif #s.pending<12 then
            s.pending[#s.pending+1]={run=run,readOnly=readOnly}
        else
            if (s.noticeAt or 0)<=CurTime() then
                s.noticeAt=CurTime()+1
                notice(p,"Too many pending actions; this click was not queued. Wait, then refresh.")
            end
            return
        end
        pump(p,s)
    end
end
