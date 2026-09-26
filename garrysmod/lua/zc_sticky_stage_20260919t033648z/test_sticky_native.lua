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
 local wall=ent('world')
 local data={HitEntity=wall,HitPos=Vector(10,20,30),HitNormal=Vector(0,0,-1),OurOldVelocity=Vector(0,0,-100),Speed=100}
 return T,a,data,ent,e,player,load
end
for _,n in ipairs({Vector(0,0,1),Vector(0,0,-1),Vector(1,0,0),Vector(-1,0,0),Vector(0,1,0),Vector(1,2,3):GetNormalized()})do
 test('native bottom alignment '..tostring(n),function()
  local T,a,d=setup();d.HitNormal=-n;d.OurOldVelocity=-n*100
  assert(T.QueueStick(a,d,1));assert(a.changes==0 and a.phys.changes==0,'physics mutated in contact recorder')
  assert(T.ApplyPendingStick(a,1.05));assert(a.ang:Up():Dot(n)>.99999)
  local lo,hi=a:GetModelBounds();local bottom=Vector((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z)*a:GetModelScale()
  local contact=LocalToWorld(bottom,angle_zero,a.pos,a.ang)
  assert(contact:DistToSqr(d.HitPos+n*T.StickGap)<1e-7)
  assert(a.group==COLLISION_GROUP_WORLD and not a.phys.motion and a.phys.vel:LengthSqr()==0)
 end)
end
test('existing collision callback records once and timer attaches',function()
 local T,a,d,ent,e=setup();T.Attach(a);assert(a.callback);a.callback(a,d)
 assert(a.ZCPoopStickPending and not a.ZCPoopSticky and a.changes==0 and a.phys.changes==0)
 a.callback(a,d);T.Tick();assert(a.ZCPoopSticky and T.stats.sticks==1);T.Tick();assert(T.stats.sticks==1)
end)
test('held prop collision cannot attach',function()
 local T,a,d,ent,e,p=setup();p.weapon.carry=a;assert(not T.QueueStick(a,d,1));assert(a.changes==0)
end)
test('fresh spawn and expired throw do not attach',function()
 local T,a,d=setup();a.ZCPoopWasManipulated=nil;assert(not T.QueueStick(a,d,1))
 a.ZCPoopWasManipulated=true;a.ZCPoopThrownUntil=0;assert(not T.QueueStick(a,d,1))
end)
test('release immediately before timer can still record impact',function()
 local T,a,d,ent,e,p=setup();a.ZCPoopHolder=p;a.ZCPoopThrownUntil=nil;assert(T.QueueStick(a,d,1))
 T.Tick();assert(a.ZCPoopSticky)
end)
test('expired contact and recycled target are rejected',function()
 local T,a,d=setup();assert(T.QueueStick(a,d,1));assert(not T.ApplyPendingStick(a,2))
 assert(T.QueueStick(a,d,2));d.HitEntity.id=d.HitEntity.id+1;assert(not T.ApplyPendingStick(a,2.1))
end)
test('pickup cancels pending attachment',function()
 local T,a,d,ent,e,p=setup();assert(T.QueueStick(a,d,1));p.weapon.carry=a;T.Tick()
 assert(not a.ZCPoopSticky and not a.ZCPoopStickPending)
end)
test('native-hands grab path detaches before handing over prop',function()
 local T,a,d,ent,e,p=setup();assert(T.QueueStick(a,d,1));T.Tick()
 T.FindGrabTarget=function()return a,0,a.pos,10 end;assert(T.ArmGrab(p))
 assert(p.weapon.carry==a and a.phys.motion and not a.ZCPoopSticky and a.group==COLLISION_GROUP_NONE)
end)
test('moving surface follows translation and rotation, removal detaches',function()
 local T,a,d,ent,e=setup();local target=ent();d.HitEntity=target
 assert(T.QueueStick(a,d,1));T.Tick();local s=a.ZCPoopSticky
 target.pos=Vector(40,20,10);target.ang=Angle(15,60,20);T.Tick()
 local expected,ang=LocalToWorld(s.localPos,s.localAng,target.pos,target.ang)
 assert(a.pos:DistToSqr(expected)<1e-7 and a.ang:Up():Dot(ang:Up())>.99999)
 target.valid=false;T.Tick();assert(not a.ZCPoopSticky and a.phys.motion)
end)
test('ragdoll attachment follows impacted physics bone',function()
 local T,a,d,ent,e=setup();local target=ent();target.physcount=15;d.HitEntity=target
 assert(not T.QueueStick(a,d,1));d.HitObject=target.phys;assert(T.QueueStick(a,d,1));T.Tick()
 local old=a.pos;target.phys.pos=target.pos+Vector(10,0,0);T.Tick();assert(a.pos:DistToSqr(old+Vector(10,0,0))<1e-7)
 target.phys.valid=false;T.Tick();assert(not a.ZCPoopSticky)
end)
test('wrong physics object, invalid vectors, self and poop targets rejected',function()
 local T,a,d,ent,e=setup();d.HitEntity=ent();d.HitObject=ent().phys;assert(not T.QueueStick(a,d,1))
 d.HitObject=nil;d.HitNormal=Vector(0/0,0,0);assert(not T.QueueStick(a,d,1))
 d.HitNormal=Vector(0,0,-1);d.HitEntity=a;assert(not T.QueueStick(a,d,1))
 local other=ent();e.ZCityPoop.owned[other]=true;d.HitEntity=other;assert(not T.QueueStick(a,d,1))
end)
test('slow contact cannot stick and thrower immunity remains',function()
 local T,a,d,ent,e,p=setup();d.OurOldVelocity=Vector(0,0,-5);assert(not T.QueueStick(a,d,1))
 d.OurOldVelocity=Vector(0,0,-100);d.HitEntity=p;a.ZCPoopIgnoreHolderUntil=2;assert(not T.QueueStick(a,d,1))
end)
test('out-of-world contact fails without physics changes',function()
 local T,a,d=setup();d.HitPos=Vector(40000,0,0);assert(T.QueueStick(a,d,1));assert(not T.ApplyPendingStick(a,1.1));assert(a.phys.changes==0)
end)
for _,event in ipairs({'ZB_EndRound','PostCleanupMap'})do
 test('cleanup cancels pending contact: '..event,function()
  local T,a,d,ent,e=setup();assert(T.QueueStick(a,d,1))
  for _,f in pairs(e.hooks[event])do f()end
  assert(not T.ApplyPendingStick(a,1.1) and a.phys.changes==0)
 end)
end
test('reload keeps state table, cancels pending and preserves attached prop',function()
 local T,a,d,ent,e,p,load=setup();assert(T.QueueStick(a,d,1));load();assert(e.ZCityPoopThrow==T)
 assert(not T.ApplyPendingStick(a,1.1));assert(T.QueueStick(a,d,1.1));T.Tick();local s=a.ZCPoopSticky
 load();T.Tick();assert(a.ZCPoopSticky==s)
end)
test('no mass change, extra timer, constraints, or client messages for attachment',function()
 local T,a,d,ent,e=setup();local before=e.messages;assert(T.QueueStick(a,d,1));T.Tick()
 assert(e.messages==before and T.TickInterval==.05 and T.ThrowSpeed==40 and T.ThrowWindow==6)
 assert(not source:find(':EnableCollisions%(') and not source:find('constraint%.'))
end)
return results
end
