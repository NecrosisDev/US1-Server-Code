assert(SERVER and engine.ActiveGamemode()=="zcity")
local body=assert(file.Read("autorun/server/zc_poop_eat.lua","LUA"))
assert(util.SHA256(body)=="1b5782020ecb62f7947f2afc59c4710c1252801aa594ba059498a533623c9782")
local blood=assert(file.Read("homigrad/organism/tier_1/modules/sv_blood.lua","LUA"))
assert(util.SHA256(blood)=="01c885c465e54d881acaee9df51b90b07cab21352065af5508ed6027fb0b6fed","Native source changed")
local a=assert(blood:find("function hg.organism.Vomit(",1,true)) local b=assert(blood:find("function hg.organism.CoughBlood(",a,true))
local tests=(function()
return function(source,native)
local results={}
local function check(name,fn)local ok,err=pcall(fn);results[#results+1]={name=name,pass=ok,error=not ok and tostring(err)or nil}end
local function compiler(text,name)
    if type(CompileString)=="function"then return assert(CompileString(text,name,false))end
    return assert(loadstring(text,name))
end
local function setup()
    local env=setmetatable({SERVER=true,ZCityPoopEat=false,ZCityPillCompat=false,clock=0,sounds=0,
        notices={},hooks={},timers={},calls=0,logs=0,assets=true},{__index=_G})
    env.IN_USE=32;env.OBS_MODE_NONE=0;env.MASK_SOLID=1;env.CHAN_AUTO=0
    env.CurTime=function()return env.clock end
    env.IsValid=function(p)return type(p)=="table"and p.valid==true end
    local mt={};mt.__index=mt
    local function vec(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0,[3]=z or 0},mt)end
    function mt:DistToSqr(b)return (self.x-b.x)^2+(self.y-b.y)^2+(self.z-b.z)^2 end
    function mt.__add(a,b)return vec(a.x+b.x,a.y+b.y,a.z+b.z)end
    function mt.__mul(a,b)return vec(a.x*b,a.y*b,a.z*b)end
    env.math=setmetatable({Clamp=function(n,a,b)return math.max(a,math.min(b,n))end},{__index=math})
    env.file={Exists=function()return env.assets end,CreateDir=function()end,Append=function()env.logs=env.logs+1 end}
    env.hook={Add=function(e,id,fn)env.hooks[e]=env.hooks[e]or {};env.hooks[e][id]=fn end}
    env.timer={Create=function(id,delay,reps,fn)env.timers[id]=fn end}
    env.resource={AddFile=function()end}
    env.util={PrecacheSound=function()end,TraceLine=function()return {Hit=env.wall==true,Entity=env.wall and {}or nil}end}
    env.net={Start=function()end,WriteEntity=function()end,WriteString=function()end,WriteMatrix=function()end,
        WriteVector=function()end,Broadcast=function()end}
    env.ThatPlyIsFemale=function()return false end
    env.ZCityPoop={owned={},accounts={a={poops={}}},Cooldown=30,Limit=2}
    local function player()
        local p={valid=true,alive=true,team=1,mode=0,pressed=true,vars={},pos=vec(0,0,30),Karma=100}
        p.organism={owner=p,alive=true,blood=10000,pulse=70,brain=0,otrub=false}
        function p:IsPlayer()return true end;function p:Alive()return self.alive end
        function p:Team()return self.team end;function p:GetObserverMode()return self.mode end
        function p:InVehicle()return self.vehicle end;function p:KeyPressed()return self.pressed end
        function p:EyePos()return self.pos end
        function p:LookupBone()return self.nohead and nil or 0 end
        function p:GetBoneMatrix()
            if self.nomatrix then return end
            return {GetAngles=function()return {Right=function()return vec(0,1,0)end,Forward=function()return vec(1,0,0)end}end,
                GetTranslation=function()return self.pos end}
        end
        function p:EmitSound(sound)env.sounds=env.sounds+1;env.lastSound=sound end
        function p:Notify(...)env.notices[#env.notices+1]={...};return true end
        function p:GetNetVar(k,d)local v=self.vars[k];if v==nil then return d end;return v end
        function p:SetNetVar(k,v)self.vars[k]=v end
        return p
    end
    local p,q=player(),player()
    env.hg={organism={},GetCurrentCharacter=function(p)return p end,IsValidPlayer=function(p)return env.IsValid(p)and p:Alive()and p.organism end}
    local original=compiler("local function _zcj_med()end\n"..native.."\nreturn hg.organism.Vomit","native_vomit_fixture")
    setfenv(original,env);original=original()
    env.hg.organism.Vomit=function(p)env.calls=env.calls+1;return original(p)end
    local fn=compiler(source,"poop_eating_fixture");setfenv(fn,env);fn()
    local function prop()
        local ent={valid=true,pos=vec(0,0,0)}
        function ent:NearestPoint()return self.pos end
        function ent:WorldSpaceCenter()return self.pos end
        function ent:Remove()self.valid=false;if self.onremove then self.onremove()end end
        env.ZCityPoop.owned[ent]=true;table.insert(env.ZCityPoop.accounts.a.poops,ent)
        return ent
    end
    local ent=prop();local c=env.ZCityPoopEat
    local function advance(t)env.clock=t;c.Tick()end
    return env,c,p,q,ent,advance,prop,fn
end
check('USE consumes one managed poop, native eating sound and exact notify',function()
 local e,c,p,q,ent=setup();assert(c.Eat(p,ent));assert(not ent.valid and #e.ZCityPoop.accounts.a.poops==0)
 assert(e.sounds==1 and e.lastSound=='snd_jack_hmcd_eat1.wav')
 assert(#e.notices==1 and e.notices[1][1]=='Why did I do that?'and e.notices[1][3]=='zc_poop_regret')
end)
check('No vomiting before three seconds; first pulse at three',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);advance(2.999);assert(e.calls==0);advance(3);assert(e.calls==1)
end)
check('Actual native vomiting deducts 200 blood and applies native state',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);advance(3);assert(p.organism.blood==9800 and p.vars.vomiting==4.5)
end)
check('Sixty-second window gives forty normal pulses then stops',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent)
 for i=0,39 do advance(3+i*1.5)end
 assert(e.calls==40 and p.organism.blood==2000 and p.vars.vomiting==63)
 advance(63);advance(90);assert(e.calls==40 and c.states[p]==nil)
end)
check('Owner immunity does not excuse voluntarily eating own poop',function()
 local e,c,p,q,ent,advance=setup();assert(c.Eat(p,ent));advance(3);assert(e.calls==1)
end)
check('No duplicate consume under repeated callbacks',function()
 local e,c,p,q,ent=setup();assert(c.Eat(p,ent));for i=1,10 do assert(not c.Eat(p,ent))end
 assert(c.stats.eaten==1 and e.sounds==1)
end)
check('Removal reentry cannot let second player eat same prop',function()
 local e,c,p,q,ent=setup();ent.onremove=function()assert(not c.Eat(q,ent))end
 assert(c.Eat(p,ent));assert(not c.states[q])
end)
check('Another poop cannot stack an active sickness',function()
 local e,c,p,q,ent,advance,prop=setup();c.Eat(p,ent);local b=prop();assert(not c.Eat(p,b)and b.valid)
end)
check('Independent players can consume separate poops',function()
 local e,c,p,q,ent,advance,prop=setup();assert(c.Eat(p,ent));assert(c.Eat(q,prop()));advance(3);assert(e.calls==2)
end)
check('Existing episode finishes before another may start',function()
 local e,c,p,q,ent,advance,prop=setup();c.Eat(p,ent);advance(63);assert(c.Eat(p,prop()))
end)
check('Foreign props and ordinary USE are untouched',function()
 local e,c,p,q,ent=setup();e.ZCityPoop.owned[ent]=nil;assert(c.Use(p,ent)==nil and ent.valid and e.calls==0)
end)
check('Managed poop blocks normal prop pickup after USE',function()
 local e,c,p,q,ent=setup();assert(c.Use(p,ent)==false and not ent.valid)
end)
check('Holding USE is not a new press',function()
 local e,c,p,q,ent=setup();p.pressed=false;assert(not c.Eat(p,ent)and ent.valid)
end)
check('Range limit prevents distant consumption',function()
 local e,c,p,q,ent=setup();p.pos.z=200;assert(not c.Eat(p,ent)and ent.valid)
end)
check('Solid obstructions block consumption',function()
 local e,c,p,q,ent=setup();e.wall=true;assert(not c.Eat(p,ent)and ent.valid)
end)
check('Dead spectator and vehicle users cannot eat',function()
 local e,c,p,q,ent=setup();p.alive=false;assert(not c.Eat(p,ent));p.alive=true;p.team=1002;assert(not c.Eat(p,ent))
 p.team=1;p.mode=4;assert(not c.Eat(p,ent));p.mode=0;p.vehicle=true;assert(not c.Eat(p,ent));assert(ent.valid)
end)
check('Unconscious users cannot initiate consumption',function()
 local e,c,p,q,ent=setup();p.organism.otrub=true;assert(not c.Eat(p,ent)and ent.valid)
end)
check('Protected pill carrier cannot eat or receive human vomiting',function()
 local e,c,p,q,ent,advance=setup();e.ZCityPillCompat={IsCarrier=function()return true end}
 assert(not c.Eat(p,ent));e.ZCityPillCompat=false;c.Eat(p,ent);e.ZCityPillCompat={IsCarrier=function()return true end}
 advance(3);assert(e.calls==0 and c.states[p]==nil)
end)
check('Death during delay cancels illness',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);p.alive=false;advance(3);assert(e.calls==0 and not c.states[p])
end)
check('Death during vomiting cancels remaining damage',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);advance(3);p.alive=false;advance(4.5);assert(e.calls==1)
end)
for _,event in ipairs({'PlayerSpawn','PlayerDeath','PlayerSilentDeath','PlayerDisconnected','ZB_EndRound','PostCleanupMap'})do
 check('Lifecycle clears episode: '..event,function()
  local e,c,p,q,ent,advance=setup();c.Eat(p,ent);e.hooks[event].ZCityPoop_EatingReset(p);advance(3);assert(e.calls==0 and not c.states[p])
 end)
