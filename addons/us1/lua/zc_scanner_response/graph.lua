-- Read-only Source nodegraph parser. Never generates or modifies a map graph.
local G={}
local function finite(n)return isnumber(n) and n==n and math.abs(n)<10000000 end
function G.Read(f,size,count)
    assert(size>=16 and size<=8388608,"invalid_size")
    assert(f:ReadLong()==37,"unsupported_version")
    local revision=f:ReadLong();local n=f:ReadLong()
    assert(n>=2 and n<=16384 and n==count,"node_count_mismatch")
    assert(size>=16+n*65,"truncated_nodes")
    local nodes={}
    for i=1,n do
        local x,y,z,yaw=f:ReadFloat(),f:ReadFloat(),f:ReadFloat(),f:ReadFloat()
        local offset=f:ReadFloat();f:Seek(f:Tell()+36)
        local kind=f:ReadByte();local flags=f:ReadUShort();local zone=f:ReadShort()
        assert(finite(x) and finite(y) and finite(z) and finite(yaw) and finite(offset),"invalid_node")
        nodes[i]={pos=Vector(x,y,z+offset),kind=kind,links={},yaw=yaw,zone=zone}
    end
    local links=f:ReadLong()
    assert(links>=1 and links<=262144 and f:Tell()+links*14+n*4<=size,"truncated_links")
    for _=1,links do
        local a,b=f:ReadShort()+1,f:ReadShort()+1
        local walk=f:ReadByte();f:Seek(f:Tell()+9)
        assert(a>=1 and a<=n and b>=1 and b<=n and a~=b,"invalid_link")
        if nodes[a].kind==2 and nodes[b].kind==2 and bit.band(walk,1)~=0 then
            nodes[a].links[#nodes[a].links+1]=b;nodes[b].links[#nodes[b].links+1]=a
        end
    end
    local ground,components={},{}
    for i,node in ipairs(nodes)do
        if node.kind==2 and #node.links>0 and not node.component then
            local component=#components+1;local queue={i};node.component=component
            local head=1
            while queue[head] do
                local id=queue[head];head=head+1;ground[#ground+1]=id
                for _,other in ipairs(nodes[id].links)do
                    if not nodes[other].component then nodes[other].component=component;queue[#queue+1]=other end
                end
            end
            components[component]=#queue
        end
    end
    assert(#ground>=2,"no_walkable_ground")
    return {nodes=nodes,ground=ground,components=components,revision=revision,count=n}
end
function G.Load()
    local count=ai.GetNodeCount and ai.GetNodeCount() or 0
    if count<2 then return nil,"no_loaded_nodegraph" end
    local path="maps/graphs/"..game.GetMap()..".ain"
    local f=file.Open(path,"rb","GAME")
    if not f then return nil,"no_readable_nodegraph" end
    local ok,result=pcall(G.Read,f,f:Size(),count);f:Close()
    if not ok then return nil,"unusable_nodegraph" end
    return result
end
return G
