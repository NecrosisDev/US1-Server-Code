-- Explicit smoke test and activation; never forces a real player to vomit.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local source=assert(file.Read("autorun/server/zc_poop_odor.lua","LUA"))
assert(util.SHA256(source)=="9c8809c03b9540c02ef1fec7a96b6550f6942690799f3c76fcbec314196b0169")
local test=(function()
-- Isolated source tests; all entities/services below are test doubles.
return function(source)
    local rows={}
    local function check(name,fn)
        local ok,err=pcall(fn)
        rows[#rows+1]={name=name,pass=ok,error=not ok and tostring(err)or nil}
    end
    local function setup()
        local e=setmetatable({SERVER=true,ZCityPoopOdor=false,ZCityPillCompat=false,clock=0,list={},blocked=false,notices=0,vomits=0,logs=0},{__index=_G})
        local vec={};vec.__index=vec
        local function V(x,y,z)return setmetatable({x=x,y=y or 0,z=z or 0},vec)end
        function vec:DistToSqr(b)return (self.x-b.x)^2+(self.y-b.y)^2+(self.z-b.z)^2 end
        e.IsValid=function(x)return type(x)=="table"and x.valid==true end
        e.OBS_MODE_NONE=0;e.MASK_SOLID_BRUSHONLY=16395
        e.CurTime=function()return e.clock end;e.RealTime=e.CurTime
        e.file={CreateDir=function()end,Append=function()e.logs=e.logs+1 end}
        e.util={TraceLine=function(t)e.trace=t;return {Hit=e.blocked,StartSolid=e.startsolid}end}
        local timers,hooks={},{}
        e.timer={Create=function(n,delay,count,fn)timers[n]={delay=delay,count=count,fn=fn}end}
        e.hook={Add=function(n,id,fn)hooks[n]=fn end};e.hooks=hooks;e.timers=timers
        e.player={GetAll=function()return e.list end}
        e.hg={organism={Vomit=function(p)
            e.vomits=e.vomits+1;p.vomits=(p.vomits or 0)+1
            if e.vomitError then error("native vomit test error")end
        end},IsValidPlayer=function(p)return p.valid and p.alive end,
        GetCurrentCharacter=function(p)return p.fake or p end}
        local C={accounts={},owned={}}
        C.Body=function(p)return p.fake or p end;e.ZCityPoop=C
        local function player(id,x)
            local p={valid=true,alive=true,team=1,observer=0,id=id,position=V(x or 0),Karma=100,
                organism={alive=true,otrub=false,blood=5000,pulse=70,brain=0},notices=0}
            function p:IsPlayer()return true end;function p:Alive()return self.alive end
            function p:Team()return self.team end;function p:GetObserverMode()return self.observer end
            function p:IsBot()return self.bot==true end;function p:UserID()return self.uid end
            function p:SteamID64()return self.id end;function p:WorldSpaceCenter()return self.position end
            function p:LookupBone()return self.nohead and nil or 0 end
            function p:GetBoneMatrix()return not self.nomatrix and {}or nil end
            function p:GetNetVar()return self.vomiting or 0 end
            function p:Notify(msg,delay,key,when)
                if e.notifyError then error("native notify test error")end
                self.notices=self.notices+1;e.notices=e.notices+1;e.lastNotice={msg,delay,key,when}
                return true
            end
            e.list[#e.list+1]=p;return p
        end
        local function poop(owner,x)
            local ent={valid=true,position=V(x or 0)}
            function ent:WorldSpaceCenter()return self.position end
            C.accounts[owner]=C.accounts[owner]or{poops={}}
            table.insert(C.accounts[owner].poops,ent);C.owned[ent]=true
            return ent
        end
        local chunk
        if type(CompileString)=="function"then chunk=CompileString(source,"poop_odor_test_subject",false)
        else chunk=loadstring(source,"poop_odor_test_subject")end
        assert(type(chunk)=="function",tostring(chunk));setfenv(chunk,e);chunk()
        local S=e.ZCityPoopOdor
        local function tick(t)e.clock=t;S.Tick()end
        local function through(a,b)for n=a*2,b*2 do tick(n/2)end end
        return e,S,player,poop,tick,through,V,C,chunk
    end
    check("exact ZCity notice text and channel, owner also smells it",function()
        local e,s,p,drop,tick=setup();p("owner");drop("owner");tick(0)
        assert(e.notices==1 and e.lastNotice[1]=="It smells like shit over here.")
        assert(e.lastNotice[2]==30 and e.lastNotice[3]=="zc_poop_smell" and e.lastNotice[4]==0)
    end)
    check("native vomit after more than ten continuous seconds, not at ten",function()
        local e,s,p,drop,tick,run=setup();p("visitor");drop("owner");run(0,10)
        assert(e.vomits==0);tick(10.5);assert(e.vomits==1)
    end)
    check("own poop never induces vomiting",function()
        local e,s,p,drop,tick,run=setup();p("owner");drop("owner");run(0,60)
        assert(e.vomits==0 and e.notices==1)
    end)
    check("creator can vomit near someone else's poop",function()
        local e,s,p,drop,tick,run=setup();p("owner");drop("owner");drop("other");run(0,11);assert(e.vomits==1)
    end)
    check("multiple overlapping poops cannot accelerate or stack vomiting",function()
        local e,s,p,drop,tick,run=setup();p("visitor");for i=1,10 do drop("owner"..i)end
        run(0,60);assert(e.vomits==1 and e.notices==1)
    end)
    check("moving between overlapping foreign poops keeps the same exposure",function()
        local e,s,p,drop,tick,run,V=setup();local v=p("visitor");local a=drop("a");local b=drop("b",100)
        run(0,6);a.valid=false;run(6.5,10.5);assert(e.vomits==1)
    end)
    check("leaving resets exposure and returning requires a new ten seconds",function()
        local e,s,p,drop,tick,run,V=setup();local v=p("visitor");drop("owner");run(0,8)
        v.position=V(500);tick(8.5);v.position=V(0);run(9,19);assert(e.vomits==0)
        tick(19.5);assert(e.vomits==1)
    end)
    check("vomits only once while staying in range, fresh visit may vomit again",function()
        local e,s,p,drop,tick,run,V=setup();local v=p("visitor");drop("owner");run(0,40);assert(e.vomits==1)
        v.position=V(500);tick(40.5);v.position=V(0);run(41,52);assert(e.vomits==2)
    end)
    check("native notice cannot spam from rapid reentry",function()
        local e,s,p,drop,tick,run,V=setup();local v=p("v");drop("a");tick(0)
        for i=1,10 do v.position=V(500);tick(i);v.position=V(0);tick(i+.5)end
        assert(e.notices==1);v.position=V(500);tick(30);v.position=V(0);tick(30.5);assert(e.notices==2)
    end)
    check("radius is 160 Source units",function()
        local e,s,p,drop,tick=setup();p("v",160.01);drop("a");tick(0);assert(e.notices==0)
        e.list[1].position.x=160;tick(.5);assert(e.notices==1)
    end)
    check("wall obstruction prevents both notice and exposure",function()
        local e,s,p,drop,tick,run=setup();p("v");drop("a");e.blocked=true;run(0,20)
        assert(e.notices==0 and e.vomits==0 and e.trace.mask==e.MASK_SOLID_BRUSHONLY)
    end)
    check("start-solid traces are not odor connections",function()
        local e,s,p,drop,tick,run=setup();p("v");drop("a");e.startsolid=true;run(0,20);assert(e.notices==0 and e.vomits==0)
    end)
    check("spectators and dead players have no notice or vomiting",function()
        local e,s,p,drop,tick,run=setup();local a=p("a");a.team=1002
        local b=p("b");b.alive=false;local c=p("c");c.observer=4;drop("owner");run(0,20)
        assert(e.notices==0 and e.vomits==0)
    end)
    check("unconscious player does not accumulate exposure",function()
        local e,s,p,drop,tick,run=setup();local a=p("v");a.organism.otrub=true;drop("owner");run(0,20)
        a.organism.otrub=false;run(21,31);assert(e.vomits==0);tick(31.5);assert(e.vomits==1)
    end)
    check("hidden pill carrier is not passed to human vomiting",function()
        local e,s,p,drop,tick,run=setup();local a=p("v");drop("owner")
        e.ZCityPillCompat={IsCarrier=function()return true end};run(0,20);assert(e.vomits==0 and e.notices==1)
    end)
    check("real ragdoll body position determines proximity",function()
        local e,s,p,drop,tick,run=setup();local a=p("v",500);a.fake=p("body",0);a.fake.team=1002
        drop("owner");run(0,11);assert(a.vomits==1 and e.vomits==1)
    end)
    check("deleted poops and decal-only leftovers have no smell",function()
        local e,s,p,drop,tick,run=setup();p("v");local a=drop("owner");run(0,8);a.valid=false;run(8.5,20);assert(e.vomits==0)
    end)
    check("unregistered props cannot spoof ownership",function()
        local e,s,p,drop,tick,run,V,C=setup();p("v");local a=drop("owner");C.owned[a]=nil;run(0,20);assert(e.notices==0 and e.vomits==0)
    end)
    check("spawn and organism replacement discard old exposure",function()
        local e,s,p,drop,tick,run=setup();local a=p("v");drop("owner");run(0,9)
        e.hooks.PlayerSpawn(a);tick(9.5);assert(e.vomits==0)
        a.organism={alive=true,blood=5000,pulse=70};run(10,20);assert(e.vomits==0);tick(20.5);assert(e.vomits==1)
    end)
    check("round cleanup and disconnect discard exposure state",function()
        local e,s,p,drop,tick,run=setup();local a=p("v");drop("owner");run(0,5)
        e.hooks.ZB_EndRound();assert(next(s.states)==nil);tick(6);e.hooks.PlayerDisconnected(a);assert(s.states[a]==nil)
    end)
    check("missing native services never fabricate a vomit or a chat fallback",function()
        local e,s,p,drop,tick,run=setup();p("v");drop("owner");e.hg.organism.Vomit=nil;run(0,20)
        assert(e.vomits==0 and e.logs==0)
    end)
    check("already vomiting player waits instead of stacking effects",function()
        local e,s,p,drop,tick,run=setup();local a=p("v");a.vomiting=20;drop("owner");run(0,19.5)
        assert(e.vomits==0);tick(20);assert(e.vomits==1)
    end)
    check("missing head matrix avoids native partial injury",function()
        local e,s,p,drop,tick,run=setup();local a=p("v");a.nomatrix=true;drop("owner");run(0,20)
        assert(e.vomits==0 and a.organism.blood==5000)
    end)
    check("long server pause is not ten verified seconds in the area",function()
        local e,s,p,drop,tick,run=setup();p("v");drop("owner");tick(0);tick(100)
        assert(e.vomits==0);run(100.5,110);assert(e.vomits==0);tick(110.5);assert(e.vomits==1)
    end)
    check("backwards clock restarts exposure safely",function()
        local e,s,p,drop,tick,run=setup();p("v");drop("owner");run(50,55);run(0,10);assert(e.vomits==0);tick(10.5);assert(e.vomits==1)
    end)
    check("native vomiting error is not retried in a storm",function()
        local e,s,p,drop,tick,run=setup();p("v");drop("owner");e.vomitError=true;run(0,40)
        assert(e.vomits==1 and e.logs==1 and s.stats.errors==1)
    end)
    check("reload preserves live visits and replaces single timer",function()
        local e,s,p,drop,tick,run,V,C,chunk=setup();p("v");drop("owner");run(0,11);chunk();run(11.5,30)
        assert(e.vomits==1 and e.ZCityPoopOdor==s and e.timers.ZCityPoop_Odor.delay==.5)
    end)
    check("account rather than player entity owns immunity",function()
        local e,s,p,drop,tick,run=setup();p("owner");p("owner");drop("owner");run(0,20);assert(e.vomits==0)
    end)
    check("no role or karma gates and no account or injury mutation outside native call",function()
        local e,s,p,drop,tick,run=setup();local a=p("a");a.traitor=true;a.Karma=1
        local b=p("b");b.traitor=false;b.Karma=120;drop("owner");run(0,11)
        assert(a.vomits==1 and b.vomits==1 and a.Karma==1 and b.Karma==120)
        assert(a.organism.blood==5000 and b.organism.brain==0)
    end)
    return rows
end

end)()
local prior=ZCityPoopOdor
local originalC=assert(ZCityPoop)
local originalCommand=concommand.GetTable().poop
local originalVomit=assert(hg.organism.Vomit)
local originalNotify=assert(FindMetaTable("Player").Notify)
local results=test(source)
assert(#results==29)
for _,r in ipairs(results)do assert(r.pass,r.name..": "..tostring(r.error))end
assert(ZCityPoopOdor==prior and ZCityPoop==originalC,"Tests escaped isolation")
include("autorun/server/zc_poop_odor.lua")
local S=assert(ZCityPoopOdor)
assert(S.Version=="20260918.1" and S.Radius==160 and S.ExposureSeconds==10)
assert(S.Interval==0.5 and timer.Exists("ZCityPoop_Odor"))
assert(originalC.Cooldown==30 and originalC.Limit==2)
assert(concommand.GetTable().poop==originalCommand)
assert(hg.organism.Vomit==originalVomit and FindMetaTable("Player").Notify==originalNotify)
local report={version=S.Version,passed=true,tests=results,test_count=#results,
 source_hash=util.SHA256(source),radius=S.Radius,exposure_seconds=S.ExposureSeconds,
 once_per_visit=true,owner_exempt=true,native_notify=true,native_vomit=true,
 time=os.time(),manual_multiplayer_test=false}
local function save()
 report.time=os.time();report.stats=table.Copy(S.stats)
 report.active_timer=timer.Exists("ZCityPoop_Odor");report.players=#player.GetAll()
 file.CreateDir("zc_poop");file.Write("zc_poop/odor_deployed.json",util.TableToJSON(report,true))
end
save();timer.Simple(3,save)
print("ZC_POOP_ODOR_ACTIVE",S.Version,#results)
