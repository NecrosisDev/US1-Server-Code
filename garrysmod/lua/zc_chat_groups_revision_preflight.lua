local result={ok=true,files={}}
for _,name in ipairs({"client.lua","cl_zchat.lua","sh_chat.lua","cl_chat.lua","ulx_chat.lua","threads.lua","sv_zc_chat_pm.lua","sv_zc_chat_reaction.lua","sv_zc_chat_moderation.lua","groups.lua","sv_zc_chat_groups.lua","cl_apply.lua","sv_preview.lua"})do
 local source=assert(file.Read("zc_chat_groups_20260923_1a/"..name..".txt","DATA"));local fn=CompileString(source,"GroupRevision/"..name,false)
 result.files[name]=isfunction(fn) and "compiled" or tostring(fn);result.ok=result.ok and isfunction(fn)
end
file.Write("zc_chat_groups_revision_preflight.json",util.TableToJSON(result,true))
