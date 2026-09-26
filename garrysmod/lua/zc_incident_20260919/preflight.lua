-- Isolated exact-source regression tests. No live entities, hooks or net sends.
local source = assert(file.Read("zc_incident_20260919/networking_candidate.lua", "LUA"))
local compiled = CompileString(source, "zc_wound_queue_candidate", false)
assert(isfunction(compiled), tostring(compiled))
local results = {kind="isolated_fixture", candidate=util.SHA256(source), time=os.time(), tests={}}
local function clone(v)
    if isvector(v) then return Vector(v.x,v.y,v.z) end
    if isangle(v) then return Angle(v.p,v.y,v.r) end
    if not istable(v) then return v end
    local t={}; for k,x in pairs(v) do t[k]=clone(x) end; return t
end
local function sandbox()
    local em,pm={},{}
    setmetatable(pm,{__index=em})
    local enabled=true
    local messages,hooks={},{}
    local current
    local netstub={Receive=function()end}
    function netstub.Start(name)current={name=name,writes={}}end
    local function write(kind,value)current.writes[#current.writes+1]={kind=kind,value=clone(value)}end
    function netstub.WriteUInt(v,b)write("uint"..b,v)end
    function netstub.WriteString(v)write("string",v)end
    function netstub.WriteType(v)write("type",v)end
    function netstub.BytesWritten()return 20 end
    function netstub.Broadcast()current.receiver=false; messages[#messages+1]=current end
    function netstub.Send(receiver)current.receiver=receiver; messages[#messages+1]=current end
    local env={CLIENT=false,SERVER=true,ZCWoundQueue=false,zb={},net=netstub,
        util={AddNetworkString=function()end},gameevent={Listen=function()end},
        hook={Add=function(event,id,fn)hooks[event]=hooks[event] or {}; hooks[event][id]=fn end},
        FindMetaTable=function(name)return name=="Player" and pm or em end,
        CreateConVar=function()return {GetBool=function()return enabled end}end,
        IsValid=function(e)return istable(e) and e.valid==true end,
        Player=function()error("unexpected player lookup")end}
    setmetatable(env,{__index=_G})
    setfenv(compiled,env); compiled()
    local function entity(id,player)
        return setmetatable({valid=true,id=id,EntIndex=function(self)return self.id end},{__index=player and pm or em})
    end
    return {env=env,messages=messages,hooks=hooks,entity=entity,em=em,pm=pm,
        flush=env.ZCWoundQueue.Flush,stats=env.ZCWoundQueue.Stats,
        toggle=function(v)enabled=v end}
end
local function payload(m)return m.writes[3].value end
local function wound(n)return {{n,Vector(1,2,3),Angle(4,5,6),"bone",100}}end
local function test(name,fn)
    local ok,err=xpcall(function()fn(sandbox())end,debug.traceback)
    results.tests[#results.tests+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}
end

test("canonical state is synchronous and wire fields are unchanged",function(s)
    local e=s.entity(1); local v=wound(4)
    e:SetNetVar("wounds",v)
    assert(e:GetNetVar("wounds")==v and #s.messages==0)
    s.flush(); local m=s.messages[1]
    assert(m.name=="zbNetVarSet" and m.writes[1].kind=="uint16" and m.writes[1].value==1)
    assert(m.writes[2].value=="wounds" and m.writes[3].kind=="type" and payload(m)[1][1]==4)
end)
test("same-tick bursts publish only the last requested payload",function(s)
    local e=s.entity(1)
    for i=1,30 do e:SetNetVar("wounds",wound(i))end
    s.flush(); assert(#s.messages==1 and payload(s.messages[1])[1][1]==30 and s.stats.coalesced==29)
end)
test("different entities and the two wound keys are independent",function(s)
    local a,b=s.entity(1),s.entity(2)
    a:SetNetVar("wounds",wound(1)); a:SetNetVar("arterialwounds",wound(2)); b:SetNetVar("wounds",wound(3))
    s.flush(); assert(#s.messages==3)
end)
test("first empty is sent; repeated empty is suppressed",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",{}); s.flush()
    for i=1,20 do e:SetNetVar("wounds",{}); s.flush()end
    assert(#s.messages==1 and s.stats.emptySkipped==20)
end)
test("nonempty-to-empty transition is sent",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",{}); s.flush()
    e:SetNetVar("wounds",wound(1)); s.flush(); e:SetNetVar("wounds",{}); s.flush()
    assert(#s.messages==3 and next(payload(s.messages[3]))==nil)
end)
test("in-place table mutation cannot corrupt the queued snapshot",function(s)
    local e=s.entity(1); local v=wound(1); e:SetNetVar("wounds",v)
    v[1][1]=9; s.flush(); assert(payload(s.messages[1])[1][1]==1)
    e:SetNetVar("wounds",v); s.flush(); assert(payload(s.messages[2])[1][1]==9)
end)
test("Vector and Angle values are independently frozen",function(s)
    local e=s.entity(1); local v=wound(1); e:SetNetVar("wounds",v)
    v[1][2].x=99; v[1][3].p=77; s.flush()
    assert(payload(s.messages[1])[1][2].x==1 and payload(s.messages[1])[1][3].p==4)
end)
test("targeted send flushes prior broadcast before private state",function(s)
    local e,p=s.entity(1),s.entity(2,true)
    e:SetNetVar("wounds",wound(1)); e:SetNetVar("wounds",wound(2),p); s.flush()
    assert(#s.messages==2 and s.messages[1].receiver==false and s.messages[2].receiver==p)
    assert(payload(s.messages[1])[1][1]==1 and payload(s.messages[2])[1][1]==2)
end)
test("targeted state invalidates empty broadcast cache",function(s)
    local e,p=s.entity(1),s.entity(2,true)
    e:SetNetVar("wounds",{}); s.flush(); e:SetNetVar("wounds",wound(1),p)
    e:SetNetVar("wounds",{}); s.flush(); assert(#s.messages==3)
end)
test("full resync follows pending broadcasts with current state",function(s)
    local e,p=s.entity(1),s.entity(2,true); local v=wound(1)
    e:SetNetVar("wounds",v); v[1][1]=2; p:SyncVars(); s.flush()
    assert(#s.messages==2 and s.messages[1].receiver==false and s.messages[2].receiver==p)
    assert(payload(s.messages[1])[1][1]==1 and payload(s.messages[2])[1][1]==2)
end)
test("resync of aliased transient state cannot strand a joining client",function(s)
    local e,p=s.entity(1),s.entity(2,true); local v={}
    e:SetNetVar("wounds",v); s.flush(); v[1]=wound(1)[1]; p:SyncVars(); v[1]=nil
    e:SetNetVar("wounds",v); s.flush(); assert(#s.messages==3 and next(payload(s.messages[3]))==nil)
end)
test("clear cancels pending data and permits a new empty state",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",wound(1)); e:ClearNetVars(); s.flush()
    assert(#s.messages==1 and s.messages[1].name=="zbNetVarDelete")
    e:SetNetVar("wounds",{}); s.flush(); assert(#s.messages==2)
end)
test("removed entities cannot publish queued state",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",wound(1)); e.valid=false; s.flush()
    assert(#s.messages==0 and s.stats.invalidDiscarded==1)
end)
test("reused entity index starts without prior empty suppression",function(s)
    local a=s.entity(1); a:SetNetVar("wounds",{}); s.flush(); a:ClearNetVars(); a.valid=false
    local b=s.entity(1); b:SetNetVar("wounds",{}); s.flush(); assert(#s.messages==3)
end)
test("nil payload preserves prior broadcast ordering",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",wound(1)); e:SetNetVar("wounds",nil); s.flush()
    assert(#s.messages==2 and payload(s.messages[1])[1][1]==1 and payload(s.messages[2])==nil)
end)
test("unsupported table shapes use original immediate path",function(s)
    local e=s.entity(1); local v={custom={nested={1}}}; e:SetNetVar("wounds",v)
    assert(#s.messages==1 and payload(s.messages[1]).custom.nested[1]==1 and s.stats.fallback==1)
end)
test("ordinary inventory and scalar variables remain immediate",function(s)
    local e=s.entity(1); e:SetNetVar("Inventory",{a=1}); e:SetNetVar("Karma",5)
    assert(#s.messages==2 and s.stats.requested==0)
end)
test("disabled queue sends every update immediately",function(s)
    s.toggle(false); local e=s.entity(1)
    for i=1,10 do e:SetNetVar("wounds",{})end
    assert(#s.messages==10); s.flush(); assert(#s.messages==10)
end)
test("disabling with a pending payload preserves ordering",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",wound(1)); s.toggle(false); e:SetNetVar("wounds",wound(2)); s.flush()
    assert(#s.messages==2 and payload(s.messages[1])[1][1]==1 and payload(s.messages[2])[1][1]==2)
end)
test("existing scalar optimizer can retain its original SetNetVar",function(s)
    local original=s.em.SetNetVar; local calls=0
    s.em.SetNetVar=function(e,...)calls=calls+1; return original(e,...)end
    local e=s.entity(1); e:SetNetVar("wounds",{}); s.flush(); assert(calls==1 and #s.messages==1)
end)
test("multiple flushes do not duplicate messages",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",wound(1)); s.flush(); s.flush(); s.flush(); assert(#s.messages==1)
end)
test("tick hook performs publication",function(s)
    local e=s.entity(1); e:SetNetVar("wounds",wound(1)); s.hooks.Tick.ZC_WoundNetFlush(); assert(#s.messages==1)
end)
results.passed=true
for _,r in ipairs(results.tests) do if not r.pass then results.passed=false end end
file.CreateDir("zc_incident_20260919")
file.Write("zc_incident_20260919/preflight.json",util.TableToJSON(results,true))
print("ZC_INCIDENT_PREFLIGHT",results.passed,#results.tests,results.candidate)
