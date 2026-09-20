require "TimedActions/ISTimedActionQueue"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISToolTipInv"
require "RadioCom/ISRadioAction"
require "RadioCom/RadioWindowModules/RWMMedia"
require "survivorssong/survivorssong_shared"
require "survivorssong/survivorssong_actions"

local SS = SurvivorsSong

-- Match Personal Journal: localize names before the native visible-container
-- refresh groups them. Late server name packets are corrected only when needed.
local localSongNames = setmetatable({}, { __mode = "k" })
local function refreshVisibleSongNames(container)
    if not container then return end
    local items = container:getItems()
    if not items then return end
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        SS.refreshSongPresentation(item)
        localSongNames[item] = SS.isKnowledgeCD(item) and item:getName() or nil
    end
end

if not ISInventoryPane.SurvivorsSongPresentationInstalled then
    local vanillaRefreshContainer = ISInventoryPane.refreshContainer
    local vanillaDrawItemIcon = ISInventoryPane.drawItemIcon

    function ISInventoryPane:refreshContainer(...)
        refreshVisibleSongNames(self.inventory)
        return vanillaRefreshContainer(self, ...)
    end

    function ISInventoryPane:drawItemIcon(item, ...)
        local expected = localSongNames[item]
        if expected and item:getName() ~= expected then
            SS.refreshSongPresentation(item)
            localSongNames[item] = SS.isKnowledgeCD(item) and item:getName() or nil
        end
        return vanillaDrawItemIcon(self, item, ...)
    end

    ISInventoryPane.SurvivorsSongPresentationInstalled = true
end

-- Match Personal Journal's tooltip strategy: supply localized recorded-time
-- metadata only while vanilla ISToolTipInv renders this physical song CD.
if not ISToolTipInv.SurvivorsSongTooltipInstalled then
    local previousToolTipRender = ISToolTipInv.render

    function ISToolTipInv:render(...)
        local item = self.item
        local songTooltip = item and SS.getSongTooltip(item) or nil
        if not songTooltip then return previousToolTipRender(self, ...) end

        local previousTooltip = item:getTooltip()
        item:setTooltip(songTooltip)
        local ok, result = pcall(previousToolTipRender, self, ...)
        item:setTooltip(previousTooltip)
        if not ok then error(result) end
        return result
    end

    ISToolTipInv.SurvivorsSongTooltipInstalled = true
end

local function disableOption(option, textKey)
    option.notAvailable = true
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    tooltip.description = getText(textKey)
    option.toolTip = tooltip
end

local function activeKnowledgeSession(device)
    return device and SS.getKnowledgeSession(device) or nil
end

local function activeMediaAction(device)
    return device and SS._activeMediaActions[device] or nil
end

local function deviceBusy(device)
    return activeKnowledgeSession(device) ~= nil or activeMediaAction(device) ~= nil
end

local function requestMediaAction(player, device, kind, disc)
    ISTimedActionQueue.add(SurvivorsSongMediaAction:new(player, device, kind, disc))
end

local function requestKnowledgeSession(player, device, kind)
    return SS.requestKnowledgeSession(player, device, kind)
end

local function onFillInventoryObjectContextMenu(playerIndex, context, items)
    local player = getSpecificPlayer(playerIndex)
    if not player then return end

    local actualItems = ISInventoryPane.getActualUniqueItems(items)
    for _, item in ipairs(actualItems) do
        if SS.isCDPlayer(item) and SS.hasErasableCD(item) then
            local erase = context:addOption(getText("ContextMenu_SurvivorsSong_EraseCD"), item,
                function(device) requestMediaAction(player, device, "erase", nil) end)
            erase.itemForTexture = item
            if deviceBusy(item) then
                disableOption(erase, "ContextMenu_SurvivorsSong_DeviceBusy")
            elseif not SS.hasUsablePower(item) then
                disableOption(erase, "ContextMenu_SurvivorsSong_NeedPower")
            end
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

local vanillaVerifyItem = RWMMedia.verifyItem
function RWMMedia:verifyItem(item)
    if self.device and SS.isCDPlayer(self.device)
        and self.deviceData and not self.deviceData:hasMedia()
        and SS.getLoadedMode(self.device) == nil
        and (SS.isBlankCD(item) or SS.isKnowledgeCD(item)) then
        return true
    end
    return vanillaVerifyItem(self, item)
