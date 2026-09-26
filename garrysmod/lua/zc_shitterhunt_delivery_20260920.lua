assert(SERVER)
assert(not ZCShitterhuntRollout,'rollout already exists')
local root='zc_shitterhunt_20260920/'
local payload=assert(file.Read(root..'client_payload.txt','DATA'))
local expected=util.SHA256(payload)
local R={clients={},targets={},hash=expected}
ZCShitterhuntRollout=R
local an='zc_shitterhunt_rollout_ack'
assert(not net.Receivers[an],'ack receiver collision')
util.AddNetworkString(an)
function R.Save()
    local count,ready=0,0
    for _,p in ipairs(player.GetHumans())do
        count=count+1;local row=R.clients[p:SteamID64()]
        if R.targets[p:SteamID64()]==p and row and row.pass then ready=ready+1 end
    end
    file.Write(root..'delivery.json',util.TableToJSON({time=os.time(),total=count,ready=ready,clients=R.clients},false))
end
net.Receive(an,function(bits,p)
    if not IsValid(p)or bits>24000 then return end
    local id=p:SteamID64();local row=R.clients[id]
    if not row or R.targets[id]~=p or row.pass or net.ReadString()~=row.nonce then return end
    local raw=net.ReadString();if #raw>2500 then return end
    local reply=util.JSONToTable(raw)
    row.reply=reply;row.pass=reply and reply.active==true and reply.version=='20260920.1' or false
    row.finished=os.time();R.Save()
end)
function R.Deliver(p)
    if not IsValid(p)or p:IsBot()then return end
    local id=p:SteamID64()
    if R.targets[id]==p and R.clients[id]and R.clients[id].pass then return end
    local nonce=tostring(os.time())..':'..tostring(SysTime())..':'..p:EntIndex()
    R.targets[id]=p;R.clients[id]={nonce=nonce,pass=false,time=os.time()}
    local body=payload..'\n'
    local encoded=util.Base64Encode(util.Compress(body))
    local bootstrap="local ok,r=xpcall(function() local existing=zb and zb.modes and zb.modes.shitterhunt if existing and existing.Version=='20260920.1' then return {active=true,version=existing.Version} end local s=assert(util.Decompress(util.Base64Decode("..string.format('%q',encoded).."),50000)) assert(util.SHA256(s)=="..string.format('%q',util.SHA256(body))..") local f=CompileString(s,'shitterhunt_client_registration',false) assert(isfunction(f),tostring(f)) return f() end,debug.traceback) if not ok then ErrorNoHalt(tostring(r)..'\\n') r={active=false,error=string.sub(tostring(r),1,2000)} end net.Start('"..an.."') net.WriteString("..string.format('%q',nonce)..") net.WriteString(util.TableToJSON(r,false)or '{}') net.SendToServer()"
    assert(#bootstrap<6000,'client bootstrap size')
    p:SendLua(bootstrap);R.Save()
end
hook.Add('PlayerInitialSpawn','ZCShitterhunt_CurrentMapDelivery',function(p)
    timer.Simple(10,function()if IsValid(p)and ZCShitterhuntRollout==R then R.Deliver(p)end end)
end)
for index,p in ipairs(player.GetHumans())do
    timer.Simple((index-1)*0.1,function()if IsValid(p)then R.Deliver(p)end end)
end
R.Save()
