--[[
    UNO HUB · UI page visibility fix
    Grow a Chicken Fighter
    SOURCE A: createAutoSellChickens + AutoSellFeature + Chickens UI
    SOURCE B: resolveEggDisplayName / rarity / ability + TextLabel Size
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local VirtualUser       = game:GetService("VirtualUser")
local Workspace         = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local Lighting          = game:GetService("Lighting")
local HttpService       = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 8)
if not PlayerGui then return end

do
    local old = PlayerGui:FindFirstChild("UNO_HUB")
    if old then
        old:SetAttribute("UNO_HUB_Shutdown", true)
        old:Destroy()
        task.wait(0.05)
    end
    local cover = PlayerGui:FindFirstChild("UNO_HUB_VisualCover")
    if cover then
        pcall(function() cover:Destroy() end)
    end
end

local Theme = {
    Background = Color3.fromRGB(11, 12, 16), Surface = Color3.fromRGB(17, 18, 24),
    SurfaceElevated = Color3.fromRGB(24, 26, 34), Sidebar = Color3.fromRGB(14, 15, 20),
    Border = Color3.fromRGB(36, 39, 50), TextPrimary = Color3.fromRGB(236, 239, 246),
    TextSecondary = Color3.fromRGB(160, 168, 185), TextMuted = Color3.fromRGB(110, 118, 135),
    Primary = Color3.fromRGB(79, 140, 255), Success = Color3.fromRGB(52, 199, 123),
    Warning = Color3.fromRGB(234, 179, 8), Danger = Color3.fromRGB(239, 68, 68),
}

local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ items = {} }, Maid) end
function Maid:Give(item) table.insert(self.items, item) return item end
function Maid:Connect(signal, fn) local c = signal:Connect(fn) return self:Give(c) end
function Maid:Task(fn)
    local token = { cancelled = false }
    self:Give(function() token.cancelled = true end)
    task.spawn(function() fn(token) end)
    return token
end
function Maid:Cleanup()
    for _, item in ipairs(self.items) do
        if typeof(item) == "RBXScriptConnection" then pcall(function() item:Disconnect() end)
        elseif type(item) == "function" then pcall(item)
        elseif type(item) == "table" and item.cancelled ~= nil then item.cancelled = true end
    end
    self.items = {}
end
local maid = Maid.new()

local State = {
    closed = false, visible = true, page = "Home", generation = 0,
    sessionStart = os.clock(), towerRuns = 0, floorsCleared = 0, koCount = 0, successfulRebirths = 0,
    log = {}, diagnostics = {}, liveEvents = {}, nameDiagSeen = {},
    tower = { status = "IDLE", floor = nil, best = nil, streak = nil, rival = nil, lastResult = nil, continue = nil, runActive = false },
    data = { roster = nil, rebirth = nil, towerBest = nil, chicken = nil, recyclerLevel = nil, money = nil, coop = nil, incubator = nil },
    autoFarmRebirth = {
        enabled = false, phase = "DISABLED", generation = 0,
        retryDelay = 5, postRebirthDelay = 30, countdown = 0, countdownLabel = "",
        surrenderInFlight = false, declineInFlight = false,
    },
    hotEgg = {
        enabled = false, phase = "DISABLED", generation = 0, movementMode = "Tween",
        meteorAvoidance = true, safetyMargin = 6, exitPitAfter = true,
        eventActive = false, holding = false, timeRemaining = nil, action = "—",
        meteorCount = 0, nearestImpact = nil, rewardConfirmed = false, hazards = {},
        endConfirmed = false, exitAttempts = 0,
        -- meteor avoidance stability (movement layer only)
        evadeTarget = nil, evadeTargetTime = 0, lastEvadeDecision = 0,
        lastEvadeReason = "—", threateningCount = 0, distToEgg = nil,
    },
    economy = {
        buyStatus = "IDLE", upgradeStatus = "IDLE", expandStatus = "IDLE", recyclerStatus = "IDLE",
        generatorsOwned = 0, generatorsSlots = 0, nextBuySlot = nil, nextBuyCost = nil, recyclerLevel = 0,
    },
    movementOwner = "NONE",
    applyingConfig = false,
    toggles = {
        autoFarmRebirth = false, autoKoDismiss = true, autoHatch = false, autoCollectEgg = false,
        autoIncubatorClaim = false, autoSell = false, autoFuse = false,
        autoBuyGenerator = false, autoUpgradeGenerator = false, autoExpandCoop = false, autoUpgradeRecycler = false, autoUpgradeIncubator = false,
        antiAfk = false, autoHotEgg = false, showFloatingButton = true, reducedMotion = false,
    },
}

local function log(level, text)
    table.insert(State.log, 1, { t = os.clock(), level = level, text = tostring(text) })
    while #State.log > 120 do table.remove(State.log) end
end
local function display(v)
    if v == nil then return "—" end
    if type(v) == "boolean" then return v and "Yes" or "No" end
    return tostring(v)
end
local function setText(label, value)
    if label and typeof(label) == "Instance" and label:IsA("TextLabel") then
        label.Text = display(value)
    end
end

-- Config / Performance placeholders (filled after feature construction)
local ConfigManager = nil
local PerformanceManager = nil
local visualCoverGui = nil
local isApplyingConfig = false
local function markConfigDirty()
    if isApplyingConfig or State.applyingConfig then return end
    if ConfigManager and type(ConfigManager.markDirty) == "function" then
        pcall(function() ConfigManager.markDirty() end)
    end
end


--------------------------------------------------------------------
-- createPerformanceManager (supplied authoritative backend)
--------------------------------------------------------------------
local VISUAL_ENABLED_CLASSES = {
    ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true,
    Sparkles = true, Highlight = true, PointLight = true, SpotLight = true, SurfaceLight = true,
    BloomEffect = true, BlurEffect = true, ColorCorrectionEffect = true, DepthOfFieldEffect = true,
    SunRaysEffect = true, Atmosphere = true, Clouds = true,
}
local DEFAULT_PROTECTED_NAME = {
    HotEgg = true, NestEgg = true, PitZone = true, Meteor = true, Hazard = true, Carrier = true,
}
local function perfSpawnThread(fn)
    if task and type(task.spawn) == "function" then return task.spawn(fn) end
    local co = coroutine.create(fn); coroutine.resume(co); return co
end
local function perfSafeConnect(signal, callback)
    if signal and type(signal.Connect) == "function" then
        local ok, connection = pcall(function() return signal:Connect(callback) end)
        if ok then return connection end
    end
    return nil
end
local function perfSafeGetDescendants(instance)
    if not instance or type(instance.GetDescendants) ~= "function" then return {} end
    local ok, descendants = pcall(function() return instance:GetDescendants() end)
    return ok and descendants or {}
end
local function perfSafeClass(instance)
    local ok, className = pcall(function() return instance.ClassName end)
    return ok and className or nil
end
local function perfSafeName(instance)
    local ok, name = pcall(function() return instance.Name end)
    return ok and name or ""
end
local function createPerformanceManager(deps)
    deps = deps or {}
    local services = deps.services or deps
    local Players = services.Players
    local Lighting = services.Lighting
    local localPlayer = deps.localPlayer
    if not localPlayer and Players then
        local ok, value = pcall(function() return Players.LocalPlayer end)
        if ok then localPlayer = value end
    end
    local config = {
        boostFPS = false, disableVFX = false, disableShadows = false,
        hideOtherPlayers = false, hideOtherChickens = false, whiteScreen = false, ultraPerformance = false,
    }
    local state = {
        destroyed = false, status = "DISABLED", whiteScreenIsCover = false,
        boostSnapshot = nil, ultraSnapshot = nil,
    }
    local stats = {
        visualObjectsDisabled = 0, visualObjectsRestored = 0, playerPartsHidden = 0,
        chickenPartsHidden = 0, protectedObjectsSkipped = 0, dynamicObjectsHandled = 0, currentMode = "DISABLED",
    }
    local originals = setmetatable({}, { __mode = "k" })
    local hiddenParts = setmetatable({}, { __mode = "k" })
    local connections = {}
    local rootConnections = setmetatable({}, { __mode = "k" })
    local function log(message, payload)
        if type(deps.log) == "function" then pcall(deps.log, message, payload) end
    end
    local function setStatus(status, payload)
        state.status = status; stats.currentMode = status; log(status, payload)
    end
    local function isProtected(instance)
        if type(deps.isProtectedInstance) == "function" then
            local ok, result = pcall(deps.isProtectedInstance, instance)
            if ok and result == true then return true end
        end
        local name = perfSafeName(instance)
        if DEFAULT_PROTECTED_NAME[name] then return true end
        local lowered = string.lower(name)
        for token in pairs(DEFAULT_PROTECTED_NAME) do
            if string.find(lowered, string.lower(token), 1, true) then return true end
        end
        return false
    end
    local function remember(instance, property, value)
        originals[instance] = originals[instance] or {}
        if originals[instance][property] == nil then originals[instance][property] = value end
    end
    local function readProperty(instance, property)
        local ok, value = pcall(function() return instance[property] end)
        if ok then return true, value end
        return false, nil
    end
    local function writeProperty(instance, property, value)
        return pcall(function() instance[property] = value end)
    end
    local function disableVisual(instance)
        if not instance or isProtected(instance) then
            if instance and isProtected(instance) then stats.protectedObjectsSkipped = stats.protectedObjectsSkipped + 1 end
            return
        end
        local className = perfSafeClass(instance)
        if not VISUAL_ENABLED_CLASSES[className] then return end
        local readable, enabled = readProperty(instance, "Enabled")
        if not readable or enabled == nil then return end
        remember(instance, "Enabled", enabled)
        if enabled == true then
            if writeProperty(instance, "Enabled", false) then stats.visualObjectsDisabled = stats.visualObjectsDisabled + 1 end
        end
    end
    local function restoreVisual(instance)
        local saved = originals[instance]
        if not saved or saved.Enabled == nil then return end
        if writeProperty(instance, "Enabled", saved.Enabled) then stats.visualObjectsRestored = stats.visualObjectsRestored + 1 end
        saved.Enabled = nil
    end
    local function processVisual(instance)
        if config.disableVFX or config.boostFPS then disableVisual(instance) else restoreVisual(instance) end
    end
    local function isLocalCharacter(model)
        if type(deps.isLocalPlayerCharacter) == "function" then
            local ok, result = pcall(deps.isLocalPlayerCharacter, model, localPlayer)
            if ok then return result == true end
        end
        return localPlayer and localPlayer.Character == model
    end
    local function isOtherPlayerCharacter(model, player)
        if isLocalCharacter(model) then return false end
        if type(deps.isOtherPlayerCharacter) == "function" then
            local ok, result = pcall(deps.isOtherPlayerCharacter, model, player)
            return ok and result == true
        end
        return player ~= nil and player ~= localPlayer
    end
    local function isOtherChickenModel(model)
        if type(deps.isOtherChickenModel) ~= "function" then return false end
        local ok, result = pcall(deps.isOtherChickenModel, model, localPlayer)
        return ok and result == true
    end
    local function setModelHidden(model, hidden, category)
        if not model or isProtected(model) then return end
        for _, instance in ipairs(perfSafeGetDescendants(model)) do
            local className = perfSafeClass(instance)
            if className == "BasePart" or className == "MeshPart" or className == "Part" or className == "UnionOperation" then
                local readable, current = readProperty(instance, "LocalTransparencyModifier")
                if readable then
                    if hidden then
                        remember(instance, "LocalTransparencyModifier", current)
                        if writeProperty(instance, "LocalTransparencyModifier", 1) then
                            hiddenParts[instance] = true
                            if category == "player" then stats.playerPartsHidden = stats.playerPartsHidden + 1
                            else stats.chickenPartsHidden = stats.chickenPartsHidden + 1 end
                        end
                    else
                        local saved = originals[instance]
                        local value = saved and saved.LocalTransparencyModifier
                        if value ~= nil then
                            writeProperty(instance, "LocalTransparencyModifier", value)
                            saved.LocalTransparencyModifier = nil
                            hiddenParts[instance] = nil
                        end
                    end
                end
            end
        end
    end
    local function processCharacter(model, player)
        if config.hideOtherPlayers or config.ultraPerformance then
            if isOtherPlayerCharacter(model, player) then setModelHidden(model, true, "player"); return end
        end
        if not config.hideOtherPlayers and not config.ultraPerformance and player ~= localPlayer then
            setModelHidden(model, false, "player")
        end
    end
    local function processChicken(model)
        local shouldHide = config.hideOtherChickens or config.ultraPerformance
        if shouldHide and isOtherChickenModel(model) then setModelHidden(model, true, "chicken")
        elseif not shouldHide and isOtherChickenModel(model) then setModelHidden(model, false, "chicken") end
    end
    local function processRoot(root)
        if not root or isProtected(root) then return end
        disableVisual(root)
        for _, instance in ipairs(perfSafeGetDescendants(root)) do processVisual(instance) end
        stats.dynamicObjectsHandled = stats.dynamicObjectsHandled + 1
    end
    local function connectRoot(root)
        if rootConnections[root] then return end
        if root and root.DescendantAdded then
            rootConnections[root] = perfSafeConnect(root.DescendantAdded, function(instance)
                if state.destroyed then return end
                processVisual(instance)
            end)
        end
    end
    local function approvedRoots()
        if type(deps.getCosmeticRoots) == "function" then
            local ok, roots = pcall(deps.getCosmeticRoots)
            if ok and type(roots) == "table" then return roots end
        end
        return deps.cosmeticRoots or {}
    end
    local function applyVisuals()
        for _, root in ipairs(approvedRoots()) do
            connectRoot(root); processRoot(root)
        end
        if Lighting and config.disableShadows then
            local readable, shadows = readProperty(Lighting, "GlobalShadows")
            if readable then
                remember(Lighting, "GlobalShadows", shadows)
                writeProperty(Lighting, "GlobalShadows", false)
            end
        elseif Lighting then
            local saved = originals[Lighting]
            if saved and saved.GlobalShadows ~= nil then
                writeProperty(Lighting, "GlobalShadows", saved.GlobalShadows)
                saved.GlobalShadows = nil
            end
        end
    end
    local function applyPlayers()
        if not Players or type(Players.GetPlayers) ~= "function" then return end
        local ok, players = pcall(function() return Players:GetPlayers() end)
        if not ok then return end
        for _, player in ipairs(players) do
            if player.Character then processCharacter(player.Character, player) end
        end
    end
    local function applyModels()
        applyVisuals(); applyPlayers()
        if type(deps.getChickenModels) == "function" then
            local ok, models = pcall(deps.getChickenModels)
            if ok and type(models) == "table" then
                for _, model in ipairs(models) do processChicken(model) end
            end
        end
    end
    local function updateModeStatus()
        if config.ultraPerformance then setStatus("ULTRA PERFORMANCE")
        elseif config.boostFPS then setStatus("BOOST FPS + LOW GRAPHICS")
        elseif config.disableVFX or config.disableShadows or config.hideOtherPlayers or config.hideOtherChickens then
            setStatus("CUSTOM PERFORMANCE")
        else setStatus("DISABLED") end
    end
    local function apply()
        if state.destroyed then return end
        applyModels()
        if config.whiteScreen then
            if type(deps.setVisualCover) == "function" then pcall(deps.setVisualCover, true) end
            state.whiteScreenIsCover = true
        else
            if type(deps.setVisualCover) == "function" then pcall(deps.setVisualCover, false) end
            state.whiteScreenIsCover = false
        end
        updateModeStatus()
    end
    local function setFlag(key, enabled)
        if state.destroyed then return false end
        config[key] = enabled == true; apply(); return true
    end
    local api = {}
    function api.setBoostFPS(enabled)
        enabled = enabled == true
        if enabled and not state.boostSnapshot then
            state.boostSnapshot = { disableVFX = config.disableVFX, disableShadows = config.disableShadows }
        elseif not enabled and state.boostSnapshot then
            config.disableVFX = state.boostSnapshot.disableVFX
            config.disableShadows = state.boostSnapshot.disableShadows
            state.boostSnapshot = nil
        end
        config.boostFPS = enabled
        if enabled then config.disableVFX = true; config.disableShadows = true end
        apply(); return true
    end
    function api.getBoostFPS() return config.boostFPS end
    function api.setDisableVFX(v) return setFlag("disableVFX", v) end
    function api.getDisableVFX() return config.disableVFX end
    function api.setDisableShadows(v) return setFlag("disableShadows", v) end
    function api.getDisableShadows() return config.disableShadows end
    function api.setHideOtherPlayers(v) return setFlag("hideOtherPlayers", v) end
    function api.getHideOtherPlayers() return config.hideOtherPlayers end
    function api.setHideOtherChickens(v) return setFlag("hideOtherChickens", v) end
    function api.getHideOtherChickens() return config.hideOtherChickens end
    function api.setWhiteScreen(v) config.whiteScreen = v == true; apply(); return true end
    function api.getWhiteScreen() return config.whiteScreen end
    function api.setUltraPerformance(enabled)
        enabled = enabled == true
        if enabled and not state.ultraSnapshot then
            state.ultraSnapshot = {
                boostFPS = config.boostFPS, disableVFX = config.disableVFX, disableShadows = config.disableShadows,
                hideOtherPlayers = config.hideOtherPlayers, hideOtherChickens = config.hideOtherChickens,
            }
        elseif not enabled and state.ultraSnapshot then
            config.boostFPS = state.ultraSnapshot.boostFPS
            config.disableVFX = state.ultraSnapshot.disableVFX
            config.disableShadows = state.ultraSnapshot.disableShadows
            config.hideOtherPlayers = state.ultraSnapshot.hideOtherPlayers
            config.hideOtherChickens = state.ultraSnapshot.hideOtherChickens
            state.ultraSnapshot = nil
        end
        config.ultraPerformance = enabled
        if enabled then
            config.boostFPS = true; config.disableVFX = true; config.disableShadows = true
            config.hideOtherPlayers = true; config.hideOtherChickens = true
        end
        apply(); return true
    end
    function api.getUltraPerformance() return config.ultraPerformance end
    function api.getStatus() return state.status end
    function api.getStats()
        local result = {}
        for key, value in pairs(stats) do result[key] = value end
        result.whiteScreenIsVisualCover = state.whiteScreenIsCover
        result.actualRenderingDisable = false
        return result
    end
    function api.refresh() apply() end
    function api.destroy()
        if state.destroyed then return end
        state.destroyed = true
        for _, connection in ipairs(connections) do
            if connection and type(connection.Disconnect) == "function" then pcall(function() connection:Disconnect() end) end
        end
        for _, connection in pairs(rootConnections) do
            if connection and type(connection.Disconnect) == "function" then pcall(function() connection:Disconnect() end) end
        end
        for instance, saved in pairs(originals) do
            if saved.Enabled ~= nil then writeProperty(instance, "Enabled", saved.Enabled) end
            if saved.GlobalShadows ~= nil then writeProperty(instance, "GlobalShadows", saved.GlobalShadows) end
            if saved.LocalTransparencyModifier ~= nil then writeProperty(instance, "LocalTransparencyModifier", saved.LocalTransparencyModifier) end
        end
        if type(deps.setVisualCover) == "function" then pcall(deps.setVisualCover, false) end
        setStatus("DISABLED")
    end
    if Players then
        table.insert(connections, perfSafeConnect(Players.PlayerAdded, function(player)
            if player.Character then processCharacter(player.Character, player) end
            table.insert(connections, perfSafeConnect(player.CharacterAdded, function(character)
                processCharacter(character, player)
            end))
        end))
        table.insert(connections, perfSafeConnect(Players.PlayerRemoving, function(player)
            if player.Character then processCharacter(player.Character, player) end
        end))
        local ok, players = pcall(function() return Players:GetPlayers() end)
        if ok then
            for _, player in ipairs(players) do
                table.insert(connections, perfSafeConnect(player.CharacterAdded, function(character)
                    processCharacter(character, player)
                end))
            end
        end
    end
    if services.Workspace and services.Workspace.DescendantAdded then
        table.insert(connections, perfSafeConnect(services.Workspace.DescendantAdded, function(instance)
            if isProtected(instance) then return end
            processVisual(instance)
            processChicken(instance)
        end))
    end
    return api
end


--------------------------------------------------------------------
-- createConfigManager (supplied authoritative backend)
--------------------------------------------------------------------
local CONFIG_VERSION = 1
local CONFIG_FOLDER = "UNO_HUB"
local CONFIG_FILE = "UNO_HUB/GrowAChickenFighter_Config.json"
local function cfgClone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[cfgClone(key, seen)] = cfgClone(item, seen)
    end
    return result
end
local function cfgDelay(seconds, callback, deps)
    if type(deps.delay) == "function" then return deps.delay(seconds, callback) end
    if task and type(task.delay) == "function" then return task.delay(seconds, callback) end
    return nil
end
local function cfgGetGlobal(name)
    if type(_G) == "table" and type(_G[name]) == "function" then return _G[name] end
    return nil
end
local function cfgChooseFunction(container, name)
    if type(container) == "table" and type(container[name]) == "function" then return container[name] end
    return cfgGetGlobal(name)
end
local function createConfigManager(deps)
    deps = deps or {}
    local fs = deps.fs or {}
    local httpService = deps.HttpService or deps.httpService
    local encode = deps.jsonEncode
    local decode = deps.jsonDecode
    if type(encode) ~= "function" and httpService then
        encode = function(value) return httpService:JSONEncode(value) end
    end
    if type(decode) ~= "function" and httpService then
        decode = function(text) return httpService:JSONDecode(text) end
    end
    local writefile = cfgChooseFunction(fs, "writefile")
    local readfile = cfgChooseFunction(fs, "readfile")
    local isfile = cfgChooseFunction(fs, "isfile")
    local makefolder = cfgChooseFunction(fs, "makefolder")
    local persistenceAvailable = type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
        and type(makefolder) == "function"
        and type(encode) == "function"
        and type(decode) == "function"
    local config = { autoSave = true, restoreDestructiveAutomation = false }
    for key, value in pairs(deps.defaults or {}) do config[key] = cfgClone(value) end
    local startupDefaults = cfgClone(config)
    local sections = {}
    local state = {
        destroyed = false, dirty = false, savePending = false, timerGeneration = 0,
        status = persistenceAvailable and "READY" or "PERSISTENCE UNAVAILABLE",
        lastError = nil, lastLoadedVersion = nil, lastSavedAt = nil,
    }
    local function log(message, payload)
        if type(deps.log) == "function" then pcall(deps.log, message, payload) end
    end
    local function setStatus(status, errorValue)
        state.status = status; state.lastError = errorValue; log(status, errorValue)
    end
    local function ensureFolder()
        local ok = pcall(makefolder, CONFIG_FOLDER)
        return ok
    end
    local function currentDefaults()
        local result = cfgClone(startupDefaults)
        result.version = CONFIG_VERSION
        for name, section in pairs(sections) do
            result[name] = cfgClone(section.defaults or {})
        end
        return result
    end
    local function sanitizeWithDefaults(value, defaults)
        if type(defaults) == "boolean" then return type(value) == "boolean" and value or defaults end
        if type(defaults) == "number" then return type(value) == "number" and value or defaults end
        if type(defaults) == "string" then return type(value) == "string" and value or defaults end
        if type(defaults) ~= "table" then return cfgClone(value) end
        if type(value) ~= "table" then return cfgClone(defaults) end
        local result = {}
        for key, defaultValue in pairs(defaults) do
            if value[key] ~= nil then result[key] = sanitizeWithDefaults(value[key], defaultValue)
            else result[key] = cfgClone(defaultValue) end
        end
        return result
    end
    local function validateSection(name, value, section)
        local normalized = sanitizeWithDefaults(value, section.defaults or {})
        if type(section.validate) == "function" then
            local ok, result = pcall(section.validate, normalized, name)
            if not ok or result == false then return cfgClone(section.defaults or {}), false end
            if type(result) == "table" then normalized = result end
        end
        return normalized, true
    end
    local function applyDocument(document)
        document = type(document) == "table" and document or {}
        local restoreDestructive = document.restoreDestructiveAutomation == true
        config.restoreDestructiveAutomation = restoreDestructive
        if type(document.autoSave) == "boolean" then config.autoSave = document.autoSave end
        for name, section in pairs(sections) do
            local value = document[name]
            local normalized = validateSection(name, value, section)
            if name == "sell" or name == "fuse" or name == "autoSell" or name == "autoFuse" then
                if type(normalized) == "table" and not restoreDestructive then
                    if normalized.enabled ~= nil then normalized.enabled = false end
                    if normalized.dryRun ~= nil then normalized.dryRun = true end
                end
            end
            if type(section.loader) == "function" then
                pcall(section.loader, cfgClone(normalized), {
                    name = name,
                    restoredDestructiveAutomation = restoreDestructive,
                    fromConfig = true,
                })
            end
        end
    end
    local function migrate(document)
        local version = tonumber(document.version) or 0
        if version > CONFIG_VERSION then return nil, "UNSUPPORTED CONFIG VERSION" end
        if version < CONFIG_VERSION and type(deps.migrate) == "function" then
            local ok, migrated = pcall(deps.migrate, cfgClone(document), version, CONFIG_VERSION)
            if not ok or type(migrated) ~= "table" then return nil, "CONFIG MIGRATION FAILED" end
            document = migrated
        end
        document.version = CONFIG_VERSION
        return document, nil
    end
    local function snapshot()
        local document = {
            version = CONFIG_VERSION,
            autoSave = config.autoSave == true,
            restoreDestructiveAutomation = config.restoreDestructiveAutomation == true,
        }
        for name, section in pairs(sections) do
            if type(section.serializer) == "function" then
                local ok, value = pcall(section.serializer)
                if ok and type(value) == "table" then document[name] = cfgClone(value)
                else document[name] = cfgClone(section.defaults or {}) end
            else
                document[name] = cfgClone(section.defaults or {})
            end
        end
        return document
    end
    local function saveNow()
        if state.destroyed then return false, "DESTROYED" end
        if not persistenceAvailable then
            setStatus("PERSISTENCE UNAVAILABLE"); return false, "PERSISTENCE UNAVAILABLE"
        end
        local document = snapshot()
        local okEncode, text = pcall(encode, document)
        if not okEncode or type(text) ~= "string" then
            setStatus("SAVE ERROR", "JSON ENCODE FAILED"); return false, "JSON ENCODE FAILED"
        end
        pcall(ensureFolder)
        local okWrite, writeError = pcall(writefile, CONFIG_FILE, text)
        if not okWrite then setStatus("SAVE ERROR", writeError); return false, writeError end
        state.dirty = false; state.savePending = false; state.lastSavedAt = os.time()
        setStatus("SAVED"); return true
    end
    local function scheduleSave()
        if state.savePending or not config.autoSave or state.destroyed then return end
        state.savePending = true
        state.timerGeneration = state.timerGeneration + 1
        local generation = state.timerGeneration
        cfgDelay(0.75, function()
            if state.destroyed or generation ~= state.timerGeneration then return end
            state.savePending = false
            if state.dirty then saveNow() end
        end, deps)
    end
    local api = {}
    function api.isPersistenceAvailable() return persistenceAvailable end
    function api.registerSection(name, serializer, loader, options)
        if state.destroyed or type(name) ~= "string" or name == "" then return false, "INVALID SECTION" end
        options = options or {}
        sections[name] = {
            serializer = serializer, loader = loader, validate = options.validate,
            defaults = cfgClone(options.defaults or {}),
        }
        return true
    end
    function api.load()
        if state.destroyed then return false, "DESTROYED" end
        if not persistenceAvailable then
            applyDocument(currentDefaults()); setStatus("PERSISTENCE UNAVAILABLE")
            return false, "PERSISTENCE UNAVAILABLE"
        end
        local existsOk, exists = pcall(isfile, CONFIG_FILE)
        if not existsOk or exists ~= true then
            applyDocument(currentDefaults()); setStatus("NO CONFIG"); return false, "NO CONFIG"
        end
        local okRead, text = pcall(readfile, CONFIG_FILE)
        if not okRead or type(text) ~= "string" then
            applyDocument(currentDefaults()); setStatus("LOAD ERROR", text); return false, "LOAD ERROR"
        end
        local okDecode, document = pcall(decode, text)
        if not okDecode or type(document) ~= "table" then
            applyDocument(currentDefaults()); setStatus("INVALID CONFIG", "JSON DECODE FAILED")
            return false, "INVALID CONFIG"
        end
        local migrated, migrationError = migrate(document)
        if not migrated then
            applyDocument(currentDefaults()); setStatus("INVALID CONFIG", migrationError)
            return false, migrationError
        end
        state.lastLoadedVersion = migrated.version
        applyDocument(migrated)
        state.dirty = false
        setStatus("LOADED")
        return true
    end
    function api.save()
        if state.destroyed then return false, "DESTROYED" end
        state.dirty = true; scheduleSave(); return true
    end
    function api.markDirty() return api.save() end
    function api.saveNow() return saveNow() end
    function api.setAutoSave(enabled)
        config.autoSave = enabled == true
        if config.autoSave and state.dirty then scheduleSave() end
        return true
    end
    function api.getAutoSave() return config.autoSave end
    function api.setRestoreDestructiveAutomation(enabled)
        config.restoreDestructiveAutomation = enabled == true
        api.markDirty(); return true
    end
    function api.getRestoreDestructiveAutomation() return config.restoreDestructiveAutomation end
    function api.getStatus() return state.status end
    function api.getLastError() return state.lastError end
    function api.isDirty() return state.dirty end
    function api.resetToDefaults(confirmed)
        if not confirmed then return false, "CONFIRMATION REQUIRED" end
        applyDocument(currentDefaults()); api.markDirty(); setStatus("RESET"); return true
    end
    function api.destroy()
        if state.destroyed then return end
        if state.dirty then saveNow() end
        state.destroyed = true
        state.timerGeneration = state.timerGeneration + 1
        state.savePending = false
        if type(deps.onDestroy) == "function" then pcall(deps.onDestroy) end
    end
    return api
