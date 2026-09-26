local rows={}
local M,F=ZCityMetaSafety,ZCityFFBrain
for _,p in ipairs(player.GetHumans())do
 local a=M and M.accounts and M.accounts[M.ID(p)];local org=p.organism or {};local ff=F and F.states and F.states[p]
 rows[#rows+1]={userid=p:UserID(),public=p:GetNetVar("Karma"),server=p.Karma,pending=a and a.balance,accountPublic=a and a.public,accountState=a and a.status,
  brain=org.brain,shaking=org.start_shaking~=nil,alive=p:Alive(),carry=a and a.ready,queued=a and a.brain,ffAdded=ff and ff.added,
  lowRate=F and F.KarmaRate and F.KarmaRate(p:GetNetVar("Karma"))}
end
local function src(f)if not isfunction(f)then return end;local i=debug.getinfo(f,"S");return {source=i.short_src,line=i.linedefined}end
local h=hook.GetTable()
file.Write("zc_scoreboard_penalty_audit.json",util.TableToJSON({rows=rows,locked=M and M.Locked(),brainVersion=F and F.Version,
 seizure=src((h["Org Think"]or{}).Its_Karma_Bro),karmaStep=src(F and F.KarmaStep),ffApply=src(F and F.Apply),meta=src(M and M.Public)},true))
