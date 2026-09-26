-- Timed calls at bounded, explicit owner slots only. No global dispatchers.
assert(SERVER)
assert(not ZCLuaMethodSample,"method sample already active")
local label=assert(ZCLuaCostLabel)
local start=SysTime()
local id="ZCLuaMethods20260919"
local r={label=label,started=os.time(),map=game.GetMap(),rows={},states={},restored=0,drift=0}
local installed={}
local function record(row,t,...)
    local dt=(SysTime()-t)*1000
    row.calls=row.calls+1
    row.totalMs=row.totalMs+dt
    row.maxMs=math.max(row.maxMs,dt)
    return ...
end
local function install(slot,key,resolved,group)
    if not isfunction(resolved) then return end
    local info=debug.getinfo(resolved,"S")
    if info.what~="Lua" then return end
    local identity=group.." "..info.source..":"..info.linedefined
    local row=r.rows[identity]
    if not row then row={calls=0,totalMs=0,maxMs=0};r.rows[identity]=row end
    local entry={slot=slot,key=key,own=rawget(slot,key)}
    entry.wrapper=function(...) return record(row,SysTime(),resolved(...)) end
    installed[#installed+1]=entry
    slot[key]=entry.wrapper
end
-- These are plain tables reached directly by the existing Org Think callback.
for _,name in ipairs({"stamina","lungs","liver","blood","pain","metabolism","random_events","pulse"}) do
    local slot=hg.organism.module[name]
    if istable(slot) then install(slot,2,slot[2],"organism."..name) end
end
-- Bounded medical observer and droplet owners; never the global dispatchers.
local justice=ZCJusticeV3Integration
if istable(justice) then
    r.justiceEnabled=justice.enabled
    for _,name in ipairs({"MedicalMutation","MedicalState","Actor","Receiver"}) do
        install(justice,name,justice[name],"justice."..name)
    end
    if istable(justice.medical_model) then
        local model=justice.medical_model
        for _,name in ipairs({"change","wound_weights"}) do install(model,name,model[name],"medical_model."..name) end
    end
end
install(hg.organism,"BloodDroplet2",hg.organism.BloodDroplet2,"organism.BloodDroplet2")
local active=true
local function finish()
    if not active then return end
    active=false
    hook.Remove("Tick",id)
    timer.Remove(id)
    for _,entry in ipairs(installed) do
        if rawget(entry.slot,entry.key)==entry.wrapper then
            entry.slot[entry.key]=entry.own
            r.restored=r.restored+1
        else r.drift=r.drift+1 end
    end
    r.installed=#installed
    r.elapsed=SysTime()-start
    r.remaining=0
    for _,entry in ipairs(installed) do
        if rawget(entry.slot,entry.key)==entry.wrapper then r.remaining=r.remaining+1 end
    end
    ZCLuaMethodSample=nil
    file.Write("zc_incident_20260919/"..label..".json",util.TableToJSON(r,false))
    print("ZC_LUA_METHOD_COMPLETE",label,r.restored,r.drift,r.remaining)
end
ZCLuaMethodSample={finish=finish}
local nextState=start
hook.Add("Tick",id,function()
    local now=SysTime()
    if now>=nextState then
        nextState=now+1
        local alive=0
        for _,ply in ipairs(player.GetHumans()) do if ply:Alive() then alive=alive+1 end end
        r.states[#r.states+1]={at=now-start,players=#player.GetHumans(),alive=alive,organisms=table.Count(hg.organism.list),entities=ents.GetCount()}
    end
    if now-start>=20 then finish() end
end)
timer.Create(id,35,1,finish)
