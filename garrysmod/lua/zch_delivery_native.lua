local r={time=os.time(),compile={},models={}}
r.compile["zch_delivery_compile_0.txt"]=type(CompileString(file.Read("zch_delivery_compile_0.txt","DATA"),"zch_delivery_compile_0.txt",false))=="function"
r.compile["zch_delivery_compile_1.txt"]=type(CompileString(file.Read("zch_delivery_compile_1.txt","DATA"),"zch_delivery_compile_1.txt",false))=="function"
r.compile["zch_delivery_compile_2.txt"]=type(CompileString(file.Read("zch_delivery_compile_2.txt","DATA"),"zch_delivery_compile_2.txt",false))=="function"
r.compile["zch_delivery_compile_3.txt"]=type(CompileString(file.Read("zch_delivery_compile_3.txt","DATA"),"zch_delivery_compile_3.txt",false))=="function"
r.compile["zch_delivery_compile_4.txt"]=type(CompileString(file.Read("zch_delivery_compile_4.txt","DATA"),"zch_delivery_compile_4.txt",false))=="function"
r.compile["zch_delivery_compile_5.txt"]=type(CompileString(file.Read("zch_delivery_compile_5.txt","DATA"),"zch_delivery_compile_5.txt",false))=="function"
for _,gender in ipairs({"male","female"}) do
 local e=ents.Create("base_anim")
 e:SetModel("models/zcity_hostage/hostage_embedded_"..gender..".mdl")
 local id,d=e:LookupSequence("zch_idle_standing")
 r.models[gender]={id=id,duration=d,count=e:GetSequenceCount(),pass=id>=0 and d>0 and e:GetSequenceCount()>=84}
 e:Remove()
end
file.Write("zch_delivery_native.json",util.TableToJSON(r,true))
print("ZCH_DELIVERY_NATIVE",util.TableToJSON(r))
