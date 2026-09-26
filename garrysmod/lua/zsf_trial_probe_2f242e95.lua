local enabled=CreateConVar("zsf_enabled","0",FCVAR_ARCHIVE+FCVAR_REPLICATED,"Enable reviewed stealth gameplay",0,1)
local trial=CreateConVar("zsf_trial_steamid","",FCVAR_ARCHIVE,"Optional SteamID64 allowed to initiate a controlled trial")
enabled:SetBool(false)
trial:SetString("76561198011536179")
local d=wOS and wOS.DynaBase
local result={time=os.time(),enabled=enabled:GetBool(),trial=trial:GetString(),models={},players=player.GetCount(),
    addon_lua=file.Exists("autorun/zcity_stealth.lua","LUA"),
    loaded=ZCityStealth and ZCityStealth.Version or false,
    dynabase=d~=nil,live_reload=d and d.LIVE_RELOAD or false,hostage=ZCityHostage and ZCityHostage.Gameplay.Version,
    downloadurl=GetConVar("sv_downloadurl"):GetString()}
for _,name in ipairs({"stealth_anims","stealth_anims_female","stealth_gameplay_male","stealth_gameplay_female"}) do
    result.models[name]=file.Exists("models/zcity_stealth/"..name..".mdl","GAME")
end
for _,p in ipairs(player.GetHumans()) do
    if p:SteamID64()==trial:GetString() then result.tester={online=true,model=p:GetModel()} end
end
file.Write("zsf_trial_probe.json",util.TableToJSON(result,true))
