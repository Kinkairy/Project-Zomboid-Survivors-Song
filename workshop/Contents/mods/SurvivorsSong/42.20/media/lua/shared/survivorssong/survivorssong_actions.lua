require "TimedActions/ISBaseTimedAction"
require "survivorssong/survivorssong_shared"
require "survivorssong/survivorssong_progress"

local SS = SurvivorsSong

SS._activeKnowledgeActions = SS._activeKnowledgeActions or setmetatable({}, { __mode = "k" })
SS._activeMediaActions = SS._activeMediaActions or setmetatable({}, { __mode = "k" })

local function syncDevice(device)
    if device and isServer() then device:syncItemFields() end
end

local function removeInventoryItem(item)
    if not item then return false end
    local container = item:getContainer()
    if not container then return false end
    container:Remove(item)
    if isServer() then sendRemoveItemFromContainer(container, item) end
    return true
end

local function addInventoryItem(character, item)
    if not character or not item then return false end
    local inventory = character:getInventory()
    if not inventory then return false end
    inventory:AddItem(item)
    if isServer() then sendAddItemToContainer(inventory, item) end
    return true
end

local function snapshotItemIds(inventory)
    local ids = {}
    if not inventory then return ids end
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local ok, id = pcall(function() return item:getID() end)
        if ok and id ~= nil then ids[tonumber(id)] = true end
    end
    return ids
end

local function findNewRecordedMedia(inventory, before, mediaIndex, fullType)
    if not inventory then return nil end
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local okId, id = pcall(function() return item:getID() end)
        local okRecorded, recorded = pcall(function() return item:isRecordedMedia() end)
        local okIndex, recordedIndex = pcall(function() return item:getRecordedMediaIndex() end)
        local okType, itemType = pcall(function() return item:getFullType() end)
        if okId and id ~= nil and not before[tonumber(id)]
            and okRecorded and recorded
            and okIndex and tonumber(recordedIndex) == tonumber(mediaIndex)
            and (not fullType or (okType and tostring(itemType) == fullType)) then
            return item
        end
    end
    return nil
end

-- Insert a real Base.CD into the native DeviceData media slot by temporarily
-- assigning it a valid vanilla CD RecordedMedia index. The temporary carrier
-- item never becomes the player-visible ejected disc.
local function insertCarrier(character, device, preferredIndex)
    local data = SS.getDeviceData(device)
    local inventory = character and character:getInventory() or nil
    if not data or not inventory or data:hasMedia() then return false end

    local carrier, carrierIndex = SS.makeCarrierCD(preferredIndex)
    if not carrier or carrierIndex == nil then return false end

    inventory:AddItem(carrier)
    if isServer() then sendAddItemToContainer(inventory, carrier) end

    data:addMediaItem(carrier)

    local inserted = data:hasMedia()
        and tonumber(data:getMediaType()) == 0
        and tonumber(data:getMediaIndex()) == tonumber(carrierIndex)

    if not inserted and carrier:getContainer() then
        removeInventoryItem(carrier)
    end
    return inserted, carrierIndex
end

local function discardCurrentCarrier(character, device)
    local data = SS.getDeviceData(device)
    local inventory = character and character:getInventory() or nil
    if not data or not inventory then return false end
    if not data:hasMedia() then return true end

    local carrierIndex = tonumber(data:getMediaIndex())
    local before = snapshotItemIds(inventory)
    data:removeMediaItem(inventory)
    local generated = findNewRecordedMedia(inventory, before, carrierIndex,
        SS.BLANK_CD_TYPE)
    if not generated then return false end
    return removeInventoryItem(generated)
end

local function rollbackCustomEject(character, device, carrierIndex, before)
    local data = SS.getDeviceData(device)
    local inventory = character and character:getInventory() or nil
    if not data or not inventory then return false end

    local restored = data:hasMedia()
    if not restored then
        restored = select(1, insertCarrier(character, device, carrierIndex)) == true
    end

    while true do
        local generated = findNewRecordedMedia(inventory, before, carrierIndex,
            SS.BLANK_CD_TYPE)
        if not generated then break end
        if not removeInventoryItem(generated) then
            syncDevice(device)
            return false
        end
    end

    syncDevice(device)
    return restored and data:hasMedia()
end

