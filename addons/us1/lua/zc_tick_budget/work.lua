local B=assert(ZCTickBudget)
local categories={Armor="armor",attachments="attachments"}
function B.SendEquipment(e,key)
    -- Authoritative state was set synchronously. Publish its latest value only.
    if not zb or not zb.net or not zb.net.list[e] then return end
    return B.entitySender.original(e,key)
end
function B.Install()
    local meta=FindMetaTable("Entity")
    if not isfunction(meta.SendNetVar) then return false end
    if B.entitySender then
        B.networkDrift=meta.SendNetVar~=B.entitySender.wrapper
        return not B.networkDrift
    end
    local original=meta.SendNetVar
    local wrapper=function(e,key,receiver)
        local category=categories[key]
        if receiver==nil and category and B.Queue(category,e,key,B.SendEquipment) then return end
        return original(e,key,receiver)
    end
    B.entitySender={original=original,wrapper=wrapper};meta.SendNetVar=wrapper
    return true
end
function B.SendWeapons()
    if zb and zb.net and zb.net.globals then SetNetVar("weapons",zb.net.globals.weapons)end
end
function B.SyncWeapons(list)
    if not zb or not zb.net or not zb.net.globals then return SetNetVar("weapons",list)end
    zb.net.globals.weapons=list
    if not B.Queue("weapons",B,"list",B.SendWeapons)then return SetNetVar("weapons",list)end
end
function B.RunFire(e,key,argument)
    if not e.initialized or not e.parent or (not IsValid(e.parent) and not e.parent:IsWorld()) or (e.life or 0)<=0 then return end
    if e:WaterLevel()>0 then return end
    local fn=e[key];if isfunction(fn)then return fn(e,argument)end
end
function B.Fire(e,key,argument)
    if not B.enabled:GetBool() then return false end
    if B.Queue("fire",e,key,B.RunFire,argument) then return true end
    B.fireShed=(B.fireShed or 0)+1
    return true -- At capacity, shed expansion/merging work; never shed burn damage.
end
function B.InitialDelay(e,key,period)
    -- Only maintenance tasks are phased. Burning damage remains on its native timer.
    if not B.enabled:GetBool() then return 0 end
    local seen=e.ZCBudgetPhases
    if not seen then seen={};e.ZCBudgetPhases=seen end
    if seen[key]then return 0 end;seen[key]=true
    local salt=key=="fuel" and 13 or key=="life" and 29 or 43
    return ((e:EntIndex()*37+salt)%17)/17*math.min(period,0.2)
end
hook.Add("InitPostEntity","ZCityTickBudget_Install",function()B.Install()end)
hook.Add("PostGamemodeLoaded","ZCityTickBudget_Install",function()B.Install()end)
timer.Create("ZCityTickBudget_Install",2,0,function()B.Install()end)
B.Install()
