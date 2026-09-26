local r={time=os.time(),activated=false,masses={},livePlayerTest=false}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_repair_batches/preflight_priority_20260919t025322z.json','DATA')))
 assert(pre.passed and #pre.tests==53,'preflight missing')
 for _,path in ipairs({'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_urine.lua'}) do
  assert(util.SHA256(assert(file.Read(path,'LUA')))==pre.hashes[path],'installed source differs '..path)
 end
 local c,i,u=ZCityPoop,ZCityPoopInvoluntary,ZCityUrine
 local accounts,owned,states,bladder,active=c.accounts,c.owned,i.states,u.bladder,u.active
 include('autorun/server/zc_poop.lua')
 include('autorun/server/zc_poop_involuntary.lua')
 include('autorun/server/zc_urine.lua')
 assert(c==ZCityPoop and i==ZCityPoopInvoluntary and u==ZCityUrine,'module table replaced')
 assert(accounts==c.accounts and owned==c.owned and states==i.states and bladder==u.bladder and active==u.active,'persistent state replaced')
 assert(c.Version=='20260919.mass1' and i.Version=='20260919.mass1' and u.Version=='20260919.drips1')
 assert(c.Mass>1 and math.abs(c.Mass-3.9003355503082275)<0.00001)
 for ent in pairs(c.owned) do if IsValid(ent) then
  local ph=ent:GetPhysicsObject()
  if IsValid(ph) then
   local before=ph:GetMass();ph:SetMass(c.Mass)
   r.masses[#r.masses+1]={index=ent:EntIndex(),creation=ent:GetCreationID(),before=before,after=ph:GetMass()}
   assert(math.abs(ph:GetMass()-c.Mass)<0.0001,'mass rejected')
  end
 end end
 r.preservedState=true;r.activated=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_repair_batches');file.Write('zc_repair_batches/activation_priority_20260919t025322z.json',util.TableToJSON(r,true))
print('ZC_PRIORITY_ACTIVATION',r.activated,#r.masses,r.error or '')