local function eraseNativeMedia(character, device)
    local data = SS.getDeviceData(device)
    local inventory = character and character:getInventory() or nil
    if not data or not inventory or not data:hasMedia()
        or tonumber(data:getMediaType()) ~= 0 then
        return false
    end

    local originalIndex = tonumber(data:getMediaIndex())
    local before = snapshotItemIds(inventory)

    if data:isPlayingMedia() then data:StopPlayMedia() end
    data:removeMediaItem(inventory)

    local originalDisc = findNewRecordedMedia(inventory, before, originalIndex, nil)
    if not originalDisc then return false end

    local inserted = insertCarrier(character, device, originalIndex)
    if not inserted then
        -- Restore the original disc to the native slot rather than lose it.
        data:addMediaItem(originalDisc)
        return false
    end

    if not removeInventoryItem(originalDisc) then
        discardCurrentCarrier(character, device)
        if not data:hasMedia() and originalDisc:getContainer() == inventory then
            data:addMediaItem(originalDisc)
        end
        syncDevice(device)
        return false
    end
    SS.setBlankLoaded(device)
    syncDevice(device)
    return true
end

local function eraseLoadedSong(device)
    if SS.getLoadedMode(device) ~= SS.MODE_SONG then return false end
    SS.setBlankLoaded(device)
    syncDevice(device)
    return true
end

local function loadPhysicalDisc(character, device, disc)
    if not SS.canLoadCustomCD(character, device, disc) then return false end

    -- Capture the knowledge payload before consuming the physical disc.
    local isSong = SS.isKnowledgeCD(disc)
    local source = disc:getModData()
    local songData = nil
    if isSong then
        songData = {
            skills = tostring(source.SS_skills or ""),
            authorName = tostring(source.SS_authorName or ""),
            authorUser = tostring(source.SS_authorUser or ""),
            recordedAt = tostring(source.SS_recordedAt or ""),
        }
    end

    local inserted = insertCarrier(character, device, nil)
    if not inserted then return false end

    if not removeInventoryItem(disc) then
        -- Native carrier now exists; remove it through the same native path
        -- before failing so the physical disc remains the only copy.
        discardCurrentCarrier(character, device)
        return false
    end

    if songData then
        SS.clearLoadedMedia(device)
        local md = device:getModData()
        md.SS_loadedMode = SS.MODE_SONG
        md.SS_loadedVersion = SS.VERSION
        md.SS_loadedSkills = songData.skills
        md.SS_loadedAuthorName = songData.authorName
        md.SS_loadedAuthorUser = songData.authorUser
        md.SS_loadedRecordedAt = songData.recordedAt
    else
        SS.setBlankLoaded(device)
    end

    syncDevice(device)
    return true
end

local function ejectPhysicalDisc(character, device)
    if not SS.canEjectCustomCD(character, device) then return false end

    local output = SS.makeEjectedCD(device)
    if not output then return false end

    local data = SS.getDeviceData(device)
    local inventory = character:getInventory()
    local carrierIndex = tonumber(data:getMediaIndex())
    local before = snapshotItemIds(inventory)

    if data:isPlayingMedia() then data:StopPlayMedia() end
    data:removeMediaItem(inventory)

    local generated = findNewRecordedMedia(inventory, before, carrierIndex, SS.BLANK_CD_TYPE)
    if not generated then
        rollbackCustomEject(character, device, carrierIndex, before)
        return false
    end
    if not removeInventoryItem(generated) then
        rollbackCustomEject(character, device, carrierIndex, before)
        return false
    end

    if not addInventoryItem(character, output) then
        rollbackCustomEject(character, device, carrierIndex, before)
        return false
    end

    SS.clearLoadedMedia(device)
    syncDevice(device)
    return true
end

SurvivorsSongKnowledgeAction = ISBaseTimedAction:derive("SurvivorsSongKnowledgeAction")

function SurvivorsSongKnowledgeAction:isValid()
    return not self.rejected
        and SS.isKnowledgeActionContextValid(self.character, self.item, self.kind)
end

function SurvivorsSongKnowledgeAction:getDuration()
    return self.duration or SS.getActionTime(self.kind, self.character, self.item)
end

function SurvivorsSongKnowledgeAction:isUsingTimeout()
    -- Personal Journal-sized record/recovery actions can legitimately exceed
    -- the normal multiplayer real-time timeout.
    return false
end

