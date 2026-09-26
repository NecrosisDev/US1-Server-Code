-- One-time state export from this task's legacy reaction module before reload.
-- Only read its named upvalues; never alter or wrap global net/hook libraries.
if not ZCChatReactionStore then
 local register=assert(ZCChatReaction_Register)
 for i=1,20 do
  local name,value=debug.getupvalue(register,i)
  if not name then break end
  if name=="original" and isfunction(value) then register=value break end
 end
 local values={}
 for i=1,20 do local name,value=debug.getupvalue(register,i) if not name then break end values[name]=value end
 assert(istable(values.reactions) and istable(values.order) and isnumber(values.nextID),"reaction migration source did not match")
 ZCChatReactionStore={records=values.reactions,order=values.order,nextID=values.nextID}
end
file.Write("zc_chat_moderation_stage/migration.json",util.TableToJSON({ok=true,records=table.Count(ZCChatReactionStore.records),order=#ZCChatReactionStore.order,nextID=ZCChatReactionStore.nextID}))
print("ZC_MODERATION_MIGRATION_READY",#ZCChatReactionStore.order)
