-- Retains all 49 rc0.4.4 behavioral cases; schema expectation and engine stubs
-- are extended for the full-knowledge candidate. Additional cases follow.
-- Execute production modules; Java/engine interfaces below are test doubles.
local script = debug.getinfo(1, "S").source:sub(2)
local tests = script:match("^(.*)/[^/]+$") or "."
local root = tests .. "/../workshop/Contents/mods/SurvivorsSong/42.20/media/lua/"
package.path = root .. "shared/?.lua;" .. package.path
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
 if engine.options and engine.options[name] ~= nil then return engine.options[name] end
 if name=="SurvivorsSong.RecoveryPercent" then return engine.ratio end
 if name=="SurvivorsSong.SkillXP" then return engine.enabled end
 if name=="MinutesPerPage" then return 2 end
 return nil end} end} end
UIManager={getProgressBar=function() return {setValue=function() end} end}
ISTimedActionQueue={isPlayerDoingAction=function() return false end,add=function() error('unexpected foreground action') end}
function getCore() return {getVersionNumber=function()return "42.20.4" end} end
ISReadABook={complete=function()return true end,getDuration=function(view) engine.nativeDurationCalls=(engine.nativeDurationCalls or 0)+1;return view.item:getNumberOfPages()*view.minutesPerPage*60 end}
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
 local p={name=name or 'Alice',user=user or 'account',skills=copy(skills or {}),id=serial,items={},mic=true,dead=false,recipes={},pages={},multipliers={},media={}}
 local inv={}
 function inv:getItemWithIDRecursiv(id) return p.items[id] end
 function inv:containsTypeRecurse() return p.mic end
 function inv:getItems() return {size=function() return 0 end} end
 function inv:setDrawDirty() end
 function p:getInventory() return inv end
 function p:getUsername() return self.user end
 function p:getDescriptor() return {getForename=function() return self.name end,getSurname=function() return '' end,getID=function() return self.id end} end
 function p:getXp() return {getXP=function(_,perk) engine.xpReads=(engine.xpReads or 0)+1;return p.skills[perk.id] or 0 end,getMultiplier=function(_,perk) return p.multipliers[perk.id] or 0 end} end
 function p:getKnownRecipes() local values={} for r in pairs(self.recipes) do values[#values+1]=r end;return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
 function p:learnRecipe(r) self.recipes[r]=true end
 function p:getAlreadyReadPages(t) return self.pages[t] or 0 end
 function p:setAlreadyReadPages(t,v) self.pages[t]=v end
 function p:isKnownMediaLine(g) return self.media[g]==true end
 function p:addKnownMediaLine(g) self.media[g]=true end
 function p:hasTrait() return false end
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
function sendServerCommand(p,module,command,args) engine.lastPacket=args;engine.packets=engine.packets or {};engine.packets[#engine.packets+1]={p=p,module=module,command=command,args=args} end
function sendClientCommand(p,module,command,args) engine.lastRequest=args;engine.requestCommand=command end
function getOnlinePlayers() return {size=function() return #(engine.players or {}) end,get=function(_,i) return engine.players[i+1] end} end
function getPlayerByOnlineID(id) for _,p in ipairs(engine.players or {}) do if p.id==id then return p end end end
SkillBook={}
CharacterTrait={ILLITERATE="illiterate"}
function getScriptManager() return {getAllItems=function() return {size=function()return 0 end} end,FindItem=function() return nil end} end
function addXpMultiplier(p,perk,value,min,max) p.multipliers[perk.id]=value;p.lastRange={min,max};engine.multiplierAdds=(engine.multiplierAdds or 0)+1 end
function sendSyncPlayerFields(p,mask) engine.syncMask=mask end
-- Simulate PZ discovery before shared.lua, including require() returning a
-- cache sentinel instead of the factory return value.
dofile(source('journal_core.lua'))
dofile(source('journal_sync.lua'))
dofile(source('knowledge.lua'))
assert(SurvivorsSong.Knowledge==nil)
package.loaded['survivorssong/journal_core']=true
package.loaded['survivorssong/journal_sync']=true
package.loaded['survivorssong/knowledge']=true
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

test('version and schema',function() eq(SS.BUILD,'rc0.4.5');eq(SS.VERSION,3);eq(SS.ACTION_PROGRESS_MODEL_VERSION,1) end)
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


local book={}
function book:getFullName() return 'Base.BookCarpentry1' end
function book:getSkillTrained() return 'Carpentry' end
function book:getNumberOfPages() return 220 end
function book:getLevelSkillTrained() return 1 end
function book:getMaxLevelTrained() return 2 end
SkillBook.Carpentry={perk=perks[1],maxMultiplier1=3,maxMultiplier2=5,maxMultiplier3=8,maxMultiplier4=12,maxMultiplier5=16}
function getScriptManager() return {getAllItems=function() return {size=function()return 1 end,get=function()return book end} end,FindItem=function(_,t)if t=='Base.BookCarpentry1' then return book end end} end
local function media(id,codes)
 local m={id=id}
 function m:getId()return self.id end
 function m:getMediaType()return 0 end
 function m:getIndex()return 12 end
 function m:getIndexForLua()return 12 end
 function m:getLineCount()return 2 end
 function m:getLine(i)return {getTextGuid=function()return id..':'..i end,getCodes=function()return i==0 and codes or '' end}end
 return m
end
local training=media('training','CRP=1'),entertainment
entertainment=media('fun','BOR=-5')
function getZomboidRadio()return {getRecordedMedia=function()return {
 getAllMediaForType=function(_,t)local a=t==0 and {training,entertainment} or {};return {size=function()return #a end,get=function(_,i)return a[i+1]end}end,
 getAllMediaForCategory=function()return {size=function()return 1 end,get=function()return training end}end,
}end}end
SS.Knowledge._permanentRewardMedia=nil
local function fullSong(p, payload)
 local d=device(p,'song',{},p.name,p.user)
 d.md.SS_loadedVersion=3;d.md.SS_loadedKnowledgeVersion=6
 for k,v in pairs(payload or {}) do d.md['SS_loaded'..k]=v end
 return d
end
local function physical(md)
 local d={item=true,class='InventoryItem',md=md or {},name='Disc',id=9990}
 function d:getFullType()return 'Base.Disc_Retail'end
 function d:getModData()return self.md end
 function d:isRecordedMedia()return self.recorded==true end
 function d:getMediaType()return 0 end
 function d:getRecordedMediaIndex()return self.recorded and 12 or -1 end
 function d:getName()return self.name end
 function d:setName(n)self.name=n end
 function d:isCustomName()return self.customName==true end
 function d:setCustomName(v)self.customName=v end
 function d:getID()return self.id end
 function d:getScriptItem()return {getRecordedMediaCat=function()return 'CDs'end}end
 function d:setRecordedMediaData(_)self.recorded=true end
 function d:getContainer()return self.container end
 return d
end
function instanceItem(t)eq(t,'Base.Disc_Retail');serial=serial+1;local d=physical();d.id=serial;return d end

test('knowledge-only recording works when SkillXP is off',function()
 engine.enabled=false;local p=player();p.recipes.Soup=true;local d=device(p);record(p,d)
 eq(d.md.SS_loadedRecipes,'Soup');eq(d.md.SS_loadedSkills,'');eq(d.md.SS_loadedKnowledgeVersion,6)
 p.recipes={};assert(SS.canRestore(p,d));assert(SS.applyRestore(p,d));eq(p.recipes.Soup,true);engine.enabled=true
end)
test('all four knowledge paths record and restore through session',function()
 local p=player(nil,nil,{Carpentry=50});p.recipes.Soup=true;p.pages['Base.BookCarpentry1']=110;p.multipliers.Carpentry=1.5;p.media['training:0']=true;p.media['fun:0']=true
 local d=device(p);record(p,d);eq(d.md.SS_loadedMediaRewards,'training=1');assert(d.md.SS_loadedSkillBookStates~='')
 p.skills.Carpentry=50;p.recipes={};p.pages={};p.multipliers={};p.media={};local delta=SS.getRestoreDelta(p,d)
 eq(delta.skills,0);eq(delta.recipes,1);eq(delta.books,1);eq(delta.vhs,2);assert(SS.startKnowledgeSession(p,d,'restore'));finish(d)
 eq(p.recipes.Soup,true);eq(p.pages['Base.BookCarpentry1'],110);eq(p.multipliers.Carpentry,1.5);eq(p.media['training:0'],true);eq(p.media['training:1'],true);eq(p.media['fun:0'],nil)
 eq(SS.canRestore(p,d),false);eq(SS.applyRestore(p,d),false)
end)
test('recipe-only full-XP restore completes instead of false empty completion',function()
 local p=player(nil,nil,{Carpentry=100});local d=fullSong(p,{Skills='Carpentry=100',Recipes='Soup'})
 assert(SS.startKnowledgeSession(p,d,'restore'));finish(d);eq(p.recipes.Soup,true);eq(SS.getKnowledgeSession(d),nil)
end)
test('whole record snapshot freezes recipes pages multipliers and media',function()
 local p=player();p.recipes.Soup=true;p.pages['Base.BookCarpentry1']=110;p.multipliers.Carpentry=1.5;p.media['training:0']=true
 local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));p.recipes.Salad=true;p.pages['Base.BookCarpentry1']=220;p.multipliers.Carpentry=3;p.media={};finish(d)
 eq(d.md.SS_loadedRecipes,'Soup');eq(d.md.SS_loadedSkillBooks,'Base.BookCarpentry1=110');eq(SS.Knowledge.decodeSkillBookStates(d.md.SS_loadedSkillBookStates)['Base.BookCarpentry1'].multiplier,1.5);eq(d.md.SS_loadedMediaRewards,'training=1')
end)
test('existing higher pages and multipliers never decrease on restore',function()
 local p=player();p.pages['Base.BookCarpentry1']=220;p.multipliers.Carpentry=3
 local states=SS.Knowledge.encodeSkillBookStates({['Base.BookCarpentry1']={fullType='Base.BookCarpentry1',perkId='Carpentry',multiplier=1.5,minLevel=1,maxLevel=2}})
 local d=fullSong(p,{Recipes='Soup',SkillBooks='Base.BookCarpentry1=110',SkillBookStates=states});assert(SS.applyRestore(p,d));eq(p.pages['Base.BookCarpentry1'],220);eq(p.multipliers.Carpentry,3)
end)
test('same pages missing multiplier uses Journal authoritative repair',function()
 local p=player();p.pages['Base.BookCarpentry1']=220
 local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220'})
 eq(SS.getRestoreDelta(p,d).multiplierRepair,true);assert(SS.canRestore(p,d));assert(SS.applyRestore(p,d));eq(p.multipliers.Carpentry,3);eq(SS.canRestore(p,d),false)
end)
test('exact empty multiplier is not invented from pages',function()
 local p=player();local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220',SkillBookStates=''})
 assert(SS.applyRestore(p,d));eq(p.pages['Base.BookCarpentry1'],220);eq(p.multipliers.Carpentry,nil)
end)
test('v2 listening neither fabricates fields nor rewrites schema',function()
 local p=player(nil,nil,{Carpentry=10});local d=device(p,'song',{Carpentry=100});d.md.SS_loadedRecipes='ForgedNewField'
 assert(SS.applyRestore(p,d));eq(p.skills.Carpentry,100);eq(p.recipes.ForgedNewField,nil);eq(d.md.SS_loadedVersion,2);eq(d.md.SS_loadedKnowledgeVersion,nil);eq(d.md.SS_loadedSkillBooks,nil)
end)
test('v2 update migrates with only actually captured knowledge',function()
 local p=player(nil,nil,{Carpentry=200});p.recipes.Soup=true;local d=device(p,'song',{Carpentry=100});record(p,d)
 eq(d.md.SS_loadedVersion,3);eq(d.md.SS_loadedKnowledgeVersion,6);eq(d.md.SS_loadedRecipes,'Soup');eq(d.md.SS_loadedSkillBooks,'');eq(d.md.SS_loadedMediaRewards,'')
end)
test('recipe-only physical CD stays a song',function()
 local disc=physical({SS_version=3,SS_knowledgeVersion=6,SS_skills='',SS_recipes='Soup',SS_authorName='Alice',SS_authorUser='account'})
 eq(SS.isKnowledgeCD(disc),true);eq(SS.isBlankCD(disc),false)
end)
test('unknown future malformed and versionless knowledge are never blank',function()
 for _,v in ipairs({4,'3.0',0}) do local disc=physical({SS_version=v,SS_skills='Carpentry=100'});eq(SS.isKnowledgeCD(disc),false);eq(SS.isBlankCD(disc),false) end
 local disc=physical({SS_recipes='Soup'});eq(SS.isBlankCD(disc),false);eq(SS.isKnowledgeCD(disc),false)
end)
test('full payload and nil state survive physical loaded physical map',function()
 for _,state in ipairs({'nil',''}) do
  local original={SS_version=3,SS_knowledgeVersion=6,SS_skills='Carpentry=100',SS_recipes='Soup',SS_skillBooks='Base.BookCarpentry1=110',SS_mediaRewards='training=1',SS_mediaRewardMode='whole-media',SS_authorName='Alice',SS_authorUser='account',SS_authorDescId='id',SS_recordedAt='date'}
  if state~='nil' then original.SS_skillBookStates=state end
  local loaded,again={},{};SS.copyKnowledgePayload(original,loaded,false,true);SS.copyKnowledgePayload(loaded,again,true,false)
  for k,v in pairs(original) do eq(again[k],v) end;eq(again.SS_skillBookStates,original.SS_skillBookStates)
 end
end)
test('eject preserves original v2 schema and full v3 data',function()
 local p=player();local d=device(p,'song',{Carpentry=100});local disc=SS.makeEjectedCD(d);eq(disc.md.SS_version,2);eq(disc.md.SS_knowledgeVersion,nil)
 d=fullSong(p,{Recipes='Soup',SkillBooks='Base.BookCarpentry1=110',SkillBookStates='',MediaRewards='training=1',MediaRewardMode='whole-media',AuthorDescId='id'});SS.saveKnowledgeProgress(d,'restore',SS.getActionActorKey(p),2,7);disc=SS.makeEjectedCD(d)
 eq(disc.md.SS_recipes,'Soup');eq(disc.md.SS_skillBookStates,'');eq(disc.md.SS_mediaRewards,'training=1');eq(disc.md.SS_authorDescId,'id');eq(disc.md.SS_progressPage,2)
end)
test('erase clears every knowledge field',function()
 local p=player();local d=fullSong(p,{Recipes='Soup',SkillBooks='Base.BookCarpentry1=110',SkillBookStates='',MediaRewards='training=1',MediaRewardMode='whole-media',AuthorDescId='id'});SS.setBlankLoaded(d)
 eq(d.md.SS_loadedMode,'blank');eq(d.md.SS_loadedRecipes,nil);eq(d.md.SS_loadedSkillBooks,nil);eq(d.md.SS_loadedSkillBookStates,nil);eq(d.md.SS_loadedMediaRewards,nil);eq(d.md.SS_loadedMediaRewardMode,nil);eq(d.md.SS_loadedAuthorDescId,nil);eq(d.md.SS_loadedKnowledgeVersion,nil)
end)
for _,field in ipairs({'Recipes','SkillBooks','SkillBookStates','MediaRewards','MediaRewardMode','KnowledgeVersion','AuthorDescId'}) do
 test('record plan rejects changed '..field,function()
  local p=player();p.recipes.Soup=true;local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'));d.md['SS_loaded'..field]='changed';finish(d);eq(d.md.SS_loadedMode,'blank');eq(SS.getKnowledgeSession(d),nil)
 end)
end
test('restore plan rejects payload substitution before result',function()
 local p=player();local d=fullSong(p,{Recipes='Soup'});assert(SS.startKnowledgeSession(p,d,'restore'));d.md.SS_loadedRecipes='Salad';finish(d);eq(p.recipes.Soup,nil);eq(p.recipes.Salad,nil)
end)
test('partial recipes learned during restore finish in the same session',function()
 local p=player();local d=fullSong(p,{Recipes=SS.Knowledge.encodeRecipes({Soup=true,Salad=true})})
 assert(SS.startKnowledgeSession(p,d,'restore'));p.recipes.Soup=true;p.recipes.NewRecipe=true;finish(d)
 eq(p.recipes.Soup,true);eq(p.recipes.Salad,true);eq(p.recipes.NewRecipe,true);eq(SS.getKnowledgeSession(d),nil);eq(d.md.SS_progressPage,nil)
 eq(SS.applyRestore(p,d),false)
end)
test('partial XP growth restores only the remaining fixed target',function()
 local p=player(nil,nil,{Carpentry=10});local d=fullSong(p,{Skills='Carpentry=100;Cooking=50'})
 assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d)
 p.skills.Carpentry=70;p.skills.NewPerk=200;engine.xpAdds=0;finish(d)
 eq(session.terminalPhase,'complete');eq(p.skills.Carpentry,100);eq(p.skills.Cooking,50);eq(p.skills.NewPerk,200);eq(engine.xpAdds,2)
 eq(SS.applyRestore(p,d),false);eq(SS.startKnowledgeSession(p,d,'restore'),false);emit('OnTick');eq(engine.xpAdds,2)
end)
test('XP grown above target never decreases while other gaps recover',function()
 local p=player();local d=fullSong(p,{Skills='Carpentry=100;Cooking=50',Recipes='Soup'})
 assert(SS.startKnowledgeSession(p,d,'restore'));p.skills.Carpentry=180;engine.xpAdds=0;finish(d)
 eq(p.skills.Carpentry,180);eq(p.skills.Cooking,50);eq(p.recipes.Soup,true);eq(engine.xpAdds,1)
end)
test('partial book pages and multiplier growth finish remaining knowledge',function()
 local p=player();local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220',Recipes='Soup'})
 assert(SS.startKnowledgeSession(p,d,'restore'));p.pages['Base.BookCarpentry1']=110;p.multipliers.Carpentry=1.5
 p.pages['Base.NewBook']=80;finish(d)
 eq(p.pages['Base.BookCarpentry1'],220);eq(p.multipliers.Carpentry,3);eq(p.pages['Base.NewBook'],80);eq(p.recipes.Soup,true);eq(SS.canRestore(p,d),false)
end)
test('higher book pages and multiplier gained in flight are preserved',function()
 local p=player();local states=SS.Knowledge.encodeSkillBookStates({['Base.BookCarpentry1']={fullType='Base.BookCarpentry1',perkId='Carpentry',multiplier=1.5,minLevel=1,maxLevel=2}})
 local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=110',SkillBookStates=states,Recipes='Soup'})
 assert(SS.startKnowledgeSession(p,d,'restore'));p.pages['Base.BookCarpentry1']=300;p.multipliers.Carpentry=5;engine.multiplierAdds=0;finish(d)
 eq(p.pages['Base.BookCarpentry1'],300);eq(p.multipliers.Carpentry,5);eq(engine.multiplierAdds,0);eq(p.recipes.Soup,true)
end)
test('partial media knowledge learned in flight fills only missing lines',function()
 local p=player();local d=fullSong(p,{MediaRewards='training=1',MediaRewardMode='whole-media'})
 assert(SS.startKnowledgeSession(p,d,'restore'));p.media['training:0']=true;p.media['new:0']=true;finish(d)
 eq(p.media['training:0'],true);eq(p.media['training:1'],true);eq(p.media['new:0'],true);eq(SS.canRestore(p,d),false)
end)
test('all target knowledge satisfied in flight completes without reward replay',function()
 local p=player();local d=fullSong(p,{Skills='Carpentry=100',Recipes='Soup',SkillBooks='Base.BookCarpentry1=220',MediaRewards='training=1'})
 assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d)
 p.skills.Carpentry=150;p.recipes.Soup=true;p.pages['Base.BookCarpentry1']=250;p.multipliers.Carpentry=5;p.media['training:0']=true;p.media['training:1']=true
 engine.xpAdds=0;engine.multiplierAdds=0;finish(d)
 eq(session.terminalPhase,'complete');eq(SS.getKnowledgeSession(d),nil);eq(d.md.SS_progressPage,nil);eq(engine.xpAdds,0);eq(engine.multiplierAdds,0);eq(p.skills.Carpentry,150);eq(p.multipliers.Carpentry,5)
 eq(SS.startKnowledgeSession(p,d,'restore'),false);eq(SS.applyRestore(p,d),false)
end)
test('restore interruption resumes checkpoint and tolerates later partial growth',function()
 local p=player();local d=fullSong(p,{Skills='Carpentry=6000',Recipes=SS.Knowledge.encodeRecipes({Soup=true,Salad=true})})
 assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d);engine.multiplier=session.duration/2;emit('OnTick');engine.multiplier=1
 stop(p,d);local page=d.md.SS_progressPage;assert(page>0);eq(p.skills.Carpentry,nil)
 assert(SS.startKnowledgeSession(p,d,'restore'));eq(SS.getKnowledgeSession(d).startPage,page);p.skills.Carpentry=2000;p.recipes.Soup=true;finish(d)
 eq(p.skills.Carpentry,6000);eq(p.recipes.Salad,true);eq(d.md.SS_progressPage,nil)
