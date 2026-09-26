local id="76561198000000000"
local viewer={SteamID64=function()return id end,Alive=function()return true end,Team=function()return 1 end}
local group={id=0,members={[id]={joined=1}}}
local message={id=0,seq=1,sender=id,name="Fixture",dead=true,reply=900,text="x"}
local short=util.TableToJSON(ZCChatGroups.Packet(viewer,group,message))
message.text=string.rep("🦆",256).."https://example.invalid/hidden.gif"
local long=util.TableToJSON(ZCChatGroups.Packet(viewer,group,message))
local parsed=util.JSONToTable(long)
local result={identical=short==long,shortBytes=#short,longBytes=#long,fixedText=parsed.text==ZCChatGroups.Hidden,messageIDRemoved=parsed.id==0,quoteRemoved=parsed.reply==0,noURL=not long:find("example.invalid",1,true)}
file.Write("zc_chat_groups_censor_check.json",util.TableToJSON(result,true))
