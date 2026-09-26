local names={"client.lua","cl_zchat.lua","sh_chat.lua","cl_chat.lua","ulx_chat.lua","threads.lua","sv_zc_chat_pm.lua","cl_apply.lua"}
local result={ok=true,files={},utf8=isfunction(utf8.len),ulx=ULib and ULib.cmds and ULib.cmds.translatedCmds["ulx psay"]~=nil,moderation=ZCChatModeration~=nil,reactions=isfunction(ZCChatReaction_Register)}
for _,name in ipairs(names) do
 local source=file.Read("zc_chat_pm_stage/"..name..".txt","DATA")
 local fn=source and CompileString(source,"PMPreflight/"..name,false)
 result.files[name]=isfunction(fn) and "compiled" or tostring(fn);result.ok=result.ok and isfunction(fn)
end
result.ok=result.ok and result.utf8 and result.ulx and result.moderation and result.reactions
file.Write("zc_chat_pm_preflight.json",util.TableToJSON(result,true))
print("ZC_PM_PREFLIGHT",result.ok)
