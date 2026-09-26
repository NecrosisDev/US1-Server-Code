-- Recompile only the notified native functions, preserving captured object references.
return function(original,code,label)
 assert(type(original)=='function','missing original '..label)
 local info=debug.getinfo(original,'S')
 assert(info.source=='@addons/zcity/lua/weapons/weapon_hands_sh.lua','unexpected owner '..tostring(info.source))
 local values,indices,decl={},{},{}
 for i=1,100 do
  local n,v=debug.getupvalue(original,i);if not n then break end
  assert(n:match('^[%a_][%w_]*$'),'invalid upvalue name')
  if type(debug.upvaluejoin)~='function' then
   assert(type(v)=='table' or type(v)=='function' or isvector(v) or isangle(v),label..': non-reference upvalue '..n..' ('..type(v)..')')
   assert(not code:find('%f[%w_]'..n..'%s*=[^=]'),label..': rebinds captured reference '..n)
  end
  values[n]=v;indices[n]=i;decl[#decl+1]='local '..n..'=__captured['..string.format('%q',n)..']'
 end
 local factory=CompileString(table.concat(decl,'\n')..'\n'..code,'@addons/zcity/lua/weapons/weapon_hands_sh.lua',false)
 assert(type(factory)=='function',tostring(factory))
 setfenv(factory,setmetatable({__captured=values},{__index=getfenv(original)}))
 local f=factory();assert(type(f)=='function','not a function');setfenv(f,getfenv(original))
 for i=1,100 do
  local n=debug.getupvalue(f,i);if not n then break end
  assert(indices[n],'unexpected new upvalue '..n)
  if type(debug.upvaluejoin)=='function' then debug.upvaluejoin(f,i,original,indices[n])
  else debug.setupvalue(f,i,values[n]) end
 end
 return f
end
