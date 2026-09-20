SurvivorsSong = SurvivorsSong or {}

local SS = SurvivorsSong

SS.VERSION = 2
SS.BUILD = "rc0.4.1"
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

-- Skill-only workload constants mirror Personal Journal 1.3.
SS.ACTION_PAGE_RATE_NUMERATOR = 7
SS.ACTION_PAGE_RATE_DENOMINATOR = 1000
SS.WRITE_BASE = 600
SS.WRITE_PER_CHANGED_SKILL = 120
SS.WRITE_PER_100_XP = 1
SS.READ_BASE = 900
SS.READ_PER_CHANGED_SKILL = 90
SS.READ_PER_100_XP = 0.8

local function finiteNumber(value)
    value = tonumber(value)
    return value ~= nil and value == value and value ~= math.huge and value ~= -math.huge
end

local function normalizeStoredSkillXp(value)
    if not finiteNumber(value) then return 0 end
    return math.floor(math.max(0, tonumber(value)) * 1000 + 0.5) / 1000
end

local function safeFullType(item)
    if not item then return nil end
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
    return safeFullType(item) == SS.CD_PLAYER_TYPE
        and (type(instanceof) ~= "function" or instanceof(item, "Radio"))
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
        and not SS.isKnowledgeCD(item)
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

function SS.getRecoveryRatio()
    return SS.getOptionNumber("RecoveryPercent", 100, 50, 100) / 100
end

function SS.getRecoverableSkillXp(savedXp)
    return normalizeStoredSkillXp((tonumber(savedXp or 0) or 0)
        * SS.getRecoveryRatio())
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

local function characterName(player)
    if not player then return "Unknown" end
    local ok, desc = pcall(function() return player:getDescriptor() end)
    if ok and desc then
        local first = tostring(desc:getForename() or "")
        local last = tostring(desc:getSurname() or "")
        local name = (first .. " " .. last):gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then return name end
    end
    local okDisplay, display = pcall(function() return player:getDisplayName() end)
    if okDisplay and display and tostring(display) ~= "" then return tostring(display) end
    return "Unknown"
end

local function username(player)
    if not player then return "" end
    local ok, value = pcall(function() return player:getUsername() end)
    if ok and value then return tostring(value) end
    return ""
end

function SS.getActionActorKey(player)
    if not player then return "" end
    local descId = ""
    local okDesc, desc = pcall(function() return player:getDescriptor() end)
    if okDesc and desc then
        local okId, value = pcall(function() return desc:getID() end)
        if okId and value ~= nil then descId = tostring(value) end
    end
    return table.concat({ username(player), descId, characterName(player) }, "\31")
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

function SS.getGameDateTimeStamp()
    -- Same timestamp format as Personal Journal 1.3.2.
    local gameTime = getGameTime and getGameTime() or nil
    if not gameTime then return nil end
    local timeOfDay = tonumber(gameTime:getTimeOfDay()) or 0
    local totalMinutes = math.floor((timeOfDay * 60) + 0.0001) % 1440
    local hour = math.floor(totalMinutes / 60)
    local minute = totalMinutes % 60
    return string.format("%04d/%02d/%02d %02d:%02d",
        tonumber(gameTime:getYear()) or 0,
        (tonumber(gameTime:getMonth()) or 0) + 1,
        (tonumber(gameTime:getDay()) or 0) + 1,
        hour, minute)
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
    if safeFullType(item) ~= SS.RETAIL_CD_TYPE or SS.isRecordedRetailCD(item) then
        return false
    end
    local md = item:getModData()
    return md and tonumber(md.SS_version) == SS.VERSION
        and tostring(md.SS_skills or "") ~= ""
end

function SS.getSavedSkills(item)
    if not SS.isKnowledgeCD(item) then return {} end
    return SS.decodeSkills(item:getModData().SS_skills)
end

