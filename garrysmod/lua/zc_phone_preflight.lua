for _, name in ipairs({"client.lua", "cl_zchat.lua"}) do
    local source = assert(file.Read("zc_chat_phone_stage/" .. name .. ".txt", "DATA"))
    local result = CompileString(source, "PhoneFinalPreflight/" .. name, false)
    assert(isfunction(result), tostring(result))
end
print("ZC_PHONE_FINAL_PREFLIGHT_PASS")
