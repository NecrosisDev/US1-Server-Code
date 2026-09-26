assert(SERVER)
local files={
    {"includes/modules/pk_pills.lua","pk_pills"},
    {"entities/kamikaze.lua","kamikaze"},
    {"entities/gmod_wire_cameracontroller.lua","wire_camera"},
    {"autorun/zcity_drones_compat.lua","drone_compat"}
}
for _,entry in ipairs(files) do
    local raw=file.Read(entry[1],"LUA")
    if raw then file.Write("zc_incident_20260919/source_"..entry[2]..".txt",raw) end
end
print("ZC_REPLICATION_SOURCES_COPIED")
