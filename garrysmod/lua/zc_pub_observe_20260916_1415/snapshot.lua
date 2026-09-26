-- Read-only, bounded content snapshot. Returns nil rather than guess on unknown data.
local S={version="20260916.1"}
function S.Take(value,deadline)
    local visited,nodes,bytes={},0,0
    local function token(tag,text)
        bytes=bytes+#text+12;if bytes>65536 then error("bytes",0)end
        return tag..#text..":"..text
    end
    local function number(n)
        if n~=n or n==math.huge or n==-math.huge then error("nonfinite",0)end
        return string.format("%.17g",n)
    end
    local encode
    encode=function(v,depth)
        nodes=nodes+1
        if nodes>1024 or depth>12 then error("complex",0)end
        if nodes%16==0 and SysTime()>deadline then error("deadline",0)end
        if v==nil then return "Z"end
        if isbool(v)then return v and "B1" or "B0"end
        if isnumber(v)then return token("N",number(v))end
        if isstring(v)then return token("S",v)end
        if isvector(v)then return token("V",number(v.x)..","..number(v.y)..","..number(v.z))end
        if isangle(v)then return token("A",number(v.p)..","..number(v.y)..","..number(v.r))end
        if IsEntity(v)then
            if not IsValid(v)then error("invalid_entity",0)end
            return token("E",v:EntIndex().."/"..v:GetCreationID())
        end
        if not istable(v) or getmetatable(v)~=nil then error("unsupported",0)end
        if visited[v]then error("cycle",0)end;visited[v]=true
        local entries={}
        for k,item in pairs(v)do
            if not isstring(k) and not isnumber(k) and not isbool(k)then error("key_type",0)end
            entries[#entries+1]=encode(k,depth+1).."="..encode(item,depth+1)
        end
        visited[v]=nil;table.sort(entries)
        return "T"..#entries.."{"..table.concat(entries,";").."}"
    end
    if SysTime()>deadline then return nil,"deadline"end
    local ok,result=pcall(encode,value,0)
    if not ok then return nil,result end
    if SysTime()>deadline then return nil,"deadline"end
    return result
end
return S