function SS.getSongTooltip(item)
    if not SS.isKnowledgeCD(item) then return nil end
    local recordedAt = tostring(item:getModData().SS_recordedAt or "")
    if recordedAt == "" then return nil end
    return getText(SS.RECORDED_AT_TEXT_KEY, recordedAt)
end

function SS.canUseKnowledgeRecord(player, itemOrDevice)
    if not player then return false end
    local savedUser = ""
    if SS.isKnowledgeCD(itemOrDevice) then
        savedUser = tostring(itemOrDevice:getModData().SS_authorUser or "")
    elseif SS.isCDPlayer(itemOrDevice) and SS.getLoadedMode(itemOrDevice) == SS.MODE_SONG then
        savedUser = tostring(itemOrDevice:getModData().SS_loadedAuthorUser or "")
    end
    local currentUser = username(player)
    return savedUser == "" or currentUser == "" or savedUser == currentUser
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
    return SS.decodeSkills(device:getModData().SS_loadedSkills)
end

function SS.getLoadedSongName(device)
    if SS.getLoadedMode(device) ~= SS.MODE_SONG then return nil end
    return SS.getSongName(device:getModData().SS_loadedAuthorName)
end

function SS.makeEjectedCD(device)
    local mode = SS.getLoadedMode(device)
    if not mode then return nil end

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
        md.SS_version = SS.VERSION
        md.SS_skills = tostring(source.SS_loadedSkills or "")
        md.SS_authorName = tostring(source.SS_loadedAuthorName or "")
        md.SS_authorUser = tostring(source.SS_loadedAuthorUser or "")
        md.SS_recordedAt = tostring(source.SS_loadedRecordedAt or "")
        SS.refreshSongPresentation(item)
    end
    return item
end

local function getPerkId(perk)
    if not perk then return nil end
    local ok, id = pcall(function() return perk:getId() end)
    if not ok or id == nil then return nil end
    id = tostring(id)
    if id == "" then return nil end
    return id
end

function SS.captureSkills(player)
    local result = {}
    if not player or not player:getXp() then return result end
    local xpObject = player:getXp()
    local maxIndex = PerkFactory.Perks.getMaxIndex()
    for index = 0, maxIndex - 1 do
        local perk = PerkFactory.Perks.fromIndex(index)
        if perk and perk ~= PerkFactory.Perks.None then
            local perkId = getPerkId(perk)
            if perkId then
                local okXp, xp = pcall(function() return xpObject:getXP(perk) end)
                local effectiveXp = okXp and tonumber(xp) or 0
                local level = tonumber(player:getPerkLevel(perk) or 0) or 0
                if level > 0 then
                    local okLevelXp, levelXp = pcall(function()
                        return PerkFactory.getPerk(perk):getTotalXpForLevel(level)
                    end)
                    if okLevelXp and finiteNumber(levelXp) then
                        effectiveXp = math.max(effectiveXp, tonumber(levelXp))
                    end
                end
                if effectiveXp > 0 then result[perkId] = effectiveXp end
            end
        end
    end
    return result
end

