if not SERVER then return end
ZCKarmaSeizureGuard={Version="20260923.1"}
local G=ZCKarmaSeizureGuard
function G.Cleanup(p,org)
 if not IsValid(p)or not p:IsPlayer()or not istable(org)or org.start_shaking==nil then return end
 local untilTime=org.start_shaking
 local karma=p.Karma
 local active=isnumber(untilTime)and untilTime==untilTime and untilTime<math.huge and untilTime>CurTime()
 local recovered=isnumber(karma)and karma==karma and karma>=50
 if not active or recovered then org.start_shaking=nil;return true end
end
-- ULib priority -2 runs before the legacy hook. Nil returns preserve every other veto.
hook.Add("Org Think","ZCKarmaSeizureGuard.Expiry",function(p,org)G.Cleanup(p,org)end,-2)
hook.Add("Should Fake Up","ZCKarmaSeizureGuard.Stand",function(p)if IsValid(p)then G.Cleanup(p,p.organism)end end,-2)