end

local vanillaAddMediaAux = RWMMedia.addMediaAux
function RWMMedia:addMediaAux(item)
    if self.device and SS.isCDPlayer(self.device)
        and (SS.isBlankCD(item) or SS.isKnowledgeCD(item)) then
        if self.deviceData:hasMedia() or SS.getLoadedMode(self.device) ~= nil then return end
        if item:getWorldItem()
            and not luautils.walkAdj(self.player, item:getWorldItem():getSquare(), true) then
            return
        end
        ISInventoryPaneContextMenu.transferIfNeeded(self.player, item)
        if self:doWalkTo() then
            requestMediaAction(self.player, self.device, "load", item)
        end
        return
    end
    return vanillaAddMediaAux(self, item)
end

local vanillaRemoveMedia = RWMMedia.removeMedia
function RWMMedia:removeMedia()
    if self.device and SS.isCDPlayer(self.device)
        and SS.getLoadedMode(self.device) ~= nil then
        if activeMediaAction(self.device) then return end
        if self:doWalkTo() then
            requestMediaAction(self.player, self.device, "eject", nil)
        end
        return
    end
    return vanillaRemoveMedia(self)
end

local function getCustomKind(device)
    local mode = SS.getLoadedMode(device)
    if mode == SS.MODE_BLANK then return "record" end
    if mode == SS.MODE_SONG then return "restore" end
    return nil
end

local function canStartCustom(player, device)
    local kind = getCustomKind(device)
    if kind == "record" then return SS.canRecord(player, device), kind end
    if kind == "restore" then return SS.canRestore(player, device), kind end
    return false, nil
end

local vanillaMediaToggle = RWMMedia.togglePlayMedia
function RWMMedia:togglePlayMedia()
    if self.device and SS.isCDPlayer(self.device) then
        if activeMediaAction(self.device) then return end

        local kind = getCustomKind(self.device)
        if kind then
            local session = activeKnowledgeSession(self.device)
            if session then
                SS.requestKnowledgeSessionStop(self.player, self.device)
                return
            end

            local allowed = kind == "record"
                and SS.canRecord(self.player, self.device)
                or SS.canRestore(self.player, self.device)
            if not allowed then return end

            if self:doWalkTo() then
                requestKnowledgeSession(self.player, self.device, kind)
            end
            return
        end
    end
    return vanillaMediaToggle(self)
end

local vanillaMediaUpdate = RWMMedia.update
function RWMMedia:update()
    vanillaMediaUpdate(self)
    if not self.device or not SS.isCDPlayer(self.device) then return end

    local mediaAction = activeMediaAction(self.device)
    if mediaAction then
        self.toggleOnOffButton:setEnable(false)
        return
    end

    local mode = SS.getLoadedMode(self.device)
    if not mode then return end

    self.itemDropBox:setStoredItemFake(self.cdTex)

    local session = activeKnowledgeSession(self.device)
    if session then
        self.toggleOnOffButton:setEnable(true)
        self.toggleOnOffButton:setTitle(self.textStop)
    else
        local allowed = canStartCustom(self.player, self.device)
        self.toggleOnOffButton:setEnable(allowed == true)
        self.toggleOnOffButton:setTitle(self.textPlay)
    end

    if session then
        local text = session.kind == "record"
            and getText("ContextMenu_SurvivorsSong_RecordingCD")
            or (SS.getLoadedSongName(self.device)
                or getText("ContextMenu_SurvivorsSong_RestoringCD"))
        self.lcd:setText(text .. " *** ")
        self.lcd:setDoScroll(true)
    elseif mode == SS.MODE_SONG then
        self.lcd:setText((SS.getLoadedSongName(self.device) or self.idleText) .. " *** ")
        self.lcd:setDoScroll(true)
    else
        self.lcd:setText(self.idleText)
        self.lcd:setDoScroll(true)
    end
end

local vanillaGetAPrompt = RWMMedia.getAPrompt
function RWMMedia:getAPrompt()
    if self.device and SS.isCDPlayer(self.device) then
        if activeMediaAction(self.device) then return nil end

        local mode = SS.getLoadedMode(self.device)
        if mode then
            if activeKnowledgeSession(self.device) then return self.textStop end
            local allowed = canStartCustom(self.player, self.device)
            return allowed and self.textPlay or nil
        end
    end
    return vanillaGetAPrompt(self)
