return function(oldSource,newSource)
local out={};local function test(n,f)local ok,e=pcall(f);out[#out+1]={name=n,pass=ok,error=not ok and tostring(e) or nil}end
local function run(source,scene,blocked,direct)
 local e=setmetatable({clock=0,traces=0,spheres=0,events={},entities={}},{__index=_G});e._G=e
 e.IsValid=function(a)return type(a)=='table' and a.valid end
 e.U={ExtinguishRadius=32,VFireExtinguishAmount=16};e.hg={RagdollOwner=function(a)return a.owner end}
 for i,spec in ipairs(scene)do
  local a={valid=not spec.invalid,class=spec.class or 'prop_physics',burning=spec.burning,id=i}
  function a:GetClass()return self.class end;function a:IsRagdoll()return self.class=='prop_ragdoll'end
  function a:IsPlayer()return self.class=='player'end;function a:IsOnFire()return self.burning==true end
  function a:WorldSpaceCenter()return Vector(self.id,0,0)end
  function a:Extinguish()self.burning=false;e.events[#e.events+1]='E'..self.id end
  if spec.soft then function a:SoftExtinguish(n)e.events[#e.events+1]='S'..self.id..':'..n end end
  e.entities[i]=a
 end
 for i,spec in ipairs(scene)do if spec.owner then e.entities[i].owner=e.entities[spec.owner]end end
 e.util={TraceLine=function(t)e.traces=e.traces+1;return {Hit=blocked=='wall',StartSolid=blocked=='solid',AllSolid=blocked=='allsolid'}end}
 e.ents={FindInSphere=function(_,radius)e.spheres=e.spheres+1;assert(radius==32);return e.entities end}
 local first=assert(source:find('local function canReachFire',1,true));local last=assert(source:find('-- Queue one',first,true))
 local f=CompileString('local U=U\n'..source:sub(first,last-1),'fire_fixture',false);assert(type(f)=='function',tostring(f));setfenv(f,e);f()
 e.U.ExtinguishImpact({}, {Entity=direct and e.entities[direct] or nil,HitPos=Vector(),HitNormal=Vector(0,0,1)})
 return e
end
local function compare(scene,blocked,direct)
 local a=run(oldSource,scene,blocked,direct);local b=run(newSource,scene,blocked,direct)
 assert(table.concat(a.events,',')==table.concat(b.events,','),'extinguish effects differ')
 assert(a.spheres==1 and b.spheres==1);return a,b
end
local metrics={}
test('100 unrelated props cause zero visibility traces',function()
 local scene={};for i=1,100 do scene[i]={}end
 local a,b=compare(scene);assert(a.traces==100 and b.traces==0)
 metrics={nearbyClutter=100,oldTraces=a.traces,newTraces=b.traces,sphereQueries=b.spheres}
end)
for _,class in ipairs({'vfire','vfire_ball','env_fire','player','prop_ragdoll'})do
 test('preserved extinguishing for '..class,function()compare({{class=class,burning=true}})end)
end
test('vfire soft-extinguish amount unchanged',function()compare({{class='vfire',soft=true}})end)
for _,blocker in ipairs({'wall','solid','allsolid'})do
 test('obstruction still prevents indirect extinguishing '..blocker,function()
  local _,e=compare({{class='player',burning=true},{class='vfire',soft=true}},blocker);assert(#e.events==0)
 end)
end
test('direct hit extinguishes any burning prop despite blocked neighborhood',function()
 local _,e=compare({{burning=true}},'wall',1);assert(e.events[1]=='E1')
end)
test('nonburning ragdoll still reaches its burning owner',function()
 local _,e=compare({{class='prop_ragdoll',owner=2},{class='prop_physics',burning=true}})
 assert(e.events[1]=='E2')
end)
test('invalid candidates and dry characters do not consume traces',function()
 local _,e=compare({{invalid=true},{class='player'},{class='prop_ragdoll'}});assert(e.traces==0)
end)
return out,metrics
end
