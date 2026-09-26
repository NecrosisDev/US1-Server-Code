-- Rollback only this cosmetic observer; existing players' puffs expire naturally.
local f=ZCFartPuff
if f then
 local hooks=hook.GetTable()
 assert(not hooks.EntityEmitSound or not hooks.EntityEmitSound.ZCFartPuff_Sound or hooks.EntityEmitSound.ZCFartPuff_Sound==f.OnSound,'observer changed since deployment')
 f.epoch=f.epoch+1
 hook.Remove('EntityEmitSound','ZCFartPuff_Sound')
 hook.Remove('ZB_EndRound','ZCFartPuff_Reset')
 hook.Remove('PostCleanupMap','ZCFartPuff_Reset')
 hook.Remove('PlayerDisconnected','ZCFartPuff_Forget')
 f.Version='disabled'
end
print('ZCFART_ROLLBACK_DISABLED')
