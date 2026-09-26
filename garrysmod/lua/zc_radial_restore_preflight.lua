local p=util.JSONToTable(file.Read("zci_panel_stage/radial-restore.txt","DATA"))
local f=CompileString(p.source,"RadialRestorePreflight",false)
file.Write("zci_panel_stage/radial-compile.json",util.TableToJSON({ok=isfunction(f),error=isstring(f) and f or nil,hash=p.hash}))