end
check('New organism cannot inherit previous body illness',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);p.organism={alive=true,blood=5000,pulse=70};advance(3);assert(e.calls==0)
end)
check('Becoming unconscious does not cancel an already consumed dose',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);p.organism.otrub=true;advance(3);assert(e.calls==1)
end)
check('Native blood loss is clamped naturally at zero',function()
 local e,c,p,q,ent,advance=setup();p.organism.blood=50;c.Eat(p,ent);advance(3);assert(p.organism.blood==0)
end)
check('Already vomiting does not receive an overlapping damage pulse',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);p.vars.vomiting=4;advance(3);assert(e.calls==0);advance(4);assert(e.calls==1)
end)
check('Server stall never backfills missed damage ticks',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);advance(30);assert(e.calls==1);advance(63);assert(e.calls==1)
end)
check('Missing asset or head matrix does not consume prop',function()
 local e,c,p,q,ent=setup();e.assets=false;assert(not c.Eat(p,ent));e.assets=true;p.nomatrix=true;assert(not c.Eat(p,ent));assert(ent.valid)
end)
check('Missing native service never consumes prop',function()
 local e,c,p,q,ent=setup();e.hg.organism.Vomit=nil;assert(not c.Eat(p,ent)and ent.valid)
end)
check('Runtime native error stops episode and logs once',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);e.hg.organism.Vomit=function()error('fixture error')end
 advance(3);advance(5);assert(not c.states[p]and c.stats.errors==1 and e.logs==1)
