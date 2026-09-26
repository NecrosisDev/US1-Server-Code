-- Native public release. Client files load normally on every join/map change;
-- retired preview transports must never overwrite the installed app versions.
if not SERVER then return end
local BUILD="20260923.release1"
local function install()
    if ZCChatNativePublicVersion==BUILD then return true end
    if not (ZCChatPM and ZCChatGroups and ZCChatModeration and ULib and ULib.cmds
        and ULib.cmds.translatedCmds and ULib.cmds.translatedCmds["ulx psay"]) then
        return false
    end
    ZCChatGroups.Preview=nil
    ZCChatPM.Preview=nil
    ZCChatModeration.PreviewOnly=nil
    local alias=ULib.sayCmds and ULib.sayCmds["@"]
    if alias then
        ULib.removeSayCommand("@")
        ULib.addSayCommand("!asay",alias.fn,alias.access,alias.hide,false)
    end
    local command=ULib.cmds.translatedCmds["ulx psay"]
    ZCChatPM.LegacyPsay=ZCChatPM.LegacyPsay or command.fn
    local function psay(caller,target,message)
        if IsValid(caller) and caller:IsPlayer() and not caller:IsBot() then
            return ZCChatPM.Send(caller,target,message,0,0)
        end
        return ZCChatPM.LegacyPsay(caller,target,message)
    end
    command.fn=psay
    ulx.psay=psay
    for _,id in ipairs({"ZCChatIdentityPreviewJoin","ZCChatBetaJoinRefresh",
        "ZCChatSocialJoinRefresh","ZCChatModerationJoinRefresh",
        "ZCChatConversationJoinRefresh","ZCChatPMPreviewJoinRefresh",
        "ZCChatGroupPreviewJoinRefresh","ZCChatGroupsPublicJoin"}) do
        hook.Remove("PlayerInitialSpawn",id)
    end
    ZCChatNativePublicVersion=BUILD
    print("[GoobOS] Native public release ready: "..BUILD)
    return true
end
if not install() then
    timer.Create("ZCChat.NativePublicBootstrap",1,10,function()
        if install() then timer.Remove("ZCChat.NativePublicBootstrap")
        elseif timer.RepsLeft("ZCChat.NativePublicBootstrap")==0 then
            ErrorNoHalt("[GoobOS] Public chat dependencies did not initialize.\n")
        end
    end)
end
