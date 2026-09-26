-- Server-only balance update. No player damage tests or chat announcements.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local function up(fn,key)
 for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then return end;if n==key then return v end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state,commit,sync=assert(up(action,"state")),assert(up(action,"Commit")),assert(up(action,"SyncTo"))
assert(not up(action,"loadError"),"Guide locked")
local candidate=assert(util.JSONToTable(file.Read("zc_brain_balance_guide.txt","DATA")))
assert(candidate.revision==24 and #candidate.pages==#state.pages)
assert(state.revision==23 or state.revision==24,"Guide changed")
if state.revision==23 then assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="a143e676ff8e8fef5299adce3f8d005da844b28c9b64d76eafeb49eed1545bd3") end
local specs={{"zc_guilt_justice/meta.lua","291604b25eae4e35598fc8b66f68c7705d19e643139a5a0d3309bbdcf964c0ab"},{"autorun/server/zc_ff_brain.lua","499dfe06a1e552457bed20aede8595244834cd22f1ab3e13abcfe07543acd062"}}
local compiled={}
for _,s in ipairs(specs) do
 local body=assert(file.Read(s[1],"LUA"));assert(util.SHA256(body)==s[2],s[1])
 local f=CompileString(body,s[1],false);assert(isfunction(f),tostring(f));compiled[s[1]]=f
end
local M=assert(ZCityMetaSafety);assert(not M.loadError,"Private journal locked")
local snapshot="zc_guilt_justice/brain_balance_before_20260916_2.txt"
if not file.Exists(snapshot,"DATA") then
 file.CreateDir("zc_guilt_justice")
 local raw=assert(util.TableToJSON({accounts=M.accounts},true));file.Write(snapshot,raw)
 assert(file.Read(snapshot,"DATA")==raw,"Snapshot failed")
end
compiled["zc_guilt_justice/meta.lua"]()
assert(not M.loadError,"Queued dose migration failed")
compiled["autorun/server/zc_ff_brain.lua"]()
local F=ZCityFFBrain
assert(F.Version=="20260916.2" and M.Version=="20260916.2")
assert(F.Settings.scale==0.0005 and F.Settings.burstCap==0.0175)
assert(F.Settings.lifeCap==0.10 and F.Settings.absoluteCap==0.125)
assert(math.abs(F.KarmaRate(25)-0.002)<0.0000001)
assert(F.VictimScale(zb.modes.tdm)==0.75 and F.VictimScale(zb.modes.hmcd)==1)
F.InstallPillBridge();F.InstallDamagePriority()
local count=0
for _,r in pairs(M.accounts) do assert(r.brainDoseVersion==2);count=count+1 end
if state.revision==23 then local ok,err=commit(candidate);assert(ok,tostring(err)) end
state=assert(up(action,"state"));assert(state.revision==24);sync()
local report={version=F.Version,meta=M.Version,guide=state.revision,accounts=count,
 reflectionScale=F.Settings.scale,burstCap=F.Settings.burstCap,lifeCap=F.Settings.lifeCap,
 absoluteCap=F.Settings.absoluteCap,rateAt25=F.KarmaRate(25),privacyLocked=M.Locked()==true,
 ffMultiplier=GetConVar("zc_ff_brain_scale"):GetFloat(),karmaMultiplier=GetConVar("zc_karma_brain_scale"):GetFloat(),
 queuedMigrationSaved=not M.loadError,tdmRetention=F.VictimScale(zb.modes.tdm),
 homicideRetention=F.VictimScale(zb.modes.hmcd),time=os.time()}
file.Write("zc_brain_balance_deployed.json",util.TableToJSON(report,true))
print("ZC_BRAIN_BALANCE_ACTIVE",F.Version,"guide",state.revision)