end)
for _,field in ipairs({'Skills','Recipes','SkillBooks','SkillBookStates','MediaRewards','MediaRewardMode','Version','KnowledgeVersion','AuthorName','AuthorUser','AuthorDescId','RecordedAt'}) do
 test('restore rejects in-flight target or identity change '..field,function()
  local p=player();local d=fullSong(p,{Skills='Carpentry=100',Recipes='Soup'});assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d)
  p.skills.Carpentry=100;p.recipes.Soup=true;d.md['SS_loaded'..field]='changed';finish(d)
  assert(session.terminalPhase~='complete');eq(SS.getKnowledgeSession(d),nil)
 end)
end
for _,field in ipairs({'name','user','id'}) do
 test('restore rejects in-flight actor identity change '..field,function()
  local p=player();local d=fullSong(p,{Skills='Carpentry=100'});assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d)
  p[field]=field=='id' and p.id+1 or 'Changed';finish(d);assert(session.terminalPhase~='complete');eq(p.skills.Carpentry,nil)
 end)
end
test('restore rejects replacement physical device',function()
 local p=player();local d=fullSong(p,{Skills='Carpentry=100'});assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d)
 local other=device(p);p.items[d.id]=other;finish(d);assert(session.terminalPhase~='complete');eq(p.skills.Carpentry,nil)
