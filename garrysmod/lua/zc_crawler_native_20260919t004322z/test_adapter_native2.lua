return function(source,nativeSource)
local out={}
local function test(name,f)local ok,err=pcall(f);out[#out+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}end
local function noop()end
local function setup()
 local e=setmetatable({SERVER=true,clock=10,logs={},timers={},hooks={},receivers={},calls={},messages={},players={}},{__index=_G});e._G=e
 e.IsValid=function(x)return type(x)=='table' and x.valid==true end
 e.CurTime=function()return e.clock end;e.vector_origin={zero=true}
 e.VectorRand=function()return {random=true}end
 e.AddCSLuaFile=noop;e.print=noop
 e.file={CreateDir=noop,Append=function(_,s)e.logs[#e.logs+1]=s end}
 e.net={Receive=function(n,f)e.receivers[n]=f end,ReadEntity=function()e.reads=(e.reads or 0)+1;return e.target end}
 e.util={AddNetworkString=noop}
 e.hook={Remove=function(event,name)e.hooks[event..'/'..name]=nil end}
 e.timer={Remove=function(n)e.timers[n]=nil end}
 e.player={Iterator=function()return ipairs(e.players)end}
 e.ent=function(kind)
  local p={valid=true,kind=kind or 'player',alive=true,admin=false,nw={},organism={pain=2,blood=4800},name='test'}
  p.index=#e.players+1
  function p:EntIndex() return self.index end
  function p:IsPlayer()return self.kind=='player'end
  function p:IsRagdoll()return self.kind=='ragdoll'end
  function p:IsAdmin()return self.admin end;function p:IsSuperAdmin()return false end
  function p:Alive()return self.alive end;function p:Nick()return self.name end
  function p:GetNWBool(k,d)local v=self.nw[k];if v==nil then return d end;return v end
  function p:GetNWEntity()return self.owner end
  function p:GetRagdollEntity()return self.FakeRagdoll end
  function p:ChatPrint(s)e.messages[#e.messages+1]=s end
  if p:IsPlayer() then e.players[#e.players+1]=p end
  return p
 end
 e.hg={RagdollOwner=function(r)return r.owner end,GetCurrentCharacter=function(p)return p.FakeRagdoll or p end}
 e.hg.Fake=function(p,a,b,force)e.calls[#e.calls+1]='fake:'..tostring(force);p.FakeRagdoll=e.ent('ragdoll');p.FakeRagdoll.owner=p end
 e.ResolvePlayer=function(p)return p:IsPlayer() and p or p.owner end
 e.BuildSplitRagdolls=function(p,rag,force)
  e.calls[#e.calls+1]='split:'..tostring(force==e.vector_origin)
  p.nw.ZCityTorsoSevered=true;rag.nw.ZCityTorsoSevered=true
  p.__zcGoreLowerTorso=e.ent('ragdoll');return {owner=p,rag=rag,lower=p.__zcGoreLowerTorso}
 end
 e.AddTorsoTrauma=function(p,rag,blast)
  e.calls[#e.calls+1]='trauma:'..tostring(blast)
  p.organism.torsoamputated=true;p.organism.llegamputated=true;p.organism.rlegamputated=true
  p.organism.painadd=blast and 85 or 70;p.organism.blood=p.organism.blood-260
 end
 local f=assert(loadstring(nativeSource,'native_torso_control'));setfenv(f,e);f()
 e.load=function()local g=assert(loadstring(source,'crawler_adapter'));setfenv(g,e);g();return e.ZCMakeCrawler end
 return e,e.ent()
end
for _,alreadyFake in ipairs({false,true})do
 test('exact native transition equivalence; preexisting ragdoll='..tostring(alreadyFake),function()
  local a,p=setup();local b,q=setup()
  if alreadyFake then a.hg.Fake(p);b.hg.Fake(q);a.calls={};b.calls={} end
  assert(a.hg.ZCityGore_AmputateTorso(p,a.vector_origin,true))
  local m=b.load();assert(m.Apply(q,'test'))
  assert(table.concat(a.calls,',')==table.concat(b.calls,','))
  assert(q.nw.ZCityTorsoSevered and q.organism.torsoamputated and q.__zcGoreLowerTorso)
  assert(p.organism.blood==q.organism.blood and p.organism.painadd==q.organism.painadd)
 end)
end
test('already severed is idempotent',function()
 local e,p=setup();local m=e.load();assert(m.Apply(p));local n=#e.calls;local ok,why=m.Apply(p);assert(ok and why=='already' and #e.calls==n)
end)
test('old crawler marker does not prevent native conversion',function()
 local e,p=setup();p.nw.zc_make_crawler=true;local m=e.load();assert(m.Apply(p));assert(p.organism.torsoamputated)
end)
test('missing native API fails closed without modifying physiology',function()
 local e,p=setup();e.hg.ZCityGore_AmputateTorso=nil;local m=e.load();local ok,why=m.Apply(p)
 assert(not ok and why=='native_torso_api_missing' and #e.calls==0 and p.organism.blood==4800 and not p.organism.torsoamputated)
end)
test('pending native transition is not duplicated',function()
 local e,p=setup();p.__zcGoreTorsoPending=true;local m=e.load();assert(not m.Apply(p));assert(#e.calls==0)
end)
test('dead player is rejected',function()
 local e,p=setup();p.alive=false;local m=e.load();assert(not m.Apply(p));assert(#e.calls==0)
end)
test('missing organism is rejected',function()
 local e,p=setup();p.organism=nil;local m=e.load();assert(not m.Apply(p));assert(#e.calls==0)
end)
test('native rejection is not reported as applied',function()
 local e,p=setup();e.hg.ZCityGore_AmputateTorso=function()return false end;local m=e.load();assert(not m.Apply(p));assert(m.stats.applied==0)
end)
test('native errors are visible and counted',function()
 local e,p=setup();e.hg.ZCityGore_AmputateTorso=function()error('native-test-error')end;local m=e.load();assert(not m.Apply(p));assert(m.stats.errors==1 and #e.logs==1)
end)
test('native return without native state is not success',function()
 local e,p=setup();e.hg.ZCityGore_AmputateTorso=function()return true end;local m=e.load();assert(not m.Apply(p));assert(m.stats.errors==1 and m.stats.applied==0)
end)
test('non-admin network request does not read or affect a target',function()
 local e,p=setup();e.target=p;local admin=e.ent();e.load();e.receivers.ZCMakeCrawler_Apply(16,admin);assert(not e.reads and #e.calls==0)
end)
for _,ragTarget in ipairs({false,true})do
 test('admin button dispatches native API; ragdoll target='..tostring(ragTarget),function()
  local e,p=setup();local admin=e.ent();admin.admin=true
  if ragTarget then e.hg.Fake(p);e.calls={};e.target=p.FakeRagdoll else e.target=p end
  e.load();e.receivers.ZCMakeCrawler_Apply(16,admin);assert(p.organism.torsoamputated and #e.messages==1)
 end)
end
test('self target is rejected',function()
 local e,p=setup();p.admin=true;e.target=p;e.load();e.receivers.ZCMakeCrawler_Apply(16,p);assert(#e.calls==0)
end)
test('oversized request is rejected before reading target',function()
 local e,p=setup();p.admin=true;e.load();e.receivers.ZCMakeCrawler_Apply(10000,p);assert(not e.reads)
end)
test('requests are rate-limited',function()
 local e,p=setup();local a=e.ent();a.admin=true;e.target=p;e.load();e.receivers.ZCMakeCrawler_Apply(16,a)
 local q=e.ent();e.target=q;e.receivers.ZCMakeCrawler_Apply(16,a);assert(not q.organism.torsoamputated and e.reads==1)
end)
test('reload preserves native function and removes only legacy button machinery',function()
 local e,p=setup();local native=e.hg.ZCityGore_AmputateTorso
 e.hooks['Fake/ZCMakeCrawler_FlagRagdoll']=true;e.hooks['Think/ZCity Gore V2_SplitPhysics']=true
 e.timers['ZCMakeCrawler_Stabilize_'..p:EntIndex()]=true;e.timers.native_torso=true
 local m=e.load();assert(e.hg.ZCityGore_AmputateTorso==native)
 assert(not e.hooks['Fake/ZCMakeCrawler_FlagRagdoll'] and e.hooks['Think/ZCity Gore V2_SplitPhysics'])
 assert(not e.timers['ZCMakeCrawler_Stabilize_'..p:EntIndex()] and e.timers.native_torso)
 m.stats.applied=7;assert(e.load()==m and m.stats.applied==7)
end)
test('load does not depend on unsupported timer.GetTable',function()
 local e,p=setup();assert(e.timer.GetTable==nil);local m=e.load();assert(m.Version=='20260919.native2')
end)
test('late legacy stabilization callback cannot change player physiology',function()
 local e,p=setup();local m=e.load();local blood,pain=p.organism.blood,p.organism.pain
 assert(m.Stabilize==m.RetiredStabilize and m.Stabilize(p)==false)
 assert(p.organism.blood==blood and p.organism.pain==pain and #e.calls==0)
end)
return out
end
