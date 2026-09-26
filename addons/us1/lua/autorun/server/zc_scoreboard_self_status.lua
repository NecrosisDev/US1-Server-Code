if not SERVER then return end
ZCScoreboardSelf=ZCScoreboardSelf or {}
local S=ZCScoreboardSelf
S.Version="20260923.self1"
S.sent=S.sent or setmetatable({}, {__mode="k"})
local function finite(n)return isnumber(n)and n==n and math.abs(n)<math.huge end
-- Read-only: no Account/Balance calls, settlement, damage, recovery or saved-score writes.
function S.Read(p)
 local actual=finite(p.Karma)and p.Karma or nil
 local public=p.GetNetVar and p:GetNetVar("Karma")
 if not finite(public)then public=nil end
 local M=ZCityMetaSafety
 local held=M and M.Locked()==true or false
 local penaltyKarma=actual
 local account=held and M.accounts and M.ID and M.accounts[M.ID(p)]
 if account and M.Round and account.round==M.Round()and finite(account.public)then penaltyKarma=account.public end
 local org=p.organism
 local brain=istable(org)and finite(org.brain)and org.brain>0 or false
 local shaking=istable(org)and finite(org.start_shaking)and org.start_shaking>CurTime()and actual~=nil and actual<50 or false
 local cv=GetConVar("zc_karma_brain_enabled")
 local F=ZCityFFBrain
 return {version=S.Version,karma=actual,public=public,penaltyKarma=penaltyKarma,brainInjury=brain,
  seizureActive=shaking,seizureRisk=actual~=nil and actual<50,
  lowKarmaBrainRisk=cv and cv:GetBool()and F and F.KarmaRate and penaltyKarma~=nil and F.KarmaRate(penaltyKarma)>0 or false,
  held=held,at=CurTime()}
end
function S.Publish(p)
 if not IsValid(p)or p:IsBot()or not p.SetLocalVar then return end
 local value=S.Read(p)
 -- Existing local-variable transport stores/sends only to this player. Never SetNetVar.
 p:SetLocalVar("ZCSB_SelfStatus",value)
 S.sent[p]=CurTime()
end
timer.Create("ZCScoreboard.SelfStatus",2,0,function()
 for _,p in ipairs(player.GetHumans())do if S.Public or p:SteamID64()=="76561198011536179"then S.Publish(p)end end
end)

ZCScoreboardSelf.Public=true
