-- Applies only the tested movement-audio module, initially to the requesting owner.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local source=assert(file.Read("zc_death_audio/movement.lua","LUA"))
assert(util.SHA256(source)=="db7ff92a3161dcc5383dbd32019e9ccf37049e58d90437b607ca4e2d4bce5590","Movement source differs from tested release")
assert(isfunction(CompileString(source,"zc_death_audio/movement.lua",false)))
AddCSLuaFile("zc_death_audio/movement.lua")
local owner="76561198011536179";local token=os.time()%4294967295
util.AddNetworkString("zc_pillaudio_apply");util.AddNetworkString("zc_pillaudio_ack")
local r={sourceHash=util.SHA256(source),version="20260916.2",time=os.time(),map=game.GetMap(),targets=0,received=0,passed=0,clients={},phase="owner"}
local expected={}
local function save()file.CreateDir("zc_pill_audio");file.Write("zc_pill_audio/deployed.json",util.TableToJSON(r,true))end
net.Receive("zc_pillaudio_ack",function(bits,p)
 local entry=expected[p]
 if not entry or entry.done or bits>32768 or net.ReadUInt(32)~=token then return end
 local reply=util.JSONToTable(net.ReadString());if not istable(reply)then return end
 entry.done=true;r.received=r.received+1
 if reply.ok==true then r.passed=r.passed+1 end
 r.clients[p:SteamID64()]=reply;save()
end)
local bootstrap=[[
net.Receive("zc_pillaudio_apply",function()
 local token=net.ReadUInt(32);local body=net.ReadData(net.ReadUInt(16))
 if token~=__TOKEN__ or not body or util.SHA256(body)~="db7ff92a3161dcc5383dbd32019e9ccf37049e58d90437b607ca4e2d4bce5590" then return end
 local fn=CompileString(body,"zc_death_audio/movement.lua",false)
 local ok,err=false,"Compilation failed"
 if isfunction(fn)then ok,err=xpcall(fn,debug.traceback)end
 timer.Simple(2,function()
  local A=ZCDeathAudio;local h=hook.GetTable();local silent=true;local state={}
  if A then
   for k,s in pairs(A.channels)do
    local volume=IsValid(s.station) and s.station:GetVolume() or 0
    state[k]=volume;if not A.Subject() and volume>0 then silent=false end
   end
  end
  local result={ok=ok and A~=nil and A.Version=="20260916.2" and not A.installError
    and h.Think.hg_FallSnd==A.Think and h.SetupMove.hg_FallSound==A.Move and silent,
    error=tostring(err or (A and A.installError) or ""),alive=LocalPlayer():Alive(),pill=A and A.PillCarrier(LocalPlayer()),volumes=state,
    silenceWhenInactive=silent,version=A and A.Version}
  net.Start("zc_pillaudio_ack");net.WriteUInt(token,32);net.WriteString(util.TableToJSON(result));net.SendToServer()
 end)
end)
]]
bootstrap=bootstrap:gsub("__TOKEN__",tostring(token));assert(#bootstrap<6000)
local function send(p)
 if not IsValid(p) or p:IsBot() or expected[p] then return end
 expected[p]={};r.targets=r.targets+1;p:SendLua(bootstrap)
 timer.Simple(1,function()
  if not IsValid(p)then return end
  net.Start("zc_pillaudio_apply");net.WriteUInt(token,32)
  net.WriteUInt(#source,16);net.WriteData(source,#source);net.Send(p)
 end)
 save()
end
concommand.Add("zc_pillaudio_rollout",function(p)
 if IsValid(p)then return end
 assert(r.clients[owner] and r.clients[owner].ok,"Owner canary has not passed")
 r.phase="all-current-clients"
 for _,client in ipairs(player.GetHumans())do send(client)end
 save()
end)
for _,p in ipairs(player.GetHumans())do if p:SteamID64()==owner then send(p)end end
save()