end

-- Native joypad A/B routing calls our narrow toggle/load/eject adapters.
-- Blank/song discs already use Base.Disc_Retail, which vanilla enumerates.

-- Normal native CD playback remains vanilla-owned. Survivor's Song only keeps
-- it running until the selected game-time deadline; custom blank/song discs
-- never reach this section.
local playback = setmetatable({}, { __mode = "k" })
local playerBuffMinute = setmetatable({}, { __mode = "k" })
local lastScanMs = setmetatable({}, { __mode = "k" })
local customStopRequested = setmetatable({}, { __mode = "k" })

local function isNativeCDDeviceData(data)
    if not data then return false end
    local okType, mediaType = pcall(function() return data:getMediaType() end)
    return okType and tonumber(mediaType) == 0 and data:hasMedia()
end

local function itemForDevice(player, data, item)
    if not player or not data then return nil end
    if not item then
        local ok, parent = pcall(function() return data:getParent() end)
        if ok then item = parent end
    end
    if not item or not instanceof(item, "Radio") or not SS.isCDPlayer(item) then
        return nil
    end
    if item:getDeviceData() ~= data then return nil end

    local ok, owner = pcall(function() return item:getPlayer() end)
    if ok and owner == player then return item end
    return nil
end

local function beginSession(player, data, item)
    if not player or not isNativeCDDeviceData(data) then return nil end

    local duration = SS.getPlaybackDurationMinutes()
    local now = getGameTime():getMinutesStamp()
    local state = {
        player = player,
        item = itemForDevice(player, data, item),
        mediaKey = SS.getMediaKey(data),
        deadlineMinute = duration > 0 and (now + duration) or nil,
        wasPlaying = data:isPlayingMedia(),
    }
    playback[data] = state
    return state
end

local function cancelSession(data)
    if not data then return end
    local state = playback[data]
    if state then state.item = nil end
    playback[data] = nil
end

local function terminateSession(state)
    if not state or state.terminal then return end
    state.terminal = true
    state.startPending = nil
    state.item = nil
end

-- Optional mounted-address adapter; Survivor's Song remains independent of MLO.
-- Ordinary held/SP devices continue through their native methods unchanged.
local function requestNativeMedia(player, data, playing)
    local mounted = MercenaryLoadout
    if mounted and mounted.onNativeMediaRequest then mounted.onNativeMediaRequest(data, playing) end
    if mounted and mounted.requestMountedMedia
        and mounted.requestMountedMedia(player, data, playing) then return end
    if playing then data:StartPlayMedia() else data:StopPlayMedia() end
end

local function requestNativeReplay(state, data)
    state.wasPlaying = false
    state.startPending = true
    requestNativeMedia(state.player, data, true)
end

-- Manual Stop remains terminal even when an extended game-time deadline exists.
local vanillaTogglePlayMedia = ISRadioAction.performTogglePlayMedia
function ISRadioAction:performTogglePlayMedia(...)
    local data = self.deviceData
    local wasPlaying = data and data:isPlayingMedia() or false
    local result = vanillaTogglePlayMedia(self, ...)

    if isNativeCDDeviceData(data) then
        if wasPlaying then
            -- Keep a terminal session while SP drains its stop tail or MP
            -- waits for ACK. A stale true flag must not create a new deadline.
            local state = playback[data] or beginSession(self.character, data)
            terminateSession(state)
        elseif data:getIsTurnedOn() then
            local state = beginSession(self.character, data)
            if state and not data:isPlayingMedia() then
                state.startPending = true
            end
        end
    end
    return result
end

local function applyBuffOncePerMinute(player, data)
    local minute = math.floor(getGameTime():getMinutesStamp())
    if playerBuffMinute[player] == minute then return end
    playerBuffMinute[player] = minute
    SS.applyListeningEffect(player, data)
end

local function isAudibleNormalPlayback(item, data)
    return SS.isCDPlayer(item)
        and isNativeCDDeviceData(data)
        and data:isPlayingMedia()
        and data:getIsTurnedOn()
        and SS.hasUsablePower(item)
        and SS.hasHeadphones(item)
        and data:getDeviceVolume() > 0
