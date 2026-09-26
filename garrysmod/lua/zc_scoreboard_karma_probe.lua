util.AddNetworkString("ZCScoreboardKarmaProbe")
net.Receive("ZCScoreboardKarmaProbe",function(bits,p)
 if bits>60000 or p:SteamID64()~="76561198011536179"then return end
 local r=util.JSONToTable(net.ReadString());if not istable(r)then return end
 file.Write("zc_scoreboard_karma_client.json",util.TableToJSON(r,true))
end)
local rows={}
for _,p in ipairs(player.GetAll())do rows[#rows+1]={userid=p:UserID(),public=p.GetNetVar and p:GetNetVar("Karma")}end
file.Write("zc_scoreboard_karma_server.json",util.TableToJSON({rows=rows,locked=ZCityMetaSafety and ZCityMetaSafety.Locked(),round=zb and zb.CROUND},true))
local client=[==[local function getKarma(ply)
    if not IsValid(ply) then return 0 end

    local candidates = {"Karma", "karma", "PlayerKarma", "HMCD_Karma", "hg_karma"}
    for _, key in ipairs(candidates) do
        local v = ply:GetNWInt(key, -999999)
        if v ~= -999999 then
            return math.floor(tonumber(v) or 0)
        end
    end

    if ply.Karma then
        return math.floor(tonumber(ply.Karma) or 0)
    end

    return 0
end


local out={rows={},fixed=PATSB and PATSB.KarmaDisplayVersion}
for _,p in ipairs(player.GetAll())do
 local public=p.GetNetVar and p:GetNetVar("Karma")
 out.rows[#out.rows+1]={userid=p:UserID(),legacy=getKarma(p),public=public,display=PATSB and PATSB.GetDisplayedKarma and PATSB.GetDisplayedKarma(p)}
end
net.Start("ZCScoreboardKarmaProbe");net.WriteString(util.TableToJSON(out));net.SendToServer()
]==]
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179"then p:SendLua(client)end end
