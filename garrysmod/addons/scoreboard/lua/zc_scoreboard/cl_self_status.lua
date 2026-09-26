if not CLIENT then return end
ZCScoreboardSelfView={Version="20260923.self1"}
local S=ZCScoreboardSelfView
function S.Get()
 local p=LocalPlayer();if not IsValid(p)or not p.GetLocalVar then return end
 local value=p:GetLocalVar("ZCSB_SelfStatus")
 if not istable(value)or value.version~=S.Version then return end
 if S.last~=value then S.last=value;S.received=RealTime()end
 if RealTime()-(S.received or 0)>7 then return end
 return value
end
function S.Text()
 local v=S.Get();if not v then return "Your karma: syncing with the server…"end
 local k=isnumber(v.karma)and v.karma==v.karma and math.abs(v.karma)<math.huge and tostring(math.floor(v.karma))or"—"
 local parts={"Your karma: "..k}
 if isnumber(v.penaltyKarma)and v.penaltyKarma~=v.karma then parts[#parts+1]="Brain-penalty basis: "..tostring(math.floor(v.penaltyKarma))end
 if v.seizureActive then parts[#parts+1]="Karma seizure active"
 elseif v.seizureRisk then parts[#parts+1]="Low-karma seizure risk"end
 if v.lowKarmaBrainRisk then parts[#parts+1]="Low-karma brain-injury risk"end
 if v.brainInjury then parts[#parts+1]="Brain injury present; damage or earlier penalties can persist after karma recovers"end
 return table.concat(parts," · ")
end
