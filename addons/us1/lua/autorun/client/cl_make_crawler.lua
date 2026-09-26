if not CLIENT then return end

-- Remove the v1 custom GoreCalc renderer if this is a hot reload.
local old=ZCMakeCrawlerClient
if old and old.wrapper and old.original and hg and hg.GoreCalc==old.wrapper then
    hg.GoreCalc=old.original
end
timer.Remove("ZCMakeCrawler_WrapGore")
if old and IsValid(old.stump)then old.stump:Remove()end

local M={Version="20260920.recovery3-admin1"}
ZCMakeCrawlerClient=M

local function IsTarget(ent)
    if not IsValid(ent)then return false end
    return ent:IsPlayer() or ent:GetClass()=="prop_ragdoll"
end
properties.Add("zc_makecrawler",{
    MenuLabel="Make Crawler",
    Order=3100.5,
    MenuIcon="icon16/user_go.png",

    Filter=function(self,ent,ply)
        return IsValid(ply) and (ply:IsAdmin() or ply:IsSuperAdmin())
            and IsTarget(ent) and ent~=ply
    end,

    Action=function(self,ent)
        net.Start("ZCMakeCrawler_Apply")
        net.WriteEntity(ent)
        net.SendToServer()
    end,
})

properties.Add("zc_returnlegs",{
    MenuLabel="Return legs",
    Order=5.1, -- Native Reset organism is 5; Freeze is 6.
    MenuIcon="icon16/user_add.png",
    Filter=function(self,ent,ply)
        if not IsValid(ply) or not ply:IsAdmin() or not IsValid(ent) then return false end
        local owner=ent:IsPlayer() and ent or ent:GetNWEntity("ply")
        if not IsValid(owner) and hg and hg.RagdollOwner then owner=hg.RagdollOwner(ent) end
        if not IsValid(owner) or not owner:IsPlayer() or not owner:Alive() then return false end
        local body=owner:GetNWEntity("FakeRagdoll")
        if ent~=owner and ent~=body then return false end
        local reset=properties.List.reset_org
        if not reset or not reset:Filter(owner,ply) then return false end
        return owner:GetNWBool("ZCityTorsoSevered",false)
            or (IsValid(body) and body:GetNWBool("ZCityTorsoSevered",false))
    end,
    Action=function(self,ent)
        net.Start("ZCMakeCrawler_ReturnLegs")
        net.WriteEntity(ent)
        net.SendToServer()
    end,
})

net.Start("ZCMakeCrawler_Ready")
net.SendToServer()

local function acknowledgeTrial()
    local ply=LocalPlayer()
    if not IsValid(ply) or not ply:IsAdmin() then return end
    net.Start("ZCMakeCrawler_TrialReady")
    net.WriteString(M.Version)
    net.SendToServer()
end
hook.Add("InitPostEntity","ZCMakeCrawler_TrialReady",function() acknowledgeTrial() end)
timer.Simple(0,acknowledgeTrial)
