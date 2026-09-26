-- Pure helpers. No engine services, gameplay RNG, networking or global mutation.
local U = {}
function U.finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function U.number(n, lo, hi, name)
    assert(U.finite(n) and n>=lo and n<=hi, "invalid "..(name or "number"))
    return n
end
function U.integer(n,lo,hi,name)
    U.number(n,lo,hi,name); assert(n==math.floor(n),"non-integer "..(name or "number")); return n
end
function U.id(s, name)
    assert(type(s)=="string" and #s>0 and #s<=192 and s:match("^[%w_:%.%-/]+$"), "invalid "..(name or "id"))
    return s
end
function U.clamp(n,a,b) return math.max(a,math.min(n,b)) end
function U.round(n) return n>=0 and math.floor(n+0.5) or -math.floor(-n+0.5) end
function U.copy(value, depth, seen)
    local t=type(value)
    if t=="nil" or t=="boolean" or t=="string" then return value end
    if t=="number" then assert(U.finite(value),"nonfinite value"); return value end
    assert(t=="table", "plain data required")
    depth=(depth or 0)+1; assert(depth<=24,"copy depth")
    seen=seen or {}; assert(not seen[value],"cyclic data")
    assert(getmetatable(value)==nil,"plain table required")
    seen[value]=true; local result={}
    for k,v in pairs(value) do
        assert(type(k)=="string" or type(k)=="number","invalid key")
        result[k]=U.copy(v,depth,seen)
    end
    seen[value]=nil; return result
end
function U.keys(t)
    local out={}; for k in pairs(t) do out[#out+1]=k end
    table.sort(out,function(a,b)return tostring(a)<tostring(b)end); return out
end
-- Canonical request identities detect conflicting reuse of a once-only receipt.
function U.canonical(x, depth)
    local t=type(x)
    if t=="nil" then return "n" end
    if t=="boolean" then return x and "t" or "f" end
    if t=="number" then assert(U.finite(x)); return "d"..string.format("%.17g",x)..";" end
    if t=="string" then return "s"..#x..":"..x end
    assert(t=="table" and not getmetatable(x),"canonical plain data")
    depth=(depth or 0)+1; assert(depth<=24,"canonical depth")
    local out={"{"}; for _,k in ipairs(U.keys(x)) do
        out[#out+1]=U.canonical(k,depth); out[#out+1]=U.canonical(x[k],depth)
    end
    out[#out+1]="}"; return table.concat(out)
end
function U.pack(...) return {n=select("#",...),...} end
function U.unpack(t) return (unpack or table.unpack)(t,1,t.n) end
function U.equal(a,b) return U.canonical(a)==U.canonical(b) end
function U.money(n) return U.round(U.number(n,-1000000,1000000,"karma")*1000000) end
-- Largest remainder allocation: exact integer conservation; deterministic ties.
function U.allocate(total, weights)
    U.integer(total,0,9007199254740991,"total")
    local sum=0; local keys=U.keys(weights)
    for _,id in ipairs(keys) do sum=sum+U.number(weights[id],0,9007199254740991,"weight") end
    local result,remainders={},{}; local used=0
    if sum==0 then assert(total==0,"cannot allocate positive total");return result end
    for _,id in ipairs(keys) do
        local raw=(weights[id]/sum)*total; local base=math.floor(raw)
        result[id]=base;used=used+base;remainders[#remainders+1]={id=id,f=raw-base}
    end
    table.sort(remainders,function(a,b)if a.f==b.f then return a.id<b.id end return a.f>b.f end)
    assert(total-used<=#remainders and total-used>=0,"allocation precision")
    for i=1,total-used do local id=remainders[i].id;result[id]=result[id]+1 end
    return result
end
return U
