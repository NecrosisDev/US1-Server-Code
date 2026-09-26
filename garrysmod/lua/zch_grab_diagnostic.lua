local result={time=os.time(),classes={},players=#player.GetHumans()}
local function state(p)
 if not IsValid(p) or not p:IsPlayer() then return {player=false} end
 return {player=true,class=p.PlayerClassName or "<nil>",alive=p:Alive(),organism=p.organism~=nil,
 unconscious=p.organism and p.organism.otrub,ground=p:OnGround(),crouch=p:Crouching(),move=p:GetMoveType(),
 vehicle=p:InVehicle(),water=p:WaterLevel(),scale=p:GetModelScale(),fake=IsValid(p.FakeRagdoll) or IsValid(p:GetNWEntity("FakeRagdoll")),
 crusher=p.SuperCrusher,suicide=p.suiciding,role=p:GetNWString("zch_role"),model=p:GetModel()}
end
for _,p in ipairs(player.GetHumans()) do
 local c=p.PlayerClassName or "<nil>" result.classes[c]=(result.classes[c] or 0)+1
 if p:SteamID64()=="76561198011536179" then
  result.tester=state(p)
  local tr=util.TraceLine({start=p:EyePos(),endpos=p:EyePos()+p:GetAimVector()*80,filter=p,mask=MASK_SHOT})
  result.target=state(tr.Entity)
 end
end
file.Write("zch_grab_diagnostic.json",util.TableToJSON(result,true))