end


--------------------------------------------------------------------
-- INTEGRATION
--------------------------------------------------------------------
local Integration = { remotes = {}, modules = {} }
local function safeRequire(inst)
    if not inst then return nil end
    local ok, res = pcall(require, inst)
    return ok and res or nil
end
local function findPath(root, segments)
    local cur = root
    for _, name in ipairs(segments) do
        if not cur then return nil end
        cur = cur:FindFirstChild(name)
    end
    return cur
end

Integration.modules.Remotes = safeRequire(findPath(ReplicatedStorage, {"Core", "Remotes"}))
Integration.modules.DataController = safeRequire(findPath(LocalPlayer, {"PlayerScripts", "Core", "Data", "DataController"}))
Integration.modules.RebirthBonus = safeRequire(findPath(ReplicatedStorage, {"Core", "Progression", "RebirthBonus"}))
Integration.modules.PitZone = safeRequire(findPath(ReplicatedStorage, {"Features", "Battle", "PitZone"}))
Integration.modules.GameConfig = safeRequire(findPath(ReplicatedStorage, {"Content", "GameConfig"}))
Integration.modules.CoopView = safeRequire(findPath(ReplicatedStorage, {"Features", "Coop", "CoopView"}))
Integration.modules.RecyclerView = safeRequire(findPath(ReplicatedStorage, {"Features", "Scrap", "RecyclerView"}))
Integration.modules.Catalog = safeRequire(findPath(ReplicatedStorage, {"Content", "Catalog"}))
Integration.modules.CatalogEggs = safeRequire(findPath(ReplicatedStorage, {"Content", "Catalog", "Eggs"}))
Integration.modules.FusionRules = safeRequire(findPath(ReplicatedStorage, {"Features", "Chicken", "FusionRules"}))
Integration.modules.IncubatorView = safeRequire(findPath(ReplicatedStorage, {"Features", "Incubator", "IncubatorView"}))

local function findDataService()
    local direct = safeRequire(findPath(ReplicatedStorage, {"Packages", "DataService"}))
    if direct then return direct end
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    if packages then
        for _, child in ipairs(packages:GetDescendants()) do
            if child.Name == "DataService" and child:IsA("ModuleScript") then
                return safeRequire(child)
            end
        end
    end
    return nil
end
Integration.modules.DataService = findDataService()

State.diagnostics["Core.Remotes"] = Integration.modules.Remotes and "FOUND" or "MISSING"
State.diagnostics["DataController"] = Integration.modules.DataController and "FOUND" or "MISSING"
State.diagnostics["Catalog"] = Integration.modules.Catalog and "FOUND" or "MISSING"
State.diagnostics["Catalog.Eggs"] = Integration.modules.CatalogEggs and "FOUND" or "MISSING"
State.diagnostics["FusionRules"] = Integration.modules.FusionRules and "FOUND" or "MISSING"
State.diagnostics["IncubatorView"] = Integration.modules.IncubatorView and "FOUND" or "MISSING"
State.diagnostics["AutoSell.Factory"] = "PRESENT"
State.diagnostics["AutoFuse.Factory"] = "PRESENT"

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
for _, name in ipairs({
    "TowerStart", "TowerSurrender", "TowerRunStarted", "TowerFloorCleared", "TowerRivalLanded",
    "TowerDefeat", "TowerRunEnded", "TowerContinueOffer", "TowerContinueDecline", "TowerContinued",
    "Rebirth", "BuyGenerator", "UpgradeGenerator", "ExpandCoop", "UpgradeRecycler",
    "HatchEggs", "IncubatorClaim", "IncubatorUpgrade", "SellChickens", "FuseChickens",
    "LiveEventStarted", "LiveEventEnded", "HotEggEntrance", "HotEggMeteor", "HotEggReward", "HotEggFinale",
}) do
    local inst = remotesFolder and remotesFolder:FindFirstChild(name)
    Integration.remotes[name] = inst
    State.diagnostics["Remote." .. name] = inst and inst.ClassName or "MISSING"
end

local function readAtom(controller, key)
    if not controller then return nil end
    local atom = controller[key]
    if type(atom) ~= "function" then return nil end
    local ok, value = pcall(atom)
    return ok and value or nil
end
local function clientGet(path)
    local service = Integration.modules.DataService
    local client = service and service.client
    if not client or type(client.get) ~= "function" then return nil end
    local ok, value = pcall(client.get, client, path)
    return ok and value or nil
end
local function readMoney()
    local dc = Integration.modules.DataController
    local money = readAtom(dc, "money")
    if type(money) == "table" and type(money.toNumber) == "function" then
        local ok, value = pcall(money.toNumber, money)
        if ok then return tonumber(value) end
    end
    local fromClient = clientGet({"money"})
    if fromClient ~= nil then return tonumber(fromClient) end
    return tonumber(money)
end
local function refreshData()
    local dc = Integration.modules.DataController
    State.data.roster = readAtom(dc, "roster")
    if type(State.data.roster) ~= "table" then
        local fromDs = clientGet({"roster"})
        if type(fromDs) == "table" then State.data.roster = fromDs end
    end
    State.data.rebirth = readAtom(dc, "rebirth")
    State.data.towerBest = readAtom(dc, "towerBest")
    State.data.chicken = readAtom(dc, "chicken")
    State.data.recyclerLevel = readAtom(dc, "recyclerLevel")
    State.data.money = readMoney()
    State.data.coop = clientGet({"coop"})
    State.data.incubator = clientGet({"incubator"})
    if State.data.towerBest ~= nil then State.tower.best = State.data.towerBest end
end
local function getRebirthInfo()
    local bonus = Integration.modules.RebirthBonus
    local rebirth = State.data.rebirth
    local count = (type(rebirth) == "table" and tonumber(rebirth.count)) or 0
    local best = tonumber(State.data.towerBest) or 0
    local required, ready = nil, false
    if bonus then
        if type(bonus.requirementFloor) == "function" then
            local ok, v = pcall(bonus.requirementFloor, count)
            if ok then required = v end
        end
        if type(bonus.ready) == "function" then
            local ok, v = pcall(bonus.ready, best, count)
            if ok then ready = v == true end
        end
    end
    return count, required, ready, best
end
local function isTowerActive()
    if State.tower.runActive then return true end
    local s = State.tower.status
    if s == "RUNNING" or s == "FLOOR CLEARED" then return true end
    if State.tower.continue and State.tower.continue.open then return true end
    return false
end
local function isContinueOpen()
    return State.tower.continue ~= nil and State.tower.continue.open == true
end
local function tryInvoke(name, ...)
    local core = Integration.modules.Remotes
    local args = table.pack(...)
    if core and core.defs and core.defs[name] then
        local def = core.defs[name]
        local kind = def.kind or def.type
        if kind == "Function" and type(core.invoke) == "function" then
            local ok, res = pcall(function() return core.invoke(def, table.unpack(args, 1, args.n)) end)
            return ok, res
        end
        if kind == "Event" and type(core.fire) == "function" then
            local ok, err = pcall(function() core.fire(def, table.unpack(args, 1, args.n)) end)
            return ok, err
        end
    end
    local remote = Integration.remotes[name]
    if not remote then return false, "missing" end
    if remote:IsA("RemoteFunction") then
        local ok, res = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
        if not ok then return false, res end
        return true, res
    elseif remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent") then
        local ok, err = pcall(function() remote:FireServer(table.unpack(args, 1, args.n)) end)
        return ok, err
    end
    return false, "bad class"
end
local function responseOK(response)
    return type(response) == "table" and response.ok == true
end

--------------------------------------------------------------------
-- DISPLAY NAME RESOLVERS (UI only)
--------------------------------------------------------------------
local function titleCaseId(id)
    local s = tostring(id or "")
    if s == "" then return s end
    local parts = {}
    for word in string.gmatch(s, "[^_%-%s]+") do
        table.insert(parts, string.upper(string.sub(word, 1, 1)) .. string.lower(string.sub(word, 2)))
    end
    if #parts == 0 then return s end
    return table.concat(parts, " ")
end
local function resolveEggDisplayName(eggId)
    if eggId == nil then return "unknown" end
    local catalog = Integration.modules.Catalog
    local eggsTable = (catalog and catalog.eggs) or Integration.modules.CatalogEggs
    if type(eggsTable) == "table" then
        local entry = eggsTable[eggId] or eggsTable[tostring(eggId)]
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
            return entry.name
        end
    end
    local fallback = tostring(eggId)
    return fallback ~= "" and fallback or "unknown"
end
local function resolveRarityDisplayName(rarityId)
    if rarityId == nil then return "unknown" end
    local catalog = Integration.modules.Catalog
    local rarity = catalog and (catalog.Rarity or catalog.rarity)
    if type(rarity) == "table" then
        if type(rarity.displayName) == "table" and type(rarity.displayName[rarityId]) == "string" and rarity.displayName[rarityId] ~= "" then
            return rarity.displayName[rarityId]
        end
        local entry = rarity[rarityId]
        if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= "" then
            return entry.name
        end
    end
    local named = titleCaseId(rarityId)
    return named ~= "" and named or tostring(rarityId)
end
local function resolveAbilityDisplayName(ability)
    if type(ability) == "table" then
        if type(ability.name) == "string" and ability.name ~= "" then return ability.name end
        if ability.id ~= nil then return titleCaseId(ability.id) end
    elseif ability ~= nil then
        local catalog = Integration.modules.Catalog
        local abilities = catalog and catalog.abilities
        if type(abilities) == "table" then
            local def = abilities[ability]
            if type(def) == "table" and type(def.name) == "string" and def.name ~= "" then return def.name end
        end
        return titleCaseId(ability)
    end
    return "unknown"
end
local function diagNameOnce(kind, id, displayName)
    local key = kind .. ":" .. tostring(id)
    if State.nameDiagSeen[key] then return end
    State.nameDiagSeen[key] = true
    if displayName == tostring(id) then
        log("UI", string.format("[%s UI] fallback raw id=%s", kind, tostring(id)))
    else
        log("UI", string.format("[%s UI] id=%s name=%s", kind, tostring(id), tostring(displayName)))
    end
end

--------------------------------------------------------------------
-- MOVEMENT
--------------------------------------------------------------------
local activeTween = nil
local function cancelMovement()
    if activeTween then pcall(function() activeTween:Cancel() end) activeTween = nil end
end
local function getHRP()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then return hrp end
    return nil
end
local function moveTo(targetPos, mode, owner)
    if State.movementOwner ~= "NONE" and State.movementOwner ~= owner then
        if owner ~= "METEOR_AVOIDANCE" and owner ~= "PIT_EXIT" then return false end
    end
    cancelMovement()
    State.movementOwner = owner
    local hrp = getHRP()
    if not hrp then State.movementOwner = "NONE" return false end
    mode = mode or "Walk"
    if mode == "Teleport" then
        hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
        State.movementOwner = "NONE"
        return true
    end
    if mode == "Walk" then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            hum:MoveTo(targetPos)
            local deadline = os.clock() + 8
            while os.clock() < deadline and State.movementOwner == owner do
                if (hrp.Position - targetPos).Magnitude < 4 then break end
                task.wait(0.15)
            end
        end
        if State.movementOwner == owner then State.movementOwner = "NONE" end
        return true
    end
    local dist = (hrp.Position - targetPos).Magnitude
    local dur = math.clamp(dist / 48, 0.12, 1.8)
    activeTween = TweenService:Create(hrp, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
    })
    activeTween:Play()
    activeTween.Completed:Wait()
    activeTween = nil
    if State.movementOwner == owner then State.movementOwner = "NONE" end
    return true
end
local MOVEMENT_RANK = { NONE = 0, AUTO_COLLECT_EGG = 1, AUTO_HOT_EGG = 2, PIT_EXIT = 3, METEOR_AVOIDANCE = 4 }
local function movementCanRun(priority)
    local owner = State.movementOwner or "NONE"
    if owner == "NONE" or owner == priority then return true end
    return (MOVEMENT_RANK[owner] or 0) < (MOVEMENT_RANK[priority] or 0)
end
local MovementAdapter = {
    canRun = function(_, priority) return movementCanRun(priority) end,
    isBlocked = function(_, priority) return not movementCanRun(priority) end,
    tryAcquire = function(_, priority)
        if not movementCanRun(priority) then return false end
        if State.movementOwner ~= "NONE" and State.movementOwner ~= priority then
            if (MOVEMENT_RANK[State.movementOwner] or 0) > (MOVEMENT_RANK[priority] or 0) then return false end
            cancelMovement()
        end
        State.movementOwner = priority
        return { priority = priority }
    end,
    release = function(lease)
        if type(lease) == "table" and lease.priority and State.movementOwner == lease.priority then
            State.movementOwner = "NONE"
        elseif State.movementOwner == "AUTO_COLLECT_EGG" then
            State.movementOwner = "NONE"
        end
    end,
}

