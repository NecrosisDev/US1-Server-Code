assert(SERVER and ZCityGoreIntestines and ZCityGoreIntestines.Version=='20260920.intestines1')
assert(not ZCIntestinesPublicRollout,'rollout already exists; inspect first')
local R={clients={},targets={},cancel={},started=os.time(),payloadHash='910a1b5aa49ab353f566a8f9915ec044c5c2534bf00f1d811b1f8f9d26e95a1a'}
ZCIntestinesPublicRollout=R
function R.Save()
 local pending,ready,total=0,0,0
 for _,p in ipairs(player.GetHumans())do
  total=total+1;local r=R.clients[p:SteamID64()]
  if R.targets[p:SteamID64()]==p and r and r.reason=='client active; visual confirmation pending' then ready=ready+1 else pending=pending+1 end
 end
 file.CreateDir('zc_intestines_public_20260920')
 file.Write('zc_intestines_public_20260920/delivery.json',util.TableToJSON({time=os.time(),started=R.started,total=total,ready=ready,pending=pending,clients=R.clients,payloadHash=R.payloadHash,automatic=GetConVar('zc_intestines_enabled'):GetBool()},false))
end
function R.Deliver(target)
 if not IsValid(target) or target:IsBot() then return end
 local current=R.clients[target:SteamID64()]
 if R.targets[target:SteamID64()]==target and current and(not current.finished or current.reason=='client active; visual confirmation pending')then return end
assert(SERVER)
local root='zc_intestines_public_20260920/'
local id=target:SteamID64()
assert(IsValid(target),'consenting client disconnected')
local dn,an='zc_intestines_public_data_'..target:EntIndex(),'zc_intestines_public_ack_'..target:EntIndex()
assert(not net.Receivers[an]and not timer.Exists(an),'trial transport collision')
local body=assert(file.Read(root..'payload.txt','DATA'))
assert(util.SHA256(body)=='910a1b5aa49ab353f566a8f9915ec044c5c2534bf00f1d811b1f8f9d26e95a1a','payload changed')
local packed=assert(util.Compress(body));assert(#packed<60000 and #body<160000,'payload size')
local nonce=tostring(os.time())..':'..tostring(SysTime())
local r={time=os.time(),target=id,publicRollout=true,productionChanged=true,entityIndex=target:EntIndex(),payloadHash=util.SHA256(body)}
local receiver,finished,sent,activated
local function sample()return {groups=ZCityGoreIntestines.count,automatic=GetConVar('zc_intestines_enabled'):GetBool(),errors=ZCityGoreIntestines.stats.errors}end
r.before=sample()
R.clients[id]=r;R.targets[id]=target
local function save()R.Save()end
local function finish(reason)
 if finished then return end;finished=true;R.cancel[target]=nil;timer.Remove(an)
 if net.Receivers[an]==receiver then net.Receivers[an]=nil end
 r.reason=reason;r.finished=os.time();r.after=sample();r.receiverRemoved=net.Receivers[an]==nil;save()
 print('ZCINTESTINES_PUBLIC',reason)
end
util.AddNetworkString(dn);util.AddNetworkString(an)
receiver=function(bits,p)
 if p~=target or bits>40000 or finished then return end
 if net.ReadString()~=nonce then return end
 local phase=net.ReadUInt(2)
 if phase==0 and sent or phase==1 and(not sent or activated)or phase==2 and not activated or phase>2 then return end
 local raw=net.ReadString();if #raw>4096 then return end
 if phase==0 then
  local ready=util.JSONToTable(raw)
  if not ready or ready.ready~=true then r.client=ready;finish('client bootstrap refused');return end
  sent=true;net.Start(dn);net.WriteString(nonce);net.WriteUInt(#packed,16);net.WriteData(packed,#packed);net.Send(target)
 elseif phase==1 then
  r.client=util.JSONToTable(raw);activated=r.client and r.client.active==true and r.client.visualRevision=='20260920.seep2'
  if not activated then finish('client installation failed');return end
  save()
  timer.Simple(15,function()
   if finished then return end
   if not IsValid(target)then finish('client disconnected before verification');return end
   target:SendLua("local s=ZCIntestinesClient local ok,r=pcall(function() return s and s.Report() or {active=false,error='trial missing'} end) if not ok then r={active=false,error=tostring(r)} end net.Start('"..an.."') net.WriteString("..string.format('%q',nonce)..") net.WriteUInt(2,2) net.WriteString(string.sub(util.TableToJSON(r,false)or '{}',1,4096)) net.SendToServer()")
  end)
 elseif phase==2 then
  r.followup=util.JSONToTable(raw)
  finish(r.followup and r.followup.active and r.followup.visualRevision=='20260920.seep2' and 'client active; visual confirmation pending'or 'client followup failed')
 end
end
net.Receive(an,receiver);receiver=net.Receivers[an]
R.cancel[target]=finish
timer.Create(an,60,1,function()finish('transport timeout; client state unverified')end)
local bootstrap=[=[
if not IsValid(LocalPlayer())then return end
local dn,an,nonce='zc_ip_data_placeholder','zc_ip_ack_placeholder',NONCE
local function ack(phase,result)
 net.Start(an);net.WriteString(nonce);net.WriteUInt(phase,2)
 net.WriteString(string.sub(util.TableToJSON(result,false)or '{}',1,4096));net.SendToServer()
end
if net.Receivers[dn]or timer.Exists(dn)then ack(0,{ready=false,error='client transport collision'});return end
local receiver
local function clean()
 if net.Receivers[dn]==receiver then net.Receivers[dn]=nil end
 timer.Remove(dn)
end
receiver=function(bits)
 if bits>490000 or net.ReadString()~=nonce then return end
 local n=net.ReadUInt(16)
 if n==0 or n>60000 or bits<(#nonce+1)*8+16+n*8 then clean();ack(1,{active=false,error='bad payload size'});return end
 local packed=net.ReadData(n);clean()
 local ok,result=xpcall(function()
  local body=assert(util.Decompress(packed,160000),'decompression failed')
  assert(util.SHA256(body)==PAYLOAD_HASH,'payload hash mismatch')
  local fn=CompileString(body,'zc_intestines_public_installer_20260920',false);assert(isfunction(fn),tostring(fn));return fn()
 end,debug.traceback)
 if not ok then ErrorNoHalt(tostring(result)..'\n');result={active=false,error=string.sub(tostring(result),1,2000)}end
 ack(1,result)
end
net.Receive(dn,receiver);receiver=net.Receivers[dn]
timer.Create(dn,55,1,clean)
ack(0,{ready=true})
]=]
bootstrap=string.Replace(bootstrap,'zc_ip_data_placeholder',dn)
bootstrap=string.Replace(bootstrap,'zc_ip_ack_placeholder',an)
bootstrap=string.Replace(bootstrap,'NONCE',string.format('%q',nonce))
bootstrap=string.Replace(bootstrap,'PAYLOAD_HASH',string.format('%q',util.SHA256(body)))
assert(#bootstrap<6000);target:SendLua(bootstrap)

end
function R.Scan()
 for index,p in ipairs(player.GetHumans())do timer.Simple((index-1)*0.25,function()if IsValid(p)then R.Deliver(p)end end)end
 R.Save()
end
hook.Add('PlayerDisconnected','ZCIntestines_PublicDeliveryDisconnect',function(p)if R.cancel[p]then R.cancel[p]('client disconnected')end end)
R.Scan()