function SurvivorsSongKnowledgeAction:start()
    SS._activeKnowledgeActions[self.item] = self
    local data = SS.getDeviceData(self.item)
    if data and data:isPlayingMedia() then data:StopPlayMedia() end
    self.item:setJobDelta(0)
    local label = getText(self.kind == "record"
        and "ContextMenu_SurvivorsSong_RecordingCD"
        or "ContextMenu_SurvivorsSong_RestoringCD")
    self.item:setJobType(label)
    SS.beginProgressView(self, label)
end

function SurvivorsSongKnowledgeAction:update()
    if isClient() then
        SS.updateProgressView(self)
        return
    end
    if not self:isValid() then
        self:forceStop()
        return
    end
    self.item:setJobDelta(self:getJobDelta())
end

local function clearKnowledgeJob(self)
    SS.endProgressView(self)
    if SS._activeKnowledgeActions[self.item] == self then
        SS._activeKnowledgeActions[self.item] = nil
    end
    if self.item then
        self.item:setJobDelta(0)
        self.item:setJobType("")
        local container = self.item:getContainer()
        if container then container:setDrawDirty(true) end
    end
end

function SurvivorsSongKnowledgeAction:stop()
    clearKnowledgeJob(self)
    ISBaseTimedAction.stop(self)
end

function SurvivorsSongKnowledgeAction:forceCancel()
    SS.endProgressView(self)
    ISBaseTimedAction.forceCancel(self)
end

function SurvivorsSongKnowledgeAction:perform()
    -- Multiplayer only reaches perform() after the server returns Done. Mirror
    -- the mode immediately so the Play button cannot briefly fall back to a
    -- second record attempt while SyncItemFields is still in flight. The full
    -- authoritative skill/author payload still comes from the server.
    if isClient() and self.kind == "record"
        and SS.getLoadedMode(self.item) == SS.MODE_BLANK then
        local md = self.item:getModData()
        md.SS_loadedMode = SS.MODE_SONG
        md.SS_loadedVersion = SS.VERSION
    end
    clearKnowledgeJob(self)
    ISBaseTimedAction.perform(self)
end

function SurvivorsSongKnowledgeAction:serverStart()
    if self.rejected or not SS.isKnowledgeActionValid(self.character, self.item, self.kind)
        or (SS._activeKnowledgeActions[self.item]
            and SS._activeKnowledgeActions[self.item] ~= self)
        or SS._activeMediaActions[self.item] then
        self.rejected = true
        SS.publishActionProgress(self, "rejected")
        self.netAction:forceComplete()
        return
    end
    SS._activeKnowledgeActions[self.item] = self
    SS.publishActionProgress(self, "running")
end

local function releaseKnowledgeServer(self)
    if SS._activeKnowledgeActions[self.item] == self then
        SS._activeKnowledgeActions[self.item] = nil
    end
end

function SurvivorsSongKnowledgeAction:serverStop()
    SS.publishActionProgress(self, "cancelled")
    releaseKnowledgeServer(self)
end

function SurvivorsSongKnowledgeAction:complete()
    if isClient() then return false end
    if self.rejected
        or not SS.isKnowledgeActionValid(self.character, self.item, self.kind) then
        SS.publishActionProgress(self, "rejected")
        releaseKnowledgeServer(self)
        return false
    end

    SS.publishActionProgress(self, "applying")
    local ok, applied = pcall(function()
        if self.kind == "record" then
            local changed = SS.commitRecord(self.character, self.item)
            if changed then syncDevice(self.item) end
            return changed
        end
        return SS.applyRestore(self.character, self.item)
    end)
    SS.publishActionProgress(self, ok and applied and "complete" or "rejected")
    releaseKnowledgeServer(self)
    if not ok then error(applied) end
    return applied == true
end

function SurvivorsSongKnowledgeAction:new(character, item, kind, recipientKey, progressKey)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.kind = kind
    o.recipientKey = recipientKey
    o.progressKey = progressKey
    if not isServer() and character then
        o.recipientKey = SS.getActionActorKey(character)
        o.progressKey = SS.newProgressKey()
    end
    if not character or not SS.isCDPlayer(item)
        or (kind ~= "record" and kind ~= "restore")
        or type(o.recipientKey) ~= "string" or #o.recipientKey > 1024
        or not SS.isProgressKey(o.progressKey) then
        o.rejected = true
    end
    o.ignoreHandsWounds = true
    o.forceProgressBar = true
    o.stopOnRun = true
    o.stopOnWalk = false
    o.duration = (not o.rejected) and SS.getActionTime(kind, character, item) or 1
    o.maxTime = isClient() and SS.PROGRESS_VIEW_SCALE or o.duration
    return o
