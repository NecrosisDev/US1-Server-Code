-- Manual scoped switchover after verified archive replacement; no loader replay.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local R=assert(ZC36RepairOps)
assert(R.trainPaused and R.TrainReady() and #R.trainQueue==0,"Old effects must drain first")
assert(ulx.traincrash==R.trainBlock and R.trainCommand.fn==R.trainBlock,"Command changed concurrently")
local receipt=assert(util.JSONToTable(assert(file.Read("zc_train_archive_receipt.json","DATA"))))
assert(receipt.after=="af607f3fac0d757fd5fb35ab7c50dec615a96caa024cc42ace52e45e0239fb79")
assert(receipt.source_sha256==util.SHA256(R.trainSource),"Staged source does not match installed archive")
local mounted=util.SHA256(assert(file.Read("ulx/modules/sh/mr_traincrash.lua","LUA")))
assert(mounted=="367eb466f44995f2bf84c45c6ffd6a7bd0244cf121cbd62dcd3cac58f0c61c15" or mounted==receipt.source_sha256,"Unexpected mounted source")
assert(R.Verify(),"Startup/dispatcher changed")
local f=CompileString(R.trainSource,"@lua/ulx/modules/sh/mr_traincrash.lua",false)
assert(isfunction(f),tostring(f))
timer.Remove("ulx_traincrash_tick");timer.Remove("ulx_traincrash_spawnq")
local ok,err=xpcall(f,debug.traceback)
if not ok then
 timer.Remove("ulx_traincrash_tick");timer.Remove("ulx_traincrash_spawnq")
 ulx.traincrash=R.trainBlock
 local cmd=ULib.cmds.translatedCmds["ulx traincrash"];if cmd then cmd.fn=R.trainBlock end
 error(err)
end
assert(timer.Exists("ulx_traincrash_tick") and timer.Exists("ulx_traincrash_spawnq"))
assert(ULib.cmds.translatedCmds["ulx traincrash"].fn==ulx.traincrash)
R.audit.trainApplied=true;R.audit.trainSourceHash=receipt.source_sha256
R.audit.trainArchiveHash=receipt.after;R.audit.trainAppliedAt=os.time()
assert(R.Verify())
print("TRAIN_ARCHIVE_ACTIVE",receipt.source_sha256)