end)
for _,option in ipairs({'SkillXP','KnownRecipes','SkillBooks','TrainingMedia'}) do
 test('restore rejects category policy change even after all gaps are filled '..option,function()
  local p=player();local d=fullSong(p,{Skills='Carpentry=100',Recipes='Soup'});assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d)
  p.skills.Carpentry=100;p.recipes.Soup=true;engine.options={['SurvivorsSong.'..option]=false};finish(d)
  assert(session.terminalPhase~='complete');engine.options=nil
 end)
end
test('empty completion rechecks policy after apply admission',function()
 local p=player();local d=fullSong(p,{Skills='Carpentry=100'});assert(SS.startKnowledgeSession(p,d,'restore'));local session=SS.getKnowledgeSession(d);p.skills.Carpentry=100
 local apply=SS.applyRestore;SS.applyRestore=function()engine.ratio=50;return false end;finish(d);SS.applyRestore=apply;engine.ratio=100
 eq(session.terminalPhase,'rejected');eq(p.skills.Carpentry,100)
end)
test('MP restoration sends missing fields to original actor',function()
 engine.server=true;engine.packets={};local p=player();local d=fullSong(p,{Recipes='Soup',SkillBooks='Base.BookCarpentry1=110',SkillBookStates='',MediaRewards='training=1'});engine.players={p}
 assert(SS.startKnowledgeSession(p,d,'restore'));finish(d);local packet
 for _,m in ipairs(engine.packets) do if m.command=='readFields' then packet=m end end
 assert(packet);eq(packet.args.recipientKey,SS.getActionActorKey(p));eq(packet.args.recipes[1],'Soup');eq(packet.args.final,true);eq(packet.args.skillBookStates,'');eq(packet.args.hasExactSkillBookSnapshot,true);eq(engine.syncMask,7)
 engine.server=false
end)
test('MP multiplier-only gate requires matching server reply',function()
 local p=player();p.pages['Base.BookCarpentry1']=220;local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220'});engine.players={p};engine.client=true
 local kind,allowed=SS.getKnowledgeActionChoice(p,d);eq(kind,'restore');eq(allowed,false);eq(engine.requestCommand,'readStatus');local request=copy(engine.lastRequest)
 engine.client=false;engine.server=true;engine.now=engine.now+500;emit('OnClientCommand',SS.MODULE,'readStatus',p,request);local answer=copy(engine.lastPacket);eq(answer.readable,true)
 engine.server=false;engine.client=true;local old=copy(answer);old.requestId=old.requestId-1;emit('OnServerCommand',SS.MODULE,'readStatus',old);eq(SS.hasServerMultiplierRepair(p,d),false)
 emit('OnServerCommand',SS.MODULE,'readStatus',answer);eq(SS.hasServerMultiplierRepair(p,d),true);kind,allowed=SS.getKnowledgeActionChoice(p,d);eq(kind,'restore');eq(allowed,true)
 d.md.SS_loadedSkillBookStates='';eq(SS.hasServerMultiplierRepair(p,d),false);engine.client=false
end)
test('server-confirmed no multiplier deficit allows knowledge update',function()
 local p=player();p.pages['Base.BookCarpentry1']=220;p.multipliers.Carpentry=3;p.recipes.Soup=true;local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220'});engine.players={p};engine.client=true
 SS.getKnowledgeActionChoice(p,d);local request=copy(engine.lastRequest);engine.client=false;engine.server=true;engine.now=engine.now+500;emit('OnClientCommand',SS.MODULE,'readStatus',p,request);local answer=copy(engine.lastPacket);eq(answer.readable,false)
 engine.server=false;engine.client=true;emit('OnServerCommand',SS.MODULE,'readStatus',answer);local kind,allowed=SS.getKnowledgeActionChoice(p,d);eq(kind,'record');eq(allowed,true);engine.client=false
end)
test('knowledge state packet cannot revive another character',function()
 local p=player();local d=device(p);engine.players={p};engine.client=true
 emit('OnServerCommand',SS.MODULE,'knowledgeState',{onlineID=p.id,recipientKey='old-actor',itemId=d.id,kind='record',phase='running',progress=0.5});eq(SS.getKnowledgeSession(d),nil);engine.client=false
end)


