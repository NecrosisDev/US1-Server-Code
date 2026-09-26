if not SERVER then return end
local U=ZCityUrine or {}
ZCityUrine=U
U.Version="20260919.spawn1"
U.ClientVersion=2
U.PacketInterval=0.10
U.ExtinguishRadius=32
U.VFireExtinguishAmount=16
U.MaxDuration=8
U.BladderCapacity=100
U.BladderInitial=100
U.BladderFillPerSecond=100/300
U.BladderDrainPerSecond=100/8
U.BladderNetInterval=0.5
U.RestartDelay=0.5
U.Speed=190
U.Gravity=386.1
U.FlightTime=1.15
U.SimStep=0.075
U.DecalCooldown=0.18
U.MaxDecals=24
U.SoundInterval=0.8
U.StreamSound="ambient/water/water_spray1.wav"
U.StopSound="ambient/water/drip1.wav"
U.ImpactSounds={"ambient/water/water_splash1.wav","ambient/water/water_splash2.wav"}
U.active=U.active or setmetatable({},{__mode="k"})
U.bladder=U.bladder or setmetatable({},{__mode="k"})
U.ready=U.ready or setmetatable({},{__mode="k"})
U.stats=U.stats or {starts=0,stops=0,packets=0,impacts=0,decals=0,client_ready=0,errors=0}
U.logged=U.logged or {}
U.serial=U.serial or 0
AddCSLuaFile("autorun/client/zc_urine_visuals.lua")
for _,n in ipairs({"ZCUrinePacketV1","ZCUrineReadyV1"})do util.AddNetworkString(n)end
pcall(PrecacheParticleSystem,"antlion_spit_trail")
local function carrier(p)
    local P=ZCityPillCompat
    return P and ((P.spawning and P.spawning[p]) or (P.IsCarrier and P.IsCarrier(p)))
end
local function playing(p)
    if not IsValid(p) or not p:IsPlayer() or not p:Alive() or p:Team()==TEAM_SPECTATOR
        or p:GetObserverMode()~=OBS_MODE_NONE or p:InVehicle() or carrier(p)then return false end
    local org=p.organism
    return not (type(org)=="table" and (org.alive==false or org.otrub))
