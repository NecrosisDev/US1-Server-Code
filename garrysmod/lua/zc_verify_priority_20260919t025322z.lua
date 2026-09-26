local r={time=os.time(),passed=false,masses={},livePlayerTest=false}
local ok,err=xpcall(function()
 local c,i,u=assert(ZCityPoop),assert(ZCityPoopInvoluntary),assert(ZCityUrine)
 assert(c.Version=='20260919.mass1' and i.Version=='20260919.mass1' and u.Version=='20260919.drips1','wrong runtime version')
 assert(concommand.GetTable().poop==c.Callback,'poop callback not linked')
 assert(timer.Exists('ZCityPoop_Involuntary') and timer.Exists('ZCityUrine_Tick') and timer.Exists('ZCityUrine_Bladder'))
 assert(#u.ImpactSounds==4)
 for n=1,4 do assert(u.ImpactSounds[n]=='homigrad/blooddrip'..n..'.wav') end
 for ent in pairs(c.owned) do if IsValid(ent) then local ph=ent:GetPhysicsObject();if IsValid(ph) then
  r.masses[#r.masses+1]=ph:GetMass();assert(math.abs(ph:GetMass()-c.Mass)<0.0001,'mass was overwritten')
 end end end
 local pre=util.JSONToTable(assert(file.Read('zc_repair_batches/preflight_priority_20260919t025322z.json','DATA')))
 for path,hash in pairs(pre.hashes) do assert(util.SHA256(assert(file.Read(path,'LUA')))==hash,'source changed '..path) end
 r.versions={poop=c.Version,involuntary=i.Version,urine=u.Version}
 r.stats={involuntary=table.Copy(i.stats),urine=table.Copy(u.stats)}
 r.commandSources={}
 for _,name in ipairs({'pee','+pee','-pee'}) do
  local f=assert(concommand.GetTable()[name]);r.commandSources[name]=debug.getinfo(f,'S').source
  assert(r.commandSources[name]=='@lua/autorun/server/zc_urine.lua','noncanonical command path')
 end
 r.mass=c.Mass;r.decal=util.DecalMaterial('YellowBlood');r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_repair_batches');file.Write('zc_repair_batches/verify_priority_20260919t025322z.json',util.TableToJSON(r,true))
print('ZC_PRIORITY_VERIFIED',r.passed,#r.masses,r.error or '')
