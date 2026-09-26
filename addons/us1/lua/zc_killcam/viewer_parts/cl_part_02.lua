return string.sub([========[x            -- Shot and death can share one quantized timestamp; never confirm before contact.
            return math.min(state.cs,b.hit[1]-.01)
        end
        return state.cs
    end
    function P.Past(state, data)
        local n, last = 0, nil
        local cs=P.Clock(state)
        for _, m in ipairs(data.marks) do if m.cs <= cs then n=n+1 last=m end end
        return n,last
    end
    function P.Phase(state)
        local b=state.bullet
        if b and b.at and not b.done and b.cinematic then
            local beat, frac=V.Cinema.Beat(b)
            return ({"PROJECTILE TRACK","CONTACT",b.body and "WOUND TRACE" or "IMPACT ANALYSIS","RESUMING"})[beat],frac,beat
        end
        return state.rate and state.rate<0.95 and "SLOW MOTION" or "RECORDED VIEW",nil,0
    end
    function P.Finale(state)
        local d=P.Data(state)
        local n,last=P.Past(state,d)
        local _,_,finish=P.Bounds(state)
        if not last or n~=d.count or finish-state.cs>90 or (state.bullet and state.bullet.at and not state.bullet.done) then return 0 end
        return V.Cinema.Reduced:GetBool() and 1 or P.Ease((90-(finish-state.cs))/30)
    end
    function P.Card(w,h,state,weapon)
        local s=P.Fonts(h)
        local a=math.Clamp(((state.curtain or 0)-0.5)*2,0,1)
        if a<=0 or state.pending or state.dialog then return end
        local age=(state.cardHold or 1.25)-math.max((state.cardUntil or RealTime())-RealTime(),0)
        local reveal=V.Cinema.Reduced:GetBool() and 1 or P.Ease(age/0.6)
        local left, top, width=w*.10,h*.28,w*.60
        local dx=(1-reveal)*18*s
        local d=P.Data(state)
        local first,span=P.Bounds(state)
        -- An abstract flight motif; it is not a fabricated map or anatomical diagram.
        local cx,cy=w*.82,h*.48
        P.Ring(cx,cy,math.min(144*s,w*.13),1,P.Tint(P.Edge,a*.65))
        P.Ring(cx,cy,math.min(120*s,w*.105),reveal*.73,P.Tint(P.Cyan,a*.45))
        P.Line(w*.70,cy,w*.93,cy,P.Tint(P.Edge,a))
        P.Diamond(cx,cy,9*s,P.Tint(P.Amber,a))
        P.Text(string.format("%02d",math.max(1,V.Cinema.Number(state.index,1))),"Number",cx,cy+35*s,P.Tint(P.Muted,a*.25),TEXT_ALIGN_CENTER)
        P.Rect(left,top-24*s,54*s*reveal,3*s,P.Tint(P.Cyan,a))
        P.Text("HIGHLIGHT OF THE ROUND","Small",left+dx,top,P.Tint(P.Cyan,a),nil,width)
        P.Text(V.Cinema.Hero(state),"Hero",left+dx,top+32*s,P.Tint(P.Paper,a),nil,width)
        P.Text(weapon,"Body",left,top+128*s,P.Tint(P.Muted,a),nil,width*.9)
        P.Text("THE DEFINING MOMENT","Micro",left,h*.71,P.Tint(P.Muted,a),nil,width)
        local cw=math.min(170*s,w*.21)
        local values={string.format("%02d",d.count),string.format("%.1f s",span/100),d.facts.range and string.format("%.1f m",d.facts.range) or "--"}
        local labels={"ELIMINATIONS","RECORDED WINDOW","SELECTED SHOT"}
        for i=1,3 do
            local x=left+(i-1)*(cw+24*s)
            P.Rect(x,top+190*s,cw,1,P.Tint(P.Edge,a))
            P.Text(values[i],"Value",x,top+209*s,P.Tint(i==1 and P.Amber or P.Paper,a),nil,cw)
            P.Text(labels[i],"Micro",x,top+247*s,P.Tint(P.Muted,a),nil,cw)
        end
        P.Text("SPACE  SKIP","Micro",w*.10,h-52*s,P.Tint(P.Muted,a))
        P.Text("US1  /  ROUND REPLAY BETA","Micro",w*.90,h-52*s,P.Tint(P.Muted,a),TEXT_ALIGN_RIGHT)
    end
    function P.Play(w,h,state,weapon)
        local s=P.Fonts(h)
        if state.pending or state.dialog then return end
        local pad,top,bottom=32*s,90*s,88*s
        local d=P.Data(state)
        local n,last=P.Past(state,d)
        local cs=P.Clock(state)
        local first,span,finish=P.Bounds(state)
        local progress=math.Clamp((cs-first)/span,0,1)
        local phase,_,beat=P.Phase(state)
        local accent=beat==1 and P.Amber or P.Cyan
        P.Rect(0,0,w,top,P.Tint(P.Ink,.95))
        P.Rect(0,h-bottom,w,bottom,P.Tint(P.Ink,.96))
        P.Rect(pad,top-1,54*s,1,P.Cyan)
        P.Text("ROUND HIGHLIGHT / BETA","Micro",pad,14*s,P.Cyan)
        P.Text(V.Cinema.Hero(state),"Title",pad,35*s,P.Paper,nil,w*.52-pad)
        P.Text(phase,"Micro",w-pad,14*s,accent,TEXT_ALIGN_RIGHT,w*.39)
        P.Text(weapon,"Body",w-pad,39*s,P.Muted,TEXT_ALIGN_RIGHT,w*.38)
        -- Fine edge shading contains the frame without another view, blur pass or screen flash.
        for i=1,6 do
            local a=(7-i)*.017
            P.Rect(0,top+(i-1)*5*s,w,5*s,P.Tint(P.Ink,a))
            P.Rect(0,h-bottom-i*5*s,w,5*s,P.Tint(P.Ink,a))
        end
        local y=h-bottom+25*s
        local width=w-2*pad
        P.Rect(pad,y,width,2*s,P.Edge)
        P.Rect(pad,y,width*progress,2*s,accent)
        for _,cs in ipairs(d.shots) do
            local x=pad+width*math.Clamp((cs-first)/span,0,1)
            P.Rect(math.min(x,w-pad-s),y-7*s,s,3*s,P.Tint(P.Muted,.45))
        end
        for _,m in ipairs(d.marks) do
            local x=pad+(width-12*s)*math.Clamp((m.cs-first)/span,0,1)+6*s
            P.Diamond(x,y+s,5*s,m.cs<=cs and P.Amber or P.Edge)
        end
        P.Rect(pad+math.min(width-2*s,width*progress),y-3*s,2*s,8*s,P.Paper)
        P.Text("SPACE  SKIP    N  DISABLE","Micro",pad,h-30*s,P.Muted,nil,width*.42)
        P.Text(string.format("%02d / %02d ELIMINATED",n,d.count),"Micro",w-pad,h-30*s,P.Amber,TEXT_ALIGN_RIGHT,width*.40)
        if w>1000*s then P.Text(string.format("%05.2f / %05.2f",math.max(0,cs-first)/100,span/100),"Micro",w/2,h-30*s,P.Muted,TEXT_ALIGN_CENTER) end
        -- Elimination cards only name events that playback has actually reached.
        if last then
            local age=(cs-last.cs)/100
            local alpha=P.Ease(age/.12)*(1-P.Ease((age-1.0)/.35))
            if V.Cinema.Reduced:GetBool() then alpha=age<1.35 and 1 or 0 end
            if alpha>0 then
                local x=pad+(V.Cinema.Reduced:GetBool() and 0 or (1-P.Ease(age/.18))*12*s)
                local yy=top+32*s
                local cw=math.min(326*s,w*.42)
                P.Rect(x,yy,cw,79*s,P.Tint(P.Ink,alpha*.91))
                P.Rect(x,yy,2*s,79*s,P.Tint(P.Amber,alpha))
                P.Text(last.head and "HEADSHOT CONFIRMED" or "ELIMINATION CONFIRMED","Micro",x+16*s,yy+12*s,P.Tint(P.Amber,alpha),nil,cw-32*s)
                P.Text(last.name,"Body",x+16*s,yy+36*s,P.Tint(P.Paper,alpha),nil,cw-32*s)
            end
        end
        -- Finish inside the existing final recorded second; never extend the server hold.
        local a=P.Finale(state)
        if a>0 then
            local yy=h-bottom-142*s
            local cw=math.min(530*s,w*.54)
            P.Rect(pad,yy,cw,112*s,P.Tint(P.Ink,a*.94))
            P.Rect(pad,yy,2*s,112*s,P.Tint(P.Cyan,a))
            P.Text(string.format("%02d",d.count),"Number",pad+18*s,yy+17*s,P.Tint(P.Paper,a),nil,95*s)
            P.Text("MOMENT COMPLETE","Micro",pad+118*s,yy+22*s,P.Tint(P.Cyan,a),nil,cw-134*s)
            P.Text(V.Cinema.Hero(state),"Value",pad+118*s,yy+46*s,P.Tint(P.Paper,a),nil,cw-134*s)
            P.Text("ELIMINATIONS","Micro",pad+18*s,yy+83*s,P.Tint(P.Muted,a),nil,cw-36*s)
        end
    end
    function P.Telemetry(w,h,state,b)
        local s=P.Fonts(h)
        local facts=V.Ballistics.Facts(b)
        local active=state.bullet and state.bullet.at and not state.bullet.done and state.bullet or nil
        local contact=active and active.landed or (not active and state.cs>=b.hit[1])
        local beat,phase=contact and 3 or 1,contact and 1 or 0
        if active and active.cinematic then beat,phase=V.Cinema.Beat(active)
        elseif active then phase=contact and (active.bodyP or 1) or (active.p or 0) end
        local accent=contact and P.Cyan or P.Amber
        local bw=math.min(414*s,w*.47)
        local bh=360*s
        local x,y=w-32*s-bw,math.min(h*.32,h-125*s-bh)
        local reveal=active and not V.Cinema.Reduced:GetBool() and P.Ease(active.t/.2) or 1
        reveal=reveal*(1-P.Finale(state)*.85)
        y=y+(1-reveal)*9*s
        local function tint(c,a)return P.Tint(c,(a or 1)*reveal)end
        P.Rect(x,y,bw,bh,tint(P.Ink,.94))
        P.Rect(x,y,2*s,bh,tint(accent))
        P.Rect(x+2*s,y,bw-2*s,1,tint(P.Edge))
        P.Text("SHOT ANALYSIS","Micro",x+20*s,y+17*s,tint(accent),nil,bw-115*s)
        P.Text(contact and "CONTACT" or "IN FLIGHT","Title",x+20*s,y+40*s,tint(P.Paper),nil,bw-108*s)
        local group=contact and V.HitGroupName and V.HitGroupName(b.hit[6]) or nil
        P.Text(group and group~="" and group:upper() or "BALLISTICS","Micro",x+20*s,y+81*s,tint(P.Muted),nil,bw-115*s)
        -- Incidence diagram: the recorded normal is vertical; zero degrees is a direct impact.
        local cx,cy=x+bw-53*s,y+58*s
        P.Ring(cx,cy,26*s,1,tint(P.Edge))
        if contact and facts.angle then
            local rad=math.rad(facts.angle)
            P.Line(cx-26*s,cy+11*s,cx+26*s,cy+11*s,tint(P.Muted,.7))
            P.Line(cx,cy+11*s,cx,cy-23*s,tint(P.Edge))
            P.Line(cx-math.sin(rad)*30*s,cy+11*s-math.cos(rad)*30*s,cx,cy+11*s,tint(accent))
            P.Diamond(cx,cy+11*s,3*s,tint(accent))
        else
            P.Line(cx-17*s,cy,cx+17*s,cy,tint(accent))
            P.Diamond(cx+17*s,cy,3*s,tint(accent))
        end
        P.Rect(x+20*s,y+111*s,bw-40*s,1,tint(P.Edge))
        local cell=(bw-54*s)/2
        local function metric(label,value,col,row,small)
            local px,py=x+20*s+(col-1)*(cell+14*s),y+128*s+(row-1)*69*s
            P.Text(label,"Micro",px,py,tint(P.Muted),nil,cell)
            P.Text(value,small and "Body" or "Value",px,py+20*s,tint(P.Paper),nil,cell)
        end
        metric("SHOT RANGE",facts.range and string.format("%.1f m",facts.range) or "Not recorded",1,1,not facts.range)
        metric("MUZZLE SPEED (NOMINAL)",facts.muzzle and string.format("%.0f m/s",facts.muzzle) or "Not recorded",2,1,not facts.muzzle)
        metric("IMPACT ANGLE",contact and facts.angle and string.format("%.1f deg",facts.angle) or (contact and "Not recorded" or "Awaiting impact"),1,2,not(contact and facts.angle))
        metric("CALIBER / LOAD",facts.caliber or (facts.diameter and string.format("%.2f mm",facts.diameter)) or "Not recorded",2,2,true)
        P.Rect(x+20*s,y+258*s,bw-40*s,1,tint(P.Edge))
        P.Text(contact and (V.Penetration and V.Penetration.Label(b,active) or string.format("%.0f DAMAGE  /  %s",math.max(0,V.Cinema.Number(b.hit[5])),b.body and "WOUND TRACE" or "CONTACT POINT")) or (V.ShotVisual and V.ShotVisual.Active() and "GENERIC PROFILE / RECORDED SHOT LINE" or "FOLLOWING THE RECORDED SHOT"),"Micro",x+20*s,y+272*s,tint(accent),nil,bw-40*s)
        local summary=contact and V.Penetration and V.Penetration.Detail(b)
        if summary then P.Text(summary,"Micro",x+20*s,y+292*s,tint(P.Muted),nil,bw-40*s) end
        local names={"TRACK","CONTACT",b.body and "TRACE" or "INSPECT","RESUME"}
        local sw=(bw-52*s)/4
        for i=1,4 do
            local px=x+20*s+(i-1)*(sw+4*s)
            P.Text(names[i],"Micro",px,y+321*s,tint(i==beat and accent or P.Muted),nil,sw)
            P.Rect(px,y+344*s,sw,2*s,tint(P.Edge))
            P.Rect(px,y+344*s,sw*(i<beat and 1 or i==beat and phase or 0),2*s,tint(accent))
        end
        if active and active.cinematic then V.Cinema.DrawMarker(w,h,active,V.Cinema.Envelope(active),s) end
        return true
    end
end
-- END HIGHLIGHT PRESENTATION

-- BEGIN SHOT VISUAL: cosmetic reconstruction on the existing recorded segment.
do
    local S = {}
    V.ShotVisual = S
    S.Enabled = CreateClientConVar("zc_killcam_shot_realism", "1", true, false, "Solid projectile and restrained contact presentation")
    -- Non-additive, depth-tested vertex colours. No model, mesh or emitter lifetime to leak.
    S.Metal = Material("color")
    S.Profile = {{0,0},{-0.30,0.30},{-0.72,0.46},{-1.05,0.50},{-2.65,0.50},{-2.85,0.42}}
    S.Radials = {}
    for i = 0, 12 do
        local a = i * math.pi / 6
        S.Radials[i + 1] = {math.cos(a), math.sin(a)}
    end
    function S.Active() return S.Enabled:GetBool() end
    function S.Progress(t)
        t = math.Clamp(t, 0, 1)
        -- Integrate a smooth speed ramp: continuous velocity at both joins, with a
        -- finite arrival speed. This is presentation time, not measured ballistics.
        local x = math.Clamp((t - 0.55) / 0.4, 0, 1)
        local integral = 0.4 * (x ^ 3 - x ^ 4 * 0.5) + math.max(0, t - 0.95)
        return (t - 0.88 * integral) / 0.78
    end
    function S.Diameter(b)
        if b.visualDiameter then return b.visualDiameter, b.visualMeasured end
        local facts = V.Ballistics and V.Ballistics.Facts(b)
        local mm = facts and facts.diameter
        -- Use the captured diameter at the game's own 52.5 units/metre scale.
        -- Shape/length are a generic profile, never a cartridge identification.
        b.visualMeasured = mm and mm >= 2 and mm <= 20 or false
        b.visualDiameter = b.visualMeasured and mm * 0.0525 or 0.28
        return b.visualDiameter, b.visualMeasured
    end
    function S.Light(b)
        if b.visualLight and b.visualLightAt:DistToSqr(b.at) < 16 * 16 and math.abs(b.t - b.visualLightTime) < 0.1 then return b.visualLight end
        local light = render.ComputeLighting(b.at)
        b.visualLight = Vector(math.Clamp(V.Cinema.Number(light.x),0,1), math.Clamp(V.Cinema.Number(light.y),0,1), math.Clamp(V.Cinema.Number(light.z),0,1))
        b.visualLightAt, b.visualLightTime = b.at, b.t
        return b.visualLight
    end
    function S.Projectile(b, nose, alpha)
        local d = S.Diameter(b)
        local light = S.Light(b)
        local available = b.landed and math.huge or b.span * (b.p or 0)
        local key = Vector(0.35,-0.45,0.82):GetNormalized()
        render.SetMaterial(S.Metal)
        for i = 1, 12 do
            local a, z = S.Radials[i], S.Radials[i + 1]
            local right = b.side * a[1] + b.up * a[2]
            local nextRight = b.side * z[1] + b.up * z[2]
            local shade = 0.40 + 0.60 * math.max(0, (right + nextRight):GetNormalized():Dot(key))
            local colour = Color(196 * shade * light.x, 137 * shade * light.y, 82 * shade * light.z, 255 * alpha)
            for j = 1, #S.Profile - 1 do
                local p, q = S.Profile[j], S.Profile[j + 1]
                local first = nose - b.dir * math.min(-p[1]*d,available)
                local last = nose - b.dir * math.min(-q[1]*d,available)
                -- The tip is the recorded position; geometry never leads it in flight.
                render.DrawQuad(first + nextRight * (p[2]*d), last + nextRight * (q[2]*d), last + right * (q[2]*d), first + right * (p[2]*d), colour)
            end
            local cap = nose - b.dir * math.min(2.85*d,available)
            render.DrawQuad(cap, cap + right * (0.42*d), cap + nextRight * (0.42*d), cap, Color(76*light.x,64*light.y,51*light.z,255*alpha))
        end
    end
    function S.Contact(state,b,alpha)
        local age = b.t - 1.25
        if age <= 0 or age >= 1.1 then return end
        local reduced = V.Cinema.Reduced:GetBool()
        local fade = alpha * (1 - age / 1.1)
        local light = S.Light(b)
        -- 2026-09-24 (owner: "improve the impact"): the contact itself reads as an event - a short hot flash at the
        -- recorded landing point and one shock ring in the plane of impact. Both sit ON the recorded point; neither
        -- guesses a surface normal, a material or a direction the data does not hold.
        S.Glow = S.Glow or Material("sprites/light_glow02_add")
        local flash = 1 - math.Clamp(age / 0.22, 0, 1)
        if flash > 0 then
            render.SetMaterial(S.Glow)
            local size = 4 + 16 * (1 - flash) * (reduced and 0.4 or 1)
            render.DrawSprite(b.to, size, size, Color(255, 236, 200, 230 * flash * alpha))
            render.DrawSprite(b.to, size * 0.45, size * 0.45, Color(255, 255, 255, 255 * flash * alpha))
        end
        if not reduced then
            local ring = math.Clamp(age / 0.4, 0, 1)
            if ring < 1 then
                local r = 1.5 + 11 * V.BulletEase(ring)
                V.Cinema.Ring(b.to, b.side, b.up, r, Color(255, 214, 160, 170 * (1 - ring) * alpha))
                V.Cinema.Ring(b.to, b.side, b.up, r * 0.6, Color(255, 240, 220, 110 * (1 - ring) * alpha))
            end
        end
        -- Blood is cosmetic and requires the recorded organism corridor plus an
        -- owned victim. No guessed surface normal, sparks or explosion.
        if reduced or not b.body or not V.Gore or not V.Gore.Enabled:GetBool() or not V.Cinema.Target(state,b) then return end
        -- wound_fx: back-spatter as soft blood droplets on arcs, not solid-colour streaks
        V.Wound.Spray(b.to, -b.dir, b.side, b.up, age, 18, 6, 7, fade, light)
        -- A brief mist at the wound: three soft dark blooms that drift out and thin.
        if V.Gore.Blood then
            render.SetMaterial(V.Gore.Blood)
            for i = 1, 3 do
                local a = i * 2.0944
                local drift = (b.side * math.cos(a) + b.up * math.sin(a)) * (1.2 + age * 3) - b.dir * (1 + age * 2)
                local size = (2.5 + i * 0.7) * (0.6 + age * 1.6)
                render.DrawSprite(b.to + drift, size, size, Color(96*light.x, 8*light.y, 6*light.z, 160*fade*fade))
            end
        end
        -- The exit, only when the recorded corridor says the round left the body: a narrower spray carrying on
        -- along the round's line from the recorded trace end.
        local v2 = b.body.v2
        if v2 and v2.reason == "exited" and b.body.last and age <= 0.8 then
            local efade = fade * (1 - age / 0.8)
            V.Wound.Spray(b.body.last, b.dir, b.side, b.up, math.max(0, age - 0.12) * 1.1, 12, 14, 3, efade, light)
        end
    end
    function S.Trace(b,alpha)
        if V.Penetration and V.Penetration.Draw(b,alpha) then return end
        if not b.body then return end
        local reveal = V.BulletEase((b.t - 1.41) / 0.30) * alpha
        if reveal <= 0 then return end
        -- Only a wound trace (no recorded corridor): the reached part as a faint red wisp and a soft glow at its end.
        local at = LerpVector(b.bodyP,b.body.first,b.body.last)
        local d = S.Diameter(b)
        V.Wound.Wisp(b.body.first, at, b.t, 0.4, b.side, b.up, d * 1.3, d * 2.2, d * 0.5, V.Wound.Red, 110 * reveal)
        render.SetMaterial(V.Wound.GlowNoZ)
        render.DrawSprite(at, 2.4, 2.4, Color(255, 120, 100, 150 * reveal))
    end
    function S.Draw(state,b)
        if not S.Active() then return false end
        if not b or not b.at or b.done then return true end
        local alpha = V.BulletWeight(b)
        if alpha <= 0 then return true end
        if V.Wound then V.Wound.Wake(b, alpha) end -- wound_fx: the translucent wake, in flight and briefly after contact
        if not b.landed then
            S.Projectile(b,b.at,alpha)
        else
            local age = b.t - 1.25
            -- Disappear into contact before the analysis fade; never park a glowing
            -- round on the skin or claim the unobserved projectile emerges at trace end.
            if age < 0.12 then
                local depth = S.Diameter(b)*2.85*math.Clamp(age/0.12,0,1)
                S.Projectile(b,b.to+b.dir*depth,alpha*(1-math.Clamp(age/0.12,0,1)))
            end
            S.Contact(state,b,alpha)
            S.Trace(b,alpha)
        end
        return true
    end
end
-- END SHOT VISUAL

-- BEGIN PENETRATION VIEW
do
    local D = {}
    V.Penetration = D
    D.Names = {"SIMULATED STOP", "NO STOP RECORDED", "TRACE LIMIT", "TRACE BOUNDARY", "OUTCOME UNKNOWN"}
    D.V2Names = {lodged="ROUND STOPPED", exited="ROUND EXITED", maxpen="PENETRATION LIMIT", boundary="TRACE BOUNDARY", limit="TRACE LIMIT"}
    D.MarkStyle = {
        entry={color=Color(98,220,239),radius=2.0}, exit={color=Color(120,224,205),radius=2.2},
        armor={color=Color(255,190,92),radius=2.6}, deflect={color=Color(255,138,91),radius=3.0},
        expand={color=Color(192,148,255),radius=2.7}, fragment={color=Color(126,189,255),radius=2.5},
        lodge={color=Color(255,105,111),radius=3.0}, maxpen={color=Color(255,174,94),radius=2.7},
    }
    local function decodePath(rows, origin, from, impact, incoming, maximum)
        if not istable(rows) or #rows < 1 or #rows > maximum then return end
        local points, distances, length = {}, {}, 0
        for i, row in ipairs(rows) do
            if not istable(row) or #row ~= 3 then return end
            for j = 1, 3 do
                if type(row[j]) ~= "number" or row[j] ~= row[j] or math.abs(row[j]) > 1e8 then return end
            end
            local point = Vector(origin[1]+row[1]/10, origin[2]+row[2]/10, origin[3]+row[3]/10)
            if i == 1 then
                if point:Distance(impact) > 24 then return end
            else
                local delta = point-points[#points]
                local step = delta:Length()
                if step > 0 then
                    if #points == 1 and delta:GetNormalized():Dot(incoming) < 0.97 then return end
                    length = length+step
                    if length > 104.1 then return end -- allow decimetre rounding on all 20 stored segments
                end
            end
            if #points == 0 or point:DistToSqr(points[#points]) > 0.0001 then
                points[#points+1], distances[#distances+1] = point, length
            end
        end
        if length < 0.01 and #points > 1 then return end
        return points, distances, length
    end
    local function closestPathDistance(points, distances, point)
        if #points == 1 then return 0 end
        local bestDistance, bestAlong = math.huge, 0
        for i = 2, #points do
            local a, delta = points[i-1], points[i]-points[i-1]
            local t = math.Clamp((point-a):Dot(delta)/math.max(delta:Dot(delta),0.000001),0,1)
            local near = a+delta*t
            local error = point:DistToSqr(near)
            if error < bestDistance then
                bestDistance = error
                bestAlong = distances[i-1]+(distances[i]-distances[i-1])*t
            end
        end
        return bestAlong, bestDistance
    end
    function D.Body(hit, origin, from, impact)
        local data = hit.penetration
        if hit.ballistic ~= 1 or not istable(data) or data.v ~= 1 or type(data.reason) ~= "number"
            or data.reason % 1 ~= 0 or not D.Names[data.reason] or not istable(data.points)
            or #data.points < 1 or #data.points > 21 then return end
        local incoming = (impact-from):GetNormalized()
        local points, distances, length = decodePath(data.points,origin,from,impact,incoming,21)
        if not points then return end
        local model = data.v2
        local v2
        if istable(model) and model.v == 2 and (model.mode == "live" or model.mode == "shadow")
            and D.V2Names[model.reason] and type(model.energy) == "number" and model.energy == model.energy
            and model.energy >= 0 and model.energy <= 1 and type(model.deflections) == "number"
            and model.deflections % 1 == 0 and model.deflections >= 0 and model.deflections <= 8
            and type(model.fragments) == "number" and model.fragments % 1 == 0 and model.fragments >= 0 and model.fragments <= 16
            and type(model.armored) == "boolean" and type(model.expanded) == "boolean"
            and istable(model.events) and #model.events <= 12 then
            v2 = {mode=model.mode,reason=model.reason,energy=model.energy,deflections=model.deflections,
                fragments=model.fragments,armored=model.armored,expanded=model.expanded,events={}}
            for _,row in ipairs(model.events) do
                local style = istable(row) and D.MarkStyle[row.k]
                local packed = istable(row) and row.p
                if style and istable(packed) and #packed == 3 then
                    local valid = true
                    for j=1,3 do if type(packed[j]) ~= "number" or packed[j] ~= packed[j] or math.abs(packed[j]) > 1e8 then valid=false break end end
                    if valid then
                        local pos = Vector(origin[1]+packed[1]/10,origin[2]+packed[2]/10,origin[3]+packed[3]/10)
                        if pos:Distance(points[1]) <= 180 then
                            local along = closestPathDistance(points,distances,pos)
                            local event = {kind=row.k,pos=pos,distance=along,style=style}
                            if type(row.f) == "number" and row.f % 1 == 0 and row.f >= 1 and row.f <= 16 then event.fragment=row.f end
                            v2.events[#v2.events+1] = event
                        end
                    end
                end
            end
        end
        if length < 0.01 and data.reason ~= 1 then return end
        return {first=points[1],last=points[#points],span=length,path=points,distances=distances,
            outcome=data.reason,recorded=true,v2=v2}
    end
    function D.Progress(b)
        local start, duration = b.cinematic and 1.41 or 1.30, b.cinematic and 0.95 or 0.45
        if b.body and b.body.recorded and b.body.span < 0.01 then return b.t >= start and 1 or 0 end
        return V.BulletEase((b.t-start)/duration)
    end
    function D.At(body, progress)
        local distance = body.span*math.Clamp(progress,0,1)
        if #body.path == 1 then return body.first, nil, 0 end
        for i = 2, #body.path do
            if distance <= body.distances[i] or i == #body.path then
                local span = body.distances[i]-body.distances[i-1]
                local direction = body.path[i]-body.path[i-1]
                return LerpVector(math.Clamp((distance-body.distances[i-1])/math.max(span,.001),0,1),body.path[i-1],body.path[i]), direction:GetNormalized(), distance
            end
        end
    end
    -- BEGIN ORGAN VIEW (organs_20260925): the organs the recorded round, its fragments and its energy crossed. No new
    -- wire: the recorded path (<= 20 points), the v2 marks and the victim ghost's own organ boxes (the shared
    -- sh_hitboxorgans tables posed on the ghost at the impact frame) say which boxes the corridor crossed and how much
    -- of the round's energy was left on entry (the recorded end energy sets the ramp, 0.35 without v2). Boxes are drawn
    -- through the body once the round reaches them; the one the round is inside breathes; a box holding a lodge or a
    -- fragment mark keeps a red core. Nothing here runs without the organism module on the client.
    D.Organs = CreateClientConVar("zc_killcam_organs", "1", true, false, "Replay: show the organs the recorded round crossed")
    -- wound_fx: tissue tones, not diagnostic neon - pink lung, dark liver-red solid organs, pale bone
    D.Tissue = {flesh=Color(196,128,116), organ=Color(206,96,86), lung=Color(236,150,162), dense=Color(150,38,38),
        vessel=Color(255,52,52), bone=Color(236,226,206), armor=Color(247,199,115)}
    local function pointInBox(ax, x, y, z)
        local px, py, pz = x - ax[10], y - ax[11], z - ax[12]
        for a = 0, 2 do
            local k = a * 3
            local p = px * ax[k + 1] + py * ax[k + 2] + pz * ax[k + 3]
            if p < ax[13 + a] or p > ax[16 + a] then return false end
        end
        return true
    end
    function D.Hits(state, b)
        local body = b and b.body
        if not body or not body.recorded or body.organs ~= nil then return end
        body.organs = false -- computed once per bullet; false = nothing to show
        local org = istable(hg) and hg.organism
        local V2 = istable(org) and org.BallisticsV2
        if not istable(V2) or not isfunction(V2.RayOBB) or not isfunction(V2.BoxAxes) or not isfunction(org.ShootMatrix) or not isfunction(org.GetHitBoxOrgans) then return end
        local ghost = V.Cinema and V.Cinema.Target and V.Cinema.Target(state, b)
        if not IsValid(ghost) then return end
        local ok, organs = pcall(org.GetHitBoxOrgans, ghost:GetModel(), ghost)
        if not ok or not istable(organs) then return end
        local ok2, boxs = pcall(org.ShootMatrix, ghost, organs)
        if not ok2 or not istable(boxs) then return end
        if isfunction(V2.TagShapes) then V2.TagShapes(boxs, organs) end -- organs2: which boxes are ellipsoids / capsules
        local rayTest = isfunction(V2.RayShape) and V2.RayShape or V2.RayOBB
        -- A1 seam (killcam_polish, zc_killcam_impact_anchor): b.to may be the recorded hit point re-placed on the body
        -- (V.HitPoint); the recorded corridor is world space as stamped, so it rides onto the body by the same offset.
        -- Mode 0 (as shipped) gives a zero shift. An implausible re-placement keeps the recorded corridor.
        local shift = Vector(0, 0, 0)
        local o = state and state.clip and state.clip.origin
        if istable(o) and istable(b.hit) and b.hit[9] and isvector(b.to) and not body.zcShifted then -- A1r: V.ShotRound may have moved the path already
            shift = b.to - Vector(o[1] + b.hit[9] / 10, o[2] + b.hit[10] / 10, o[3] + b.hit[11] / 10)
            if shift:LengthSqr() > 40 * 40 then shift = Vector(0, 0, 0) end
        end
        local energyEnd = body.v2 and body.v2.energy or 0.35
        local span = math.max(body.span, 0.001)
        local hits, byBox = {}, {}
        for i = 2, #body.path do
            local a, delta = body.path[i-1] + shift, body.path[i] - body.path[i-1]
            local len = delta:Length()
            if len > 0.001 then
                local d = delta / len
                for k = 1, #boxs do
                    local box = boxs[k]
                    local organ = box[6] and organs[box[6]] and organs[box[6]][box[7]]
                    if organ and not organ[7] then
                        local t0, t1 = rayTest(a.x, a.y, a.z, d.x, d.y, d.z, box)
                        if t0 and t0 < len and t1 > 0 then
                            t0, t1 = math.max(t0, 0), math.min(t1, len)
                            local h = byBox[k]
                            if not h then
                                h = {box = box, organ = organ, name = tostring(organ[1]), enter = body.distances[i-1] + t0, exit = body.distances[i-1] + t1, depth = 0}
                                byBox[k] = h
                                hits[#hits + 1] = h
                            end
                            h.exit = body.distances[i-1] + t1
                            h.depth = h.depth + (t1 - t0)
                        end
                    end
                end
            end
        end
        if #hits == 0 then return end
        local classify = isfunction(V2.Classify) and V2.Classify
        local label = isfunction(org.OrganLabel) and org.OrganLabel
        for _, h in ipairs(hits) do
            h.class = classify and classify(h.organ) or "organ"
            h.label = label and label(h.organ) or h.name
            h.energyIn = 1 - (1 - energyEnd) * math.Clamp(h.enter / span, 0, 1)
            h.energyOut = 1 - (1 - energyEnd) * math.Clamp(h.exit / span, 0, 1)
            h.deposit = math.max(h.energyIn - h.energyOut, 0)
        end
        if body.v2 then
            for _, mark in ipairs(body.v2.events) do
                if mark.kind == "lodge" or mark.kind == "fragment" then
                    for _, h in ipairs(hits) do
                        local mx, my, mz = mark.pos.x + shift.x, mark.pos.y + shift.y, mark.pos.z + shift.z
                        if (isfunction(V2.PointInShape) and V2.PointInShape(h.box, mx, my, mz)) or (not isfunction(V2.PointInShape) and pointInBox(V2.BoxAxes(h.box), mx, my, mz)) then
                            if mark.kind == "lodge" then h.lodged = true end
                            if mark.fragment or mark.kind == "fragment" then h.fragment = true end
                        end
                    end
                end
            end
        end
        table.sort(hits, function(p, q) return p.enter < q.enter end)
        hits.shift = shift
        body.organs = hits
    end
    function D.DrawOrgans(b, reveal, reached, reduced)
        local hits = b.body and b.body.organs
        if not hits or not D.Organs:GetBool() then return end
        cam.IgnoreZ(true)
        render.SetColorMaterial()
        for _, h in ipairs(hits) do
            if h.enter <= reached + 0.5 then
                local c = D.Tissue[h.class] or D.Tissue.organ
                local inside = reached < h.exit and (b.bodyP or 0) < 0.995
                local breathe = (inside and not reduced) and (0.75 + math.sin(b.t * 9) * 0.25) or 1
                local heat = 0.35 + 0.65 * math.min(1, h.deposit * 4)
                -- wound_fx: the organ's own shape as a soft solid (no wireframe: that was the admin hitbox debug view)
                V.Wound.OrganSolid(h.box, Color(c.r, c.g, c.b, (40 + 80 * heat) * breathe * reveal))
                if h.lodged or h.fragment then
                    render.DrawBox(h.box[1], h.box[2], h.box[3] * 0.4, h.box[4] * 0.4, Color(255, 105, 111, 120 * reveal))
                end
            end
        end
        cam.IgnoreZ(false)
    end
    -- "HEART 62%  /  RIGHT LUNG, LOWER LOBE 21%  /  LIVER, RIGHT LOBE (FRAGMENT)": the three organs that took the most
    -- of the round's energy, bones only when the round stopped in one.
    function D.OrganLine(b)
        local hits = b and b.body and b.body.organs
        if not hits then return end
        local ranked = {}
        for _, h in ipairs(hits) do if h.class ~= "bone" or h.lodged then ranked[#ranked + 1] = h end end
        table.sort(ranked, function(p, q) return p.deposit > q.deposit end)
        local out = {}
        for i = 1, math.min(3, #ranked) do
            local h = ranked[i]
            out[#out + 1] = string.upper(h.label) .. (h.lodged and " (STOPPED)" or h.fragment and " (FRAGMENT)" or string.format(" %d%%", math.floor(h.deposit * 100 + 0.5)))
        end
        if #out == 0 then return end
        return table.concat(out, "  /  ")
    end
    -- END ORGAN VIEW
    function D.Detail(b)
        local body = b and b.body
        local v2 = body and body.v2
        if not v2 then return D.OrganLine(b) end
        local labels = {v2.mode == "live" and "V2 LIVE" or "V2 SHADOW"}
        if v2.armored then labels[#labels+1] = "ARMOR" end
        if v2.expanded then labels[#labels+1] = "EXPANSION" end
        if v2.deflections > 0 then labels[#labels+1] = string.format("DEFLECT x%d",v2.deflections) end
        if v2.fragments > 0 then labels[#labels+1] = string.format("FRAG x%d",v2.fragments) end
        local organs = D.OrganLine(b)
        if organs then labels[#labels+1] = organs end
        return table.concat(labels,"  /  ")
    end
    function D.Label(b, active)
        if not b.body then return "DEPTH NOT RECORDED" end
        if not b.body.recorded then return "DEPTH NOT RECORDED / WOUND TRACE ONLY" end
        local progress = active and (active.bodyP or 0) or 1
        local v2 = b.body.v2
        if v2 then
            if progress < 0.995 then return string.format("V2 TRACE %d%% / %d MARKS",math.floor(progress*100+0.5),#v2.events) end
            return string.format("%s  /  %d%% ENERGY REMAINING",D.V2Names[v2.reason],math.floor(v2.energy*100+0.5))
        end
        local depth = b.body.span*progress/0.525 -- world units to centimetres
        local outcome = progress >= 1 and D.Names[b.body.outcome] or "TRAVERSING"
        return string.format("DEPTH %.1f cm / %s",depth,outcome)
    end
    function D.Draw(b, alpha)
        local body=b.body
        if not body or not body.recorded then return false end
        if not b.landed then return true end
        local start=b.cinematic and 1.41 or 1.30
        local reveal=V.BulletEase((b.t-start)/.16)*alpha
        if reveal<=0 then return true end
        local progress = b.bodyP or 0
        local point=D.At(body,progress)
        local reached=body.span*progress
        local reduced = V.Cinema.Reduced:GetBool()
        local v2 = body.v2
        -- The wound reads through the body from any angle (part 07's rule: flight respects walls, the wound view ignores
        -- depth). Same recorded data and timing as before; the look is wound_fx (V.Wound, below).
        D.Glow = D.Glow or Material("sprites/light_glow02_add_noz")
        D.DrawOrgans(b, reveal, reached, reduced) -- under the channel: the organs the round has reached so far
        -- wound_fx: the permanent channel as a faint red wisp, the temporary cavity as pulsing flesh orbs sized by the
        -- energy deposited and the tissue it is in, and the recorded fragments as small gibs (V.Wound, below).
        V.Wound.Channel(b, body, reached, point, reveal)
        V.Wound.Cavity(b, body, reached, reveal, reduced)
        V.Wound.Fragments(b, body, reveal, reduced)
        if progress < 0.995 then
            render.SetMaterial(D.Glow)
            local pulse = reduced and 1 or (1 + math.sin(b.t*22)*0.12)
            render.DrawSprite(point, 3.2*pulse, 3.2*pulse, Color(255,236,220,220*reveal))
            render.DrawSprite(point, 7*pulse, 7*pulse, Color(255,110,90,70*reveal))
        end
        if v2 then
            for _,mark in ipairs(v2.events) do
                local secondaryFragment = mark.fragment and mark.kind ~= "fragment"
                local visible = secondaryFragment and progress >= 0.995 or (not secondaryFragment and mark.distance <= reached+0.75)
                if visible then
                    local c, style = mark.style.color, mark.style
                    local age = math.Clamp((reached - mark.distance) / 6, 0, 1)
                    local pulse = mark.kind == "fragment" and (1.08 + math.sin(b.t*10)*0.08) or 1
                    local pop = reduced and 1 or (1 + 0.9*(1-age))
                    -- wound_fx: a mark is a soft glow that pops as the round reaches it (no wire sphere); fragments fly as
                    -- gibs (V.Wound.Fragments) and a deflection shows in the channel's own kink
                    render.SetMaterial(D.Glow)
                    render.DrawSprite(mark.pos, style.radius*2.2*pop*pulse, style.radius*2.2*pop*pulse, Color(c.r,c.g,c.b,150*reveal*(1-age*0.5)))
                    render.DrawSprite(mark.pos, style.radius*0.8, style.radius*0.8, Color(255,255,255,120*reveal*(1-age*0.6)))
                end
            end
        end
        local stopped = (b.bodyP or 0)>=1 and (body.outcome==1 or (v2 ~= nil and v2.reason=="lodged"))
        if stopped then
            -- The stop: a slow-breathing glow where the round came to rest.
            render.SetMaterial(D.Glow)
            local breathe = reduced and 1 or (1 + math.sin(b.t*4)*0.18)
            render.DrawSprite(point, 4.5*breathe, 4.5*breathe, Color(255,105,111,150*reveal))
        elseif (b.bodyP or 0)>=1 and v2 ~= nil and v2.reason=="exited" then
            render.SetMaterial(D.Glow)
            render.DrawSprite(point, 5, 5, Color(255,120,100,140*reveal)) -- the exit wound
        end
        return true
    end
end
-- END PENETRATION VIEW

-- BEGIN WOUND FX (wound_fx_20260926). Owner: "transparent, wispy trails, not debug-looking solid-color trails ... small
-- gibs for the fragments, and a bright red, fleshy orb to emulate cavitation ... pay attention to ballistics and the
-- organism". Everything here is driven by the recorded round and the server's own tissue model: the diameter
-- (V.ShotVisual.Diameter), the v2 energy the round kept, whether and where it expanded, where it fragmented and where
-- each fragment stopped (v2 marks), and the organ boxes the corridor crossed with the energy left in each (D.Hits, the
-- same sh_ballistics_v2 tissue classes the server walked). Scoped: the assembled viewer sits at LuaJIT's 200-local limit.
do
    local W = {}
    V.Wound = W
    W.Trail = Material("trails/smoke")
    W.GlowNoZ = Material("sprites/light_glow02_add_noz")
    W.Flesh = CreateMaterial("zckc_cavity_v1", "UnlitGeneric", {["$basetexture"] = "vgui/white", ["$translucent"] = 1,
        ["$vertexcolor"] = 1, ["$vertexalpha"] = 1, ["$nocull"] = 1})
    local fleshTexture = Material("models/flesh"):GetTexture("$basetexture")
    if fleshTexture then W.Flesh:SetTexture("$basetexture", fleshTexture) end
    W.Vapour, W.Red = Color(226, 231, 238), Color(122, 18, 16)
    -- Temporary-cavity response per tissue class (V2.Classify): elastic, low-density lung stretches and springs back;
    -- the solid organs (heart, liver, spleen, kidneys: "dense") are inelastic and tear; bone fractures instead of
    -- stretching; armor does not cavitate.
    W.Stretch = {flesh = 1.0, organ = 1.0, vessel = 0.9, dense = 1.35, lung = 0.55, bone = 0.2, armor = 0}
    -- Fragment stand-ins by what the round broke on: bone chips off a bone box, metal off a plate, flesh otherwise.
    W.GibSet = {
        bone = {"models/gibs/hgibs_rib.mdl", "models/gibs/hgibs_scapula.mdl", "models/gibs/hgibs_spine.mdl"},
        armor = {"models/gibs/metal_gib4.mdl", "models/gibs/metal_gib5.mdl", "models/gibs/metal_gib2.mdl"},
        flesh = {"models/gibs/antlion_gib_small_1.mdl", "models/gibs/antlion_gib_small_2.mdl"},
    }
    W.GibTint = {bone = {0.93, 0.88, 0.80}, armor = {0.62, 0.64, 0.68}, flesh = {0.78, 0.22, 0.18}}
    W.Mtx = Matrix()
    local tint = Color(0, 0, 0, 0) -- one colour, refilled per vertex: these run every frame of the shot
    local function fill(c, r, g, b, a) c.r, c.g, c.b, c.a = r, g, b, math.Clamp(a, 0, 255) return c end

    -- A translucent, turbulent ribbon from `tail` to `tip`: two soft layers of the smoke trail texture whose
    -- centreline drifts sideways (more towards the tail, where the air or tissue has had longer to move) and whose
    -- opacity rises towards the tip. Never a solid colour, never a hard line.
    function W.Wisp(tail, tip, t, seed, side, up, tipW, tailW, spread, col, alpha)
        if alpha <= 0.5 then return end
        local delta = tip - tail
        local len = delta:Length()
        if len < 0.05 then return end
        local n = math.Clamp(math.ceil(len / 3), 3, 32)
        render.SetMaterial(W.Trail)
        for layer = 1, 2 do
            local wide = layer == 1
            render.StartBeam(n + 1)
            for i = 0, n do
                local f = i / n
                local s = f * len
                local drift = (1 - f) * spread * (wide and 1 or 0.55)
                local a = math.sin(s * 0.41 + t * 1.9 + seed + layer)
                local c = math.cos(s * 0.29 - t * 1.4 + seed * 1.7 + layer * 2)
                local p = tail + delta * f + side * (a * drift) + up * (c * drift)
                local width = Lerp(f, tailW, tipW) * (wide and 1 or 0.4)
                render.AddBeam(p, width, s / 20 - t * 0.5 + seed, fill(tint, col.r, col.g, col.b, alpha * (wide and 0.5 or 1) * (f ^ 0.8)))
            end
            render.EndBeam()
        end
    end

    -- The round's wake in the air: short, pale, widening and drifting behind it, lingering briefly after contact.
    function W.Wake(b, alpha)
        local age = b.landed and math.max(0, b.t - 1.25) or 0
        local linger = 1 - math.Clamp(age / 0.9, 0, 1)
        if linger <= 0 then return end
        local d = V.ShotVisual.Diameter(b)
        local tip = b.landed and b.to or b.at
        local length = math.min(b.landed and b.span or b.span * (b.p or 0), 72)
        if length < 0.5 then return end
        W.Wisp(tip - b.dir * length, tip, b.t, 1.3, b.side, b.up, d * 1.6, d * 8 + age * 6, 0.9 + age * 3, W.Vapour, 70 * alpha * linger)
    end

    -- Where the recorded round expanded (a v2 "expand" mark), as a distance along the corridor; nil for FMJ/AP.
    local function expandAt(body)
        if body.expandAt ~= nil then return body.expandAt or nil end
        body.expandAt = false
        for _, m in ipairs(body.v2 and body.v2.events or {}) do
            if m.kind == "expand" then body.expandAt = m.distance break end
        end
        return body.expandAt or nil
    end

    -- Peak temporary-cavity radius at distance x along the corridor. The energy the round deposits per unit length
    -- there (the organ box it is in: D.Hits deposit / its depth; else the corridor's average loss) sets the size, the
    -- energy it still carries scales it, the tissue class says how far that tissue stretches, and an expanded round
    -- (recorded "expand" mark behind x) throws a wider cavity. World units; the game's 52.5 units per metre.
    function W.CavityRadius(body, x, d)
        local span = math.max(body.span, 0.001)
        local energyEnd = body.v2 and body.v2.energy or 0.35
        local eIn = 1 - (1 - energyEnd) * math.Clamp(x / span, 0, 1)
        local class, rate = "flesh", (1 - energyEnd) / span
        for _, h in ipairs(body.organs or {}) do
            if x >= h.enter and x <= h.exit then
                class, rate = h.class, h.deposit / math.max(h.exit - h.enter, 0.5)
                if h.class ~= "bone" then break end -- a soft organ inside a bone box is what stretches
            end
        end
        local grow = W.Stretch[class] or 1
        local ex = expandAt(body)
        if ex and x >= ex then grow = grow * 1.6 end
        return math.Clamp(d * (6 + 30 * math.Clamp(rate * 5, 0, 1)) * grow * (0.45 + 0.55 * eIn), 0, 7), class
    end

    -- Seconds since the round passed distance x (the corridor reveal runs over `duration` from `start`).
    local function sincePassed(b, body, x)
        local start, duration = b.cinematic and 1.41 or 1.30, b.cinematic and 0.95 or 0.45
        local span = math.max(body.span, 0.001)
        return ((b.bodyP or 0) - x / span) * duration + math.max(0, b.t - (start + duration))
    end

    -- The permanent wound channel: a faint dark-red wisp along the recorded path, as far as the round has reached.
    function W.Channel(b, body, reached, point, alpha)
        local d = V.ShotVisual.Diameter(b)
        for i = 2, #body.path do
            if body.distances[i - 1] >= reached then break end
            local last = body.distances[i] <= reached and body.path[i] or point
            W.Wisp(body.path[i - 1], last, b.t, i * 0.7, b.side, b.up, d * 1.3, d * 2.2, d * 0.6, W.Red, 120 * alpha)
        end
    end

    -- The temporary cavity: bright red, fleshy orbs along the reached corridor. Each swells as the round passes (the
    -- cavity opens just behind the tip), collapses and pulses a few times, and settles towards the permanent channel.
    -- Reduced motion: one steady, smaller orb per sample, no pulsing.
    function W.Cavity(b, body, reached, alpha, reduced)
        local d = V.ShotVisual.Diameter(b)
        local stepLen = math.max(1.4, body.span / 14)
        cam.IgnoreZ(true)
        render.SetMaterial(W.Flesh)
        local glows = {}
        local x = 0
        while x <= reached and x <= body.span do
            local rmax, class = W.CavityRadius(body, x, d)
            if rmax > 0.05 then
                local age = sincePassed(b, body, x)
                local r, fade
                if reduced then
                    r, fade = rmax * 0.55, 0.8
                else
                    local rise = math.Clamp(age / 0.08, 0, 1)
                    local settle = math.max(0, age - 0.08)
                    local pulse = math.abs(math.cos(settle * 16)) ^ 0.6
                    r = rmax * math.sin(rise * math.pi / 2) * (0.18 + 0.82 * math.exp(-settle / 0.28) * pulse)
                    fade = 0.35 + 0.65 * math.exp(-settle / 0.5)
                end
                if r > 0.05 then
                    local at = V.Penetration.At(body, math.Clamp(x / math.max(body.span, 0.001), 0, 1))
                    if at then
                        local dense = class == "dense" and 1 or 0
                        render.DrawSphere(at, r, 14, 10, fill(tint, 255, 58 - 18 * dense, 46 - 14 * dense, 150 * fade * alpha))
                        glows[#glows + 1] = {at, r, fade}
                    end
                end
            end
            x = x + stepLen
        end
        render.SetMaterial(W.GlowNoZ)
        for _, g in ipairs(glows) do
            render.DrawSprite(g[1], g[2] * 3.4, g[2] * 3.4, fill(tint, 255, 36, 24, 70 * g[3] * alpha))
        end
        cam.IgnoreZ(false)
    end

    local function pickModel(class, k)
        local set = W.GibSet[class] or W.GibSet.bone
        local G = V.Gore
        if not G or not isfunction(G.Model) then return end
        for j = 0, #set - 1 do
            local path = set[(k + j - 1) % #set + 1]
            local m = G.Model("wfx:" .. path, path)
            if IsValid(m) then return m, false end
        end
        return G.Model("wfx:fallback", G.GibModel), true
    end

    -- Fragment paths from the recorded v2 marks: they leave from the "fragment" mark (the bone or plate the round
    -- broke on) and end at that fragment's own terminal mark (lodge / exit / limit, tagged with its index). A fragment
    -- with no recorded end is shown heading 20-45 degrees off the round's line (sh_ballistics_v2 fragAngleMin/Span)
    -- for a distance set by the energy the round kept. Built once per bullet.
    function W.FragmentPaths(b, body)
        if body.fragPaths ~= nil then return body.fragPaths end
        body.fragPaths = false
        local v2 = body.v2
        if not v2 or v2.fragments <= 0 then return false end
        local spawn, ends = nil, {}
        for _, m in ipairs(v2.events) do
            if m.kind == "fragment" and not spawn then spawn = m elseif m.fragment and m.kind ~= "fragment" then ends[m.fragment] = m end
        end
        if not spawn then return false end
        local class = "bone"
        for _, h in ipairs(body.organs or {}) do
            if spawn.distance >= h.enter - 0.5 and spawn.distance <= h.exit + 0.5 and (h.class == "bone" or h.class == "armor") then class = h.class break end
        end
        local paths = {}
        for k = 1, math.min(v2.fragments, 8) do
            local stop = ends[k]
            local to = stop and stop.pos
            if not to then
                local off = math.rad(20 + 25 * ((k * 0.618034) % 1))
                local around = k * 2.399963
                local dir = b.dir * math.cos(off) + (b.side * math.cos(around) + b.up * math.sin(around)) * math.sin(off)
                to = spawn.pos + dir * (3 + 6 * v2.energy)
            end
            paths[k] = {from = spawn.pos, to = to, dist = spawn.distance, class = class, k = k}
        end
        body.fragPaths = paths
        return paths
    end

    -- Small gibs on those paths: they start as the round reaches the break, decelerate through tissue (ease-out) and
    -- tumble less as they slow, each leaving a thin blood wisp behind it.
    function W.Fragments(b, body, alpha, reduced)
        local paths = W.FragmentPaths(b, body)
        if not paths then return end
        local d = V.ShotVisual.Diameter(b)
        cam.IgnoreZ(true)
        for _, f in ipairs(paths) do
            local age = sincePassed(b, body, f.dist)
            if age > 0 then
                local q = 1 - (1 - math.Clamp(age / 0.35, 0, 1)) ^ 3
                local at = LerpVector(q, f.from, f.to)
                local model, fallback = pickModel(f.class, f.k)
                if IsValid(model) then
                    local spin = reduced and 0 or (1 - q) * age * 720
                    model:SetPos(at)
                    model:SetAngles(Angle(f.k * 47 + spin, f.k * 91 + spin * 0.7, f.k * 23))
                    model:SetModelScale(fallback and 0.05 or (0.06 + 0.02 * (f.k % 3)))
                    if fallback then model:SetSubMaterial(0, "models/flesh") end
                    local c = W.GibTint[f.class] or W.GibTint.bone
                    render.SetColorModulation(c[1], c[2], c[3])
                    render.SetBlend(math.Clamp(alpha, 0, 1))
                    model:SetupBones() model:DrawModel()
                    render.SetBlend(1)
                    render.SetColorModulation(1, 1, 1)
                end
                W.Wisp(f.from, at, b.t, f.k * 1.9, b.side, b.up, d * 0.5, d * 0.9, d * 0.3, W.Red, 110 * alpha)
            end
        end
        cam.IgnoreZ(false)
    end

    -- Blood thrown from a wound: droplets on ballistic arcs (the replay's -95 u/s^2 presentation gravity), soft blood
    -- sprites only. `forward` is the speed along `dir` (back towards the shooter at the entry, on along the line at an
    -- exit), `spread` the radial speed.
    function W.Spray(origin, dir, side, up, age, count, forward, spread, alpha, light)
        local G = V.Gore
        if not G or not G.Blood or alpha <= 0 then return end
        render.SetMaterial(G.Blood)
        local time = age * 0.18
        for i = 1, count do
            local a = i * 2.399963
            local radial = side * math.cos(a) + up * math.sin(a)
            local velocity = radial * (spread + i * 0.9) + dir * (forward + i * 1.4)
            local p = origin + velocity * time + Vector(0, 0, -95 * time * time)
            local size = 0.35 + (i % 4) * 0.18
            render.DrawSprite(p, size, size, fill(tint, 112 * light.x, 9 * light.y, 7 * light.z, 210 * alpha * (1 - i / (count + 4))))
        end
    end

    -- Organs as soft solid shapes (their own ellipsoid / capsule / box from sh_hitboxorgans), never wireframes.
    function W.OrganSolid(box, col)
        render.SetColorMaterial()
        local s = box.v2shape
        if s ~= "ellipsoid" and s ~= "capsule" then render.DrawBox(box[1], box[2], box[3], box[4], col) return end
        local half = (box[4] - box[3]) / 2
        local centre = LocalToWorld((box[3] + box[4]) / 2, angle_zero, box[1], box[2])
        if s == "ellipsoid" then
            W.Mtx:Identity() W.Mtx:Translate(centre) W.Mtx:Rotate(box[2]) W.Mtx:Scale(half)
            cam.PushModelMatrix(W.Mtx)
            render.DrawSphere(vector_origin, 1, 16, 12, col)
            cam.PopModelMatrix()
            return
        end
        local f, r, u = box[2]:Forward(), -box[2]:Right(), box[2]:Up()
        local axis, rad, h
        if half.x >= half.y and half.x >= half.z then axis, rad, h = f, math.max(half.y, half.z), half.x
        elseif half.y >= half.z then axis, rad, h = r, math.max(half.x, half.z), half.y
        else axis, rad, h = u, math.max(half.x, half.y), half.z end
        h = math.max(h - rad, 0)
        render.DrawSphere(centre - axis * h, rad, 12, 8, col)
        render.DrawSphere(centre + axis * h, rad, 12, 8, col)
        local mid = Vector(rad, rad, rad)
        if axis == f then mid.x = h elseif axis == r then mid.y = h else mid.z = h end
        render.DrawBox(centre, box[2], -mid, mid, col)
    end
end
-- END WOUND FX








surface.CreateFont("ZCKC.Small", {font = "Tahoma", size = 13, weight = 500})
surface.CreateFont("ZCKC.Body", {font = "Tahoma", size = 15, weight = 500})
surface.CreateFont("ZCKC.Head", {font = "Tahoma", size = 18, weight = 800})

local COL = {
    bg = Color(18, 20, 24, 250), panel = Color(28, 31, 37), line = Color(60, 66, 78), text = Color(225, 228, 235), dim = Color(140, 147, 160),
    victim = Color(90, 170, 255), killer = Color(255, 90, 80), attacker = Color(255, 170, 70), bystander = Color(150, 155, 165),
    good = Color(120, 210, 130), bad = Color(255, 110, 100), shot = Color(255, 220, 120), hit = Color(255, 90, 80), death = Color(255, 255, 255),
    draw = Color(190, 160, 255), aim = Color(255, 170, 70), down = Color(150, 200, 255),
}
local STATUS_TEXT = {[1] = "You are not a party to that clip.", [2] = "That clip has expired.", [3] = "Clips cannot be opened while you are alive in a live round.", [4] = "Still sending the previous clip."}
local MAP_SPAN, MAP_RES = 3200, 1024 -- world units covered by the overhead render, and its texture size

local frame, state -- state: the open clip and playback position

----------------------------------------------------------------- overhead map render
-- One orthographic top-down render of the real map around the death, taken once per clip.
-- The camera sits just under the ceiling above the victim so roofs do not hide interiors.
-- PROVISIONAL(2026-09-21, unseen in-engine by the author: needs the owner's eyes; falls back to the grid, ratify-by: 2026-10-05)
local mapRT, mapMat, hidePlayers
local function renderMap(clip)
    mapRT = mapRT or GetRenderTarget("zckc_map", MAP_RES, MAP_RES)
    mapMat = mapMat or CreateMaterial("zckc_map_mat", "UnlitGeneric", {["$basetexture"] = "zckc_map", ["$translucent"] = "0"})
    mapMat:SetTexture("$basetexture", mapRT)
    local o = Vector(clip.origin[1], clip.origin[2], clip.origin[3])
    local up = util.TraceLine({start = o + Vector(0, 0, 48), endpos = o + Vector(0, 0, 640), mask = MASK_SOLID_BRUSHONLY})
    local camZ = up.HitPos.z - 6
    local half = MAP_SPAN / 2
    render.PushRenderTarget(mapRT)
    render.Clear(0, 0, 0, 255, true, true)
    hidePlayers = true -- a recording must never show where living players are right now
    local ok, err = V.WithReplayScene(function() render.RenderView({
        origin = Vector(o.x, o.y, camZ), angles = Angle(90, 90, 0), x = 0, y = 0, w = MAP_RES, h = MAP_RES,
        ortho = {left = -half, right = half, top = -half, bottom = half}, znear = 1, zfar = camZ - o.z + 600,
        drawviewmodel = false, drawhud = false, drawmonitors = false, dopostprocess = false, bloomtone = false,
    }) end)
    hidePlayers = false
    render.PopRenderTarget()
    if not ok then print("[Killcam] overhead render failed, using the grid: " .. tostring(err)) end
    return ok
end
hook.Add("PrePlayerDraw", "ZCKillcam.HideInMapRender", function() if hidePlayers then return true end end)
hook.Add("PostRender", "ZCKillcam.MapRender", function()
    if not state or not state.wantMap then return end
    state.wantMap = false
    state.hasMap = renderMap(state.clip)
end)

----------------------------------------------------------------- networking
local function ask(name, arg)
    net.Start(name)
    net.WriteString(arg or "")
    net.SendToServer()
end

-- Blobs packed a slice at a time on the server arrive as several compressed streams:
--     "ZCM1" <len>,<len>,...;" <stream> <stream> ...
-- Clips stored before that are one stream with no mark.
function V.Unpack(data)
    if string.sub(data, 1, 4) ~= "ZCM1" then return util.Decompress(data) end
    local stop = string.find(data, ";", 5, true)
    if not stop then return end
    local out, at = {}, stop + 1
    for len in string.gmatch(string.sub(data, 5, stop - 1), "%d+") do
        local text = util.Decompress(string.sub(data, at, at + tonumber(len) - 1))
        if not text then return end
        out[#out + 1] = text
        at = at + tonumber(len)
    end
    return table.concat(out)
end

local parts = {}
local openClip
net.Receive("zckc_clip", function()
    local id, status = net.ReadString(), net.ReadUInt(3)
    if status ~= 0 then
        -- replay_v1 P3: a refusal of what the round viewer asked for is shown there (cl_part_09 V.TapeRefused)
        if V.TapeRefused and string.sub(id, 1, 5) == "tape:" and V.TapeRefused(id, status) then return end
        if IsValid(frame) then frame.note = STATUS_TEXT[status] or "The clip could not be opened." end
        return
    end
    local seq, total, len = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(16)
    local bucket = parts[id]
    if not bucket then -- the server sends one clip at a time: a new id drops whatever was half-received
        bucket = {n = 0}
        parts = {[id] = bucket}
    end
    if not bucket[seq] then bucket[seq] = net.ReadData(len) bucket.n = bucket.n + 1 end
    if bucket.n < total then return end
    parts[id] = nil
    local raw = V.Unpack(table.concat(bucket, "", 1, total))
    -- A round tape is not a clip: it is one JSON mark per LINE, so util.JSONToTable below would fail it and report
    -- "The clip is damaged". Tape ids are prefixed "tape:" and clip ids never are, so the split is unambiguous.
    if raw and string.sub(id, 1, 5) == "tape:" and V.TapeBlob then return V.TapeBlob(id, raw) end
    local clip = raw and util.JSONToTable(raw)
    if not clip or not ((clip.actors and clip.events) or clip.instances) then
        if IsValid(frame) then frame.note = "The clip is damaged." end
        return
    end
    openClip(id, clip)
end)

----------------------------------------------------------------- playback state
-- A life sequence is a list of short clips; the viewer plays one instance at a time.
local function loadInstance(id, seq, index)
    local inst = seq.instances[index]
    if not inst then return end
    openClip(id, inst.clip, seq, index)
end

function openClip(id, clip, seq, index)
    if clip.instances then return loadInstance(id, clip, 1) end
    V.Prepare(clip)
    local runs = V.AimRuns(clip)
    state = {id = id, clip = clip, runs = runs, log = V.BuildLog(clip, runs), findings = V.Findings(clip, runs),
        cs = clip.first, playing = true, speed = 1, follow = clip.victim, zoom = 0.45, camX = 0, camY = 0, showMap = true,
        wantMap = clip.map == game.GetMap(), hasMap = false, seq = seq, index = index,
        reported = state and state.id == id and state.reported or {}}
    if IsValid(frame) then frame.note = nil frame:Rebuild() end
end

local function seek(cs) state.cs = math.Clamp(cs, state.clip.first, state.clip.last) end
local function jumpEvent(dir)
    local best
    for _, e in ipairs(state.log) do
        if dir > 0 and e.cs > state.cs + 5 then best = e.cs break end
        if dir < 0 and e.cs < state.cs - 30 then best = e.cs end
    end
    if best then seek(best) state.playing = false end
end

----------------------------------------------------------------- drawing helpers
local function roleColor(actor) return COL[actor.role] or COL.bystander end
local function dashed(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    dx, dy = dx / len, dy / len
    for d = 0, len, 14 do
        local e = math.min(d + 8, len)
        surface.DrawLine(x1 + dx * d, y1 + dy * d, x1 + dx * e, y1 + dy * e)
    end
end
local function disc(x, y, r, col)
    draw.NoTexture()
    surface.SetDrawColor(col)
    local poly = {}
    for i = 0, 15 do local a = math.rad(i / 16 * 360) poly[#poly + 1] = {x = x + math.cos(a) * r, y = y + math.sin(a) * r} end
    surface.DrawPoly(poly)
end

----------------------------------------------------------------- the scene
local function paintScene(self, w, h)
    surface.SetDrawColor(COL.panel) surface.DrawRect(0, 0, w, h)
    if not state then
        draw.SimpleText(IsValid(frame) and frame.note or "Pick a record on the left.", "ZCKC.Body", w / 2, h / 2, COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    local clip, cs = state.clip, state.cs
    if state.follow and clip.actors[state.follow] then
        local fx, fy = V.StateAt(clip.actors[state.follow], cs)
        if fx then state.camX, state.camY = fx, fy end
    end
    local zoom, cx, cy = state.zoom, w / 2, h / 2
    local function toScreen(x, y) return cx + (x - state.camX) * zoom, cy - (y - state.camY) * zoom end

    if state.showMap and state.hasMap then
        local half = MAP_SPAN / 2
        local x0, y0 = toScreen(-half, half)
        surface.SetDrawColor(255, 255, 255, 235)
        surface.SetMaterial(mapMat)
        surface.DrawTexturedRect(x0, y0, MAP_SPAN * zoom, MAP_SPAN * zoom)
        surface.SetDrawColor(10, 12, 16, 120) surface.DrawRect(0, 0, w, h) -- dim it so the markers read
    else
        surface.SetDrawColor(COL.line.r, COL.line.g, COL.line.b, 70)
        local step = 256
        local gx0 = math.floor((state.camX - cx / zoom) / step) * step
        for gx = gx0, state.camX + cx / zoom, step do local sx = toScreen(gx, 0) surface.DrawLine(sx, 0, sx, h) end
        local gy0 = math.floor((state.camY - cy / zoom) / step) * step
        for gy = gy0, state.camY + cy / zoom, step do local _, sy = toScreen(0, gy) surface.DrawLine(0, sy, w, sy) end
    end
    -- scale bar
    surface.SetDrawColor(COL.text) surface.DrawRect(12, h - 18, 500 * zoom, 2)
    draw.SimpleText("500 units", "ZCKC.Small", 12, h - 34, COL.text)

    local refZ = 0
    if state.follow and clip.actors[state.follow] then local _, _, fz = V.StateAt(clip.actors[state.follow], cs) refZ = fz or 0 end

    -- recent shots and hits stay on screen briefly so a paused frame still shows them
    for _, e in ipairs(clip.events) do
        local age = cs - e[1]
        if age >= 0 and age <= 60 and e[2] ~= 3 then
            local from = clip.actors[e[3]]
            local ax, ay, _, ayaw
            if from then ax, ay, _, ayaw = V.StateAt(from, e[1]) end
            if ax then
                local sx, sy = toScreen(ax, ay)
                local alpha = 255 * (1 - age / 60)
                if e[2] == 2 and clip.actors[e[4]] then
                    local bx, by = V.StateAt(clip.actors[e[4]], e[1])
                    if bx then
                        local tx, ty = toScreen(bx, by)
                        surface.SetDrawColor(COL.hit.r, COL.hit.g, COL.hit.b, alpha)
                        if e[8] == 1 then surface.DrawLine(sx, sy, tx, ty) else dashed(sx, sy, tx, ty) end
                        disc(tx, ty, 4 + 6 * (1 - age / 60), Color(255, 90, 80, alpha))
                    end
                elseif e[2] == 1 then
                    local r = math.rad(ayaw)
                    surface.SetDrawColor(COL.shot.r, COL.shot.g, COL.shot.b, alpha * 0.8)
                    surface.DrawLine(sx, sy, sx + math.cos(r) * 900 * zoom, sy - math.sin(r) * 900 * zoom)
                end
            end
        end
    end

    for i, actor in ipairs(clip.actors) do
        local x, y, z, yaw, _, flags, wep, hp = V.StateAt(actor, cs)
        if x then
            local col = roleColor(actor)
            local sx, sy = toScreen(x, y)
            local dz = z - refZ
            local alpha = math.abs(dz) > 100 and 90 or 255 -- another floor: faded, with an arrow
            local alive, ragdoll = V.HasFlag(flags, 1), V.HasFlag(flags, 4)
            if actor.named then -- two-second trail
                surface.SetDrawColor(col.r, col.g, col.b, 110)
                local px, py
                for back = 200, 0, -20 do
                    local tx, ty = V.StateAt(actor, cs - back)
                    if tx then
                        local qx, qy = toScreen(tx, ty)
                        if px then surface.DrawLine(px, py, qx, qy) end
                        px, py = qx, qy
                    end
                end
            end
            if alive and not ragdoll then
                local target = actor.named and V.AimedAt(clip, i, cs)
                local r = math.rad(yaw)
                local reach = (V.Unarmed(clip, wep) and 60 or 420) * zoom
                if target then surface.SetDrawColor(255, 60, 50, 230) else surface.SetDrawColor(col.r, col.g, col.b, alpha * 0.55) end
                surface.DrawLine(sx, sy, sx + math.cos(r) * reach, sy - math.sin(r) * reach)
            end
            local radius = V.HasFlag(flags, 2) and 5 or 7
            if not alive then
                surface.SetDrawColor(col.r, col.g, col.b, alpha)
                surface.DrawLine(sx - 7, sy - 7, sx + 7, sy + 7) surface.DrawLine(sx - 7, sy + 7, sx + 7, sy - 7)
            elseif ragdoll then
                surface.SetDrawColor(col.r, col.g, col.b, alpha) surface.DrawRect(sx - 9, sy - 3, 18, 6)
            else
                disc(sx, sy, radius, Color(col.r, col.g, col.b, alpha))
            end
            if i == state.follow then surface.DrawCircle(sx, sy, 12, 255, 255, 255, 160) end
            if math.abs(dz) > 100 then draw.SimpleText(dz > 0 and "above" or "below", "ZCKC.Small", sx + 10, sy - 6, Color(255, 255, 255, 200)) end
            if actor.named then
                local tag = actor.label .. (alive and "" or " (dead)") .. (ragdoll and alive and " (down)" or "")
                draw.SimpleTextOutlined(tag, "ZCKC.Small", sx, sy - 26, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
                local class = clip.weaponName[wep]
                draw.SimpleTextOutlined(V.Unarmed(clip, wep) and "unarmed" or (string.gsub(class, "^weapon_", "")), "ZCKC.Small", sx, sy + 18, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, color_black)
                if alive then
                    surface.SetDrawColor(0, 0, 0, 200) surface.DrawRect(sx - 16, sy - 17, 32, 4)
                    surface.SetDrawColor(COL.good) surface.DrawRect(sx - 15, sy - 16, 30 * math.Clamp(hp / 100, 0, 1), 2)
                end
            end
        end
    end
    draw.SimpleText(string.format("%+.1fs   %sx   %s", cs / 100, state.speed, clip.map or ""), "ZCKC.Head", 12, 10, COL.text)
    if clip.map ~= game.GetMap() then draw.SimpleText("Recorded on another map: no backdrop", "ZCKC.Small", 12, 32, COL.dim) end
end

----------------------------------------------------------------- timeline
local function paintTimeline(self, w, h)
    surface.SetDrawColor(COL.panel) surface.DrawRect(0, 0, w, h)
    if not state then return end
    local clip = state.clip
    local function xOf(cs) return 10 + (cs - clip.first) / (clip.last - clip.first) * (w - 20) end
    surface.SetDrawColor(COL.line) surface.DrawRect(10, h / 2 - 2, w - 20, 4)
    for _, run in ipairs(state.runs) do -- when someone held aim on someone: a band under the bar
        local col = roleColor(clip.actors[run.a])
        surface.SetDrawColor(col.r, col.g, col.b, 150)
        surface.DrawRect(xOf(run.from), h / 2 + 5, math.max(xOf(run.to) - xOf(run.from), 2), 3)
    end
    for _, e in ipairs(state.log) do
        if e.kind == "shot" or e.kind == "hit" or e.kind == "death" or e.kind == "draw" then
            surface.SetDrawColor(COL[e.kind])
            local tall = e.kind == "death" and 16 or (e.kind == "hit" and 12 or 7)
            surface.DrawRect(xOf(e.cs) - 1, h / 2 - 3 - tall, 2, tall)
        end
    end
    surface.SetDrawColor(COL.text) surface.DrawRect(xOf(0), 4, 1, h - 8)
    draw.SimpleText("death", "ZCKC.Small", xOf(0) + 4, 2, COL.dim)
    surface.SetDrawColor(255, 255, 255) surface.DrawRect(xOf(state.cs) - 1, 2, 3, h - 4)
    if self.dragging then
        local mx = self:CursorPos()
        seek(clip.first + math.Clamp((mx - 10) / (w - 20), 0, 1) * (clip.last - clip.first))
        if not input.IsMouseDown(MOUSE_LEFT) then self.dragging = false end
    end
end

----------------------------------------------------------------- frame
local function button(parent, text, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText("") b.label = text
    b.Paint = function(s, w, h)
        surface.SetDrawColor(s:IsHovered() and COL.line or COL.panel) surface.DrawRect(0, 0, w, h)
        draw.SimpleText(isfunction(s.label) and s.label() or s.label, "ZCKC.Body", w / 2, h / 2, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = fn
    return b
end

local notes
local function open(target)
    if IsValid(frame) then frame:Remove() end
    state = nil
    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(ScrW() * 0.9, 1500), math.min(ScrH() * 0.88, 900))
    frame:Center() frame:SetTitle("") frame:MakePopup() frame:SetDraggable(true)
    frame.Paint = function(_, w, h)
        surface.SetDrawColor(COL.bg) surface.DrawRect(0, 0, w, h)
        draw.SimpleText("Incident records", "ZCKC.Head", 14, 6, COL.text)
        if frame.note then draw.SimpleText(frame.note, "ZCKC.Body", 200, 8, COL.bad) end
    end
    frame.OnRemove = function() state = nil end

    local side = vgui.Create("DPanel", frame) side:Dock(LEFT) side:SetWide(250) side:DockMargin(0, 6, 6, 0) side.Paint = nil
    local tabs = vgui.Create("DPanel", side) tabs:Dock(TOP) tabs:SetTall(28) tabs:DockMargin(0, 0, 0, 6) tabs.Paint = nil
    -- The server decides what each tab may list: "All" answers admins only, "Submitted" operators and up.
    for _, tab in ipairs({{"Mine", ""}, {"Submitted", "submitted"}, {"All", "all"}}) do
        local b = button(tabs, tab[1], function() frame.scope = tab[2] ask("zckc_index", tab[2]) end)
        b:Dock(LEFT) b:SetWide(80) b:DockMargin(0, 0, 5, 0)
    end
    local left = vgui.Create("DScrollPanel", side) left:Dock(FILL)
    local right = vgui.Create("DPanel", frame) right:Dock(RIGHT) right:SetWide(330) right:DockMargin(6, 6, 0, 0) right.Paint = nil
]========], 2)
