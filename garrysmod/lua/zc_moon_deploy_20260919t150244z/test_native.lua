-- Native Lua, Vector and JSON; simulated console, disk and map lifecycle only.
return function(oldCode,code)
local results={};local function test(n,f)local ok,err=pcall(f);results[#results+1]={name=n,pass=ok,error=not ok and tostring(err) or nil}end
local J='zc_hmcd_mutators/moon_gravity_lease.json'
local function world(g,v)return {gravity=g or 600,physics=v or Vector(0,0,-(g or 600)),files={},queue={},boot=0}end
local env
function env(src,w)
 w=w or world();w.boot=w.boot+1
 local e=setmetatable({SERVER=true,CLIENT=false,ZC_HMCD_MOON_GRAVITY_STATE=false},{__index=_G});e._G=e
 e.world=w;e.logs={};e.commands={};e.callbacks={};e.hooks={};e.timers={}
 e.os={time=function()return 1789830400+w.boot end};e.SysTime=function()return 100+w.boot end
 e.IsValid=function(p)return type(p)=='table' and p.valid==true end
 e.GetConVar=function()return {GetFloat=function()return w.gravity end}end
 e.physenv={GetGravity=function()return Vector(w.physics)end,SetGravity=function(v)w.physics=Vector(v)end}
 e.file={Exists=function(p)return w.files[p]~=nil end,Read=function(p)return w.files[p]end,CreateDir=function()end,
  Write=function(p,s)if not w.writeFail then w.files[p]=s end end,Delete=function(p)w.files[p]=nil end}
 e.util={TableToJSON=util.TableToJSON,JSONToTable=util.JSONToTable}
 e.ErrorNoHalt=function(s)e.logs[#e.logs+1]=s end
 e.concommand={Add=function(n,f)e.commands[n]=f end}
 e.cvars={AddChangeCallback=function(_,f,n)e.callbacks[n]=f end,RemoveChangeCallback=function(_,n)e.callbacks[n]=nil end}
 e.hook={Add=function(n,id,f)e.hooks[n]=e.hooks[n] or {};e.hooks[n][id]=f end}
 e.timer={Simple=function(_,f)e.timers[#e.timers+1]=f end}
 e.game={ConsoleCommand=function(s)for line in s:gmatch('[^\n]+')do w.queue[#w.queue+1]=line end end}
 local m={definitions={},Finite=function(n)return type(n)=='number' and n==n and math.abs(n)<math.huge end}
 function m:Register(d)assert(not self.definitions[d.ID],'duplicate');self.definitions[d.ID]=d;e.def=d end
 e.ZC_HMCD_MUTATORS=m
 function e:load()local f=CompileString(src,'moon_isolated',false);assert(type(f)=='function',tostring(f));setfenv(f,e);f()end
 function e:set(v)local old=w.gravity;w.gravity=v;w.physics=Vector(0,0,-v)
  for _,f in pairs(e.callbacks)do f('sv_gravity',tostring(old),tostring(v))end end
 function e:pump(limit)
  local n=0;while #w.queue>0 and n<(limit or 100)do n=n+1;local c=table.remove(w.queue,1)
   local v=c:match('^sv_gravity (.+)$')
   if v then if not w.commandFail then self:set(assert(tonumber(v)))end
   else local name,token,action=c:match('^(%S+) (%S+) (%S+)$');if e.commands[name]then e.commands[name](nil,name,{token,action})end end
  end;assert(n<100,'unbounded queue')
 end
 function e:fire(n)for _,f in pairs(e.hooks[n] or {})do f()end end
 function e:init()self:fire('InitPostEntity');local timers=e.timers;e.timers={};for _,f in ipairs(timers)do f()end;self:pump()end
 function e:cancel()if not e.ctx then return end;e.ctx.valid=false;for i=#e.ctx.cleanups,1,-1 do e.ctx.cleanups[i]()end end
 function e:start(pump)
  assert(e.def.CanStart());local ctx={valid=true,prefix='fixture_',data={},cleanups={}}
  function ctx:Valid()return self.valid end;function ctx:Cleanup(f)self.cleanups[#self.cleanups+1]=f end
  function ctx:Call(f)if not self.valid then return end;local ok,err=pcall(f);if not ok then e.logs[#e.logs+1]=tostring(err);e:cancel()end end
  e.ctx=ctx;e.def.Start(ctx);if pump~=false then e:pump()end
 end
 function e:nextMap(carry,shutdown)
  if shutdown~=false then e:fire('ShutDown')end;if not carry then w.queue={}end
  w.physics=Vector(0,0,-w.gravity);return env(src,w)
 end
 e:load();return e
end
local function normal(e,g,v)assert(e.world.gravity==g,'scalar '..e.world.gravity);assert(e.world.physics== (v or Vector(0,0,-g)),'physics '..tostring(e.world.physics))end
local function cleared(e)assert(not e.world.files[J],'journal remains');assert(not e.ZC_HMCD_MOON_GRAVITY_STATE.recovery)end
test('old bug: complete map interruption leaves gravity at 180',function()local e=env(oldCode);e:start();e=e:nextMap();e:init();normal(e,180)end)
test('new module: interrupted active moon restores 600',function()local e=env(code);e:start();e=e:nextMap();e:init();normal(e,600);cleared(e)end)
test('normal cleanup restores custom scalar and vector',function()local v=Vector(7,8,-410);local e=env(code,world(720,v));e:start();e:cancel();e:pump();normal(e,720,v);cleared(e)end)
test('custom baseline survives map teardown with native JSON',function()local v=Vector(3,4,-810);local e=env(code,world(900,v));e:start();e=e:nextMap();e:init();normal(e,900,v);cleared(e)end)
for _,carry in ipairs({false,true})do for step=0,3 do
 test('application interrupted at command '..step..'; carry='..tostring(carry),function()
  local e=env(code);e:start(false);e:pump(step);e=e:nextMap(carry);e:init();normal(e,600);cleared(e)
 end)
 test('restoration interrupted at command '..step..'; carry='..tostring(carry),function()
  local e=env(code);e:start();e:cancel();e:pump(step);e=e:nextMap(carry);e:init();normal(e,600);cleared(e)
 end)
end end
for step=0,3 do test('recovery itself interrupted at command '..step,function()
 local e=env(code);e:start();e=e:nextMap();e:fire('InitPostEntity');e:pump(step);e=e:nextMap(true);e:init();normal(e,600);cleared(e)
end)end
test('journal exists before submitting the gravity write',function()local e=env(code);e:start(false);e:pump(1);normal(e,600);assert(e.world.files[J] and e.world.queue[1]=='sv_gravity 180')end)
test('disk write failure prevents low-gravity application',function()local e=env(code);e.world.writeFail=true;e:start();normal(e,600);assert(#e.logs>0)end)
test('admin gravity change ends ownership',function()local e=env(code);e:start();e:set(450);e:cancel();e:pump();e=e:nextMap();e:init();normal(e,450);cleared(e)end)
test('new map custom gravity wins',function()local e=env(code);e:start();e=e:nextMap();e:set(800);e:init();normal(e,800);cleared(e)end)
test('absence of journal does not blindly reset existing 180',function()local e=env(code,world(180));e:init();normal(e,180);cleared(e)end)
test('crash-like map-state loss still recovers',function()local e=env(code);e:start();e=e:nextMap(false,false);e:init();normal(e,600);cleared(e)end)
test('old command tokens cannot affect next-map recovery',function()
 local e=env(code);e:start();local token=e.ZC_HMCD_MOON_GRAVITY_STATE.lease.token;e=e:nextMap()
 e.commands.zc_moon_gravity_internal(nil,'',{token,'recovered'});assert(e.ZC_HMCD_MOON_GRAVITY_STATE.recovery.phase=='pending');e:init();normal(e,600)
end)
test('player cannot invoke internal gravity command',function()local e=env(code);e:start(false);local s=e.ZC_HMCD_MOON_GRAVITY_STATE.lease;e.commands.zc_moon_gravity_internal({valid=true},'',{s.token,'apply'});normal(e,600)end)
test('native JSON rejects malformed record without gravity change',function()local w=world(180);w.files[J]='{}';local e=env(code,w);e:init();normal(e,180);assert(e.ZC_HMCD_MOON_GRAVITY_STATE.recoveryError)end)
test('failed engine restore retains journal and reports failure',function()local e=env(code);e:start();e=e:nextMap();e.world.commandFail=true;e:init();normal(e,180);assert(e.world.files[J] and #e.logs>0)end)
test('same-map framework reload restores active lease',function()local e=env(code);e:start();e:cancel();e.ZC_HMCD_MUTATORS.definitions={};e:load();e:init();normal(e,600);cleared(e)end)
return results
end
