if not CLIENT then return end
local chunks={}
chunks[#chunks+1]=assert(CompileFile("zc_scoreboard/cl_self_status.lua"))
chunks[#chunks+1]=assert(CompileFile("zc_scoreboard/cl_services.lua"))
chunks[#chunks+1]=assert(CompileFile("zc_scoreboard/cl_model.lua"))
chunks[#chunks+1]=assert(CompileFile("zc_scoreboard/cl_skin.lua"))
chunks[#chunks+1]=assert(CompileFile("zc_scoreboard/cl_view.lua"))
chunks[#chunks+1]=assert(CompileFile("zc_scoreboard/cl_controller.lua"))
local allowed={
 ["addons/scoreboard/lua/autorun/client/cl_pat_scoreboard.lua"]=true,
 ["autorun/client/cl_pat_scoreboard.lua"]=true,["zc_scoreboard_voice_trial_20260920"]=true,["ZCScoreboardRepair"]=true}
for event,name in pairs({ScoreboardShow="PATSB_Show",ScoreboardHide="PATSB_Hide"})do
 local fn=(hook.GetTable()[event]or{})[name]
 if isfunction(fn)then assert(allowed[debug.getinfo(fn,"S").short_src],"Scoreboard owner changed: "..event)end
end
if ZCScoreboard and ZCScoreboard.Close then ZCScoreboard.Close()end
if ZCScoreboard and ZCScoreboard.Services then ZCScoreboard.Services.CloseAuxiliary()end
ZCScoreboard=ZCScoreboard or {};ZCScoreboard.State=ZCScoreboard.State or {}
for _,fn in ipairs(chunks)do fn()end
ZCScoreboard.Version="20260923.roster3"
