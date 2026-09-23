-- Survivor's Song rc0.4: server-authoritative background knowledge sessions.
-- Recording/restoring no longer occupies the character TimedAction queue.
-- Timing still advances in the same units as BaseAction: GameTime multiplier
-- per tick. The physical CD owns interruption checkpoints; while loaded, the
-- device mirrors that checkpoint because the player-visible disc is replaced
-- by the native RecordedMedia carrier.
require "survivorssong/survivorssong_shared"

local SS = SurvivorsSong
local STATE_PUSH_MS = 500

SS._knowledgeSessions = SS._knowledgeSessions or {}
SS._knowledgeSessionByPlayer = SS._knowledgeSessionByPlayer or setmetatable({}, { __mode = "k" })
SS._clientKnowledgeSessions = SS._clientKnowledgeSessions or {}
SS._clientKnowledgePending = SS._clientKnowledgePending or {}
SS._clientKnowledgeSessionByPlayer = SS._clientKnowledgeSessionByPlayer
    or setmetatable({}, { __mode = "k" })

local function nowMs()
    return getTimestampMs()
end

local function clamp01(value)
    return math.max(0, math.min(1, tonumber(value) or 0))
end

local function authoritative()
    return isServer() or not isClient()
end

local function deviceId(device)
    if not device then return nil end
    local ok, id = pcall(function() return device:getID() end)
    if not ok then return nil end
    return tonumber(id)
end

local function labelFor(kind)
    return getText(kind == "record"
        and "ContextMenu_SurvivorsSong_RecordingCD"
        or "ContextMenu_SurvivorsSong_RestoringCD")
end

local function markItem(device, kind, progress)
    if not device then return end
    device:setJobType(labelFor(kind))
    device:setJobDelta(clamp01(progress))
    local container = device:getContainer()
    if container then container:setDrawDirty(true) end
end

local function clearItem(device)
    if not device then return end
    device:setJobDelta(0)
    device:setJobType("")
    local container = device:getContainer()
    if container then container:setDrawDirty(true) end
end

local function hasForegroundTimedAction(player)
    if not player or not ISTimedActionQueue
        or not ISTimedActionQueue.isPlayerDoingAction then
        return false
    end
    return ISTimedActionQueue.isPlayerDoingAction(player) == true
end

local function setOverheadProgress(player, value)
    if isServer() or not player or not player:isLocalPlayer()
        or hasForegroundTimedAction(player) then
        return
    end
    local ok, bar = pcall(function()
        return UIManager.getProgressBar(player:getPlayerNum())
    end)
    if ok and bar then bar:setValue(clamp01(value)) end
end

local function clearOverheadProgress(player)
    if isServer() or not player or not player:isLocalPlayer()
        or hasForegroundTimedAction(player) then
        return
    end
    local ok, bar = pcall(function()
        return UIManager.getProgressBar(player:getPlayerNum())
    end)
    if ok and bar then bar:setValue(0) end
end

local function sessionProgress(session)
    if not session then return 0 end
    if session.duration <= 0 then return 1 end
    local localProgress = clamp01(session.elapsed / session.duration)
    return clamp01((session.startPage
        + (session.pages - session.startPage) * localProgress)
        / session.pages)
end

local function sessionPage(session)
    if not session then return 0 end
    local progress = session.duration > 0
        and clamp01(session.elapsed / session.duration) or 1
    return math.max(session.startPage, math.min(session.pages,
        session.startPage
            + math.floor((session.pages - session.startPage)
                * progress + 0.000001)))
end

local function syncDevice(device)
    if device and isServer() then device:syncItemFields() end
end

local function pushState(session, phase, force)
    if not session then return end
    local t = nowMs()
    if not force and session.lastPushMs
        and t >= session.lastPushMs
        and t - session.lastPushMs < STATE_PUSH_MS then
        return
    end
    session.lastPushMs = t
    local progress = sessionProgress(session)
    if isServer() then
        sendServerCommand(session.player, SS.MODULE, "knowledgeState", {
            onlineID = session.player:getOnlineID(),
            itemId = session.itemId,
            kind = session.kind,
            phase = phase or session.phase,
            progress = progress,
        })
    elseif not isClient() then
        markItem(session.device, session.kind, progress)
        setOverheadProgress(session.player, progress)
    end
