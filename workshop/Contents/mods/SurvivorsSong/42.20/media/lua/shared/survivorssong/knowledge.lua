-- CD carrier adapter for the generated Personal Journal 1.3.3 authority.
-- The core never touches a Diary, Journal UI, or the LegacyJournal global.
SurvivorsSong = SurvivorsSong or {}
function SurvivorsSong.installKnowledge()
local SS = SurvivorsSong
if SS._knowledgeInstalled then return end
require "survivorssong/journal_core"
local newCore = assert(SS.newJournalCore, "Journal core factory was not loaded")
local pendingPlayerSync = setmetatable({}, { __mode = "k" })
local K = newCore({ sendSyncPlayerFields = function(player, mask)
    -- Defer fallible transport until applyRead has returned its immutable
    -- missingFields result. Domain code and the global native API stay intact.
    pendingPlayerSync[player] = mask
end })
SS.Knowledge = K
K.MODULE = SS.MODULE

-- Explicit schema bridge. Existing v2 discs contain XP only. They are read
-- through a temporary v6 view; merely loading/listening never stamps new data.
local fields = {
    { "version", "Version", "version" },
    { "knowledgeVersion", "KnowledgeVersion", nil },
    { "skills", "Skills", "skills" },
    { "recipes", "Recipes", "recipes" },
    { "skillBooks", "SkillBooks", "skillBooks" },
    { "skillBookStates", "SkillBookStates", "skillBookStates" },
    { "mediaRewards", "MediaRewards", "mediaRewards" },
    { "mediaRewardMode", "MediaRewardMode", "mediaRewardMode" },
    { "authorName", "AuthorName", "authorName" },
    { "authorUser", "AuthorUser", "authorUser" },
    { "authorDescId", "AuthorDescId", "authorDescId" },
    { "recordedAt", "RecordedAt", "writtenAt" },
}
local function key(field, loaded)
    return loaded and "SS_loaded" .. field[2] or "SS_" .. field[1]
end

function SS.copyKnowledgePayload(source, target, fromLoaded, toLoaded)
    for _, field in ipairs(fields) do
        -- Do not coerce nil to "": missing and exact-empty multiplier
        -- snapshots have different meanings in the Journal schema.
        target[key(field, toLoaded)] = source[key(field, fromLoaded)]
    end
end

function SS.hasKnowledgeMarker(item)
    if not item then return false end
    local md = item:getModData()
    for _, field in ipairs(fields) do
        if md[key(field, false)] ~= nil then return true end
    end
    return false
end

local function version(value)
    if type(value) == "number" and value == math.floor(value) then return value end
    if type(value) == "string" and value:match("^%d+$") then return tonumber(value) end
    return nil
end

function SS.isSupportedKnowledgeRecord(holder, loaded)
    if loaded then
        if not SS.isCDPlayer(holder) or SS.getLoadedMode(holder) ~= SS.MODE_SONG then return false end
    elseif not SS.isPhysicalCD(holder) or SS.isRecordedRetailCD(holder) then
        return false
    end
    local md = holder:getModData()
    local v = version(md[loaded and "SS_loadedVersion" or "SS_version"])
    if v == SS.LEGACY_VERSION then
        return type(md[key(fields[3], loaded)]) == "string"
            and md[key(fields[3], loaded)] ~= ""
    end
    return v == SS.VERSION
        and version(md[loaded and "SS_loadedKnowledgeVersion" or "SS_knowledgeVersion"]) == K.VERSION
end

function SS.isSupportedLoadedCarrier(device)
    if not SS.isCDPlayer(device) then return false end
    local mode = SS.getLoadedMode(device)
    if mode == SS.MODE_SONG then return SS.isSupportedKnowledgeRecord(device, true) end
    local v = version(device:getModData().SS_loadedVersion)
    return mode == SS.MODE_BLANK and (v == SS.LEGACY_VERSION or v == SS.VERSION)
end

