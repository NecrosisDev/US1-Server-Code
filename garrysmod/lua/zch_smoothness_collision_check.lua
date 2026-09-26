local src=file.Read("zch_smoothness_collision.txt","DATA")
local fn=CompileString(src,"ZCHSmoothnessCollision",false)
file.Write("zch_smoothness_collision_compile.json",util.TableToJSON({time=os.time(),compiled=isfunction(fn),crc=util.CRC(src),error=isstring(fn) and fn or nil},true))
