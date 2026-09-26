if not SERVER then return end
local files={"sh_bullet.lua","sh_luabullets.lua","sv_input.lua","sh_hitboxorgans.lua"}
for _,name in ipairs(files)do
    local path="zc_bullet_phase2/"..name
    local src=file.Read(path,"LUA")
    if not src then
        print("P2_COMPILE",name,false,"missing")
    else
        local fn=CompileString(src,"@"..path,false)
        if isfunction(fn)then
            print("P2_COMPILE",name,true,"ok")
        else
            print("P2_COMPILE",name,false,tostring(fn))
        end
    end
end
