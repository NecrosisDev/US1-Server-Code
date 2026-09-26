-- Cosmetic adapter to the existing fart sound; does not generate fart events.
local VERSION="20260919.puff2"
local MESSAGE="ZCFartPuffV1"
local READY="ZCFartPuffReadyV1"
local SOUND="snd_jack_hmcd_fart.wav"
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function validPos(v)return isvector(v) and finite(v.x) and finite(v.y) and finite(v.z) end
if SERVER then
    AddCSLuaFile("autorun/zc_fart_puff.lua")
    util.AddNetworkString(MESSAGE);util.AddNetworkString(READY)
    local F=ZCFartPuff or {};ZCFartPuff=F;F.Version=VERSION
    F.last=F.last or setmetatable({},{__mode="k"})
    F.ready=F.ready or setmetatable({},{__mode="k"})
    F.stats=F.stats or {sent=0,limited=0,errors=0}
    F.epoch=(F.epoch or 0)+1;F.window=0;F.count=0
    function F.IsSound(s)
        if type(s)~="string" then return false end
        s=s:lower():gsub("\\","/"):gsub("^[%)%^%*%@%#]+",""):gsub("^sound/","")
        return s==SOUND
    end
    function F.Position(ent)
        local body=ent
        if ent:IsPlayer() and ZCityPoop and type(ZCityPoop.Body)=="function" then
            local b=ZCityPoop.Body(ent);if IsValid(b) then body=b end
        end
        local pos;local bone=body:LookupBone("ValveBiped.Bip01_Pelvis")
        if bone and bone>=0 then local m=body:GetBoneMatrix(bone);if m then pos=m:GetTranslation() end end
        pos=pos or body:WorldSpaceCenter()-Vector(0,0,8)
        local dir=-body:GetForward();return body,pos+dir*7,dir
    end
    function F.Error(err)
        F.stats.errors=F.stats.errors+1
        if F.logged then return end;F.logged=true
        ErrorNoHalt("[FartPuff] "..tostring(err).."\n")
    end
    function F.Handle(data)
        if not IsValid(data.Entity) or (data.Volume or 1)<=0 then return end
        if bit.band(data.Flags or 0,SND_STOP or 4)~=0 then return end
        local body,pos,dir=F.Position(data.Entity)
        if not IsValid(body) or not validPos(pos) or not validPos(dir) then return end
        local now=CurTime();local previous=F.last[body]
        if previous and now>=previous and now-previous<0.2 then F.stats.limited=F.stats.limited+1;return end
        if now<F.window or now-F.window>=1 then F.window=now;F.count=0 end
        if F.count>=24 then F.stats.limited=F.stats.limited+1;return end
        F.last[body]=now;F.count=F.count+1;local epoch=F.epoch
        -- Send after the sound callback, without disturbing an in-progress net message.
        timer.Simple(0,function()
            if F.epoch~=epoch then return end
            local ok,err=pcall(function()
                net.Start(MESSAGE,true);net.WriteVector(pos);net.WriteNormal(dir);net.SendPVS(pos)
                F.stats.sent=F.stats.sent+1
            end)
            if not ok then F.Error(err) end
        end)
    end
    function F.OnSound(data)
        if not F.IsSound(data.SoundName) and not F.IsSound(data.OriginalSoundName) then return end
        local ok,err=pcall(F.Handle,data);if not ok then F.Error(err) end
        -- No return value: never cancel or modify any sound.
    end
    hook.Add("EntityEmitSound","ZCFartPuff_Sound",F.OnSound,HOOK_MONITOR_HIGH or -2)
    local function reset()F.epoch=F.epoch+1;F.last=setmetatable({},{__mode="k"})end
    hook.Add("ZB_EndRound","ZCFartPuff_Reset",reset)
    hook.Add("PostCleanupMap","ZCFartPuff_Reset",reset)
    hook.Add("PlayerDisconnected","ZCFartPuff_Forget",function(p)F.ready[p]=nil;F.last[p]=nil end)
    net.Receive(READY,function(bits,p)
        if bits~=10 or not IsValid(p) or p:IsBot() then return end
        if net.ReadUInt(8)~=2 then return end
        local mode=net.ReadUInt(2)
        F.ready[p]=mode==1 and "spitter_v2" or mode==2 and "compatibility_puff_v2" or "unavailable_v2"
    end)
    return
