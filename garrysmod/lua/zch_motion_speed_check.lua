local src=file.Read("zch_motion_speed.txt","DATA")
local fn=CompileString(src,"ZCHMotionSpeed",false)
file.Write("zch_motion_speed_compile.json",util.TableToJSON({time=os.time(),compiled=isfunction(fn),crc=util.CRC(src),error=isstring(fn) and fn or nil},true))
