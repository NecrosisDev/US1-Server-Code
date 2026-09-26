util.AddNetworkString("ZCScoreboardSyncAudit")
local state={clients={},sent={}};ZCScoreboardSyncAudit=state
net.Receive("ZCScoreboardSyncAudit",function(bits,p)
 if bits>48000 or not state.sent[p]then return end
 state.sent[p]=nil
 local received=util.JSONToTable(net.ReadString());if not istable(received)or not istable(received.rows)or #received.rows>128 then return end
 local differences={};local count=0
 for _,row in ipairs(received.rows)do
  if istable(row)and isnumber(row.id)then
   local target=Player(row.id)
   if IsValid(target)then
    local expected=target:GetNetVar("Karma")
    if isnumber(expected)and isnumber(row.public)and math.abs(expected-row.public)>.01 then differences[#differences+1]={id=row.id,expected=expected,received=row.public}end
    count=count+1
   end
  end
 end
 state.clients[tostring(p:UserID())]={version=tostring(received.version),count=count,differences=differences}
 file.Write("zc_scoreboard_sync_audit.json",util.TableToJSON(state.clients,true))
end)
local client=[=[local rows={}
for _,p in ipairs(player.GetAll())do rows[#rows+1]={id=p:UserID(),public=p:GetNetVar("Karma")}end
net.Start("ZCScoreboardSyncAudit");net.WriteString(util.TableToJSON({rows=rows,version=PATSB and PATSB.KarmaDisplayVersion}));net.SendToServer()
]=]
for i,p in ipairs(player.GetHumans())do timer.Simple(i*.1,function()if IsValid(p)then state.sent[p]=true;p:SendLua(client)end end)end
local samples={}
timer.Create("ZCScoreboard.PenaltyAudit",1,30,function()
 local M,F=ZCityMetaSafety,ZCityFFBrain;local rows={}
 for _,p in ipairs(player.GetHumans())do
  local org=p.organism or {};local a=M and M.accounts[M.ID(p)]
  if (org.brain or 0)>0 or org.start_shaking or p.Karma~=p:GetNetVar("Karma")then
   rows[#rows+1]={id=p:UserID(),rank=p:GetUserGroup(),actual=p.Karma,public=p:GetNetVar("Karma"),brain=org.brain,seizure=org.start_shaking~=nil,alive=p:Alive(),
    pending=a and a.balance,queued=a and a.brain,carry=a and a.ready,accountState=a and a.status,loading=ZCityGuiltJustice and ZCityGuiltJustice.loading[p]~=nil}
  end
 end
 samples[#samples+1]={time=CurTime(),mode=zb.CROUND,round=zb.ROUND_STATE,locked=M.Locked(),metaError=M.loadError,rows=rows}
 file.Write("zc_scoreboard_penalty_samples.json",util.TableToJSON(samples,true))
end)
