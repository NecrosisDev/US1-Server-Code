-- Read-only export of the mounted native gore code and callback origins.
local r={time=os.time(),functions={},hooks={},workshop={}}
file.CreateDir('zc_crawler_native')
local source=file.Read('autorun/z_podgruz.lua','LUA')
r.mountedGore=source~=nil
if source then file.Write('zc_crawler_native/mounted_gore.lua.txt',source);r.goreSHA256=util.SHA256(source) end
for _,name in ipairs({'Gib_RemoveBone','Gib_Input','SpawnMeatGore'}) do
 local f=_G[name];if isfunction(f) then r.functions[name]=debug.getinfo(f,'S') end
end
for name,f in pairs(hg or {}) do
 if isfunction(f) and (name:lower():find('gore') or name:lower():find('torso') or name:lower():find('gib')) then r.functions['hg.'..name]=debug.getinfo(f,'S') end
end
for event,entries in pairs(hook.GetTable()) do
 for name,f in pairs(entries) do
  if isfunction(f) and (tostring(name):lower():find('gore') or tostring(name):lower():find('torso')) then
   r.hooks[event..'/'..tostring(name)]=debug.getinfo(f,'S')
  end
 end
end
for _,a in ipairs(engine.GetAddons()) do
 if tostring(a.title):lower():find('gore') then r.workshop[#r.workshop+1]={title=a.title,wsid=a.wsid,mounted=a.mounted,updated=a.updated} end
end
file.Write('zc_crawler_native/inspect_20260919t004322z.json',util.TableToJSON(r,true))
print('ZC_CRAWLER_NATIVE_INSPECTED',r.mountedGore)
