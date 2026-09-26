-- Temporary owner preview persistence. Retire this loader when polish3 is public.
-- Public clients continue through native gamemode loading.
if not SERVER then return end
hook.Add("PlayerInitialSpawn", "ZCChatPolishOwnerRestore", function(ply)
    if ply:IsBot() or ply:SteamID() ~= "STEAM_0:1:25635225" then return end
    timer.Simple(12, function()
        if not IsValid(ply) then return end
        if not file.Exists("zc_chat_polish_stage/cl_zchat.lua.txt", "DATA") then return end
        include("zc_chat_polish_preview.lua")
    end)
end)
