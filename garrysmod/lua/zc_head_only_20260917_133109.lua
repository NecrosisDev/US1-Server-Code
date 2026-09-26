-- Manual, server-only head optimization. Source files and startup remain untouched.
assert(SERVER and engine.ActiveGamemode()=='zcity')
assert(not ZCHeadOnlyRepair,'Reconcile an existing head transaction first')
local sourcePath='weapons/homigrad_base/sh_bullet.lua'
local beforeHash='1270a1ef4be0b8e502b1f73fcec5c6aabc99215bfe04efe4d0fa7b2dff19058c'
local afterHash='4bbd5ace440cc5057407db48bd9a2263e18c21783fed00fbfa99e0cd3027d623'
local dataRoot='zc_head_only_20260917_133109/'
local before=assert(file.Read(sourcePath,'LUA'))
local after=assert(file.Read(dataRoot..'candidate.txt','DATA'))
assert(util.SHA256(before)==beforeHash and util.SHA256(after)==afterHash,'Source drift')
local old=assert(weapons.GetStored('homigrad_base').FireBullet)
local initial={hook.Call,hook.Add,include,net.Start,net.Send,net.Broadcast,FindMetaTable('Entity').FireLuaBullets}
local startup={}
for _,name in ipairs({'Initialize','PostGamemodeLoaded','InitPostEntity'})do
    startup[name]={};for k,v in pairs(hook.GetTable()[name] or {})do startup[name][k]=v end
end
local function invariant()
    local now={hook.Call,hook.Add,include,net.Start,net.Send,net.Broadcast,FindMetaTable('Entity').FireLuaBullets}
    for i,v in ipairs(initial)do if now[i]~=v then return false end end
    for name,saved in pairs(startup)do
        local current=hook.GetTable()[name] or {}
        for k,v in pairs(saved)do if current[k]~=v then return false end end
        for k,v in pairs(current)do if saved[k]~=v then return false end end
    end
    return util.SHA256(assert(file.Read(sourcePath,'LUA')))==beforeHash
end
local roots={weapons.GetStored('homigrad_base')}
for _,t in ipairs(weapons.GetList())do
    roots[#roots+1]=t;local b=baseclass.Get(t.ClassName);if istable(b)then roots[#roots+1]=b end
end
local function instances()
    local list={};for _,e in ipairs(ents.GetAll())do if IsValid(e) and e:IsWeapon()then list[#list+1]=e end end
    return list
end
local module=assert(file.Read(dataRoot..'transaction.txt','DATA'))
assert(util.SHA256(module)=='87b40dd28d3e8c8de847c875af6c7c37ebf18eb06544fd3caba0f942f55daf04','Transaction file mismatch')
local load=CompileString(module,'@head_transaction',false);assert(isfunction(load),tostring(load))
local R=load()(before,after,old,roots,instances,invariant)
function R.Report()
    local count={original=0,replacement=0,other=0}
    for _,e in ipairs(instances())do
        local key=e.FireBullet==R.replacement and 'replacement' or e.FireBullet==old and 'original' or 'other'
        count[key]=count[key]+1
    end
    local out={at=os.time(),map=game.GetMap(),players=#player.GetHumans(),state=R.state,
        verified=R.Verify(),targets=R.targetCount,liveWeapons=count,sourceUnchanged=invariant(),
        persistence='Runtime-only; clean map load/restart restores original disk code.'}
    file.Write(dataRoot..'runtime_status.json',util.TableToJSON(out,true))
    print('HEAD_ONLY_STATUS',R.state,out.verified,count.replacement,count.original)
    return out
end
ZCHeadOnlyRepair=R
R.Report()