end

SurvivorsSongMediaAction = ISBaseTimedAction:derive("SurvivorsSongMediaAction")

function SurvivorsSongMediaAction:isValid()
    return not self.rejected
        and SS.isMediaActionValid(self.character, self.item, self.kind, self.secondaryItem)
end

function SurvivorsSongMediaAction:getDuration()
    return SS.MEDIA_ACTION_TIME
end

function SurvivorsSongMediaAction:start()
    SS._activeMediaActions[self.item] = self
    local data = SS.getDeviceData(self.item)
    if data and data:isPlayingMedia() then data:StopPlayMedia() end

    self.item:setJobDelta(0)
    local key = self.kind == "erase" and "ContextMenu_SurvivorsSong_ErasingCD"
        or (self.kind == "load" and "IGUI_media_addMedia" or "IGUI_media_removeMedia")
    self.item:setJobType(getText(key))
end

function SurvivorsSongMediaAction:update()
    self.item:setJobDelta(self:getJobDelta())
end

local function clearMediaJob(self)
    if SS._activeMediaActions[self.item] == self then
        SS._activeMediaActions[self.item] = nil
    end
    if self.item then
        self.item:setJobDelta(0)
        self.item:setJobType("")
        local container = self.item:getContainer()
        if container then container:setDrawDirty(true) end
    end
end

local function applyClientMirror(self)
    if not isClient() or not self.item then return end
    if self.kind == "erase" then
        SS.setBlankLoaded(self.item)
    elseif self.kind == "load" and self.secondaryItem then
        SS.setLoadedFromDisc(self.item, self.secondaryItem)
    elseif self.kind == "eject" then
        SS.clearLoadedMedia(self.item)
    end
end

function SurvivorsSongMediaAction:stop()
    clearMediaJob(self)
    ISBaseTimedAction.stop(self)
end

function SurvivorsSongMediaAction:perform()
    applyClientMirror(self)
    clearMediaJob(self)
    ISBaseTimedAction.perform(self)
end

function SurvivorsSongMediaAction:serverStart()
    if self.rejected or not self:isValid()
        or SS._activeKnowledgeActions[self.item]
        or (SS._activeMediaActions[self.item]
            and SS._activeMediaActions[self.item] ~= self) then
        self.rejected = true
        self.netAction:forceComplete()
        return
    end
    SS._activeMediaActions[self.item] = self
end

local function releaseMediaServer(self)
    if SS._activeMediaActions[self.item] == self then
        SS._activeMediaActions[self.item] = nil
    end
end

function SurvivorsSongMediaAction:serverStop()
    releaseMediaServer(self)
end

function SurvivorsSongMediaAction:complete()
    if isClient() then return false end
    if self.rejected or not self:isValid() then
        releaseMediaServer(self)
        return false
    end

    local applied = false
    if self.kind == "load" then
        applied = loadPhysicalDisc(self.character, self.item, self.secondaryItem)
    elseif self.kind == "eject" then
        applied = ejectPhysicalDisc(self.character, self.item)
    elseif self.kind == "erase" then
        if SS.getLoadedMode(self.item) == SS.MODE_SONG then
            applied = eraseLoadedSong(self.item)
        else
            applied = eraseNativeMedia(self.character, self.item)
        end
    end

    releaseMediaServer(self)
    return applied == true
end

function SurvivorsSongMediaAction:new(character, item, kind, secondaryItem)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.item = item
    o.kind = kind
    o.secondaryItem = secondaryItem
    if not character or not SS.isCDPlayer(item)
        or (kind ~= "load" and kind ~= "eject" and kind ~= "erase") then
        o.rejected = true
    end
    o.ignoreHandsWounds = true
    o.forceProgressBar = true
    o.stopOnRun = true
    o.stopOnWalk = false
    o.maxTime = isClient() and -1 or o:getDuration()
    return o
end

print("[SurvivorsSong] actions loaded build=" .. SS.BUILD)