--------------------------------------------------------------------
-- createAutoSellChickens (SOURCE A — full backend restored)
--------------------------------------------------------------------
local function createAutoSellChickens(deps)
    assert(type(deps) == "table", "createAutoSellChickens(deps) requires a dependency table")
    assert(type(deps.Remotes) == "table", "deps.Remotes is required")
    assert(type(deps.Remotes.invoke) == "function", "deps.Remotes.invoke is required")
    assert(type(deps.Remotes.defs) == "table" and deps.Remotes.defs.SellChickens ~= nil, "SellChickens required")
    assert(type(deps.DataController) == "table", "deps.DataController is required")
    assert(type(deps.DataController.roster) == "function", "roster required")
    assert(type(deps.Catalog) == "table", "deps.Catalog is required")
    local Remotes, DataController, Catalog = deps.Remotes, deps.DataController, deps.Catalog
    local logSink = deps.log
    local enabled, destroyed, generation, sellInProgress = false, false, 0, false
    local rosterUnsubscribe, wakeEvaluation, lastRosterFingerprint, lastLogKey = nil, false, nil, nil
    local configRevision = 0
    local selectedRarities, abilityWhitelist = {}, { voodoo = true, cycleofash = true }
    local protectMutated, protectFavorites, dryRun = true, true, true
    local maxBatchSize, pollInterval, confirmationTimeout, retryDelay = 10, 1, 8, 2
    local status, lastError = "DISABLED", nil
    local stats = {
        totalEvaluated = 0, totalSoldConfirmed = 0, totalProtectedActive = 0, totalProtectedFavorite = 0,
        totalProtectedMutated = 0, totalProtectedAbility = 0, totalProtectedIncubator = 0, totalProtectedBusy = 0,
        totalFailedNotConfirmed = 0, lastBatchSize = 0, lastError = nil,
    }
    local function emit(message, force)
        if type(logSink) ~= "function" then return end
        local key = tostring(message)
        if force or key ~= lastLogKey then lastLogKey = key; pcall(logSink, "[AutoSell] " .. key) end
    end
    local function invalidateEvaluation(reason)
        lastRosterFingerprint = nil
        configRevision = configRevision + 1
        wakeEvaluation = true
        if reason then
            emit("Evaluation forced by config change — " .. tostring(reason), true)
        end
    end
    local function setStatus(nextStatus, detail)
        status = nextStatus
        if detail then emit(nextStatus .. " — " .. tostring(detail)) else emit(nextStatus) end
    end
    local function sleep(seconds)
        if task and type(task.wait) == "function" then task.wait(seconds) elseif wait then wait(seconds) end
    end
    local function spawn(fn)
        if task and type(task.spawn) == "function" then return task.spawn(fn) end
        return coroutine.wrap(fn)()
    end
    local function copyMap(source)
        local result = {}
        for key, value in pairs(source or {}) do result[key] = value end
        return result
    end
    local function copyArray(source)
        local result = {}
        for i, value in ipairs(source or {}) do result[i] = value end
        return result
    end
    local function readRoster()
        local ok, roster = pcall(DataController.roster)
        if not ok or type(roster) ~= "table" then return nil, "ROSTER UNAVAILABLE" end
        return roster
    end
    local function rarityCatalog() return Catalog.Rarity or Catalog.rarity or {} end
    local function rarityRank(rarityId)
        local rarity = rarityCatalog()
        if type(rarity.rankOf) == "function" then
            local ok, rank = pcall(rarity.rankOf, rarityId)
            if ok and type(rank) == "number" then return rank end
        end
        if type(rarity.rank) == "table" and type(rarity.rank[rarityId]) == "number" then return rarity.rank[rarityId] end
        return math.huge
    end
    local function getAvailableRarities()
        local rarity, result, seen = rarityCatalog(), {}, {}
        local rankTable = rarity.rank
        if type(rankTable) == "table" then
            for id in pairs(rankTable) do
                if type(id) == "string" and not seen[id] then seen[id] = true; table.insert(result, id) end
            end
        end
        table.sort(result, function(a, b)
            local ar, br = rarityRank(a), rarityRank(b)
            if ar == br then return a < b end
            return ar < br
        end)
        return result
    end
    local function resolveRarity(chicken)
        if chicken.rarity ~= nil then return chicken.rarity end
        local typeDef = chicken.typeId and Catalog.chickenTypes and Catalog.chickenTypes[chicken.typeId]
        if typeDef and typeDef.rarity ~= nil then return typeDef.rarity end
        local defaultType = Catalog.defaultChickenType
        return defaultType and defaultType.rarity or nil
    end
    local function resolveAbility(chicken)
        local ability = chicken.ability
        if ability == nil then
            local typeDef = chicken.typeId and Catalog.chickenTypes and Catalog.chickenTypes[chicken.typeId]
            ability = typeDef and typeDef.signature or nil
        end
        if ability == nil then
            local defaultType = Catalog.defaultChickenType
            ability = defaultType and defaultType.signature or nil
        end
        if ability == nil then ability = "beyblade" end
        return ability
    end
    local function getAvailableAbilities()
        local result, abilities = {}, Catalog.abilities
        if type(abilities) ~= "table" then return result end
        for key, definition in pairs(abilities) do
            if type(key) == "string" then
                table.insert(result, {
                    id = definition and definition.id or key,
                    name = definition and definition.name or key,
                    rarity = definition and definition.rarity or nil,
                })
            end
        end
        table.sort(result, function(a, b) return tostring(a.id) < tostring(b.id) end)
        return result
    end
    local function getIncubatorDecision()
        if type(deps.getIncubatorOccupantId) == "function" then
            local ok, occupantId = pcall(deps.getIncubatorOccupantId)
            if ok and occupantId ~= nil then return "ID", occupantId end
        end
        if type(deps.isIncubatorOccupied) == "function" then
            local ok, isOccupied = pcall(deps.isIncubatorOccupied)
            if not ok then return "PAUSE", nil end
            if isOccupied == true then return "PAUSE", nil end
            return "NONE", nil
        end
        return "UNAVAILABLE", nil
    end
    local function globalPauseReason()
        local incubatorMode = getIncubatorDecision()
        if incubatorMode == "PAUSE" then return "PAUSED — INCUBATOR OCCUPIED" end
        if type(deps.isTradeActive) == "function" then
            local ok, active = pcall(deps.isTradeActive)
            if not ok or active == true then return "PAUSED — TRADE ACTIVE" end
        end
        if type(deps.isFusionActive) == "function" then
            local ok, active = pcall(deps.isFusionActive)
            if not ok or active == true then return "PAUSED — FUSION ACTIVE" end
        end
        return nil
    end
    local function makeLookup(roster)
        local lookup = {}
        for _, chicken in ipairs(roster.chickens or {}) do
            if type(chicken) == "table" and chicken.id ~= nil then lookup[chicken.id] = chicken end
        end
        return lookup
    end
    local function evaluateChicken(chicken, roster, incubatorMode, incubatorId)
        stats.totalEvaluated = stats.totalEvaluated + 1
        local rarity = resolveRarity(chicken)
        local ability = resolveAbility(chicken)
        local function decide(shouldSell, reason)
            emit(string.format("id=%s rarity=%s ability=%s decision=%s",
                tostring(chicken.id), tostring(rarity), tostring(ability), tostring(reason)))
            return shouldSell, reason
        end
        if chicken.id == roster.activeId then
            stats.totalProtectedActive = stats.totalProtectedActive + 1
            return decide(false, "KEEP_ACTIVE")
        end
        if protectFavorites and chicken.favorite == true then
            stats.totalProtectedFavorite = stats.totalProtectedFavorite + 1
            return decide(false, "KEEP_FAVORITE")
        end
        if incubatorMode == "ID" and chicken.id == incubatorId then
            stats.totalProtectedIncubator = stats.totalProtectedIncubator + 1
            return decide(false, "KEEP_INCUBATOR")
        end
        if type(deps.isChickenBusy) == "function" then
            local ok, busy = pcall(deps.isChickenBusy, chicken.id)
            if not ok or busy == true then
                stats.totalProtectedBusy = stats.totalProtectedBusy + 1
                return decide(false, "KEEP_BUSY")
            end
        end
        if protectMutated and chicken.mutation ~= nil then
            stats.totalProtectedMutated = stats.totalProtectedMutated + 1
            return decide(false, "KEEP_MUTATED")
        end
        if abilityWhitelist[ability] then
            stats.totalProtectedAbility = stats.totalProtectedAbility + 1
            return decide(false, "KEEP_ABILITY")
        end
        -- normalize rarity key to lowercase string for map lookup (Catalog uses lowercase ids)
        local rarityKey = rarity ~= nil and string.lower(tostring(rarity)) or nil
        if rarityKey ~= nil and selectedRarities[rarityKey] then
            return decide(true, "SELL")
        end
        -- also try exact key if catalog already lowercase
        if rarity ~= nil and selectedRarities[rarity] then
            return decide(true, "SELL")
        end
        return decide(false, "KEEP_RARITY")
    end
    local function collectCandidates(roster)
        local incubatorMode, incubatorId = getIncubatorDecision()
        local ids, reasons = {}, {}
        if incubatorMode == "PAUSE" then return nil, reasons, "PAUSED — INCUBATOR OCCUPIED" end
        for _, chicken in ipairs(roster.chickens or {}) do
            if type(chicken) == "table" and chicken.id ~= nil then
                local shouldSell, reason = evaluateChicken(chicken, roster, incubatorMode, incubatorId)
                reasons[chicken.id] = reason
                if shouldSell then table.insert(ids, chicken.id) end
            end
        end
        return ids, reasons, nil
    end
    local function revalidateBatch(candidateIds)
        local roster, err = readRoster()
        if not roster then return {}, err end
        local pause = globalPauseReason()
        if pause then return {}, pause end
        local incubatorMode, incubatorId = getIncubatorDecision()
        if incubatorMode == "PAUSE" then return {}, "PAUSED — INCUBATOR OCCUPIED" end
        local lookup, finalIds = makeLookup(roster), {}
        for _, id in ipairs(candidateIds) do
            local chicken = lookup[id]
            if chicken and evaluateChicken(chicken, roster, incubatorMode, incubatorId) then
                table.insert(finalIds, id)
            end
        end
        return finalIds, nil
    end
    local function waitForConfirmation(requestedIds, requestGeneration)
        local deadline = os.clock() + confirmationTimeout
        local confirmed = {}
        while os.clock() < deadline do
            if destroyed or not enabled or requestGeneration ~= generation then return confirmed, "CANCELLED" end
            local roster = readRoster()
            if type(roster) == "table" then
                local lookup = makeLookup(roster)
                local count = 0
                for _, id in ipairs(requestedIds) do
                    if not confirmed[id] and lookup[id] == nil then confirmed[id] = true end
                    if confirmed[id] then count = count + 1 end
                end
                if count == #requestedIds then break end
            end
            sleep(0.25)
        end
        return confirmed, nil
    end
    local function fingerprint(roster)
        local parts = {}
        for _, chicken in ipairs(roster.chickens or {}) do
            if type(chicken) == "table" then
                table.insert(parts, tostring(chicken.id) .. ":" .. tostring(chicken.level) .. ":" .. tostring(chicken.favorite) .. ":" .. tostring(chicken.mutation) .. ":" .. tostring(chicken.ability))
            end
        end
        table.sort(parts)
        return table.concat(parts, "|") .. "|active=" .. tostring(roster.activeId)
    end
    local function performEvaluation(workerGeneration)
        if destroyed or not enabled or workerGeneration ~= generation or sellInProgress then return end
        local pause = globalPauseReason()
        if pause then setStatus(pause) return end
        setStatus("SCANNING")
        local roster, rosterError = readRoster()
        if not roster then
            lastError = rosterError; stats.lastError = rosterError
            setStatus("ERROR", rosterError) return
        end
        local currentFingerprint = fingerprint(roster) .. "|cfg=" .. tostring(configRevision)
        if currentFingerprint == lastRosterFingerprint then setStatus("IDLE") return end
        lastRosterFingerprint = currentFingerprint
        -- log selected rarities once per forced eval
        do
            local sel = {}
            for id, on in pairs(selectedRarities) do if on then table.insert(sel, id) end end
            table.sort(sel)
            emit("Selected rarities: " .. (#sel > 0 and table.concat(sel, ", ") or "(none)"), true)
        end
        local candidateIds, _, collectionError = collectCandidates(roster)
        if collectionError then setStatus(collectionError) return end
        if #candidateIds == 0 then setStatus("NO MATCHING CHICKENS") return end
        setStatus("CANDIDATES FOUND", tostring(#candidateIds))
        local offset = 1
        while offset <= #candidateIds and enabled and not destroyed and workerGeneration == generation do
            local requested = {}
            for index = offset, math.min(offset + maxBatchSize - 1, #candidateIds) do
                table.insert(requested, candidateIds[index])
            end
            offset = offset + #requested
            local finalIds, validationError = revalidateBatch(requested)
            if validationError then
                lastError = validationError; stats.lastError = validationError
                setStatus(validationError) return
            end
            if #finalIds == 0 then continue end
            stats.lastBatchSize = #finalIds
            if dryRun then
                for _, id in ipairs(finalIds) do emit("WOULD SELL: id = " .. tostring(id)) end
                setStatus("CONFIRMED", "DRY RUN")
                continue
            end
            sellInProgress = true
            setStatus("SELLING", tostring(#finalIds))
            local requestGeneration = generation
            local ok, response = pcall(Remotes.invoke, Remotes.defs.SellChickens, finalIds)
            if not ok then
                sellInProgress = false
                lastError = tostring(response); stats.lastError = lastError
                stats.totalFailedNotConfirmed = stats.totalFailedNotConfirmed + #finalIds
                setStatus("ERROR", lastError)
                sleep(retryDelay)
                continue
            end
            setStatus("WAITING CONFIRMATION")
            local confirmed = waitForConfirmation(finalIds, requestGeneration)
            sellInProgress = false
            local confirmedCount = 0
            for _, id in ipairs(finalIds) do
                if confirmed[id] then
                    confirmedCount = confirmedCount + 1
                    stats.totalSoldConfirmed = stats.totalSoldConfirmed + 1
                else
                    stats.totalFailedNotConfirmed = stats.totalFailedNotConfirmed + 1
                end
            end
            if confirmedCount == #finalIds then setStatus("CONFIRMED")
            else setStatus("WAITING CONFIRMATION", "partial"); sleep(retryDelay) end
        end
    end
    local function scheduleEvaluation() wakeEvaluation = true end
    local function worker(workerGeneration)
        while not destroyed and enabled and workerGeneration == generation do
            if wakeEvaluation or rosterUnsubscribe == nil then
                wakeEvaluation = false
                performEvaluation(workerGeneration)
            end
            if rosterUnsubscribe ~= nil then sleep(0.25) else sleep(pollInterval) end
        end
        if workerGeneration == generation then sellInProgress = false end
    end
    local api = {}
    function api.setAutoSell(value)
        if destroyed then return false end
        local nextValue = value == true
        if enabled == nextValue then return true end
        generation = generation + 1
        enabled = nextValue
        sellInProgress = false
        lastRosterFingerprint = nil
        configRevision = configRevision + 1
        wakeEvaluation = true
        if not enabled then setStatus("DISABLED") return true end
        setStatus("IDLE")
        emit("Auto Sell enabled — fresh evaluation", true)
        if type(deps.subscribeRoster) == "function" then
            local ok, unsubscribe = pcall(deps.subscribeRoster, scheduleEvaluation)
            if ok and type(unsubscribe) == "function" then rosterUnsubscribe = unsubscribe else rosterUnsubscribe = nil end
        end
        local workerGeneration = generation
        spawn(function() worker(workerGeneration) end)
        return true
    end
    function api.isEnabled() return enabled end
    function api.setRaritySelected(rarityId, value)
        if type(rarityId) ~= "string" or rarityId == "" then return false end
        local key = string.lower(rarityId)
        selectedRarities[key] = value == true
        invalidateEvaluation("rarity:" .. key .. "=" .. tostring(value == true))
        return true
    end
    function api.isRaritySelected(rarityId)
        if type(rarityId) ~= "string" then return false end
        return selectedRarities[string.lower(rarityId)] == true or selectedRarities[rarityId] == true
    end
    function api.getSelectedRarities()
        local result = {}
        for id, selected in pairs(selectedRarities) do if selected then table.insert(result, id) end end
        table.sort(result, function(a, b)
            local ar, br = rarityRank(a), rarityRank(b)
            if ar == br then return a < b end
            return ar < br
        end)
        return result
    end
    function api.clearRaritySelection() selectedRarities = {}; invalidateEvaluation("clear rarities") end
    function api.selectAllRarities()
        for _, id in ipairs(getAvailableRarities()) do selectedRarities[string.lower(id)] = true end
        invalidateEvaluation("select all rarities")
    end
    function api.getAvailableRarities() return getAvailableRarities() end
    function api.setProtectMutated(value) protectMutated = value == true; invalidateEvaluation("protectMutated=" .. tostring(value == true)) end
    function api.getProtectMutated() return protectMutated end
    function api.setProtectFavorites(value) protectFavorites = value == true; invalidateEvaluation("protectFavorites=" .. tostring(value == true)) end
    function api.getProtectFavorites() return protectFavorites end
    function api.setAbilityWhitelisted(abilityId, value)
        if type(abilityId) ~= "string" or abilityId == "" then return false end
        abilityWhitelist[abilityId] = value == true
        invalidateEvaluation("ability:" .. abilityId .. "=" .. tostring(value == true))
        return true
    end
    function api.isAbilityWhitelisted(abilityId) return abilityWhitelist[abilityId] == true end
    function api.getAbilityWhitelist() return copyMap(abilityWhitelist) end
    function api.getAvailableAbilities() return getAvailableAbilities() end
    function api.clearAbilityWhitelist() abilityWhitelist = {}; invalidateEvaluation("clear ability whitelist") end
    function api.setMaxBatchSize(value)
        local number = tonumber(value)
        if not number then return false end
        maxBatchSize = math.clamp(math.floor(number), 1, 100)
        return true
    end
    function api.getMaxBatchSize() return maxBatchSize end
    function api.setDryRun(value) dryRun = value == true; invalidateEvaluation("dryRun=" .. tostring(value == true)) end
    function api.getDryRun() return dryRun end
    function api.getStatus() return status end
    function api.getStats()
        local result = copyMap(stats)
        result.selectedRarities = copyArray(api.getSelectedRarities())
        result.abilityWhitelist = copyMap(abilityWhitelist)
        result.maxBatchSize = maxBatchSize
        result.dryRun = dryRun
        return result
    end
    function api.destroy()
        if destroyed then return end
        destroyed = true
        enabled = false
        generation = generation + 1
        sellInProgress = false
        if type(rosterUnsubscribe) == "function" then pcall(rosterUnsubscribe) end
        rosterUnsubscribe = nil
        setStatus("DISABLED")
    end
    return api
end

--------------------------------------------------------------------
-- createAutoCollectEggs (NestEgg — preserved)
--------------------------------------------------------------------
local function createAutoCollectEggs(deps)
    assert(type(deps) == "table", "createAutoCollectEggs(deps) requires a dependency table")
    local CollectionService = assert(deps.CollectionService, "CollectionService is required")
    local PlayersSvc = assert(deps.Players, "Players is required")
    local TweenSvc = assert(deps.TweenService, "TweenService is required")
    local LP = assert(deps.LocalPlayer or PlayersSvc.LocalPlayer, "LocalPlayer is required")
    local movement = deps.movement
    local DataController = deps.DataController
    local logSink = deps.log
    local PRIORITY = "AUTO_COLLECT_EGG"
    local MODES = { Walk = true, Tween = true, Teleport = true }
    local trackedEggs, attributeWaits, connections, temporaryConnections = {}, {}, {}, {}
    local serial, generation, workerRunning, enabled, destroyed = 0, 0, false, false, false
    local movementLease, activeTw, activeTweenConnection, activeMoveConnection = nil, nil, nil, nil
    local currentTarget, movementMode, status, lastError = nil, "Walk", "DISABLED", nil
    local inventoryConfirmation, retryCount, failedUntil = "UNAVAILABLE", 0, {}
    local CONFIG = {
        attributeWaitSeconds = 1.25, pollSeconds = 0.25, arrivalDistance = 3.5, arrivalHeight = 2.25,
        collectionTimeout = 4.5, maxRetries = 3, retryDelay = 0.7, failedCooldown = 8,
        positionRefreshDistance = 2.5, tweenDuration = 0.65, inventoryConfirmSeconds = 0.9,
    }
    local function now() return os.clock() end
    local function clog(message)
        if type(logSink) == "function" then pcall(logSink, "[CollectEgg] " .. tostring(message)) end
    end
    local function setStatus(nextStatus, detail)
        status = nextStatus
        if detail ~= nil then lastError = tostring(detail) end
    end
    local function disconnect(connection)
        if connection then pcall(function() connection:Disconnect() end) end
    end
    local function disconnectList(list)
        for key, connection in pairs(list) do disconnect(connection); list[key] = nil end
    end
    local function isValidInstance(instance)
        return instance and instance:IsA("BasePart") and instance.Parent ~= nil and CollectionService:HasTag(instance, "NestEgg")
    end
    local function getRootAndHumanoid()
        local character = LP.Character
        if not character then return nil, nil end
        local root = character:FindFirstChild("HumanoidRootPart")
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then return nil, nil end
        return root, humanoid
    end
    local function horizontalDistance(a, b)
        local delta = a - b
        return Vector3.new(delta.X, 0, delta.Z).Magnitude
    end
    local function safeInventory()
        if type(deps.getRoster) == "function" then
            local ok, roster = pcall(deps.getRoster)
            if ok and type(roster) == "table" then return roster end
        end
        if DataController and type(DataController.roster) == "function" then
            local ok, roster = pcall(function() return DataController.roster() end)
            if ok and type(roster) == "table" then return roster end
        end
        return nil
    end
    local function inventoryAmount(tier)
        local roster = safeInventory()
        if not roster or type(roster.eggs) ~= "table" then return nil end
        local value = roster.eggs[tier]
        return type(value) == "number" and value or nil
    end
    local function clearAttributeWait(instance)
        local waitState = attributeWaits[instance]
        if not waitState then return end
        for _, connection in pairs(waitState.connections) do disconnect(connection) end
        attributeWaits[instance] = nil
    end
    local function removeTracked(instance)
        clearAttributeWait(instance)
        trackedEggs[instance] = nil
        failedUntil[instance] = nil
        if currentTarget == instance then currentTarget = nil end
    end
    local function registerReady(instance)
        if destroyed or not isValidInstance(instance) then return false end
        local owner = instance:GetAttribute("owner")
        local tier = instance:GetAttribute("tier")
        if owner == nil or tier == nil then return false end
        if owner ~= LP.UserId then removeTracked(instance) return false end
        serial = serial + 1
        local existing = trackedEggs[instance]
        local record = existing or { serial = serial, retries = 0 }
        record.tier = tier
        record.position = instance.Position - Vector3.new(0, instance.Size.Y / 2, 0)
        record.rawPosition = instance.Position
        record.inventoryBefore = inventoryAmount(tier)
        record.lastSeen = now()
        trackedEggs[instance] = record
        clearAttributeWait(instance)
        if not existing then clog(("NestEgg detected | tier = %s"):format(tostring(tier))) end
        return true
    end
    local function waitForAttributes(instance)
        if destroyed or attributeWaits[instance] or trackedEggs[instance] then return end
        if not instance or not instance:IsA("BasePart") then return end
        local deadline = now() + CONFIG.attributeWaitSeconds
        local waitState = { connections = {}, deadline = deadline }
        attributeWaits[instance] = waitState
        local function tryReady()
            if destroyed or not isValidInstance(instance) then clearAttributeWait(instance) return end
            if instance:GetAttribute("owner") ~= nil and instance:GetAttribute("tier") ~= nil then
                registerReady(instance)
            end
        end
        waitState.connections.owner = instance:GetAttributeChangedSignal("owner"):Connect(tryReady)
        waitState.connections.tier = instance:GetAttributeChangedSignal("tier"):Connect(tryReady)
        temporaryConnections[instance] = task.spawn(function()
            while not destroyed and attributeWaits[instance] == waitState and now() < deadline do
                tryReady()
                if not attributeWaits[instance] then return end
                task.wait(0.1)
            end
            if attributeWaits[instance] == waitState then clearAttributeWait(instance) end
            temporaryConnections[instance] = nil
        end)
        tryReady()
    end
    local function onAdded(instance)
        if not instance or not instance:IsA("BasePart") then return end
        if instance:GetAttribute("owner") == nil or instance:GetAttribute("tier") == nil then
            waitForAttributes(instance) return
        end
        registerReady(instance)
    end
    local function inventoryConfirmationFor(record)
        if not record or record.inventoryBefore == nil then
            inventoryConfirmation = "UNAVAILABLE" return
        end
        local deadline = now() + CONFIG.inventoryConfirmSeconds
        while not destroyed and now() < deadline do
            local currentAmount = inventoryAmount(record.tier)
            if currentAmount ~= nil then
                if currentAmount > record.inventoryBefore then
                    inventoryConfirmation = "AVAILABLE — INCREASE OBSERVED" return
                end
                inventoryConfirmation = "AVAILABLE — INCREASE NOT OBSERVED"
            end
            task.wait(0.1)
        end
    end
    local function onRemoved(instance)
        local record = trackedEggs[instance]
        local wasTarget = currentTarget == instance
        if not record then clearAttributeWait(instance) return end
        removeTracked(instance)
        if not wasTarget or destroyed then return end
        setStatus("COLLECTED")
        clog(("Target removed | tier = %s"):format(tostring(record.tier)))
        inventoryConfirmation = "UNAVAILABLE"
        inventoryConfirmationFor(record)
        if enabled and not destroyed then currentTarget = nil end
    end
    local function initialScan()
        for _, instance in CollectionService:GetTagged("NestEgg") do onAdded(instance) end
    end
    local function releaseMovement()
        if activeTw then pcall(function() activeTw:Cancel() end) activeTw = nil end
        disconnect(activeTweenConnection); activeTweenConnection = nil
        disconnect(activeMoveConnection); activeMoveConnection = nil
        if movementLease ~= nil and movement and type(movement.release) == "function" then
            pcall(movement.release, movementLease)
        end
        movementLease = nil
    end
    local function movementAvailable()
        if not movement then return true end
        if type(movement.canRun) == "function" then
            local ok, result = pcall(movement.canRun, movement, PRIORITY)
            if ok and result == false then return false end
        end
        if type(movement.isBlocked) == "function" then
            local ok, result = pcall(movement.isBlocked, movement, PRIORITY)
            if ok and result == true then return false end
        end
        return true
    end
    local function acquireMovement()
        if movementLease ~= nil then return true end
        if not movementAvailable() then setStatus("PAUSED MOVEMENT BUSY") return false end
        if movement and type(movement.tryAcquire) == "function" then
            local ok, lease = pcall(movement.tryAcquire, movement, PRIORITY)
            if not ok or lease == false or lease == nil then
                setStatus("PAUSED MOVEMENT BUSY") return false
            end
            movementLease = lease
        end
        return true
    end
    local function targetStillValid(instance)
        return enabled and not destroyed and trackedEggs[instance] ~= nil and isValidInstance(instance)
    end
    local function chooseTarget()
        local root = select(1, getRootAndHumanoid())
        if not root then return nil end
        local best, bestDistance, bestSerial
        local currentTime = now()
        for instance, record in pairs(trackedEggs) do
            if isValidInstance(instance) and instance:GetAttribute("owner") == LP.UserId then
                record.position = instance.Position - Vector3.new(0, instance.Size.Y / 2, 0)
                record.rawPosition = instance.Position
                local blockedUntil = failedUntil[instance] or 0
                if currentTime >= blockedUntil then
                    local distance = horizontalDistance(root.Position, record.rawPosition)
                    if not bestDistance or distance < bestDistance or (distance == bestDistance and record.serial < bestSerial) then
                        best = instance; bestDistance = distance; bestSerial = record.serial
                    end
                end
            else
                removeTracked(instance)
            end
        end
        return best, bestDistance
    end
    local function targetDistance(instance)
        local root = select(1, getRootAndHumanoid())
        if not root or not trackedEggs[instance] or not isValidInstance(instance) then return nil end
        return horizontalDistance(root.Position, instance.Position)
    end
    local function waitForCollection(instance, token)
        setStatus("WAITING COLLECTION")
        local deadline = now() + CONFIG.collectionTimeout
        while enabled and not destroyed and generation == token do
            if not targetStillValid(instance) then return true end
            if now() >= deadline then return false end
            task.wait(CONFIG.pollSeconds)
        end
        return true
    end
    local function walkTo(instance, token)
        local root, humanoid = getRootAndHumanoid()
        if not root or not humanoid then return false, "character unavailable" end
        local record = trackedEggs[instance]
        if not record then return true end
        setStatus("MOVING")
        humanoid:MoveTo(record.rawPosition)
        local moveFinished = false
        activeMoveConnection = humanoid.MoveToFinished:Connect(function() moveFinished = true end)
        local deadline = now() + CONFIG.collectionTimeout
        local lastDestination = record.rawPosition
        while enabled and not destroyed and generation == token and targetStillValid(instance) do
            local currentRoot = select(1, getRootAndHumanoid())
            if not currentRoot then break end
            local currentRecord = trackedEggs[instance]
            if not currentRecord then return true end
            if horizontalDistance(currentRoot.Position, instance.Position) <= CONFIG.arrivalDistance then
                setStatus("ARRIVED") return true
            end
            if horizontalDistance(lastDestination, currentRecord.rawPosition) >= CONFIG.positionRefreshDistance then
                lastDestination = currentRecord.rawPosition
                humanoid:MoveTo(lastDestination)
            end
            if now() >= deadline then break end
            task.wait(CONFIG.pollSeconds)
        end
        disconnect(activeMoveConnection); activeMoveConnection = nil
        return targetStillValid(instance), "walk timeout"
    end
    local function tweenTo(instance, token)
        local root = select(1, getRootAndHumanoid())
        if not root then return false, "character unavailable" end
        local record = trackedEggs[instance]
        if not record then return true end
        setStatus("MOVING")
        local destination = instance.Position + Vector3.new(0, CONFIG.arrivalHeight, 0)
        local tween = TweenSvc:Create(root, TweenInfo.new(CONFIG.tweenDuration, Enum.EasingStyle.Linear), {
            CFrame = CFrame.new(destination),
        })
        activeTw = tween
        local completed = false
        activeTweenConnection = tween.Completed:Connect(function() completed = true end)
        tween:Play()
        while enabled and not destroyed and generation == token and targetStillValid(instance) and not completed do
            task.wait(CONFIG.pollSeconds)
        end
        if activeTw == tween then activeTw = nil end
        disconnect(activeTweenConnection); activeTweenConnection = nil
        if not targetStillValid(instance) then return true end
        setStatus("ARRIVED")
        return true
    end
    local function teleportTo(instance)
        local root = select(1, getRootAndHumanoid())
        if not root then return false, "character unavailable" end
        local record = trackedEggs[instance]
        if not record or not targetStillValid(instance) then return true end
        setStatus("MOVING")
        root.CFrame = CFrame.new(instance.Position + Vector3.new(0, CONFIG.arrivalHeight, 0))
        setStatus("ARRIVED")
        return true
    end
    local function moveToTarget(instance, token)
        if not acquireMovement() then return false, "movement busy" end
        if movementMode == "Walk" then return walkTo(instance, token)
        elseif movementMode == "Tween" then return tweenTo(instance, token)
        elseif movementMode == "Teleport" then return teleportTo(instance) end
        return false, "invalid movement mode"
    end
    local function handleTargetFailure(instance)
        local record = trackedEggs[instance]
        if not record then return end
        record.retries = (record.retries or 0) + 1
        retryCount = record.retries
        if record.retries <= CONFIG.maxRetries then
            failedUntil[instance] = now() + CONFIG.retryDelay
        else
            failedUntil[instance] = now() + CONFIG.failedCooldown
        end
        setStatus("RETRYING")
    end
    local function worker(token)
        if workerRunning then return end
        workerRunning = true
        while enabled and not destroyed and generation == token do
            if not movementAvailable() then
                releaseMovement()
                setStatus("PAUSED MOVEMENT BUSY")
                task.wait(CONFIG.pollSeconds)
                continue
            end
            local target = chooseTarget()
            if not target then
                releaseMovement()
                setStatus(next(trackedEggs) and "SEARCHING" or "NO EGGS")
                task.wait(CONFIG.pollSeconds)
                continue
            end
            currentTarget = target
            local moved, moveError = moveToTarget(target, token)
            if not enabled or destroyed or generation ~= token then break end
            if not moved then
                if moveError == "movement busy" then setStatus("PAUSED MOVEMENT BUSY")
                else lastError = moveError; setStatus("ERROR", moveError) end
                releaseMovement()
                task.wait(CONFIG.pollSeconds)
                continue
            end
            if targetStillValid(target) then
                local collected = waitForCollection(target, token)
                if collected and not targetStillValid(target) then
                    setStatus("COLLECTED")
                else
                    handleTargetFailure(target)
                end
            end
            releaseMovement()
            currentTarget = nil
        end
        releaseMovement()
        workerRunning = false
    end
    local function startWorker()
        if workerRunning or destroyed then return end
        generation = generation + 1
        local token = generation
        task.spawn(function()
            local ok, err = xpcall(function() worker(token) end, debug.traceback)
            if not ok and not destroyed and generation == token then
                lastError = tostring(err)
                setStatus("ERROR", err)
                workerRunning = false
                releaseMovement()
            end
        end)
    end
    local function setAutoCollectEggs(value)
        if destroyed then return false end
        enabled = value == true
        generation = generation + 1
        if not enabled then
            setStatus("DISABLED")
            currentTarget = nil
            releaseMovement()
            return true
        end
        lastError = nil
        setStatus("SEARCHING")
        startWorker()
        return true
    end
    local function setMovementMode(mode)
        if type(mode) ~= "string" or not MODES[mode] then return false end
        if movementMode ~= mode then releaseMovement() end
        movementMode = mode
        return true
    end
    local function getTrackedEggs()
        local result = {}
        for instance, record in pairs(trackedEggs) do
            if isValidInstance(instance) and instance:GetAttribute("owner") == LP.UserId then
                table.insert(result, {
                    instance = instance, tier = record.tier, position = record.position,
                    distance = targetDistance(instance), retries = record.retries or 0,
                })
            end
        end
        return result
    end
    local function getStatus()
        return {
            state = status, enabled = enabled, movementMode = movementMode,
            trackedEggCount = #getTrackedEggs(),
            currentTargetTier = currentTarget and trackedEggs[currentTarget] and trackedEggs[currentTarget].tier or nil,
            currentTargetDistance = currentTarget and targetDistance(currentTarget) or nil,
            inventoryConfirmation = inventoryConfirmation, retryCount = retryCount, lastError = lastError,
        }
    end
    local function destroy()
        if destroyed then return end
        destroyed = true
        enabled = false
        generation = generation + 1
        currentTarget = nil
        releaseMovement()
        disconnectList(connections)
        for instance in pairs(attributeWaits) do clearAttributeWait(instance) end
        disconnectList(temporaryConnections)
        table.clear(trackedEggs)
        table.clear(failedUntil)
    end
    connections.added = CollectionService:GetInstanceAddedSignal("NestEgg"):Connect(onAdded)
    connections.removed = CollectionService:GetInstanceRemovedSignal("NestEgg"):Connect(onRemoved)
    initialScan()
    return {
        setAutoCollectEggs = setAutoCollectEggs,
        setMovementMode = setMovementMode,
        getMovementMode = function() return movementMode end,
        getStatus = getStatus,
        getTrackedEggs = getTrackedEggs,
        getTrackedEggCount = function() return #getTrackedEggs() end,
        destroy = destroy,
    }
end

--------------------------------------------------------------------
-- Feature construction
--------------------------------------------------------------------
local AutoCollectEggFeature = nil
local AutoSellFeature = nil

do
    local ok, feat = pcall(function()
        return createAutoCollectEggs({
            CollectionService = CollectionService,
            Players = Players,
            TweenService = TweenService,
            LocalPlayer = LocalPlayer,
            DataController = Integration.modules.DataController,
            movement = MovementAdapter,
            log = function(msg) log("COLLECT", msg) end,
            getRoster = function()
                if Integration.modules.DataController then
                    local ok2, r = pcall(function() return Integration.modules.DataController.roster() end)
                    if ok2 and type(r) == "table" then return r end
                end
                return State.data.roster
            end,
        })
    end)
    if ok then
        AutoCollectEggFeature = feat
        State.diagnostics["AutoCollectEggs"] = "READY"
    else
        State.diagnostics["AutoCollectEggs"] = "ERROR: " .. tostring(feat)
        log("ERROR", "AutoCollectEggs: " .. tostring(feat))
    end
end

do
    local remotes = Integration.modules.Remotes
    local dc = Integration.modules.DataController
    local catalog = Integration.modules.Catalog
    State.diagnostics["AutoSell.Remotes"] = remotes and "FOUND" or "MISSING"
    State.diagnostics["AutoSell.DataController"] = dc and "FOUND" or "MISSING"
    State.diagnostics["AutoSell.Catalog"] = catalog and "FOUND" or "MISSING"
    local sellDef = remotes and remotes.defs and remotes.defs.SellChickens
    State.diagnostics["AutoSell.SellChickens"] = sellDef and "FOUND" or "MISSING"
    if not remotes then
        State.diagnostics["AutoSell.Feature"] = "ERROR: Core.Remotes missing"
    elseif type(remotes.invoke) ~= "function" then
        State.diagnostics["AutoSell.Feature"] = "ERROR: Remotes.invoke missing"
    elseif not sellDef then
        State.diagnostics["AutoSell.Feature"] = "ERROR: Remotes.defs.SellChickens missing"
    elseif not dc then
        State.diagnostics["AutoSell.Feature"] = "ERROR: DataController missing"
    elseif type(dc.roster) ~= "function" then
        State.diagnostics["AutoSell.Feature"] = "ERROR: DataController.roster missing"
    elseif not catalog then
        State.diagnostics["AutoSell.Feature"] = "ERROR: Catalog missing"
    else
        local ok, featOrErr = pcall(function()
            return createAutoSellChickens({
                Remotes = remotes,
                DataController = dc,
                Catalog = catalog,
                log = function(msg) log("SELL", msg) end,
                getIncubatorOccupantId = function()
                    local inc = State.data.incubator
                    if type(inc) == "table" then return inc.occupantId or inc.chickenId or inc.activeId end
                    return nil
                end,
                -- Only treat as occupied when an actual chicken occupant id field exists.
                -- Incubator egg storage (#eggs > 0) is NOT occupancy and must not pause Auto Sell.
                isIncubatorOccupied = function()
                    local inc = State.data.incubator
                    if type(inc) ~= "table" then return false end
                    if inc.occupantId ~= nil or inc.chickenId ~= nil then return true end
                    if type(inc.occupant) == "table" and (inc.occupant.id ~= nil or inc.occupant.chickenId ~= nil) then
                        return true
                    end
                    return false
                end,
            })
        end)
        if ok and featOrErr then
            AutoSellFeature = featOrErr
            AutoSellFeature.setDryRun(true)
            State.diagnostics["AutoSell.Feature"] = "READY"
            log("INFO", "AutoSellFeature READY (DryRun ON)")
        else
            State.diagnostics["AutoSell.Feature"] = "ERROR: " .. tostring(featOrErr)
            log("ERROR", "AutoSell construct: " .. tostring(featOrErr))
        end
    end
end



--------------------------------------------------------------------
-- createAutoFuseChickens (FINAL verified/safety-patched backend — embedded)
--------------------------------------------------------------------
local RARITY_ORDER_FUSE = {
    "common", "uncommon", "rare", "epic", "legendary",
    "mythic", "divine", "celestial", "cosmic", "secret",
}
local RARITY_RANK_FUSE = {}
for index, rarity in ipairs(RARITY_ORDER_FUSE) do
    RARITY_RANK_FUSE[rarity] = index
end
local DEFAULT_FUSE_ABILITIES = {
    voodoo = true,
    cycleofash = true,
}
local function fuseCopyMap(source)
    local result = {}
    for key, value in pairs(source or {}) do
        result[key] = value
    end
    return result
end
local function fuseCopyArray(source)
    local result = {}
    for index, value in ipairs(source or {}) do
        result[index] = value
    end
    return result
end
local function fuseStableId(id)
    return tostring(id)
end
local function fuseWaitFor(seconds, deps)
    if type(deps.wait) == "function" then
        deps.wait(seconds)
    elseif task and type(task.wait) == "function" then
        task.wait(seconds)
    elseif wait then
        wait(seconds)
    end
end
local function fuseSpawnThread(fn)
    if task and type(task.spawn) == "function" then
        return task.spawn(fn)
    end
    local co = coroutine.create(fn)
    coroutine.resume(co)
    return co
end
local function fuseReadRoster(DataController)
    if not DataController then return nil end
    local ok, roster = pcall(function() return DataController.roster() end)
    if ok and type(roster) == "table" then return roster end
    return nil
end
local function fuseReadMoney(DataController)
    if not DataController then return nil end
    local ok, money = pcall(function() return DataController.money() end)
    if ok then return money end
    return nil
end
local function fuseFindChicken(roster, id)
    for _, chicken in ipairs((roster and roster.chickens) or {}) do
        if chicken and chicken.id == id then return chicken end
    end
    return nil
end
local function fuseMakeSpec(chicken)
    return {
        id = chicken.id,
        typeId = chicken.typeId,
        level = chicken.level or 1,
        genome = chicken.genome,
        ability = chicken.ability,
        rarity = chicken.rarity,
        mutation = chicken.mutation,
        eggs = chicken.eggs,
        look = chicken.look,
    }
end
local function fuseCompareByLevelThenId(a, b)
    local levelA = tonumber(a.level) or 1
    local levelB = tonumber(b.level) or 1
    if levelA ~= levelB then return levelA < levelB end
    return fuseStableId(a.id) < fuseStableId(b.id)
end

local function createAutoFuseChickens(deps)
    deps = deps or {}
    assert(type(deps.Remotes) == "table", "Auto Fuse requires deps.Remotes")
    assert(type(deps.DataController) == "table", "Auto Fuse requires deps.DataController")
    assert(type(deps.Catalog) == "table", "Auto Fuse requires deps.Catalog")
    assert(type(deps.FusionRules) == "table", "Auto Fuse requires deps.FusionRules")
    assert(type(deps.Remotes.invoke) == "function", "Auto Fuse requires Remotes.invoke")
    assert(type(deps.Remotes.defs) == "table", "Auto Fuse requires Remotes.defs")
    assert(deps.Remotes.defs.FuseChickens ~= nil, "Auto Fuse requires Remotes.defs.FuseChickens")
    assert(type(deps.FusionRules.cost) == "function", "Auto Fuse requires FusionRules.cost")
    local Remotes = deps.Remotes
    local DataController = deps.DataController
    local Catalog = deps.Catalog
    local FusionRules = deps.FusionRules
    local config = {
        enabled = false,
        dryRun = true,
        matchMode = "Same Chicken",
        selectedRarities = {},
        protectFavorites = true,
        protectMutated = true,
        abilityWhitelist = fuseCopyMap(DEFAULT_FUSE_ABILITIES),
        keepCopies = 1,
    }
    local lifecycle = {
        destroyed = false,
        generation = 0,
        fusionInProgress = false,
        operationHeld = false,
        rosterDisconnect = nil,
    }
    local state = {
        status = "DISABLED",
        lastResponse = nil,
        lastPair = nil,
        lastResult = nil,
        lastReserveReports = {},
        configRevision = 0,
        evaluationRevision = -1,
    }
    local stats = {
        totalEvaluated = 0,
        eligibleChickens = 0,
        pairsBuilt = 0,
        confirmedFusions = 0,
        protectedActive = 0,
        protectedFavorite = 0,
        protectedMutated = 0,
        protectedAbility = 0,
        protectedIncubator = 0,
        protectedBusy = 0,
        noPairCount = 0,
        reservedKeepCopies = 0,
        lastKeepCopyBlock = nil,
        lastParentA = nil,
        lastParentB = nil,
        lastResultId = nil,
        lastResultRarity = nil,
        lastAscended = nil,
        lastCost = nil,
        lastError = nil,
    }
    local function log(message, payload)
        if type(deps.log) == "function" then
            pcall(deps.log, message, payload)
        end
    end
    local function setStatus(status, payload)
        state.status = status
        if payload then log(status, payload) else log(status) end
    end
    local function invalidate()
        state.configRevision = state.configRevision + 1
        state.evaluationRevision = -1
    end
    local function typeDefinition(chicken)
        local types = Catalog.chickenTypes
        if type(types) == "table" and chicken and chicken.typeId then
            return types[chicken.typeId]
        end
        return nil
    end
    local function resolvedRarity(chicken)
        if chicken and chicken.rarity then return chicken.rarity end
        local definition = typeDefinition(chicken)
        if definition and definition.rarity then return definition.rarity end
        local defaultDefinition = Catalog.defaultChickenType
        if type(defaultDefinition) == "table" then return defaultDefinition.rarity end
        return nil
    end
    local function resolvedAbility(chicken)
        if chicken and chicken.ability then return chicken.ability end
        local definition = typeDefinition(chicken)
        if definition and definition.signature then return definition.signature end
        local defaultDefinition = Catalog.defaultChickenType
        if type(defaultDefinition) == "table" and defaultDefinition.signature then
            return defaultDefinition.signature
        end
        return "beyblade"
    end
    local function availableAbilities()
        local result = {}
        local abilities = Catalog.abilities
        if type(abilities) == "table" then
            for key, value in pairs(abilities) do
                local id = key
                if type(value) == "table" and value.id then id = value.id end
                if type(id) == "string" then
                    result[id] = {
                        id = id,
                        name = type(value) == "table" and value.name or id,
                    }
                end
            end
        end
        return result
    end
    local function moneyIsEnough(money, cost)
        if money == nil or cost == nil then return false end
        if type(money) == "table" and type(money.moreEquals) == "function" then
            local ok, result = pcall(function() return money:moreEquals(cost) end)
            return ok and result == true
        end
        if type(money) == "number" and type(cost) == "number" then
            return money >= cost
        end
        return false
    end
    local function getIncubatorState()
        local occupied = false
        local occupantId = nil
        if type(deps.isIncubatorOccupied) == "function" then
            local ok, value = pcall(deps.isIncubatorOccupied)
            if not ok then return true, nil, true end
            occupied = value == true
        end
        if type(deps.getIncubatorOccupantId) == "function" then
            local ok, value = pcall(deps.getIncubatorOccupantId)
            if not ok then return occupied, nil, true end
            occupantId = value
            if occupantId ~= nil then occupied = true end
        end
        return occupied, occupantId, false
    end
    local function globalOperationState()
        if type(deps.isTradeActive) == "function" then
            local ok, active = pcall(deps.isTradeActive)
            if not ok or active == true then return "PAUSED — TRADE ACTIVE" end
        end
        if type(deps.isFusionActive) == "function" then
            local ok, active = pcall(deps.isFusionActive)
            if not ok or active == true then return "PAUSED — FUSION BUSY" end
        end
        if type(deps.canOperate) == "function" then
            local ok, allowed = pcall(deps.canOperate, "AUTO_FUSE")
            if not ok or allowed == false then return "PAUSED — FUSION BUSY" end
        end
        return nil
    end
    local function chickenProtection(chicken, roster, incubatorOccupied, occupantId, incubatorUnknown)
        if chicken.id == roster.activeId then
            stats.protectedActive = stats.protectedActive + 1
            return "ACTIVE"
        end
        if config.protectFavorites and chicken.favorite == true then
            stats.protectedFavorite = stats.protectedFavorite + 1
            return "FAVORITE"
        end
        if incubatorOccupied and (incubatorUnknown or occupantId == nil or chicken.id == occupantId) then
            stats.protectedIncubator = stats.protectedIncubator + 1
            return "INCUBATOR"
        end
        if type(deps.isChickenBusy) == "function" then
            local ok, busy = pcall(deps.isChickenBusy, chicken.id)
            if not ok or busy == true then
                stats.protectedBusy = stats.protectedBusy + 1
                return "BUSY"
            end
        end
        if config.protectMutated and chicken.mutation ~= nil then
            stats.protectedMutated = stats.protectedMutated + 1
            return "MUTATED"
        end
        if config.abilityWhitelist[resolvedAbility(chicken)] == true then
            stats.protectedAbility = stats.protectedAbility + 1
            return "ABILITY"
        end
        local rarity = resolvedRarity(chicken)
        if not rarity or not config.selectedRarities[rarity] then
            return "RARITY"
        end
        return nil
    end
    local function buildPairs(roster)
        stats.reservedKeepCopies = 0
        local groups = {}
        local eligibleByType = {}
        local protectedByType = {}
        local typeTotals = {}
        local incubatorOccupied, occupantId, incubatorUnknown = getIncubatorState()
        local globalPause = globalOperationState()
        if incubatorOccupied and (incubatorUnknown or occupantId == nil) then
            setStatus("PAUSED — INCUBATOR OCCUPIED")
            return {}, globalPause
        end
        if globalPause then
            setStatus(globalPause)
            return {}, globalPause
        end
        local chickens = roster.chickens or {}
        for _, chicken in ipairs(chickens) do
            if chicken and chicken.id ~= nil then
                stats.totalEvaluated = stats.totalEvaluated + 1
                local typeId = chicken.typeId
                local reason = chickenProtection(chicken, roster, incubatorOccupied, occupantId, incubatorUnknown)
                if typeId == nil then
                    reason = reason or "UNKNOWN TYPE"
                end
                if typeId ~= nil then
                    typeTotals[typeId] = (typeTotals[typeId] or 0) + 1
                    if reason then
                        protectedByType[typeId] = (protectedByType[typeId] or 0) + 1
                    else
                        eligibleByType[typeId] = eligibleByType[typeId] or {}
                        table.insert(eligibleByType[typeId], chicken)
                    end
                end
            end
        end
        local keep = math.max(0, tonumber(config.keepCopies) or 1)
        local candidates = {}
        local reservedThisEvaluation = 0
        for typeId, eligible in pairs(eligibleByType) do
            table.sort(eligible, fuseCompareByLevelThenId)
            local protected = protectedByType[typeId] or 0
            local additionalReserve = math.max(0, keep - protected)
            additionalReserve = math.min(additionalReserve, #eligible)
            local consumableCount = math.max(0, #eligible - additionalReserve)
            reservedThisEvaluation = reservedThisEvaluation + additionalReserve
            for index = 1, consumableCount do
                table.insert(candidates, eligible[index])
            end
        end
        stats.reservedKeepCopies = reservedThisEvaluation
        stats.eligibleChickens = #candidates
        for _, chicken in ipairs(candidates) do
            local key
            if config.matchMode == "Same Chicken" then
                key = chicken.typeId
            else
                key = resolvedRarity(chicken)
            end
            if key ~= nil then
                groups[key] = groups[key] or {}
                table.insert(groups[key], chicken)
            end
        end
        local fusionPairs = {}
        for _, group in pairs(groups) do
            table.sort(group, fuseCompareByLevelThenId)
            local pairable = math.floor(#group / 2) * 2
            local index = 1
            while index + 1 <= pairable do
                table.insert(fusionPairs, { a = group[index], b = group[index + 1] })
                index = index + 2
            end
        end
        stats.pairsBuilt = #fusionPairs
        if #fusionPairs == 0 then
            stats.noPairCount = stats.noPairCount + 1
        end
        return fusionPairs, nil
    end
    local function selectedRarityCount()
        local count = 0
        for _, rarity in ipairs(RARITY_ORDER_FUSE) do
            if config.selectedRarities[rarity] then count = count + 1 end
        end
        return count
    end
    local function canConsumePairWithKeepCopies(roster, parentA, parentB)
        local keep = math.max(0, tonumber(config.keepCopies) or 1)
        local counts = {}
        for _, chicken in ipairs(roster.chickens or {}) do
            if chicken and chicken.typeId ~= nil then
                counts[chicken.typeId] = (counts[chicken.typeId] or 0) + 1
            end
        end
        local typeA = parentA.typeId
        local typeB = parentB.typeId
        if typeA == nil or typeB == nil then
            return false, {
                reason = "PAIR INVALID — KEEP COPIES",
                typeId = typeA or typeB,
                current = 0,
                wouldRemain = 0,
                required = keep,
            }
        end
        local countA = counts[typeA] or 0
        local countB = counts[typeB] or 0
        local remainingA = countA - 1
        local remainingB = countB - 1
        if typeA == typeB then
            remainingA = countA - 2
            remainingB = remainingA
        end
        if remainingA < keep then
            return false, {
                reason = "PAIR INVALID — KEEP COPIES",
                typeId = typeA,
                current = countA,
                wouldRemain = remainingA,
                required = keep,
            }
        end
        if typeB ~= typeA and remainingB < keep then
            return false, {
                reason = "PAIR INVALID — KEEP COPIES",
                typeId = typeB,
                current = countB,
                wouldRemain = remainingB,
                required = keep,
            }
        end
        return true, nil
    end
    local function currentPairIsValid(roster, pair)
        local a = fuseFindChicken(roster, pair.a.id)
        local b = fuseFindChicken(roster, pair.b.id)
        if not a or not b or a.id == b.id then return false, "PAIR REMOVED" end
        if a.id == roster.activeId or b.id == roster.activeId then return false, "ACTIVE" end
        local incubatorOccupied, occupantId, incubatorUnknown = getIncubatorState()
        if incubatorOccupied and (incubatorUnknown or occupantId == nil) then
            return false, "PAUSED — INCUBATOR OCCUPIED"
        end
        if incubatorOccupied and (a.id == occupantId or b.id == occupantId) then
            return false, "INCUBATOR"
        end
        local globalPause = globalOperationState()
        if globalPause then return false, globalPause end
        local function validOne(chicken)
            if config.protectFavorites and chicken.favorite == true then return false end
            if config.protectMutated and chicken.mutation ~= nil then return false end
            if config.abilityWhitelist[resolvedAbility(chicken)] == true then return false end
            local rarity = resolvedRarity(chicken)
            if not rarity or not config.selectedRarities[rarity] then return false end
            if type(deps.isChickenBusy) == "function" then
                local ok, busy = pcall(deps.isChickenBusy, chicken.id)
                if not ok or busy == true then return false end
            end
            return true
        end
        if not validOne(a) or not validOne(b) then return false, "PROTECTED" end
        if config.matchMode == "Same Chicken" and a.typeId ~= b.typeId then
            return false, "MATCH CHANGED"
        end
        if config.matchMode == "Same Rarity" and resolvedRarity(a) ~= resolvedRarity(b) then
            return false, "MATCH CHANGED"
        end
        local keepOk, keepDetails = canConsumePairWithKeepCopies(roster, a, b)
        if not keepOk then
            stats.lastKeepCopyBlock = keepDetails
            log("[AutoFuse] Pair invalidated by Keep Copies", keepDetails)
            return false, "PAIR INVALID — KEEP COPIES"
        end
        return true, a, b
    end
    local function calculateCost(a, b)
        local specA = fuseMakeSpec(a)
        local specB = fuseMakeSpec(b)
        local ok, cost = pcall(function() return FusionRules.cost(specA, specB) end)
        if not ok then return nil, "COST ERROR" end
        return cost, nil
    end
    local function acquireOperation()
        if lifecycle.operationHeld then return true end
        if type(deps.acquireOperation) == "function" then
            local ok, acquired = pcall(deps.acquireOperation, "AUTO_FUSE")
            if not ok or acquired == false then return false end
        end
        lifecycle.operationHeld = true
        return true
    end
    local function releaseOperation()
        if lifecycle.operationHeld and type(deps.releaseOperation) == "function" then
            pcall(deps.releaseOperation, "AUTO_FUSE")
        end
        lifecycle.operationHeld = false
    end
    local function rosterHas(roster, id)
        return fuseFindChicken(roster, id) ~= nil
    end
    local function waitForRosterConfirmation(oldA, oldB, resultId, generation)
        local deadline = os.clock() + 8
        while os.clock() < deadline do
            if lifecycle.destroyed or lifecycle.generation ~= generation then
                return false, "CANCELLED"
            end
            local roster = fuseReadRoster(DataController)
            if roster then
                local sourcesGone = not rosterHas(roster, oldA) and not rosterHas(roster, oldB)
                local resultPresent = resultId == nil or rosterHas(roster, resultId)
                if sourcesGone and resultPresent then return true, nil end
            end
            fuseWaitFor(0.85, deps)
        end
        return false, "NOT CONFIRMED"
    end
    local function invokeFusion(a, b, generation)
        local leaseHeld = false
        local roster
        if config.dryRun then
            roster = fuseReadRoster(DataController)
            if not roster then return false, "ROSTER UNAVAILABLE" end
        else
            if not acquireOperation() then
                setStatus("PAUSED — FUSION BUSY")
                return false, "PAUSED — FUSION BUSY"
            end
            leaseHeld = true
            roster = fuseReadRoster(DataController)
            if not roster then
                releaseOperation()
                return false, "ROSTER UNAVAILABLE"
            end
        end
        local valid, valueA, valueB = currentPairIsValid(roster, { a = a, b = b })
        if not valid then
            if leaseHeld then releaseOperation() end
            return false, valueA
        end
        a, b = valueA, valueB
        local cost, costError = calculateCost(a, b)
        if costError then
            stats.lastError = costError
            if leaseHeld then releaseOperation() end
            return false, costError
        end
        stats.lastCost = cost
        local money = fuseReadMoney(DataController)
        if not moneyIsEnough(money, cost) then
            if leaseHeld then releaseOperation() end
            setStatus("WAITING FOR MONEY", { cost = cost })
            return false, "WAITING FOR MONEY"
        end
        local levelA = tonumber(a.level) or 1
        local levelB = tonumber(b.level) or 1
        local levelSide = if levelA >= levelB then "a" else "b"
        local locks = {}
        stats.lastParentA = a.id
        stats.lastParentB = b.id
        stats.lastCost = cost
        state.lastPair = { a = a.id, b = b.id, levelSide = levelSide, cost = cost }
        local payload = {
            parentA = a.id, parentB = b.id, matchMode = config.matchMode,
            rarity = resolvedRarity(a), typeIdA = a.typeId, typeIdB = b.typeId,
            levelA = levelA, levelB = levelB, cost = cost, levelSide = levelSide,
        }
        if config.dryRun then
            setStatus("DRY RUN", payload)
            log("WOULD FUSE", payload)
            return true, "DRY RUN"
        end
        lifecycle.fusionInProgress = true
        setStatus("FUSING", payload)
        local ok, response = pcall(function()
            return Remotes.invoke(
                Remotes.defs.FuseChickens,
                a.id,
                b.id,
                locks,
                nil,
                levelSide
            )
        end)
        lifecycle.fusionInProgress = false
        if leaseHeld then
            releaseOperation()
            leaseHeld = false
        end
        if lifecycle.destroyed or lifecycle.generation ~= generation then
            return false, "CANCELLED"
        end
        if not ok then
            stats.lastError = tostring(response)
            setStatus("ERROR", { error = response })
            return false, "ERROR"
        end
        state.lastResponse = response
        if type(response) ~= "table" or response.ok ~= true or type(response.data) ~= "table" then
            local errorValue = type(response) == "table" and response.error or nil
            stats.lastError = errorValue
            setStatus("ERROR", { error = errorValue, response = response })
            return false, "ERROR"
        end
        local result = response.data
        local resultId = result.chickenId
        state.lastResult = result
        stats.lastResultId = resultId
        stats.lastResultRarity = result.rarity
        stats.lastAscended = result.ascended
        setStatus("WAITING CONFIRMATION", { resultId = resultId })
        local confirmed, confirmationError = waitForRosterConfirmation(a.id, b.id, resultId, generation)
        if not confirmed then
            stats.lastError = confirmationError
            setStatus("NOT CONFIRMED", { error = confirmationError })
            return false, confirmationError
        end
        stats.confirmedFusions = stats.confirmedFusions + 1
        stats.lastError = nil
        setStatus("CONFIRMED", {
            parentA = a.id, parentB = b.id, resultId = resultId,
            rarity = result.rarity, ascended = result.ascended,
        })
        return true, result
    end
    local function worker(generation)
        while config.enabled and not lifecycle.destroyed and lifecycle.generation == generation do
            if selectedRarityCount() == 0 then
                stats.reservedKeepCopies = 0
                setStatus("NO RARITY SELECTED")
                fuseWaitFor(0.9, deps)
            else
                setStatus("SCANNING")
                local roster = fuseReadRoster(DataController)
                if not roster then
                    stats.reservedKeepCopies = 0
                    stats.lastError = "ROSTER UNAVAILABLE"
                    setStatus("ERROR")
                    fuseWaitFor(1, deps)
                else
                    local fusionPairs, pause = buildPairs(roster)
                    if pause then
                        fuseWaitFor(1, deps)
                    elseif #fusionPairs == 0 then
                        if stats.eligibleChickens == 0 then
                            setStatus("NO ELIGIBLE CHICKENS")
                        else
                            setStatus("NO PAIR AVAILABLE")
                        end
                        fuseWaitFor(0.9, deps)
                    else
                        local pair = fusionPairs[1]
                        setStatus("PAIR READY", { a = pair.a.id, b = pair.b.id })
                        local success, result = invokeFusion(pair.a, pair.b, generation)
                        if success and result == "DRY RUN" then
                            fuseWaitFor(1, deps)
                        elseif not success then
                            fuseWaitFor(1.5, deps)
                        else
                            fuseWaitFor(0.85, deps)
                        end
                    end
                end
            end
        end
        if not lifecycle.destroyed and lifecycle.generation == generation and not config.enabled then
            setStatus("DISABLED")
        end
    end
    local api = {}
    function api.setAutoFuse(enabled)
        if lifecycle.destroyed then return false end
        enabled = enabled == true
        if config.enabled == enabled then return true end
        config.enabled = enabled
        lifecycle.generation = lifecycle.generation + 1
        if not enabled then
            if not lifecycle.fusionInProgress then releaseOperation() end
            setStatus("DISABLED")
            return true
        end
        local generation = lifecycle.generation
        fuseSpawnThread(function()
            local ok, err = xpcall(function()
                worker(generation)
            end, function(e)
                return debug.traceback(tostring(e), 2)
            end)
            if not ok and lifecycle.generation == generation then
                stats.lastError = tostring(err)
                setStatus("ERROR")
                log("[AutoFuse] worker error", tostring(err))
            end
        end)
        return true
    end
    function api.isEnabled() return config.enabled == true end
    function api.setMatchMode(mode)
        if mode ~= "Same Chicken" and mode ~= "Same Rarity" then
            return false, "INVALID MATCH MODE"
        end
        config.matchMode = mode
        invalidate()
        return true
    end
    function api.getMatchMode() return config.matchMode end
    function api.setRaritySelected(rarityId, enabled)
        if type(rarityId) ~= "string" or RARITY_RANK_FUSE[rarityId] == nil then
            return false, "UNKNOWN RARITY"
        end
        config.selectedRarities[rarityId] = enabled == true or nil
        invalidate()
        return true
    end
    function api.isRaritySelected(rarityId) return config.selectedRarities[rarityId] == true end
    function api.getSelectedRarities()
        local result = {}
        for _, rarity in ipairs(RARITY_ORDER_FUSE) do
            if config.selectedRarities[rarity] then table.insert(result, rarity) end
        end
        return result
    end
    function api.clearRaritySelection() config.selectedRarities = {}; invalidate() end
    function api.selectAllRarities()
        for _, rarity in ipairs(RARITY_ORDER_FUSE) do config.selectedRarities[rarity] = true end
        invalidate()
    end
    function api.getAvailableRarities() return fuseCopyArray(RARITY_ORDER_FUSE) end
    function api.setProtectFavorites(enabled) config.protectFavorites = enabled == true; invalidate() end
    function api.getProtectFavorites() return config.protectFavorites end
    function api.setProtectMutated(enabled) config.protectMutated = enabled == true; invalidate() end
    function api.getProtectMutated() return config.protectMutated end
    function api.setAbilityWhitelisted(abilityId, enabled)
        if type(abilityId) ~= "string" then return false, "INVALID ABILITY" end
        config.abilityWhitelist[abilityId] = enabled == true or nil
        invalidate()
        return true
    end
    function api.isAbilityWhitelisted(abilityId) return config.abilityWhitelist[abilityId] == true end
    function api.getAbilityWhitelist() return fuseCopyMap(config.abilityWhitelist) end
    function api.clearAbilityWhitelist() config.abilityWhitelist = {}; invalidate() end
    function api.getAvailableAbilities() return availableAbilities() end
    function api.setKeepCopies(n)
        n = tonumber(n)
        if not n then return false, "INVALID KEEP COPIES" end
        config.keepCopies = math.max(0, math.floor(n))
        invalidate()
        return true
    end
    function api.getKeepCopies() return config.keepCopies end
    function api.setDryRun(enabled) config.dryRun = enabled == true; invalidate() end
    function api.getDryRun() return config.dryRun end
    function api.getStatus() return state.status end
    function api.getStats()
        local result = {}
        for key, value in pairs(stats) do result[key] = value end
        return result
    end
    function api.getLastResponse() return state.lastResponse end
    function api.getLastResult() return state.lastResult end
    function api.forceEvaluation()
        invalidate()
        if config.enabled and not lifecycle.fusionInProgress then
            lifecycle.generation = lifecycle.generation + 1
            local generation = lifecycle.generation
            fuseSpawnThread(function()
                local ok, err = xpcall(function()
                    worker(generation)
                end, function(e)
                    return debug.traceback(tostring(e), 2)
                end)
                if not ok and lifecycle.generation == generation then
                    stats.lastError = tostring(err)
                    setStatus("ERROR")
                    log("[AutoFuse] worker error", tostring(err))
                end
            end)
        end
    end
    function api.destroy()
        if lifecycle.destroyed then return end
        lifecycle.destroyed = true
        config.enabled = false
        lifecycle.generation = lifecycle.generation + 1
        if not lifecycle.fusionInProgress then releaseOperation() end
        if type(lifecycle.rosterDisconnect) == "function" then
            pcall(lifecycle.rosterDisconnect)
            lifecycle.rosterDisconnect = nil
        end
        setStatus("DISABLED")
    end
    if type(deps.subscribeRoster) == "function" then
        local ok, disconnect = pcall(deps.subscribeRoster, function()
            if config.enabled and not lifecycle.fusionInProgress then
                state.evaluationRevision = -1
            end
        end)
        if ok and type(disconnect) == "function" then
            lifecycle.rosterDisconnect = disconnect
        end
    end
    return api
end

--------------------------------------------------------------------
-- Auto Fuse feature instance (ONE instance)
--------------------------------------------------------------------
local AutoFuseFeature = nil
do
    local remotes = Integration.modules.Remotes
    local dc = Integration.modules.DataController
    local catalog = Integration.modules.Catalog
    local fusionRules = Integration.modules.FusionRules
    State.diagnostics["AutoFuse.Remotes"] = remotes and "FOUND" or "MISSING"
    State.diagnostics["AutoFuse.DataController"] = dc and "FOUND" or "MISSING"
    State.diagnostics["AutoFuse.Catalog"] = catalog and "FOUND" or "MISSING"
    State.diagnostics["AutoFuse.FusionRules"] = fusionRules and "FOUND" or "MISSING"
    local fuseDef = remotes and remotes.defs and remotes.defs.FuseChickens
    State.diagnostics["AutoFuse.FuseChickens"] = fuseDef and "FOUND" or "MISSING"
    if not remotes or not fuseDef or type(remotes.invoke) ~= "function" then
        State.diagnostics["AutoFuse.Feature"] = "ERROR: FuseChickens remote missing"
    elseif not dc or type(dc.roster) ~= "function" then
        State.diagnostics["AutoFuse.Feature"] = "ERROR: DataController.roster missing"
    elseif not catalog then
        State.diagnostics["AutoFuse.Feature"] = "ERROR: Catalog missing"
    elseif not fusionRules or type(fusionRules.cost) ~= "function" then
        State.diagnostics["AutoFuse.Feature"] = "ERROR: FusionRules.cost missing"
    else
        local ok, featOrErr = pcall(function()
            return createAutoFuseChickens({
                Remotes = remotes,
                DataController = dc,
                Catalog = catalog,
                FusionRules = fusionRules,
                log = function(msg, payload)
                    if payload ~= nil then
                        log("FUSE", tostring(msg) .. " " .. tostring(payload))
                    else
                        log("FUSE", tostring(msg))
                    end
                end,
                getIncubatorOccupantId = function()
                    local inc = State.data.incubator
                    if type(inc) == "table" then
                        return inc.occupantId or inc.chickenId or inc.activeId
                    end
                    return nil
                end,
                isIncubatorOccupied = function()
                    local inc = State.data.incubator
                    if type(inc) ~= "table" then return false end
                    if inc.occupantId ~= nil or inc.chickenId ~= nil then return true end
                    if type(inc.occupant) == "table" and (inc.occupant.id ~= nil or inc.occupant.chickenId ~= nil) then
                        return true
                    end
                    return false
                end,
                -- No inventing busy/trade/fusion predicates when unverified
            })
        end)
        if ok and featOrErr then
            AutoFuseFeature = featOrErr
            AutoFuseFeature.setDryRun(true)
            State.diagnostics["AutoFuse.Feature"] = "READY"
            log("INFO", "AutoFuseFeature READY (DryRun ON, no rarity selected)")
        else
            State.diagnostics["AutoFuse.Feature"] = "ERROR: " .. tostring(featOrErr)
            log("ERROR", "AutoFuse construct: " .. tostring(featOrErr))
        end
    end
end

--------------------------------------------------------------------
-- AUTO HATCH (resilient roster + Catalog display names)
--------------------------------------------------------------------
local function createAutoHatch(deps)
    local Remotes = deps.Remotes
    local DataController = deps.DataController
    local GameConfig = deps.GameConfig
    local feature = {
        enabled = false, generation = 0, inProgress = false, status = "DISABLED",
        selected = {}, selectedOriginal = {}, userCustomized = false, selectAllMode = false,
        currentTarget = nil, currentQty = 0, currentBatch = 0, lastError = nil,
        rosterAvailable = true, lastKnownTypes = {},
    }
    local function getBatchMax()
        local max = 10
        if GameConfig and GameConfig.roster and GameConfig.roster.hatch and type(GameConfig.roster.hatch.batchMax) == "number" then
            max = GameConfig.roster.hatch.batchMax
        end
        return max
    end
    local function getRoster()
        if DataController then
            local ok, roster = pcall(function() return DataController.roster() end)
            if ok and type(roster) == "table" then return roster end
        end
        if type(State.data.roster) == "table" then return State.data.roster end
        local fromDs = clientGet({"roster"})
        if type(fromDs) == "table" then return fromDs end
        return nil
    end
    local function getRosterEggs()
        local roster = getRoster()
        if type(roster) ~= "table" or type(roster.eggs) ~= "table" then
            feature.rosterAvailable = false
            return {}
        end
        feature.rosterAvailable = true
        return roster.eggs
    end
    function feature.getAvailableEggTypes()
        local eggs = getRosterEggs()
        local list = {}
        if not feature.rosterAvailable then
            for _, cached in ipairs(feature.lastKnownTypes) do
                table.insert(list, { id = cached.id, key = cached.key, quantity = 0, displayName = cached.displayName })
            end
            return list, false
        end
        for eggId, qty in pairs(eggs) do
            local n = tonumber(qty) or 0
            if n > 0 then
                local friendly = resolveEggDisplayName(eggId)
                diagNameOnce("HATCH", eggId, friendly)
                table.insert(list, {
                    id = eggId,
                    key = tostring(eggId),
                    quantity = n,
                    displayName = friendly,
                })
            end
        end
        table.sort(list, function(a, b) return tostring(a.displayName) < tostring(b.displayName) end)
        if #list > 0 then feature.lastKnownTypes = list end
        return list, true
    end
    function feature.getSelectedEggs()
        local out = {}
        for key, on in pairs(feature.selected) do
            if on and feature.selectedOriginal[key] ~= nil then table.insert(out, feature.selectedOriginal[key]) end
        end
        return out
    end
    function feature.isEggSelected(eggId) return feature.selected[tostring(eggId)] == true end
    function feature.setEggSelected(eggId, enabled)
        feature.userCustomized = true
        feature.selectAllMode = false
        local key = tostring(eggId)
        if enabled then feature.selected[key] = true; feature.selectedOriginal[key] = eggId
        else feature.selected[key] = nil; feature.selectedOriginal[key] = nil end
    end
    function feature.clearEggSelection()
        feature.userCustomized = true; feature.selectAllMode = false
        feature.selected = {}; feature.selectedOriginal = {}
    end
    function feature.selectAllAvailableEggs()
        feature.selected = {}; feature.selectedOriginal = {}
        for _, egg in ipairs(feature.getAvailableEggTypes()) do
            feature.selected[egg.key] = true
            feature.selectedOriginal[egg.key] = egg.id
        end
        feature.selectAllMode = true
    end
    local function invokeHatch(tier, batch)
        if Remotes and Remotes.defs and Remotes.defs.HatchEggs and type(Remotes.invoke) == "function" then
            local ok, res = pcall(function() return Remotes.invoke(Remotes.defs.HatchEggs, tier, batch) end)
            return ok, res
        end
        return tryInvoke("HatchEggs", tier, batch)
    end
    local function pickTarget()
        local available, ok = feature.getAvailableEggTypes()
        if not ok and #available == 0 then return nil, 0, "NO_ROSTER" end
        if feature.selectAllMode then
            for _, egg in ipairs(available) do
                if feature.selected[egg.key] == nil and egg.quantity > 0 then
                    feature.selected[egg.key] = true
                    feature.selectedOriginal[egg.key] = egg.id
                end
            end
        end
        local byKey = {}
        for _, egg in ipairs(available) do byKey[egg.key] = egg end
        local keys = {}
        for key, on in pairs(feature.selected) do if on then table.insert(keys, key) end end
        table.sort(keys)
        if #keys == 0 then return nil, 0, "NO_SELECTION" end
        for _, key in ipairs(keys) do
            local egg = byKey[key]
            if egg and egg.quantity > 0 then return egg.id, egg.quantity, "OK" end
        end
        return nil, 0, "WAITING_QTY"
    end
    local function worker(token, myGen)
        while not token.cancelled and feature.enabled and myGen == feature.generation do
            if feature.inProgress then task.wait(0.25) continue end
            refreshData()
            local tier, qty, reason = pickTarget()
            feature.currentTarget = tier; feature.currentQty = qty
            if reason == "NO_ROSTER" then feature.status = "ROSTER DATA UNAVAILABLE"; feature.currentBatch = 0; task.wait(1) continue end
            if reason == "NO_SELECTION" then feature.status = "NO EGG TYPE SELECTED"; feature.currentBatch = 0; task.wait(0.8) continue end
            if not tier or qty <= 0 then feature.status = "WAITING FOR SELECTED EGGS"; feature.currentBatch = 0; task.wait(0.8) continue end
            local batch = math.min(qty, getBatchMax())
            if batch <= 0 then feature.status = "WAITING FOR SELECTED EGGS"; task.wait(0.8) continue end
            feature.inProgress = true
            feature.status = "HATCHING " .. resolveEggDisplayName(tier)
            feature.currentBatch = batch
            local eggsBefore = getRosterEggs()
            local beforeQty = tonumber(eggsBefore[tier]) or qty
            local ok, response = invokeHatch(tier, batch)
            if not ok or not responseOK(response) then
                feature.status = "ERROR"; feature.lastError = tostring(response)
                feature.inProgress = false; task.wait(1.2) continue
            end
            local results = response.data and response.data.results
            if type(results) ~= "table" or #results == 0 then
                feature.status = "ERROR"; feature.lastError = "empty results"
                feature.inProgress = false; task.wait(1.2) continue
            end
            local deadline = os.clock() + 6
            while os.clock() < deadline and feature.enabled and myGen == feature.generation do
                refreshData()
                local afterQty = tonumber(getRosterEggs()[tier]) or beforeQty
                if afterQty < beforeQty then break end
                task.wait(0.3)
            end
            feature.inProgress = false
            task.wait(0.35)
        end
        if not feature.enabled then feature.status = "DISABLED" end
    end
    function feature.setAutoHatch(on)
        feature.enabled = on == true
        State.toggles.autoHatch = feature.enabled
        feature.generation += 1
        feature.inProgress = false
        local myGen = feature.generation
        if not feature.enabled then
            feature.status = "DISABLED"
            feature.currentTarget = nil; feature.currentQty = 0; feature.currentBatch = 0
            return
        end
        if not feature.userCustomized then
            feature.selectAllAvailableEggs()
            feature.userCustomized = false
            feature.selectAllMode = true
        end
        feature.status = "RUNNING"
        maid:Task(function(token) worker(token, myGen) end)
    end
    function feature.getStatus()
        return {
            enabled = feature.enabled, status = feature.status, selected = feature.getSelectedEggs(),
            target = feature.currentTarget, quantity = feature.currentQty, batch = feature.currentBatch,
            selectAllMode = feature.selectAllMode, lastError = feature.lastError, rosterAvailable = feature.rosterAvailable,
        }
    end
    return feature
end

local function createAutoIncubatorClaim(deps)
    local Remotes = deps.Remotes
    local DataService = deps.DataService
    local feature = { enabled = false, generation = 0, inProgress = false, status = "DISABLED", lastError = nil }
    local function getIncubator()
        local client = DataService and DataService.client
        if client and type(client.get) == "function" then
            local ok, value = pcall(client.get, client, {"incubator"})
            if ok and type(value) == "table" then return value end
        end
        return State.data.incubator
    end
    local function eggCount(inc)
        if type(inc) ~= "table" then return 0 end
        if type(inc.eggs) == "table" then return #inc.eggs end
        return tonumber(inc.eggCount) or tonumber(inc.stored) or 0
    end
    local function invokeClaim()
        if Remotes and Remotes.defs and Remotes.defs.IncubatorClaim and type(Remotes.invoke) == "function" then
            local ok, res = pcall(function() return Remotes.invoke(Remotes.defs.IncubatorClaim) end)
            return ok, res
        end
        return tryInvoke("IncubatorClaim")
    end
    local function worker(token, myGen)
        while not token.cancelled and feature.enabled and myGen == feature.generation do
            if feature.inProgress then task.wait(0.25) continue end
            refreshData()
            local count = eggCount(getIncubator())
            if count <= 0 then feature.status = "WAITING"; task.wait(0.9) continue end
            feature.inProgress = true; feature.status = "CLAIMING"
            local before = count
            local ok = invokeClaim()
            if not ok then feature.status = "ERROR"; feature.inProgress = false; task.wait(1.2) continue end
            local deadline = os.clock() + 6
            while os.clock() < deadline and feature.enabled and myGen == feature.generation do
                refreshData()
                if eggCount(getIncubator()) < before then break end
                task.wait(0.3)
            end
            feature.status = "CONFIRMED"
            feature.inProgress = false
            task.wait(0.5)
        end
        if not feature.enabled then feature.status = "DISABLED" end
    end
    function feature.setAutoIncubatorClaim(on)
        feature.enabled = on == true
        State.toggles.autoIncubatorClaim = feature.enabled
        feature.generation += 1
        feature.inProgress = false
        local myGen = feature.generation
        if not feature.enabled then feature.status = "DISABLED" return end
        feature.status = "WAITING"
        maid:Task(function(token) worker(token, myGen) end)
    end
    function feature.getStatus()
        local inc = getIncubator()
        return {
            enabled = feature.enabled, status = feature.status, eggCount = eggCount(inc),
            level = inc and (inc.level or inc.Level), lastError = feature.lastError,
        }
    end
    return feature
end

local HatchFeature = createAutoHatch({
    Remotes = Integration.modules.Remotes,
    DataController = Integration.modules.DataController,
    GameConfig = Integration.modules.GameConfig,
})
local IncubatorClaimFeature = createAutoIncubatorClaim({
    Remotes = Integration.modules.Remotes,
    DataService = Integration.modules.DataService,
})

--------------------------------------------------------------------
-- AUTO UPGRADE INCUBATOR (IncubatorUpgrade no-arg + IncubatorView)
--------------------------------------------------------------------
local AutoUpgradeIncubatorFeature = nil
do
    local feature = {
        enabled = false,
        generation = 0,
        upgradeInProgress = false,
        status = "DISABLED",
        level = nil,
        nextCost = nil,
        requiredRebirth = nil,
        lastError = nil,
    }

    local function getIncubator()
        local fromState = State.data.incubator
        if type(fromState) == "table" then return fromState end
        local ds = Integration.modules.DataService
        local client = ds and ds.client
        if client and type(client.get) == "function" then
            local ok, value = pcall(client.get, client, {"incubator"})
            if ok and type(value) == "table" then return value end
        end
        return nil
    end

    local function getIncubatorLevel()
        local inc = getIncubator()
        if type(inc) ~= "table" then return 0 end
        local level = tonumber(inc.level) or tonumber(inc.Level) or 0
        return level
    end

    local function getRebirthCount()
        local count = select(1, getRebirthInfo())
        return tonumber(count) or 0
    end

    local function getMoneyNumber()
        refreshData()
        local m = State.data.money
        if type(m) == "number" then return m end
        if type(m) == "table" and type(m.toNumber) == "function" then
            local ok, v = pcall(m.toNumber, m)
            if ok then return tonumber(v) end
        end
        return tonumber(m) or 0
    end

    local function moneyEnough(cost)
        if cost == nil then return false end
        local money = State.data.money
        -- Prefer Number-like moreEquals when available
        if type(money) == "table" and type(money.moreEquals) == "function" then
            local ok, res = pcall(function() return money:moreEquals(cost) end)
            if ok then return res == true end
        end
        local mn = getMoneyNumber()
        local cn = tonumber(cost)
        if cn == nil then return false end
        return mn >= cn
    end

    local function invokeUpgrade()
        local Remotes = Integration.modules.Remotes
        if Remotes and Remotes.defs and Remotes.defs.IncubatorUpgrade and type(Remotes.invoke) == "function" then
            local ok, res = pcall(function()
                return Remotes.invoke(Remotes.defs.IncubatorUpgrade)
            end)
            return ok, res
        end
        return tryInvoke("IncubatorUpgrade")
    end

    local function worker(token, myGen)
        while not token.cancelled and feature.enabled and myGen == feature.generation do
            if feature.upgradeInProgress then
                task.wait(0.25)
                continue
            end
            refreshData()
            local view = Integration.modules.IncubatorView
            if not view then
                feature.status = "ERROR"
                feature.lastError = "IncubatorView missing"
                task.wait(1.2)
                continue
            end

            local level = getIncubatorLevel()
            feature.level = level
            local rebirth = getRebirthCount()
            local maxLevel = tonumber(view.maxLevel) or 0

            if maxLevel > 0 and level >= maxLevel then
                feature.status = "MAXED"
                feature.nextCost = nil
                feature.requiredRebirth = nil
                task.wait(1.0)
                continue
            end

            local can, needRebirth = false, nil
            if type(view.canUpgrade) == "function" then
                local ok, a, b = pcall(view.canUpgrade, level, rebirth)
                if ok then
                    can, needRebirth = a == true, b
                end
            end

            local nextLevel = level + 1
            if nextLevel < 1 then nextLevel = 1 end
            local cost = nil
            if type(view.upgradeCost) == "function" then
                local ok, c = pcall(view.upgradeCost, nextLevel)
                if ok then cost = c end
            end
            feature.nextCost = cost
            feature.requiredRebirth = needRebirth

            if not can then
                if needRebirth ~= nil then
                    feature.status = "WAITING FOR REBIRTH"
                else
                    feature.status = "SCANNING"
                end
                task.wait(1.0)
                continue
            end

            if not moneyEnough(cost) then
                feature.status = "WAITING FOR MONEY"
                task.wait(1.0)
                continue
            end

            feature.upgradeInProgress = true
            feature.status = "UPGRADING"
            local beforeLevel = level
            local ok, response = invokeUpgrade()
            if not ok then
                feature.status = "ERROR"
                feature.lastError = tostring(response)
                feature.upgradeInProgress = false
                task.wait(1.5)
                continue
            end
            if type(response) == "table" and response.ok == false then
                feature.status = "ERROR"
                feature.lastError = tostring(response.error or "rejected")
                feature.upgradeInProgress = false
                task.wait(1.5)
                continue
            end

            feature.status = "WAITING CONFIRMATION"
            local confirmed = false
            local deadline = os.clock() + 8
            while os.clock() < deadline and feature.enabled and myGen == feature.generation do
                refreshData()
                local nowLevel = getIncubatorLevel()
                feature.level = nowLevel
                if nowLevel > beforeLevel then
                    confirmed = true
                    break
                end
                task.wait(0.35)
            end
            if confirmed then
                feature.status = "CONFIRMED"
                feature.lastError = nil
            else
                feature.status = "ERROR"
                feature.lastError = "level not confirmed"
            end
            feature.upgradeInProgress = false
            task.wait(0.75)
        end
        if not feature.enabled then feature.status = "DISABLED" end
    end

    function feature.setAutoUpgradeIncubator(on)
        feature.enabled = on == true
        State.toggles.autoUpgradeIncubator = feature.enabled
        feature.generation += 1
        feature.upgradeInProgress = false
        local myGen = feature.generation
        if not feature.enabled then
            feature.status = "DISABLED"
            return
        end
        feature.status = "SCANNING"
        maid:Task(function(token)
            worker(token, myGen)
        end)
    end

    function feature.getStatus()
        return {
            status = feature.status,
            level = feature.level,
            nextCost = feature.nextCost,
            requiredRebirth = feature.requiredRebirth,
            lastError = feature.lastError,
            enabled = feature.enabled,
        }
    end

    AutoUpgradeIncubatorFeature = feature
    State.diagnostics["AutoUpgradeIncubator.Feature"] = "READY"
    State.diagnostics["Remote.IncubatorUpgrade"] = Integration.remotes.IncubatorUpgrade and Integration.remotes.IncubatorUpgrade.ClassName
        or (Integration.modules.Remotes and Integration.modules.Remotes.defs and Integration.modules.Remotes.defs.IncubatorUpgrade and "DEF")
        or "MISSING"
end

--------------------------------------------------------------------
-- Performance Manager + Config Manager
--------------------------------------------------------------------
do
    local function setVisualCover(enabled)
        if enabled then
            if visualCoverGui and visualCoverGui.Parent then visualCoverGui.Enabled = true; return end
            local gui = Instance.new("ScreenGui")
            gui.Name = "UNO_HUB_VisualCover"
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 100
            gui.ResetOnSpawn = false
            local frame = Instance.new("Frame")
            frame.Size = UDim2.fromScale(1, 1)
            frame.BackgroundColor3 = Color3.fromRGB(8, 8, 10)
            frame.BorderSizePixel = 0
            frame.Parent = gui
            local openBtn = Instance.new("TextButton")
            openBtn.Size = UDim2.fromOffset(120, 32)
            openBtn.Position = UDim2.new(1, -132, 0, 12)
            openBtn.BackgroundColor3 = Theme.Primary
            openBtn.Text = "UNO HUB"
            openBtn.Font = Enum.Font.GothamBold
            openBtn.TextSize = 12
            openBtn.TextColor3 = Color3.new(1, 1, 1)
            openBtn.AutoButtonColor = false
            openBtn.Parent = frame
            corner(openBtn, 6)
            openBtn.MouseButton1Click:Connect(function()
                State.visible = true
                if Main then Main.Visible = true end
            end)
            gui.Parent = PlayerGui
            visualCoverGui = gui
        else
            if visualCoverGui then pcall(function() visualCoverGui:Destroy() end); visualCoverGui = nil end
        end
    end
    local function isProtectedInstance(inst)
        if not inst then return false end
        -- Never touch UNO HUB UI or PlayerGui chrome
        local ok, current = pcall(function() return inst end)
        if ok and inst then
            local node = inst
            for _ = 1, 12 do
                if not node then break end
                local n = ""
                pcall(function() n = node.Name end)
                if n == "UNO_HUB" or n == "UNO_HUB_VisualCover" or n == "PlayerGui" then
                    return true
                end
                local par = nil
                pcall(function() par = node.Parent end)
                node = par
            end
        end
        local name = ""
        pcall(function() name = inst.Name end)
        local lower = string.lower(tostring(name))
        for _, tok in ipairs({"hotegg", "nestegg", "meteor", "hazard", "pitzone", "carrier", "uno_hub"}) do
            if string.find(lower, tok, 1, true) then return true end
        end
        local tagged = false
        pcall(function() if CollectionService:HasTag(inst, "NestEgg") then tagged = true end end)
        return tagged
    end
    local function getCosmeticRoots()
        local roots = {}
        if Lighting then table.insert(roots, Lighting) end
        for _, name in ipairs({"Effects", "VFX", "Visuals", "Fx", "FX", "Particles"}) do
            local a = Workspace:FindFirstChild(name); if a then table.insert(roots, a) end
            local b = ReplicatedStorage:FindFirstChild(name); if b then table.insert(roots, b) end
        end
        return roots
    end
    local function isOtherChickenModel() return false end

    PerformanceManager = createPerformanceManager({
        services = { Players = Players, Lighting = Lighting, Workspace = Workspace },
        localPlayer = LocalPlayer,
        getCosmeticRoots = getCosmeticRoots,
        isProtectedInstance = isProtectedInstance,
        isOtherChickenModel = isOtherChickenModel,
        setVisualCover = setVisualCover,
        log = function(msg, payload)
            log("PERF", tostring(msg) .. (payload and (" " .. tostring(payload)) or ""))
        end,
    })
    State.diagnostics["PerformanceManager"] = PerformanceManager and "READY" or "MISSING"

    ConfigManager = createConfigManager({
        HttpService = HttpService,
        log = function(msg, payload)
            log("CFG", tostring(msg) .. (payload and (" " .. tostring(payload)) or ""))
        end,
    })
    State.diagnostics["ConfigManager"] = ConfigManager and (ConfigManager.isPersistenceAvailable() and "READY" or "NO FS") or "MISSING"

    if ConfigManager then
        ConfigManager.registerSection("automation", function()
            return {
                autoFarmRebirth = State.toggles.autoFarmRebirth == true,
                autoKoDismiss = State.toggles.autoKoDismiss == true,
                autoCollectEgg = State.toggles.autoCollectEgg == true,
                autoHotEgg = State.toggles.autoHotEgg == true,
                antiAfk = State.toggles.antiAfk == true,
                autoHatch = State.toggles.autoHatch == true,
                autoIncubatorClaim = State.toggles.autoIncubatorClaim == true,
                autoUpgradeIncubator = State.toggles.autoUpgradeIncubator == true,
                autoBuyGenerator = State.toggles.autoBuyGenerator == true,
                autoUpgradeGenerator = State.toggles.autoUpgradeGenerator == true,
                autoExpandCoop = State.toggles.autoExpandCoop == true,
                autoUpgradeRecycler = State.toggles.autoUpgradeRecycler == true,
            }
        end, function(data)
            if type(data) ~= "table" then return end
            local function applyToggle(key, setter)
                if data[key] == nil then return end
                State.toggles[key] = data[key] == true
                if setter then pcall(setter, data[key] == true) end
            end
            applyToggle("autoFarmRebirth", setAutoFarmRebirth)
            applyToggle("autoKoDismiss")
            if AutoCollectEggFeature then applyToggle("autoCollectEgg", function(v) AutoCollectEggFeature.setAutoCollectEggs(v) end) end
            applyToggle("autoHotEgg", setAutoHotEgg)
            applyToggle("antiAfk", setAntiAfk)
            if HatchFeature then applyToggle("autoHatch", function(v) HatchFeature.setAutoHatch(v) end) end
            if IncubatorClaimFeature then applyToggle("autoIncubatorClaim", function(v) IncubatorClaimFeature.setAutoIncubatorClaim(v) end) end
            if AutoUpgradeIncubatorFeature then applyToggle("autoUpgradeIncubator", function(v) AutoUpgradeIncubatorFeature.setAutoUpgradeIncubator(v) end) end
            applyToggle("autoBuyGenerator", setAutoBuyGenerator)
            applyToggle("autoUpgradeGenerator", setAutoUpgradeGenerator)
            applyToggle("autoExpandCoop", setAutoExpandCoop)
            applyToggle("autoUpgradeRecycler", setAutoUpgradeRecycler)
        end, { defaults = {} })

        ConfigManager.registerSection("hotEgg", function()
            return { meteorAvoidance = HE.meteorAvoidance == true, movementMode = HE.movementMode or "Tween", exitPitAfter = HE.exitPitAfter == true }
        end, function(data)
            if type(data) ~= "table" then return end
            if data.meteorAvoidance ~= nil then HE.meteorAvoidance = data.meteorAvoidance == true end
            if type(data.movementMode) == "string" then HE.movementMode = data.movementMode end
            if data.exitPitAfter ~= nil then HE.exitPitAfter = data.exitPitAfter == true end
        end, { defaults = { meteorAvoidance = true, movementMode = "Tween", exitPitAfter = true } })

        ConfigManager.registerSection("sell", function()
            if not AutoSellFeature then return { enabled = false, dryRun = true } end
            return {
                enabled = (AutoSellFeature.isEnabled and AutoSellFeature.isEnabled()) or false,
                dryRun = (AutoSellFeature.getDryRun and AutoSellFeature.getDryRun()) or true,
                rarities = (AutoSellFeature.getSelectedRarities and AutoSellFeature.getSelectedRarities()) or {},
                protectFavorites = (AutoSellFeature.getProtectFavorites and AutoSellFeature.getProtectFavorites()) or true,
                protectMutated = (AutoSellFeature.getProtectMutated and AutoSellFeature.getProtectMutated()) or true,
            }
        end, function(data)
            if type(data) ~= "table" or not AutoSellFeature then return end
            if type(data.rarities) == "table" then
                if AutoSellFeature.clearRaritySelection then pcall(AutoSellFeature.clearRaritySelection) end
                for _, r in ipairs(data.rarities) do pcall(AutoSellFeature.setRaritySelected, r, true) end
            end
            if data.protectFavorites ~= nil then pcall(AutoSellFeature.setProtectFavorites, data.protectFavorites == true) end
            if data.protectMutated ~= nil then pcall(AutoSellFeature.setProtectMutated, data.protectMutated == true) end
            if data.dryRun ~= nil then pcall(AutoSellFeature.setDryRun, data.dryRun == true) end
            if data.enabled ~= nil then pcall(AutoSellFeature.setAutoSell, data.enabled == true) end
        end, { defaults = { enabled = false, dryRun = true } })

        ConfigManager.registerSection("fuse", function()
            if not AutoFuseFeature then return { enabled = false, dryRun = true, matchMode = "Same Chicken", keepCopies = 1 } end
            return {
                enabled = (AutoFuseFeature.isEnabled and AutoFuseFeature.isEnabled()) or false,
                dryRun = (AutoFuseFeature.getDryRun and AutoFuseFeature.getDryRun()) or true,
                matchMode = (AutoFuseFeature.getMatchMode and AutoFuseFeature.getMatchMode()) or "Same Chicken",
                rarities = (AutoFuseFeature.getSelectedRarities and AutoFuseFeature.getSelectedRarities()) or {},
                keepCopies = (AutoFuseFeature.getKeepCopies and AutoFuseFeature.getKeepCopies()) or 1,
                protectFavorites = (AutoFuseFeature.getProtectFavorites and AutoFuseFeature.getProtectFavorites()) or true,
                protectMutated = (AutoFuseFeature.getProtectMutated and AutoFuseFeature.getProtectMutated()) or true,
            }
        end, function(data)
            if type(data) ~= "table" or not AutoFuseFeature then return end
            if type(data.matchMode) == "string" then pcall(AutoFuseFeature.setMatchMode, data.matchMode) end
            if data.keepCopies ~= nil then pcall(AutoFuseFeature.setKeepCopies, data.keepCopies) end
            if type(data.rarities) == "table" then
                if AutoFuseFeature.clearRaritySelection then pcall(AutoFuseFeature.clearRaritySelection) end
                for _, r in ipairs(data.rarities) do pcall(AutoFuseFeature.setRaritySelected, r, true) end
            end
            if data.protectFavorites ~= nil then pcall(AutoFuseFeature.setProtectFavorites, data.protectFavorites == true) end
            if data.protectMutated ~= nil then pcall(AutoFuseFeature.setProtectMutated, data.protectMutated == true) end
            if data.dryRun ~= nil then pcall(AutoFuseFeature.setDryRun, data.dryRun == true) end
            if data.enabled ~= nil then pcall(AutoFuseFeature.setAutoFuse, data.enabled == true) end
        end, { defaults = { enabled = false, dryRun = true, matchMode = "Same Chicken", keepCopies = 1 } })

        ConfigManager.registerSection("performance", function()
            if not PerformanceManager then return {} end
            return {
                boostFPS = PerformanceManager.getBoostFPS(),
                disableVFX = PerformanceManager.getDisableVFX(),
                disableShadows = PerformanceManager.getDisableShadows(),
                hideOtherPlayers = PerformanceManager.getHideOtherPlayers(),
                hideOtherChickens = PerformanceManager.getHideOtherChickens(),
                whiteScreen = PerformanceManager.getWhiteScreen(),
                ultraPerformance = PerformanceManager.getUltraPerformance(),
            }
        end, function(data)
            if type(data) ~= "table" or not PerformanceManager then return end
            if data.disableVFX ~= nil then PerformanceManager.setDisableVFX(data.disableVFX == true) end
            if data.disableShadows ~= nil then PerformanceManager.setDisableShadows(data.disableShadows == true) end
            if data.hideOtherPlayers ~= nil then PerformanceManager.setHideOtherPlayers(data.hideOtherPlayers == true) end
            if data.hideOtherChickens ~= nil then PerformanceManager.setHideOtherChickens(data.hideOtherChickens == true) end
            if data.whiteScreen ~= nil then PerformanceManager.setWhiteScreen(data.whiteScreen == true) end
            if data.boostFPS ~= nil then PerformanceManager.setBoostFPS(data.boostFPS == true) end
            if data.ultraPerformance ~= nil then PerformanceManager.setUltraPerformance(data.ultraPerformance == true) end
        end, { defaults = { boostFPS = false, disableVFX = false, disableShadows = false, hideOtherPlayers = false, hideOtherChickens = false, whiteScreen = false, ultraPerformance = false } })

        -- load deferred until after AFR/HE definitions
    end
end



--------------------------------------------------------------------
-- ECONOMY / HOT EGG / AFR (same contracts as previous working base)
--------------------------------------------------------------------
local function coopSnapshot()
    local coop = clientGet({"coop"}) or State.data.coop
    if type(coop) ~= "table" then return nil end
    local snapshot = { slots = tonumber(coop.slots) or 0, generators = {} }
    for _, generator in ipairs(coop.generators or {}) do
        local slot = tonumber(generator.slot)
        if slot then snapshot.generators[slot] = { slot = slot, level = tonumber(generator.level) or 0, corn = tonumber(generator.corn) or 0 } end
    end
    return snapshot
end
local function generatorView(snapshot)
    local view = Integration.modules.CoopView
    if not snapshot or not view then return nil end
    local count = 0
    for _ in pairs(snapshot.generators) do count += 1 end
    local result = { buySlot = nil, buyCost = nil, expandCost = nil, canExpand = false, generators = {}, owned = count }
    if type(view.buyGeneratorCost) == "function" then result.buyCost = view.buyGeneratorCost(count) end
    if type(view.expandCost) == "function" then result.expandCost = view.expandCost(snapshot.slots) end
    if type(view.canExpand) == "function" then result.canExpand = view.canExpand(snapshot.slots) == true end
    if type(view.canBuyGenerator) == "function" and view.canBuyGenerator(snapshot.slots, count) then result.buySlot = count + 1 end
    for slot, generator in pairs(snapshot.generators) do
        local item = { slot = generator.slot, level = generator.level, corn = generator.corn, upgradeCost = nil, canUpgrade = false }
        if type(view.upgradeCost) == "function" then item.upgradeCost = view.upgradeCost(generator.level) end
        if type(view.canUpgrade) == "function" then item.canUpgrade = view.canUpgrade(generator.level) == true end
        result.generators[slot] = item
    end
    return result
end
local function waitForCoopChange(before, predicate, timeout)
    local deadline = os.clock() + (timeout or 8)
    while os.clock() < deadline and not State.closed do
        refreshData()
        local after = coopSnapshot()
        if after and predicate(before, after) then return after end
        task.wait(0.35)
    end
    return nil
end
local function refreshEconomyStatus()
    refreshData()
    local snap = coopSnapshot()
    local view = generatorView(snap)
    local owned = 0
    if snap then for _ in pairs(snap.generators) do owned += 1 end end
    State.economy.generatorsOwned = owned
    State.economy.generatorsSlots = snap and snap.slots or 0
    State.economy.nextBuySlot = view and view.buySlot or nil
    State.economy.nextBuyCost = view and view.buyCost or nil
    State.economy.recyclerLevel = tonumber(State.data.recyclerLevel) or 0
end
local Economy = { generations = {} }
local function stopEconomy(name) Economy.generations[name] = (Economy.generations[name] or 0) + 1 end
local function economyWorker(name, enabled, body)
    stopEconomy(name)
    if not enabled then return end
    local generation = Economy.generations[name]
    maid:Task(function(token)
        while not token.cancelled and not State.closed and State.toggles[name] and generation == Economy.generations[name] do
            pcall(body, generation)
            task.wait(0.85)
        end
    end)
end
local function setAutoBuyGenerator(on)
    State.toggles.autoBuyGenerator = on
    if not on then State.economy.buyStatus = "IDLE" end
    economyWorker("autoBuyGenerator", on, function()
        refreshEconomyStatus()
        local before = coopSnapshot()
        local view = generatorView(before)
        if not before or not view then State.economy.buyStatus = "NO DATA" return end
        local owned = 0
        for _ in pairs(before.generators) do owned += 1 end
        if owned >= before.slots then State.economy.buyStatus = "FULL" return end
        if not view.buySlot then State.economy.buyStatus = "NO SLOT" return end
        local money = readMoney() or 0
        if view.buyCost and money < view.buyCost then State.economy.buyStatus = "WAITING MONEY" return end
        State.economy.buyStatus = "BUYING"
        local sent, response = tryInvoke("BuyGenerator", view.buySlot)
        if sent and responseOK(response) then
            local target = view.buySlot
            local after = waitForCoopChange(before, function(_, new) return new.generators[target] ~= nil end, 8)
            State.economy.buyStatus = after and "SUCCESS" or "TIMEOUT"
        else State.economy.buyStatus = "FAILED" end
    end)
end
local function setAutoUpgradeGenerator(on)
    State.toggles.autoUpgradeGenerator = on
    if not on then State.economy.upgradeStatus = "IDLE" end
    economyWorker("autoUpgradeGenerator", on, function()
        refreshEconomyStatus()
        local before = coopSnapshot()
        local view = generatorView(before)
        if not view then State.economy.upgradeStatus = "NO DATA" return end
        local candidates = {}
        for _, gen in pairs(view.generators) do if gen.canUpgrade then table.insert(candidates, gen) end end
        table.sort(candidates, function(a, b) if a.level == b.level then return a.slot < b.slot end return a.level < b.level end)
        if #candidates == 0 then State.economy.upgradeStatus = "NONE" return end
        local money = readMoney() or 0
        for _, gen in ipairs(candidates) do
            if gen.upgradeCost and money < gen.upgradeCost then State.economy.upgradeStatus = "WAITING MONEY" continue end
            State.economy.upgradeStatus = "UPGRADING"
            local sent, response = tryInvoke("UpgradeGenerator", gen.slot)
            if sent and responseOK(response) then
                local slot = gen.slot
                local after = waitForCoopChange(before, function(old, new)
                    return new.generators[slot] and old.generators[slot] and new.generators[slot].level > old.generators[slot].level
                end, 8)
                State.economy.upgradeStatus = after and "SUCCESS" or "TIMEOUT"
            else State.economy.upgradeStatus = "FAILED" end
            return
        end
    end)
end
local function setAutoExpandCoop(on)
    State.toggles.autoExpandCoop = on
    if not on then State.economy.expandStatus = "IDLE" end
    economyWorker("autoExpandCoop", on, function()
        refreshEconomyStatus()
        local before = coopSnapshot()
        local view = generatorView(before)
        if not before or not view or not view.canExpand then State.economy.expandStatus = "UNAVAILABLE" return end
        local money = readMoney() or 0
        if view.expandCost and money < view.expandCost then State.economy.expandStatus = "WAITING MONEY" return end
        State.economy.expandStatus = "EXPANDING"
        local sent, response = tryInvoke("ExpandCoop")
        if sent and responseOK(response) then
            local after = waitForCoopChange(before, function(old, new) return new.slots > old.slots end, 8)
            State.economy.expandStatus = after and "SUCCESS" or "TIMEOUT"
        else State.economy.expandStatus = "FAILED" end
    end)
end
local function setAutoUpgradeRecycler(on)
    State.toggles.autoUpgradeRecycler = on
    if not on then State.economy.recyclerStatus = "IDLE" end
    economyWorker("autoUpgradeRecycler", on, function()
        refreshData()
        local view = Integration.modules.RecyclerView
        local level = tonumber(State.data.recyclerLevel) or 0
        local rebirth = State.data.rebirth
        local count = type(rebirth) == "table" and tonumber(rebirth.count) or 0
        if not view or type(view.canUpgrade) ~= "function" or not view.canUpgrade(level, count) then
            State.economy.recyclerStatus = "UNAVAILABLE" return
        end
        local cost = type(view.upgradeCost) == "function" and view.upgradeCost(level) or nil
        local money = readMoney() or 0
        if cost and money < cost then State.economy.recyclerStatus = "WAITING MONEY" return end
        State.economy.recyclerStatus = "UPGRADING"
        local sent, response = tryInvoke("UpgradeRecycler")
        if sent and responseOK(response) then
            local deadline = os.clock() + 8
            while os.clock() < deadline and State.toggles.autoUpgradeRecycler do
                refreshData()
                if (tonumber(State.data.recyclerLevel) or 0) > level then
                    State.economy.recyclerStatus = "SUCCESS" return
                end
                task.wait(0.35)
            end
            State.economy.recyclerStatus = "TIMEOUT"
        else State.economy.recyclerStatus = "FAILED" end
    end)
end

local HE = State.hotEgg
local function pitCenter()
    local pz = Integration.modules.PitZone
    if pz and typeof(pz.center) == "Vector3" then return pz.center end
    return Vector3.new(0, 0, 0)
end
local function pitRadius()
    local pz = Integration.modules.PitZone
    if pz and type(pz.radius) == "number" then return pz.radius end
    local gc = Integration.modules.GameConfig
    if gc and gc.pit and type(gc.pit.radius) == "number" then return gc.pit.radius end
    return 40
end
local function isInsidePit(pos)
    local pz = Integration.modules.PitZone
    if pz and type(pz.contains) == "function" then
        local ok, res = pcall(pz.contains, pos)
        if ok then return res == true end
    end
    local c = pitCenter()
    return Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude <= pitRadius()
end
local function exitClearance()
    local gc = Integration.modules.GameConfig
    if gc and gc.pit and type(gc.pit.exitClearance) == "number" then return gc.pit.exitClearance end
    return 8
end
local function getHotEggPart()
    local p = Workspace:FindFirstChild("HotEgg")
    if p and p:IsA("BasePart") then return p end
    return nil
end
local function isLocalHolding()
    local egg = getHotEggPart()
    if not egg then return false end
    local c = egg:GetAttribute("Carrier")
    return typeof(c) == "number" and c == LocalPlayer.UserId
end
local function getEventName(payload)
    if type(payload) == "string" then return payload end
    if type(payload) == "table" then return payload.eventName or payload.id or payload.name end
    return nil
end
local function isHotEggEventName(name)
    if type(name) ~= "string" then return false end
    local lower = string.lower(name)
    return lower == "hotegg" or lower == "hot_egg" or lower == "hot egg"
end
local function clearHotEggLiveEvents()
    State.liveEvents["hotEgg"] = nil
    State.liveEvents["HotEgg"] = nil
    for k in pairs(State.liveEvents) do
        if isHotEggEventName(k) then State.liveEvents[k] = nil end
    end
end
local function clearEvadeState()
    HE.evadeTarget = nil
    HE.evadeTargetTime = 0
    HE.lastEvadeDecision = 0
    HE.lastEvadeReason = "—"
    HE.threateningCount = 0
end
local function markHotEggEventFinished(reason)
    HE.eventActive = false; HE.endConfirmed = true; HE.timeRemaining = 0
    HE.holding = false; HE.hazards = {}; HE.meteorCount = 0; HE.nearestImpact = nil
    clearEvadeState()
    clearHotEggLiveEvents()
end
local function markHotEggEventStarted()
    HE.endConfirmed = false; HE.eventActive = true; HE.rewardConfirmed = false
    HE.holding = false; HE.hazards = {}; HE.meteorCount = 0; HE.nearestImpact = nil; HE.exitAttempts = 0
    clearEvadeState()
end
local function setTowerStatus(status, payload)
    State.tower.status = status
    if type(payload) == "table" then
        State.tower.floor = payload.floor or payload.currentFloor or State.tower.floor
        State.tower.best = payload.best or payload.towerBest or State.tower.best
    end
end
local function connectRemoteEvent(name, callback)
    local remote = Integration.remotes[name]
    if not remote then return end
    if not remote:IsA("RemoteEvent") and not remote:IsA("UnreliableRemoteEvent") then return end
    maid:Connect(remote.OnClientEvent, callback)
end

connectRemoteEvent("TowerRunStarted", function(payload)
    State.towerRuns += 1; State.tower.runActive = true
    State.autoFarmRebirth.surrenderInFlight = false
    setTowerStatus("RUNNING", payload)
end)
connectRemoteEvent("TowerFloorCleared", function(payload)
    State.floorsCleared += 1; State.tower.runActive = true
    setTowerStatus("FLOOR CLEARED", payload)
end)
connectRemoteEvent("TowerRivalLanded", function(payload) State.tower.runActive = true; setTowerStatus("RUNNING", payload) end)
connectRemoteEvent("TowerDefeat", function(payload) State.koCount += 1; setTowerStatus("K.O.", payload) end)
connectRemoteEvent("TowerRunEnded", function(payload)
    State.tower.runActive = false
    State.autoFarmRebirth.surrenderInFlight = false
    State.autoFarmRebirth.declineInFlight = false
    setTowerStatus("RUN ENDED", payload)
    if State.tower.continue then State.tower.continue.open = false end
end)
connectRemoteEvent("TowerContinueOffer", function(payload)
    if type(payload) ~= "table" then return end
    if payload.open ~= true then
        if State.tower.continue then State.tower.continue.open = false end
        State.autoFarmRebirth.declineInFlight = false
        return
    end
    State.tower.continue = {
        open = true, paid = payload.paid == true,
        secs = tonumber(payload.secs) or 0, floor = tonumber(payload.floor) or 0,
        best = tonumber(payload.best) or 0, deadline = os.clock() + (tonumber(payload.secs) or 0),
    }
    State.autoFarmRebirth.declineInFlight = false
end)
connectRemoteEvent("TowerContinued", function(payload)
    State.tower.continue = nil
    State.autoFarmRebirth.declineInFlight = false
    State.tower.runActive = true
    setTowerStatus("RUNNING", payload)
end)
connectRemoteEvent("LiveEventStarted", function(payload)
    if type(payload) ~= "table" then return end
    local name = payload.eventName or payload.id or "unknown"
    State.liveEvents[name] = { phase = "STARTED", endsAt = payload.endsAt, duration = payload.duration, startedAt = os.clock() }
    if isHotEggEventName(name) then markHotEggEventStarted() end
end)
connectRemoteEvent("LiveEventEnded", function(payload)
    local name = getEventName(payload)
    if type(name) == "string" then
        State.liveEvents[name] = nil
        if isHotEggEventName(name) then markHotEggEventFinished("LiveEventEnded") end
    end
end)
connectRemoteEvent("HotEggEntrance", function() markHotEggEventStarted() end)
connectRemoteEvent("HotEggMeteor", function(payload)
    if HE.endConfirmed or not HE.eventActive then return end
    if type(payload) ~= "table" or typeof(payload.at) ~= "Vector3" then return end
    local fall = math.clamp(tonumber(payload.fall) or 1.2, 0.2, 6)
    local radius = math.clamp(tonumber(payload.radius) or 8, 2, 40)
    local id = tostring(os.clock()) .. "_" .. math.random(1, 9999)
    HE.hazards[id] = { id = id, pos = payload.at, radius = radius, impactAt = os.clock() + fall }
end)
connectRemoteEvent("HotEggReward", function() HE.rewardConfirmed = true end)
connectRemoteEvent("HotEggFinale", function(payload)
    markHotEggEventFinished("HotEggFinale")
    if type(payload) == "table" and typeof(payload.userId) == "number" and payload.userId == LocalPlayer.UserId then
        HE.rewardConfirmed = true
    end
end)

local function heSetPhase(phase, action)
    HE.phase = phase
    if action then HE.action = action end
end
local IMMINENT_WINDOW = 1.35 -- seconds; only these meteors force emergency evade
local EVADE_RESELECT_COOLDOWN = 0.2
local EVADE_REUSE_RADIUS = 4.5

local function pruneHazards()
    local now = os.clock()
    local nearest, count, threatening = nil, 0, 0
    for id, h in pairs(HE.hazards) do
        if now > h.impactAt + 0.8 then
            HE.hazards[id] = nil
        else
            count += 1
            local t = h.impactAt - now
            if nearest == nil or t < nearest then nearest = t end
            if t <= IMMINENT_WINDOW then threatening += 1 end
        end
    end
    HE.meteorCount = count
    HE.nearestImpact = nearest
    HE.threateningCount = threatening
end

-- Returns true if pos is free of ALL active hazard radii (used for target validation).
local function isPositionSafe(pos)
    pruneHazards()
    local margin = HE.safetyMargin or 6
    for _, h in pairs(HE.hazards) do
        local d = Vector3.new(pos.X - h.pos.X, 0, pos.Z - h.pos.Z).Magnitude
        if d <= (h.radius + margin) then return false end
    end
    return true
end

-- Returns true only when an IMMINENT meteor threatens this position (time-aware).
local function isPositionThreatened(pos)
    pruneHazards()
    local now = os.clock()
    local margin = HE.safetyMargin or 6
    for _, h in pairs(HE.hazards) do
        local t = h.impactAt - now
        if t <= IMMINENT_WINDOW and t > -0.15 then
            local d = Vector3.new(pos.X - h.pos.X, 0, pos.Z - h.pos.Z).Magnitude
            if d <= (h.radius + margin) then
                return true
            end
        end
    end
    return false
end

local function flatDist(a, b)
    return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Safe-point selection: pit-constrained, egg-aware before hold, minimal after hold.
local function findSafePoint(preferPos, eggPos, holding)
    local hrp = getHRP()
    if not hrp then return nil end
    local playerPos = hrp.Position
    local origin = preferPos or playerPos
    local y = playerPos.Y

    -- Reuse existing evade target if still valid (anti-thrash)
    local existing = HE.evadeTarget
    if typeof(existing) == "Vector3" then
        if isInsidePit(existing) and isPositionSafe(existing) then
            return existing
        end
    end

    local candidates = {}
    local function addCandidate(v)
        if typeof(v) ~= "Vector3" then return end
        table.insert(candidates, Vector3.new(v.X, y, v.Z))
    end

    addCandidate(origin)
    addCandidate(playerPos)

    -- Ring around player
    for angle = 0, 330, 30 do
        local rad = math.rad(angle)
        for _, dist in ipairs({ 5, 10, 16, 22, 28 }) do
            addCandidate(Vector3.new(playerPos.X + math.cos(rad) * dist, y, playerPos.Z + math.sin(rad) * dist))
        end
    end

    -- Candidates around Hot Egg (only when not holding — progress toward egg)
    if not holding and typeof(eggPos) == "Vector3" then
        addCandidate(eggPos)
        for angle = 0, 330, 45 do
            local rad = math.rad(angle)
            for _, dist in ipairs({ 4, 9, 14 }) do
                addCandidate(Vector3.new(eggPos.X + math.cos(rad) * dist, y, eggPos.Z + math.sin(rad) * dist))
            end
        end
    end

    -- Candidates near pit center (helps when player is pushed to edges)
    local center = pitCenter()
    if typeof(center) == "Vector3" then
        addCandidate(center)
        for angle = 0, 315, 45 do
            local rad = math.rad(angle)
            for _, dist in ipairs({ 8, 16 }) do
                addCandidate(Vector3.new(center.X + math.cos(rad) * dist, y, center.Z + math.sin(rad) * dist))
            end
        end
    end

    local best, bestScore = nil, math.huge
    for _, c in ipairs(candidates) do
        if not isInsidePit(c) then continue end
        if not isPositionSafe(c) then continue end
        local moveCost = flatDist(c, playerPos)
        local score
        if holding then
            -- After hold: minimize movement only
            score = moveCost
        else
            -- Before hold: safety + progress toward egg
            local eggCost = 0
            if typeof(eggPos) == "Vector3" then
                eggCost = flatDist(c, eggPos) * 1.35
            end
            score = moveCost * 0.85 + eggCost
        end
        if score < bestScore then
            bestScore = score
            best = c
        end
    end
    return best
end
local function findExitPoint(extraDist)
    local hrp = getHRP()
    if not hrp then return nil end
    local center = pitCenter()
    local base = pitRadius() + exitClearance() + 4 + (extraDist or 0)
    local flat = Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z)
    local dir = flat.Magnitude > 1 and flat.Unit or Vector3.new(1, 0, 0)
    local y = hrp.Position.Y
    for step = 0, 12 do
        local dist = base + step * 6
        local candidate = Vector3.new(center.X + dir.X * dist, y, center.Z + dir.Z * dist)
        if not isInsidePit(candidate) then return candidate end
    end
    return Vector3.new(center.X + dir.X * (base + 80), y, center.Z + dir.Z * (base + 80))
end
local function beginHotEggEnd()
    cancelMovement()
    if State.movementOwner == "AUTO_HOT_EGG" or State.movementOwner == "METEOR_AVOIDANCE" then
        State.movementOwner = "NONE"
    end
    clearEvadeState()
    HE.holding = false; HE.hazards = {}; HE.meteorCount = 0
    local hrp = getHRP()
    local inside = hrp and isInsidePit(hrp.Position) or false
    if not HE.exitPitAfter then heSetPhase("COMPLETE", "Done"); State.movementOwner = "NONE"; return end
    if not inside then heSetPhase("COMPLETE", "Already outside"); State.movementOwner = "NONE"; return end
    HE.exitAttempts = 0
    heSetPhase("EVENT_END_CONFIRMED", "Event over")
end
local function runPitExit()
    HE.exitAttempts = (HE.exitAttempts or 0) + 1
    local exitPos = findExitPoint(math.max(0, (HE.exitAttempts - 1) * 10))
    if not exitPos then return false end
    cancelMovement(); State.movementOwner = "NONE"
    moveTo(exitPos, HE.movementMode, "PIT_EXIT")
    heSetPhase("VERIFYING_PIT_EXIT", "Verifying exit")
    local deadline = os.clock() + 6
    while os.clock() < deadline do
        local h = getHRP()
        if h and not isInsidePit(h.Position) then
            heSetPhase("COMPLETE", "Pit exit confirmed")
            State.movementOwner = "NONE"
            return true
        end
        task.wait(0.2)
    end
    return false
end
local function heCancel()
    HE.generation += 1
    cancelMovement()
    if State.movementOwner == "AUTO_HOT_EGG" or State.movementOwner == "METEOR_AVOIDANCE" or State.movementOwner == "PIT_EXIT" then
        State.movementOwner = "NONE"
    end
    if not HE.enabled then heSetPhase("DISABLED", "—") end
end
local function heTick(token)
    local myGen = HE.generation
    while not token.cancelled and not State.closed and HE.enabled and myGen == HE.generation do
        pruneHazards()
        HE.holding = isLocalHolding()
        if not HE.endConfirmed then
            local ev = State.liveEvents["hotEgg"] or State.liveEvents["HotEgg"]
            if ev then HE.eventActive = true end
        else
            HE.eventActive = false
        end
        local egg = getHotEggPart()
        local activePhases = {
            EVENT_STARTED = true, WAITING_HOT_EGG = true, SEARCHING_HOT_EGG = true,
            MOVING_TO_HOT_EGG = true, VERIFYING_PICKUP = true, HOLDING_HOT_EGG = true,
            EVADING_METEOR = true, METEOR_WARNING = true,
        }
        if not HE.eventActive and not HE.endConfirmed and activePhases[HE.phase] then
            markHotEggEventFinished("soft-end")
        end
        if HE.phase == "EVENT_END_CONFIRMED" then heSetPhase("EXITING_PIT", "Leaving pit") end
        if HE.phase == "EXITING_PIT" or HE.phase == "VERIFYING_PIT_EXIT" then
            if runPitExit() then
                task.wait(1.2); heSetPhase("WAITING_EVENT", "Idle"); HE.endConfirmed = false
            else
                heSetPhase("EXITING_PIT", "Retry exit"); task.wait(0.35)
            end
            continue
        end
        if HE.phase == "COMPLETE" then
            task.wait(0.8); heSetPhase("WAITING_EVENT", "Idle"); HE.endConfirmed = false
            continue
        end
        if HE.endConfirmed and (activePhases[HE.phase] or (HE.phase ~= "WAITING_EVENT" and HE.phase ~= "DISABLED")) then
            beginHotEggEnd(); continue
        end
        if not HE.eventActive and not HE.endConfirmed then
            if HE.phase ~= "WAITING_EVENT" then heSetPhase("WAITING_EVENT", "Idle") end
            if egg then markHotEggEventStarted(); heSetPhase("EVENT_STARTED", "Egg present")
            else task.wait(0.4) continue end
        end
        -- Holding detection (state only; movement decided below)
        local holdingNow = isLocalHolding()
        HE.holding = holdingNow
        if typeof(egg) == "Instance" and egg:IsA("BasePart") then
            local hrpNow = getHRP()
            if hrpNow then HE.distToEgg = flatDist(hrpNow.Position, egg.Position) else HE.distToEgg = nil end
        else
            HE.distToEgg = nil
        end

        -- Meteor avoidance: only react to IMMINENT threats; reuse safe target; anti-thrash cooldown
        if HE.eventActive and not HE.endConfirmed and HE.meteorAvoidance then
            local h = getHRP()
            if h then
                local threatened = isPositionThreatened(h.Position)
                if threatened then
                    local now = os.clock()
                    local reuse = HE.evadeTarget
                    local canReuse = typeof(reuse) == "Vector3"
                        and isInsidePit(reuse)
                        and isPositionSafe(reuse)
                        and (now - (HE.lastEvadeDecision or 0)) < 1.25
                    local needNew = not canReuse
                    -- Emergency: always allow new target if current target is gone/unsafe
                    if needNew and (now - (HE.lastEvadeDecision or 0)) < EVADE_RESELECT_COOLDOWN and canReuse then
                        needNew = false
                    end
                    if needNew then
                        local eggPos = (not holdingNow and egg and egg:IsA("BasePart")) and egg.Position or nil
                        local safe = findSafePoint(h.Position, eggPos, holdingNow)
                        if safe then
                            HE.evadeTarget = safe
                            HE.evadeTargetTime = now
                            HE.lastEvadeDecision = now
                            HE.lastEvadeReason = holdingNow and "imminent (holding)" or "imminent (approach)"
                            heSetPhase("EVADING_METEOR", HE.lastEvadeReason)
                            -- Only cancel/restart movement if target moved meaningfully
                            local owner = State.movementOwner
                            local shouldRestart = true
                            if owner == "METEOR_AVOIDANCE" and typeof(reuse) == "Vector3" then
                                if flatDist(reuse, safe) < EVADE_REUSE_RADIUS then
                                    shouldRestart = false
                                end
                            end
                            if shouldRestart then
                                cancelMovement()
                                moveTo(safe, HE.movementMode, "METEOR_AVOIDANCE")
                            end
                        else
                            HE.lastEvadeReason = "no safe point"
                        end
                    else
                        -- Keep moving toward existing safe target
                        heSetPhase("EVADING_METEOR", "Hold safe target")
                        if State.movementOwner ~= "METEOR_AVOIDANCE" and typeof(HE.evadeTarget) == "Vector3" then
                            moveTo(HE.evadeTarget, HE.movementMode, "METEOR_AVOIDANCE")
                        end
                    end
                    task.wait(0.08)
                    continue
                else
                    -- Threat cleared — drop evade target so approach can resume immediately
                    if HE.evadeTarget ~= nil then
                        HE.evadeTarget = nil
                        HE.lastEvadeReason = "clear"
                        if State.movementOwner == "METEOR_AVOIDANCE" then
                            cancelMovement()
                            State.movementOwner = "NONE"
                        end
                    end
                end
            end
        end

        -- Holding mode: stay put when safe (no walk back to egg spawn)
        if HE.eventActive and not HE.endConfirmed and holdingNow then
            heSetPhase("HOLDING_HOT_EGG", "Holding")
            task.wait(0.25)
            continue
        end

        HE.holding = false
        if not HE.eventActive or HE.endConfirmed then task.wait(0.3) continue end
        if not egg then heSetPhase("WAITING_HOT_EGG", "Egg missing"); task.wait(0.35) continue end

        -- Safe approach toward Hot Egg (only when not threatened)
        heSetPhase("MOVING_TO_HOT_EGG", "Moving to egg")
        moveTo(egg.Position, HE.movementMode, "AUTO_HOT_EGG")
        if HE.endConfirmed or not HE.eventActive then beginHotEggEnd() continue end
        heSetPhase("VERIFYING_PICKUP", "Verifying pickup")
        local deadline = os.clock() + 2.5
        local got = false
        while os.clock() < deadline and myGen == HE.generation do
            if HE.endConfirmed or not HE.eventActive then break end
            -- Abort approach verification if an imminent threat appears
            local hh = getHRP()
            if hh and isPositionThreatened(hh.Position) then break end
            if isLocalHolding() then got = true break end
            task.wait(0.15)
        end
        if HE.endConfirmed or not HE.eventActive then beginHotEggEnd() continue end
        if got then heSetPhase("HOLDING_HOT_EGG", "Holding")
        else heSetPhase("SEARCHING_HOT_EGG", "Retry"); task.wait(0.25) end
    end
    if not HE.enabled then heSetPhase("DISABLED", "—") end
end
local function setAutoHotEgg(on)
    State.toggles.autoHotEgg = on
    HE.enabled = on
    heCancel()
    if on then
        HE.generation += 1; HE.endConfirmed = false
        heSetPhase("WAITING_EVENT", "Idle")
        maid:Task(heTick)
    else heSetPhase("DISABLED", "—") end
end

local AFR = State.autoFarmRebirth
local function afrSetPhase(phase, extra)
    AFR.phase = phase
    if extra then AFR.countdownLabel = extra end
end
local function afrCancel()
    AFR.generation += 1
    AFR.countdown = 0; AFR.countdownLabel = ""
    AFR.surrenderInFlight = false; AFR.declineInFlight = false
    if not AFR.enabled then afrSetPhase("DISABLED") end
end
local function waitTowerEnd(myGen, timeout)
    local deadline = os.clock() + (timeout or 12)
    while os.clock() < deadline and myGen == AFR.generation and AFR.enabled do
        if not isTowerActive() and (State.tower.status == "RUN ENDED" or not State.tower.runActive) then return true end
        task.wait(0.25)
    end
    return not isTowerActive()
end
local function requestSurrender(myGen)
    if AFR.surrenderInFlight then return true end
    AFR.surrenderInFlight = true
    afrSetPhase("SURRENDERING_TOWER")
    tryInvoke("TowerSurrender")
    afrSetPhase("WAITING_TOWER_END")
    local ended = waitTowerEnd(myGen, 12)
    AFR.surrenderInFlight = false
    return ended
end
local function requestDecline(myGen)
    if not isContinueOpen() or AFR.declineInFlight or not State.toggles.autoKoDismiss then return not isContinueOpen() end
    AFR.declineInFlight = true
    afrSetPhase("DECLINING_CONTINUE")
    tryInvoke("TowerContinueDecline")
    afrSetPhase("WAITING_TOWER_END")
    local deadline = os.clock() + 10
    while os.clock() < deadline and myGen == AFR.generation and AFR.enabled do
        if not isContinueOpen() and (State.tower.status == "RUN ENDED" or not isTowerActive()) then
            AFR.declineInFlight = false; return true
        end
        task.wait(0.25)
    end
    AFR.declineInFlight = false
    return not isContinueOpen()
end
local function requestRebirth(myGen)
    afrSetPhase("REBIRTH_REQUESTED")
    refreshData()
    local before = select(1, getRebirthInfo())
    if not tryInvoke("Rebirth") then afrSetPhase("ERROR") return false end
    afrSetPhase("WAITING_REBIRTH_CONFIRMATION")
    local deadline = os.clock() + 8
    while os.clock() < deadline and myGen == AFR.generation and AFR.enabled do
        refreshData()
        if select(1, getRebirthInfo()) > before then State.successfulRebirths += 1; return true end
        task.wait(0.35)
    end
    afrSetPhase("ERROR")
    return false
end
local function afrTick(token)
    local myGen = AFR.generation
    while not token.cancelled and not State.closed and AFR.enabled and myGen == AFR.generation do
        if State.movementOwner == "AUTO_HOT_EGG" or State.movementOwner == "METEOR_AVOIDANCE" or State.movementOwner == "PIT_EXIT" then
            task.wait(0.35) continue
        end
        if State.hotEgg.enabled and State.hotEgg.eventActive and not State.hotEgg.endConfirmed
            and State.hotEgg.phase ~= "COMPLETE" and State.hotEgg.phase ~= "DISABLED" and State.hotEgg.phase ~= "WAITING_EVENT" then
            task.wait(0.35) continue
        end
        refreshData()
        local ready = select(3, getRebirthInfo())
        if isContinueOpen() then
            afrSetPhase("CONTINUE_OFFER")
            if State.toggles.autoKoDismiss then
                requestDecline(myGen)
                refreshData()
                ready = select(3, getRebirthInfo())
                if not ready then
                    afrSetPhase("RETRY_WAIT")
                    for i = AFR.retryDelay, 1, -1 do
                        if myGen ~= AFR.generation or not AFR.enabled then return end
                        if isContinueOpen() or select(3, getRebirthInfo()) then break end
                        AFR.countdown = i; task.wait(1)
                    end
                    AFR.countdown = 0
                    if not isTowerActive() then setTowerStatus("IDLE") end
                    continue
                end
            else task.wait(0.5) continue end
        end
        if ready then
            afrSetPhase("REBIRTH_READY")
            if isTowerActive() then requestSurrender(myGen) end
            if isContinueOpen() and State.toggles.autoKoDismiss then requestDecline(myGen) end
            if isTowerActive() then waitTowerEnd(myGen, 8) end
            if myGen ~= AFR.generation or not AFR.enabled then return end
            if requestRebirth(myGen) and myGen == AFR.generation and AFR.enabled then
                afrSetPhase("POST_REBIRTH_COOLDOWN")
                for i = AFR.postRebirthDelay, 1, -1 do
                    if myGen ~= AFR.generation or not AFR.enabled then return end
                    AFR.countdown = i; task.wait(1)
                end
                AFR.countdown = 0
            else task.wait(2) end
            continue
        end
        if isTowerActive() then
            if State.tower.status == "K.O." then
                afrSetPhase("K.O.")
                local waitOffer = os.clock() + 2.5
                while os.clock() < waitOffer and myGen == AFR.generation do
                    if isContinueOpen() or State.tower.status == "RUN ENDED" then break end
                    task.wait(0.2)
                end
                if isContinueOpen() then continue end
                if not isTowerActive() then
                    afrSetPhase("RETRY_WAIT")
                    for i = AFR.retryDelay, 1, -1 do
                        if myGen ~= AFR.generation or not AFR.enabled then return end
                        AFR.countdown = i; task.wait(1)
                    end
                    AFR.countdown = 0; setTowerStatus("IDLE")
                end
            else afrSetPhase("TOWER_RUNNING"); task.wait(0.5) end
            continue
        end
        if State.tower.status == "IDLE" or State.tower.status == "RUN ENDED" or State.tower.status == "ERROR" then
            afrSetPhase("STARTING_TOWER")
            if tryInvoke("TowerStart") then
                local deadline = os.clock() + 6
                while os.clock() < deadline and myGen == AFR.generation do
                    if State.tower.runActive or State.tower.status == "RUNNING" then break end
                    task.wait(0.25)
                end
            else afrSetPhase("ERROR"); task.wait(3) end
        else task.wait(0.4) end
    end
    if not AFR.enabled then afrSetPhase("DISABLED") end
end
local function setAutoFarmRebirth(on)
    State.toggles.autoFarmRebirth = on
    AFR.enabled = on
    afrCancel()
    if on then
        AFR.generation += 1
        afrSetPhase("CHECKING_REBIRTH")
        maid:Task(afrTick)
    else afrSetPhase("DISABLED") end
end

local antiAfkGen = 0
local function setAntiAfk(on)
    State.toggles.antiAfk = on
    antiAfkGen += 1
    local my = antiAfkGen
    if on then
        maid:Task(function(token)
            while not token.cancelled and not State.closed and State.toggles.antiAfk and my == antiAfkGen do
                pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
                task.wait(60)
            end
        end)
    end
end

--------------------------------------------------------------------
-- UI
--------------------------------------------------------------------
local function corner(parent, r)
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = parent; return c
end
local function stroke(parent, color)
    local s = Instance.new("UIStroke"); s.Color = color or Theme.Border; s.Thickness = 1; s.Parent = parent; return s
end
local function pad(parent, t, r, b, l)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, t or 0); p.PaddingRight = UDim.new(0, r or t or 0)
    p.PaddingBottom = UDim.new(0, b or t or 0); p.PaddingLeft = UDim.new(0, l or r or t or 0)
    p.Parent = parent; return p
end
local function text(parent, str, size, color, font, xAlign)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1; l.Text = str or ""; l.Font = font or Enum.Font.Gotham
    l.TextSize = size or 13; l.TextColor3 = color or Theme.TextPrimary
    l.TextXAlignment = xAlign or Enum.TextXAlignment.Left
    l.TextYAlignment = Enum.TextYAlignment.Center; l.TextTruncate = Enum.TextTruncate.AtEnd
    l.Parent = parent
    return l
end
local function makeSwitch(parent, initial, onChange)
    local track = Instance.new("Frame")
    track.Size = UDim2.fromOffset(40, 22)
    track.BackgroundColor3 = initial and Theme.Primary or Color3.fromRGB(45, 48, 58)
    track.BorderSizePixel = 0; track.Parent = parent; corner(track, 11)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.fromOffset(16, 16)
    knob.Position = initial and UDim2.new(1, -19, 0.5, -8) or UDim2.fromOffset(3, 3)
    knob.BackgroundColor3 = Color3.new(1, 1, 1); knob.BorderSizePixel = 0; knob.Parent = track; corner(knob, 8)
    local btn = Instance.new("TextButton"); btn.Size = UDim2.fromScale(1, 1); btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = track
    local state = initial
    local function set(v, animate)
        state = v
        local goalPos = v and UDim2.new(1, -19, 0.5, -8) or UDim2.fromOffset(3, 3)
        local goalCol = v and Theme.Primary or Color3.fromRGB(45, 48, 58)
        if animate and not State.toggles.reducedMotion then
            TweenService:Create(knob, TweenInfo.new(0.15), { Position = goalPos }):Play()
            TweenService:Create(track, TweenInfo.new(0.15), { BackgroundColor3 = goalCol }):Play()
        else knob.Position = goalPos; track.BackgroundColor3 = goalCol end
    end
    btn.MouseButton1Click:Connect(function() set(not state, true); if onChange then onChange(state) end end)
    return track, set
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "UNO_HUB"; Gui.ResetOnSpawn = false; Gui.IgnoreGuiInset = true; Gui.DisplayOrder = 50
Gui:SetAttribute("UNO_HUB_Shutdown", false); Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Size = UDim2.fromOffset(900, 560); Main.Position = UDim2.fromScale(0.5, 0.5); Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.BackgroundColor3 = Theme.Background; Main.BorderSizePixel = 0; Main.ClipsDescendants = true; Main.Parent = Gui
corner(Main, 12); stroke(Main)

do
    local dragging, start, startPos
    maid:Connect(Main.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; start = input.Position; startPos = Main.Position end
    end)
    maid:Connect(UserInputService.InputChanged, function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - start
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    maid:Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.fromOffset(200, 560); Sidebar.BackgroundColor3 = Theme.Sidebar; Sidebar.BorderSizePixel = 0; Sidebar.Parent = Main; corner(Sidebar, 12)
local brand = Instance.new("Frame"); brand.Size = UDim2.new(1, 0, 0, 64); brand.BackgroundTransparency = 1; brand.Parent = Sidebar
text(brand, "UNO HUB", 18, Theme.Primary, Enum.Font.GothamBold).Position = UDim2.fromOffset(18, 14)
text(brand, "Grow a Chicken Fighter", 10, Theme.TextMuted).Position = UDim2.fromOffset(18, 38)

local NavScroll = Instance.new("ScrollingFrame")
NavScroll.Position = UDim2.fromOffset(0, 68); NavScroll.Size = UDim2.new(1, 0, 1, -130)
NavScroll.BackgroundTransparency = 1; NavScroll.BorderSizePixel = 0; NavScroll.ScrollBarThickness = 2
NavScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; NavScroll.CanvasSize = UDim2.new(); NavScroll.Parent = Sidebar
Instance.new("UIListLayout", NavScroll).Padding = UDim.new(0, 2)
pad(NavScroll, 4, 10, 8, 10)

local pages = {
    { id = "Home", icon = "◇", title = "Home" },
    { id = "Auto Farm", icon = "⚡", title = "Auto Farm" },
    { id = "Tower", icon = "△", title = "Tower" },
    { id = "Rebirth", icon = "↻", title = "Rebirth" },
    { id = "Eggs", icon = "○", title = "Eggs" },
    { id = "Chickens", icon = "★", title = "Chickens" },
    { id = "Fuse", icon = "⊕", title = "Fuse" },
    { id = "Incubator", icon = "◎", title = "Incubator" },
    { id = "Coop", icon = "⌂", title = "Coop" },
    { id = "Events", icon = "✦", title = "Events" },
    { id = "Utility", icon = "◈", title = "Utility" },
    { id = "Diagnostics", icon = "◉", title = "Diagnostics" },
    { id = "Settings", icon = "⚙", title = "Settings" },
}
local navButtons = {}
local pageDescs = {
    Home = "Overview", ["Auto Farm"] = "Farm + Collect", Tower = "Tower",
    Rebirth = "Rebirth", Eggs = "Hatch filter", Chickens = "Auto Sell",
    Fuse = "Auto Fuse", Incubator = "Auto claim", Coop = "Generators", Events = "Hot Egg",
    Utility = "Anti-AFK", Diagnostics = "Integration", Settings = "Actions",
}

local Profile = Instance.new("Frame")
Profile.Position = UDim2.new(0, 0, 1, -58); Profile.Size = UDim2.new(1, 0, 0, 58); Profile.BackgroundTransparency = 1; Profile.Parent = Sidebar
local avatar = Instance.new("ImageLabel")
avatar.Size = UDim2.fromOffset(32, 32); avatar.Position = UDim2.fromOffset(16, 10)
avatar.BackgroundColor3 = Theme.SurfaceElevated; avatar.BorderSizePixel = 0
avatar.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. LocalPlayer.UserId .. "&width=48&height=48&format=png"
avatar.Parent = Profile; corner(avatar, 8)
text(Profile, LocalPlayer.DisplayName, 12, Theme.TextPrimary, Enum.Font.GothamMedium).Position = UDim2.fromOffset(56, 10)
text(Profile, "@" .. LocalPlayer.Name, 10, Theme.TextMuted).Position = UDim2.fromOffset(56, 28)

local ContentRoot = Instance.new("Frame")
ContentRoot.Position = UDim2.fromOffset(200, 0); ContentRoot.Size = UDim2.new(1, -200, 1, 0)
ContentRoot.BackgroundColor3 = Theme.Background; ContentRoot.BorderSizePixel = 0; ContentRoot.Parent = Main
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 52); Topbar.BackgroundColor3 = Theme.Surface; Topbar.BorderSizePixel = 0; Topbar.Parent = ContentRoot; stroke(Topbar)
local PageTitle = text(Topbar, "HOME", 16, Theme.TextPrimary, Enum.Font.GothamBold)
PageTitle.Position = UDim2.fromOffset(20, 8); PageTitle.Size = UDim2.fromOffset(280, 20)
local PageDesc = text(Topbar, "Overview", 11, Theme.TextMuted)
PageDesc.Position = UDim2.fromOffset(20, 28); PageDesc.Size = UDim2.fromOffset(280, 16)
local connDot = Instance.new("Frame")
connDot.Size = UDim2.fromOffset(7, 7); connDot.Position = UDim2.new(1, -160, 0.5, -3)
connDot.BackgroundColor3 = Theme.Success; connDot.BorderSizePixel = 0; connDot.Parent = Topbar; corner(connDot, 4)
local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.fromOffset(28, 28); minBtn.Position = UDim2.new(1, -72, 0.5, -14)
minBtn.BackgroundColor3 = Theme.SurfaceElevated; minBtn.Text = "—"; minBtn.Font = Enum.Font.GothamBold
minBtn.TextSize = 14; minBtn.TextColor3 = Theme.TextSecondary; minBtn.AutoButtonColor = false; minBtn.Parent = Topbar; corner(minBtn, 6)
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28); closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
closeBtn.BackgroundColor3 = Theme.SurfaceElevated; closeBtn.Text = "✕"; closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12; closeBtn.TextColor3 = Theme.TextSecondary; closeBtn.AutoButtonColor = false; closeBtn.Parent = Topbar; corner(closeBtn, 6)
local PageHost = Instance.new("Frame")
PageHost.Position = UDim2.fromOffset(0, 52); PageHost.Size = UDim2.new(1, 0, 1, -52)
PageHost.BackgroundTransparency = 1; PageHost.ClipsDescendants = true; PageHost.Parent = ContentRoot
local Float = Instance.new("TextButton")
Float.Size = UDim2.fromOffset(52, 32); Float.Position = UDim2.new(0, 24, 0.5, -16)
Float.BackgroundColor3 = Theme.Primary; Float.Text = "UNO"; Float.Font = Enum.Font.GothamBold
Float.TextSize = 13; Float.TextColor3 = Color3.new(1, 1, 1); Float.Visible = false; Float.AutoButtonColor = false; Float.Parent = Gui; corner(Float, 8)

local function setVisible(vis)
    if State.closed then return end
    State.visible = vis
    if vis then Main.Visible = true; Float.Visible = false
    else Main.Visible = false; if State.toggles.showFloatingButton then Float.Visible = true end end
end
local function shutdown()
    State.closed = true; State.generation += 1
    -- save config while feature getters still available
    if ConfigManager then pcall(function() ConfigManager.destroy() end) end
    if AutoCollectEggFeature then pcall(function() AutoCollectEggFeature.setAutoCollectEggs(false); AutoCollectEggFeature.destroy() end) end
    if AutoSellFeature then pcall(function() AutoSellFeature.setAutoSell(false); AutoSellFeature.destroy() end) end
    if AutoFuseFeature then pcall(function() AutoFuseFeature.setAutoFuse(false); AutoFuseFeature.destroy() end) end
    HatchFeature.setAutoHatch(false)
    IncubatorClaimFeature.setAutoIncubatorClaim(false)
    if AutoUpgradeIncubatorFeature then pcall(function() AutoUpgradeIncubatorFeature.setAutoUpgradeIncubator(false) end) end
    afrCancel(); heCancel(); antiAfkGen += 1
    for name in pairs(Economy.generations) do stopEconomy(name) end
    for k in pairs(State.toggles) do State.toggles[k] = false end
    if PerformanceManager then pcall(function() PerformanceManager.destroy() end) end
    if visualCoverGui then pcall(function() visualCoverGui:Destroy() end); visualCoverGui = nil end
    maid:Cleanup(); Gui:Destroy()
end
minBtn.MouseButton1Click:Connect(function() setVisible(false) end)
closeBtn.MouseButton1Click:Connect(shutdown)
Float.MouseButton1Click:Connect(function() setVisible(true) end)
maid:Connect(UserInputService.InputBegan, function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if UserInputService:GetFocusedTextBox() then return end
        setVisible(not State.visible)
    end
end)

local Views = {}
local function createScrollPage()
    local sc = Instance.new("ScrollingFrame")
    sc.Name = "PageRoot"
    sc.Size = UDim2.fromScale(1, 1)
    sc.Position = UDim2.fromOffset(0, 0)
    sc.BackgroundTransparency = 1
    sc.BorderSizePixel = 0
    sc.ScrollBarThickness = 3
    sc.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sc.CanvasSize = UDim2.new(0, 0, 0, 0)
    sc.ZIndex = 2
    sc.Visible = false
    sc.Parent = PageHost
    local lay = Instance.new("UIListLayout")
    lay.Name = "PageLayout"
    lay.Padding = UDim.new(0, 10)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sc
    pad(sc, 16, 18, 20, 18)
    -- Fallback if AutomaticCanvasSize stalls at 0
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        local y = lay.AbsoluteContentSize.Y + 36
        if y > 0 and (sc.AbsoluteCanvasSize.Y < 1 or sc.CanvasSize.Y.Offset < y) then
            sc.CanvasSize = UDim2.new(0, 0, 0, y)
        end
    end)
    return sc
end
local function card(parent, order, title, desc)
    local f = Instance.new("Frame")
    f.LayoutOrder = order or 0; f.Size = UDim2.new(1, 0, 0, 0); f.AutomaticSize = Enum.AutomaticSize.Y
    f.BackgroundColor3 = Theme.Surface; f.BorderSizePixel = 0; f.Parent = parent; corner(f, 9); stroke(f)
    local inner = Instance.new("Frame")
    inner.Size = UDim2.new(1, 0, 0, 0); inner.AutomaticSize = Enum.AutomaticSize.Y; inner.BackgroundTransparency = 1; inner.Parent = f
    pad(inner, 12, 14, 12, 14)
    local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 6); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = inner
    if title then
        local h = Instance.new("Frame"); h.Size = UDim2.new(1, 0, 0, 18); h.BackgroundTransparency = 1; h.LayoutOrder = 0; h.Parent = inner
        text(h, title, 12, Theme.TextSecondary, Enum.Font.GothamMedium).Size = UDim2.new(1, 0, 1, 0)
        if desc then
            local d = text(inner, desc, 11, Theme.TextMuted); d.Size = UDim2.new(1, 0, 0, 14); d.LayoutOrder = 1
        end
    end
    return f, inner
end
local function row(parent, order, left)
    local r = Instance.new("Frame"); r.LayoutOrder = order or 0; r.Size = UDim2.new(1, 0, 0, 22); r.BackgroundTransparency = 1; r.Parent = parent
    text(r, left, 12, Theme.TextMuted).Size = UDim2.new(0.5, 0, 1, 0)
    local v = text(r, "—", 12, Theme.TextPrimary, Enum.Font.GothamMedium, Enum.TextXAlignment.Right)
    v.Size = UDim2.new(0.5, 0, 1, 0); v.Position = UDim2.fromScale(0.5, 0)
    return v
end
local function settingRow(parent, order, title, desc, key, onChange)
    local f = Instance.new("Frame"); f.LayoutOrder = order or 0; f.Size = UDim2.new(1, 0, 0, 0)
    f.AutomaticSize = Enum.AutomaticSize.Y; f.BackgroundTransparency = 1; f.Parent = parent; pad(f, 4, 0, 4, 0)
    local top = Instance.new("Frame"); top.Size = UDim2.new(1, 0, 0, 24); top.BackgroundTransparency = 1; top.Parent = f
    text(top, title, 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
    local sw = select(1, makeSwitch(top, State.toggles[key] == true, function(v)
        State.toggles[key] = v
        if onChange then onChange(v) end
        markConfigDirty()
    end))
    sw.Position = UDim2.new(1, -40, 0.5, -11)
end
local function safeBuild(name, fn)
    local ok, err = xpcall(fn, function(e)
        if type(debug) == "table" and type(debug.traceback) == "function" then
            return debug.traceback(tostring(e), 2)
        end
        return tostring(e)
    end)
    if not ok then
        log("ERROR", "Build " .. name .. ": " .. tostring(err))
        warn("[UNO UI] PAGE ERROR", name, err)
        local sc = createScrollPage()
        local _, inner = card(sc, 1, "PAGE ERROR")
        setText(row(inner, 1, "Error"), tostring(err))
        Views[name] = { root = sc, update = function() end }
    end
end

local function makeFilterRow(parent, order, displayName, quantityText, checked, onToggle)
    local f = Instance.new("Frame")
    f.LayoutOrder = order
    f.Size = UDim2.new(1, 0, 0, 26)
    f.BackgroundTransparency = 1
    f.Parent = parent
    local check = Instance.new("TextButton")
    check.Size = UDim2.fromOffset(22, 22)
    check.Position = UDim2.fromOffset(0, 2)
    check.BackgroundColor3 = Theme.SurfaceElevated
    check.Text = checked and "✓" or ""
    check.Font = Enum.Font.GothamBold
    check.TextSize = 14
    check.TextColor3 = Theme.Success
    check.AutoButtonColor = false
    check.Parent = f
    corner(check, 4)
    local nameL = text(f, displayName, 12, Theme.TextPrimary)
    nameL.Position = UDim2.fromOffset(30, 0)
    nameL.Size = UDim2.new(1, -110, 1, 0)
    local qtyL = nil
    if quantityText then
        qtyL = text(f, quantityText, 12, Theme.TextMuted, nil, Enum.TextXAlignment.Right)
        qtyL.Position = UDim2.new(1, -70, 0, 0)
        qtyL.Size = UDim2.fromOffset(66, 26)
    end
    check.MouseButton1Click:Connect(function() onToggle(check) end)
    return f, check, nameL, qtyL
end

safeBuild("Home", function()
    local sc = createScrollPage()
    local _, afr = card(sc, 1, "AUTO FARM REBIRTH")
    local phase = row(afr, 1, "Phase")
    local _, sell = card(sc, 2, "AUTO SELL")
    local sSt = row(sell, 1, "Status")
    local _, he = card(sc, 3, "HOT EGG")
    local hePhase = row(he, 1, "Phase")
    Views.Home = { root = sc, update = function()
        setText(phase, AFR.phase)
        setText(sSt, AutoSellFeature and AutoSellFeature.getStatus() or State.diagnostics["AutoSell.Feature"] or "—")
        setText(hePhase, HE.phase)
    end }
end)

safeBuild("Auto Farm", function()
    local sc = createScrollPage()
    local _, primary = card(sc, 1, "PRIMARY")
    settingRow(primary, 1, "Auto Farm Rebirth", nil, "autoFarmRebirth", setAutoFarmRebirth)
    settingRow(primary, 2, "Auto K.O. Dismiss", nil, "autoKoDismiss")
    settingRow(primary, 3, "Auto Hatch Eggs", nil, "autoHatch", function(v) HatchFeature.setAutoHatch(v) end)
    if AutoCollectEggFeature then
        local _, collectCard = card(sc, 2, "AUTO COLLECT LAID EGGS")
        settingRow(collectCard, 1, "Auto Collect Laid Eggs", nil, "autoCollectEgg", function(v)
            AutoCollectEggFeature.setAutoCollectEggs(v)
        end)
        local cState = row(collectCard, 2, "Status")
        local cCount = row(collectCard, 3, "Detected Eggs")
        Views["Auto Farm"] = { root = sc, update = function()
            local st = AutoCollectEggFeature.getStatus()
            setText(cState, st.state)
            setText(cCount, st.trackedEggCount)
        end }
    else
        Views["Auto Farm"] = { root = sc, update = function() end }
    end
end)

safeBuild("Tower", function()
    local sc = createScrollPage()
    local _, ov = card(sc, 1, "TOWER")
    local floor = row(ov, 1, "Floor"); local status = row(ov, 2, "Status")
    settingRow(ov, 3, "Auto K.O. Dismiss", nil, "autoKoDismiss")
    Views.Tower = { root = sc, update = function()
        setText(floor, State.tower.floor); setText(status, State.tower.status)
    end }
end)
safeBuild("Rebirth", function()
    local sc = createScrollPage()
    local _, top = card(sc, 1, "REBIRTH")
    local ready = row(top, 1, "Status")
    settingRow(top, 2, "Auto Farm Rebirth", nil, "autoFarmRebirth", setAutoFarmRebirth)
    Views.Rebirth = { root = sc, update = function()
        setText(ready, select(3, getRebirthInfo()) and "READY" or "NOT READY")
    end }
end)

safeBuild("Eggs", function()
    local sc = createScrollPage()
    local _, hatchCard = card(sc, 1, "AUTO HATCH EGGS")
    settingRow(hatchCard, 1, "Auto Hatch Eggs", nil, "autoHatch", function(v) HatchFeature.setAutoHatch(v) end)
    local st = row(hatchCard, 2, "Status")
    local tgt = row(hatchCard, 3, "Target")

    local _, filterCard = card(sc, 2, "EGG FILTER")
    local filterHost = Instance.new("Frame")
    filterHost.LayoutOrder = 10
    filterHost.Size = UDim2.new(1, 0, 0, 0)
    filterHost.AutomaticSize = Enum.AutomaticSize.Y
    filterHost.BackgroundTransparency = 1
    filterHost.Parent = filterCard
    Instance.new("UIListLayout", filterHost).Padding = UDim.new(0, 4)

    local btnRow = Instance.new("Frame")
    btnRow.LayoutOrder = 0
    btnRow.Size = UDim2.new(1, 0, 0, 28)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = filterHost
    local function smallBtn(parent, label, x, fn)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(90, 24)
        b.Position = UDim2.fromOffset(x, 2)
        b.BackgroundColor3 = Theme.SurfaceElevated
        b.Text = label
        b.Font = Enum.Font.Gotham
        b.TextSize = 11
        b.TextColor3 = Theme.TextPrimary
        b.AutoButtonColor = false
        b.Parent = parent
        corner(b, 5)
        b.MouseButton1Click:Connect(fn)
    end
    smallBtn(btnRow, "Select All", 0, function()
        HatchFeature.selectAllAvailableEggs()
        HatchFeature.userCustomized = true
    end)
    smallBtn(btnRow, "Clear", 96, function() HatchFeature.clearEggSelection() end)

    local eggRows = {}
    Views.Eggs = { root = sc, update = function()
        refreshData()
        local available = HatchFeature.getAvailableEggTypes()
        for i, egg in ipairs(available) do
            local key = egg.key
            local friendly = egg.displayName
            if type(friendly) ~= "string" or friendly == "" then
                friendly = resolveEggDisplayName(egg.id)
            end
            local rowUI = eggRows[key]
            if not rowUI then
                local f, check, nameL, qtyL = makeFilterRow(
                    filterHost, 10 + i, friendly, "x" .. tostring(egg.quantity),
                    HatchFeature.isEggSelected(egg.id),
                    function(checkBtn)
                        local now = not HatchFeature.isEggSelected(egg.id)
                        HatchFeature.setEggSelected(egg.id, now)
                        checkBtn.Text = now and "✓" or ""
                    end
                )
                eggRows[key] = { frame = f, check = check, name = nameL, qty = qtyL, id = egg.id }
            else
                rowUI.name.Text = friendly
                if rowUI.qty then rowUI.qty.Text = "x" .. tostring(egg.quantity) end
                rowUI.check.Text = HatchFeature.isEggSelected(egg.id) and "✓" or ""
            end
        end
        local hs = HatchFeature.getStatus()
        setText(st, hs.status)
        setText(tgt, hs.target and resolveEggDisplayName(hs.target) or hs.target)
    end }
end)

-- CHICKENS PAGE (Auto Sell restored)
safeBuild("Chickens", function()
    local sc = createScrollPage()
    local _, sellCard = card(sc, 1, "AUTO SELL CHICKENS")

    if not AutoSellFeature then
        local err = State.diagnostics["AutoSell.Feature"] or "unknown error"
        setText(row(sellCard, 1, "Status"), tostring(err))
        setText(row(sellCard, 2, "Remotes"), State.diagnostics["AutoSell.Remotes"] or "—")
        setText(row(sellCard, 3, "DataController"), State.diagnostics["AutoSell.DataController"] or "—")
        setText(row(sellCard, 4, "Catalog"), State.diagnostics["AutoSell.Catalog"] or "—")
        setText(row(sellCard, 5, "SellChickens"), State.diagnostics["AutoSell.SellChickens"] or "—")
        Views.Chickens = { root = sc, update = function() end }
        return
    end

    settingRow(sellCard, 1, "Auto Sell Chickens", nil, "autoSell", function(v)
        AutoSellFeature.setAutoSell(v)
    end)
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 2; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = sellCard
        text(f, "Dry Run", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, AutoSellFeature.getDryRun() == true, function(v)
            AutoSellFeature.setDryRun(v)
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 3; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = sellCard
        text(f, "Protect Mutated", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, AutoSellFeature.getProtectMutated() == true, function(v)
            AutoSellFeature.setProtectMutated(v)
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 4; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = sellCard
        text(f, "Protect Favorites", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, AutoSellFeature.getProtectFavorites() == true, function(v)
            AutoSellFeature.setProtectFavorites(v)
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end

    local _, rarityCard = card(sc, 2, "RARITY FILTER")
    local rarityHost = Instance.new("Frame")
    rarityHost.LayoutOrder = 5
    rarityHost.Size = UDim2.new(1, 0, 0, 0)
    rarityHost.AutomaticSize = Enum.AutomaticSize.Y
    rarityHost.BackgroundTransparency = 1
    rarityHost.Parent = rarityCard
    Instance.new("UIListLayout", rarityHost).Padding = UDim.new(0, 4)

    local rarities = AutoSellFeature.getAvailableRarities()
    if #rarities == 0 then
        rarities = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "divine", "celestial", "cosmic", "secret" }
    end
    for i, rarityId in ipairs(rarities) do
        local friendly = resolveRarityDisplayName(rarityId)
        diagNameOnce("RARITY", rarityId, friendly)
        makeFilterRow(rarityHost, i, friendly, nil, AutoSellFeature.isRaritySelected(rarityId), function(checkBtn)
            local now = not AutoSellFeature.isRaritySelected(rarityId)
            AutoSellFeature.setRaritySelected(rarityId, now)
            checkBtn.Text = now and "✓" or ""
        end)
    end

    local _, abilityCard = card(sc, 3, "ABILITY WHITELIST")
    local abilityHost = Instance.new("Frame")
    abilityHost.LayoutOrder = 5
    abilityHost.Size = UDim2.new(1, 0, 0, 0)
    abilityHost.AutomaticSize = Enum.AutomaticSize.Y
    abilityHost.BackgroundTransparency = 1
    abilityHost.Parent = abilityCard
    Instance.new("UIListLayout", abilityHost).Padding = UDim.new(0, 4)

    local abilities = AutoSellFeature.getAvailableAbilities()
    if #abilities == 0 then
        abilities = {
            { id = "voodoo", name = "Voodoo" },
            { id = "cycleofash", name = "Cycle of Ash" },
        }
    end
    table.sort(abilities, function(a, b)
        return resolveAbilityDisplayName(a) < resolveAbilityDisplayName(b)
    end)
    for i, ab in ipairs(abilities) do
        local aid = ab.id
        local friendly = resolveAbilityDisplayName(ab)
        diagNameOnce("ABILITY", aid, friendly)
        makeFilterRow(abilityHost, i, friendly, nil, AutoSellFeature.isAbilityWhitelisted(aid), function(checkBtn)
            local now = not AutoSellFeature.isAbilityWhitelisted(aid)
            AutoSellFeature.setAbilityWhitelisted(aid, now)
            checkBtn.Text = now and "✓" or ""
        end)
    end

    local _, statsCard = card(sc, 4, "SELL STATUS / DIAGNOSTICS")
    local sStatus = row(statsCard, 1, "Status")
    local sDry = row(statsCard, 2, "Dry Run")
    local sSel = row(statsCard, 3, "Selected Rarities")
    local sEval = row(statsCard, 4, "Evaluated")
    local sSold = row(statsCard, 5, "Confirmed Sold")
    local sAct = row(statsCard, 6, "Protected Active")
    local sFav = row(statsCard, 7, "Protected Favorite")
    local sMut = row(statsCard, 8, "Protected Mutated")
    local sAb = row(statsCard, 9, "Protected Ability")
    local sInc = row(statsCard, 10, "Protected Incubator")
    local sFail = row(statsCard, 11, "Failed / Not Confirmed")
    local sBatch = row(statsCard, 12, "Last Batch")
    local sErr = row(statsCard, 13, "Last Error")

    Views.Chickens = { root = sc, update = function()
        setText(sStatus, AutoSellFeature.getStatus())
        setText(sDry, AutoSellFeature.getDryRun() and "ON" or "OFF")
        local st = AutoSellFeature.getStats()
        local sel = st.selectedRarities or {}
        setText(sSel, #sel > 0 and table.concat(sel, ", ") or "(none)")
        setText(sEval, st.totalEvaluated)
        setText(sSold, st.totalSoldConfirmed)
        setText(sAct, st.totalProtectedActive)
        setText(sFav, st.totalProtectedFavorite)
        setText(sMut, st.totalProtectedMutated)
        setText(sAb, st.totalProtectedAbility)
        setText(sInc, st.totalProtectedIncubator)
        setText(sFail, st.totalFailedNotConfirmed)
        setText(sBatch, st.lastBatchSize)
        setText(sErr, st.lastError)
    end }
end)


-- FUSE PAGE
safeBuild("Fuse", function()
    local sc = createScrollPage()
    local _, fuseCard = card(sc, 1, "AUTO FUSE CHICKENS")

    if not AutoFuseFeature then
        local err = State.diagnostics["AutoFuse.Feature"] or "unknown error"
        setText(row(fuseCard, 1, "Status"), tostring(err))
        setText(row(fuseCard, 2, "Remotes"), State.diagnostics["AutoFuse.Remotes"] or "—")
        setText(row(fuseCard, 3, "FusionRules"), State.diagnostics["AutoFuse.FusionRules"] or "—")
        setText(row(fuseCard, 4, "FuseChickens"), State.diagnostics["AutoFuse.FuseChickens"] or "—")
        Views.Fuse = { root = sc, update = function() end }
        return
    end

    settingRow(fuseCard, 1, "Auto Fuse Chickens", nil, "autoFuse", function(v)
        AutoFuseFeature.setAutoFuse(v)
    end)
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 2; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = fuseCard
        text(f, "Dry Run", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, AutoFuseFeature.getDryRun() == true, function(v)
            AutoFuseFeature.setDryRun(v)
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end
    setText(row(fuseCard, 3, "Active Chicken"), "ALWAYS PROTECTED")
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 4; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = fuseCard
        text(f, "Protect Favorites", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, AutoFuseFeature.getProtectFavorites() == true, function(v)
            AutoFuseFeature.setProtectFavorites(v)
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 5; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = fuseCard
        text(f, "Protect Mutated", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, AutoFuseFeature.getProtectMutated() == true, function(v)
            AutoFuseFeature.setProtectMutated(v)
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end

    -- Match Mode
    local _, matchCard = card(sc, 2, "MATCH MODE")
    local matchLabel = row(matchCard, 1, "Mode")
    local function matchBtn(parent, order, label, mode)
        local f = Instance.new("Frame"); f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = parent
        local b = Instance.new("TextButton")
        b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundColor3 = Theme.SurfaceElevated
        b.Text = label
        b.Font = Enum.Font.Gotham
        b.TextSize = 12
        b.TextColor3 = Theme.TextPrimary
        b.AutoButtonColor = false
        b.Parent = f
        corner(b, 6)
        b.MouseButton1Click:Connect(function()
            AutoFuseFeature.setMatchMode(mode)
        end)
    end
    matchBtn(matchCard, 2, "Same Chicken", "Same Chicken")
    matchBtn(matchCard, 3, "Same Rarity", "Same Rarity")

    -- Keep Copies
    local _, keepCard = card(sc, 3, "KEEP COPIES PER CHICKEN")
    local keepVal = row(keepCard, 1, "Keep Copies")
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 2; f.Size = UDim2.new(1, 0, 0, 30)
        f.BackgroundTransparency = 1; f.Parent = keepCard
        local function nbtn(x, label, delta)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(36, 26)
            b.Position = UDim2.fromOffset(x, 2)
            b.BackgroundColor3 = Theme.SurfaceElevated
            b.Text = label
            b.Font = Enum.Font.GothamBold
            b.TextSize = 14
            b.TextColor3 = Theme.TextPrimary
            b.AutoButtonColor = false
            b.Parent = f
            corner(b, 6)
            b.MouseButton1Click:Connect(function()
                local cur = AutoFuseFeature.getKeepCopies() or 1
                AutoFuseFeature.setKeepCopies(math.max(0, cur + delta))
            end)
        end
        nbtn(0, "−", -1)
        nbtn(44, "+", 1)
    end

    -- Rarity Filter
    local _, rarityCard = card(sc, 4, "RARITY FILTER")
    local rarityHost = Instance.new("Frame")
    rarityHost.LayoutOrder = 5
    rarityHost.Size = UDim2.new(1, 0, 0, 0)
    rarityHost.AutomaticSize = Enum.AutomaticSize.Y
    rarityHost.BackgroundTransparency = 1
    rarityHost.Parent = rarityCard
    Instance.new("UIListLayout", rarityHost).Padding = UDim.new(0, 4)
    do
        local btnRow = Instance.new("Frame")
        btnRow.LayoutOrder = 0
        btnRow.Size = UDim2.new(1, 0, 0, 28)
        btnRow.BackgroundTransparency = 1
        btnRow.Parent = rarityHost
        local function smallBtn(parent, label, x, fn)
            local b = Instance.new("TextButton")
            b.Size = UDim2.fromOffset(90, 24)
            b.Position = UDim2.fromOffset(x, 2)
            b.BackgroundColor3 = Theme.SurfaceElevated
            b.Text = label
            b.Font = Enum.Font.Gotham
            b.TextSize = 11
            b.TextColor3 = Theme.TextPrimary
            b.AutoButtonColor = false
            b.Parent = parent
            corner(b, 5)
            b.MouseButton1Click:Connect(fn)
        end
        smallBtn(btnRow, "Select All", 0, function() AutoFuseFeature.selectAllRarities() end)
        smallBtn(btnRow, "Clear", 96, function() AutoFuseFeature.clearRaritySelection() end)
    end
    local rarities = AutoFuseFeature.getAvailableRarities()
    for i, rarityId in ipairs(rarities) do
        local friendly = resolveRarityDisplayName(rarityId)
        diagNameOnce("FUSE_RARITY", rarityId, friendly)
        makeFilterRow(rarityHost, 10 + i, friendly, nil, AutoFuseFeature.isRaritySelected(rarityId), function(checkBtn)
            local now = not AutoFuseFeature.isRaritySelected(rarityId)
            AutoFuseFeature.setRaritySelected(rarityId, now)
            checkBtn.Text = now and "✓" or ""
        end)
    end

    -- Ability whitelist
    local _, abilityCard = card(sc, 5, "PROTECTED ABILITIES")
    local abilityHost = Instance.new("Frame")
    abilityHost.LayoutOrder = 5
    abilityHost.Size = UDim2.new(1, 0, 0, 0)
    abilityHost.AutomaticSize = Enum.AutomaticSize.Y
    abilityHost.BackgroundTransparency = 1
    abilityHost.Parent = abilityCard
    Instance.new("UIListLayout", abilityHost).Padding = UDim.new(0, 4)
    local abilitiesMap = AutoFuseFeature.getAvailableAbilities()
    local abilities = {}
    if type(abilitiesMap) == "table" then
        for id, def in pairs(abilitiesMap) do
            table.insert(abilities, type(def) == "table" and def or { id = id, name = id })
        end
    end
    if #abilities == 0 then
        abilities = {
            { id = "voodoo", name = "Voodoo" },
            { id = "cycleofash", name = "Cycle of Ash" },
        }
    end
    table.sort(abilities, function(a, b)
        return resolveAbilityDisplayName(a) < resolveAbilityDisplayName(b)
    end)
    for i, ab in ipairs(abilities) do
        local aid = ab.id
        local friendly = resolveAbilityDisplayName(ab)
        diagNameOnce("FUSE_ABILITY", aid, friendly)
        makeFilterRow(abilityHost, i, friendly, nil, AutoFuseFeature.isAbilityWhitelisted(aid), function(checkBtn)
            local now = not AutoFuseFeature.isAbilityWhitelisted(aid)
            AutoFuseFeature.setAbilityWhitelisted(aid, now)
            checkBtn.Text = now and "✓" or ""
        end)
    end

    -- Status / stats
    local _, statsCard = card(sc, 6, "FUSE STATUS / DIAGNOSTICS")
    local sStatus = row(statsCard, 1, "Status")
    local sDry = row(statsCard, 2, "Dry Run")
    local sMatch = row(statsCard, 3, "Match Mode")
    local sKeep = row(statsCard, 4, "Keep Copies")
    local sElig = row(statsCard, 5, "Eligible")
    local sPairs = row(statsCard, 6, "Pairs Available")
    local sRes = row(statsCard, 7, "Reserved Keep")
    local sConf = row(statsCard, 8, "Confirmed Fusions")
    local sPA = row(statsCard, 9, "Last Parent A")
    local sPB = row(statsCard, 10, "Last Parent B")
    local sResId = row(statsCard, 11, "Last Result")
    local sRar = row(statsCard, 12, "Last Result Rarity")
    local sAsc = row(statsCard, 13, "Ascended")
    local sCost = row(statsCard, 14, "Last Cost")
    local sErr = row(statsCard, 15, "Last Error")

    Views.Fuse = { root = sc, update = function()
        setText(sStatus, AutoFuseFeature.getStatus())
        setText(sDry, AutoFuseFeature.getDryRun() and "ON" or "OFF")
        setText(sMatch, AutoFuseFeature.getMatchMode())
        setText(sKeep, AutoFuseFeature.getKeepCopies())
        setText(keepVal, AutoFuseFeature.getKeepCopies())
        setText(matchLabel, AutoFuseFeature.getMatchMode())
        local st = AutoFuseFeature.getStats()
        setText(sElig, st.eligibleChickens)
        setText(sPairs, st.pairsBuilt)
        setText(sRes, st.reservedKeepCopies)
        setText(sConf, st.confirmedFusions)
        setText(sPA, st.lastParentA)
        setText(sPB, st.lastParentB)
        setText(sResId, st.lastResultId)
        setText(sRar, st.lastResultRarity)
        setText(sAsc, st.lastAscended)
        setText(sCost, st.lastCost)
        setText(sErr, st.lastError)
    end }
end)

safeBuild("Incubator", function()
    local sc = createScrollPage()
    local _, info = card(sc, 1, "INCUBATOR")
    local level = row(info, 1, "Level"); local eggs = row(info, 2, "Stored")
    local _, claim = card(sc, 2, "AUTO CLAIM")
    settingRow(claim, 1, "Auto Claim Eggs", nil, "autoIncubatorClaim", function(v) IncubatorClaimFeature.setAutoIncubatorClaim(v) end)
    local cStatus = row(claim, 2, "Status")
    Views.Incubator = { root = sc, update = function()
        local is = IncubatorClaimFeature.getStatus()
        setText(level, is.level); setText(eggs, is.eggCount); setText(cStatus, is.status)
    end }
end)
safeBuild("Coop", function()
    local sc = createScrollPage()
    local _, status = card(sc, 1, "COOP")
    local slots = row(status, 1, "Generators")
    local _, auto = card(sc, 2, "AUTOMATION")
    settingRow(auto, 1, "Auto Buy Generator", nil, "autoBuyGenerator", setAutoBuyGenerator)
    settingRow(auto, 2, "Auto Upgrade Generator", nil, "autoUpgradeGenerator", setAutoUpgradeGenerator)
    settingRow(auto, 3, "Auto Expand Coop", nil, "autoExpandCoop", setAutoExpandCoop)
    settingRow(auto, 4, "Auto Upgrade Recycler", nil, "autoUpgradeRecycler", setAutoUpgradeRecycler)

    local _, incCard = card(sc, 3, "INCUBATOR")
    settingRow(incCard, 1, "Auto Upgrade Incubator", nil, "autoUpgradeIncubator", function(v)
        if AutoUpgradeIncubatorFeature then
            AutoUpgradeIncubatorFeature.setAutoUpgradeIncubator(v)
        end
    end)
    local iLevel = row(incCard, 2, "Level")
    local iCost = row(incCard, 3, "Next Upgrade Cost")
    local iReb = row(incCard, 4, "Required Rebirth")
    local iStatus = row(incCard, 5, "Status")

    Views.Coop = { root = sc, update = function()
        refreshEconomyStatus()
        setText(slots, string.format("%d / %d", State.economy.generatorsOwned, State.economy.generatorsSlots))
        if AutoUpgradeIncubatorFeature then
            local st = AutoUpgradeIncubatorFeature.getStatus()
            setText(iLevel, st.level)
            setText(iCost, st.nextCost)
            setText(iReb, st.requiredRebirth)
            setText(iStatus, st.status)
        else
            setText(iStatus, State.diagnostics["AutoUpgradeIncubator.Feature"] or "—")
        end
    end }
end)
safeBuild("Events", function()
    local sc = createScrollPage()
    local _, heCard = card(sc, 1, "HOT EGG")
    settingRow(heCard, 1, "Auto Hot Egg", nil, "autoHotEgg", setAutoHotEgg)
    local phase = row(heCard, 2, "Phase")
    local ended = row(heCard, 3, "End Confirmed")
    local holding = row(heCard, 4, "Holding Egg")
    local hazards = row(heCard, 5, "Active Hazards")
    local threat = row(heCard, 6, "Threatening")
    local dist = row(heCard, 7, "Dist To Egg")
    local evade = row(heCard, 8, "Last Evade Reason")
    local action = row(heCard, 9, "Action")
    Views.Events = { root = sc, update = function()
        setText(phase, HE.phase)
        setText(ended, HE.endConfirmed and "YES" or "NO")
        setText(holding, HE.holding and "YES" or "NO")
        setText(hazards, HE.meteorCount)
        setText(threat, HE.threateningCount)
        setText(dist, HE.distToEgg and string.format("%.1f", HE.distToEgg) or "—")
        setText(evade, HE.lastEvadeReason)
        setText(action, HE.action)
    end }
end)
safeBuild("Utility", function()
    local sc = createScrollPage()
    local _, afk = card(sc, 1, "ANTI-AFK")
    settingRow(afk, 1, "Anti-AFK", nil, "antiAfk", setAntiAfk)
    Views.Utility = { root = sc, update = function() end }
end)
safeBuild("Diagnostics", function()
    local sc = createScrollPage()
    local _, integ = card(sc, 1, "INTEGRATION")
    local rows = {}
    Views.Diagnostics = { root = sc, update = function()
        for _, r in pairs(rows) do r:Destroy() end
        table.clear(rows)
        local order = 5
        local keys = {}
        for k in pairs(State.diagnostics) do table.insert(keys, k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local r = Instance.new("Frame"); r.LayoutOrder = order; r.Size = UDim2.new(1, 0, 0, 20)
            r.BackgroundTransparency = 1; r.Parent = integ
            text(r, k, 11, Theme.TextMuted).Size = UDim2.new(0.55, 0, 1, 0)
            local vl = text(r, tostring(State.diagnostics[k]), 11, Theme.TextPrimary, nil, Enum.TextXAlignment.Right)
            vl.Size = UDim2.new(0.45, 0, 1, 0); vl.Position = UDim2.fromScale(0.55, 0)
            table.insert(rows, r); order += 1
        end
    end }
end)
safeBuild("Settings", function()
    local sc = createScrollPage()
    local _, perfCard = card(sc, 1, "PERFORMANCE")
    if PerformanceManager then
        local function perfToggle(order, title, getter, setter)
            local f = Instance.new("Frame"); f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, 28)
            f.BackgroundTransparency = 1; f.Parent = perfCard
            text(f, title, 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
            local sw = select(1, makeSwitch(f, getter() == true, function(v) setter(v); markConfigDirty() end))
            sw.Position = UDim2.new(1, -40, 0.5, -11)
        end
        perfToggle(1, "Boost FPS + Low Graphics", PerformanceManager.getBoostFPS, PerformanceManager.setBoostFPS)
        perfToggle(2, "Disable VFX", PerformanceManager.getDisableVFX, PerformanceManager.setDisableVFX)
        perfToggle(3, "Disable Shadows", PerformanceManager.getDisableShadows, PerformanceManager.setDisableShadows)
        perfToggle(4, "Hide Other Players", PerformanceManager.getHideOtherPlayers, PerformanceManager.setHideOtherPlayers)
        perfToggle(5, "Hide Other Chickens", PerformanceManager.getHideOtherChickens, PerformanceManager.setHideOtherChickens)
        perfToggle(6, "White Screen / AFK Saver", PerformanceManager.getWhiteScreen, PerformanceManager.setWhiteScreen)
        perfToggle(7, "Ultra Performance", PerformanceManager.getUltraPerformance, PerformanceManager.setUltraPerformance)
        local pStatus = row(perfCard, 10, "Status")
        local pVfx = row(perfCard, 11, "VFX Disabled")
        local pPl = row(perfCard, 12, "Player Parts Hidden")
        local pCh = row(perfCard, 13, "Chicken Parts Hidden")
        local pCover = row(perfCard, 14, "Screen Cover")
        local pRender = row(perfCard, 15, "Actual Rendering Disable")
        local pNote = row(perfCard, 16, "Hide Chickens")
        Views._perfUpdate = function()
            setText(pStatus, PerformanceManager.getStatus())
            local st = PerformanceManager.getStats()
            setText(pVfx, st.visualObjectsDisabled)
            setText(pPl, st.playerPartsHidden)
            setText(pCh, st.chickenPartsHidden)
            setText(pCover, st.whiteScreenIsVisualCover and "VISUAL COVER" or "OFF")
            setText(pRender, "NO")
            setText(pNote, "UNAVAILABLE — MAPPING NOT VERIFIED")
        end
    else
        setText(row(perfCard, 1, "Status"), "MISSING")
        Views._perfUpdate = function() end
    end

    local _, cfgCard = card(sc, 2, "CONFIG")
    local resetArmedUntil = 0
    if ConfigManager then
        do
            local f = Instance.new("Frame"); f.LayoutOrder = 1; f.Size = UDim2.new(1, 0, 0, 28)
            f.BackgroundTransparency = 1; f.Parent = cfgCard
            text(f, "Auto Save Config", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
            local sw = select(1, makeSwitch(f, ConfigManager.getAutoSave() == true, function(v) ConfigManager.setAutoSave(v) end))
            sw.Position = UDim2.new(1, -40, 0.5, -11)
        end
        do
            local f = Instance.new("Frame"); f.LayoutOrder = 2; f.Size = UDim2.new(1, 0, 0, 28)
            f.BackgroundTransparency = 1; f.Parent = cfgCard
            text(f, "Restore Destructive Automation", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
            local sw = select(1, makeSwitch(f, ConfigManager.getRestoreDestructiveAutomation() == true, function(v) ConfigManager.setRestoreDestructiveAutomation(v) end))
            sw.Position = UDim2.new(1, -40, 0.5, -11)
        end
        local cPersist = row(cfgCard, 3, "Persistence")
        local cStatus = row(cfgCard, 4, "Status")
        local cDirty = row(cfgCard, 5, "Dirty")
        local cErr = row(cfgCard, 6, "Last Error")
        local function cfgBtn(parent, order, label, color, fn)
            local f = Instance.new("Frame"); f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, 34)
            f.BackgroundTransparency = 1; f.Parent = parent
            local b = Instance.new("TextButton"); b.Size = UDim2.new(1, 0, 1, 0)
            b.BackgroundColor3 = color or Theme.SurfaceElevated; b.Text = label
            b.Font = Enum.Font.GothamMedium; b.TextSize = 12; b.TextColor3 = Theme.TextPrimary
            b.AutoButtonColor = false; b.Parent = f; corner(b, 6); b.MouseButton1Click:Connect(fn)
            return b
        end
        cfgBtn(cfgCard, 7, "Save Now", Theme.Primary, function() ConfigManager.saveNow() end)
        cfgBtn(cfgCard, 8, "Reload Config", Theme.SurfaceElevated, function()
            isApplyingConfig = true; State.applyingConfig = true
            ConfigManager.load()
            isApplyingConfig = false; State.applyingConfig = false
        end)
        local resetBtn = cfgBtn(cfgCard, 9, "Reset Config", Theme.Danger, function()
            local now = os.clock()
            if now > resetArmedUntil then
                resetArmedUntil = now + 4
                if resetBtn then resetBtn.Text = "CONFIRM RESET" end
                return
            end
            resetArmedUntil = 0
            if resetBtn then resetBtn.Text = "Reset Config" end
            isApplyingConfig = true; State.applyingConfig = true
            ConfigManager.resetToDefaults(true)
            isApplyingConfig = false; State.applyingConfig = false
        end)
        Views._cfgUpdate = function()
            setText(cPersist, ConfigManager.isPersistenceAvailable() and "AVAILABLE" or "UNAVAILABLE")
            setText(cStatus, ConfigManager.getStatus())
            setText(cDirty, ConfigManager.isDirty() and "YES" or "NO")
            setText(cErr, ConfigManager.getLastError())
        end
    else
        setText(row(cfgCard, 1, "Status"), "MISSING")
        Views._cfgUpdate = function() end
    end

    local _, actions = card(sc, 3, "ACTIONS")
    local function actionBtn(parent, order, label, color, fn)
        local f = Instance.new("Frame"); f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, 34)
        f.BackgroundTransparency = 1; f.Parent = parent
        local b = Instance.new("TextButton"); b.Size = UDim2.new(1, 0, 1, 0)
        b.BackgroundColor3 = color or Theme.SurfaceElevated; b.Text = label
        b.Font = Enum.Font.GothamMedium; b.TextSize = 12; b.TextColor3 = Theme.TextPrimary
        b.AutoButtonColor = false; b.Parent = f; corner(b, 6); b.MouseButton1Click:Connect(fn)
    end
    actionBtn(actions, 1, "Reset Window Position", Theme.SurfaceElevated, function() Main.Position = UDim2.fromScale(0.5, 0.5) end)
    actionBtn(actions, 2, "Close UNO HUB", Theme.Danger, shutdown)
    Views.Settings = { root = sc, update = function()
        if Views._perfUpdate then pcall(Views._perfUpdate) end
        if Views._cfgUpdate then pcall(Views._cfgUpdate) end
    end }
end)

local function showPage(id)
    local target = Views[id]
    if type(target) ~= "table" or typeof(target.root) ~= "Instance" then
        warn("[UNO UI] Missing page:", tostring(id))
        return
    end
    State.page = id
    if PageTitle then PageTitle.Text = string.upper(id) end
    if PageDesc then PageDesc.Text = pageDescs[id] or "" end
    for pid, view in pairs(Views) do
        -- Ignore helper keys like _perfUpdate / _cfgUpdate
        if type(view) == "table" and typeof(view.root) == "Instance" then
            view.root.Visible = false
        end
    end
    target.root.Visible = true
    target.root.Position = UDim2.fromOffset(0, 0)
    target.root.Size = UDim2.fromScale(1, 1)
    if target.root.Parent ~= PageHost then
        target.root.Parent = PageHost
    end
    for pid, btn in pairs(navButtons) do
        local selected = pid == id
        btn.BackgroundTransparency = selected and 0 or 1
        btn.BackgroundColor3 = selected and Theme.SurfaceElevated or Color3.new(0, 0, 0)
        local accent = btn:FindFirstChild("Accent"); if accent then accent.Visible = selected end
        local label = btn:FindFirstChild("Label")
        if label then label.TextColor3 = selected and Theme.TextPrimary or Theme.TextSecondary end
    end
    if type(target.update) == "function" then pcall(target.update) end
end

for i, p in ipairs(pages) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32); btn.BackgroundTransparency = 1; btn.Text = ""
    btn.AutoButtonColor = false; btn.LayoutOrder = i; btn.Parent = NavScroll; corner(btn, 6)
    local accent = Instance.new("Frame"); accent.Name = "Accent"; accent.Size = UDim2.fromOffset(3, 16)
    accent.Position = UDim2.fromOffset(0, 8); accent.BackgroundColor3 = Theme.Primary
    accent.BorderSizePixel = 0; accent.Visible = false; accent.Parent = btn; corner(accent, 2)
    local label = text(btn, p.icon .. "   " .. p.title, 13, Theme.TextSecondary)
    label.Name = "Label"; label.Position = UDim2.fromOffset(14, 0); label.Size = UDim2.new(1, -20, 1, 0)
    btn.MouseButton1Click:Connect(function() showPage(p.id) end)
    navButtons[p.id] = btn
end

maid:Task(function(token)
    while not token.cancelled and not State.closed do
        refreshData()
        pruneHazards()
        HE.holding = isLocalHolding()
        connDot.BackgroundColor3 = (Integration.modules.DataController or Integration.modules.Remotes) and Theme.Success or Theme.Warning
        local view = Views[State.page]
        if view and view.update then pcall(view.update) end
        task.wait(0.45)
    end
end)


-- One-time page visibility audit (UI only)
do
    local pageIds = {"Home","Auto Farm","Tower","Rebirth","Eggs","Chickens","Fuse","Incubator","Coop","Events","Utility","Diagnostics","Settings"}
    for _, pid in ipairs(pageIds) do
        local view = Views[pid]
        local root = type(view) == "table" and view.root or nil
        if typeof(root) ~= "Instance" then
            warn("[UNO UI] missing root:", pid)
        else
            local parentName = root.Parent and root.Parent.Name or "nil"
            local childCount = #root:GetChildren()
            print(string.format(
                "[UNO UI] %s root=%s parent=%s visible=%s children=%d absSize=%s",
                pid, root.Name, parentName, tostring(root.Visible), childCount, tostring(root.AbsoluteSize)
            ))
            if root.Parent ~= PageHost then
                warn("[UNO UI] reparenting", pid, "to PageHost")
                root.Parent = PageHost
            end
            root.Size = UDim2.fromScale(1, 1)
            root.Position = UDim2.fromOffset(0, 0)
        end
    end
    print("[UNO UI] PageHost absSize=", PageHost.AbsoluteSize, "ContentRoot absSize=", ContentRoot.AbsoluteSize)
end

refreshData()
refreshEconomyStatus()
-- Config load after all feature functions exist
if ConfigManager then
    isApplyingConfig = true
    State.applyingConfig = true
    pcall(function() ConfigManager.load() end)
    isApplyingConfig = false
    State.applyingConfig = false
end
showPage("Home")
log("INFO", "UNO HUB — UI page visibility fix")
print("[UNO HUB] AutoSellFeature =", AutoSellFeature and "READY" or State.diagnostics["AutoSell.Feature"])
print("[UNO HUB] AutoFuseFeature =", AutoFuseFeature and "READY" or State.diagnostics["AutoFuse.Feature"])