end
if not CLIENT then return end
local old=ZCFartPuffClient
if old and type(old.Reset)=="function" then old.Reset() end
local V={Version=VERSION,active={},MaxActive=12,EmitSeconds=0.18,Lifetime=1.5,errors=0,fallbacks=0}
ZCFartPuffClient=V
local PCF="particles/antlion_worker.pcf"
local PARTICLE="antlion_spit_trail"
V.hasFile=file.Exists(PCF,"GAME")
V.hasNoEntity=type(CreateParticleSystemNoEntity)=="function"
V.hasEntity=type(CreateParticleSystem)=="function"
V.native=V.hasFile and (V.hasNoEntity or V.hasEntity)
if V.native then
    local ok,err=pcall(function()game.AddParticles(PCF);PrecacheParticleSystem(PARTICLE)end)
    V.native=ok;V.nativeError=not ok and tostring(err) or nil
end
local fallbackMaterial="particle/particle_smokegrenade"
local mat=Material(fallbackMaterial)
V.fallback=type(ParticleEmitter)=="function" and mat~=nil and not mat:IsError()
V.available=V.native or V.fallback
V.mode=V.native and "spitter" or V.fallback and "compatibility_puff" or "unavailable"
if not V.available then ErrorNoHalt("[FartPuff] Neither native particles nor the stock puff renderer is available.\n") end
local function stop(s,remove)
    if IsValid(s.fx) then s.fx:StopEmission(false,remove,false) end
    if remove and s.particles and CurTime()-s.born<0.7 then
        for _,p in ipairs(s.particles) do pcall(p.SetDieTime,p,0) end
    end
end
function V.Reset()
    for _,s in ipairs(V.active) do stop(s,true) end;V.active={}
end
function V.Fallback(pos,dir)
    if not V.fallback then return end
    local emitter=ParticleEmitter(pos,false);if not IsValid(emitter) then return end
    local particles={}
    for i=1,8 do
        local p=emitter:Add(fallbackMaterial,pos)
        if p then
            p:SetVelocity(dir*18+VectorRand()*9);p:SetLifeTime(0);p:SetDieTime(0.7)
            p:SetStartAlpha(90);p:SetEndAlpha(0);p:SetStartSize(2);p:SetEndSize(10)
            p:SetRoll(math.Rand(-math.pi,math.pi));p:SetRollDelta(math.Rand(-1,1))
            p:SetColor(125,145,65);p:SetAirResistance(35);p:SetGravity(Vector(0,0,6))
            p:SetCollide(false);particles[#particles+1]=p
        end
    end
    emitter:Finish()
    if #particles>0 then V.fallbacks=V.fallbacks+1;return {particles=particles,born=CurTime()} end
end
function V.Puff(pos,dir)
    if not V.available or not validPos(pos) or not validPos(dir) then return false end
    while #V.active>=V.MaxActive do stop(table.remove(V.active,1),true) end
    local s
    if V.native then
        local ok,fx=pcall(function()
            if V.hasNoEntity then return CreateParticleSystemNoEntity(PARTICLE,pos,dir:Angle()) end
            local f=CreateParticleSystem(game.GetWorld(),PARTICLE,PATTACH_WORLDORIGIN,0,pos)
            if IsValid(f) then f:SetControlPoint(0,pos);f:SetControlPoint(1,pos) end
            return f
        end)
        if ok and IsValid(fx) then s={fx=fx,born=CurTime()}
        else
            V.native=false;V.nativeError=tostring(fx);V.mode=V.fallback and "compatibility_puff" or "unavailable"
            V.available=V.fallback
            if V.ReportReady then V.ReportReady() end
        end
    end
    s=s or V.Fallback(pos,dir)
    if not s then
        V.errors=V.errors+1
        if V.errors==1 then ErrorNoHalt("[FartPuff] Failed to create a native or compatibility puff.\n") end
        return false
    end
    V.active[#V.active+1]=s;return true
end
net.Receive(MESSAGE,function(bits)
    if bits>256 then return end
    V.Puff(net.ReadVector(),net.ReadNormal())
end)
function V.Tick()
    local now=CurTime()
    for i=#V.active,1,-1 do
        local s=V.active[i];local age=now-s.born
        if age<0 or age>=V.Lifetime or (s.fx and not IsValid(s.fx)) then
            stop(s,true);table.remove(V.active,i)
        elseif s.fx and age>=V.EmitSeconds and not s.stopped then
            stop(s,false);s.stopped=true
        end
    end
end
hook.Add("Think","ZCFartPuff_Expire",V.Tick)
hook.Add("PostCleanupMap","ZCFartPuff_Reset",V.Reset)
hook.Add("ShutDown","ZCFartPuff_Reset",V.Reset)
function V.ReportReady()
    if util.NetworkStringToID(READY)==0 then return end
    net.Start(READY);net.WriteUInt(2,8)
    net.WriteUInt(V.native and 1 or V.fallback and 2 or 0,2);net.SendToServer()
end
hook.Add("InitPostEntity","ZCFartPuff_Ready",V.ReportReady)
timer.Simple(1,V.ReportReady)
