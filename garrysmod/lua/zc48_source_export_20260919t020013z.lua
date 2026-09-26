-- Fixed, relevant source export only. Does not execute the exported addon code.
file.CreateDir('zc_48x60_audit')
local out={time=os.time(),sources={}}
for name,path in pairs({bloodclotter='weapons/weapon_bloodclotter_sh.lua',patcher='autorun/+piengineers_lua_patcher_rewrite.lua',gore='autorun/z_podgruz.lua'}) do
 local s=file.Read(path,'LUA')
 if s then file.Write('zc_48x60_audit/'..name..'_source.txt',s);out.sources[name]={path=path,sha256=util.SHA256(s),bytes=#s} end
end
local f=debug.getinfo(util.ScreenShake,'S');out.screenShake={source=f.source,line=f.linedefined}
file.Write('zc_48x60_audit/source_export_20260919t020013z.json',util.TableToJSON(out,true))
print('ZC48_SOURCES_EXPORTED')
