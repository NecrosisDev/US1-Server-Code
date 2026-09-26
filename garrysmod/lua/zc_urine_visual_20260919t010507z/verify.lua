local r={time=os.time(),passed=false,renderedTest=false,map=game.GetMap(),clients=0,clientsUpdated=0}
local ok,err=xpcall(function()
 local pre=util.JSONToTable(assert(file.Read('zc_urine_visual/preflight_20260919t010507z.json','DATA')))
 local u=assert(ZCityUrine);assert(u.Version=='20260919.visual1' and u.ClientVersion==4,'wrong active version')
 for path,hash in pairs(pre.sources)do
  assert(util.SHA256(assert(file.Read(path,'LUA')))==hash,'hash mismatch '..path)
 end
 local client=assert(file.Read('autorun/client/zc_urine_visuals.lua','LUA'))
 assert(not client:find('ParticleEffectAttach',1,true) and not client:find('ClientsideModel',1,true),'travelling emitters remain')
 assert(client:find('render.ComputeLighting',1,true),'lighting attenuation missing')
 r.commands={}
 for _,name in ipairs({'pee','+pee','-pee'})do
  local f=concommand.GetTable()[name];assert(type(f)=='function','missing command '..name)
  r.commands[name]=debug.getinfo(f,'S').short_src
  assert(r.commands[name]=='lua/autorun/server/zc_urine.lua','command not loaded from canonical live path')
 end
 for _,p in ipairs(player.GetAll())do
  if not p:IsBot()then r.clients=r.clients+1;if u.ready[p]==4 then r.clientsUpdated=r.clientsUpdated+1 end end
 end
 assert(timer.Exists('ZCityUrine_Tick') and timer.Exists('ZCityUrine_Bladder'),'missing timers')
 r.version=u.Version;r.stats=table.Copy(u.stats);r.activeSessions=table.Count(u.active)
 r.splashInterval=u.SplashInterval;r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_urine_visual')
file.Write('zc_urine_visual/verify_20260919t010507z.json',util.TableToJSON(r,true))
print('ZC_URINE_VISUAL_VERIFY',r.passed,r.clientsUpdated,r.clients,r.error or '')
