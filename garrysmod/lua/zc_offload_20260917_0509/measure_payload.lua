-- Native serialization size only. The encoded message is always aborted, never sent.
return function(index, inventory)
 assert(SERVER and istable(inventory))
 local function bytes(value)
  local result
  local ok,err=pcall(function()
   net.Start("zbNetVarSet")
   net.WriteUInt(index,16);net.WriteString("Inventory");net.WriteType(value)
   result=net.BytesWritten()
  end)
  net.Abort()
  if not ok then error(err,0)end
  return result
 end
 local start=SysTime()
 local full=bytes(inventory)
 local ammo=istable(inventory.Ammo) and bytes({Ammo=inventory.Ammo}) or nil
 local public={}
 for key,value in pairs(inventory)do if key~="Ammo"then public[key]=value end end
 local rest=bytes(public)
 return {fullBytes=full,ammoOnlyBytes=ammo,withoutAmmoBytes=rest,elapsedMs=(SysTime()-start)*1000}
end
