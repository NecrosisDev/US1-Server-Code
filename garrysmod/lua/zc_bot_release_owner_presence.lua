local owner="76561198011536179"
local found=false
for _,p in ipairs(player.GetHumans()) do if p:SteamID64()==owner then found=true break end end
file.Write("zc_bot_release_owner_presence.json",util.TableToJSON({time=os.time(),connected=found,humans=#player.GetHumans()},true))
