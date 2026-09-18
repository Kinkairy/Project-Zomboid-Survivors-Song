require "TimedActions/ISTimedActionQueue"
require "Hotbar/ISHotbar"
require "ISUI/ISInventoryPane"
require "ISUI/ISInventoryPaneContextMenu"
require "RadioCom/ISRadioAction"
require "RadioCom/RadioWindowModules/RWMMedia"
require "survivorssong/survivorssong_shared"
require "survivorssong/survivorssong_actions"

local SS = SurvivorsSong

local function disableOption(option, textKey)
    option.notAvailable = true
    local tooltip = ISInventoryPaneContextMenu.addToolTip()
    tooltip.description = getText(textKey)
    option.toolTip = tooltip
end

local function activeKnowledgeAction(device)
    return device and SS._activeKnowledgeActions[device] or nil
end

local function activeMediaAction(device)
    return device and SS._activeMediaActions[device] or nil
end

local function deviceBusy(device)
    return activeKnowledgeAction(device) ~= nil or activeMediaAction(device) ~= nil
end

local function activeKnowledgeForHotbarSlot(hotbar, slotIndex)
    local item = hotbar and hotbar.attachedItems
        and hotbar.attachedItems[slotIndex] or nil
    local active = item and SS.isCDPlayer(item)
        and activeKnowledgeAction(item) or nil
    if active and active.character == hotbar.chr then
        return active, item
    end
    return nil, item
end

local function activeAttachedKnowledge(hotbar)
    if not hotbar or not hotbar.attachedItems then return nil end
    for _, item in pairs(hotbar.attachedItems) do
        local active = item and SS.isCDPlayer(item)
            and activeKnowledgeAction(item) or nil
        if active and active.character == hotbar.chr then return active end
    end
    return nil
end

local function hotbarNonQueueGuardsPass(hotbar)
    if not hotbar or isGamePaused() then return false end
    local player = hotbar.chr or hotbar.character
    if not player or player:isDead() or player:isAttacking() then return false end
    local radial = getPlayerRadialMenu(hotbar.playerNum)
    return not radial or not radial:isReallyVisible()
end

-- Vanilla Hotbar rejects every shortcut while any TimedAction is queued.
-- Survivor's Song recording/restoring is intentionally long, so intercept only
-- the hotbar entry points needed to interrupt that exact knowledge action.
-- forceStop sends the normal native stop; authoritative serverStop saves the
-- current disc checkpoint before the queued equip/stow action can run.
if not SS._hotbarInterruptWrapped then
    local vanillaHotbarMouseUp = ISHotbar.onMouseUp
    function ISHotbar:onMouseUp(x, y)
        if not ISMouseDrag.dragging then
            local slotIndex = self:getSlotIndexAt(x, y)
            local active = slotIndex and slotIndex > -1
                and activeKnowledgeForHotbarSlot(self, slotIndex) or nil
            if active and hotbarNonQueueGuardsPass(self) then
                active:forceStop()
                self:activateSlot(slotIndex)
                return
            end
        end
        return vanillaHotbarMouseUp(self, x, y)
    end

    local vanillaHotbarKeyPressed = ISHotbar.onKeyPressed
    ISHotbar.onKeyPressed = function(key)
        local player = getSpecificPlayer(0)
        local hotbar = getPlayerHotbar(0)
        local slotIndex = hotbar and hotbar:getSlotForKey(key) or -1
        local active = hotbar and slotIndex and slotIndex > -1
            and activeKnowledgeForHotbarSlot(hotbar, slotIndex) or nil
        local speed = UIManager.getSpeedControls()
        local radial = getPlayerRadialMenu(0)
        if active and player and not player:isDead()
            and (not speed or speed:getCurrentGameSpeed() ~= 0)
            and not JoypadState.players[1]
            and not player:isAttacking()
            and (not radial or not radial:isReallyVisible())
            and not hotbar.radialWasVisible then
            active:forceStop()
            hotbar:activateSlot(slotIndex)
            return
        end
        return vanillaHotbarKeyPressed(key)
    end

    -- Mercenary Loadout's D-pad radio slice deliberately delegates to this
    -- vanilla guard before calling Hotbar:activateSlot(). Preserve every stock
    -- guard except the non-empty action queue when the queued action is the
    -- active Survivor's Song knowledge action on an attached CD player.
    local vanillaHotbarAllowed = ISHotbar.isAllowedToActivateSlot
    function ISHotbar:isAllowedToActivateSlot()
        if vanillaHotbarAllowed(self) then return true end
        local joypad = JoypadState.players[(self.playerNum or 0) + 1]
        local active = joypad and activeAttachedKnowledge(self) or nil
        if active and hotbarNonQueueGuardsPass(self) then
            active:forceStop()
            return true
        end
        return false
    end

    SS._hotbarInterruptWrapped = true
