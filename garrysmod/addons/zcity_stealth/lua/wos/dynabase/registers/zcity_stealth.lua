local male="models/zcity_stealth/stealth_anims.mdl"
local female="models/zcity_stealth/stealth_anims_female.mdl"
local gm="models/zcity_stealth/stealth_gameplay_male.mdl"
local gf="models/zcity_stealth/stealth_gameplay_female.mdl"
for _,path in ipairs({male,female,gm,gf}) do
    if not file.Exists(path,"GAME") then ErrorNoHalt("[ZCity Stealth] Missing animation content: "..path.."\n") return end
end
wOS.DynaBase:RegisterSource({Name="ZCity | Stealth Finishers",Type=WOS_DYNABASE.EXTENSION,Shared=male,Male=male,Female=female})
hook.Add("PreLoadAnimations","ZCityStealth.Mount",function(gender)
    if gender==WOS_DYNABASE.FEMALE then IncludeModel(female) IncludeModel(gf)
    elseif gender==WOS_DYNABASE.SHARED or gender==WOS_DYNABASE.MALE then IncludeModel(male) IncludeModel(gm) end
end)