end

local function updateDevice(player, item)
    if not item or not instanceof(item, "Radio") then return end
    local data = item:getDeviceData()

    if SS.isCDPlayer(item) and SS.getLoadedMode(item) ~= nil then
        cancelSession(data)
        if data and data:isPlayingMedia() then
            if not customStopRequested[data] then
                customStopRequested[data] = true
                requestNativeMedia(player, data, false)
            end
        elseif data then
            customStopRequested[data] = nil
        end
        return
    end
    if data then customStopRequested[data] = nil end

    if not SS.isCDPlayer(item) or not isNativeCDDeviceData(data) then
        cancelSession(data)
        return
    end

    local now = getGameTime():getMinutesStamp()
    local playing = data:isPlayingMedia()
    local state = playback[data]
    if state and state.mediaKey ~= SS.getMediaKey(data) then
        cancelSession(data)
        state = nil
    end
    -- Retain this tombstone until an explicit Play or a different disc starts
    -- a session. Clearing it on the first false poll permits a late ACK to rearm.
    if state and state.terminal then return end
    if state and state.deadlineMinute and now >= state.deadlineMinute then
        if playing or state.startPending then requestNativeMedia(player, data, false) end
        terminateSession(state)
        return
    end

    if playing then
        if not state then
            state = beginSession(player, data, item)
        else
            state.player = player
            state.item = item
            state.wasPlaying = true
            state.startPending = nil
        end

        if isAudibleNormalPlayback(item, data) then
            applyBuffOncePerMinute(player, data)
        end
        return
    end

    if not state then return end
    if not data:getIsTurnedOn() or not data:hasMedia() then
        terminateSession(state)
        return
    end
    -- A native MP Play request may take more than one scan to be acknowledged.
    if state.startPending then
        if not SS.hasUsablePower(item) or not SS.hasHeadphones(item)
            or data:getDeviceVolume() <= 0 then
            terminateSession(state)
            return
        end

        return
    end

    if state.wasPlaying and state.deadlineMinute
        and now < state.deadlineMinute then
        -- Native inventory-media playback advances only while the device is
        -- actually listenable. Do not resurrect an extended session while
        -- headphones are removed, power is unavailable, or volume is muted.
        if data:getIsTurnedOn() and SS.hasUsablePower(item)
            and SS.hasHeadphones(item) and data:getDeviceVolume() > 0 then
            requestNativeReplay(state, data)
        else
            terminateSession(state)
        end
        return
    end

    cancelSession(data)
end

local function scanPlayer(player)
    if not player or not player:isLocalPlayer() or player:isDead() then return end

    local now = getTimestampMs()
    local last = lastScanMs[player] or 0
    if now - last < 500 then return end
    lastScanMs[player] = now

    local seen = {}
    -- Once playback has begun, follow that exact native DeviceData through its
    -- parent Radio. Some mounted-item integrations keep the Radio usable but
    -- omit it from recursive inventory enumeration.
    for data, state in pairs(playback) do
        if state.player == player and not state.terminal then
            local item = itemForDevice(player, data, state.item)
                or itemForDevice(player, data, nil)
            if item then
                state.item = item
                seen[data] = true
                updateDevice(player, item)
            end
        end
    end

    local inventory = player:getInventory()
    if not inventory then return end

    -- CD players may be inside backpacks/pouches while a mounting mod keeps
    -- them usable. Scan the complete player inventory tree so playback
    -- deadlines continue to be enforced after the device leaves the root
    -- inventory level.
    local items = inventory:getAllEvalRecurse(function(item)
        return SS.isCDPlayer(item)
    end)
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local data = item and item:getDeviceData() or nil
        if not seen[data] then updateDevice(player, item) end
    end
end
Events.OnPlayerUpdate.Add(scanPlayer)
Events.OnDisconnect.Add(function()
    -- The connection has ended; drop client-only ownership and deadline caches.
    -- No play/stop request may be sent while tearing the connection down.
    playback = setmetatable({}, { __mode = "k" })
    playerBuffMinute = setmetatable({}, { __mode = "k" })
    lastScanMs = setmetatable({}, { __mode = "k" })
    customStopRequested = setmetatable({}, { __mode = "k" })
end)

print("[SurvivorsSong] client loaded build=" .. SS.BUILD)
