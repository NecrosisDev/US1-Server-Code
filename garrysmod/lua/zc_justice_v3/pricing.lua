return function(U,C)
    local P={}
    local knots={{0,10},{25,0},{50,-10},{100,-20},{120,-30}}
    local slopes={0}
    for i=2,#knots-1 do
        local a=(knots[i][2]-knots[i-1][2])/(knots[i][1]-knots[i-1][1])
        local b=(knots[i+1][2]-knots[i][2])/(knots[i+1][1]-knots[i][1])
        slopes[i]=a*b>0 and 2*a*b/(a+b) or 0
    end
    slopes[#knots]=0
    function P.value(karma)
        karma=U.clamp(U.number(karma,-60,1000000,"karma"),0,120)
        for i=1,#knots-1 do
            local a,b=knots[i],knots[i+1]
            if karma<=b[1] then
                local h=b[1]-a[1];local t=(karma-a[1])/h
                return (2*t^3-3*t^2+1)*a[2]+(t^3-2*t^2+t)*h*slopes[i]
                    +(-2*t^3+3*t^2)*b[2]+(t^3-t^2)*h*slopes[i+1]
            end
        end
    end
    function P.loss(karma,units)
        return U.money(math.max(0,-P.value(karma))*U.clamp(U.number(units,0,10000,"harm units"),0,10)/10)
    end
    function P.bounty(karma) return U.money(math.max(0,P.value(karma))) end
    function P.passive_rate(karma)
        U.number(karma,-60,120,"karma");if karma>=50 then return 0 end
        local deficit=(50-U.clamp(karma,0,50))/25
        return (0.00025+0.00075*deficit)*(karma<=25 and 2 or 1)
    end
    -- Physical retention does NOT consult scoring, guilt, attribution or role secrets.
    function P.retention(mode)
        return mode.public_tdm==true and mode.hidden~=true and 0.75 or 1
    end
    function P.reflect(s, e)
        local b=C.brain
        if not e.accountable or not e.accepted or e.system or e.control_only or e.admin then return 0,s end
        local now=U.number(e.time,0,1e12,"time")
        local raw=U.number(e.damage,0,1e9,"damage")
        local weight=assert(b.weights[e.weight],"unregistered brain weight")
        local brain=U.number(e.brain,0,1e6,"brain");local mult=e.traitor_pair and 2 or 1
        local scale=U.number(e.scale or 1,0,2,"feedback multiplier")
        s=U.copy(s or {score=0,last=now,added=0,burst=now,used=0})
        assert(now>=s.last,"backdated feedback")
        local before=math.max(0,s.score-math.max(0,now-s.last-b.delay)*b.decay)
        local after=before+math.min(raw,100)*weight
        local excess=math.max(0,after-b.grace)-math.max(0,before-b.grace)
        if now-s.burst>=b.burst_time then s.burst=now;s.used=0 end
        local add=math.max(0,math.min(excess*b.scale*mult*scale,
            b.burst_cap*mult-s.used,b.life_cap-s.added,b.ceiling-brain))
        s.score=math.min(after,250);s.last=now;s.added=s.added+add;s.used=s.used+add
        return add,s
    end
    return P
end
