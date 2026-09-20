require "TimedActions/ISBaseTimedAction"
require "survivorssong/survivorssong_shared"
require "survivorssong/survivorssong_progress"

local SS = SurvivorsSong

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

    -- Capture the knowledge payload and interruption checkpoint before
    -- consuming the physical disc. The checkpoint belongs to the disc, not
    -- to whichever CD player happens to hold it.
    local isSong = SS.isKnowledgeCD(disc)
    local source = disc:getModData()
    local progressData = SS.snapshotKnowledgeProgress(disc)
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
    SS.restoreKnowledgeProgress(device, progressData)

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

-- The server's complete() mutates the disc and syncs the device. Client
-- completion clears presentation only, including rejected/cancelled actions.
function SurvivorsSongMediaAction:stop()
    clearMediaJob(self)
    ISBaseTimedAction.stop(self)
end

function SurvivorsSongMediaAction:perform()
    clearMediaJob(self)
    ISBaseTimedAction.perform(self)
end

function SurvivorsSongMediaAction:serverStart()
    -- Media mutations own the device briefly. End any background knowledge
    -- session first so its current whole-page checkpoint is saved before
    -- erase/eject/load changes the loaded-disc state.
    if SS.hasKnowledgeSession(self.item) then
        SS.stopKnowledgeSessionForDevice(self.item, "stopped")
    end
    if self.rejected or not self:isValid()
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
    -- serverStart() handles MP. This duplicate authoritative guard is required
    -- for singleplayer, where the media action has no dedicated serverStart.
    if SS.hasKnowledgeSession(self.item) then
        SS.stopKnowledgeSessionForDevice(self.item, "stopped")
    end
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