function SS.knowledgeView(holder, loaded)
    local md = { LJ_written = false }
    local supported = holder and SS.isSupportedKnowledgeRecord(holder, loaded)
    if supported then
        local source = holder:getModData()
        md.LJ_written = true
        md.LJ_version = K.VERSION
        local legacy = version(source[loaded and "SS_loadedVersion" or "SS_version"]) == SS.LEGACY_VERSION
        for _, field in ipairs(fields) do
            if field[3] and field[3] ~= "version" then
                local isLegacyField = field[1] == "skills" or field[1] == "authorName"
                    or field[1] == "authorUser" or field[1] == "recordedAt"
                if not legacy or isLegacyField then md["LJ_" .. field[3]] = source[key(field, loaded)] end
            end
        end
    end
    return {
        _songKnowledgeView = true, holder = holder, loaded = loaded,
        getModData = function() return md end,
    }
end

local nativeCapture = K.captureSkills
local nativeEncode, nativeDecode = K.encodeSkills, K.decodeSkills
local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function finiteMap(values)
    local result = {}
    for name, value in pairs(values or {}) do
        if finite(tonumber(value)) and tonumber(value) > 0 then result[name] = value end
    end
    return result
end
-- The valid-value codec is identical. The carrier boundary also preserves
-- rc0.4.4's rejection of non-finite numeric data before it reaches Java APIs.
function SS.captureSkills(player) return nativeCapture(player) end
function SS.encodeSkills(values) return nativeEncode(finiteMap(values)) end
function SS.decodeSkills(encoded) return finiteMap(nativeDecode(encoded)) end
local sampledPlayer, sampledSkills

local function configure(core)
    core.MODULE = SS.MODULE
    core.isSupportedItem = function(item)
        return type(item) == "table" and item._songKnowledgeView == true
    end
    core.hasWritingTool = function(player) return SS.hasMicrophone(player) end
    core.refreshJournalPresentation = function() return false end
    core.isOptionEnabled = function(name) return SS.isOptionEnabled(name, true) end
    core.getOptionNumber = function(name, defaultValue, minValue, maxValue)
        if name == "WriteTimeMultiplier" then name = "RecordTimeMultiplier" end
        if name == "ReadTimeMultiplier" then name = "RestoreTimeMultiplier" end
        return SS.getOptionNumber(name, defaultValue, minValue, maxValue)
    end
    core.encodeSkills, core.decodeSkills = SS.encodeSkills, SS.decodeSkills
    core.captureSkills = function(player)
        if sampledPlayer == player and sampledSkills then return sampledSkills end
        return SS.captureSkills(player)
    end
    return core
end
configure(K)
SS.getActionActorKey = K.getActionActorKey
SS.getGameDateTimeStamp = K.getGameDateTimeStamp
SS.getRecoverableSkillXp = K.getRecoverableSkillXp
SS.getRecoveryRatio = K.getRecoveryRatio
SS.hasKnowledgeDelta = K.hasDelta
require "survivorssong/journal_sync"
SS.KnowledgeSync = assert(SS.newJournalSync, "Journal sync factory was not loaded")(K)

local function withSkills(player, current, fn)
    local previousPlayer, previousSkills = sampledPlayer, sampledSkills
    sampledPlayer, sampledSkills = player, current
    local ok, result = pcall(fn)
    sampledPlayer, sampledSkills = previousPlayer, previousSkills
    if not ok then error(result) end
    return result
end

local function emptyDelta()
    return { xp = 0, skills = 0, recipes = 0, books = 0, vhs = 0 }
end

function SS.getRecordDelta(player, device, currentSkills)
    local mode = SS.getLoadedMode(device)
    if not player or (mode ~= SS.MODE_BLANK and mode ~= SS.MODE_SONG)
        or (mode == SS.MODE_SONG and not SS.canUseKnowledgeRecord(player, device)) then
        return emptyDelta()
    end
    local delta = withSkills(player, currentSkills, function()
        return K.getWriteDelta(player, SS.knowledgeView(device, true))
    end)
    delta.snapshot = delta.mergedSkills -- rc0.4.4 skill-plan compatibility
    return delta
end

