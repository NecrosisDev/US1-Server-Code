-- Owns only the local falling-static and running-wind loops.
if SERVER then return end
local VERSION="20260916.2"
if ZCDeathAudio and ZCDeathAudio.Version==VERSION then return end
local previous=ZCDeathAudio
if previous and previous.Dispose then previous.Dispose() end
local A={Version=VERSION,generation=0,channels={},stats={loads=0,stale=0,resets=0},blocked=false}
local specs={fall="sound/zcity/other/fallstatic.wav",wind="sound/zcity/other/runwind.wav"}
for key,path in pairs(specs)do A.channels[key]={path=path,volume=0,target=0,rate=1,retry=0}end
local function finite(v)return isnumber(v) and v==v and v>-math.huge and v<math.huge end
local function stop(channel)
 if IsValid(channel)then channel:SetVolume(0);channel:Stop()end
end
function A.Clear()
 A.generation=A.generation+1;A.stats.resets=A.stats.resets+1
 for _,s in pairs(A.channels)do
  stop(s.station);s.station=nil;s.loading=false;s.volume=0;s.target=0;s.rate=1
 end
end
function A.Dispose()A.disposed=true;A.Clear()end
-- The invisible carrier's speed is not a human fall/run sound source.
-- All active pill forms own their own audio, including custom flying forms.
function A.PillCarrier(p)
 if not IsValid(p) then return false end
 local compat=ZCityPillCompat
 if compat and isfunction(compat.IsCarrier) and compat.IsCarrier(p) then return true end
 if pk_pills and isfunction(pk_pills.getMappedEnt) and IsValid(pk_pills.getMappedEnt(p)) then return true end
 if isfunction(p.GetNWEntity) and IsValid(p:GetNWEntity("zc_pill_morph")) then return true end
 return isfunction(p.GetNWBool) and p:GetNWBool("zc_pill_spawning",false) or false
end

function A.Subject()
 local p=LocalPlayer()
 if not IsValid(p) or not p:Alive() or not p.organism or p.organism.otrub then return end
 if A.PillCarrier(p) then return end
 if A.blocked or not hg or not isfunction(hg.GetCurrentCharacter)then return end
 local e=hg.GetCurrentCharacter(p);if not IsValid(e)then return end
 return p,e
end
function A.Ensure(s)
 if IsValid(s.station) or s.loading or RealTime()<s.retry then return end
 local generation=A.generation;s.loading=true;A.stats.loads=A.stats.loads+1
 sound.PlayFile(s.path,"noplay noblock",function(channel,code,message)
  if A.disposed or generation~=A.generation or not A.Subject() then
   stop(channel);A.stats.stale=A.stats.stale+1
   if generation==A.generation then s.loading=false end
   return
  end
  s.loading=false
  if not IsValid(channel)then
   s.retry=RealTime()+5;s.lastError=tostring(message or code or "Audio unavailable");return
  end
  channel:SetVolume(0);channel:EnableLooping(true);s.station=channel;s.lastError=nil
 end)
end
function A.Evaluate(p,e)
 local velocity=e:GetVelocity();local speed=velocity:Length()
 if not finite(speed) or not finite(velocity.z) then return false,0,1 end
 local rag=e:IsRagdoll();local walking=p:GetMoveType()==MOVETYPE_WALK
 local falling=-velocity.z>700 and (rag or not p:OnGround())
  and ((rag and not e:IsConstrained()) or walking)
 local wind=speed>250 and (rag or walking) and math.Clamp(speed/1400,0,1) or 0
 return falling,wind,math.Clamp(speed/700,1,3),speed
end
function A.Think()
 local p=LocalPlayer()
 if IsValid(p)then
  if not p:Alive()then A.sawDead=true
  elseif A.sawDead then A.blocked=false;A.sawDead=false end
 end
 local player,body=A.Subject()
 if not player then
  if not A.idle then A.Clear();A.idle=true end
  return
 end
 A.idle=false
 local falling,wind,rate=A.Evaluate(player,body)
 A.channels.fall.target=falling and 1 or 0;A.channels.wind.target=wind;A.channels.wind.rate=rate
 for _,s in pairs(A.channels)do
  if s.target>0 or s.volume>0.01 then A.Ensure(s)end
  local channel=s.station
  if IsValid(channel)then
   local volume=LerpFT(0.05,s.volume,s.target)
   s.volume=finite(volume) and math.Clamp(volume,0,1) or 0
   channel:SetVolume(s.volume)
   if s.volume>0.01 then
    channel:SetPlaybackRate(s.rate)
    if channel:GetState()~=GMOD_CHANNEL_PLAYING then channel:Play()end
   elseif channel:GetState()==GMOD_CHANNEL_PLAYING then channel:Pause();channel:SetTime(0)end
  end
 end
end
function A.Move(mover)
 local p,e=A.Subject();if not p or (mover and mover~=p)then return end
 local falling,_,_,speed=A.Evaluate(p,e);if not falling then return end
 local value=1-speed/500;local angle=AngleRand(-value,value)
 Suppress(0.05)
 if e:IsRagdoll()then angle.r=0;p:SetEyeAngles(p:EyeAngles()+angle)
 else SetViewPunchAngles(angle)end
end
local function localDeath(p)
 if p~=LocalPlayer()then return end
 A.blocked=true;A.Clear();A.idle=true
end
local function localSpawn(p)
 if p~=LocalPlayer() or OverrideSpawn then return end
 A.Clear();A.blocked=false;A.sawDead=false;A.idle=true
end
local function localUnconscious(p)
 if p==LocalPlayer()then A.Clear();A.idle=true end
end
local function retire(fn)
 if not isfunction(fn)then return end
 for i=1,50 do
  local name,value=debug.getupvalue(fn,i);if not name then break end
  if name=="fallSndStation" or name=="windSndStation" then stop(value)end
 end
end
function A.Install()
 local h=hook.GetTable();local oldThink=(h.Think or {}).hg_FallSnd
 local oldMove=(h.SetupMove or {}).hg_FallSound
 for _,fn in pairs({oldThink,oldMove})do
  if isfunction(fn) and fn~=A.Think and fn~=A.Move then
   local source=debug.getinfo(fn,"S").short_src
   if not source:find("homigrad/cl_utility.lua",1,true)
    and not source:find("zc_death_audio/movement.lua",1,true) then
    A.installError="Unexpected movement-audio handler: "..source;return false
   end
  end
 end
 if oldThink~=A.Think or oldMove~=A.Move then
  retire(oldThink);retire(oldMove)
  timer.Simple(1,function()retire(oldThink);retire(oldMove)end)
 end
 hook.Add("Think","hg_FallSnd",A.Think)
 hook.Add("SetupMove","hg_FallSound",A.Move)
 hook.Add("Player_Death","ZCDeathAudio",localDeath)
 hook.Add("Player Spawn","ZCDeathAudio",localSpawn)
 hook.Add("HG_OnOtrub","ZCDeathAudio",localUnconscious)
 hook.Add("PreCleanupMap","ZCDeathAudio",A.Clear)
 hook.Add("ShutDown","ZCDeathAudio",A.Dispose)
 A.installError=nil;return true
end
ZCDeathAudio=A
hook.Add("HomigradRun","ZCDeathAudio",function()A.Install()end)
hook.Add("OnReloaded","ZCDeathAudio",function()A.Install()end)
A.Install()
timer.Simple(0,function()if not A.disposed then A.Install()end end)