end

local function requestMediaAction(player, device, kind, disc)
    ISTimedActionQueue.add(SurvivorsSongMediaAction:new(player, device, kind, disc))
end

local function requestKnowledgeAction(player, device, kind)
    ISTimedActionQueue.add(SurvivorsSongKnowledgeAction:new(player, device, kind))
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

        local active = activeKnowledgeAction(self.device)
        if active then
            active:forceStop()
            return
        end

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
            local active = activeKnowledgeAction(self.device)
            if active then
                active:forceStop()
                return
            end

            local allowed = kind == "record"
                and SS.canRecord(self.player, self.device)
                or SS.canRestore(self.player, self.device)
            if not allowed then return end

            if self:doWalkTo() then
                requestKnowledgeAction(self.player, self.device, kind)
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

    -- A blank/song disc never enters native RecordedMedia playback.
    if self.deviceData:isPlayingMedia() then
        self.deviceData:StopPlayMedia()
    end

    self.itemDropBox:setStoredItemFake(self.cdTex)

    local active = activeKnowledgeAction(self.device)
    if active then
        self.toggleOnOffButton:setEnable(true)
        self.toggleOnOffButton:setTitle(self.textStop)
    else
        local allowed = canStartCustom(self.player, self.device)
        self.toggleOnOffButton:setEnable(allowed == true)
        self.toggleOnOffButton:setTitle(self.textPlay)
    end

    if active then
        local text = active.kind == "record"
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
            if activeKnowledgeAction(self.device) then return self.textStop end
            local allowed = canStartCustom(self.player, self.device)
            return allowed and self.textPlay or nil
        end
    end
    return vanillaGetAPrompt(self)
end

