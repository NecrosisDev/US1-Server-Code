local S=ZCityStealth
local H=ZCityHostage and ZCityHostage.Gameplay
local result={time=os.time(),uptime=CurTime(),map=game.GetMap(),players=#player.GetHumans(),
    version=S and S.Version or false,seams=S and S.SeamsReady() or false,
    hostage=H and H.Version or false,hostageSeams=H and H.SeamsReady() or false,
    enabled=GetConVar("zsf_enabled") and GetConVar("zsf_enabled"):GetBool(),
    trial=GetConVar("zsf_trial_steamid") and GetConVar("zsf_trial_steamid"):GetString(),
    restart=ZC_RESTART_WARNING and ZC_RESTART_WARNING.Status(),
    settingsCRC=util.CRC(file.Read("restart_warning/settings.json","DATA") or ""),models={},sequences={}}
for _,name in ipairs({"stealth_anims","stealth_anims_female","stealth_gameplay_male","stealth_gameplay_female"}) do
    result.models[name]=file.Exists("models/zcity_stealth/"..name..".mdl","GAME")
end
if S then
    for _,model in ipairs({"models/player/group01/male_07.mdl","models/player/group01/female_02.mdl","models/slav/f/female_03.mdl"}) do
        local e=ents.Create("base_anim")
        local r={checked=0,missing={}}
        if IsValid(e) then
            e:SetModel(model)
            for name,clip in pairs(S.Assets.clips) do
                local id,duration=e:LookupSequence(clip.sequence)
                r.checked=r.checked+1
                if not id or id<0 or not duration or duration<=0 then r.missing[#r.missing+1]=name end
            end
            e:Remove()
        end
        result.sequences[model]=r
    end
    for _,p in ipairs(player.GetHumans()) do
        if p:SteamID64()=="76561198011536179" then
            result.tester={online=true,ready=S.Ready[p]==S.Token(p),model=p:GetModel(),token=S.Ready[p]}
        end
    end
end
file.Write("zsf_postrestart_2f242e95.json",util.TableToJSON(result,true))
