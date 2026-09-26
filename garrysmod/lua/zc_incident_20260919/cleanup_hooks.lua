assert(SERVER)
if ZCIncidentHookSample then ZCIncidentHookSample.Finish() end
local own="zc_incident_20260919/hooks_sample.lua"
local found,seen={},{}
local function unwrap(fn)
    if not isfunction(fn) then return nil end
    local info=debug.getinfo(fn,"S")
    if not info or not info.source:find(own,1,true) then return nil end
    for i=1,20 do
        local name,value=debug.getupvalue(fn,i)
        if not name then break end
        if name=="fn" and isfunction(value) then return value end
    end
end
local count=0
local function walk(value,path,depth)
    if depth>4 or seen[value] or (count>12000 and istable(value)) then return end
    if not isfunction(value) and not istable(value) then return end
    if value==_G or value==debug or value==package or value==hg or value==zb or value==hook then return end
    seen[value]=true count=count+1
    if isfunction(value) then
        for i=1,60 do
            local name,child=debug.getupvalue(value,i)
            if not name then break end
            local original=unwrap(child)
            if original then
                found[#found+1]=path.." upvalue:"..name
                if ZCIncidentCleanupApply then debug.setupvalue(value,i,original) end
            elseif istable(child) then walk(child,path.."/"..name,depth+1) end
        end
    else
        for key,child in pairs(value) do
            local original=unwrap(child)
            if original then
                found[#found+1]=path.." field:"..tostring(key)
                if ZCIncidentCleanupApply then value[key]=original end
            elseif istable(child) then walk(child,path.."/"..tostring(key),depth+1) end
        end
    end
end
walk(ZCORGSCHED,"ZCORGSCHED",0)
-- Remove only callbacks whose exact source is this incident's sampler.
for event,prios in pairs(hook.GetULibTable()) do
 if event=="Think" or event=="Tick" or event=="OnEntityCreated" or event=="EntityTakeDamage" or event=="OrgThink" then
    for prio,entries in pairs(prios) do
        for name,data in pairs(entries) do
            local original=unwrap(data.fn)
            if original then
                found[#found+1]="hook:"..event.."/"..tostring(name)
                if ZCIncidentCleanupApply then hook.Add(event,name,original,prio) end
            else walk(data.fn,"hook:"..event.."/"..tostring(name),0) end
        end
    end
end
end
walk(ZCORGSCHED,"ZCORGSCHED",0)
local report={applied=ZCIncidentCleanupApply or false,found=found,visited=count}
file.Write("zc_incident_20260919/cleanup_hooks.json",util.TableToJSON(report,true))
print("ZC_INCIDENT_HOOK_CLEANUP",report.applied,#found,count)