end

local function saveCheckpoint(session, publish)
    if not session or not session.device then return end
    local page = sessionPage(session)
    if page <= session.lastPage then return end
    session.lastPage = page
    SS.saveKnowledgeProgress(session.device, session.kind,
        session.actor, page, session.pages)
    if publish ~= false then syncDevice(session.device) end
end

local function removeSession(session)
    if not session then return end
    if SS._knowledgeSessions[session.device] == session then
        SS._knowledgeSessions[session.device] = nil
    end
    if SS._knowledgeSessionByPlayer[session.player] == session then
        SS._knowledgeSessionByPlayer[session.player] = nil
    end
end

local function finishSession(session, phase, keepCheckpoint)
    if not session then return end
    if keepCheckpoint then saveCheckpoint(session) end
    removeSession(session)
    pushState(session, phase, true)
    if not isServer() then
        clearItem(session.device)
        clearOverheadProgress(session.player)
    end
end

function SS.getKnowledgeSession(device)
    local id = deviceId(device)
    if not id then return nil end
    if isClient() then
        return SS._clientKnowledgeSessions[id]
            or SS._clientKnowledgePending[id]
    end
    return SS._knowledgeSessions[device]
end

function SS.hasKnowledgeSession(device)
    return SS.getKnowledgeSession(device) ~= nil
end

function SS.startKnowledgeSession(player, device, kind)
    if not authoritative() or not player or not device
        or (kind ~= "record" and kind ~= "restore") then
        return false
    end
    if SS._activeMediaActions and SS._activeMediaActions[device] then return false end

    local existing = SS._knowledgeSessions[device]
    if existing then return existing.player == player and existing.kind == kind end
    if SS._knowledgeSessionByPlayer[player] then return false end
    if not SS.isKnowledgeActionContextValid(player, device, kind) then return false end

    local delta = kind == "restore"
        and SS.getRestoreDelta(player, device)
        or SS.getRecordDelta(player, device)
    if delta.skills <= 0 then return false end
    local recordPlan = kind == "record" and SS.makeRecordPlan(player, device, delta) or nil
    if kind == "record" and not recordPlan then return false end
    local pages = SS.getActionPageCount(kind, delta)
    local actor = SS.getActionActorKey(player)
    local startPage = SS.getSavedKnowledgePage(device, kind, actor, pages)
    local totalTime = SS.getActionTime(kind, player, device, delta)
    local duration = SS.getRemainingActionTime(totalTime, startPage, pages)

    local session = {
        player = player,
        device = device,
        itemId = deviceId(device),
        kind = kind,
        actor = actor,
        recordPlan = recordPlan,
        pages = pages,
        startPage = startPage,
        lastPage = startPage,
        duration = duration,
        elapsed = 0,
        phase = "running",
        lastPushMs = nil,
    }
    SS._knowledgeSessions[device] = session
    SS._knowledgeSessionByPlayer[player] = session

    local data = SS.getDeviceData(device)
    if data and data:isPlayingMedia() then data:StopPlayMedia() end
    pushState(session, "running", true)
    return true
end

function SS.stopKnowledgeSession(player, device, reason)
    if not authoritative() or not device then return false end
    local session = SS._knowledgeSessions[device]
    if not session or (player and session.player ~= player) then return false end
    saveCheckpoint(session)
    finishSession(session, reason or "stopped", false)
    return true
end

function SS.stopKnowledgeSessionForDevice(device, reason)
    if not authoritative() or not device then return false end
    local session = SS._knowledgeSessions[device]
    if not session then return false end
    saveCheckpoint(session)
    finishSession(session, reason or "stopped", false)
    return true
end

