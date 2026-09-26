if not SERVER then return end
local files={
    "zc_bullet_audit_phase2/sh_bullet.lua",
    "zc_bullet_audit_phase2/sh_luabullets.lua"
}
local report={version="20260918.1",files={},passed=true}
for _,path in ipairs(files) do
    local src=file.Read(path,"LUA")
    local row={bytes=src and #src or 0}
    if not src then
        row.ok=false;row.error="missing";report.passed=false
    else
        local compiled=CompileString(src,"@"..path,false)
        row.ok=isfunction(compiled)
        if not row.ok then row.error=tostring(compiled);report.passed=false end
    end
    report.files[path]=row
end
file.CreateDir("zc_bullet_audit_phase2")
file.Write("zc_bullet_audit_phase2/compile.json",util.TableToJSON(report,true))
print("ZC_BULLET_PHASE2_COMPILE",report.passed)
