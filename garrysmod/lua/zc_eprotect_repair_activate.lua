-- One-time delivery/diagnostics; no protection settings or punishments changed.
if not SERVER then return end
local version="20260918.1"
local source=assert(file.Read("autorun/eprotect_loader.lua","LUA"))
assert(util.SHA256(source)=="4ccb9ad34435033cd4fbcaddbeebad518c7d49a73f5597421b64ed2671d3ba76","Unexpected loader source")
assert(eProtect and isfunction(eProtect.punish) and isfunction(eProtect.canNetwork),"Server protection missing")
local before=assert(ZCEProtectRepairBaseline,"Missing live protection snapshot")
assert(eProtect.punish==before.punish and eProtect.canNetwork==before.canNetwork
    and net.Incoming==before.incoming and net.Receivers["ep:handeler"]==before.receiver,
    "Server protection handlers changed")
local receipt="zc_ep_startup_ack"
util.AddNetworkString(receipt)
local nonce=util.SHA256(tostring(SysTime())..tostring(os.time())):sub(1,24)
local expected,received={},{}
local report={version=version,started=os.time(),sent=0,received=0,passed=0,clients={}}
ZCEProtectRepairReport=report
local function save()
    file.CreateDir("zc_eprotect_repair")
    report.updated=os.time()
    file.Write("zc_eprotect_repair/status.json",util.TableToJSON(report,true))
end
net.Receive(receipt,function(bits,p)
    if bits>4096 or not IsValid(p)or received[p]or not expected[p]then return end
    if net.ReadString()~=nonce then return end
    local loaded,restored,hooks,patched=net.ReadBool(),net.ReadBool(),net.ReadBool(),net.ReadBool()
    local message=net.ReadString():sub(1,300)
    received[p]=true
    local passed=loaded and restored and hooks
    report.received=report.received+1;if passed then report.passed=report.passed+1 end
    report.clients[tostring(p:UserID())]={passed=passed,loaded=loaded,restored=restored,hooks=hooks,
        compatibility=patched,error=message}
    save()
end)
local ending=[==[
end,debug.traceback)
if not ok then ErrorNoHalt(tostring(err).."\n")end
timer.Simple(2,function()
    local s=ZCEProtectStartup or {};local h=hook.GetTable()
    local handlers=type((h["eP:MsgCExecuted"]or{})["eP:DetectBadMSGC"])=="function"
        and type((h["eP:PostInitPanel"]or{})["eP:DetectBadVGUI"])=="function"
        and type(net.Receivers["ep:handeler"])=="function"
    net.Start("zc_ep_startup_ack")
    net.WriteString("NONCE")
    net.WriteBool(ok and s.loaded==true);net.WriteBool(s.restored==true)
    net.WriteBool(handlers);net.WriteBool(s.compatibilityUsed==true)
    net.WriteString(tostring(err or s.error or ""):sub(1,300));net.SendToServer()
end)
]==]
local script="local ok,err=xpcall(function()\n"..source..ending:gsub("NONCE",nonce)
assert(#script<6000,"Client script too large")
for _,p in ipairs(player.GetHumans())do
    expected[p]=true;report.sent=report.sent+1
    p:SendLua(script)
end
save()
timer.Simple(15,save)
print("ZC_EPROTECT_REPAIR_DELIVERED",version,report.sent)
