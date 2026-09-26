return function(sources)
local results={}
local function test(name,fn)
 local ok,err=pcall(fn)
 results[#results+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}
end
local function noop()end
local function env(client)
 local e=setmetatable({SERVER=not client,CLIENT=client,clock=0,props={},players={},timers={},hooks={},receivers={},notices=0,sounds=0,anchors=0},{__index=_G})
 e._G=e
 e.IsValid=function(x)return type(x)=='table' and x.valid==true end
 e.isstring=function(x)return type(x)=='string'end
 e.CurTime=function()return e.clock end;e.RealTime=e.CurTime
 e.math=setmetatable({Clamp=function(v,a,b)if v<a then return a elseif v>b then return b else return v end end,Rand=function(a,b)return (a+b)/2 end},{__index=math})
 local vm={};vm.__index=vm
 e.Vector=function(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vm)end
 vm.__add=function(a,b)return e.Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
 vm.__sub=function(a,b)return e.Vector(a.x-b.x,a.y-b.y,a.z-b.z)end
 vm.__mul=function(a,b)return e.Vector(a.x*b,a.y*b,a.z*b)end
 vm.Length=function(a)return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z)end
 vm.DistToSqr=function(a,b)local d=a-b;return d.x*d.x+d.y*d.y+d.z*d.z end
 e.VectorRand=function()return e.Vector()end
 e.hook={Add=function(n,id,f)e.hooks[n]=e.hooks[n] or {};e.hooks[n][id]=f end}
 e.fire=function(n,...)for _,f in pairs(e.hooks[n] or {})do f(...)end end
 e.timer={Create=function(n,d,r,f)e.timers[n]=f end,Simple=function(d,f)e.timers[#e.timers+1]={at=e.clock+d,fn=f}end}
 e.advance=function(t)e.clock=t;for i=#e.timers,1,-1 do local s=e.timers[i];if s.at<=t then table.remove(e.timers,i);s.fn()end end end
 e.commands={};e.concommand={GetTable=function()return e.commands end,Add=function(n,f)e.commands[n]=f end}
 e.net={Receive=function(n,f)e.receivers[n]=f end,Start=noop,SendPVS=noop,Send=noop,Broadcast=noop,SendToServer=noop}
 for _,n in ipairs({'WriteEntity','WriteUInt','WriteVector','WriteNormal','WriteBool','WriteFloat'})do e.net[n]=noop end
 for _,n in ipairs({'ReadEntity','ReadUInt','ReadVector','ReadFloat','ReadBool','ReadNormal'})do e.net[n]=function()return table.remove(e.netq,1)end end
 e.file={Exists=function()return true end,CreateDir=noop,Append=noop,Read=function()return ''end,Write=noop}
 e.resource={AddWorkshop=noop,AddFile=noop};e.sound={Play=function()e.sounds=e.sounds+1 end}
 e.util={AddNetworkString=noop,IsValidProp=function()return true end,PrecacheModel=noop,PrecacheSound=noop,DecalEx=noop}
 e.util.TraceLine=function()return {Hit=false}end
 e.AddCSLuaFile=noop;e.PrecacheParticleSystem=noop;e.ParticleEffectAttach=noop;e.ConVarExists=function()return false end;e.ErrorNoHalt=noop
 e.include=function()e.ZCityPoop.MakeStain=noop end
 e.Color=function()return {}end;e.CreateMaterial=function()return {}end
 e.game={AddParticles=noop,GetWorld=function()return {}end};e.render={SetMaterial=noop,DrawBeam=noop}
 for _,k in ipairs({'OBS_MODE_NONE','HUD_PRINTCONSOLE','COLLISION_GROUP_DEBRIS','COLLISION_GROUP_NONE','FVPHYSICS_NO_IMPACT_DMG','CHAN_AUTO','RENDERGROUP_OTHER','PATTACH_ABSORIGIN_FOLLOW','MASK_SOLID_BRUSHONLY','IN_ATTACK2'})do e[k]=0 end
 e.player={GetAll=function()return e.players end}
 e.hg={organism={fake_spine1=1,fake_spine2=1,fake_spine3=.5}}
 e.ent=function()
  local ph={valid=true,motion=true};function ph:EnableMotion(v)self.motion=v end
  ph.AddGameFlag=noop;ph.SetMass=noop;ph.Wake=noop;ph.GetVelocity=function()return e.Vector()end;ph.IsMotionEnabled=function(s)return s.motion end
  local a={valid=true,physics=ph,pos=e.Vector(),collisionChanges=0}
  for _,n in ipairs({'SetModel','SetPos','SetAngles','SetCollisionGroup','Spawn','Activate','SetNoDraw','SetNW2Bool','SetModelScale','StopParticles','EmitSound','AddCallback'})do a[n]=noop end
  a.Remove=function(s)s.valid=false;e.fire('EntityRemoved',s);if s.anchor then e.anchors=e.anchors-1 end end
  a.GetPhysicsObject=function()return ph end;a.GetPos=function(s)return s.pos end;a.WorldSpaceCenter=a.GetPos
  a.CollisionRulesChanged=function(s)s.collisionChanges=s.collisionChanges+1 end
  e.props[#e.props+1]=a;return a
 end
 e.ents={Create=function()return e.ent()end}
 e.ClientsideModel=function()local a=e.ent();a.anchor=true;e.anchors=e.anchors+1;return a end
 e.playerNew=function(id)
  local p=e.ent();p.id=id or '123';p.alive=true;p.team=1;p.mode=0;p.vehicle=false;p.organism={alive=true}
  p.IsPlayer=function()return true end;p.IsBot=function()return false end
  p.Alive=function(s)return s.alive end;p.Team=function(s)return s.team end;p.GetObserverMode=function(s)return s.mode end
  p.InVehicle=function(s)return s.vehicle end;p.SteamID64=function(s)return s.id end;p.UserID=function()return 1 end
  p.PrintMessage=function()e.notices=e.notices+1 end;p.Notify=p.PrintMessage
  p.SetNW2Float=function(s,k,v)s[k]=v end;p.GetActiveWeapon=function(s)return s.weapon end
  p.GetNetVar=function(s,k,d)return d end;p.KeyDown=function()return true end
  e.players[#e.players+1]=p;return p
 end
 e.load=function(name)local f=assert(loadstring(assert(sources[name],name),'@'..name));setfenv(f,e);f()end
 return e
end
local function urine()
 local e=env(false);e.load('autorun/server/zc_urine.lua');local u=e.ZCityUrine;local p=e.playerNew()
 u.Source=function(p)return e.Vector(),e.Vector(1,0,0),p end
 u.ResetBladder(p,100);return e,u,p
end
local function core()
 local e=env(false);e.load('autorun/server/zc_poop.lua');local c=e.ZCityPoop;local p=e.playerNew()
 c.DropPosition=function()return e.Vector(),{}end;return e,c,p
end
local function close(a,b)assert(math.abs(a-b)<.00001,tostring(a)..' ~= '..tostring(b))end
test('urine: stop between bladder ticks charges the elapsed interval',function()
 local e,u,p=urine();assert(u.Start(p));e.clock=.05;u.Stop(p,true);close(u.GetBladder(p),99.375)
end)
test('urine: repeated short streams cannot avoid draining',function()
 local e,u,p=urine();for i=0,9 do e.clock=i*.6;assert(u.Start(p));e.clock=e.clock+.05;u.Stop(p,true)end
 close(u.GetBladder(p),100-10*.625+9*.55/3)
end)
test('urine: delayed end settles at eight seconds, not one tick',function()
 local e,u,p=urine();assert(u.Start(p));e.clock=20;u.Tick();close(u.GetBladder(p),0);assert(not u.active[p])
end)
test('urine: regeneration accounts for elapsed time',function()
 local e,u,p=urine();u.ResetBladder(p,0);e.clock=300;u.UpdateBladder(p,e.clock,false);close(u.GetBladder(p),100)
end)
test('urine: empty-command flood emits at most one notice',function()
 local e,u,p=urine();u.ResetBladder(p,0);for i=1,200 do assert(not u.Start(p))end;assert(e.notices<=1,e.notices)
end)
test('urine: failed source attempts are rate limited',function()
 local e,u,p=urine();local calls=0;u.Source=function()calls=calls+1 end;for i=1,200 do u.Start(p)end;assert(calls==1,calls)
end)
test('urine: normal full stream drains once and stops',function()
 local e,u,p=urine();assert(u.Start(p));for i=1,80 do e.clock=i/10;u.BladderTick();u.Tick()end
 close(u.GetBladder(p),0);assert(not u.active[p]);assert(u.stats.starts==1 and u.stats.stops==1)
end)
test('urine: malformed readiness payload is ignored',function()
 local e,u,p=urine();e.receivers.ZCUrineReadyV1(1024,p);assert(not u.ready[p])
end)
test('urine: reload preserves bladder and active session',function()
 local e,u,p=urine();u.ResetBladder(p,45);assert(u.Start(p));local state=u.active[p]
 e.load('autorun/server/zc_urine.lua');assert(u.active[p]==state);close(u.GetBladder(p),45)
end)
test('urine: dead players cannot start',function()
 local e,u,p=urine();p.alive=false;assert(not u.Start(p));assert(u.stats.starts==0)
end)
test('urine: nonfinite bladder state recovers without free capacity',function()
 local e,u,p=urine();u.bladder[p].value=0/0;close(u.UpdateBladder(p,0,false),0)
end)
test('poop: freeze timer leaves a manipulated prop movable',function()
 local e,c,p=core();local ok,ent=c.Spawn(p);assert(ok);ent.ZCPoopWasManipulated=true;e.advance(2);assert(ent.physics.motion)
end)
test('poop: removal purges ownership without leaving stale entries',function()
 local e,c,p=core();local ok,a=c.Spawn(p);assert(ok);a:Remove();assert(not c.owned[a]);assert(#c.accounts[p.id].poops==0)
end)
test('poop: cleanup removes both props despite synchronous removal hooks',function()
 local e,c,p=core();local _,a=c.Spawn(p);e.clock=30;local _,b=c.Spawn(p);c.Cleanup();assert(not a.valid and not b.valid)
end)
test('poop: cooldown and two-prop limit remain intact',function()
 local e,c,p=core();local _,a=c.Spawn(p);assert(not c.Spawn(p));e.clock=30;assert(c.Spawn(p));e.clock=60;assert(c.Spawn(p));assert(not a.valid and #c.accounts[p.id].poops==2)
end)
local function involuntary()
 local e=env(false);e.load('autorun/server/zc_poop_involuntary.lua');return e,e.ZCityPoopInvoluntary,e.playerNew()
end
test('involuntary: failed death attempts stop at retry budget',function()
 local e,i,p=involuntary();p.alive=false;p.organism.alive=false;local calls=0
 i.Spawn=function()calls=calls+1;return false,'ground'end
 for n=0,100 do e.advance(n*.21);i.Tick()end;assert(calls==i.RetryCount,'attempts='..calls)
end)
test('involuntary: pending retries cannot act on replacement organism',function()
 local e,i,p=involuntary();p.organism.spine3=1;local calls=0;i.Spawn=function()calls=calls+1;return false end
 i.Tick();p.organism={alive=true,spine3=1};e.advance(.21);assert(calls==1,calls)
end)
test('involuntary: cleanup does not regenerate existing death events',function()
 local e,i,p=involuntary();p.alive=false;p.organism.alive=false;local calls=0;i.Spawn=function()calls=calls+1;return true end
 e.fire('PostCleanupMap');i.Tick();assert(calls==0,calls)
end)
test('throw: collision updates are cached and refreshed only on change',function()
 local e=env(false);e.load('autorun/server/zc_poop_throw.lua');local t=e.ZCityPoopThrow;local a=e.ent();local p=e.playerNew()
 e.ZCityPoop={owned={[a]=true}};t.UpdateCollisionFilter(a,p);assert(a.collisionChanges==1)
 t.UpdateCollisionFilter(a,p);assert(a.collisionChanges==1);e.clock=100
 assert(e.hooks.ShouldCollide.ZCityPoopThrow_HolderCollision(a,p)==false)
 t.UpdateCollisionFilter(a,nil);assert(a.collisionChanges==2)
 assert(e.hooks.ShouldCollide.ZCityPoopThrow_HolderCollision(a,p)==nil)
end)
local function visuals()
 local e=env(true);e.load('autorun/client/zc_urine_visuals.lua')
 local function packet(n)e.netq={nil,n,e.Vector(),e.Vector(100,0,0),1};e.netq[1]={};e.receivers.ZCUrinePacketV1()end
 return e,e.ZCityUrineVisuals,packet
end
test('client urine: packet and model counts are bounded under bursts',function()
 local e,v,packet=visuals();for n=1,1000 do packet(n)end
 assert(#v.packets<=192,#v.packets);assert(e.anchors<=32,e.anchors)
end)
test('client urine: cleanup releases all effect models',function()
 local e,v,packet=visuals();for n=1,80 do packet(n)end;e.fire('PostCleanupMap');assert(e.anchors==0);assert(#v.packets==0)
end)
test('client urine: version transition releases old effect models',function()
 local e,v,packet=visuals();for n=1,80 do packet(n)end;v.Version='previous';e.load('autorun/client/zc_urine_visuals.lua');assert(e.anchors==0)
end)
test('client smear: seen-ID history is bounded',function()
 local e=env(true);e.load('autorun/client/zc_poop_smear.lua');for n=1,3000 do e.netq={n,true,e.Vector(),e.Vector(0,0,1)};e.receivers.ZCPoopSmearV1()end
 local count=0;for _ in pairs(e.ZCPoopSmearClient.seen)do count=count+1 end;assert(count<=2048,count)
 e.clock=31;e.timers.ZCityPoopSmear_Flush();assert(#e.ZCPoopSmearClient.queue==0)
end)

test('urine delivery: does not inject live client code',function()
 local e,u,p=urine();p.SendLua=function()error('live injection')end;assert(u.SendClient(p)==false)
end)
test('throw delivery: does not inject live client code',function()
 local e=env(false);e.load('autorun/server/zc_poop_throw.lua');local p=e.playerNew();p.SendLua=function()error('live injection')end;assert(e.ZCityPoopThrow.SendClient(p)==false)
end)
return results
end
