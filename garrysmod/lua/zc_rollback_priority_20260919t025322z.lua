local r={time=os.time(),restored=false}
local ok,err=xpcall(function()
 include('autorun/server/zc_poop.lua')
 include('autorun/server/zc_poop_involuntary.lua')
 include('autorun/server/zc_urine.lua')
 local c=assert(ZCityPoop);c.Mass=nil
 for ent in pairs(c.owned) do if IsValid(ent) then local ph=ent:GetPhysicsObject();if IsValid(ph) and math.abs(ph:GetMass()-3.9003355503082275)<0.0001 then
  ph:SetMass(7.800671100616455)
 end end end
 r.restored=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_repair_batches');file.Write('zc_repair_batches/rollback_priority_20260919t025322z.json',util.TableToJSON(r,true))
print('ZC_PRIORITY_ROLLBACK',r.restored,r.error or '')
