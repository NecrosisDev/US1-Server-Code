return function(oldSource,newSource)
local tests={}
local function test(n,f)local ok,err=pcall(f);tests[#tests+1]={name=n,pass=ok,error=not ok and tostring(err) or nil}end
local function setup(src,pose,ground)
 local e=setmetatable({SERVER=true,SWEP={},timers={},trace={},sounds=0},{__index=_G});e._G=e
 local vm={};vm.__index=vm
 local function V(x,y,z)return setmetatable({x or 0,y or 0,z or 0},vm)end
 vm.__add=function(a,b)return V(a[1]+b[1],a[2]+b[2],a[3]+b[3])end
 vm.__sub=function(a,b)return V(a[1]-b[1],a[2]-b[2],a[3]-b[3])end
 vm.__mul=function(a,b)return V(a[1]*b,a[2]*b,a[3]*b)end
 vm.__div=function(a,b)return V(a[1]/b,a[2]/b,a[3]/b)end
 local function angle()return {Forward=function()return V(1,0,0)end,Right=function()return V(0,-1,0)end,Up=function()return V(0,0,1)end,RotateAroundAxis=function()end,0,0,0}end
 e.Vector=V;e.Angle=angle;e.vector_origin=V()
 e.IsValid=function(a)return type(a)=='table' and a.valid==true end
 local phys={SetVelocity=function(s,v)s.velocity=v end}
 local ent={valid=true,SetOwner=function(s,v)s.ownerValue=v end,SetCollisionGroup=function(s,v)s.group=v end,
  Spawn=function(s)s.spawned=true end,SetPos=function(s,v)s.pos=v end,SetAngles=function(s,v)s.ang=v end,GetPhysicsObject=function()return phys end}
 local p={valid=true,EyeAngles=angle,Team=function()return 0 end,SteamID=function()return 'fixture'end,
  EmitSound=function()e.sounds=e.sounds+1 end,IsPlayer=function()return true end,ViewPunch=function()end,AnimRestartGesture=function()end,
  GetAimVector=function()return V(1,0,0)end,GetVelocity=function()return V(2,0,0)end,IsOnGround=function()return ground end,
  SetVelocity=function(s,v)s.impulse=v end}
 e.ents={Create=function()return ent end};e.game={GetWorld=function()return {}end};e.hg={GetCurrentCharacter=function()return p end}
 e.timer={Simple=function(t,f)e.timers[#e.timers+1]={delay=t,fn=f}end}
 e.COLLISION_GROUP_WEAPON=11;e.COLLISION_GROUP_INTERACTIVE=4
 local f=assert(loadstring(src,'throw_fixture'));setfenv(f,e);f()
 local headm=pose=='matrix' and {GetTranslation=function()return V(10,20,30)end} or nil
 if pose=='false' then headm=false elseif pose=='no_translation' then headm={GetTranslation=function()return nil end} end
 local w=setmetatable({ENT='fixture_grenade',GetOwner=function()return p end,GetEyeTrace=function()return nil,nil,headm end,
  GetAngles=angle,GetPos=function()return V(100,200,300)end,ThrowAdd=function(s)s.added=(s.added or 0)+1 end,lastOwner=p},{__index=e.SWEP})
 return e,w,p,ent,phys
end
local function same(a,b)for i=1,3 do assert(a[i]==b[i],i)end end
for _,ground in ipairs({true,false}) do
 test('valid pose preserves throw position, velocity, fuse and count; grounded='..tostring(ground),function()
  local a,wa,pa,ea,pha=setup(oldSource,'matrix',ground);local b,wb,pb,eb,phb=setup(newSource,'matrix',ground)
  wa:Throw(150,4,true);wb:Throw(150,4,true)
  same(ea.pos,eb.pos);same(pha.velocity,phb.velocity)
  assert(ea.timer==eb.timer and wa.added==wb.added and eb.spawned and #a.timers==#b.timers)
  if ground then same(pa.impulse,pb.impulse)end
 end)
end
for _,pose in ipairs({'missing','false','no_translation'}) do
 test('missing pose uses existing position fallback; '..pose,function()
  local e,w,p,ent,phys=setup(newSource,pose,true);w:Throw(150,4,true)
  assert(ent.spawned and ent.pos[1]==105 and ent.pos[2]==200 and ent.pos[3]==300)
  assert(phys.velocity[1]==102 and ent.timer==4 and w.added==1 and w.Thrower==nil)
 end)
end
test('missing projectile class is still a no-op',function()
 local e,w,p,ent=setup(newSource,'matrix',true);w.ENT=nil;w:Throw(150,4,true);assert(not ent.spawned and not w.added)
end)
return tests
end