function SS.requestKnowledgeSession(player, device, kind)
    if not player or not device then return false end
    local id = deviceId(device)
    if not id then return false end

    if isClient() then
        if SS._clientKnowledgeSessions[id] or SS._clientKnowledgePending[id] then
            return false
        end
        local delta = kind == "restore"
            and SS.getRestoreDelta(player, device)
            or SS.getRecordDelta(player, device)
        local pages = SS.getActionPageCount(kind, delta)
        local savedPage = SS.getSavedKnowledgePage(device, kind,
            SS.getActionActorKey(player), pages)
        SS._clientKnowledgePending[id] = {
            itemId = id,
            kind = kind,
            phase = "waiting",
            progress = pages > 0 and savedPage / pages or 0,
        }
        sendClientCommand(player, SS.MODULE, "knowledgeStart", {
            itemId = id,
            kind = kind,
        })
        return true
    end

    return SS.startKnowledgeSession(player, device, kind)
end

function SS.requestKnowledgeSessionStop(player, device)
    if not player or not device then return false end
    local id = deviceId(device)
    if not id then return false end
    if isClient() then
        local state = SS._clientKnowledgeSessions[id]
            or SS._clientKnowledgePending[id]
        sendClientCommand(player, SS.MODULE, "knowledgeStop", {
            itemId = id,
            kind = state and state.kind or "",
        })
        return true
    end
    return SS.stopKnowledgeSession(player, device, "stopped")
end

local function completeSession(session)
    local ok, applied = pcall(function()
        if session.kind == "record" then
            return SS.commitRecord(session.player, session.device, session.recordPlan)
        end
        return SS.applyRestore(session.player, session.device)
    end)

    if ok and applied then
        SS.clearKnowledgeProgress(session.device)
        syncDevice(session.device)
        session.elapsed = session.duration
        finishSession(session, "complete", false)
        return
    end

    -- A restore can become unnecessary while it runs if another mechanic
    -- grants the missing XP. Treat that as a clean completion rather than
    -- keeping a 100% session alive forever.
    if ok and session.kind == "restore"
        and SS.isKnowledgeActionContextValid(session.player, session.device, session.kind)
        and SS.getRestoreDelta(session.player, session.device).skills <= 0 then
        SS.clearKnowledgeProgress(session.device)
        syncDevice(session.device)
        session.elapsed = session.duration
        finishSession(session, "complete", false)
        return
    end

    saveCheckpoint(session)
    finishSession(session, "rejected", false)
end

