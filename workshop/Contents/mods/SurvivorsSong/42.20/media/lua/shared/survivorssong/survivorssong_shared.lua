SurvivorsSong = SurvivorsSong or {}

local SS = SurvivorsSong
SS._sharedReady = false
SS._knowledgeInstalled = false

SS.VERSION = 3
SS.LEGACY_VERSION = 2
SS.BUILD = "rc0.4.5"
SS.MODULE = "SurvivorsSong"

SS.RETAIL_CD_TYPE = "Base.Disc_Retail"
-- B42.20 has no Base.CD item. Blank/song discs reuse the real vanilla
-- Base.Disc_Retail item with RecordedMedia index cleared to -1.
SS.BLANK_CD_TYPE = SS.RETAIL_CD_TYPE
SS.CD_PLAYER_TYPE = "Base.CDplayer"
SS.MICROPHONE_TYPE = "Base.Microphone"
SS.RECORDED_AT_TEXT_KEY = "IGUI_SurvivorsSong_RecordedAt"

SS.MODE_BLANK = "blank"
SS.MODE_SONG = "song"
SS.MEDIA_ACTION_TIME = 30
SS.ACTION_PROGRESS_MODEL_VERSION = 1

local function finiteNumber(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function safeFullType(item)
    -- Fluid-transfer and other native UI paths may pass Java components such
    -- as FluidContainer here. Kahlua still reports an invalid Java method call
    -- even when getFullType() is wrapped in pcall, so reject non-items first.
    if not item or not instanceof(item, "InventoryItem") then return nil end
    local ok, value = pcall(function() return item:getFullType() end)
    if not ok or not value then return nil end
    return tostring(value)
end
SS.safeFullType = safeFullType

local function safeItemId(item)
    if not item then return nil end
    local ok, value = pcall(function() return item:getID() end)
    if not ok or value == nil then return nil end
    return tonumber(value)
end
SS.safeItemId = safeItemId

function SS.isCDPlayer(item)
    -- Native media windows also expose world devices and VehiclePart. Check
    -- the Java class before calling InventoryItem methods: pcall still logs
    -- invalid Java method calls in Kahlua on every window update.
    if not item or not instanceof(item, "Radio") then return false end
    return safeFullType(item) == SS.CD_PLAYER_TYPE
end

function SS.isRecordedRetailCD(item)
    if safeFullType(item) ~= SS.RETAIL_CD_TYPE then return false end
    local okRecorded, recorded = pcall(function() return item:isRecordedMedia() end)
    if not okRecorded or recorded ~= true then return false end
    local okType, mediaType = pcall(function() return item:getMediaType() end)
    return okType and tonumber(mediaType) == 0
end

function SS.isPhysicalCD(item)
    return safeFullType(item) == SS.RETAIL_CD_TYPE
end

function SS.isBlankCD(item)
    return safeFullType(item) == SS.RETAIL_CD_TYPE
        and not SS.isRecordedRetailCD(item)
        and not SS.hasKnowledgeMarker(item)
end

function SS.findItemById(player, itemId)
    if not player or itemId == nil then return nil end
    local inventory = player:getInventory()
    local numeric = tonumber(itemId)
    if not inventory or not numeric then return nil end
    local ok, item = pcall(function() return inventory:getItemWithIDRecursiv(numeric) end)
    if ok then return item end
    return nil
end

function SS.findDeviceById(player, itemId)
    local item = SS.findItemById(player, itemId)
    if SS.isCDPlayer(item) then return item end
    return nil
end

function SS.getDeviceData(device)
    if not SS.isCDPlayer(device) then return nil end
    local ok, data = pcall(function() return device:getDeviceData() end)
    if ok then return data end
    return nil
end

function SS.getOptionNumber(name, defaultValue, minValue, maxValue)
    local value = defaultValue
    local ok, configured = pcall(function()
        local options = getSandboxOptions()
        local option = options and options:getOptionByName("SurvivorsSong." .. name)
        if option then return option:getValue() end
        return nil
    end)
    if ok and finiteNumber(configured) then value = tonumber(configured) end
    if minValue ~= nil then value = math.max(minValue, value) end
    if maxValue ~= nil then value = math.min(maxValue, value) end
    return value
end

function SS.isOptionEnabled(name, defaultValue)
    local value = defaultValue ~= false
    local ok, configured = pcall(function()
        local options = getSandboxOptions()
        local option = options and options:getOptionByName("SurvivorsSong." .. name)
        if option then return option:getValue() end
        return nil
    end)
    if not ok or configured == nil then return value end
    if configured == true or tostring(configured) == "true" then return true end
    if configured == false or tostring(configured) == "false" then return false end
    return value
end

-- 1 = vanilla, 2 = 30, 3 = 60, 4 = 120 game minutes.
function SS.getPlaybackDurationMinutes()
    local option = math.floor(SS.getOptionNumber("PlaybackDuration", 3, 1, 4))
    if option == 1 then return 0 end
    if option == 2 then return 30 end
    if option == 4 then return 120 end
    return 60
end

function SS.isSkillXpEnabled()
    return SS.isOptionEnabled("SkillXP", true)
end

function SS.hasMicrophone(player)
    if not player or not player:getInventory() then return false end
    local inventory = player:getInventory()
    local ok, found = pcall(function()
        return inventory:containsTypeRecurse("Microphone")
            or inventory:containsTypeRecurse(SS.MICROPHONE_TYPE)
    end)
    if ok and found then return true end

    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        if safeFullType(items:get(index)) == SS.MICROPHONE_TYPE then return true end
    end
    return false
end

function SS.hasHeadphones(device)
    local data = SS.getDeviceData(device)
    if not data then return false end
    local ok, headphoneType = pcall(function() return data:getHeadphoneType() end)
    return ok and tonumber(headphoneType) ~= nil and tonumber(headphoneType) >= 0
end

function SS.hasUsablePower(device)
    local data = SS.getDeviceData(device)
    if not data then return false end

    local okBattery, batteryPowered = pcall(function() return data:getIsBatteryPowered() end)
    if okBattery and batteryPowered == true then
        local okHas, hasBattery = pcall(function() return data:getHasBattery() end)
        local okPower, power = pcall(function() return data:getPower() end)
        return okHas and hasBattery == true and okPower and (tonumber(power) or 0) > 0
    end

    local okHere, canPower = pcall(function() return data:canBePoweredHere() end)
    return okHere and canPower == true
end

function SS.isDeviceTurnedOn(device)
    local data = SS.getDeviceData(device)
    if not data then return false end
    local ok, value = pcall(function() return data:getIsTurnedOn() end)
    return ok and value == true
end

function SS.isKnowledgeDeviceActiveForPlayer(player, device)
    if not player or not device then return false end
    if SS.findDeviceById(player, safeItemId(device)) ~= device then return false end
    if player:getPrimaryHandItem() == device or player:getSecondaryHandItem() == device then
        return true
    end
    local okAttached, attached = pcall(function() return player:isAttachedItem(device) end)
    if okAttached and attached == true then return true end
    local okSlot, slot = pcall(function() return device:getAttachedSlot() end)
    return okSlot and tonumber(slot) ~= nil and tonumber(slot) >= 0
        and device:getContainer() == player:getInventory()
end

-- Blank/song CDs occupy the native DeviceData media slot with a temporary
-- vanilla CD RecordedMedia index. Presence/ejection therefore stays on the
-- native hasMedia()/removeMediaItem() path instead of being faked in ModData.
function SS.getCarrierMediaData(preferredIndex, mediaCategory)
    if not mediaCategory then return nil end
    local ok, recorded = pcall(function()
        return getZomboidRadio():getRecordedMedia()
    end)
    if not ok or not recorded then return nil end

    -- Use the same category API as vanilla InvContextMedia. Lua numbers cannot
    -- be passed to the Java short/byte index/type overloads on B42.20.
    local okList, list = pcall(function()
        return recorded:getAllMediaForCategory(mediaCategory)
    end)
    if not okList or not list then return nil end
    local preferred = tonumber(preferredIndex)
    local fallback = nil
    for index = 0, list:size() - 1 do
        local data = list:get(index)
        if data and tonumber(data:getMediaType()) == 0 then
            local mediaIndex = tonumber(data:getIndexForLua())
            if mediaIndex and mediaIndex >= 0 then
                if mediaIndex == preferred then return data end
                fallback = fallback or data
            end
        end
    end
    return fallback
end

function SS.makeCarrierCD(preferredIndex)
    local item = instanceItem(SS.RETAIL_CD_TYPE)
    if not item then return nil end
    local mediaData = SS.getCarrierMediaData(preferredIndex,
        item:getScriptItem():getRecordedMediaCat())
    if not mediaData then return nil end

    item:setRecordedMediaData(mediaData)

    if not item:isRecordedMedia() or tonumber(item:getMediaType()) ~= 0 then
        return nil
    end
    return item, tonumber(item:getRecordedMediaIndex())
end

local PROGRESS_FIELDS = {
    "SS_progressKind",
    "SS_progressActor",
    "SS_progressPage",
    "SS_progressTotalPages",
    "SS_progressModelVersion",
}

local LOADED_FIELDS = {
    "SS_loadedMode",
    "SS_loadedVersion",
    "SS_loadedSkills",
    "SS_loadedKnowledgeVersion",
    "SS_loadedRecipes",
    "SS_loadedSkillBooks",
    "SS_loadedSkillBookStates",
    "SS_loadedMediaRewards",
    "SS_loadedMediaRewardMode",
    "SS_loadedAuthorDescId",
    "SS_loadedAuthorName",
    "SS_loadedAuthorUser",
    "SS_loadedRecordedAt",
}
for _, key in ipairs(PROGRESS_FIELDS) do
    LOADED_FIELDS[#LOADED_FIELDS + 1] = key
end

function SS.getLoadedMode(device)
    if not SS.isCDPlayer(device) then return nil end
    local mode = tostring(device:getModData().SS_loadedMode or "")
    if mode == SS.MODE_BLANK or mode == SS.MODE_SONG then return mode end
    return nil
end

function SS.clearLoadedMedia(device)
    if not SS.isCDPlayer(device) then return false end
    local md = device:getModData()
    for _, key in ipairs(LOADED_FIELDS) do md[key] = nil end
    return true
end

function SS.setBlankLoaded(device)
    if not SS.isCDPlayer(device) then return false end
    SS.clearLoadedMedia(device)
    local md = device:getModData()
    md.SS_loadedMode = SS.MODE_BLANK
    md.SS_loadedVersion = SS.VERSION
    return true
end

local function holderModData(holder)
    if not holder then return nil end
    local ok, md = pcall(function() return holder:getModData() end)
    if ok then return md end
    return nil
end

function SS.snapshotKnowledgeProgress(holder)
    local md = holderModData(holder)
    local result = {}
    if not md then return result end
    for _, key in ipairs(PROGRESS_FIELDS) do
        result[key] = md[key]
    end
    return result
end

function SS.restoreKnowledgeProgress(holder, snapshot)
    local md = holderModData(holder)
    if not md then return false end
    for _, key in ipairs(PROGRESS_FIELDS) do
        md[key] = snapshot and snapshot[key] or nil
    end
    return true
end

function SS.copyKnowledgeProgress(source, target)
    return SS.restoreKnowledgeProgress(target, SS.snapshotKnowledgeProgress(source))
end

function SS.getSavedKnowledgePage(holder, kind, actorKey, totalPages)
    local md = holderModData(holder)
    if not md then return 0 end
    if tostring(md.SS_progressKind or "") ~= tostring(kind or "")
        or tostring(md.SS_progressActor or "") ~= tostring(actorKey or "")
        or tonumber(md.SS_progressModelVersion) ~= SS.ACTION_PROGRESS_MODEL_VERSION then
        return 0
    end
    totalPages = math.max(1, math.floor(tonumber(totalPages) or 1))
    local page = math.max(0, math.floor(tonumber(md.SS_progressPage) or 0))
    return math.max(0, math.min(totalPages, page))
end

function SS.saveKnowledgeProgress(holder, kind, actorKey, page, totalPages)
    local md = holderModData(holder)
    if not md then return false end
    totalPages = math.max(1, math.floor(tonumber(totalPages) or 1))
    page = math.max(0, math.min(totalPages,
        math.floor(tonumber(page) or 0)))
    md.SS_progressKind = tostring(kind or "")
    md.SS_progressActor = tostring(actorKey or "")
    md.SS_progressPage = page
    md.SS_progressTotalPages = totalPages
    md.SS_progressModelVersion = SS.ACTION_PROGRESS_MODEL_VERSION
    return true
end

function SS.clearKnowledgeProgress(holder)
    SS.restoreKnowledgeProgress(holder, nil)
end

function SS.getRemainingActionTime(totalTime, startPage, totalPages)
    totalPages = math.max(1, math.floor(tonumber(totalPages) or 1))
    startPage = math.max(0, math.min(totalPages,
        math.floor(tonumber(startPage) or 0)))
    return math.max(1, math.floor((tonumber(totalTime) or 1)
        * ((totalPages - startPage) / totalPages)))
end

function SS.getSongName(authorName)
    authorName = tostring(authorName or "")
    if authorName == "" then authorName = "Unknown" end
    local ok, translated = pcall(function()
        return getText("IGUI_SurvivorsSong_SongName", authorName)
    end)
    if ok and translated and tostring(translated) ~= "IGUI_SurvivorsSong_SongName" then
        return tostring(translated)
    end
    return "CD: " .. authorName .. "'s Song"
end

function SS.isKnowledgeCD(item)
    return SS.isSupportedKnowledgeRecord(item, false)
end

function SS.getSavedSkills(item)
    return SS.Knowledge.getSavedSkills(SS.knowledgeView(item, false))
end

function SS.getSongTooltip(item)
    if not SS.isKnowledgeCD(item) then return nil end
    local recordedAt = tostring(item:getModData().SS_recordedAt or "")
    if recordedAt == "" then return nil end
    return getText(SS.RECORDED_AT_TEXT_KEY, recordedAt)
end


function SS.canUseKnowledgeRecord(player, itemOrDevice)
    local loaded = SS.isCDPlayer(itemOrDevice)
    return SS.Knowledge.isAuthor(player, SS.knowledgeView(itemOrDevice, loaded))
end

function SS.refreshSongPresentation(item)
    if not SS.isKnowledgeCD(item) then return false end
    local expected = SS.getSongName(item:getModData().SS_authorName)
    local changed = false
    if item:getName() ~= expected then
        item:setName(expected)
        changed = true
    end
    local ok, customName = pcall(function() return item:isCustomName() end)
    if not ok or customName ~= true then
        item:setCustomName(true)
        changed = true
    end
    return changed
end

function SS.getLoadedSkills(device)
    if SS.getLoadedMode(device) ~= SS.MODE_SONG then return {} end
    return SS.Knowledge.getSavedSkills(SS.knowledgeView(device, true))
end

function SS.getLoadedSongName(device)
    if SS.getLoadedMode(device) ~= SS.MODE_SONG then return nil end
    return SS.getSongName(device:getModData().SS_loadedAuthorName)
end

function SS.makeEjectedCD(device)
    local mode = SS.getLoadedMode(device)
    if not mode then return nil end
    -- Unknown loaded schemas must stay intact for a compatible version;
    -- this adapter cannot safely repackage fields it does not understand.
    if not SS.isSupportedLoadedCarrier(device) then return nil end

    local item = instanceItem(SS.RETAIL_CD_TYPE)
    if not item then return nil end
    -- A fresh vanilla Base.Disc_Retail already has no RecordedMedia index.
    -- Do not call setRecordedMediaIndex(-1): that Java bridge call is not
    -- valid in the dedicated-server Lua runtime used by B42.20.
    -- The interruption checkpoint belongs to the disc, so carry the loaded
    -- semantic checkpoint back to the physical item on eject.
    SS.copyKnowledgeProgress(device, item)
    if mode == SS.MODE_SONG then
        local source = device:getModData()
        local md = item:getModData()
        SS.copyKnowledgePayload(source, md, true, false)
        SS.refreshSongPresentation(item)
    end
    return item
end

-- Knowledge semantics are generated from Personal Journal 1.3.3. Device,
-- carrier and presentation adapters live separately from that authority.
SS._sharedReady = true
require "survivorssong/knowledge"
SS.installKnowledge()

function SS.canLoadCustomCD(player, device, disc)
    if not player or player:isDead() or not SS.isCDPlayer(device) then return false end
    if not SS.isBlankCD(disc) and not SS.isKnowledgeCD(disc) then return false end
    if SS.findDeviceById(player, safeItemId(device)) ~= device then return false end
    if SS.findItemById(player, safeItemId(disc)) ~= disc then return false end
    local data = SS.getDeviceData(device)
    return data and tonumber(data:getMediaType()) == 0 and not data:hasMedia()
        and SS.getLoadedMode(device) == nil
end

function SS.canEjectCustomCD(player, device)
    if not player or player:isDead() or not SS.isCDPlayer(device) then return false end
    if SS.findDeviceById(player, safeItemId(device)) ~= device then return false end
    local data = SS.getDeviceData(device)
    return data and data:hasMedia() and tonumber(data:getMediaType()) == 0
        and SS.getLoadedMode(device) ~= nil
end

function SS.hasErasableCD(device)
    if not SS.isCDPlayer(device) then return false end
    local data = SS.getDeviceData(device)
    if not data or not data:hasMedia() or tonumber(data:getMediaType()) ~= 0 then return false end
    local mode = SS.getLoadedMode(device)
    return mode == nil or mode == SS.MODE_SONG
end

function SS.canEraseCD(player, device)
    if not player or player:isDead() or not SS.isCDPlayer(device) then return false end
    if SS.findDeviceById(player, safeItemId(device)) ~= device then return false end
    return SS.hasUsablePower(device) and SS.hasErasableCD(device)
end

function SS.isMediaActionValid(player, device, kind, disc)
    if kind == "load" then return SS.canLoadCustomCD(player, device, disc) end
    if kind == "eject" then return SS.canEjectCustomCD(player, device) end
    if kind == "erase" then return SS.canEraseCD(player, device) end
    return false
end

-- Continuous effects retain vanilla interaction magnitudes, native stat bounds
-- and native halo presentation. B42.20's radio handler still calls removed
-- getStress/getPanic/getAnger methods; use the maintained CharacterStat API.
SS.LISTENING_EFFECTS = {
    { option = "ReduceBoredom", default = true, stat = "BOREDOM", amount = 5, halo = "Boredom" },
    { option = "ReduceUnhappiness", default = true, stat = "UNHAPPINESS", amount = 5, halo = "Unhappiness" },
    { option = "ReduceStress", default = true, stat = "STRESS", amount = 0.05, halo = "Stress" },
    { option = "ReducePanic", default = false, stat = "PANIC", amount = 5, halo = "Panic" },
    { option = "ReduceAnger", default = false, stat = "ANGER", amount = 0.05, halo = "Anger" },
}

function SS.getMediaKey(deviceData)
    if not deviceData then return "" end
    local ok, media = pcall(function() return deviceData:getMediaData() end)
    if ok and media then
        local idOk, id = pcall(function() return media:getId() end)
        if idOk and id and tostring(id) ~= "" then return tostring(id) end
    end
    local typeOk, mediaType = pcall(function() return deviceData:getMediaType() end)
    local indexOk, mediaIndex = pcall(function() return deviceData:getMediaIndex() end)
    return tostring(typeOk and mediaType or "") .. ":" .. tostring(indexOk and mediaIndex or "")
end

function SS.applyListeningEffect(player, deviceData)
    if isServer() or not player or not player:isLocalPlayer()
        or player:isDead() or player:isAsleep()
        or not deviceData or not deviceData:hasMedia()
        or not deviceData:isPlayingMedia() then
        return false
    end
    local stats = player:getStats()
    if not stats then return false end
    local changed = false
    for _, effect in ipairs(SS.LISTENING_EFFECTS) do
        if SS.isOptionEnabled(effect.option, effect.default) then
            local stat = CharacterStat[effect.stat]
            if stat and stats:add(stat, -effect.amount) then
                changed = true
                HaloTextHelper.addTextWithArrow(player,
                    getText("IGUI_HaloNote_" .. effect.halo), "[br/]", false,
                    HaloTextHelper.getGoodColor())
            end
        end
    end
    if changed then
        local moodles = player:getMoodles()
        if moodles then moodles:Update() end
    end
    return changed
end

print("[SurvivorsSong] shared loaded build=" .. SS.BUILD)
