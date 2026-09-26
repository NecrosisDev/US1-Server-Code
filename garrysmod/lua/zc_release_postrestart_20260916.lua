-- One-shot read-only client registration check. Creates no panels and changes no voice settings.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local token=tonumber(util.CRC(tostring(SysTime())..":"..os.time()))
local channel="zc_release_readonly_ack"
util.AddNetworkString(channel)
local report={time=os.time(),map=game.GetMap(),token=token,targets=0,received=0,clients={},
    mysqlModule=mysql and mysql.module,mysqlConnectionPresent=mysql and mysql.connection~=nil or false,
    note="Registration/measurement checks only; no rendered-panel, close, actual voice or persistence test."}
local expected={}
local names={"bootstrap","initpost_errors_clear","ZFrame_registered","font_measurement","voice_hooks","menu_handlers"}
local function save()file.CreateDir("zc_release_guard");file.Write("zc_release_guard/post_restart.json",util.TableToJSON(report,true))end
net.Receive(channel,function(bits,p)
    if bits<97 or bits>104 or not expected[p]then return end
    if net.ReadUInt(32)~=token then return end
    expected[p]=nil;local mask=net.ReadUInt(32);local adminView=net.ReadBool()
    local width,height=net.ReadUInt(16),net.ReadUInt(16)
    local row={adminVoicePreference=adminView,width=width,height=height,checks={}}
    for i,name in ipairs(names)do row.checks[name]=bit.band(mask,bit.lshift(1,i-1))~=0 end
    report.clients[tostring(p:UserID())]=row;report.received=report.received+1;save()
end)
local code=[[
local mask=0
local function check(i,fn)local ok,v=pcall(fn);if ok and v==true then mask=bit.bor(mask,bit.lshift(1,i-1))end end
check(1,function()return ZCUIRecovery~=nil and ZCUIRecovery.Version=="20260916.1"end)
check(2,function()return ZCUIRecovery~=nil and istable(ZCUIRecovery.errors) and next(ZCUIRecovery.errors)==nil end)
check(3,function()return vgui.GetControlTable("ZFrame")~=nil end)
check(4,function()surface.SetFont("ZCity_Tiny");local w,h=surface.GetTextSize("Hg");return w>0 and h>0 end)
check(5,function()local h=hook.GetTable();local s=h.PlayerStartVoice or {};local e=h.PlayerEndVoice or {};return isfunction(s.showVoicePanels) and isfunction(s.RemoveVoicePanles) and hg~=nil and isfunction(hg.ShouldSuppressVoicePanel) and isfunction(e.ZCityUIVoiceState)end)
check(6,function()return GAMEMODE~=nil and isfunction(GAMEMODE.ScoreboardShow) and isfunction(GAMEMODE.ScoreboardHide) and vgui.GetControlTable("SolidMapVote")~=nil and SolidMapVote~=nil and isfunction(SolidMapVote.RerollButtonState)end)
net.Start("zc_release_readonly_ack");net.WriteUInt(__TOKEN__,32);net.WriteUInt(mask,32)
net.WriteBool(GetConVar("zb_admin_show_voicechat") and GetConVar("zb_admin_show_voicechat"):GetBool() or false)
net.WriteUInt(math.Clamp(ScrW(),0,65535),16);net.WriteUInt(math.Clamp(ScrH(),0,65535),16);net.SendToServer()
]]
code=string.Replace(code,"__TOKEN__",tostring(token))
local receiver=net.Receivers[channel]
for _,p in ipairs(player.GetHumans())do
    expected[p]=true;report.targets=report.targets+1;p:SendLua(code)
end
save()
timer.Simple(15,function()
    report.finished=os.time();report.missing=report.targets-report.received;save()
    if net.Receivers[channel]==receiver then net.Receivers[channel]=nil end
end)