local function authoritativeTick()
    if not authoritative() then return end
    local multiplier = tonumber(getGameTime():getMultiplier()) or 0
    if multiplier < 0 then multiplier = 0 end

    local sessions = {}
    for _, session in pairs(SS._knowledgeSessions) do
        sessions[#sessions + 1] = session
    end

    -- B42.20 has no server OnPlayerDisconnect(ed) Lua event. Use the
    -- engine's online-player list before advancing any authoritative session.
    local online
    if isServer() and #sessions > 0 then
        online = {}
        local players = getOnlinePlayers()
        for index = 0, players:size() - 1 do online[players:get(index)] = true end
    end

    for _, session in ipairs(sessions) do
        if SS._knowledgeSessions[session.device] == session then
            local player = session.player
            local device = session.device

            -- Ownership loss is terminal for this in-memory session. The
            -- mirrored checkpoint remains on the loaded device/CD.
            if online and not online[player] then
                saveCheckpoint(session, false)
                removeSession(session)
                -- No terminal packet may be sent to a disconnected player.
            elseif not player or player:isDead()
                or SS.findDeviceById(player, session.itemId) ~= device then
                saveCheckpoint(session)
                finishSession(session, "stopped", false)
            else
                local valid = SS.isKnowledgeActionContextValid(
                    player, device, session.kind)
                    and SS.getActionActorKey(player) == session.actor
                    and (session.kind ~= "record"
                        or SS.isRecordPlanCurrent(player, device, session.recordPlan))
                if valid then
                    session.elapsed = session.elapsed + multiplier
                    saveCheckpoint(session)
                    if session.elapsed >= session.duration then
                        completeSession(session)
                    else
                        pushState(session, "running", false)
                    end
                else
                    -- rc0.4: any required-condition loss is terminal for the
                    -- in-memory session. Preserve the whole-page checkpoint on
                    -- the loaded CD and require an explicit Play to resume.
                    saveCheckpoint(session)
                    finishSession(session, "stopped", false)
                end
            end
        end
    end
end

local function sendTerminalState(player, itemId, kind, phase, progress)
    if not isServer() or not player then return end
    sendServerCommand(player, SS.MODULE, "knowledgeState", {
        onlineID = player:getOnlineID(),
        itemId = tonumber(itemId),
        kind = tostring(kind or ""),
        phase = tostring(phase or "rejected"),
        progress = clamp01(progress or 0),
    })
end

local function handleClientCommand(module, command, player, args)
    if not isServer() or module ~= SS.MODULE or not player
        or type(args) ~= "table" then
        return
    end
    if command ~= "knowledgeStart" and command ~= "knowledgeStop" then return end

    local itemId = tonumber(args.itemId)
    local kind = tostring(args.kind or "")
    local device = itemId and SS.findDeviceById(player, itemId) or nil

    if command == "knowledgeStart" then
        if not device or not SS.startKnowledgeSession(player, device, kind) then
            sendTerminalState(player, itemId, kind, "rejected", 0)
        end
        return
    end

    if not device or not SS.stopKnowledgeSession(player, device, "stopped") then
        sendTerminalState(player, itemId, kind, "stopped", 0)
    end
end

local function handleServerCommand(module, command, args)
    if not isClient() or module ~= SS.MODULE or command ~= "knowledgeState"
        or type(args) ~= "table" then
        return
    end

    local id = tonumber(args.itemId)
    local progress = tonumber(args.progress)
    local kind = tostring(args.kind or "")
    local phase = tostring(args.phase or "")
    if not id or (kind ~= "record" and kind ~= "restore")
        or not progress or progress < 0 or progress > 1 then
        return
    end

    local onlineID = tonumber(args.onlineID)
    local localPlayer = onlineID and getPlayerByOnlineID(onlineID) or nil
    if not localPlayer or not localPlayer:isLocalPlayer() then return end
    SS._clientKnowledgePending[id] = nil
    local device = SS.findDeviceById(localPlayer, id)
    local active = phase == "running"

    if active then
        local state = {
            itemId = id,
            kind = kind,
            phase = phase,
            progress = progress,
        }
        SS._clientKnowledgeSessions[id] = state
        SS._clientKnowledgeSessionByPlayer[localPlayer] = state
        if device then markItem(device, kind, progress) end
        setOverheadProgress(localPlayer, progress)
    else
        SS._clientKnowledgeSessions[id] = nil
        if SS._clientKnowledgeSessionByPlayer[localPlayer]
            and SS._clientKnowledgeSessionByPlayer[localPlayer].itemId == id then
            SS._clientKnowledgeSessionByPlayer[localPlayer] = nil
        end
        if device and not (SS._activeMediaActions
            and SS._activeMediaActions[device]) then
            clearItem(device)
        end
        clearOverheadProgress(localPlayer)
    end
end

local function refreshBackgroundOverheadProgress(player)
    if isServer() or not player or not player:isLocalPlayer()
        or hasForegroundTimedAction(player) then
        return
    end
    local state
    if isClient() then
        state = SS._clientKnowledgeSessionByPlayer[player]
    else
        state = SS._knowledgeSessionByPlayer[player]
    end
    if state then
        local value = state.progress
        if value == nil then value = sessionProgress(state) end
        setOverheadProgress(player, value)
    else
        clearOverheadProgress(player)
    end
end

local function clearDisconnectedClient()
    if isServer() then return end
    for player, state in pairs(SS._clientKnowledgeSessionByPlayer) do
        local device = SS.findDeviceById(player, state.itemId)
        if device then clearItem(device) end
        clearOverheadProgress(player)
    end
    SS._clientKnowledgeSessions = {}
    SS._clientKnowledgePending = {}
    SS._clientKnowledgeSessionByPlayer = setmetatable({}, { __mode = "k" })
end

Events.OnTick.Add(authoritativeTick)
Events.OnPlayerUpdate.Add(refreshBackgroundOverheadProgress)
Events.OnClientCommand.Add(handleClientCommand)
Events.OnServerCommand.Add(handleServerCommand)
Events.OnDisconnect.Add(clearDisconnectedClient)
