-- Staff operations bridge. Explicit actions only; no arbitrary console/Lua execution.
if not SERVER then return end
AddCSLuaFile("traitor_admin/cl_staff.lua")
util.AddNetworkString("traitoradmin_staff_action")
util.AddNetworkString("traitoradmin_staff_data")
local enqueue = include("traitor_admin/sv_requests.lua")(0.2)
local groups = setmetatable({}, {__mode="k"})
local pointPages = setmetatable({}, {__mode="k"})
ZC_TRAITOR_STAFF = ZC_TRAITOR_STAFF or {frozen=setmetatable({}, {__mode="k"})}
local S=ZC_TRAITOR_STAFF
local bundles={t={"HMCD_TDM_T","HMCD_CRI_T","RIOT_TDM_RIOTERS"},ct={"HMCD_TDM_CT","HMCD_CRI_CT","RIOT_TDM_LAW"}}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function num(v,lo,hi) local n=tonumber(v); if finite(n) and n>=lo and n<=hi then return n end end
local function current() return CurrentRound and CurrentRound() end
local function admin(p) return IsValid(p) and (p:IsAdmin() or p:IsSuperAdmin()) end
local function mapPath(id) return "zbattle/mappoints/"..game.GetMap().."/"..id..".json" end
local function validGroup(id) return type(id)=="string" and #id<=80 and id:match("^[%w_]+$") and zb and zb.Points and zb.Points[id] end
local function writeFile(path,raw)
    file.Write(path,raw)
    return file.Read(path,"DATA")==raw
end
local function persist(path,raw)
    if type(raw)~="string" then return false end
    local before=file.Read(path,"DATA")
    if writeFile(path,raw) then return true end
    if before then writeFile(path,before) else file.Delete(path) end
    return false
