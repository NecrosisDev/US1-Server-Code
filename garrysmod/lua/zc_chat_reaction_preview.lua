local source=assert(file.Read("zc_chat_reaction_client_fix.lua","LUA"))
assert(isfunction(CompileString(source,"ReactionFixPreflight",false)))
for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then p:SendLua(source) print("ZC_REACTION_FIX_PREVIEW",p:UserID()) end end
