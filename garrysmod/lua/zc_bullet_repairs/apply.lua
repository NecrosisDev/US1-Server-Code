-- Executed by server.cfg after normal loading; never re-include shared gameplay.
if not SERVER or engine.ActiveGamemode()~='zcity' then return end
local root='zc_bullet_repairs/'
local manifest=assert(util.JSONToTable(assert(file.Read(root..'manifest.json','LUA'))))
local text=assert(file.Read(root..'deployment.txt','LUA'))
assert(util.SHA256(text)==manifest.files['deployment.txt'],'Deployment artifact drift')
local load=CompileString(text,'@zc_bullet_repairs/deployment',false)
assert(isfunction(load),tostring(load))
load()()