end
local function rotations()
    local rows,seen={},{}
    for id,m in pairs(zb and zb.modes or {}) do
        local entries=type(m.Types)=="table" and m.Types or {[id]=m}
        for key,def in pairs(entries) do
            if type(def)=="table" and type(key)=="string" then
                local k=key=="fear_soe" and "fear" or key
                if not seen[k] then
                    seen[k]=true
                    local weight=(zb.ModesChances or {})[k]
                    if weight==nil then weight=k=="fear" and 0.03 or def.Chance or m.Chance or 0.1 end
                    local effective=weight
                    if zb.GetChance then local ok,n=pcall(zb.GetChance,k); if ok and finite(n) then effective=n end end
                    rows[#rows+1]={id=k,title=k=="fear" and "Fear (shared total)" or tostring(def.PrintName or def.Name or m.PrintName or k),weight=weight,effective=effective}
                end
            end
        end
    end
    table.sort(rows,function(a,b) return a.id<b.id end)
    return rows
end
local function pointData(id)
    if not validGroup(id) or not zb.GetMapPoints then return {} end
    return zb.GetMapPoints(id) or {}
end
local function pointRevision(points) return util.CRC(util.TableToJSON(points) or "") end
-- Prepare all files before changing any group, verify writes, and roll back the
-- complete bundle on failure. Native SaveMapPoints has no success return value.
local function savePointGroups(changes)
    file.CreateDir("zbattle/mappoints/"..game.GetMap())
    local jobs={}
    for id,points in pairs(changes) do
        if not validGroup(id) then return false,"Unknown spawn group." end
        local raw=util.TableToJSON(points,true)
        if not raw or #raw>524288 then return false,"Spawn group is too large to save." end
        jobs[#jobs+1]={id=id,raw=raw,points=points,old=file.Read(mapPath(id),"DATA")}
    end
    table.sort(jobs,function(a,b) return a.id<b.id end)
    for _,job in ipairs(jobs) do
        if not writeFile(mapPath(job.id),job.raw) then
            local rollback=true
            for _,restore in ipairs(jobs) do
                if restore.old then rollback=writeFile(mapPath(restore.id),restore.old) and rollback
                else file.Delete(mapPath(restore.id)); rollback=not file.Exists(mapPath(restore.id),"DATA") and rollback end
            end
            return false,rollback and "Save failed; original spawn files restored." or "Save and rollback failed; check server storage before editing more points."
        end
    end
    for _,job in ipairs(jobs) do zb.Points[job.id].Points=job.points end
    return true,"Saved spawn points for "..#jobs.." group(s)."
end
local function release(p)
    if S.frozen[p] then if IsValid(p) then p:Freeze(false) end; S.frozen[p]=nil end
end
local function releaseAll() for p in pairs(S.frozen) do release(p) end end
hook.Add("ZB_PreRoundStart","traitoradmin_event_unfreeze",releaseAll)
hook.Add("ZB_EndRound","traitoradmin_event_unfreeze",releaseAll)
hook.Add("PostCleanupMap","traitoradmin_event_unfreeze",releaseAll)
hook.Add("PlayerSpawn","traitoradmin_event_unfreeze",release)
hook.Add("PlayerDeath","traitoradmin_event_unfreeze",release)
hook.Add("PlayerDisconnected","traitoradmin_event_unfreeze",release)
local function participants(ply)
    local out={}
    for _,p in ipairs(player.GetAll()) do if p~=ply and IsValid(p) and p:Alive() and p:Team()~=TEAM_SPECTATOR then out[#out+1]=p end end
    table.sort(out,function(a,b) return a:EntIndex()<b:EntIndex() end)
    return out
end
local function teleport(ply,tr)
    tr=tr or ply:GetEyeTrace()
    if not tr.Hit or tr.HitSky or not util.IsInWorld(tr.HitPos) then return false,"Aim at a place inside the map." end
    local targets=participants(ply)
    if #targets==0 then return false,"No living participants to teleport." end
    local spots,used={},{}
    local anchor=tr.HitPos+tr.HitNormal*8
    local offsets={}
    for x=-7,7 do for y=-7,7 do offsets[#offsets+1]={x=x,y=y} end end
    table.sort(offsets,function(a,b) return a.x*a.x+a.y*a.y < b.x*b.x+b.y*b.y end)
    for _,p in ipairs(targets) do
        if p:InVehicle() or IsValid(p.FakeRagdoll) then return false,"A participant is in a vehicle or ragdoll; get them standing first." end
        local mins,maxs=p:GetHull()
        local chosen
        for _,offset in ipairs(offsets) do
            local col,row=offset.x,offset.y
            local xy=anchor+Vector(col*72,row*72,0)
            local ground=util.TraceLine({start=xy+Vector(0,0,96),endpos=xy-Vector(0,0,192),mask=MASK_PLAYERSOLID,filter=targets})
            if ground.Hit and not ground.HitSky and ground.HitNormal.z>0.65 then
                local pos=ground.HitPos+Vector(0,0,4)
                local hull=util.TraceHull({start=pos,endpos=pos,mins=mins,maxs=maxs,mask=MASK_PLAYERSOLID,filter=targets})
                local free=util.IsInWorld(pos) and not hull.Hit and not hull.StartSolid
                for _,prior in ipairs(used) do if prior:DistToSqr(pos)<72*72 then free=false break end end
                if free then chosen=pos break end
            end
        end
        if not chosen then return false,"Not enough clear ground near your crosshair. Nobody was moved." end
        spots[p]=chosen; used[#used+1]=chosen
    end
    for _,p in ipairs(targets) do p:SetPos(spots[p]); p:SetLocalVelocity(Vector(0,0,0)) end
    return true,"Teleported "..#targets.." living participants around your crosshair."
end
local function timerRows()
    local rows={}
    local function deadline(id,label,due)
        if finite(due) and due>0 then rows[#rows+1]={id=id,title=label,left=math.max(0,due-CurTime()),kind="Round countdown",reps=1,source="ZCity round state"} end
    end
    local m=current()
    if zb and m then
        if zb.ROUND_STATE==1 then
            if finite(zb.ROUND_START) and finite(zb.ROUND_TIME) then deadline("round_limit","Round time limit (mode may override)",zb.ROUND_START+zb.ROUND_TIME) end
            if m==zb.modes.hmcd and m.saved and m.PoliceAllowed and not m.PoliceSpawned and m.Types and m.Types[m.Type] and m.Types[m.Type].PoliceAllowed then deadline("police",m.Type=="soe" and "National Guard arrival" or "Police arrival",m.saved.PoliceTime) end
            if m.RoleChooseRound then deadline("role_choice","Role selection",m.StartRoundTime) end
        end
        if zb.ROUND_STATE==3 then deadline("intermission","Round-end transition",zb.END_TIME) end
    end
    local mut=ZC_HMCD_MUTATORS
    if mut and zb and zb.ROUND_STATE==1 and mut.current and mut.current.mode==m and mut.current.stamp==zb.ROUND_START and mut.current.definition.ID=="informant" then
        local d=mut.current.data
        if not d.finished and (d.phase=="waiting" or d.phase=="between_calls") then deadline("informant_call","Informant: next call",d.due) end
        if d.phase=="ringing" then deadline("informant_answer","Informant: answer window",d.deadline) end
        if d.phase=="raising" or d.phase=="listening" then deadline("informant_phase","Informant: "..d.phase,d.transition) end
    end
    if mut and zb and zb.ROUND_STATE==1 and mut.waiting and mut.waiting.mode==m and mut.waiting.stamp==zb.ROUND_START and mut.timeout then deadline("mutation_ready","Mutation readiness timeout",mut.waiting.since+mut.timeout:GetFloat()) end
    if zb and zb.ROUND_STATE==1 and m then
        if m==zb.modes.hmcd and timer.Exists("HMCDSpawnSWAT") then
            local left=timer.TimeLeft("HMCDSpawnSWAT")
            if finite(left) then rows[#rows+1]={id="swat",title="SWAT follow-up",left=math.abs(left),paused=left<0,kind="Reinforcements"} end
        end
        if m.name=="homelanderhns" and finite(zb.ROUND_START) and zb.ROUND_START+30>CurTime() then deadline("homelander_wake","Homelander release",zb.ROUND_START+30) end
        if m==zb.modes.fear then
            deadline("fear_attack","Fear: next attack",m.saved and m.saved.KillTime)
            for key,label in pairs({NextWhisper="Whisper",NextAmbient="Ambient scare",NextSighting="Sighting",NextBlackGuy="Shadow figure",NextCharple="Charple scare",NextDoors="Door event",NextLightTheft="Light theft",NextFling="Fling",NextDoorLock="Door lock",NextBodySwap="Body swap"}) do
                if finite(m[key]) and m[key]>CurTime() then deadline("fear_"..key,"Fear: "..label,m[key]) end
            end
        end
    end
    table.sort(rows,function(a,b) return a.kind==b.kind and a.id<b.id or a.kind<b.kind end)
    return rows
end
local function send(ply,page,message)
    local d={page=page,message=message or "",map=game.GetMap(),superadmin=ply:IsSuperAdmin(),round=current() and (current().PrintName or current().name) or "None"}
    if page=="restarts" then
        local controller=ZC_RESTART_WARNING
        if controller and controller.Status and controller.Change then d.restarts=controller.Status()
        else d.restarts={available=false,error="Install restart_warning v2 to control this addon's restart schedule."} end
    elseif page=="karma" then
        local k=ZC_ADMIN_KARMA
        if k and k.Status and k.SetOwn then d.karma=k.Status(ply)
        else d.karma={available=false,error="Install the updated sv_admin_max_karma.lua to enable personal karma settings."} end
    elseif page=="modevotes" then
        local controller=ZC_MODEVOTE_WEIGHTS
        d.modevotes=controller and controller.Status and controller.Status() or {available=false,error="Install the updated sh_mode_vote.lua in admin_max_karma."}
    elseif page=="rotation" then
        d.rows=rotations()
        local fear=zb and zb.modes and zb.modes.fear
        local maps=util.JSONToTable(file.Read("fear_maps.txt","DATA") or "") or {}
        d.fearAvailable=fear~=nil; d.fearApproved=maps[game.GetMap()]==true; d.night=game.GetMap():find("night",1,true)~=nil
    elseif page=="spawns" then
        d.groups={}
        for id,entry in pairs(zb and zb.Points or {}) do if validGroup(id) then d.groups[#d.groups+1]={id=id,title=entry.Name or id,count=#pointData(id)} end end
        table.sort(d.groups,function(a,b) return a.id<b.id end)
        d.group=groups[ply] or (d.groups[1] and d.groups[1].id) or ""
        local points=pointData(d.group); d.revision=pointRevision(points); d.points={}
        d.total=#points; d.pages=math.max(1,math.ceil(#points/128))
        d.pointPage=math.min(pointPages[ply] or 1,d.pages)
        for i=(d.pointPage-1)*128+1,math.min(d.pointPage*128,#points) do
            local p=points[i]
            if p.pos and p.ang then d.points[#d.points+1]={index=i,x=p.pos.x,y=p.pos.y,z=p.pos.z,yaw=p.ang.y} end
        end
    elseif page=="events" then
        local m=zb and zb.modes and zb.modes.event
        d.available=m~=nil; d.active=m and current()==m or false
        d.title=GetGlobalString("ZB_EventName",""); d.role=GetGlobalString("ZB_EventRole","Player"); d.objective=GetGlobalString("ZB_EventObjective","")
        d.logic=m and m.EndLogicType or 2; d.loot=m and m.LootEnabled or false
        d.frozen=0; for p in pairs(S.frozen) do if IsValid(p) then d.frozen=d.frozen+1 end end
    elseif page=="timers" then d.rows=timerRows(); d.observing=true end
    net.Start("traitoradmin_staff_data"); net.WriteTable(d); net.Send(ply)
end
net.Receive("traitoradmin_staff_action",function(len,ply)
    if not admin(ply) or len>8192 then return end
    local page,action,target,value=net.ReadString(),net.ReadString(),net.ReadString(),net.ReadString()
    if not ({modevotes=true,rotation=true,spawns=true,events=true,timers=true,karma=true,restarts=true})[page] or #action>24 or #target>80 or #value>700 then return end
    local round,stamp,state=current(),zb and zb.ROUND_START,zb and zb.ROUND_STATE
    -- Capture point placement and teleport aim at receipt, not after queue delay.
    local position,facing,aim
    if page=="spawns" and (action=="add" or action=="bundle") then position=ply:GetPos(); facing=ply:EyeAngles().y end
    if page=="events" and action=="teleport" then aim=ply:GetEyeTrace() end
    enqueue(ply,function()
    if page=="events" and (action=="teleport" or action=="freeze") and
        (current()~=round or not zb or zb.ROUND_START~=stamp or zb.ROUND_STATE~=state) then
        send(ply,page,"Round changed; staging action cancelled. Try again in the current round.")
        return
    end
    local ok,message=true,""
    if action=="get" then
        if page=="spawns" and target~="" and validGroup(target) then
            groups[ply]=target
            local pageNum=num(value,1,10000)
            pointPages[ply]=pageNum and math.floor(pageNum) or 1
        end
    elseif page=="restarts" then
        local controller=ZC_RESTART_WARNING
        if not controller or not controller.Change then ok,message=false,"Updated restart_warning addon is unavailable."
        else ok,message=controller.Change(ply,action,target,value) end
    elseif page=="karma" then
        local k=ZC_ADMIN_KARMA
        if target~="" then ok,message=false,"This control only changes your own karma."
        elseif not k or not k.SetOwn then ok,message=false,"Updated admin_max_karma addon is unavailable."
        elseif action=="set" then
            local n=tonumber(value)
            if not finite(n) then ok,message=false,"Enter a valid karma number." else ok,message=k.SetOwn(ply,n) end
        elseif action=="reset" then ok,message=k.SetOwn(ply,nil)
        else ok,message=false,"Unknown karma action." end
    elseif page=="modevotes" then
        local controller=ZC_MODEVOTE_WEIGHTS
        if not controller or not controller.Change then ok,message=false,"Updated mode-vote controls are unavailable."
        else ok,message=controller.Change(ply,action,target,value) end
    elseif page=="rotation" and action=="weight" then
        local n=num(value,0,1000); local found=false
        for _,row in ipairs(rotations()) do if row.id==target then found=true end end
        if not n or not found then ok,message=false,"Invalid rotation weight."
        else
            local weights=table.Copy(zb.ModesChances or {}); weights[target]=n
            file.CreateDir("zbattle")
            local raw=util.TableToJSON(weights,true)
            ok=raw and persist("zbattle/modeschances.json",raw)
            if ok then zb.ModesChances=weights; message="Saved rotation weight. Mode eligibility still applies." else message="Could not save rotation settings." end
        end
    elseif page=="rotation" and action=="fear_map" then
        if not ply:IsSuperAdmin() then ok,message=false,"Fear map approval requires superadmin."
        elseif value~="0" and value~="1" then ok,message=false,"Invalid map setting."
        else
            local maps=util.JSONToTable(file.Read("fear_maps.txt","DATA") or "") or {}
            maps[game.GetMap()]=value=="1" and true or nil
            ok=persist("fear_maps.txt",util.TableToJSON(maps,true))
            if ok then if zb.modes.fear then zb.modes.fear.FearMaps=maps end; message="Saved Fear map approval. Night-named maps remain allowed by ZCity." else message="Could not save Fear map list." end
        end
    elseif page=="spawns" and (action=="add" or action=="bundle" or action=="remove") then
        local ids=action=="bundle" and bundles[target] or {target}
        if not ids or #ids==0 then ok,message=false,"Unknown spawn bundle."
        else
            local changes={}
            for _,id in ipairs(ids) do
                if not validGroup(id) then ok,message=false,"Missing spawn group: "..id; break end
                changes[id]=table.Copy(pointData(id))
                if action=="remove" then
                    local index,revision=value:match("^(%d+):(%d+)$"); index=tonumber(index)
                    if not index or pointRevision(changes[id])~=revision or not changes[id][index] then ok,message=false,"Points changed. Refresh and select the point again."; break end
                    table.remove(changes[id],index)
                else
                    if #changes[id]>=2048 or not util.IsInWorld(position) then ok,message=false,"Point limit reached or position outside map."; break end
                    changes[id][#changes[id]+1]={pos=position,ang=Angle(0,facing,0)}
                end
            end
            if ok then ok,message=savePointGroups(changes); if action~="bundle" then groups[ply]=target end end
        end
    elseif page=="events" and action=="teleport" then ok,message=teleport(ply,aim)
    elseif page=="events" and action=="freeze" then
        local count=0
        for _,p in ipairs(participants(ply)) do if not p:IsFrozen() then S.frozen[p]=true; p:Freeze(true); count=count+1 end end
        message="Froze "..count.." living participants."
    elseif page=="events" and action=="unfreeze" then releaseAll(); message="Released all freezes created by this menu."
    elseif page=="events" then
        local m=zb and zb.modes and zb.modes.event
        if not m then ok,message=false,"Event mode unavailable."
        elseif action=="text" and ({title=true,role=true,objective=true})[target] then
            local key=({title="ZB_EventName",role="ZB_EventRole",objective="ZB_EventObjective"})[target]
            if #value>(target=="objective" and 600 or 120) or value:find("[%z\1-\8\11\12\14-\31]") then ok,message=false,"Text is too long or contains control characters."
            else SetGlobalString(key,value); message="Updated event "..target.."." end
        elseif action=="logic" and num(value,1,3) and tonumber(value)==math.floor(tonumber(value)) then m.EndLogicType=tonumber(value); message="Updated event end conditions."
        elseif action=="loot" and (value=="0" or value=="1") then
            m.LootEnabled=value=="1"; m.LootSpawn=m.LootEnabled
            if current()==m and zb.ROUND_STATE==1 then
                concommand.Run(ply,"zb_event_loot",{value},value)
            end
            message="Event loot setting updated."
        else ok,message=false,"Unknown event action." end
    else ok,message=false,"Unknown staff action." end
    if action~="get" then print("[TraitorAdmin] "..ply:Nick().." "..page.."/"..action..": "..message) end
    send(ply,page,message)
    end,action=="get")
end)
