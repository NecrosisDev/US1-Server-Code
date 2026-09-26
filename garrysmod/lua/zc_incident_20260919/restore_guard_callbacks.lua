assert(SERVER)
local function up(fn,wanted)
    if not isfunction(fn) then return end
    for i=1,40 do
        local name,value=debug.getupvalue(fn,i)
        if not name then return end
        if name==wanted then return value end
    end
end
local function original(fn)
    for _=1,6 do
        if not isfunction(fn) then return end
        local source=debug.getinfo(fn,"S").source
        if source:find("zc_incident_20260919/hooks_sample.lua",1,true) then return up(fn,"fn") end
        fn=up(fn,"previous")
    end
end
local restored={}
local t=hook.GetTable().EntityTakeDamage
local c=ZCityPillCompat
for priority,entries in pairs(hook.GetULibTable().EntityTakeDamage) do
    for name,data in pairs(entries) do
        local baseline=original(data.fn)
        if baseline then
            local source=debug.getinfo(baseline,"S").source
            assert(source:find("zcity_pillpack_compat.lua",1,true),"unexpected baseline owner")
            local previous=assert(up(baseline,"previous"),"missing original guard callback")
            local record=assert(c.wraps[t][name])
            assert(record.wrapper==data.fn,"guard changed during cleanup")
            hook.Add("EntityTakeDamage",name,baseline,priority)
            record.wrapper,record.original=baseline,previous
            if name=="homigrad-damage" then
                assert(debug.getinfo(previous,"S").source:find("zc_ff_brain.lua",1,true))
                local bridge=assert(ZCityFFBrain.nativeBridge)
                bridge.wrapper,bridge.original=previous,assert(up(previous,"previous"))
            end
            restored[#restored+1]=name
        end
    end
end
file.Write("zc_incident_20260919/guard_restore.json",util.TableToJSON({restored=restored},true))
print("ZC_INCIDENT_GUARDS_RESTORED",#restored)