function SS.encodeSkills(skills)
    local keys = {}
    for perkId, xp in pairs(skills or {}) do
        if tostring(perkId or "") ~= "" and normalizeStoredSkillXp(xp) > 0 then
            keys[#keys + 1] = tostring(perkId)
        end
    end
    table.sort(keys)
    local out = {}
    for _, perkId in ipairs(keys) do
        out[#out + 1] = perkId .. "=" .. tostring(normalizeStoredSkillXp(skills[perkId]))
    end
    return table.concat(out, ";")
end

function SS.decodeSkills(encoded)
    local result = {}
    if encoded == nil or tostring(encoded) == "" then return result end
    for token in string.gmatch(tostring(encoded), "[^;]+") do
        local equal = string.find(token, "=", 1, true)
        if equal then
            local perkId = string.sub(token, 1, equal - 1)
            local xp = normalizeStoredSkillXp(string.sub(token, equal + 1))
            if perkId ~= "" and xp > 0 then result[perkId] = xp end
        end
    end
    return result
end

local function countSkillMap(skills)
    local count, totalXp = 0, 0
    for _, xp in pairs(skills or {}) do
        local value = normalizeStoredSkillXp(xp)
        if value > 0 then
            count = count + 1
            totalXp = totalXp + value
        end
    end
    return count, totalXp
end

function SS.getRecordDelta(player, device)
    local result = { xp = 0, skills = 0, snapshot = {} }
    if not player or SS.getLoadedMode(device) ~= SS.MODE_BLANK then return result end
    result.snapshot = SS.captureSkills(player)
    result.skills, result.xp = countSkillMap(result.snapshot)
    return result
end

local function resolvePerk(perkId)
    local perk = PerkFactory.Perks.FromString(tostring(perkId or ""))
    if perk and perk ~= PerkFactory.Perks.None then return perk end
    return nil
end

function SS.getRestoreDelta(player, device)
    local result = { xp = 0, skills = 0 }
    if not player or SS.getLoadedMode(device) ~= SS.MODE_SONG then return result end
    local current = SS.captureSkills(player)
    for perkId, savedXp in pairs(SS.getLoadedSkills(device)) do
        local currentXp = tonumber(current[perkId] or 0) or 0
        local target = SS.getRecoverableSkillXp(savedXp)
        if resolvePerk(perkId)
            and normalizeStoredSkillXp(target) > normalizeStoredSkillXp(currentXp) then
            result.xp = result.xp + (target - currentXp)
            result.skills = result.skills + 1
        end
    end
    return result
end

function SS.writeSongToLoadedDevice(player, device)
    if not player or SS.getLoadedMode(device) ~= SS.MODE_BLANK then return false end
    local delta = SS.getRecordDelta(player, device)
    if delta.skills <= 0 then return false end

    local md = device:getModData()
    md.SS_loadedMode = SS.MODE_SONG
    md.SS_loadedVersion = SS.VERSION
    md.SS_loadedSkills = SS.encodeSkills(delta.snapshot)
    md.SS_loadedAuthorName = characterName(player)
    md.SS_loadedAuthorUser = username(player)
    local recordedAt = SS.getGameDateTimeStamp()
    if recordedAt then md.SS_loadedRecordedAt = recordedAt end
    return true
end

local function canRecordContext(player, device)
    if not SS.isSkillXpEnabled() then return false end
    if not player or player:isDead() or not SS.isCDPlayer(device) then return false end
    if not SS.isKnowledgeDeviceActiveForPlayer(player, device) then return false end
    local data = SS.getDeviceData(device)
    if not data or not data:hasMedia() or tonumber(data:getMediaType()) ~= 0 then return false end
    if SS.getLoadedMode(device) ~= SS.MODE_BLANK then return false end
    if not SS.isDeviceTurnedOn(device) or not SS.hasUsablePower(device) then return false end
    return SS.hasHeadphones(device) and SS.hasMicrophone(player)
end

local function canRestoreContext(player, device)
    if not SS.isSkillXpEnabled() then return false end
    if not player or player:isDead() or not SS.isCDPlayer(device) then return false end
    if not SS.isKnowledgeDeviceActiveForPlayer(player, device) then return false end
    local data = SS.getDeviceData(device)
    if not data or not data:hasMedia() or tonumber(data:getMediaType()) ~= 0 then return false end
    if SS.getLoadedMode(device) ~= SS.MODE_SONG then return false end
    if not SS.isDeviceTurnedOn(device) or not SS.hasUsablePower(device) then return false end
    return SS.hasHeadphones(device) and SS.canUseKnowledgeRecord(player, device)
end

function SS.canRecord(player, device)
    return canRecordContext(player, device)
        and SS.getRecordDelta(player, device).skills > 0
end

function SS.canRestore(player, device)
    return canRestoreContext(player, device)
        and SS.getRestoreDelta(player, device).skills > 0
end

function SS.isKnowledgeActionContextValid(player, device, kind)
    if kind == "record" then return canRecordContext(player, device) end
    if kind == "restore" then return canRestoreContext(player, device) end
    return false
end

function SS.commitRecord(player, device)
    if not SS.canRecord(player, device) then return false end
    return SS.writeSongToLoadedDevice(player, device)
end

function SS.applyRestore(player, device)
    if not SS.canRestore(player, device) then return false end
    local xpObject = player:getXp()
    local changed = false
    for perkId, savedXp in pairs(SS.getLoadedSkills(device)) do
        local perk = resolvePerk(perkId)
        if perk then
            local current = tonumber(xpObject:getXP(perk)) or 0
            local target = SS.getRecoverableSkillXp(savedXp)
            if target > current then
                addXpNoMultiplier(player, perk, target - current)
                changed = true
            end
        end
    end
    return changed
end

function SS.getActionPageCount(kind, delta)
    delta = delta or {}
    local xpBlocks = math.ceil(math.max(0, tonumber(delta.xp or 0) or 0) / 100)
    local units
    if kind == "restore" then
        units = SS.READ_BASE
            + ((tonumber(delta.skills or 0) or 0) * SS.READ_PER_CHANGED_SKILL)
            + (xpBlocks * SS.READ_PER_100_XP)
    else
        units = SS.WRITE_BASE
            + ((tonumber(delta.skills or 0) or 0) * SS.WRITE_PER_CHANGED_SKILL)
            + (xpBlocks * SS.WRITE_PER_100_XP)
    end
    return math.max(1, math.ceil(math.max(0, units)
        * SS.ACTION_PAGE_RATE_NUMERATOR / SS.ACTION_PAGE_RATE_DENOMINATOR))
end

local function getVanillaReadingTime(pageCount)
    local minutesPerPage = 2.0
    local okOption, configured = pcall(function()
        local option = getSandboxOptions():getOptionByName("MinutesPerPage")
        if option then return option:getValue() end
        return nil
    end)
    if okOption and tonumber(configured) and tonumber(configured) >= 0 then
        minutesPerPage = tonumber(configured)
    end

    local minutesPerDay = 30
    local okTime, configuredDay = pcall(function()
        local gameTime = getGameTime()
        return gameTime and gameTime:getMinutesPerDay() or nil
    end)
    if okTime and tonumber(configuredDay) and tonumber(configuredDay) > 0 then
        minutesPerDay = tonumber(configuredDay)
    end
    return math.max(1, pageCount * minutesPerPage * minutesPerDay * 2)
end

function SS.getActionTime(kind, player, device, delta)
    if player and player:isTimedActionInstant() then return 1 end
    local multiplierName = kind == "restore" and "RestoreTimeMultiplier" or "RecordTimeMultiplier"
    local multiplier = SS.getOptionNumber(multiplierName, 1.0, 0.1, 10.0)
    delta = delta or (kind == "restore" and SS.getRestoreDelta(player, device)
        or SS.getRecordDelta(player, device))
    local pages = SS.getActionPageCount(kind, delta)

    if kind == "restore" then
        require "TimedActions/ISReadABook"
        local view = {
            getNumberOfPages = function() return pages end,
            getSkillTrained = function() return nil end,
            getFullType = function() return "Base.Diary1" end,
            setAlreadyReadPages = function() end,
            getAlreadyReadPages = function() return 0 end,
            hasTag = function() return false end,
        }
        local minutes = getSandboxOptions():getOptionByName("MinutesPerPage"):getValue() or 2
        if minutes < 0 then minutes = 2 end
        local time = ISReadABook.getDuration({
            character = player, item = view, minutesPerPage = minutes,
        })
        return math.max(1, math.floor(time * multiplier))
    end

    return math.max(1, math.floor(getVanillaReadingTime(pages) * multiplier))
end

function SS.isKnowledgeActionValid(player, device, kind)
    if kind == "record" then return SS.canRecord(player, device) end
    if kind == "restore" then return SS.canRestore(player, device) end
    return false
end

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
