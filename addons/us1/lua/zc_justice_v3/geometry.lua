-- Pure geometry over copied numeric vectors. No traces, RNG, or engine state.
return function(U)
    local G={}
    local function vector(v)
        assert(type(v)=="table" and U.finite(v[1]) and U.finite(v[2]) and U.finite(v[3]),"invalid vector")
        return v
    end
    function G.subtract(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
    function G.dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
    function G.length(a) return math.sqrt(G.dot(a,a)) end
    function G.distance(a,b) return G.length(G.subtract(a,b)) end
    function G.segment_box(start,finish,shape,tolerance)
        vector(start);vector(finish);vector(shape.origin);vector(shape.mins);vector(shape.maxs)
        tolerance=tolerance or 0;U.number(tolerance,0,64,"shape tolerance")
        local rel=G.subtract(start,shape.origin);local direction=G.subtract(finish,start)
        local low,high=0,1
        for i=1,3 do
            local axis=vector(shape.axes[i]);local x=G.dot(rel,axis);local d=G.dot(direction,axis)
            local a,b=shape.mins[i]-tolerance,shape.maxs[i]+tolerance
            if math.abs(d)<1e-10 then
                if x<a or x>b then return false end
            else
                local t1,t2=(a-x)/d,(b-x)/d
                if t1>t2 then t1,t2=t2,t1 end
                low,high=math.max(low,t1),math.min(high,t2)
                if low>high then return false end
            end
        end
        return true,low
    end
    function G.directed(input)
        if not input.committed or not input.timeline_valid then return false,"UNCOMMITTED_OR_UNVALIDATED" end
        if input.ricochet then return false,"RICOCHET" end
        if input.known_interception then return false,"AMBIGUOUS_INTERCEPT" end
        if not input.shapes or #input.shapes==0 then return false,"SHAPE_UNAVAILABLE" end
        local intended,actual=false,false
        for _,shape in ipairs(input.shapes)do
            if G.segment_box(input.start,input.intended_end,shape,8)then intended=true end
            if G.segment_box(input.actual_start or input.start,input.actual_end,shape,24)then actual=true end
        end
        if not intended then return false,"NOT_DIRECTED" end
        if not actual then return false,"PATH_MISSED_OR_OBSTRUCTED" end
        return true,"DIRECTED_PATH"
    end
    return G
end
