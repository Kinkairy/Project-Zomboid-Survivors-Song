-- Survivor's Song R2.2: server-authoritative knowledge-action progress view.
-- Adapted from Personal Journal 1.3.2. This is presentation telemetry only:
-- it cannot award XP, complete the action, or supply a client-authored workload.
require "survivorssong/survivorssong_shared"
local SS = SurvivorsSong
SS.PROGRESS_VIEW_SCALE = 1000000
local POLL_MS, STALE_MS = 500, 3000
local views = setmetatable({}, { __mode = "k" })
SS._progressKeyCounter = SS._progressKeyCounter or 0

local function now() return getTimestampMs() end
local function finite(n)
    return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end
local function integer(n) return finite(n) and n == math.floor(n) end

function SS.isProgressKey(key)
    return type(key) == "string" and #key > 0 and #key <= 96
end

function SS.newProgressKey()
    SS._progressKeyCounter = SS._progressKeyCounter + 1
    return tostring(now()) .. ":" .. tostring(SS._progressKeyCounter)
end

function SS.beginProgressView(action, label)
    if not isClient() then return end
    views[action.character] = action
    local initial = 0
    if action.plan and action.plan.pages and action.plan.pages > 0 then
        initial = action.plan.startPage / action.plan.pages
    end
    action.progressView = { value = initial, sequence = 0, phase = "waiting",
        label = label, nextPoll = 0, receivedAt = nil }
    action.action:setTime(SS.PROGRESS_VIEW_SCALE)
    action:setJobDelta(initial)
    action.item:setJobDelta(initial)
end

function SS.endProgressView(action)
    if action and views[action.character] == action then views[action.character] = nil end
    if action then action.progressView = nil end
end

local function setLabel(action, key)
    local v = action.progressView
    local label = key and getText(key, v.label) or v.label
    if v.displayLabel ~= label then
        v.displayLabel = label
        action.item:setJobType(label)
        local container = action.item:getContainer()
        if container then container:setDrawDirty(true) end
    end
end

local function draw(action)
    local v = action.progressView
    local progress = v.value
    -- BaseAction may locally advance before Lua update. Pin both visible bars
    -- back to the last real server sample on every client frame.
    action:setJobDelta(progress)
    action.item:setJobDelta(progress)
    UIManager.getProgressBar(action.character:getPlayerNum()):setValue(progress)

    local age = now() - (v.receivedAt or 0)
    if v.phase == "complete" then
        setLabel(action, "IGUI_SurvivorsSong_WaitActionDone")
    elseif v.phase == "applying" then
        setLabel(action, "IGUI_SurvivorsSong_Applying")
    elseif not v.receivedAt or age > STALE_MS or age < 0 then
        setLabel(action, "IGUI_SurvivorsSong_WaitServer")
    elseif progress >= 1 then
        setLabel(action, "IGUI_SurvivorsSong_WaitActionDone")
    else
        setLabel(action, nil)
    end
end

function SS.updateProgressView(action)
    local v = action.progressView
    if not v or views[action.character] ~= action then return end
    local t = now()
    if t >= v.nextPoll or t < v.nextPoll - POLL_MS then
        v.nextPoll = t + POLL_MS
        local ok, err = pcall(sendClientCommand, action.character, SS.MODULE, "progress", {
            itemId = action.item:getID(), kind = action.kind,
            progressKey = action.progressKey,
        })
        if not ok and not v.warningLogged then
            v.warningLogged = true
            print("[SurvivorsSong] progress request failed: " .. tostring(err))
        end
    end
    draw(action)
end

function SS.publishActionProgress(action, phase)
    if not isServer() or not action or not SS.isProgressKey(action.progressKey) then return end
    local ok, err = pcall(function()
        local value = phase == "complete" and 1 or action.netAction:getProgress()
        if not finite(value) then return end
        if phase ~= "complete" and action.plan and action.plan.pages
            and action.plan.pages > 0 then
            value = (action.plan.startPage
                + (action.plan.pages - action.plan.startPage) * value)
                / action.plan.pages
        end
        action.progressSequence = (action.progressSequence or 0) + 1
        sendServerCommand(action.character, SS.MODULE, "progress", {
            onlineID = action.character:getOnlineID(),
            recipientKey = action.recipientKey,
            itemId = action.item:getID(),
            kind = action.kind,
            progressKey = action.progressKey,
            sequence = action.progressSequence,
            phase = phase,
            progress = math.max(0, math.min(1, value)),
        })
    end)
    if not ok and not action.progressWarningLogged then
        action.progressWarningLogged = true
        print("[SurvivorsSong] progress view send failed: " .. tostring(err))
    end
end

local function receiveRequest(module, command, player, args)
    if not isServer() or module ~= SS.MODULE or command ~= "progress"
        or not player or type(args) ~= "table" then return end
    local item = SS.findDeviceById(player, args.itemId)
    local action = item and SS._activeKnowledgeActions[item] or nil
    if not action or action.character ~= player or action.rejected
        or args.progressKey ~= action.progressKey or args.kind ~= action.kind
        or tonumber(args.itemId) ~= action.item:getID() then return end

    local t = now()
    if action.lastProgressReply and t >= action.lastProgressReply
        and t - action.lastProgressReply < POLL_MS then return end
    action.lastProgressReply = t
    SS.publishActionProgress(action, "running")
end

local phaseRank = { running = 1, applying = 2, complete = 3,
    rejected = 3, cancelled = 3 }

local function receiveReply(module, command, args)
    if not isClient() or module ~= SS.MODULE or command ~= "progress"
        or type(args) ~= "table" or not integer(args.onlineID) or args.onlineID < 0 then return end
    local player = getPlayerByOnlineID(args.onlineID)
    local action = player and views[player]
    local v = action and action.progressView
    if not v or not player:isLocalPlayer() or player:isDead()
        or args.recipientKey ~= SS.getActionActorKey(player)
        or args.progressKey ~= action.progressKey or args.kind ~= action.kind
        or tonumber(args.itemId) ~= action.item:getID()
        or SS.findDeviceById(player, args.itemId) ~= action.item
        or not integer(args.sequence) or args.sequence <= v.sequence
        or not phaseRank[args.phase] or not finite(args.progress)
        or args.progress < 0 or args.progress > 1 then return end
    if (phaseRank[v.phase] or 0) > phaseRank[args.phase] then return end
    if args.progress < v.value then return end

    v.sequence, v.receivedAt, v.phase = args.sequence, now(), args.phase
    v.value = args.progress
    if args.phase == "rejected" or args.phase == "cancelled" then
        action.rejected = true
    end
end

Events.OnClientCommand.Add(receiveRequest)
Events.OnServerCommand.Add(receiveReply)
