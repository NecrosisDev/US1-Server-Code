return function(before,after)
local results,metrics={},{}
local function test(name,fn)local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}end
local function clone(v,seen)
 if type(v)~='table' then return v end
 seen=seen or {};if seen[v] then return seen[v] end
 local t={};seen[v]=t;for k,x in pairs(v) do t[clone(k,seen)]=clone(x,seen) end;return t
end
local function equal(a,b,seen)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b or (type(a)=='number' and a~=a and b~=b) end
 seen=seen or {};if seen[a]==b then return true end;seen[a]=b
 for k,v in pairs(a) do if not equal(v,b[k],seen) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end;return true
end
local function env(source,options)
 local o=options or {};local e=setmetatable({SERVER=true,CLIENT=false,clock=10,events={},sends={},draws=0,seed=o.seed or 12345},{__index=_G});e._G=e
 local function noop()end
 e.math=setmetatable({},{__index=math})
 local function random()e.draws=e.draws+1;e.seed=e.seed*48271%2147483647;return e.seed/2147483647 end
 e.math.Rand=function(a,b)return a+(b-a)*random()end
 e.math.random=function(a,b)local r=random();if not a then return r end;if not b then b=a;a=1 end;return a+math.floor(r*(b-a+1))end
 e.math.Clamp=function(x,a,b)return math.max(a,math.min(b,x))end
 e.math.Approach=function(x,to,delta)if x<to then return math.min(to,x+delta)end;return math.max(to,x-delta)end
 e.math.Round=function(x)return math.floor(x+.5)end
 e.table=setmetatable({GetKeys=function(t)local k={};for a in pairs(t)do k[#k+1]=a end;return k end},{__index=table})
 e.CurTime=function()return e.clock end;e.Lerp=function(t,a,b)return a+(b-a)*t end
 e.IsValid=function(x)return type(x)=='table' and x.valid==true end
 local vm={};vm.__index=vm
 e.Vector=function(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},vm)end
 vm.__add=function(a,b)return e.Vector(a.x+b.x,a.y+b.y,a.z+b.z)end
 vm.__mul=function(a,b)return e.Vector(a.x*b,a.y*b,a.z*b)end
 vm.__unm=function(a)return e.Vector(-a.x,-a.y,-a.z)end
 vm.Length=function(a)return math.sqrt(a.x*a.x+a.y*a.y+a.z*a.z)end
 vm.Angle=function(a)return {Forward=function()return e.Vector(1,0,0)end,Right=function()return e.Vector(0,1,0)end}end
 e.VectorRand=function(a,b)return e.Vector(e.math.Rand(a,b),e.math.Rand(a,b),e.math.Rand(a,b))end
 e.LocalToWorld=function(pos,ang,origin,angles)return origin,ang end
 e.hook={Run=function(name,owner,org,wound,dir,artery)e.events[#e.events+1]={'droplet',wound.uid,artery,clone(dir)}end}
 e.util={AddNetworkString=noop}
 e.hg={organism={module={},fake_spine2=1,fake_spine3=1},lerpFrameTime2=function(rate,dt)return math.min(1,rate*dt)end}
 e.ZCJusticeV3Integration={enabled=true,Safe=function(self,fn,...)return fn(self,...)end,
  MedicalMutation=function(self,org,channel,old,new,kind,obj)e.events[#e.events+1]={'medical',channel,old,new,kind,obj and obj.uid or false}end}
 local owner={valid=true,player=o.player~=false,alive=o.alive~=false,stored={}}
 owner.IsPlayer=function(s)return s.player end;owner.Alive=function(s)return s.alive end
 owner.GetVelocity=function()return e.Vector(2,3,4)end
 owner.GetBonePosition=function()return e.Vector(),vm.Angle()end;owner.LookupBone=function()return 0 end
 owner.Notify=function(_,...)e.events[#e.events+1]={'notice',...}end
 owner.SetNetVar=function(self,key,value)
  self.stored[key]=value
  e.sends[#e.sends+1]={key=key,value=clone(value),at=e.clock}
 end
 e.owner=owner
 if o.fake then owner.FakeRagdoll={valid=true,GetVelocity=owner.GetVelocity,GetBonePosition=owner.GetBonePosition,LookupBone=owner.LookupBone}end
 local org={owner=owner,isPly=owner.player,blood=4500,bleed=1,internalBleed=0,internalBleedHeal=0,arteria=0,o2={90},pulse=70,satiety=50,adrenaline=1,temperature=36.7,consciousness=1,hemotransfusionshock=0,heart=0,liver=0,bleedingmul=1,brain=0,trachea=0,pneumothorax=0,wantToVomit=0,otrub=false,pain=2,painlessen=1,spine2=0,spine3=0,wounds={},arterialwounds={}}
 e.org=org;owner.organism=org
 local function wounds(n,kind,severity,due)
  local out={};for i=1,n do out[i]={[1]=type(severity)=='function' and severity(i) or severity or 0,[2]=e.Vector(i,1,2),[3]=e.Vector(),[4]='test_bone',[5]=due or 0,[6]=e.Vector(1,0,0),[7]='artery_'..i,uid=kind..i};org['artery_'..i]=1 end;return out
 end
 org.wounds=wounds(o.normal or 0,'n',o.normalSeverity,o.normalDue)
 org.arterialwounds=wounds(o.arterial or 0,'a',o.arterialSeverity,o.arterialDue)
 if o.fields then for k,v in pairs(o.fields)do org[k]=clone(v)end end
 e.hg.GetCurrentCharacter=function()return owner.FakeRagdoll or owner end
 local f=assert(loadstring(source,'@blood_source'));setfenv(f,e);f()
 e.run=function(dt)e.hg.organism.module.blood[2](owner,org,dt or .1)end
 e.snapshot=function()
  local t={};for k,v in pairs(org)do if k~='owner' then t[k]=clone(v)end end
  return {org=t,events=clone(e.events),draws=e.draws,stored=clone(owner.stored)}
 end
 return e
end
local function compare(options,steps)
 local a,b=env(before,options),env(after,options)
 for i=1,steps or 1 do a.clock=10+i*.1;b.clock=a.clock;a.run(options.dt or .1);b.run(options.dt or .1)
  assert(equal(a.snapshot(),b.snapshot()),'physiology, bookkeeping, droplets, randomness or final stored state changed')
 end
 return a,b
end
local cases={
 {'empty lists',{normal=0,arterial=0}}, {'one normal removal',{normal=1}},
 {'multiple normal removals',{normal=20}}, {'one artery removal',{arterial=1}},
 {'multiple arterial removals',{arterial=20}}, {'both removal paths',{normal=20,arterial=20}},
 {'nonzero normal wounds remain',{normal=10,normalSeverity=4}},
 {'nonzero arterial wounds remain',{arterial=10,arterialSeverity=4}},
 {'mixed severities',{normal=20,arterial=20,normalSeverity=function(i)return i%2==0 and 0 or 10 end,arterialSeverity=function(i)return i%3==0 and 0 or 5 end}},
 {'arterial pulse not due',{arterial=15,arterialDue=1000}},
 {'player currently ragdolled',{normal=20,arterial=20,fake=true}},
 {'dead player',{normal=20,arterial=20,alive=false}},
 {'NPC',{normal=20,arterial=20,player=false}},
 {'unconscious player',{normal=10,arterial=10,fields={otrub=true}}},
 {'heart and internal bleeding',{normal=10,arterial=10,fields={heart=1,internalBleed=2,internalBleedHeal=.1}}},
 {'coagulation removes tiny wounds',{normal=10,normalSeverity=.00001}},
 {'low oxygen and pulse',{normal=10,arterial=10,fields={pulse=8,o2={3},arteria=1}}},
 {'zero delta time',{normal=5,arterial=5,normalSeverity=.01,dt=0}}
}
for _,c in ipairs(cases) do
 test(c[1]..': unchanged calculation results',function()compare(c[2],1)end)
end
for _,key in ipairs({'normal','arterial'})do
 test(key..': many removals produce one final-list update',function()
  local a,b=compare({[key]=100});assert(#a.sends>1 and #b.sends==1,'publication counts')
  assert(equal(a.sends[#a.sends].value,b.sends[1].value),'wrong final payload')
  local oldEntries=0;for _,s in ipairs(a.sends)do oldEntries=oldEntries+#s.value end
  metrics[key]={originalMessages=#a.sends,candidateMessages=#b.sends,initialEntries=100,finalEntries=#b.sends[1].value,originalEntriesSerialized=oldEntries,candidateEntriesSerialized=#b.sends[1].value}
 end)
 test(key..': no removal creates no publication',function()
  local _,b=compare({[key]=10,[key..'Severity']=5});assert(#b.sends==0)
 end)
end
 test('both lists publish separately at their existing calculation boundaries',function()
  local _,b=compare({normal=20,arterial=20});assert(#b.sends==2)
  assert(b.sends[1].key=='wounds' and b.sends[2].key=='arterialwounds')
 end)
test('repeated calculations preserve empty-list transitions and artery flags',function()
 local a,b=compare({normal=100,arterial=100},15)
 assert(#b.org.wounds==0 and #b.org.arterialwounds==0)
 for i=1,100 do assert(a.org['artery_'..i]==b.org['artery_'..i])end
 assert(#b.sends<#a.sends)
end)
test('unchanged lists are not assigned new table identities',function()
 local b=env(after,{normal=10,arterial=10,normalSeverity=2,arterialSeverity=3})
 local n,a=b.org.wounds,b.org.arterialwounds;b.run();assert(b.org.wounds==n and b.org.arterialwounds==a)
end)
test('40 seeded multi-step scenarios preserve physiology and observation ordering',function()
 for seed=1,40 do
  compare({seed=seed,normal=seed%17,arterial=seed%11,fake=seed%2==0,player=seed%3~=0,
   normalSeverity=function(i)return i%3==0 and 0 or i*.002 end,
   arterialSeverity=function(i)return i%2==0 and 0 or 2 end},20)
 end
 metrics.randomized={scenarios=40,stepsEach=20}
end)
test('original iteration/removal behavior is preserved rather than silently redesigned',function()
 local a,b=compare({normal=100});assert(#a.org.wounds==#b.org.wounds)
 metrics.iteration={initial=100,remaining=#b.org.wounds,note='Existing pairs/table.remove order retained, including skipped entries.'}
end)
test('publishes current list before unrelated later physiology errors',function()
 for _,s in ipairs({before,after})do
  local e=env(s,{normal=20});e.org.heart=1;e.org.pain=nil
  local ok=pcall(e.run);assert(not ok and #e.sends>0)
 end
end)
return {tests=results,metrics=metrics}
end
