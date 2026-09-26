-- Read-only native encoder sampling. Every scratch message is aborted, never sent.
local id='ZC_NativeEncoding132421';assert(not timer.Exists(id),'probe already active')
local r={time=os.time(),players=#player.GetHumans(),map=game.GetMap(),samples={},skipped=0,busy=0,sent=0}
local rows={};local allowed={'Inventory','wounds','arterialwounds','attachments','Armor'}
for e,t in pairs(zb.net.list) do if IsValid(e) then
 for _,key in ipairs(allowed) do if t[key]~=nil and #rows<128 then rows[#rows+1]={ent=e,key=key,creation=e:GetCreationID()}end end
end end
local index=1;local deadline=SysTime()+10;local stopped=false
local function bounded(v,seen,budget,depth)
 if depth>6 then return false end
 local t=type(v);budget.nodes=budget.nodes+1
 if budget.nodes>256 then return false end
 if t=='table' then
  if seen[v] then return false end;seen[v]=true;budget.bytes=budget.bytes+16
  for k,x in pairs(v) do if not bounded(k,seen,budget,depth+1) or not bounded(x,seen,budget,depth+1) then return false end end
  seen[v]=nil
 elseif t=='string' then if #v>4096 then return false end;budget.bytes=budget.bytes+#v+4
 elseif t=='number' or t=='boolean' or isvector(v) or isangle(v) or IsEntity(v) then budget.bytes=budget.bytes+32
 else return false end
 return budget.bytes<32768
end
local function finish(reason)
 if stopped then return end;stopped=true;timer.Remove(id);r.reason=reason;r.finished=os.time();r.selected=#rows
 file.CreateDir('zc_net_validation');file.Write('zc_net_validation/encoding_20260919t132421z.json',util.TableToJSON(r,true))
 print('ZC_NATIVE_ENCODING_FINISHED',#r.samples,r.skipped,r.reason)
end
timer.Create(id,0,0,function()
 if SysTime()>deadline then finish('deadline');return end
 local row=rows[index];if not row then finish('complete');return end
 if net.BytesWritten()~=nil then r.busy=r.busy+1;return end
 index=index+1
 local t=IsValid(row.ent) and row.ent:GetCreationID()==row.creation and zb.net.list[row.ent]
 local value=t and t[row.key]
 if value==nil or not bounded(value,{},{bytes=0,nodes=0},0) then r.skipped=r.skipped+1;return end
 local started=SysTime()
 local ok,bytes=pcall(function()
  net.Start('zbNetVarSet',false);net.WriteUInt(row.ent:EntIndex(),16)
  net.WriteString(row.key);net.WriteType(value);return net.BytesWritten()
 end)
 net.Abort()
 r.samples[#r.samples+1]={key=row.key,bytes=ok and bytes or nil,ms=(SysTime()-started)*1000,error=not ok and tostring(bytes):sub(1,200) or nil}
end)
print('ZC_NATIVE_ENCODING_STARTED',#rows)