end
U.CanPlay=playing
function U.Error(tag,err)
    U.stats.errors=U.stats.errors+1
    if U.logged[tag]then return end
    U.logged[tag]=true
    file.CreateDir("zc_urine")
    file.Append("zc_urine/errors.txt",os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end
function U.PublishBladder(p,s,now,force)
    if not IsValid(p) or not s then return end
    if force or now>=(s.nextNet or 0)then
        s.nextNet=now+U.BladderNetInterval
        p:SetNW2Float("zc_bladder",s.value)
        p:SetNW2Float("zc_bladder_capacity",U.BladderCapacity)
    end
end
function U.ResetBladder(p,value)
    if not IsValid(p)then return end
    local now=CurTime()
    local s={value=math.Clamp(value or U.BladderInitial,0,U.BladderCapacity),
        last=now,nextNet=0}
    U.bladder[p]=s
    U.PublishBladder(p,s,now,true)
    return s
end
function U.BladderState(p,now)
    local s=U.bladder[p]
    if not s then s=U.ResetBladder(p,U.BladderInitial) end
    return s
end
function U.UpdateBladder(p,now,draining)
    if not IsValid(p) then return 0 end
    now=now or CurTime()
    local s=U.BladderState(p,now)
    if not s then return 0 end
    -- Settle elapsed time on every start/stop boundary, including delayed ticks.
    local active=draining and U.active[p]
    local untilTime=active and math.min(now,active.ends) or now
    local dt=math.Clamp(untilTime-(s.last or now),0,300)
    s.last=now
    if type(s.value)~="number" or s.value~=s.value or math.abs(s.value)==math.huge then
        s.value=0
    end
    s.value=math.Clamp(s.value,0,U.BladderCapacity)
    if draining then
        s.value=math.max(0,s.value-U.BladderDrainPerSecond*dt)
    else
        s.value=math.min(U.BladderCapacity,s.value+U.BladderFillPerSecond*dt)
    end
    U.PublishBladder(p,s,now,false)
    return s.value
end
function U.GetBladder(p)
    local s=U.bladder[p]
    return s and s.value or U.BladderInitial
end
function U.Body(p)
    local C=ZCityPoop
    if C and type(C.Body)=="function"then
        local ok,b=pcall(C.Body,p)
        if ok and IsValid(b)then return b end
    end
    if hg and type(hg.GetCurrentCharacter)=="function"then
        local ok,b=pcall(hg.GetCurrentCharacter,p)
        if ok and IsValid(b)then return b end
    end
    return p
end
function U.Source(p)
    local body=U.Body(p)
    if not IsValid(body)then return end
    local pos
    local bone=body:LookupBone("ValveBiped.Bip01_Pelvis")
    if bone and bone>=0 then
        local m=body:GetBoneMatrix(bone)
        if m then pos=m:GetTranslation()end
    end
    pos=pos or (body:WorldSpaceCenter()-Vector(0,0,12))
    local ang=p:EyeAngles()
    local dir=ang:Forward()
    pos=pos+dir*4-Vector(0,0,3)
    return pos,dir,body
end
function U.Simulate(start,velocity,filter)
    local last=start
    local down=Vector(0,0,-0.5*U.Gravity)
    for t=U.SimStep,U.FlightTime,U.SimStep do
        local pos=start+velocity*t+down*(t*t)
        local tr=util.TraceLine({start=last,endpos=pos,mask=MASK_SHOT,filter=filter})
        if tr.Hit then return t,tr end
        last=pos
    end
    return U.FlightTime,nil
end
function U.SendPacket(p,start,velocity,flight)
    U.serial=(U.serial+1)%65535
    if U.serial==0 then U.serial=1 end
    net.Start("ZCUrinePacketV1")
    net.WriteEntity(p)
    net.WriteUInt(U.serial,16)
    net.WriteVector(start)
    net.WriteVector(velocity)
    net.WriteFloat(flight)
    net.SendPVS(start)
    U.stats.packets=U.stats.packets+1
end
local function canReachFire(from,ent)
    if not IsValid(ent)then return false end
    local tr=util.TraceLine({
        start=from,
        endpos=ent:WorldSpaceCenter(),
        mask=MASK_SOLID_BRUSHONLY
    })
    return not tr.Hit and not tr.StartSolid and not tr.AllSolid
end
function U.ExtinguishImpact(p,tr)
    if not tr then return end
    local hit=tr.Entity
    if IsValid(hit)then
        if hit:IsOnFire()then hit:Extinguish() end
        if hit:IsRagdoll() and hg and type(hg.RagdollOwner)=="function"then
            local owner=hg.RagdollOwner(hit)
            if IsValid(owner) and owner:IsOnFire()then owner:Extinguish() end
        end
    end
    local origin=tr.HitPos+tr.HitNormal*2
    for _,ent in ipairs(ents.FindInSphere(tr.HitPos,U.ExtinguishRadius))do
        if IsValid(ent) and canReachFire(origin,ent)then
            local class=ent:GetClass()
            if class=="vfire" then
                if type(ent.SoftExtinguish)=="function"then
                    ent:SoftExtinguish(U.VFireExtinguishAmount)
                else
                    ent:Extinguish()
                end
            elseif class=="vfire_ball" or class=="env_fire" then
                ent:Extinguish()
            elseif ent:IsPlayer() or ent:IsRagdoll() then
                if ent:IsOnFire()then ent:Extinguish() end
                if ent:IsRagdoll() and hg and type(hg.RagdollOwner)=="function"then
                    local owner=hg.RagdollOwner(ent)
                    if IsValid(owner) and owner:IsOnFire()then owner:Extinguish() end
                end
            end
        end
    end
end
function U.Impact(p,s,tr,now)
    if not tr or tr.HitSky or tr.StartSolid or tr.AllSolid then return end
    U.ExtinguishImpact(p,tr)
    U.stats.impacts=U.stats.impacts+1
    if now>=(s.nextImpactSound or 0)then
        s.nextImpactSound=now+0.16
        sound.Play(U.ImpactSounds[math.random(#U.ImpactSounds)],tr.HitPos,50,math.random(96,104),0.35)
    end
    if s.decals<U.MaxDecals and now>=(s.nextDecal or 0)then
        s.nextDecal=now+U.DecalCooldown
        s.decals=s.decals+1
        U.stats.decals=U.stats.decals+1
        util.Decal("BeerSplash",tr.HitPos+tr.HitNormal*2,tr.HitPos-tr.HitNormal*2,p)
    end
    if bit.band(tr.Contents or 0,CONTENTS_WATER)~=0 then
        local ed=EffectData()
        ed:SetOrigin(tr.HitPos);ed:SetNormal(Vector(0,0,1));ed:SetScale(2)
        util.Effect("watersplash",ed,true,true)
    end
end
function U.Stop(p,quiet)
    local s=U.active[p]
    if not s then return false end
    if IsValid(p) then U.UpdateBladder(p,CurTime(),true) end
    U.active[p]=nil
    if IsValid(p) then p.ZCUrineNextStart=CurTime()+U.RestartDelay end
    U.stats.stops=U.stats.stops+1
    if not quiet and IsValid(p)then
        local pos=select(1,U.Source(p))
        if pos then sound.Play(U.StopSound,pos,42,math.random(98,104),0.25)end
    end
    return true
end
function U.Start(p)
    if not playing(p) or U.active[p]then return false end
    local now=CurTime()
    if now<(p.ZCUrineNextStart or 0) or now<(p.ZCUrineNextAttempt or 0)then return false end
    p.ZCUrineNextAttempt=now+U.RestartDelay
    local bladder=U.UpdateBladder(p,now,false)
    if bladder<=0.01 then
        U.stats.empty_denied=(U.stats.empty_denied or 0)+1
        if now<(p.ZCUrineNextEmptyNotice or 0) then return false end
        p.ZCUrineNextEmptyNotice=now+2
        if type(p.Notify)=="function"then
            p:Notify("My bladder is empty.",3,"zc_urine_empty",0)
        else
            p:PrintMessage(HUD_PRINTCONSOLE,"My bladder is empty.\n")
        end
        return false
    end
    local pos=select(1,U.Source(p))
    if not pos then return false end
    U.active[p]={started=now,ends=now+U.MaxDuration,nextPacket=0,nextSound=0,
        nextDecal=0,nextImpactSound=0,decals=0}
    U.stats.starts=U.stats.starts+1
    sound.Play(U.StreamSound,pos,46,100,0.22)
    return true
end
function U.Emit(p,s,now)
    if U.active[p]~=s or U.UpdateBladder(p,now,true)<=0 then U.Stop(p,true);return end
    local start,dir,body=U.Source(p)
    if not start or not IsValid(body)then U.Stop(p,true);return end
    local velocity=dir*(U.Speed*math.Rand(0.96,1.04))+VectorRand()*2.5
    local filter={p}
    if body~=p then filter[#filter+1]=body end
    local flight,tr=U.Simulate(start,velocity,filter)
    U.SendPacket(p,start,velocity,flight)
    if tr then U.Impact(p,s,tr,now)end
    if now>=s.nextSound then
        s.nextSound=now+U.SoundInterval
        sound.Play(U.StreamSound,start,46,math.random(98,102),0.18)
    end
end
function U.Tick()
    local now=CurTime()
    for p,s in pairs(U.active)do
        if not playing(p) or now>=s.ends then
            U.Stop(p)
        elseif now>=s.nextPacket then
            s.nextPacket=now+U.PacketInterval
            local ok,err=pcall(U.Emit,p,s,now)
            if not ok then U.Error("emit",err);U.Stop(p,true)end
        end
    end
end
timer.Create("ZCityUrine_Tick",0.02,0,U.Tick)
function U.BladderTick()
    local now=CurTime()
    for _,p in ipairs(player.GetAll())do
        if IsValid(p) and p:IsPlayer() and p:Alive()then
            local draining=U.active[p]~=nil
            local value=U.UpdateBladder(p,now,draining)
            if draining and value<=0 then U.Stop(p)end
        end
    end
end
timer.Create("ZCityUrine_Bladder",0.1,0,U.BladderTick)
concommand.Add("+pee",function(p)if IsValid(p)then U.Start(p)end end)
concommand.Add("-pee",function(p)if IsValid(p)then U.Stop(p)end end)
concommand.Add("pee",function(p)
    if not IsValid(p)then return end
    if U.active[p]then U.Stop(p)else U.Start(p)end
end,nil,"Toggle urination. Bind +pee for hold-to-urinate.")
local function stopOnly(p)U.Stop(p,true)end
hook.Add("PlayerDeath","ZCityUrine_Stop",stopOnly)
hook.Add("PlayerSilentDeath","ZCityUrine_Stop",stopOnly)
hook.Add("PlayerDisconnected","ZCityUrine_Stop",function(p)
    U.Stop(p,true)
    U.bladder[p]=nil
    U.ready[p]=nil
end)
hook.Add("PlayerSpawn","ZCityUrine_BladderReset",function(p)
    -- Native fake-up calls Spawn under OverrideSpawn; it is not a new life.
    if OverrideSpawn then return end
    U.Stop(p,true)
    U.ResetBladder(p,U.BladderInitial)
end)
hook.Add("ZB_EndRound","ZCityUrine_StopAll",function()
    for p in pairs(U.active)do U.Stop(p,true)end
end)
hook.Add("PostCleanupMap","ZCityUrine_StopAll",function()
    for p in pairs(U.active)do U.Stop(p,true)end
end)
function U.SendClient()
    -- Client Lua is delivered by AddCSLuaFile on join, not live code injection.
    return false
end
net.Receive("ZCUrineReadyV1",function(bits,p)
    if not IsValid(p) or p:IsBot() or bits~=8 or U.ready[p]==U.ClientVersion then return end
    if net.ReadUInt(8)~=U.ClientVersion then return end
    U.ready[p]=U.ClientVersion;U.stats.client_ready=U.stats.client_ready+1
end)
hook.Add("PlayerInitialSpawn","ZCityUrine_Client",function(p)
    timer.Simple(5,function()U.SendClient(p)end)
end)
timer.Simple(1,function()for _,p in ipairs(player.GetAll())do U.SendClient(p)end end)
