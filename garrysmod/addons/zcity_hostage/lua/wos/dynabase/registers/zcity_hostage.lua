-- Loaded and sent to clients by ZCity's existing DynaBase autoloader.
local model = "models/zcity_hostage/hostage_embedded_male.mdl"
local female = "models/zcity_hostage/hostage_embedded_female.mdl"
local gameplayMale = "models/zcity_hostage/gameplay_male.mdl"
local gameplayFemale = "models/zcity_hostage/gameplay_female.mdl"
if not file.Exists(model, "GAME")
    or not file.Exists(female, "GAME")
    or not file.Exists(gameplayMale, "GAME") or not file.Exists(gameplayFemale, "GAME") then
    ErrorNoHalt("[ZCity Hostage] Missing compiled animation content; registration skipped.\n")
    return
end

wOS.DynaBase:RegisterSource({
    Name = "ZCity | Hostage Set",
    Type = WOS_DYNABASE.EXTENSION,
    Shared = model,
    Male = model,
    Female = female
})

hook.Add("PreLoadAnimations", "ZCityHostage.Mount", function(gender)
    if gender == WOS_DYNABASE.FEMALE then
        IncludeModel(female)
        IncludeModel(gameplayFemale)
    elseif gender == WOS_DYNABASE.SHARED or gender == WOS_DYNABASE.MALE then
        IncludeModel(model)
        IncludeModel(gameplayMale)
    end
end)
