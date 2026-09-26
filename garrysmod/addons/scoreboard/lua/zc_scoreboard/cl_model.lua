if not CLIENT then return end
local S=ZCScoreboard
-- Only public fields; neither hidden role, alive status nor unsettled karma enters the model.
function S.ReadPlayer(p)
 if not IsValid(p)then return end
 local H=S.Services
 return {entity=p,id=p:UserID(),name=p:Nick() or "Player",bot=p:IsBot(),
  spectator=TEAM_SPECTATOR and p:Team()==TEAM_SPECTATOR or false,
  character=p:GetNWString("PlayerName",""),rank=H.Rank(p),karma=H.Karma(p),
  session=H.Session(p),playtime=H.Playtime(p),seconds=H.PlaySeconds(p) or 0,
  ping=(p.GetNetVar and p:GetNetVar("zcPing")) or p:Ping() or 0}
end
function S.SelectRows(source,query,filter,sort)
 local rows={};query=string.lower(query or "")
 for _,r in ipairs(source)do
  if (filter~="players" or not r.spectator) and (filter~="spectators" or r.spectator)
   and (S.Services.Bool("show_spectators",true) or not r.spectator)
   and string.find(string.lower(r.name.." "..r.character),query,1,true)then rows[#rows+1]=r end
 end
 table.sort(rows,function(a,b)
  if sort=="playtime" and a.seconds~=b.seconds then return a.seconds>b.seconds end
  if sort=="ping" and a.ping~=b.ping then return a.ping<b.ping end
  local an,bn=string.lower(a.name),string.lower(b.name)
  if an~=bn then return an<bn end
  return a.id<b.id
 end)
 return rows
end
function S.PublicKarmaText(value)
 return value==nil and "—" or tostring(value)
end
-- Stable identity includes the actual entity and join id. Bots never share SteamID keys.
function S.Reconcile(rows,current,create,update,remove)
 local seen={}
 for index,data in ipairs(rows)do
  local p=data.entity;local row=current[p]
  if row and row.joinID~=data.id then remove(row);current[p]=nil;row=nil end
  if not row then row=create(data);row.joinID=data.id;current[p]=row end
  seen[p]=true;update(row,data,index)
 end
 for p,row in pairs(current)do if not seen[p]then remove(row);current[p]=nil end end
end
