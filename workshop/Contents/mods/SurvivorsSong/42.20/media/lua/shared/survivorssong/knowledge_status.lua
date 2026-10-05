-- Journal's server-only multiplier admission adapted to a persistent CD window.
-- Replies are bound to request, character, device and exact knowledge payload.
require "survivorssong/survivorssong_shared"
local SS = SurvivorsSong
if SS._knowledgeStatusInstalled then return end
SS._knowledgeStatusInstalled = true
local pending, answers = {}, {}
local rate = setmetatable({}, { __mode = "k" })
local nextRequest = 0
local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value < math.huge and value == math.floor(value)
end
local function current(entry, player, device)
    return entry and entry.player == player and entry.device == device
        and entry.actor == SS.getActionActorKey(player)
        and entry.signature == SS.getKnowledgePayloadSignature(device)
        and SS.findDeviceById(player, SS.safeItemId(device)) == device
        and SS.isKnowledgeActionContextValid(player, device, "restore")
end
function SS.getServerMultiplierReadStatus(player, device)
    local answer = answers[SS.safeItemId(device)]
    local now = getTimestampMs()
    if not current(answer, player, device) or now < answer.at or now - answer.at >= 1000 then return nil end
    return answer.readable
end
function SS.hasServerMultiplierRepair(player, device)
    return SS.getServerMultiplierReadStatus(player, device) == true
end
function SS.requestMultiplierReadStatus(player, device)
    if not isClient() or not SS.isKnowledgeActionContextValid(player, device, "restore") then return end
    local id, now = SS.safeItemId(device), getTimestampMs()
    if not id then return end
    local request = pending[id]
    if current(request, player, device) and now >= request.at and now - request.at < 1000 then return end
    nextRequest = nextRequest + 1
    request = { player = player, device = device, actor = SS.getActionActorKey(player),
        signature = SS.getKnowledgePayloadSignature(device), requestId = nextRequest, at = now }
    pending[id] = request
    sendClientCommand(player, SS.MODULE, "readStatus", {
        itemId = id, requestId = request.requestId, recipientKey = request.actor,
    })
end
local function onClientCommand(module, command, player, args)
    if not isServer() or module ~= SS.MODULE or command ~= "readStatus" or not player
        or type(args) ~= "table" or not integer(args.requestId) or not integer(args.itemId)
        or args.recipientKey ~= SS.getActionActorKey(player) then return end
    local now = getTimestampMs()
    if rate[player] and now >= rate[player] and now - rate[player] < 250 then return end
    rate[player] = now
    local device = SS.findDeviceById(player, args.itemId)
    if not device or not SS.isKnowledgeActionContextValid(player, device, "restore") then return end
    sendServerCommand(player, SS.MODULE, "readStatus", {
        onlineID = player:getOnlineID(), recipientKey = SS.getActionActorKey(player),
        itemId = args.itemId, requestId = args.requestId,
        signature = SS.getKnowledgePayloadSignature(device),
        readable = SS.getRestoreDelta(player, device).multiplierRepair == true,
    })
end
local function onServerCommand(module, command, args)
    if not isClient() or module ~= SS.MODULE or command ~= "readStatus" or type(args) ~= "table"
        or not integer(args.onlineID) or not integer(args.itemId) or not integer(args.requestId) then return end
    local player = getPlayerByOnlineID(args.onlineID)
    local request = pending[args.itemId]
    if not player or not player:isLocalPlayer() or player:isDead() or not request
        or request.requestId ~= args.requestId or args.recipientKey ~= request.actor
        or args.signature ~= request.signature or not current(request, player, request.device) then return end
    pending[args.itemId] = nil
    request.at = getTimestampMs()
    request.readable = args.readable == true
    answers[args.itemId] = request
end
Events.OnClientCommand.Add(onClientCommand)
Events.OnServerCommand.Add(onServerCommand)
Events.OnDisconnect.Add(function() pending = {}; answers = {} end)
