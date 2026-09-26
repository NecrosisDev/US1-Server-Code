local r={time=os.time(),restored=false}
local ok,err=xpcall(function()
 for _,path in ipairs({'autorun/server/zc_poop.lua','autorun/server/zc_poop_involuntary.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_urine.lua'})do include(path)end
 hook.Remove('EntityRemoved','ZCityPoop_ForgetRemoved')
 -- Preserve normal client delivery during rollback; never force a client hotload.
 if ZCityUrine then ZCityUrine.SendClient=function()return false end end
 if ZCityPoopThrow then ZCityPoopThrow.SendClient=function()return false end end
 r.restored=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_waste_hardening')
file.Write('zc_waste_hardening/rollback_20260918t233404z.json',util.TableToJSON(r,true))
print('ZCWASTE_ROLLBACK',r.restored)
