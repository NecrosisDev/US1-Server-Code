if not SERVER then return end
local source=file.Read("zc_context_posture_candidate.lua","LUA")
local compiled=CompileString(source,"ContextPosturePreflight",false)
file.Write("zci_context_posture_preflight.json",util.TableToJSON({ok=isfunction(compiled),hash=util.SHA256(source),error=isfunction(compiled) and "" or tostring(compiled),time=os.time()}))
