local u=ZCityUrine
local r={time=os.time(),passed=false,players=#player.GetHumans(),map=game.GetMap()}
local ok,err=xpcall(function()
 assert(u and u.Version=='20260919.drips2')
 assert(u.StreamSound==nil and u.StopSound==nil)
 local src=assert(file.Read('autorun/server/zc_urine.lua','LUA'))
 assert(util.SHA256(src)=='687475204301976705db49f70cf2fae34fb1302819364706fc5ce6d4ff28451a')
 assert(not src:find('ambient/water/',1,true) and not src:find('util.Effect("watersplash"',1,true))
 r.stats=table.Copy(u.stats);r.version=u.Version;r.source=debug.getinfo(u.QueueSplash,'S').source
 r.commands={};for _,n in ipairs({'pee','+pee','-pee'})do r.commands[n]=debug.getinfo(concommand.GetTable()[n],'S').source end
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.Write('zc_audio_repair/verified_20260919t031136z.json',util.TableToJSON(r,true))
print('ZC_AUDIO_VERIFIED',r.passed,r.error or '')