end)
check('Removal failure has no queued sickness',function()
 local e,c,p,q,ent=setup();ent.Remove=function()error('remove error')end
 assert(not c.Eat(p,ent)and not c.states[p]and ent.valid and e.sounds==0)
end)
check('Hot reload retains original delay and single timer identity',function()
 local e,c,p,q,ent,advance,prop,load=setup();c.Eat(p,ent);e.clock=2;load()
 assert(e.ZCityPoopEat==c and c.states[p].starts==3);advance(3);assert(e.calls==1)
end)
check('No change to karma brain or poop spawn limits',function()
 local e,c,p,q,ent,advance=setup();c.Eat(p,ent);advance(3)
 assert(p.Karma==100 and p.organism.brain==0 and e.ZCityPoop.Cooldown==30 and e.ZCityPoop.Limit==2)
end)
return results
end

end)() local rows=tests(body,blood:sub(a,b-1))
file.CreateDir("zc_poop") file.Write("zc_poop/eating_tests.json",util.TableToJSON(rows,true))
for _,r in ipairs(rows)do assert(r.pass,r.name..": "..tostring(r.error))end
assert(file.Exists("sound/snd_jack_hmcd_eat1.wav","GAME"),"Eating sound missing")
local C=assert(ZCityPoop) local old=C.Callback local native=hg.organism.Vomit local odor=ZCityPoopOdor.Callback
include("autorun/server/zc_poop_eat.lua") local E=assert(ZCityPoopEat)
assert(E.Delay==3 and E.Duration==60 and E.VomitInterval==1.5)
assert(hook.GetTable().PlayerUse.ZCityPoop_Eat==E.Use and timer.Exists("ZCityPoop_Eating"))
assert(C.Callback==old and C.Cooldown==30 and C.Limit==2 and hg.organism.Vomit==native and ZCityPoopOdor.Callback==odor)
file.Write("zc_poop/eating_deployed.json",util.TableToJSON({version=E.Version,passed=true,time=os.time(),test_count=#rows,delay=E.Delay,duration=E.Duration,interval=E.VomitInterval,source_hash=util.SHA256(body),active_timer=timer.Exists("ZCityPoop_Eating"),native_handler_unchanged=true,stats=E.stats,players=#player.GetAll()},true))
print("ZC_POOP_EATING_ACTIVE",E.Version,#rows)
