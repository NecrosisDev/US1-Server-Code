if not SERVER then return end
local files={"client.lua","cl_zchat.lua","sh_chat.lua","sv_chatter.lua","sv_zc_chat_reaction.lua","cl_ulx_lib.lua"}
for _,name in ipairs(files) do
    local source=assert(file.Read("zc_chat_beta_stage/"..name..".txt","DATA"),name)
    local fn=CompileString(source,"ZCChatBetaPreflight/"..name,false)
    assert(isfunction(fn),tostring(fn))
    local compressed=util.Compress(source)
    if name=="client.lua" then assert(#compressed<64000,"media delivery size limit") end
    print("ZC_CHAT_BETA_PREFLIGHT",name,util.SHA256(source),#compressed)
end
print("ZC_CHAT_BETA_PREFLIGHT_PASS")
