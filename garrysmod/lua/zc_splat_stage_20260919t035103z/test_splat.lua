-- Native vector/angle maths, isolated fake entities. No live gameplay actions.
return function(source)
local results={};local function noop()end
local function test(name,f)local ok,err=pcall(f);results[#results+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}end
local function setup()
 local e=setmetatable({SERVER=true,CLIENT=false,clock=1,players={},props={},timers={},hooks={},receivers={},sounds=0,messages=0,world=game.GetWorld()},{__index=_G});e._G=e
 e.heldents={};e.sound={Play=function()assert(not e.inCollision);e.sounds=e.sounds+1 end};e.ZCityPoopThrow=false;e.ZCityPillCompat=false;e.hg={}
 e.IsValid=function(x)return type(x)=='table' and x.valid==true end
 e.CurTime=function()return e.clock end
 e.AddCSLuaFile=noop;e.ErrorNoHalt=function(s)error(s)end
 e.util={AddNetworkString=noop,IsInWorld=function(v)return math.abs(v.x)<32000 and math.abs(v.y)<32000 and math.abs(v.z)<32000 end}
 e.file={CreateDir=noop,Append=noop};e.net={Start=noop,WriteUInt=noop,WriteBool=noop,WriteEntity=noop,WriteVector=noop,WriteNormal=noop,Broadcast=function()assert(not e.inCollision);e.messages=e.messages+1 end,Receive=function(n,f)e.receivers[n]=f end}
 e.hook={Add=function(n,id,f)e.hooks[n]=e.hooks[n] or {};e.hooks[n][id]=f end}
 e.timer={Simple=function(_,f)e.timers[#e.timers+1]=f end,Create=function(n,_,_,f)e.timers[n]=f end}
 e.player={GetAll=function()return e.players end}
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
  function a:EntIndex()return self.id end
  function a:Remove()assert(not e.inCollision);self.valid=false;e.ZCityPoop.owned[self]=nil end
  function a:GetPos()return self.pos end
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
  function a:GetActiveWeapon()return self.weapon end
  function a:Alive()return self.alive~=false end
  function a:Team()return 1 end
  function a:GetObserverMode()return OBS_MODE_NONE end
  function a:InVehicle()return false end
  function a:OnGround()return false end
  function a:GetMoveType()return MOVETYPE_WALK end
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
 local wall=game.GetWorld()
 local data={HitEntity=wall,HitPos=Vector(10,20,30),HitNormal=Vector(0,0,-1),OurOldVelocity=Vector(0,0,-100),Speed=100}
 e.flush=function()local todo=e.timers;e.timers={};for i=1,#todo do todo[i]() end end
 return T,a,data,ent,e,player,load
end
test('real world contact works even though IsValid(world) is false',function()
 local T,a,d,ent,e,p=setup();assert(not e.IsValid(d.HitEntity));T.MarkThrown(p,a)
 e.inCollision=true;a.callback(a,d);assert(a.valid and e.messages==0);e.inCollision=false
 e.flush();assert(not a.valid and e.messages==1 and T.stats.splats==1)
end)
test('ordinary fast drop never destroys or paints',function()
 local T,a,d,ent,e=setup();T.Attach(a);d.OurOldVelocity=Vector(0,0,-900)
 a.callback(a,d);e.flush();assert(a.valid and e.messages==0)
end)
test('old throw speed flags are not sufficient without native throw event',function()
 local T,a,d,ent,e=setup();a.ZCPoopThrownUntil=999;T.OnCollide(a,d);e.flush();assert(a.valid and e.messages==0)
end)
test('held and secondary-held props never splat',function()
 local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);p.weapon.carry=a;T.OnCollide(a,d);assert(not a.ZCPoopSplatPending)
 p.weapon.carry=nil;e.heldents[a.id]={a,p};T.OnCollide(a,d);assert(not a.ZCPoopSplatPending)
end)
test('low collision Speed does not suppress an explicitly thrown splat',function()
 local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);d.Speed=0;d.OurOldVelocity=Vector(0,0,-1)
 T.OnCollide(a,d);e.flush();assert(not a.valid and e.messages==1)
end)
test('repeated collisions and timer servicing create one decal and one removal',function()
 local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);for i=1,20 do T.OnCollide(a,d)end
 local s=a.ZCPoopSplatPending;assert(T.CommitSplat(a,s));e.flush();assert(e.messages==1 and T.stats.splats==1)
end)
test('pickup between contact and deferred removal cancels destruction',function()
 local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);T.OnCollide(a,d);p.weapon.carry=a;e.flush()
 assert(a.valid and e.messages==0)
end)
test('expired throw does not turn a later nudge into a splat',function()
 local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);e.clock=10;T.OnCollide(a,d);e.flush();assert(a.valid and e.messages==0)
end)
test('non-poop native throws do not arm anything',function()
 local T,a,d,ent,e,p=setup();local other=ent();T.MarkThrown(p,other);assert(not other.ZCPoopThrowTicket)
end)
for _,event in ipairs({'ZB_EndRound','PostCleanupMap'})do
 test('pending splat cancelled on '..event,function()
  local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);T.OnCollide(a,d)
  for _,f in pairs(e.hooks[event] or {})do f()end;e.flush();assert(a.valid and e.messages==0)
 end)
end
test('reload invalidates pending splat',function()
 local T,a,d,ent,e,p,load=setup();T.MarkThrown(p,a);T.OnCollide(a,d);load();e.flush();assert(a.valid and e.messages==0)
end)
test('invalid and out-of-world contacts never remove a prop',function()
 local T,a,d,ent,e,p=setup();T.MarkThrown(p,a);d.HitNormal=Vector();T.OnCollide(a,d);assert(not a.ZCPoopSplatPending)
 d.HitNormal=Vector(0,0,-1);d.HitPos=Vector(90000,0,0);T.OnCollide(a,d);e.flush();assert(a.valid and e.messages==0)
end)
test('moving target contact is transformed before painting',function()
 local T,a,d,ent,e,p=setup();d.HitEntity=ent();T.MarkThrown(p,a);T.OnCollide(a,d)
 local painted;T.SendSmear=function(hit,pos)painted=pos;e.messages=e.messages+1 end
 d.HitEntity.pos=Vector(25,0,0);e.flush();assert(not a.valid and painted:DistToSqr(d.HitPos+Vector(25,0,0))<.001)
end)
test('removed target and recycled entity do not receive stale decals',function()
 local T,a,d,ent,e,p=setup();d.HitEntity=ent();T.MarkThrown(p,a);T.OnCollide(a,d);d.HitEntity.id=999;e.flush()
 assert(a.valid and e.messages==0)
end)

return results
end
