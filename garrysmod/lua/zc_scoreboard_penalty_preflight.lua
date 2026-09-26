local sources=util.JSONToTable([==[[{"name": "meta.lua", "path": "zcity_release_tools/staged/scoreboard-penalty-20260923T015057Z/meta.lua", "sha": "d2cda597de88de5ff5961faaf957083bef901de066b81919757db0e63a609078"}, {"name": "sv_seizure_guard.lua", "path": "zcity_release_tools/staged/scoreboard-penalty-20260923T015057Z/sv_seizure_guard.lua", "sha": "bc595d5ad092cd910adea38620a1d5ed0b931937f83563cff0a62f4c4e992baa"}, {"name": "sv_self_status.lua", "path": "zcity_release_tools/staged/scoreboard-penalty-20260923T015057Z/sv_self_status.lua", "sha": "ea06d8651656bdb4175762aa7c08c2671941ab1d0eb848c8fe5af3b304bcc8d5"}]]==])
local result={ok=true}
for _,row in ipairs(sources)do
 local text=assert(file.Read("zc_scoreboard_preflight_"..row.name..".txt","DATA"));assert(util.SHA256(text)==row.sha)
 local fn=CompileString(text,"ScoreboardPenaltyPreflight/"..row.name,false)
 if not isfunction(fn)then result.ok=false;result.error=tostring(fn)break end
end
file.Write("zc_scoreboard_penalty_preflight.json",util.TableToJSON(result,true))