for _,option in ipairs({'SkillXP','KnownRecipes','SkillBooks','TrainingMedia'}) do
 test('mid-session '..option..' policy change stops recording',function()
  local p=player(nil,nil,{Carpentry=100});p.recipes.Soup=true;local d=device(p);assert(SS.startKnowledgeSession(p,d,'record'))
  local session=SS.getKnowledgeSession(d);engine.multiplier=session.duration/2;emit('OnTick');engine.multiplier=1
  engine.options={['SurvivorsSong.'..option]=false};emit('OnTick');eq(SS.getKnowledgeSession(d),nil);eq(d.md.SS_loadedMode,'blank');assert(d.md.SS_progressPage>0);engine.options=nil
 end)
end
test('recovery percent change invalidates current restore plan',function()
 local p=player();local d=fullSong(p,{Skills='Carpentry=100',Recipes='Soup'});assert(SS.startKnowledgeSession(p,d,'restore'));engine.ratio=50;emit('OnTick');eq(SS.getKnowledgeSession(d),nil);eq(p.skills.Carpentry,nil);eq(p.recipes.Soup,nil);engine.ratio=100
end)
test('future-version loaded blank refuses record and lossy eject',function()
 local p=player(nil,nil,{Carpentry=100});local d=device(p);d.md.SS_loadedVersion=99;d.md.SS_loadedFutureField='keep';eq(SS.canRecord(p,d),false);eq(SS.makeEjectedCD(d),nil);eq(d.md.SS_loadedFutureField,'keep')
end)
test('native field-sync failure retries committed result without reapplying',function()
 engine.server=true;engine.packets={};local p=player();local d=fullSong(p,{Skills='Carpentry=100',Recipes='Soup'});engine.players={p};engine.xpAdds=0
 local nativeSync=sendSyncPlayerFields;local attempts=0
 sendSyncPlayerFields=function(...)attempts=attempts+1;if attempts==1 then error('injected native fields send failure')end;return nativeSync(...)end
 assert(SS.startKnowledgeSession(p,d,'restore'));p.skills.Carpentry=60;finish(d);local session=SS.getKnowledgeSession(d);assert(session and session.applied and session.resultFields);eq(p.skills.Carpentry,100);eq(p.recipes.Soup,true);eq(engine.xpAdds,1)
 eq(SS.stopKnowledgeSession(p,d),false);eq(SS.stopKnowledgeSessionForDevice(d),false);engine.now=engine.now+501;emit('OnTick');eq(SS.getKnowledgeSession(d),nil);eq(engine.xpAdds,1);eq(attempts,2)
 sendSyncPlayerFields=nativeSync;engine.server=false
end)
test('partial result chunk failure retries immutable fields idempotently',function()
 engine.server=true;engine.packets={};local p=player();local recipes={};for i=1,101 do recipes[string.format('Recipe%03d',i)]=true end
 local d=fullSong(p,{Recipes=SS.Knowledge.encodeRecipes(recipes),Skills='Carpentry=100'});engine.players={p};engine.xpAdds=0
 local nativeSend=sendServerCommand;local chunks=0
 sendServerCommand=function(player,module,command,args)if command=='readFields' then chunks=chunks+1;if chunks==2 then error('injected second chunk failure')end end;return nativeSend(player,module,command,args)end
 assert(SS.startKnowledgeSession(p,d,'restore'));finish(d);assert(SS.getKnowledgeSession(d).applied);eq(engine.xpAdds,1);eq(SS.stopKnowledgeSession(p,d),false)
 engine.now=engine.now+501;emit('OnTick');eq(SS.getKnowledgeSession(d),nil);eq(engine.xpAdds,1);eq(chunks,5);sendServerCommand=nativeSend
 -- A separate client character consumes the duplicated first chunk followed
 -- by the full retry. It reaches the same fixed target exactly once.
 local client=player();client.id=p.id;engine.players={client};engine.server=false;engine.client=true
 for _,packet in ipairs(engine.packets) do if packet.command=='readFields' then packet.args.recipientKey=SS.getActionActorKey(client);emit('OnServerCommand',SS.MODULE,packet.command,packet.args) end end
 for name in pairs(recipes) do eq(client.recipes[name],true)end;engine.client=false
end)
test('readStatus for an earlier character cannot enable a new one',function()
 local p=player();p.pages['Base.BookCarpentry1']=220;local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220'});engine.players={p};engine.client=true;SS.getKnowledgeActionChoice(p,d);local request=copy(engine.lastRequest)
 engine.client=false;engine.server=true;engine.now=engine.now+500;emit('OnClientCommand',SS.MODULE,'readStatus',p,request);local answer=copy(engine.lastPacket);engine.server=false;engine.client=true;p.name='New Character';emit('OnServerCommand',SS.MODULE,'readStatus',answer);eq(SS.hasServerMultiplierRepair(p,d),false);engine.client=false
end)
test('negative multiplier response expires and can be refreshed',function()
 local p=player();p.pages['Base.BookCarpentry1']=220;p.multipliers.Carpentry=3;local d=fullSong(p,{SkillBooks='Base.BookCarpentry1=220'});engine.players={p};engine.client=true;SS.getKnowledgeActionChoice(p,d);local request=copy(engine.lastRequest)
 engine.client=false;engine.server=true;engine.now=engine.now+500;emit('OnClientCommand',SS.MODULE,'readStatus',p,request);local answer=copy(engine.lastPacket);engine.server=false;engine.client=true;emit('OnServerCommand',SS.MODULE,'readStatus',answer);eq(SS.getServerMultiplierReadStatus(p,d),false);engine.now=engine.now+1001;eq(SS.getServerMultiplierReadStatus(p,d),nil);SS.getKnowledgeActionChoice(p,d);assert(engine.lastRequest.requestId>request.requestId);engine.client=false
end)