function SS.getRestoreDelta(player, device, currentSkills)
    if not player or not SS.isSupportedKnowledgeRecord(device, true) then return emptyDelta() end
    return withSkills(player, currentSkills, function()
        return K.getReadDelta(player, SS.knowledgeView(device, true))
    end)
end

local function canUseDevice(player, device)
    if not player or player:isDead() or not SS.isCDPlayer(device) then return false end
    if not SS.isKnowledgeDeviceActiveForPlayer(player, device) then return false end
    local data = SS.getDeviceData(device)
    return data and data:hasMedia() and tonumber(data:getMediaType()) == 0
        and SS.isDeviceTurnedOn(device) and SS.hasUsablePower(device) and SS.hasHeadphones(device)
end

local function canRecordContext(player, device)
    if not canUseDevice(player, device) or not SS.hasMicrophone(player) then return false end
    local mode = SS.getLoadedMode(device)
    return (mode == SS.MODE_BLANK and SS.isSupportedLoadedCarrier(device))
        or (mode == SS.MODE_SONG and SS.canUseKnowledgeRecord(player, device))
end
local function canRestoreContext(player, device)
    return canUseDevice(player, device) and SS.isSupportedKnowledgeRecord(device, true)
        and SS.canUseKnowledgeRecord(player, device)
end

function SS.canRecord(player, device)
    return canRecordContext(player, device) and K.hasDelta(SS.getRecordDelta(player, device))
end
function SS.canRestore(player, device)
    return canRestoreContext(player, device) and (K.hasDelta(SS.getRestoreDelta(player, device))
        or (isClient() and SS.hasServerMultiplierRepair and SS.hasServerMultiplierRepair(player, device)))
end
function SS.isKnowledgeActionContextValid(player, device, kind)
    if kind == "record" then return canRecordContext(player, device) end
    if kind == "restore" then return canRestoreContext(player, device) end
    return false
end
function SS.isKnowledgeActionValid(player, device, kind)
    if kind == "record" then return SS.canRecord(player, device) end
    if kind == "restore" then return SS.canRestore(player, device) end
    return false
end

function SS.getKnowledgeActionChoice(player, device)
    local mode = SS.getLoadedMode(device)
    if mode ~= SS.MODE_BLANK and mode ~= SS.MODE_SONG then return nil, false end
    local restore = mode == SS.MODE_SONG and canRestoreContext(player, device)
    local record = canRecordContext(player, device)
    if not restore and not record then return mode == SS.MODE_BLANK and "record" or "restore", false end
    local current = SS.captureSkills(player)
    if restore then
        if K.hasDelta(SS.getRestoreDelta(player, device, current)) then return "restore", true end
        if isClient() and K.hasSkillBookMultiplierTarget(player, SS.knowledgeView(device, true), false) then
            local status = SS.getServerMultiplierReadStatus and SS.getServerMultiplierReadStatus(player, device)
            if status == true then return "restore", true end
            if status == nil then
                if SS.requestMultiplierReadStatus then SS.requestMultiplierReadStatus(player, device) end
                -- Resolve a possible server-only deficit before updating the
                -- same disc. A confirmed no-deficit response may record.
                return "restore", false
            end
        end
    end
    if record and K.hasDelta(SS.getRecordDelta(player, device, current)) then return "record", true end
    return mode == SS.MODE_BLANK and "record" or "restore", false
end

local function payloadSnapshot(device)
    local result = { SS_loadedMode = device:getModData().SS_loadedMode }
    SS.copyKnowledgePayload(device:getModData(), result, true, true)
    return result
