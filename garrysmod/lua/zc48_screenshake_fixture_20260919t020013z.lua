-- Exact-source fixture with mocked recipients and sends; affects no player.
local r={time=os.time(),tests={},liveEffectTriggered=false}
local source=assert(file.Read('homigrad/sh_utility.lua','LUA'))
local first=assert(source:find('function util.ScreenShake(',1,true))
local last=assert(source:find('local plyMeta = FindMetaTable',first,true))
local old=source:sub(first,last-1);r.sourceSHA256=util.SHA256(source)
local function replace(s,a,b)local x,y=s:find(a,1,true);assert(x,a);return s:sub(1,x-1)..b..s:sub(y+1)end
local candidate=replace(old,'ents.FindInSphere(vPos, nRadius * nRadius)','crfFilter and {} or ents.FindInSphere(vPos, nRadius)')
candidate=replace(candidate,'local crf = RecipientFilter()','local crf = crfFilter or RecipientFilter()')
local function trial(code,explicit)
 local e=setmetatable({SERVER=true,CLIENT=false,util={},net={},ents={},calls=0},{__index=_G});e._G=e
 local a={x=50,IsPlayer=function()return true end};local b={x=500,IsPlayer=function()return true end}
 local prop={x=60,IsPlayer=function()return false end};e.IsValid=function(v)return v==a or v==b or v==prop end
 e.RecipientFilter=function()return {players={},AddPlayer=function(self,p)self.players[#self.players+1]=p end}end
 e.ents.FindInSphere=function(_,radius)e.radius=radius;e.calls=e.calls+1;local t={};for _,p in ipairs({a,b,prop}) do if p.x<=radius then t[#t+1]=p end end;return t end
 for _,k in ipairs({'Start','WriteVector','WriteFloat','WriteBool'}) do e.net[k]=function()end end
 e.net.Send=function(filter)e.sent=filter end
 local f=CompileString(code,'screenshake_fixture',false);assert(type(f)=='function',tostring(f));setfenv(f,e);f()
 local given=explicit and e.RecipientFilter() or nil;if given then given:AddPlayer(b)end
 e.util.ScreenShake(Vector(),1,1,1,150,false,given)
 return {radius=e.radius,calls=e.calls,recipients=#e.sent.players,near=e.sent.players[1]==a,usesExplicit=e.sent==given}
end
local a=trial(old,false);local b=trial(old,true);local c=trial(candidate,false);local d=trial(candidate,true)
r.original={untargeted=a,targeted=b};r.candidate={untargeted=c,targeted=d}
r.tests={{name='original squared radius reproduced',pass=a.radius==22500 and a.recipients==2},
{name='original explicit recipient ignored',pass=not b.usesExplicit and b.recipients==2},
{name='candidate uses requested radius',pass=c.radius==150 and c.recipients==1 and c.near},
{name='candidate honors explicit filter without a world scan',pass=d.usesExplicit and d.calls==0 and d.recipients==1}}
r.passed=true;for _,t in ipairs(r.tests) do if not t.pass then r.passed=false end end
file.CreateDir('zc_48x60_audit')
file.Write('zc_48x60_audit/screenshake_fixture_20260919t020013z.json',util.TableToJSON(r,true))
file.Write('zc_48x60_audit/screenshake_candidate_20260919t020013z.txt',candidate)
print('ZC48_SCREENSHAKE_FIXTURE',r.passed)
