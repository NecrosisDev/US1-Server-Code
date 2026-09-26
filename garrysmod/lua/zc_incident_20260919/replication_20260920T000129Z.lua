-- Read-only, incremental census. Does not invoke or replace addon callbacks.
assert(SERVER)
local id = "ZCReplicationCensus20260919"
assert(not hook.GetTable().Tick[id], "census already running")
local label = assert(ZCReplicationLabel)
local started = SysTime()
local humans, entities, organisms = player.GetHumans(), ents.GetAll(), {}
for _, org in pairs(hg.organism.list) do organisms[#organisms + 1] = org end
local r = {time=os.time(),map=game.GetMap(),tick=engine.TickInterval(),cvars={},players={},
    entities={},organisms={},visibilityHooks={},entityCount=#entities,playerCount=#humans,
    taskSeconds=0,maxTaskSeconds=0}
for _, name in ipairs({"sv_minupdaterate","sv_maxupdaterate","sv_minrate","sv_maxrate",
    "sv_parallel_sendsnapshot","sv_parallel_packentities","net_compresspackets",
    "net_compresspackets_minsize","sv_client_min_interp_ratio","sv_client_max_interp_ratio"}) do
    local cv=GetConVar(name)
    r.cvars[name]=cv and cv:GetString() or "MISSING"
end
for name, fn in pairs(hook.GetTable().SetupPlayerVisibility or {}) do
    if isfunction(fn) then
        local d=debug.getinfo(fn,"S")
        r.visibilityHooks[#r.visibilityHooks+1]={name=tostring(name),source=d.source,line=d.linedefined}
    end
end
local tasks = {}
for _, ply in ipairs(humans) do
    tasks[#tasks+1] = function()
        if not IsValid(ply) then return end
        local row={alive=ply:Alive(),rates={},pvsClass={},pvsCount=0}
        for _,name in ipairs({"cl_updaterate","cl_cmdrate","rate","cl_interp","cl_interp_ratio"}) do
            row.rates[name]=ply:GetInfo(name)
        end
        -- Proxy only: excludes AddOriginToPVS and engine transmit rules.
        for _,ent in ipairs(ents.FindInPVS(ply)) do
            local c=ent:GetClass()
            row.pvsClass[c]=(row.pvsClass[c] or 0)+1
            row.pvsCount=row.pvsCount+1
        end
        r.players[#r.players+1]=row
    end
end
for _,org in ipairs(organisms) do
    tasks[#tasks+1] = function()
        local ent=org.owner
        if not IsValid(ent) then return end
        local rf=RecipientFilter()
        rf:AddPVS(ent:GetPos())
        if ent:IsPlayer() then rf:RemovePlayer(ent) end
        r.organisms[#r.organisms+1]={class=ent:GetClass(),alive=org.alive,player=ent:IsPlayer(),
            bareRecipients=rf:GetCount(),wounds=table.Count(org.wounds or {}),arterial=table.Count(org.arterialwounds or {})}
    end
end
local ei=1
tasks[#tasks+1]=function()
    local deadline=SysTime()+0.00075
    while ei<=#entities do
        local ent=entities[ei]
        ei=ei+1
        if IsValid(ent) then
            local c=ent:GetClass()
            local row=r.entities[c] or {count=0,nwKeys=0,moving=0,physics=0,awake=0}
            r.entities[c]=row
            row.count=row.count+1
            row.nwKeys=row.nwKeys+table.Count(ent:GetNWVarTable())
            if ent:GetVelocity():LengthSqr()>1 then row.moving=row.moving+1 end
            local phys=ent:GetPhysicsObject()
            if IsValid(phys) then
                row.physics=row.physics+1
                if not phys:IsAsleep() then row.awake=row.awake+1 end
            end
            if isfunction(ent.UpdateTransmitState) and not row.transmitSource then
                local d=debug.getinfo(ent.UpdateTransmitState,"S")
                row.transmitSource={source=d.source,line=d.linedefined}
            end
        end
        if SysTime()>=deadline then return false end
    end
end
local index=1
local function finish(reason)
    hook.Remove("Tick",id)
    timer.Remove(id)
    r.elapsed=SysTime()-started
    r.reason=reason
    file.Write("zc_incident_20260919/"..label..".json",util.TableToJSON(r,false))
    print("ZC_REPLICATION_CENSUS",label,reason,r.elapsed)
end
hook.Add("Tick",id,function()
    local t=SysTime()
    local ok,result=pcall(tasks[index])
    local dt=SysTime()-t
    r.taskSeconds=r.taskSeconds+dt
    r.maxTaskSeconds=math.max(r.maxTaskSeconds,dt)
    if not ok then r.error=tostring(result) finish("error") return end
    if result~=false then index=index+1 end
    if index>#tasks then finish("complete") end
end)
timer.Create(id,20,1,function()finish("watchdog")end)
