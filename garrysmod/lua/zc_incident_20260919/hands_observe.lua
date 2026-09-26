assert(SERVER)
local id="ZCLuaCostHands20260919"
assert(not hook.GetTable().Tick[id])
local start=SysTime()
local seen=setmetatable({},{__mode="k"})
local r={started=os.time(),arch=jit.arch,jitVersion=jit.version,jitEnabled=jit.status(),observations=0,
    tableReplaced=0,sameHoldReplaced=0,holdChanged=0,byHold={},states={},callbackSeconds=0}
local nextState=start
local function finish()
    hook.Remove("Tick",id)
    timer.Remove(id)
    r.elapsed=SysTime()-start
    file.Write("zc_incident_20260919/hands_observe.json",util.TableToJSON(r,false))
    print("ZC_HANDS_OBSERVE_COMPLETE",r.observations,r.sameHoldReplaced)
end
hook.Add("Tick",id,function()
    local t=SysTime()
    local count=0
    for _,ply in ipairs(player.GetHumans()) do
        local wep=ply:GetActiveWeapon()
        if IsValid(wep) and wep:GetClass()=="weapon_hands_sh" then
            count=count+1
            local hold=wep:GetHoldType()
            local old=seen[wep]
            r.observations=r.observations+1
            r.byHold[hold]=(r.byHold[hold] or 0)+1
            if old then
                if old.activity~=wep.ActivityTranslate then
                    r.tableReplaced=r.tableReplaced+1
                    if old.hold==hold then r.sameHoldReplaced=r.sameHoldReplaced+1 end
                end
                if old.hold~=hold then r.holdChanged=r.holdChanged+1 end
            else
                local info=debug.getinfo(wep.SetWeaponHoldType,"S")
                r.setter={source=info.source,line=info.linedefined}
            end
            seen[wep]={activity=wep.ActivityTranslate,hold=hold}
        end
    end
    if t>=nextState then
        nextState=t+1
        r.states[#r.states+1]={at=t-start,activeHands=count,players=#player.GetHumans()}
    end
    r.callbackSeconds=r.callbackSeconds+SysTime()-t
    if t-start>=12 then finish() end
end)
timer.Create(id,20,1,finish)
