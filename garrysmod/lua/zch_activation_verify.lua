local G=ZCityHostage and ZCityHostage.Gameplay
local result={time=os.time(),version=G and G.Version,enabled=GetConVar("zch_gameplay_enabled") and GetConVar("zch_gameplay_enabled"):GetBool(),
    seams=G and G.SeamsReady(),players=#player.GetHumans(),map=game.GetMap(),uptime=CurTime(),sequences={},readyPlayers=0,
    restart=ZC_RESTART_WARNING and ZC_RESTART_WARNING.Status()}
if G then for _,p in ipairs(player.GetHumans()) do if G.Ready[p]==G.ReadyToken(p) then result.readyPlayers=result.readyPlayers+1 end end end
if G then
    for _,model in ipairs({"models/player/group01/male_07.mdl","models/player/group01/female_02.mdl","models/slav/f/female_03.mdl"}) do
        local e=ents.Create("base_anim")
        if IsValid(e) then
            e:SetModel(model)
            local id,duration=e:LookupSequence(G.Clips.holdA)
            result.sequences[model]={id=id,duration=duration,pass=id and id>=0 and duration and duration>0}
            e:Remove()
        end
    end
end
file.Write("zch_activation_boot.json",util.TableToJSON(result,true))
print("ZCH_ACTIVATION_BOOT",util.TableToJSON(result))
util.AddNetworkString("zch_activation_client")
net.Receive("zch_activation_client",function(len,p)
    if not IsValid(p) or p:SteamID64()~="76561198011536179" or len>16000 then return end
    file.Write("zch_activation_client_loaded.json",net.ReadString())
end)
function ZCH_CheckOwnerClient()
    local code=[=[local G=ZCityHostage and ZCityHostage.Gameplay local id,d=LocalPlayer():LookupSequence('zcg_paired_pistol_grabhostagefromfront_loop_att') local src=file.Read('homigrad/cl_tpikzzzmwwork.lua','LUA') or '' local t={time=os.time(),version=G and G.Version,seams=G and G.SeamsReady(),seq=id,duration=d,model=LocalPlayer():GetModel(),tpikGuard=string.find(src,'ZCityHostage.Gameplay.OwnsPose',1,true)~=nil} net.Start('zch_activation_client') net.WriteString(util.TableToJSON(t)) net.SendToServer()]=]
    for _,p in ipairs(player.GetHumans()) do if p:SteamID64()=="76561198011536179" then p:SendLua(code) return true end end
    return false
end
