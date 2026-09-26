-- Cosmetic adapter to the existing fart sound; does not generate fart events.
local VERSION="20260919.puff1"
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
        if bits~=9 or not IsValid(p) or p:IsBot() or F.ready[p] then return end
        if net.ReadUInt(8)~=1 then return end
        F.ready[p]=net.ReadBool() and "loaded" or "missing_assets_or_api"
    end)
    return
end
if not CLIENT then return end
local old=ZCFartPuffClient
if old and type(old.Reset)=="function" then old.Reset() end
local V={Version=VERSION,active={},MaxActive=12,EmitSeconds=0.18,Lifetime=1.5,errors=0}
ZCFartPuffClient=V
local available=file.Exists("particles/antlion_worker.pcf","GAME") and type(CreateParticleSystemNoEntity)=="function"
local ok,err=pcall(function()
    if not available then error("particle file or CreateParticleSystemNoEntity unavailable") end
    game.AddParticles("particles/antlion_worker.pcf");PrecacheParticleSystem("antlion_spit_trail")
end)
V.available=ok
if not ok then ErrorNoHalt("[FartPuff] "..tostring(err).."\n") end
local function stop(fx,remove)
    if IsValid(fx) then fx:StopEmission(false,remove,false) end
end
function V.Reset()
    for _,s in ipairs(V.active) do stop(s.fx,true) end;V.active={}
end
function V.Puff(pos,dir)
    if not V.available or not validPos(pos) or not validPos(dir) then return false end
    while #V.active>=V.MaxActive do stop(table.remove(V.active,1).fx,true) end
    local ok,fx=pcall(CreateParticleSystemNoEntity,"antlion_spit_trail",pos,dir:Angle())
    if not ok or not IsValid(fx) then
        V.errors=V.errors+1
        if V.errors==1 then ErrorNoHalt("[FartPuff] Could not create particle system: "..tostring(fx).."\n") end
        return false
    end
    V.active[#V.active+1]={fx=fx,born=CurTime()};return true
end
net.Receive(MESSAGE,function(bits)
    if bits>256 then return end
    V.Puff(net.ReadVector(),net.ReadNormal())
end)
function V.Tick()
    local now=CurTime()
    for i=#V.active,1,-1 do
        local s=V.active[i];local age=now-s.born
        if not IsValid(s.fx) or age<0 or age>=V.Lifetime then
            stop(s.fx,true);table.remove(V.active,i)
        elseif age>=V.EmitSeconds and not s.stopped then
            stop(s.fx,false);s.stopped=true
        end
    end
end
hook.Add("Think","ZCFartPuff_Expire",V.Tick)
hook.Add("PostCleanupMap","ZCFartPuff_Reset",V.Reset)
hook.Add("ShutDown","ZCFartPuff_Reset",V.Reset)
local function ready()
    if util.NetworkStringToID(READY)==0 then return end
    net.Start(READY);net.WriteUInt(1,8);net.WriteBool(V.available);net.SendToServer()
end
hook.Add("InitPostEntity","ZCFartPuff_Ready",ready)
timer.Simple(1,ready)
