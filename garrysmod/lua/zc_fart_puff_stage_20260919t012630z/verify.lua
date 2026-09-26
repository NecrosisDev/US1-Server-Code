local f=ZCFartPuff
local r={time=os.time(),map=game.GetMap(),version=f and f.Version,stats=f and table.Copy(f.stats),clients=0,loaded=0,missingAssets=0,renderedTest=false}
r.hookLinked=f and hook.GetTable().EntityEmitSound.ZCFartPuff_Sound==f.OnSound or false
r.hash=util.SHA256(file.Read('autorun/zc_fart_puff.lua','LUA') or '')
for _,p in ipairs(player.GetHumans())do
 r.clients=r.clients+1
 if f and f.ready[p]=='loaded' then r.loaded=r.loaded+1 end
 if f and f.ready[p]=='missing_assets_or_api' then r.missingAssets=r.missingAssets+1 end
end
file.CreateDir('zc_fart_puff')
file.Write('zc_fart_puff/verification_20260919t012630z.json',util.TableToJSON(r,true))
print('ZCFART_VERIFICATION',r.version,r.hookLinked,r.loaded,r.clients)
