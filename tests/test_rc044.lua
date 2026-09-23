-- Execute production modules; Java/engine interfaces below are test doubles.
local script = debug.getinfo(1, "S").source:sub(2)
local tests = script:match("^(.*)/[^/]+$") or "."
local root = tests .. "/../workshop/Contents/mods/SurvivorsSong/42.20/media/lua/"
local function source(name)
    return root .. (name:find("_client",1,true) and "client" or "shared") .. "/survivorssong/" .. name
end
local passed = 0
local function eq(a,b) assert(a==b, tostring(a).." ~= "..tostring(b)) end
local function close(a,b) assert(math.abs(a-b)<1e-8, tostring(a).." ~= "..tostring(b)) end
local function test(name, fn) fn(); passed=passed+1; print("PASS "..name) end
local function copy(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local engine={server=false,client=false,now=1000,multiplier=1,ratio=100,enabled=true}
local function event() local e={callbacks={}}; e.Add=function(f) e.callbacks[#e.callbacks+1]=f end; return e end
Events={OnTick=event(),OnPlayerUpdate=event(),OnClientCommand=event(),OnServerCommand=event(),OnDisconnect=event(),OnFillInventoryObjectContextMenu=event()}
local function emit(name,...) for _,f in ipairs(Events[name].callbacks) do f(...) end end
function isServer() return engine.server end
function isClient() return engine.client end
function getTimestampMs() return engine.now end
function instanceof(item,kind) return item and (kind=="InventoryItem" and item.item or kind==item.class) or false end
function getText(key,...) return key..table.concat({...}," ") end
function getGameTime() return {
 getMultiplier=function() return engine.multiplier end,getMinutesPerDay=function() return 30 end,
 getTimeOfDay=function() return 12.5 end,getYear=function() return 1993 end,
 getMonth=function() return 6 end,getDay=function() return 14 end,
 getMinutesStamp=function() return engine.now/1000 end} end
function getSandboxOptions() return {getOptionByName=function(_,name) return {getValue=function()
 if name=="SurvivorsSong.RecoveryPercent" then return engine.ratio end
 if name=="SurvivorsSong.SkillXP" then return engine.enabled end
 if name=="MinutesPerPage" then return 2 end
 return nil end} end} end
UIManager={getProgressBar=function() return {setValue=function() end} end}
ISTimedActionQueue={isPlayerDoingAction=function() return false end,add=function() error('unexpected foreground action') end}
ISReadABook={getDuration=function(view) engine.nativeDurationCalls=(engine.nativeDurationCalls or 0)+1;return view.item:getNumberOfPages()*view.minutesPerPage*60 end}
ISInventoryPane={refreshContainer=function() end,drawItemIcon=function() end}
ISInventoryPaneContextMenu={}
ISToolTipInv={render=function() end}
ISRadioAction={performTogglePlayMedia=function() end}
local function noop() end
RWMMedia={verifyItem=noop,addMediaAux=noop,removeMedia=noop,update=noop,getAPrompt=noop,
 togglePlayMedia=function() engine.nativePlay=(engine.nativePlay or 0)+1 end}
local originalRequire=require
function require(name)
 if name=="survivorssong/survivorssong_shared" then return SurvivorsSong end
 if name=="survivorssong/survivorssong_progress" then return true end
 if name=="survivorssong/survivorssong_actions" then return true end
 if name:match('^ISUI/') or name:match('^TimedActions/') or name:match('^RadioCom/') then return true end
 return originalRequire(name)
end
local perks={}
for i,name in ipairs({'Carpentry','Cooking','Fitness','NewPerk'}) do
 perks[i]={id=name,getId=function(self) return self.id end}
end
PerkFactory={Perks={None={},getMaxIndex=function() return #perks end,
 fromIndex=function(i) return perks[i+1] end,
 FromString=function(name) for _,p in ipairs(perks) do if p.id==name then return p end end end},
 getPerk=function() return {getTotalXpForLevel=function(_,n) return n*100 end} end}
local serial=0
local function player(name,user,skills)
 serial=serial+1
 local p={name=name or 'Alice',user=user or 'account',skills=copy(skills or {}),id=serial,items={},mic=true,dead=false}
 local inv={}
 function inv:getItemWithIDRecursiv(id) return p.items[id] end
 function inv:containsTypeRecurse() return p.mic end
 function inv:getItems() return {size=function() return 0 end} end
 function inv:setDrawDirty() end
 function p:getInventory() return inv end
 function p:getUsername() return self.user end
 function p:getDescriptor() return {getForename=function() return self.name end,getSurname=function() return '' end,getID=function() return self.id end} end
 function p:getXp() return {getXP=function(_,perk) engine.xpReads=(engine.xpReads or 0)+1;return p.skills[perk.id] or 0 end} end
 function p:getPerkLevel(perk) return self.levels and self.levels[perk.id] or 0 end
 function p:getPrimaryHandItem() return self.hand end
 function p:getSecondaryHandItem() return nil end
 function p:isAttachedItem(d) return d.attached end
 function p:isDead() return self.dead end
 function p:isLocalPlayer() return true end
 function p:isTimedActionInstant() return false end
 function p:getPlayerNum() return 0 end
 function p:getOnlineID() return self.id end
 return p
end
local function device(p,mode,saved,author,user)
 serial=serial+1
 local d={item=true,class='Radio',id=serial,on=true,power=1,headphones=0,attached=false,
 md={SS_loadedMode=mode or 'blank',SS_loadedVersion=2}}
 function d:getFullType() return 'Base.CDplayer' end
 function d:getID() return self.id end
 function d:getModData() return self.md end
 function d:getContainer() return p:getInventory() end
 function d:getAttachedSlot() return self.attached and 1 or -1 end
 function d:setJobDelta(x) self.progress=x end
 function d:setJobType(x) self.job=x end
 function d:syncItemFields() end
 local data={}
 function data:hasMedia() return d.media~=false end
 function data:getMediaType() return 0 end
 function data:getHeadphoneType() return d.headphones end
 function data:getIsBatteryPowered() return true end
 function data:getHasBattery() return true end
 function data:getPower() return d.power end
 function data:getIsTurnedOn() return d.on end
 function data:isPlayingMedia() return false end
 function d:getDeviceData() return data end
 if mode=='song' then
  d.md.SS_loadedSkills=SurvivorsSong.encodeSkills(saved or {})
  d.md.SS_loadedAuthorName=author or p.name;d.md.SS_loadedAuthorUser=user==nil and p.user or user
  d.md.SS_loadedRecordedAt='old'
 end
 p.items[d.id]=d;p.hand=d;return d
end
function addXpNoMultiplier(p,perk,amount) p.skills[perk.id]=(p.skills[perk.id] or 0)+amount;engine.xpAdds=(engine.xpAdds or 0)+1 end
function sendServerCommand(p,module,command,args) engine.lastPacket=args end
function sendClientCommand(p,module,command,args) engine.lastRequest=args end
function getOnlinePlayers() return {size=function() return #(engine.players or {}) end,get=function(_,i) return engine.players[i+1] end} end
function getPlayerByOnlineID(id) for _,p in ipairs(engine.players or {}) do if p.id==id then return p end end end
dofile(source('survivorssong_shared.lua'));local SS=SurvivorsSong
SS._activeMediaActions={}
dofile(source('survivorssong_progress.lua'))
dofile(source('survivorssong_client.lua'))
local nativeCapture=SS.captureSkills
local captures=0
SS.captureSkills=function(...) captures=captures+1;return nativeCapture(...) end
local function finish(d)
 local s=SS.getKnowledgeSession(d);assert(s,'no session')
 engine.multiplier=s.duration-s.elapsed;engine.now=engine.now+500;emit('OnTick');engine.multiplier=1
end
local function stop(p,d) SS.stopKnowledgeSession(p,d) end
local function record(p,d) assert(SS.startKnowledgeSession(p,d,'record'));finish(d) end
local function window(p,d)
 return setmetatable({player=p,device=d,deviceData=d:getDeviceData(),textPlay='Play',textStop='Stop',idleText='idle',
 itemDropBox={setStoredItemFake=noop},lcd={setText=noop,setDoScroll=noop},
 toggleOnOffButton={setEnable=function(self,v) self.enabled=v end,setTitle=noop},doWalkTo=function() return true end},{__index=RWMMedia})
end

test('version and schema',function() eq(SS.BUILD,'rc0.4.4');eq(SS.VERSION,2);eq(SS.ACTION_PROGRESS_MODEL_VERSION,1) end)
test('native capture uses level floor',function() local p=player(nil,nil,{Carpentry=5});p.levels={Carpentry=2};eq(SS.captureSkills(p).Carpentry,200) end)
test('fresh recording and update same disc',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);record(p,d);p.skills.Carpentry=140;record(p,d);eq(SS.getLoadedSkills(d).Carpentry,140) end)
test('snapshot does not pay for later XP',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));p.skills.Carpentry=1000;p.skills.Cooking=200;finish(d);eq(SS.getLoadedSkills(d).Carpentry,100);eq(SS.getLoadedSkills(d).Cooking,nil);eq(SS.getRecordDelta(p,d).skills,2) end)
test('second update captures deferred XP',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));p.skills.Carpentry=500;finish(d);record(p,d);eq(SS.getLoadedSkills(d).Carpentry,500) end)
test('snapshot survives later XP decrease',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));p.skills.Carpentry=10;finish(d);eq(SS.getLoadedSkills(d).Carpentry,100) end)
test('do not downgrade older higher skill',function() local p=player(nil,nil,{Carpentry=10,Cooking=200});local d=device(p,'song',{Carpentry=100,Cooking=50});record(p,d);eq(SS.getLoadedSkills(d).Carpentry,100);eq(SS.getLoadedSkills(d).Cooking,200) end)
test('preserve removed perk in record',function() local p=player(nil,nil,{Carpentry=200});local d=device(p,'song',{RemovedPerk=900,Carpentry=100});record(p,d);eq(SS.getLoadedSkills(d).RemovedPerk,900) end)
test('no-op does not change timestamp',function() local p=player(nil,nil,{Carpentry=100});local d=device(p,'song',{Carpentry=100});eq(SS.startKnowledgeSession(p,d,'record'),false);eq(d.md.SS_loadedRecordedAt,'old') end)
test('no naked record commit',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);eq(SS.commitRecord(p,d),false);eq(SS.getLoadedMode(d),'blank') end)
test('record commit cannot replay',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));local plan=SS.getKnowledgeSession(d).recordPlan;finish(d);eq(SS.commitRecord(p,d,plan),false) end)
test('changed disc baseline rejects',function() local p=player(nil,nil,{Carpentry=200});local d=device(p,'song',{Carpentry=100});assert(SS.startKnowledgeSession(p,d,'record'));d.md.SS_loadedSkills='Carpentry=500';finish(d);eq(SS.getLoadedSkills(d).Carpentry,500);eq(SS.getKnowledgeSession(d),nil) end)
test('other account rejected',function() local p=player('Alice','other',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'Alice','owner');eq(SS.canRecord(p,d),false);eq(SS.canRestore(p,d),false) end)
test('same account renamed character preserves first author',function() local p=player('Bob','owner',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'Alice','owner');record(p,d);eq(d.md.SS_loadedAuthorName,'Alice');eq(d.md.SS_loadedAuthorUser,'owner') end)
test('blank saved username uses matching name',function() local p=player('Alice','account',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'Alice','');eq(SS.canRecord(p,d),true);record(p,d);eq(d.md.SS_loadedAuthorUser,'') end)
test('blank saved username does not allow another name',function() local p=player('Bob','account',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'Alice','');eq(SS.canRecord(p,d),false) end)
test('blank current username uses matching name',function() local p=player('Alice','',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'Alice','owner');eq(SS.canRecord(p,d),true) end)
test('blank current username rejects different name',function() local p=player('Bob','',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'Alice','owner');eq(SS.canRecord(p,d),false) end)
test('unbound unnamed old record fails without mutation',function() local p=player('Bob','',{Carpentry=100});local d=device(p,'song',{Carpentry=50},'','');eq(SS.canRecord(p,d),false);eq(SS.getLoadedSkills(d).Carpentry,50) end)
test('actor change stops background record',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));p.name='Other';finish(d);eq(SS.getLoadedMode(d),'blank');eq(SS.getKnowledgeSession(d),nil) end)
test('codec retains raw precision',function() local x=13800.0004;close(SS.decodeSkills(SS.encodeSkills({Carpentry=x})).Carpentry,x) end)
test('rounding only affects growth comparison',function() local p=player(nil,nil,{Carpentry=100.0004});local d=device(p,'song',{Carpentry=100});eq(SS.getRecordDelta(p,d).skills,0) end)
test('journal 7-page precision boundary',function() local p=player(nil,nil,{Carpentry=13800.0004});local d=device(p,'song',{Carpentry=100});local delta=SS.getRecordDelta(p,d);close(delta.xp,13700.0004);eq(SS.getActionPageCount('record',delta),7) end)
test('invalid numeric CD entries excluded',function() local x=SS.decodeSkills('a=nan;b=inf;c=-1;d=0;e=1.0004');eq(x.a,nil);eq(x.b,nil);eq(x.c,nil);eq(x.d,nil);close(x.e,1.0004) end)
test('restore adds only missing XP without multiplier',function() local p=player(nil,nil,{Carpentry=40});local d=device(p,'song',{Carpentry=100});engine.xpAdds=0;assert(SS.startKnowledgeSession(p,d,'restore'));finish(d);eq(p.skills.Carpentry,100);eq(engine.xpAdds,1);eq(SS.applyRestore(p,d),false);eq(engine.xpAdds,1) end)
test('restore 50 percent no repeated stacking',function() engine.ratio=50;local p=player(nil,nil,{Carpentry=10});local d=device(p,'song',{Carpentry=100});assert(SS.applyRestore(p,d));eq(p.skills.Carpentry,50);eq(SS.applyRestore(p,d),false);engine.ratio=100 end)
test('restore first even with newly gained skill',function() local p=player(nil,nil,{Carpentry=10,Cooking=80});local d=device(p,'song',{Carpentry=100});local k,a=SS.getKnowledgeActionChoice(p,d);eq(k,'restore');eq(a,true);SS.applyRestore(p,d);k,a=SS.getKnowledgeActionChoice(p,d);eq(k,'record');eq(a,true) end)
test('restore does not need microphone',function() local p=player(nil,nil,{Carpentry=10});p.mic=false;local d=device(p,'song',{Carpentry=100});local k,a=SS.getKnowledgeActionChoice(p,d);eq(k,'restore');eq(a,true) end)
test('record needs microphone',function() local p=player(nil,nil,{Carpentry=100});p.mic=false;local d=device(p);eq(SS.startKnowledgeSession(p,d,'record'),false) end)
for _,name in ipairs({'power','on','headphones','placement'}) do
 test('loss of '..name..' stops and keeps page checkpoint',function()
  local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'))
  local s=SS.getKnowledgeSession(d);engine.multiplier=s.duration*0.6;emit('OnTick');engine.multiplier=1
  if name=='power' then d.power=0 elseif name=='on' then d.on=false elseif name=='headphones' then d.headphones=-1 else p.hand=nil end
  emit('OnTick');eq(SS.getKnowledgeSession(d),nil);assert((d.md.SS_progressPage or 0)>0);eq(SS.getLoadedMode(d),'blank')
 end)
