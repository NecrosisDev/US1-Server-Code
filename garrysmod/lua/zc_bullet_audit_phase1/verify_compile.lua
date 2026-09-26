if not SERVER then return end
local paths={
 "zc_bullet_audit_phase1/sh_bullet.lua",
 "zc_bullet_audit_phase1/sh_luabullets.lua"
}
file.CreateDir("zc_bullet_audit_phase1")
local out={}
for _,path in ipairs(paths)do
 local src=file.Read(path,"LUA")
 local c=src and CompileString(src,"@"..path,false) or "missing"
 local ok=isfunction(c)
 out[#out+1]={path=path,ok=ok,err=ok and nil or tostring(c)}
end
file.Write("zc_bullet_audit_phase1/compile.json",util.TableToJSON(out,true))
print("ZC_BULLET_COMPILE",out[1].ok,out[2].ok)
