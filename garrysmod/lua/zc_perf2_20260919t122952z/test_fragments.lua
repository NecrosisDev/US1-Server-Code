return function(oldSource,newSource)
local out={};local function test(name,f)local ok,e=pcall(f);out[#out+1]={name=name,pass=ok,error=not ok and tostring(e) or nil}end
local function block(source)
 local start=assert(source:find('\ttimer.Simple(0, function()\n\t\tif not IsValid(self) then return end\n\t\tutil.ScreenShake',1,true))
 local stop=assert(source:find('\n\tutil.ScreenShake( selfPos, 35, 1, 1, 1000, true )',start,true))
 return 'return function(self,selfPos)\nlocal vecCone=Vector()\n'..source:sub(start,stop-1)..'\nend'
end
local function run(source,count,cost,opt)
 opt=opt or {};local e=setmetatable({clock=0,tick=1,attempts=0,bullets={},simple={},named={},errors={},slices={}},{__index=_G});e._G=e
 local a={valid=true,Fragmentation=count,Penetration=8,PenetrationMultiplier=2,owner={}}
 e.IsValid=function(x)return type(x)=='table' and x.valid==true end
 e.SysTime=function()return e.clock end;e.engine={TickCount=function()return e.tick end}
 e.timer={Simple=function(_,f)e.simple[#e.simple+1]=f end,Create=function(n,_,_,f)e.named[n]=f end,Remove=function(n)e.named[n]=nil end}
 e.hg={ammotypeshuy={['Metal Debris']={BulletSettings={Speed=700,Penetration=9,Diameter=2,Distance=4000}}},bulletHit=function()end}
 e.util={ScreenShake=function()end,QuickTrace=function()
  e.attempts=e.attempts+1;e.clock=e.clock+cost
  if opt.failAt==e.attempts then error('fixture failure') end
  local i=e.attempts;return {Hit=i%4~=0,HitSky=i%4==1,HitWorld=i%4==2}
 end}
 e.VectorRand=function()return Vector(1,2,3)end
 function a:EntIndex()return 77 end;function a:GetCreationID()return 9 end
 function a:CallOnRemove(_,f)self.cleanup=f end
 function a:FireLuaBullets(b,sync)e.bullets[#e.bullets+1]={damage=b.Damage,force=b.Force,penetration=b.Penetration,speed=b.Speed,diameter=b.Diameter,distance=b.Distance,lag=b.DisableLagComp,sync=sync,owner=b.Attacker==self.owner}end
 function a:ExplodeAdd()e.adds=(e.adds or 0)+1 end
 e.SafeRemoveEntity=function(x)x.valid=false;e.removals=(e.removals or 0)+1;if x.cleanup then x.cleanup()end end
 e.ErrorNoHalt=function(s)e.errors[#e.errors+1]=s end
 local f=CompileString(block(source),'fragment_fixture',false);assert(type(f)=='function',tostring(f));setfenv(f,e);f()(a,Vector())
 local function timed(fn)local n=e.attempts;local t=e.clock;fn();e.slices[#e.slices+1]={count=e.attempts-n,cost=e.clock-t}end
 timed(e.simple[1]);e.first=e.attempts
 local before=e.attempts;for _,fn in pairs(e.named)do timed(fn)end;e.sameTick=e.attempts-before
 if opt.cancel then e.SafeRemoveEntity(a) end
 for tick=2,3000 do
  if next(e.named)==nil then break end
  e.tick=tick;for _,fn in pairs(e.named)do timed(fn)end
 end
 assert(next(e.named)==nil,'job did not finish');return e,a
end
for _,n in ipairs({0,1,64,65,700,960})do
 test('preserved fragment attempts and payloads '..n,function()
  local old=run(oldSource,n,.00002);local new,a=run(newSource,n,.00002)
  assert(old.attempts==n and new.attempts==n and #old.bullets==#new.bullets)
  for i,b in ipairs(old.bullets)do for k,v in pairs(b)do assert(new.bullets[i][k]==v,k)end end
  assert(a.ShrapnelDone and new.removals==1 and new.adds==1)
 end)
end
test('cheap fragments have cumulative one-millisecond slices',function()
 local old=run(oldSource,700,.00002);local new=run(newSource,700,.00002)
 assert(old.first==700 and new.first<700)
 for _,s in ipairs(new.slices)do assert(s.cost<=.001020001,'oversized slice '..s.cost)end
end)
test('zero-cost fragments capped at 64 attempts per resume',function()
 local e=run(newSource,700,0);assert(e.first==64)
 for _,s in ipairs(e.slices)do assert(s.count<=64)end
end)
test('first and named timer do not double-spend one tick',function()local e=run(newSource,700,0);assert(e.sameTick==0)end)
test('expensive fragment is indivisible but next work yields',function()
 local e=run(newSource,8,.003);for _,s in ipairs(e.slices)do assert(s.count<=1 and s.cost<=.0030001)end
end)
test('removed grenade cancels remaining work',function()
 local e=run(newSource,700,.00002,{cancel=true});assert(e.attempts<700 and e.removals==1)
end)
test('coroutine failure is logged once and cleans the timer',function()
 local e=run(newSource,700,.00002,{failAt=80});assert(#e.errors==1 and e.attempts==80 and e.removals==1)
end)
local old=run(oldSource,700,.00002);local new=run(newSource,700,.00002)
return out,{oldFirstFragments=old.first,newFirstFragments=new.first,oldFirstMs=old.slices[1].cost*1000,newFirstMs=new.slices[1].cost*1000,simulatedFragmentMicroseconds=20,newResumeCount=#new.slices}
end
