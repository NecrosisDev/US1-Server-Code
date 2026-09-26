local rows={}
for _,p in ipairs(player.GetHumans()) do
 local r=ZCKillcamViewerDeliveryStatus and ZCKillcamViewerDeliveryStatus[p]
 rows[#rows+1]={userid=p:UserID(),ok=r and r.ok or false,detail=r and r.detail or "no acknowledgment",at=r and r.at,connected=p:TimeConnected(),alive=p:Alive(),health=p:Health(),team=p:Team(),observer=p:GetObserverMode(),timingOut=p:IsTimingOut(),authenticated=p:IsFullyAuthenticated()}
end
file.Write("zc_release_delivery_ack.json",util.TableToJSON({at=os.time(),clients=rows},true))
