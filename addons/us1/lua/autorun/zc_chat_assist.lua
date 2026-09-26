if SERVER then
    AddCSLuaFile('zc_chat_assist/model.lua')
    AddCSLuaFile('zc_chat_assist/client.lua')
    include('zc_chat_assist/server.lua')
else
    include('zc_chat_assist/client.lua')
end
