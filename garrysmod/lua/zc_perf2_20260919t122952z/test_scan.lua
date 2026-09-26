-- Native vector/angle maths, isolated fake entities. No live gameplay actions.
return function(source)
local results={};local function noop()end
local function test(name,f)local ok,err=pcall(f);results[#results+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}end
local function setup()
 local e=setmetatable({SERVER=true,CLIENT=false,clock=1,players={},props={},timers={},hooks={},receivers={},sounds=0,messages=0,world=game.GetWorld()},{__index=_G});e._G=e
 e.ZCityPoopThrow=false;e.ZCityPillCompat=false;e.hg={}
 e.IsValid=function(x)return type(x)=='table' and x.valid==true end
 e.CurTime=function()return e.clock end
 e.AddCSLuaFile=noop;e.ErrorNoHalt=function(s)error(s)end
 e.util={AddNetworkString=noop,IsInWorld=function(v)return math.abs(v.x)<32000 and math.abs(v.y)<32000 and math.abs(v.z)<32000 end}
 e.file={CreateDir=noop,Append=noop};e.net={Start=noop,WriteUInt=noop,WriteBool=noop,WriteEntity=noop,WriteVector=noop,WriteNormal=noop,Broadcast=function()e.messages=e.messages+1 end,Receive=function(n,f)e.receivers[n]=f end}
 e.hook={Add=function(n,id,f)e.hooks[n]=e.hooks[n] or {};e.hooks[n][id]=f end}
 e.timer={Simple=function(_,f)e.timers[#e.timers+1]=f end,Create=function(n,_,_,f)e.timers[n]=f end}
 e.player={GetAll=function()e.rosterCalls=(e.rosterCalls or 0)+1;return e.players end}
 e.ZCityPoop={owned={},Scale=.75}
 local nextid=0
 local function ent(kind)
  nextid=nextid+1
  local a={valid=true,kind=kind or 'prop',id=nextid,pos=Vector(),ang=Angle(),group=COLLISION_GROUP_NONE,modelScale=.75,changes=0}
  local p={valid=true,motion=true,vel=Vector(0,0,-100),av=Vector(2,3,4),entity=a,changes=0}
  function p:EnableMotion(v)self.motion=v;self.changes=self.changes+1 end
  function p:Wake()end
  function p:IsMotionEnabled()return self.motion end
  function p:SetVelocityInstantaneous(v)self.vel=v;self.changes=self.changes+1 end
  function p:SetAngleVelocityInstantaneous(v)self.av=v;self.changes=self.changes+1 end
  function p:GetVelocity()return self.vel end
  function p:GetEntity()return self.entity end
  function p:GetPos()return self.pos or a.pos end
  function p:GetAngles()return self.ang or a.ang end
  a.phys=p
  function a:GetPhysicsObject()return self.phys end
  function a:GetPhysicsObjectCount()return self.physcount or 1 end
  function a:IsPlayer()return self.kind=='player' end
  function a:IsWorld()return self.kind=='world' end
  function a:GetCreationID()return self.id end
  function a:GetPos()if self.kind=='player' then e.playerPositionCalls=(e.playerPositionCalls or 0)+1 end;return self.pos end
  function a:GetAngles()return self.ang end
  function a:SetPos(v)self.pos=v;self.changes=self.changes+1 end
  function a:SetAngles(v)self.ang=v;self.changes=self.changes+1 end
  function a:GetModelBounds()return Vector(-5.128057,-5.029511,-.209914),Vector(5.264502,5.144992,7.800671)end
  function a:GetModelScale()return self.modelScale end
  function a:SetModelScale(v)self.modelScale=v end
  function a:GetCollisionGroup()return self.group end
  function a:SetCollisionGroup(v)self.group=v;self.changes=self.changes+1 end
  function a:CollisionRulesChanged()self.changes=self.changes+1 end
  function a:AddCallback(_,f)self.callback=f end
  function a:EmitSound()e.sounds=e.sounds+1 end
  function a:GetActiveWeapon()e.weaponQueries=(e.weaponQueries or 0)+1;return self.weapon end
  function a:Alive()return self.alive~=false end
  function a:Team()return 1 end
  function a:GetObserverMode()return OBS_MODE_NONE end
  function a:InVehicle()return self.vehicle==true end
  function a:OnGround()return self.ground==true end
  function a:GetMoveType()return self.noclip and MOVETYPE_NOCLIP or MOVETYPE_WALK end
  function a:KeyDown()return true end
  return a
 end
 local player=ent('player');player.organism={alive=true};e.players={player}
 player.weapon=ent('weapon');local w=player.weapon
 function w:GetClass()return 'weapon_hands_sh' end
 function w:GetCarrying()return self.carry end
 function w:SetCarrying(v)self.carry=v end
 function w:GetFists()return false end
 local function load()
  local f=CompileString(source,'sticky_candidate_fixture',false);assert(type(f)=='function',tostring(f));setfenv(f,e);f()
 end
 load();local T=e.ZCityPoopThrow
 local a=ent();e.ZCityPoop.owned[a]=true;a.ZCPoopWasManipulated=true;a.ZCPoopLastHolder=player;a.ZCPoopThrownUntil=7
 local wall=ent('world')
 local data={HitEntity=wall,HitPos=Vector(10,20,30),HitNormal=Vector(0,0,-1),OurOldVelocity=Vector(0,0,-100),Speed=100}
 return T,a,data,ent,e,player,load
end
test('footsteps enter, stay, leave and reenter',function()
 local t,a,d,ent,e,p=setup();p.ground=true;p.pos=Vector(0,0,0);a.pos=Vector(0,0,0)
 t.CheckStepped(a,1);assert(e.sounds==1)
 t.CheckStepped(a,1.2);assert(e.sounds==1)
 p.pos=Vector(100,0,0);t.CheckStepped(a,1.4);assert(not a.ZCPoopStepContacts[p])
 p.pos=Vector(0,0,0);t.CheckStepped(a,1.6);assert(e.sounds==2)
end)
test('grid borders and negative coordinates match naive radius test',function()
 local t,a,d,ent,e,p=setup();p.ground=true
 for _,x in ipairs({-36.1,-18,-.01,0,17.99,18,36.1})do
  for _,dx in ipairs({-18.01,-18,-10,0,10,18,18.01})do
   for _,dy in ipairs({-18,0,18})do
    a.pos=Vector(x,0,0);p.pos=Vector(x+dx,dy,0);a.ZCPoopNextStepScan=0;a.ZCPoopStepContacts=nil
    t.CheckStepped(a,2)
    local actualX,actualY=p.pos.x-a.pos.x,p.pos.y-a.pos.y
    local expected=actualX*actualX+actualY*actualY<=t.StepRadius*t.StepRadius
    assert((a.ZCPoopStepContacts[p]==true)==expected,'grid mismatch')
   end
  end
 end
end)
test('height and player eligibility still reject noncontacts',function()
 local t,a,d,ent,e,p=setup();p.ground=true
 for _,field in ipairs({'vehicle','fake','noclip','dead','airborne','height'})do
  p.vehicle=false;p.FakeRagdoll=nil;p.noclip=false;p.alive=true;p.ground=true;p.pos=Vector()
  if field=='vehicle' then p.vehicle=true elseif field=='fake' then p.FakeRagdoll=ent()
  elseif field=='noclip' then p.noclip=true elseif field=='dead' then p.alive=false
  elseif field=='airborne' then p.ground=false else p.pos=Vector(0,0,18.01)end
  a.ZCPoopNextStepScan=0;a.ZCPoopStepContacts=nil;t.CheckStepped(a,2)
  assert(next(a.ZCPoopStepContacts)==nil,field)
 end
end)
test('idle timer with no owned props never scans players',function()
 local t,a,d,ent,e,p=setup();e.ZCityPoop.owned={};e.rosterCalls=0;t.Tick();assert(e.rosterCalls==0)
end)
test('direct holder query stays live after carry changes',function()
 local t,a,d,ent,e,p=setup();p.weapon.carry=a;assert(t.ActiveHolder(a)==p)
 p.weapon.carry=nil;assert(t.ActiveHolder(a)==nil)
end)
local metrics={}
test('48-player 96-prop pass keeps exact footprint contacts',function()
 local t,a,d,ent,e,p=setup();e.players={};e.ZCityPoop.owned={}
 local props={}
 for i=1,48 do
  local q=ent('player');q.ground=true;q.pos=Vector((i%8)*40,math.floor(i/8)*40,0)
  q.weapon=ent('weapon');function q.weapon:GetClass()return 'weapon_hands_sh'end
  function q.weapon:GetCarrying()return nil end;e.players[i]=q
 end
 for i=1,96 do local q=ent();q.pos=Vector((i%8)*40,math.floor(i/8)*20,0);e.ZCityPoop.owned[q]=true;props[i]=q end
 e.rosterCalls=0;e.playerPositionCalls=0;e.weaponQueries=0;t.Tick()
 for _,q in ipairs(props)do
  for _,p in ipairs(e.players)do
   local delta=q.pos-p.pos;local expected=delta.x*delta.x+delta.y*delta.y<=324
   assert((q.ZCPoopStepContacts[p]==true)==expected)
  end
 end
 metrics={players=48,props=96,rosterCalls=e.rosterCalls,playerPositionCalls=e.playerPositionCalls,weaponQueries=e.weaponQueries}
 if t.BuildRoster then assert(e.rosterCalls==1 and e.playerPositionCalls==48 and e.weaponQueries==48)end
end)
return results,metrics
end
