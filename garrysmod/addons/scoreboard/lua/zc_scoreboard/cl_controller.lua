if not CLIENT then return end
local S=ZCScoreboard
if IsValid(S.Frame)then S.Frame:Remove()end
function S.Close()
 if IsValid(S.Frame)then
  if IsValid(S.Frame.List)then S.State.scroll=S.Frame.List:GetVBar():GetScroll()end
  S.Frame:Remove()
 end
end
function S.Open()
 if IsValid(S.Frame)then return end
 S.BuildView()
end
function S.Rebuild()
 if not IsValid(S.Frame)then return end
 S.Close();S.Open()
end
-- Retire exactly the incumbent scoreboard hooks after all successor modules compile.
local hooks=hook.GetTable()
local previous=(hooks.ScoreboardHide or {}).PATSB_Hide
local allowed={
 ["addons/scoreboard/lua/autorun/client/cl_pat_scoreboard.lua"]=true,
 ["autorun/client/cl_pat_scoreboard.lua"]=true,
 ["zc_scoreboard_voice_trial_20260920"]=true,["ZCScoreboardRepair"]=true
}
for event,name in pairs({ScoreboardShow="PATSB_Show",ScoreboardHide="PATSB_Hide"})do
 local callback=(hooks[event]or{})[name]
 if isfunction(callback)then
  assert(allowed[debug.getinfo(callback,"S").short_src],"Scoreboard hook owner changed: "..event)
 end
end
if isfunction(previous)then previous()end
hook.Remove("ScoreboardShow","PATSB_Show");hook.Remove("ScoreboardHide","PATSB_Hide")
hook.Remove("InitPostEntity","PATSB_RequestInitialSettings")
hook.Add("ScoreboardShow","ZCScoreboard.Show",function()S.Open();return true end)
hook.Add("ScoreboardHide","ZCScoreboard.Hide",function()S.Close();return true end)
hook.Add("OnScreenSizeChanged","ZCScoreboard.Resize",function()S.Rebuild()end)
hook.Add("InitPostEntity","ZCScoreboard.Settings",function()net.Start("PATSB_RequestSettings");net.SendToServer()end)
concommand.Add("goobos_scoreboard",function()S.Open()end)