end
test('record microphone loss preserves checkpoint',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));local s=SS.getKnowledgeSession(d);engine.multiplier=s.duration/2;emit('OnTick');engine.multiplier=1;p.mic=false;emit('OnTick');eq(SS.getKnowledgeSession(d),nil);assert(d.md.SS_progressPage>0) end)
test('resume after pause recalculates remaining work',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));local s=SS.getKnowledgeSession(d);engine.multiplier=s.duration/2;emit('OnTick');engine.multiplier=1;stop(p,d);local page=d.md.SS_progressPage;p.skills.Cooking=100;assert(SS.startKnowledgeSession(p,d,'record'));eq(SS.getKnowledgeSession(d).startPage,page);finish(d);eq(SS.getLoadedSkills(d).Cooking,100);eq(d.md.SS_progressPage,nil) end)
test('checkpoint copy follows disc into another device',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);SS.saveKnowledgeProgress(d,'record',SS.getActionActorKey(p),2,6);local disc={md={}};function disc:getModData() return self.md end;SS.copyKnowledgeProgress(d,disc);local d2=device(p);SS.copyKnowledgeProgress(disc,d2);eq(SS.getSavedKnowledgePage(d2,'record',SS.getActionActorKey(p),6),2) end)
test('hand to attachment does not cancel',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));p.hand=nil;d.attached=true;emit('OnTick');assert(SS.getKnowledgeSession(d));finish(d);eq(SS.getLoadedMode(d),'song') end)
test('choice captures skills exactly once',function() local p=player(nil,nil,{Carpentry=150});local d=device(p,'song',{Carpentry=100});captures=0;local k,a=SS.getKnowledgeActionChoice(p,d);eq(k,'record');eq(a,true);eq(captures,1) end)
test('no-power choice does not capture',function() local p=player(nil,nil,{Carpentry=150});local d=device(p);d.power=0;captures=0;local k,a=SS.getKnowledgeActionChoice(p,d);eq(a,false);eq(captures,0) end)
test('idle custom never falls through to native playback',function() local p=player(nil,nil,{Carpentry=100});local d=device(p,'song',{Carpentry=100});engine.nativePlay=0;window(p,d):togglePlayMedia();eq(engine.nativePlay,0) end)
test('ordinary CD still uses native playback',function() local p=player();local d=device(p);d.md={};engine.nativePlay=0;window(p,d):togglePlayMedia();eq(engine.nativePlay,1) end)
test('UI update and joypad share 250ms sampled decision',function() local p=player(nil,nil,{Carpentry=150});local d=device(p,'song',{Carpentry=100});local w=window(p,d);captures=0;w:update();w:getAPrompt();w:update();eq(captures,1);engine.now=engine.now+250;w:update();eq(captures,2) end)
test('click revalidates cache after microphone removal',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);local w=window(p,d);w:update();eq(w.toggleOnOffButton.enabled,true);p.mic=false;w:togglePlayMedia();eq(SS.getKnowledgeSession(d),nil) end)
test('skill switch off blocks start',function() engine.enabled=false;local p=player(nil,nil,{Carpentry=100});local d=device(p);eq(SS.startKnowledgeSession(p,d,'record'),false);engine.enabled=true end)
test('second simultaneous device cannot start',function() local p=player(nil,nil,{Carpentry=100});local d=device(p);d.attached=true;assert(SS.startKnowledgeSession(p,d,'record'));local d2=device(p);eq(SS.startKnowledgeSession(p,d2,'record'),false);stop(p,d) end)
test('client cannot commit local XP snapshot',function() engine.client=true;local p=player(nil,nil,{Carpentry=100});local d=device(p);local plan=SS.makeRecordPlan(p,d,SS.getRecordDelta(p,d));eq(SS.commitRecord(p,d,plan),false);eq(SS.startKnowledgeSession(p,d,'record'),false);engine.client=false end)
test('server rebuilds plan ignoring supplied snapshot fields',function() engine.server=true;local p=player(nil,nil,{Carpentry=100});local d=device(p);engine.players={p};emit('OnClientCommand',SS.MODULE,'knowledgeStart',p,{itemId=d.id,kind='record',encoded='Carpentry=999999',duration=1});eq(SS.getKnowledgeSession(d).recordPlan.encoded,'Carpentry=100');finish(d);eq(SS.getLoadedSkills(d).Carpentry,100);engine.server=false end)
test('server disconnect cleans active session',function() engine.server=true;local p=player(nil,nil,{Carpentry=100});local d=device(p);engine.players={p};assert(SS.startKnowledgeSession(p,d,'record'));engine.players={};emit('OnTick');eq(SS.getKnowledgeSession(d),nil);engine.server=false end)
test('native duration delegated for restore',function() local p=player(nil,nil,{Carpentry=10});local d=device(p,'song',{Carpentry=100});engine.nativeDurationCalls=0;SS.getActionTime('restore',p,d);eq(engine.nativeDurationCalls,1) end)
print('TOTAL '..passed..' PASS; production modules with engine stubs, not game validation')