-- Execute the actual media action code with native-slot inventory doubles.
ISBaseTimedAction={}
function ISBaseTimedAction:derive()local child={};child.__index=child;return setmetatable(child,{__index=self})end
function ISBaseTimedAction:new(character)return setmetatable({character=character},{__index=self})end
function ISBaseTimedAction:perform()end
function ISBaseTimedAction:stop()end
function sendAddItemToContainer()end
function sendRemoveItemFromContainer()end
dofile(source('survivorssong_actions.lua'))
local function mediaInventory(p,d)
 local inv=p:getInventory()
 function inv:getItems()local values={};for _,v in pairs(p.items)do values[#values+1]=v end;return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
 function inv:AddItem(item)p.items[item.id]=item;item.container=self;return item end
 function inv:Remove(item)p.items[item.id]=nil;item.container=nil end
 local data=d:getDeviceData()
 function data:getMediaIndex()return d.mediaIndex or 12 end
 function data:addMediaItem(item)if self:hasMedia()then return end;d.media=true;d.mediaIndex=12;inv:Remove(item)end
 function data:removeMediaItem(out)if not self:hasMedia()then return end;local item=instanceItem('Base.Disc_Retail');item.recorded=true;out:AddItem(item);d.media=false end
 return inv,data
end
test('actual native load-eject-reload keeps full payload and checkpoint',function()
 local p=player();local d=device(p);d.md={};d.media=false;local inv=mediaInventory(p,d)
 local disc=instanceItem('Base.Disc_Retail');disc.md={SS_version=3,SS_knowledgeVersion=6,SS_skills='',SS_recipes='Soup',SS_skillBooks='Base.BookCarpentry1=110',SS_skillBookStates='',SS_mediaRewards='training=1',SS_mediaRewardMode='whole-media',SS_authorName=p.name,SS_authorUser=p.user};SS.saveKnowledgeProgress(disc,'restore',SS.getActionActorKey(p),2,8);inv:AddItem(disc)
 local action=SurvivorsSongMediaAction:new(p,d,'load',disc);eq(action:complete(),true);eq(p.items[disc.id],nil);eq(d.md.SS_loadedRecipes,'Soup');eq(d.md.SS_loadedSkillBookStates,'');eq(d.md.SS_progressPage,2)
 action=SurvivorsSongMediaAction:new(p,d,'eject');eq(action:complete(),true);eq(d.md.SS_loadedMode,nil);local output
 for _,v in pairs(p.items)do if v~=d and SS.isKnowledgeCD(v)then output=v end end
 assert(output);eq(output.md.SS_recipes,'Soup');eq(output.md.SS_mediaRewards,'training=1');eq(output.md.SS_skillBookStates,'');eq(output.md.SS_progressPage,2)
 local second=device(p);second.md={};second.media=false;mediaInventory(p,second);action=SurvivorsSongMediaAction:new(p,second,'load',output);eq(action:complete(),true);eq(second.md.SS_loadedRecipes,'Soup');eq(second.md.SS_progressPage,2);assert(SS.startKnowledgeSession(p,second,'restore'));eq(SS.getKnowledgeSession(second).startPage,2);finish(second);eq(p.recipes.Soup,true)
end)
test('actual media action refuses unknown song without data loss',function()
 local p=player();local d=fullSong(p,{Recipes='Soup',SkillBookStates='',MediaRewards='training=1'});mediaInventory(p,d)
 d.md.SS_loadedVersion=99;local action=SurvivorsSongMediaAction:new(p,d,'eject');eq(action:complete(),false);eq(d.md.SS_loadedRecipes,'Soup');eq(d.md.SS_loadedVersion,99)
end)


test('late progress cannot resurrect a completed session',function()
 local p=player();local d=device(p);engine.players={p};engine.client=true
 local packet={onlineID=p.id,recipientKey=SS.getActionActorKey(p),itemId=d.id,kind='record',phase='complete',progress=1,sequence=100}
 emit('OnServerCommand',SS.MODULE,'knowledgeState',packet);eq(SS.getKnowledgeSession(d),nil)
 packet.phase='running';packet.progress=0.5;packet.sequence=99;emit('OnServerCommand',SS.MODULE,'knowledgeState',packet);eq(SS.getKnowledgeSession(d),nil)
 packet.sequence=101;emit('OnServerCommand',SS.MODULE,'knowledgeState',packet);assert(SS.getKnowledgeSession(d));packet.sequence=102;packet.phase='complete';packet.progress=1;emit('OnServerCommand',SS.MODULE,'knowledgeState',packet);eq(SS.getKnowledgeSession(d),nil);engine.client=false
end)
test('non-finite progress and fractional sequence cannot start client view',function()
 local p=player();local d=device(p);engine.players={p};engine.client=true
 local packet={onlineID=p.id,recipientKey=SS.getActionActorKey(p),itemId=d.id,kind='record',phase='running',progress=0/0,sequence=1}
 emit('OnServerCommand',SS.MODULE,'knowledgeState',packet);eq(SS.getKnowledgeSession(d),nil);packet.progress=0.5;packet.sequence=1.5;emit('OnServerCommand',SS.MODULE,'knowledgeState',packet);eq(SS.getKnowledgeSession(d),nil);engine.client=false
end)

test('terminal packet failure retries without restarting domain work',function()
 engine.server=true;local p=player();local d=fullSong(p,{Skills='Carpentry=100'});engine.players={p};engine.xpAdds=0;local nativeSend=sendServerCommand;local failures=0
 sendServerCommand=function(player,module,command,args)if command=='knowledgeState' and args.phase=='complete' and failures==0 then failures=1;error('injected terminal send failure')end;return nativeSend(player,module,command,args)end
 assert(SS.startKnowledgeSession(p,d,'restore'));finish(d);assert(SS.getKnowledgeSession(d).terminalPhase=='complete');eq(engine.xpAdds,1);engine.now=engine.now+501;emit('OnTick');eq(SS.getKnowledgeSession(d),nil);eq(engine.xpAdds,1);sendServerCommand=nativeSend;engine.server=false
end)
test('failed stop packet never lets cancelled recording keep advancing',function()
 engine.server=true;local p=player(nil,nil,{Carpentry=100});local d=device(p);engine.players={p};local nativeSend=sendServerCommand;local failures=0
 sendServerCommand=function(player,module,command,args)if command=='knowledgeState' and args.phase=='stopped' and failures==0 then failures=1;error('injected stopped send failure')end;return nativeSend(player,module,command,args)end
 assert(SS.startKnowledgeSession(p,d,'record'));SS.stopKnowledgeSession(p,d);local session=SS.getKnowledgeSession(d);assert(session.terminalPhase=='stopped');local elapsed=session.elapsed;engine.multiplier=session.duration;emit('OnTick');engine.multiplier=1;eq(session.elapsed,elapsed);eq(d.md.SS_loadedMode,'blank');engine.now=engine.now+501;emit('OnTick');eq(SS.getKnowledgeSession(d),nil);sendServerCommand=nativeSend;engine.server=false
end)
print('TOTAL '..passed..' PASS; production modules with engine stubs, not game validation')