local function collectInsertableCDs(player)
    local medias = {}
    local inventory = player and player:getInventory() or nil
    if not inventory then return medias end

    local retail = inventory:FindAll(SS.RETAIL_CD_TYPE)
    for index = 0, retail:size() - 1 do
        medias[#medias + 1] = retail:get(index)
    end

    return medias
end

local vanillaGetBPrompt = RWMMedia.getBPrompt
function RWMMedia:getBPrompt()
    local vanillaPrompt = vanillaGetBPrompt(self)
    if vanillaPrompt or not self.device or not SS.isCDPlayer(self.device)
        or self.deviceData:hasMedia() then
        return vanillaPrompt
    end

    -- Vanilla owns normal RecordedMedia. Blank/song discs are the same real
    -- Base.Disc_Retail type with no native RecordedMedia index.
    local inventory = self.player and self.player:getInventory() or nil
    local discs = inventory and inventory:FindAll(SS.RETAIL_CD_TYPE) or nil
    if discs then
        for index = 0, discs:size() - 1 do
            local disc = discs:get(index)
            if SS.isBlankCD(disc) or SS.isKnowledgeCD(disc) then
                return getText("IGUI_media_addMedia")
            end
        end
    end
    return nil
end

local vanillaJoypadDown = RWMMedia.onJoypadDown
function RWMMedia:onJoypadDown(button)
    if self.device and SS.isCDPlayer(self.device) then
        if button == Joypad.AButton and SS.getLoadedMode(self.device) ~= nil then
            self:togglePlayMedia()
            return
        end

        if button == Joypad.BButton then
            if self.deviceData:hasMedia() then
                self:removeMedia()
                return
            end

            local medias = collectInsertableCDs(self.player)
            if #medias > 0 then
                self:addMedia(medias)
                return
            end
        end
    end
    return vanillaJoypadDown(self, button)
end

-- Normal native CD playback remains vanilla-owned. Survivor's Song only keeps
-- it running until the selected game-time deadline; custom blank/song discs
-- never reach this section.
local playback = setmetatable({}, { __mode = "k" })
local playerBuffMinute = setmetatable({}, { __mode = "k" })
local lastScanMs = setmetatable({}, { __mode = "k" })

local function isNativeCDDeviceData(data)
    if not data then return false end
    local okType, mediaType = pcall(function() return data:getMediaType() end)
    return okType and tonumber(mediaType) == 0 and data:hasMedia()
end

local function beginSession(player, data)
    if not player or not isNativeCDDeviceData(data) then return nil end

    local duration = SS.getPlaybackDurationMinutes()
    local now = getGameTime():getMinutesStamp()
    local state = {
        player = player,
        mediaKey = SS.getMediaKey(data),
        deadlineMinute = duration > 0 and (now + duration) or nil,
        wasPlaying = data:isPlayingMedia(),
    }
    playback[data] = state
    return state
end

local function cancelSession(data)
    if data then playback[data] = nil end
end

-- Manual Stop remains terminal even when an extended game-time deadline exists.
local vanillaTogglePlayMedia = ISRadioAction.performTogglePlayMedia
function ISRadioAction:performTogglePlayMedia(...)
    local data = self.deviceData
    local wasPlaying = data and data:isPlayingMedia() or false
    if wasPlaying then cancelSession(data) end

    local result = vanillaTogglePlayMedia(self, ...)

    if not wasPlaying and data and data:isPlayingMedia()
        and isNativeCDDeviceData(data) then
        beginSession(self.character, data)
    end
    return result
end

local function applyBuffOncePerMinute(player, data)
    local minute = getGameTime():getMinutesStamp()
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
        if data and data:isPlayingMedia() then data:StopPlayMedia() end
        return
    end

    if not SS.isCDPlayer(item) or not isNativeCDDeviceData(data) then
        cancelSession(data)
        return
    end

    local now = getGameTime():getMinutesStamp()
    local playing = data:isPlayingMedia()
    local state = playback[data]

    if playing then
        if not state or state.mediaKey ~= SS.getMediaKey(data) then
            state = beginSession(player, data)
        else
            state.player = player
            state.wasPlaying = true
        end

        if state and state.deadlineMinute and now >= state.deadlineMinute then
            cancelSession(data)
            data:StopPlayMedia()
            return
        end

        if isAudibleNormalPlayback(item, data) then
            applyBuffOncePerMinute(player, data)
        end
        return
    end

    if not state then return end
    if not data:getIsTurnedOn() or not data:hasMedia() then
        cancelSession(data)
        return
    end

    if state.wasPlaying and state.deadlineMinute
        and now < state.deadlineMinute then
        -- Native inventory-media playback advances only while the device is
        -- actually listenable. Do not resurrect an extended session while
        -- headphones are removed, power is unavailable, or volume is muted.
        if data:getIsTurnedOn() and SS.hasUsablePower(item)
            and SS.hasHeadphones(item) and data:getDeviceVolume() > 0 then
            state.wasPlaying = false
            data:StartPlayMedia()
        else
            cancelSession(data)
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

    local inventory = player:getInventory()
    if not inventory then return end
    local items = inventory:getItems()
    for index = 0, items:size() - 1 do
        updateDevice(player, items:get(index))
    end
end
Events.OnPlayerUpdate.Add(scanPlayer)

print("[SurvivorsSong] client loaded build=" .. SS.BUILD)
