local rows={}
for _,p in ipairs(player.GetHumans())do if string.find(string.lower(p:Nick()),"bomber7",1,true)then
 local M,F=ZCityMetaSafety,ZCityFFBrain;local a=M and M.accounts[M.ID(p)];local org=p.organism or {};local ff=F and F.states[p]
 rows[#rows+1]={id=p:UserID(),name=p:Nick(),rank=p:GetUserGroup(),actual=p.Karma,public=p:GetNetVar("Karma"),saved=p:guilt_GetValue(),brain=org.brain,shaking=org.start_shaking,alive=p:Alive(),
  account=a,ff=ff and {score=ff.score,added=ff.added},loading=ZCityGuiltJustice and ZCityGuiltJustice.loading[p]~=nil,immune=F.AdminImmune(p)}
end end
file.Write("zc_scoreboard_bomber7.json",util.TableToJSON({rows=rows,locked=ZCityMetaSafety.Locked(),round=zb.ROUND_STATE,mode=zb.CROUND},true))
