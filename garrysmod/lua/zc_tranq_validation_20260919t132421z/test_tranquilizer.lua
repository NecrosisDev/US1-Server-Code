-- Isolated method fixtures only. No live weapon or player actions.
return function(original,candidate,compiler)
local results={};local metrics={}
local function test(name,f)local ok,err=pcall(f);results[#results+1]={name=name,pass=ok,error=not ok and tostring(err) or nil}end
local function env(code,automatic)
 local e=setmetatable({SERVER=true,CLIENT=false,time=10,lookups=0,shots=0,posts=0,dry=0,allowed=true,usable=true},{__index=_G})
 e._G=e;e.CurTime=function()return e.time end
 e.owner={npc=false};function e.owner:IsNPC()return self.npc end
 e.LocalPlayer=function()return e.owner end
 e.weapons_Get=function(class)e.lookups=e.lookups+1;assert(class=='weapon_tranquilizer');return {Primary={Automatic=automatic}}end
 local w={Primary={Wait=.2,Next=0},drawBullet=true,clip=200};e.SWEP=w
 function w:GetOwner()return e.owner end;function w:GetClass()return 'weapon_tranquilizer'end
 function w:Clip1()return self.clip end;function w:CanPrimaryAttack()return e.allowed end
 function w:CanUse()return e.usable end
 function w:PrimaryShoot()e.shots=e.shots+1;self.clip=self.clip-1 end
 function w:PrimaryShootPost()e.posts=e.posts+1 end
 function w:PrimaryShootEmpty()e.dry=e.dry+1 end
 local f,err=compiler(code,'tranquilizer_fixture');assert(type(f)=='function',tostring(err or f));setfenv(f,e);f()
 return e,w
end
for _,automatic in ipairs({false,true}) do
 test('100 shots preserve count and timing; automatic='..tostring(automatic),function()
  local a,w=env(original,automatic);local b,x=env(candidate,automatic)
  for i=1,100 do a.time=i;b.time=i;w:Shoot();x:Shoot()end
  assert(a.shots==100 and b.shots==100 and a.posts==b.posts and w.clip==x.clip and w.Primary.Next==x.Primary.Next)
  assert(x.Primary.Automatic==automatic and b.lookups==1)
  if not automatic then metrics={originalLookups=a.lookups,candidateLookups=b.lookups,shots=100} end
 end)
end
for _,cached in ipairs({false,true}) do
 test('explicit cached value honored; '..tostring(cached),function()
  local e,w=env(candidate,not cached);w.Primary.RealAutomatic=cached;w:Shoot()
  assert(e.lookups==0 and w.Primary.Automatic==cached and e.shots==1)
 end)
end
for _,gate in ipairs({'allowed','usable','Next','NextFire','empty','undrawn','remoteClient'}) do
 test('native rejection preserved: '..gate,function()
  for _,source in ipairs({original,candidate}) do
   local e,w=env(source,false)
   if gate=='allowed' or gate=='usable' then e[gate]=false
   elseif gate=='Next' or gate=='NextFire' then w.Primary[gate]=20
   elseif gate=='empty' then w.clip=0
   elseif gate=='undrawn' then w.drawBullet=false
   else e.CLIENT=true;e.LocalPlayer=function()return {}end end
   assert(w:Shoot()==false and e.lookups==0 and e.shots==0 and e.posts==0)
   assert(e.dry==((gate=='empty' or gate=='undrawn') and 1 or 0))
  end
 end)
end
test('explicit override preserves empty-shot and cooldown behavior',function()
 for _,source in ipairs({original,candidate}) do
  local e,w=env(source,false);w.clip=0;w.drawBullet=false;w:Shoot(true)
  assert(e.shots==1 and e.dry==0);e.time=10.01;assert(w:Shoot(true)==false and e.shots==1)
 end
end)
test('dry-fire does not overwrite cached semiautomatic mode',function()
 local e,w=env(candidate,false);w:Shoot();w.clip=0;e.time=11;w:Shoot();w.clip=3;e.time=12;w:Shoot()
 assert(e.lookups==1 and e.shots==2 and e.dry==1 and w.Primary.Automatic==false)
end)
test('NPC draw and timing exceptions preserved',function()
 for _,source in ipairs({original,candidate}) do
  local e,w=env(source,false);e.owner.npc=true;w.drawBullet=false;w.Primary.Next=999;w.Primary.NextFire=999
  w:Shoot();assert(e.shots==1 and e.dry==0 and w.Primary.Next==10.2)
 end
end)
test('explicit nil invalidation re-resolves the inherited definition',function()
 local e,w=env(candidate,false);w:Shoot();w.Primary.RealAutomatic=nil;e.time=11
 e.weapons_Get=function()e.lookups=e.lookups+1;return {Primary={Automatic=true}}end
 w:Shoot();assert(e.lookups==2 and w.Primary.Automatic==true)
end)
test('local client still predicts the same shot',function()
 local e,w=env(candidate,false);e.CLIENT=true;e.SERVER=false;w:Shoot()
 assert(e.shots==1 and e.posts==1 and e.lookups==1)
end)
return results,metrics
end
