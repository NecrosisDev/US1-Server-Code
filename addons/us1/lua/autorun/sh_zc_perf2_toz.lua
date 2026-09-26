-- TOZ-194 only: absent magazine bones must not abort world-model creation/reload visuals.
if SERVER then AddCSLuaFile("autorun/sh_zc_perf2_toz.lua") end
ZCPerf2TOZ=ZCPerf2TOZ or {}
local T=ZCPerf2TOZ
T.Version="20260916.2"
local full=Vector(1,1,1)
function T.Scale(model,scale)
    if not IsValid(model) then return end
    local bone=model:LookupBone("b_wpn_mag_b1")
    if bone~=nil and bone>=0 then model:ManipulateBoneScale(bone,scale) end
end
function T.ModelCreated(self,model)T.Scale(model,vector_origin)end
function T.Insert(self,model)
    self:EmitSound("weapons/toz_shotgun/toz_shell_insert_"..math.random(1,3)..".wav")
    T.Scale(model,full)
end
function T.EndReload(self,model)T.Scale(model,vector_origin)end
local function supported(fn,ours)
    if fn==ours then return true end
    if not isfunction(fn) then return false end
    local source=debug.getinfo(fn,"S").short_src
    return source:find("weapons/weapon_toz194.lua",1,true)~=nil
        or source:find("sh_zc_perf2_toz.lua",1,true)~=nil
end
function T.Apply(weapon,class)
    if class~="weapon_toz194" or not weapon then return false end
    local events=weapon.AnimsEvents
    local insert=events and events.base_reload_insert
    local finish=events and events.base_reload_end
    if not insert or not finish or not supported(weapon.ModelCreated,T.ModelCreated)
        or not supported(insert[0.1],T.Insert) or not supported(finish[0],T.EndReload) then return false end
    weapon.ModelCreated=T.ModelCreated
    insert[0.1]=T.Insert;finish[0]=T.EndReload
    weapon.ZCTozBoneGuard=T.Version
    return true
end
function T.RepairModel(weapon)
    if not CLIENT then return false end
    local model=weapon.worldModel
    if not IsValid(model) or not model.GetOwner or IsValid(model:GetOwner()) then return false end
    -- Native creation assigns an owner AFTER ModelCreated; a failure before then
    -- leaves a partial client model that would otherwise never be initialized.
    weapon.worldModel=nil;model:Remove()
    T.repaired=(T.repaired or 0)+1
    return true
end
function T.Install()
    local n=0
    if T.Apply(weapons.GetStored("weapon_toz194"),"weapon_toz194") then n=n+1 end
    for _,e in ipairs(ents.FindByClass("weapon_toz194")) do
        if IsValid(e) and T.Apply(e,"weapon_toz194") then n=n+1;T.RepairModel(e)end
    end
    return n
end
hook.Add("PreRegisterSWEP","ZCPerf2TOZ",function(weapon,class)T.Apply(weapon,class)end)
-- Install returns a count. Startup hooks must NOT return that count:
-- even zero stops the remaining hooks in both GMod and ULib.
function T.OnStartup()
    T.Install()
end
hook.Add("PostGamemodeLoaded","ZCPerf2TOZ",T.OnStartup)
hook.Add("InitPostEntity","ZCPerf2TOZ",T.OnStartup)
hook.Add("OnReloadedWep","ZCPerf2TOZ",function(e)
    if IsValid(e) then T.Apply(e,e:GetClass())end
end)
T.Install()