end
function SS.getKnowledgePayloadSignature(device)
    local md = device and device:getModData() or {}
    local parts = { tostring(md.SS_loadedMode or "") }
    for _, field in ipairs(fields) do
        local value = md[key(field, true)]
        parts[#parts + 1] = value == nil and "N" or (type(value) .. ":" .. #tostring(value) .. ":" .. tostring(value))
    end
    return table.concat(parts, "\30")
end
local function knowledgePolicy()
    return table.concat({ tostring(K.isSkillXpEnabled()), tostring(K.isRecipesEnabled()),
        tostring(K.isSkillBooksEnabled()), tostring(K.isTrainingMediaEnabled()),
        tostring(K.getRecoveryRatio()) }, "|")
end
function SS.makeKnowledgeBaseline(player, device)
    return { actor = SS.getActionActorKey(player), device = device,
        signature = SS.getKnowledgePayloadSignature(device), baseline = payloadSnapshot(device), policy = knowledgePolicy() }
end
function SS.isKnowledgeBaselineCurrent(player, device, plan)
    if type(plan) ~= "table" or plan.device ~= device or plan.consumed
        or plan.actor ~= SS.getActionActorKey(player) or type(plan.baseline) ~= "table" then return false end
    local md = device:getModData()
    if md.SS_loadedMode ~= plan.baseline.SS_loadedMode then return false end
    for _, field in ipairs(fields) do
        local name = key(field, true)
        if md[name] ~= plan.baseline[name] then return false end
    end
    return true
end

function SS.makeRecordPlan(player, device, delta)
    if isClient() or not canRecordContext(player, device) or not K.hasDelta(delta) then return nil end
    local plan = SS.makeKnowledgeBaseline(player, device)
    -- Freeze the complete admission snapshot. Reusing commitWrite through a
    -- private core instance retains every Journal merge/serialization rule.
    local writer = configure(newCore())
    writer.getWriteDelta = function() return delta end
    local view = SS.knowledgeView(device, true)
    if not writer.commitWrite(player, view) then return nil end
    plan.payload = view:getModData()
    plan.encoded = plan.payload.LJ_skills -- compatibility with rc0.4.4 diagnostics
    return plan
end
function SS.isKnowledgePolicyCurrent(plan)
    return plan and plan.policy == knowledgePolicy()
end
function SS.isRecordPlanCurrent(player, device, plan)
    return SS.isKnowledgeBaselineCurrent(player, device, plan) and type(plan.payload) == "table"
end
function SS.commitRecord(player, device, plan)
    if isClient() or not canRecordContext(player, device) or not SS.isRecordPlanCurrent(player, device, plan)
        or not SS.isKnowledgePolicyCurrent(plan) then return false end
    local session = SS._knowledgeSessions and SS._knowledgeSessions[device]
    if not session or session.player ~= player or session.recordPlan ~= plan then return false end
    local md = device:getModData()
    for _, field in ipairs(fields) do
        if field[3] and field[3] ~= "version" then md[key(field, true)] = plan.payload["LJ_" .. field[3]] end
    end
    md.SS_loadedMode = SS.MODE_SONG
    md.SS_loadedVersion = SS.VERSION
    md.SS_loadedKnowledgeVersion = K.VERSION
    md.SS_loadedRecordedAt = SS.getGameDateTimeStamp() or plan.payload.LJ_writtenAt
    plan.consumed = true
    return true
end
function SS.applyRestore(player, device)
    if isClient() or not SS.canRestore(player, device) then return false end
    pendingPlayerSync[player] = nil
    local changed, fields = K.applyRead(player, SS.knowledgeView(device, true))
    if fields then fields.playerFieldMask = pendingPlayerSync[player] end
    pendingPlayerSync[player] = nil
    return changed, fields
end
function SS.getActionPageCount(kind, delta)
    return K.getActionPageCount(kind == "restore" and "read" or "write", delta)
end
function SS.getActionTime(kind, player, device, delta)
    delta = delta or (kind == "restore" and SS.getRestoreDelta(player, device) or SS.getRecordDelta(player, device))
    if kind == "restore" then return K.getReadTime(delta, player) end
    return K.getWriteTime(delta, player)
end

function SS.getRestoreSignature(player, device, delta)
    return K.getActionSignature("read", SS.knowledgeView(device, true), delta or SS.getRestoreDelta(player, device))
end

SS._knowledgeInstalled = true
end
-- PZ discovers shared Lua files independently of require(). Defer installation
-- until the carrier API exists; the shared entry point calls this explicitly.
if SurvivorsSong._sharedReady then SurvivorsSong.installKnowledge() end
