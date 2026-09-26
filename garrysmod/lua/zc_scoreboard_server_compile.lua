local data=assert(file.Read("zc_scoreboard_server_compile.txt","DATA"));assert(util.SHA256(data)=="1eff1736baa44e528bf5b951343e05abc455108fa059ed3e0eb2370e2de07a30")
local result={at=os.time(),files={},humans=#player.GetHumans(),meta=ZCityMetaSafety and ZCityMetaSafety.PublicRevision,seizure=ZCKarmaSeizureGuard and ZCKarmaSeizureGuard.Version,self=ZCScoreboardSelf and ZCScoreboardSelf.Version}
for name,source in pairs(util.JSONToTable(data))do local fn=CompileString(source,"ZCScoreboardCompile/"..name,false);result.files[name]=isfunction(fn)or tostring(fn)end
file.Write("zc_scoreboard_server_compile.json",util.TableToJSON(result,true))
