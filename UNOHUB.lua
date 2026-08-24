--[[
    UNO HUB
]]


local function __unoRunStage(name, fn)
    print("[UNO FINAL] START " .. name)
    local ok, result = pcall(fn)
    if not ok then
        warn("[UNO FINAL] FAILED " .. name .. ": " .. tostring(result))
        error("[UNO FINAL] " .. name .. " failed: " .. tostring(result), 0)
    end
    print("[UNO FINAL] OK " .. name)
    return result
end



local function __unoStage01()
--[[
    UNO HUB · Responsive UIScale
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
    local env = (getgenv and getgenv()) or _G
    local oldIntegration = env.UNO_HUB_PRIORITY_INTEGRATION
    if oldIntegration and type(oldIntegration.destroy) == "function" then
        pcall(oldIntegration.destroy)
    end
    local old = PlayerGui:FindFirstChild("UNO_HUB")

    if old then
        old:SetAttribute("UNO_HUB_Shutdown", true)
        old:Destroy()
        task.wait(0.05)
    end
    local cover = PlayerGui:FindFirstChild("UNO_HUB_VisualCover")
    if cover then pcall(function() cover:Destroy() end) end
end

local Theme = {
    Background = Color3.fromRGB(18, 18, 18),
    Surface = Color3.fromRGB(22, 22, 22),
    SurfaceElevated = Color3.fromRGB(30, 30, 30),
    Sidebar = Color3.fromRGB(23, 23, 23),
    Border = Color3.fromRGB(53, 53, 53),
    TextPrimary = Color3.fromRGB(242, 242, 242),
    TextSecondary = Color3.fromRGB(200, 200, 205),
    TextMuted = Color3.fromRGB(130, 130, 140),
    Primary = Color3.fromRGB(238, 238, 238),
    Success = Color3.fromRGB(93, 205, 135),
    Warning = Color3.fromRGB(230, 185, 70),
    Danger = Color3.fromRGB(225, 80, 80),
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
        coordinatorPauseReasons = {},
    },
    hotEgg = {
        enabled = false, phase = "DISABLED", generation = 0, movementMode = "Tween",
        meteorAvoidance = true, safetyMargin = 6, exitPitAfter = true,
        eventActive = false, holding = false, timeRemaining = nil, action = "—",
        meteorCount = 0, nearestImpact = nil, rewardConfirmed = false, hazards = {},
        endConfirmed = false, exitAttempts = 0,
        coordinatorPauseReasons = {},
        -- meteor avoidance stability (movement layer only)
        evadeTarget = nil, evadeTargetTime = 0, lastEvadeDecision = 0,
        lastEvadeReason = "—", threateningCount = 0, distToEgg = nil,
    },
    economy = {
        buyStatus = "IDLE", upgradeStatus = "IDLE", expandStatus = "IDLE", recyclerStatus = "IDLE",
        generatorsOwned = 0, generatorsSlots = 0, nextBuySlot = nil, nextBuyCost = nil, recyclerLevel = 0,
    },
    movementOwner = "NONE",
    toggles = {
        autoFarmRebirth = false, autoKoDismiss = true, autoHatch = false, autoCollectEgg = false,
        autoIncubatorClaim = false, autoSell = false, autoFuse = false,
        autoUFOAscension = false,
        autoBuyGenerator = false, autoUpgradeGenerator = false, autoExpandCoop = false, autoUpgradeRecycler = false, autoUpgradeIncubator = false,
        antiAfk = true, autoRebirth = false, autoHotEgg = false, autoArena = false, autoEventCapsule = false, autoKraken = false, showFloatingButton = true, reducedMotion = false,
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

local ConfigManager = nil
local PerformanceManager = nil
local visualCoverGui = nil
local isApplyingConfig = false
local function markConfigDirty()
    if isApplyingConfig then return end
    if ConfigManager and type(ConfigManager.markDirty) == "function" then
        pcall(function() ConfigManager.markDirty() end)
    end
end

-- PERFORMANCE MANAGER
-- standalone integration-ready code
--
-- Conservative client-side performance controls. This module never destroys,
-- renames, reparents, or clears Workspace objects.

local VISUAL_ENABLED_CLASSES = {
    ParticleEmitter = true,
    Trail = true,
    Beam = true,
    Smoke = true,
    Fire = true,
    Sparkles = true,
    Highlight = true,
    PointLight = true,
    SpotLight = true,
    SurfaceLight = true,
    BloomEffect = true,
    BlurEffect = true,
    ColorCorrectionEffect = true,
    DepthOfFieldEffect = true,
    SunRaysEffect = true,
    Atmosphere = true,
    Clouds = true,
}

local DEFAULT_PROTECTED_NAME = {
    HotEgg = true,
    NestEgg = true,
    PitZone = true,
    Meteor = true,
    Hazard = true,
    Carrier = true,
}

local function spawnThread(fn)
    if task and type(task.spawn) == "function" then
        return task.spawn(fn)
    end
    local co = coroutine.create(fn)
    coroutine.resume(co)
    return co
end

local function safeConnect(signal, callback)
    if signal and type(signal.Connect) == "function" then
        local ok, connection = pcall(function()
            return signal:Connect(callback)
        end)
        if ok then
            return connection
        end
    end
    return nil
end

local function safeGetDescendants(instance)
    if not instance or type(instance.GetDescendants) ~= "function" then
        return {}
    end
    local ok, descendants = pcall(function()
        return instance:GetDescendants()
    end)
    return ok and descendants or {}
end

local function safeClass(instance)
    local ok, className = pcall(function()
        return instance.ClassName
    end)
    return ok and className or nil
end

local function safeName(instance)
    local ok, name = pcall(function()
        return instance.Name
    end)
    return ok and name or ""
end

local function createPerformanceManager(deps)
    deps = deps or {}
    local services = deps.services or deps
    local Players = services.Players
    local Lighting = services.Lighting
    local localPlayer = deps.localPlayer
    if not localPlayer and Players then
        local ok, value = pcall(function()
            return Players.LocalPlayer
        end)
        if ok then localPlayer = value end
    end

    local config = {
        boostFPS = false,
        disableVFX = false,
        disableShadows = false,
        hideOtherPlayers = false,
        hideOtherChickens = false,
        whiteScreen = false,
        ultraPerformance = false,
    }

    local state = {
        destroyed = false,
        status = "DISABLED",
        whiteScreenIsCover = false,
        boostSnapshot = nil,
        ultraSnapshot = nil,
    }

    local stats = {
        visualObjectsDisabled = 0,
        visualObjectsRestored = 0,
        playerPartsHidden = 0,
        chickenPartsHidden = 0,
        protectedObjectsSkipped = 0,
        dynamicObjectsHandled = 0,
        currentMode = "DISABLED",
    }

    local originals = setmetatable({}, { __mode = "k" })
    local hiddenParts = setmetatable({}, { __mode = "k" })
    local connections = {}
    local rootConnections = setmetatable({}, { __mode = "k" })

    local function log(message, payload)
        if type(deps.log) == "function" then
            pcall(deps.log, message, payload)
        end
    end

    local function setStatus(status, payload)
        state.status = status
        stats.currentMode = status
        log(status, payload)
    end

    local function isProtected(instance)
        if type(deps.isProtectedInstance) == "function" then
            local ok, result = pcall(deps.isProtectedInstance, instance)
            if ok and result == true then
                return true
            end
        end
        local name = safeName(instance)
        if DEFAULT_PROTECTED_NAME[name] then
            return true
        end
        local lowered = string.lower(name)
        for token in pairs(DEFAULT_PROTECTED_NAME) do
            if string.find(lowered, string.lower(token), 1, true) then
                return true
            end
        end
        return false
    end

    local function remember(instance, property, value)
        originals[instance] = originals[instance] or {}
        if originals[instance][property] == nil then
            originals[instance][property] = value
        end
    end

    local function readProperty(instance, property)
        local ok, value = pcall(function()
            return instance[property]
        end)
        if ok then return true, value end
        return false, nil
    end

    local function writeProperty(instance, property, value)
        return pcall(function()
            instance[property] = value
        end)
    end

    local function disableVisual(instance)
        if not instance or isProtected(instance) then
            if instance and isProtected(instance) then
                stats.protectedObjectsSkipped = stats.protectedObjectsSkipped + 1
            end
            return
        end
        local className = safeClass(instance)
        if not VISUAL_ENABLED_CLASSES[className] then
            return
        end
        local readable, enabled = readProperty(instance, "Enabled")
        if not readable or enabled == nil then
            return
        end
        remember(instance, "Enabled", enabled)
        if enabled == true then
            local ok = writeProperty(instance, "Enabled", false)
            if ok then
                stats.visualObjectsDisabled = stats.visualObjectsDisabled + 1
            end
        end
    end

    local function restoreVisual(instance)
        local saved = originals[instance]
        if not saved or saved.Enabled == nil then
            return
        end
        if writeProperty(instance, "Enabled", saved.Enabled) then
            stats.visualObjectsRestored = stats.visualObjectsRestored + 1
        end
        saved.Enabled = nil
    end

    local function processVisual(instance)
        if config.disableVFX or config.boostFPS then
            disableVisual(instance)
        else
            restoreVisual(instance)
        end
    end

    local function isLocalCharacter(model)
        if type(deps.isLocalPlayerCharacter) == "function" then
            local ok, result = pcall(deps.isLocalPlayerCharacter, model, localPlayer)
            if ok then return result == true end
        end
        return localPlayer and localPlayer.Character == model
    end

    local function isOtherPlayerCharacter(model, player)
        if isLocalCharacter(model) then
            return false
        end
        if type(deps.isOtherPlayerCharacter) == "function" then
            local ok, result = pcall(deps.isOtherPlayerCharacter, model, player)
            return ok and result == true
        end
        return player ~= nil and player ~= localPlayer
    end

    local function isOtherChickenModel(model)
        if type(deps.isOtherChickenModel) ~= "function" then
            return false
        end
        local ok, result = pcall(deps.isOtherChickenModel, model, localPlayer)
        return ok and result == true
    end

    local function setModelHidden(model, hidden, category)
        if not model or isProtected(model) then
            return
        end
        local descendants = safeGetDescendants(model)
        for _, instance in ipairs(descendants) do
            local className = safeClass(instance)
            if className == "BasePart" or className == "MeshPart" or className == "Part" or className == "UnionOperation" then
                local readable, current = readProperty(instance, "LocalTransparencyModifier")
                if readable then
                    if hidden then
                        remember(instance, "LocalTransparencyModifier", current)
                        if writeProperty(instance, "LocalTransparencyModifier", 1) then
                            hiddenParts[instance] = true
                            if category == "player" then
                                stats.playerPartsHidden = stats.playerPartsHidden + 1
                            else
                                stats.chickenPartsHidden = stats.chickenPartsHidden + 1
                            end
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
            if isOtherPlayerCharacter(model, player) then
                setModelHidden(model, true, "player")
                return
            end
        end
        if not config.hideOtherPlayers and not config.ultraPerformance and player ~= localPlayer then
            setModelHidden(model, false, "player")
        end
    end

    local function processChicken(model)
        local shouldHide = config.hideOtherChickens or config.ultraPerformance
        if shouldHide and isOtherChickenModel(model) then
            setModelHidden(model, true, "chicken")
        elseif not shouldHide and isOtherChickenModel(model) then
            setModelHidden(model, false, "chicken")
        end
    end

    local function processRoot(root)
        if not root or isProtected(root) then
            return
        end
        disableVisual(root)
        for _, instance in ipairs(safeGetDescendants(root)) do
            processVisual(instance)
        end
        stats.dynamicObjectsHandled = stats.dynamicObjectsHandled + 1
    end

    local function connectRoot(root)
        if rootConnections[root] then return end
        if root and root.DescendantAdded then
            rootConnections[root] = safeConnect(root.DescendantAdded, function(instance)
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
            connectRoot(root)
            processRoot(root)
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
            if player.Character then
                processCharacter(player.Character, player)
            end
        end
    end

    local function applyModels()
        applyVisuals()
        applyPlayers()
        if type(deps.getChickenModels) == "function" then
            local ok, models = pcall(deps.getChickenModels)
            if ok and type(models) == "table" then
                for _, model in ipairs(models) do processChicken(model) end
            end
        end
    end

    local function updateModeStatus()
        if config.ultraPerformance then
            setStatus("ULTRA PERFORMANCE")
        elseif config.boostFPS then
            setStatus("BOOST FPS + LOW GRAPHICS")
        elseif config.disableVFX or config.disableShadows or config.hideOtherPlayers or config.hideOtherChickens then
            setStatus("CUSTOM PERFORMANCE")
        else
            setStatus("DISABLED")
        end
    end

    local function apply()
        if state.destroyed then return end
        applyModels()
        if config.whiteScreen then
            if type(deps.setVisualCover) == "function" then
                pcall(deps.setVisualCover, true)
            end
            state.whiteScreenIsCover = true
        else
            if type(deps.setVisualCover) == "function" then
                pcall(deps.setVisualCover, false)
            end
            state.whiteScreenIsCover = false
        end
        updateModeStatus()
    end

    local function setFlag(key, enabled)
        if state.destroyed then return false end
        config[key] = enabled == true
        apply()
        return true
    end

    local api = {}

    function api.setBoostFPS(enabled)
        enabled = enabled == true
        if enabled and not state.boostSnapshot then
            state.boostSnapshot = {
                disableVFX = config.disableVFX,
                disableShadows = config.disableShadows,
            }
        elseif not enabled and state.boostSnapshot then
            config.disableVFX = state.boostSnapshot.disableVFX
            config.disableShadows = state.boostSnapshot.disableShadows
            state.boostSnapshot = nil
        end
        config.boostFPS = enabled
        if enabled then
            config.disableVFX = true
            config.disableShadows = true
        end
        apply()
        return true
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

    function api.setWhiteScreen(v)
        config.whiteScreen = v == true
        apply()
        return true
    end
    function api.getWhiteScreen() return config.whiteScreen end

    function api.setUltraPerformance(enabled)
        enabled = enabled == true
        if enabled and not state.ultraSnapshot then
            state.ultraSnapshot = {
                boostFPS = config.boostFPS,
                disableVFX = config.disableVFX,
                disableShadows = config.disableShadows,
                hideOtherPlayers = config.hideOtherPlayers,
                hideOtherChickens = config.hideOtherChickens,
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
            config.boostFPS = true
            config.disableVFX = true
            config.disableShadows = true
            config.hideOtherPlayers = true
            config.hideOtherChickens = true
        end
        apply()
        return true
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

    function api.refresh()
        apply()
    end

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
        table.insert(connections, safeConnect(Players.PlayerAdded, function(player)
            if player.Character then processCharacter(player.Character, player) end
            table.insert(connections, safeConnect(player.CharacterAdded, function(character)
                processCharacter(character, player)
            end))
        end))
        table.insert(connections, safeConnect(Players.PlayerRemoving, function(player)
            if player.Character then processCharacter(player.Character, player) end
        end))
        local ok, players = pcall(function() return Players:GetPlayers() end)
        if ok then
            for _, player in ipairs(players) do
                table.insert(connections, safeConnect(player.CharacterAdded, function(character)
                    processCharacter(character, player)
                end))
            end
        end
    end

    if services.Workspace and services.Workspace.DescendantAdded then
        table.insert(connections, safeConnect(services.Workspace.DescendantAdded, function(instance)
            -- Workspace additions are classified, never blindly destroyed.
            if isProtected(instance) then return end
            processVisual(instance)
            processChicken(instance)
        end))
    end

    return api
end

-- createPerformanceManager defined above

-- CONFIG MANAGER
-- standalone integration-ready code
--
-- Configuration is data only. This module never executes config text.

local CONFIG_VERSION = 1
local CONFIG_FOLDER = "UNOHUB"
local DEFAULT_CONFIG_NAME = "default"

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[clone(key, seen)] = clone(item, seen)
    end
    return result
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return false, nil end
    return pcall(fn, ...)
end

local function delay(seconds, callback, deps)
    if type(deps.delay) == "function" then
        return deps.delay(seconds, callback)
    end
    if task and type(task.delay) == "function" then
        return task.delay(seconds, callback)
    end
    return nil
end

local function getGlobal(name)
    local env = (getgenv and getgenv()) or nil
    if type(env) == "table" and type(env[name]) == "function" then
        return env[name]
    end
    if type(_G) == "table" and type(_G[name]) == "function" then
        return _G[name]
    end
    return nil
end

local function chooseFunction(container, name)
    if type(container) == "table" and type(container[name]) == "function" then
        return container[name]
    end
    return getGlobal(name)
end

local function createConfigManager(deps)
    deps = deps or {}
    local fs = deps.fs or {}
    local httpService = deps.HttpService or deps.httpService
    local encode = deps.jsonEncode
    local decode = deps.jsonDecode

    if type(encode) ~= "function" and httpService then
        encode = function(value)
            return httpService:JSONEncode(value)
        end
    end
    if type(decode) ~= "function" and httpService then
        decode = function(text)
            return httpService:JSONDecode(text)
        end
    end

    local writefile = chooseFunction(fs, "writefile")
    local readfile = chooseFunction(fs, "readfile")
    local isfile = chooseFunction(fs, "isfile")
    local makefolder = chooseFunction(fs, "makefolder")

    local persistenceAvailable = type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
        and type(makefolder) == "function"
        and type(encode) == "function"
        and type(decode) == "function"

    local config = {
        autoSave = true,
        restoreDestructiveAutomation = false,
        configName = DEFAULT_CONFIG_NAME,
    }

    local function sanitizeConfigName(value)
        value = tostring(value or "")
        value = string.gsub(value, "^%s+", "")
        value = string.gsub(value, "%s+$", "")
        value = string.gsub(value, "[^%w%-%_]", "_")
        if value == "" then value = DEFAULT_CONFIG_NAME end
        return string.sub(value, 1, 48)
    end

    local function configPath()
        return CONFIG_FOLDER .. "/" .. sanitizeConfigName(config.configName) .. ".json"
    end
    for key, value in pairs(deps.defaults or {}) do
        config[key] = clone(value)
    end
    local startupDefaults = clone(config)

    local sections = {}
    local state = {
        destroyed = false,
        dirty = false,
        savePending = false,
        timerGeneration = 0,
        status = persistenceAvailable and "READY" or "PERSISTENCE UNAVAILABLE",
        lastError = nil,
        lastLoadedVersion = nil,
        lastSavedAt = nil,
    }

    local function log(message, payload)
        if type(deps.log) == "function" then
            pcall(deps.log, message, payload)
        end
    end

    local function setStatus(status, errorValue)
        state.status = status
        state.lastError = errorValue
        log(status, errorValue)
    end

    local function ensureFolder()
        local ok = pcall(makefolder, CONFIG_FOLDER)
        -- Existing-folder errors are harmless; writing the file is the
        -- authoritative capability test.
        return ok
    end

    local function currentDefaults()
        local result = clone(startupDefaults)
        result.version = CONFIG_VERSION
        for name, section in pairs(sections) do
            result[name] = clone(section.defaults or {})
        end
        return result
    end

    local function sanitizeWithDefaults(value, defaults)
        if type(defaults) == "boolean" then
            return type(value) == "boolean" and value or defaults
        end
        if type(defaults) == "number" then
            return type(value) == "number" and value or defaults
        end
        if type(defaults) == "string" then
            return type(value) == "string" and value or defaults
        end
        if type(defaults) ~= "table" then
            return clone(value)
        end
        if type(value) ~= "table" then
            return clone(defaults)
        end
        local result = {}
        for key, defaultValue in pairs(defaults) do
            if value[key] ~= nil then
                result[key] = sanitizeWithDefaults(value[key], defaultValue)
            else
                result[key] = clone(defaultValue)
            end
        end
        return result
    end

    local function validateSection(name, value, section)
        local normalized = sanitizeWithDefaults(value, section.defaults or {})
        if type(section.validate) == "function" then
            local ok, result = pcall(section.validate, normalized, name)
            if not ok or result == false then
                return clone(section.defaults or {}), false
            end
            if type(result) == "table" then
                normalized = result
            end
        end
        return normalized, true
    end

    local function applyDocument(document)
        document = type(document) == "table" and document or {}
        local restoreDestructive = document.restoreDestructiveAutomation == true
        config.restoreDestructiveAutomation = restoreDestructive
        if type(document.autoSave) == "boolean" then
            config.autoSave = document.autoSave
        end
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
                pcall(section.loader, clone(normalized), {
                    name = name,
                    restoredDestructiveAutomation = restoreDestructive,
                    fromConfig = true,
                })
            end
        end
    end

    local function migrate(document)
        local version = tonumber(document.version) or 0
        if version > CONFIG_VERSION then
            return nil, "UNSUPPORTED CONFIG VERSION"
        end
        if version < CONFIG_VERSION and type(deps.migrate) == "function" then
            local ok, migrated = pcall(deps.migrate, clone(document), version, CONFIG_VERSION)
            if not ok or type(migrated) ~= "table" then
                return nil, "CONFIG MIGRATION FAILED"
            end
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
                if ok and type(value) == "table" then
                    document[name] = clone(value)
                else
                    document[name] = clone(section.defaults or {})
                end
            else
                document[name] = clone(section.defaults or {})
            end
        end
        return document
    end

    local function saveNow()
        if state.destroyed then return false, "DESTROYED" end
        if not persistenceAvailable then
            setStatus("PERSISTENCE UNAVAILABLE")
            return false, "PERSISTENCE UNAVAILABLE"
        end
        local document = snapshot()
        local okEncode, text = pcall(encode, document)
        if not okEncode or type(text) ~= "string" then
            setStatus("SAVE ERROR", "JSON ENCODE FAILED")
            return false, "JSON ENCODE FAILED"
        end
        local okFolder = ensureFolder()
        if not okFolder then
            -- Some runtimes throw when a folder already exists. Continue to
            -- the write attempt because writefile is the decisive operation.
            log("CONFIG FOLDER CHECK", "CONTINUING")
        end
        local okWrite, writeError = pcall(writefile, configPath(), text)
        if not okWrite then
            setStatus("SAVE ERROR", writeError)
            return false, writeError
        end
        state.dirty = false
        state.savePending = false
        state.lastSavedAt = os.time()
        setStatus("SAVED")
        return true
    end

    local function scheduleSave()
        if state.savePending or not config.autoSave or state.destroyed then return end
        state.savePending = true
        state.timerGeneration = state.timerGeneration + 1
        local generation = state.timerGeneration
        delay(0.75, function()
            if state.destroyed or generation ~= state.timerGeneration then return end
            state.savePending = false
            if state.dirty then saveNow() end
        end, deps)
    end

    local api = {}

    function api.isPersistenceAvailable()
        return persistenceAvailable
    end

    function api.registerSection(name, serializer, loader, options)
        if state.destroyed or type(name) ~= "string" or name == "" then
            return false, "INVALID SECTION"
        end
        options = options or {}
        sections[name] = {
            serializer = serializer,
            loader = loader,
            validate = options.validate,
            defaults = clone(options.defaults or {}),
        }
        return true
    end

    function api.load()
        if state.destroyed then return false, "DESTROYED" end
        if not persistenceAvailable then
            applyDocument(currentDefaults())
            setStatus("PERSISTENCE UNAVAILABLE")
            return false, "PERSISTENCE UNAVAILABLE"
        end
        local existsOk, exists = pcall(isfile, configPath())
        if not existsOk or exists ~= true then
            applyDocument(currentDefaults())
            setStatus("NO CONFIG")
            return false, "NO CONFIG"
        end
        local okRead, text = pcall(readfile, configPath())
        if not okRead or type(text) ~= "string" then
            applyDocument(currentDefaults())
            setStatus("LOAD ERROR", text)
            return false, "LOAD ERROR"
        end
        local okDecode, document = pcall(decode, text)
        if not okDecode or type(document) ~= "table" then
            applyDocument(currentDefaults())
            setStatus("INVALID CONFIG", "JSON DECODE FAILED")
            return false, "INVALID CONFIG"
        end
        local migrated, migrationError = migrate(document)
        if not migrated then
            applyDocument(currentDefaults())
            setStatus("INVALID CONFIG", migrationError)
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
        state.dirty = true
        scheduleSave()
        return true
    end

    function api.markDirty()
        return api.save()
    end

    function api.saveNow()
        return saveNow()
    end

    function api.setAutoSave(enabled)
        config.autoSave = enabled == true
        if config.autoSave and state.dirty then scheduleSave() end
        return true
    end

    function api.getAutoSave()
        return config.autoSave
    end

    function api.setConfigName(value)
        config.configName = sanitizeConfigName(value)
        return config.configName
    end

    function api.getConfigName()
        return config.configName
    end

    function api.getConfigPath()
        return configPath()
    end

    function api.setRestoreDestructiveAutomation(enabled)
        config.restoreDestructiveAutomation = enabled == true
        api.markDirty()
        return true
    end

    function api.getRestoreDestructiveAutomation()
        return config.restoreDestructiveAutomation
    end

    function api.getStatus()
        return state.status
    end

    function api.getLastError()
        return state.lastError
    end

    function api.isDirty()
        return state.dirty
    end

    function api.resetToDefaults(confirmed)
        if not confirmed then
            return false, "CONFIRMATION REQUIRED"
        end
        applyDocument(currentDefaults())
        api.markDirty()
        setStatus("RESET")
        return true
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

-- createConfigManager defined above



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
local function getTowerStatus()
    return tostring(State.tower.status)
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
        task.wait(seconds)
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
        else
        task.wait(seconds)
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
        matchMode = nil,
        selectedRarities = {},
        protectFavorites = true,
        protectMutated = true,
        abilityWhitelist = fuseCopyMap(DEFAULT_FUSE_ABILITIES),
        keepCopies = 0,
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
        local keep = math.max(0, tonumber(config.keepCopies) or 0)
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
        local keep = math.max(0, tonumber(config.keepCopies) or 0)
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
            if config.matchMode ~= "Same Chicken" and config.matchMode ~= "Same Rarity" then
                stats.reservedKeepCopies = 0
                setStatus("NO MATCH MODE")
                fuseWaitFor(0.9, deps)
            elseif selectedRarityCount() == 0 then
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
        if mode == nil then
            config.matchMode = nil
            invalidate()
            return true
        end
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
        if next(HE.coordinatorPauseReasons) ~= nil then
            heSetPhase("PAUSED_FOR_EVENT", "Coordinator")
            task.wait(0.35)
            continue
        end
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
local function isLocalPlayerInsidePit()
    local hrp = getHRP()
    return hrp ~= nil and isInsidePit(hrp.Position)
end

local function requestUFOTowerExit()
    if not isTowerActive() then return true end
    tryInvoke("TowerSurrender")
    local deadline = os.clock() + 12
    while os.clock() < deadline do
        if not isTowerActive() then return true end
        task.wait(0.25)
    end
    return not isTowerActive()
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
        -- These event collectors only need PLAYER movement priority.
        -- They must not pause pet-side NORMAL_FARM.
        AFR.coordinatorPauseReasons["COORDINATOR_OWNER:HOT_EGG"] = nil
        AFR.coordinatorPauseReasons["COORDINATOR_OWNER:EVENT_CAPSULE"] = nil
        AFR.coordinatorPauseReasons["COORDINATOR_OWNER:KRAKEN_EGG"] = nil

        if next(AFR.coordinatorPauseReasons) ~= nil then
            afrSetPhase("PAUSED_FOR_EVENT", "Coordinator")
            task.wait(0.35)
            continue
        elseif AFR.phase == "PAUSED_FOR_EVENT" then
            afrSetPhase("CHECKING_REBIRTH")
        end
        -- World events may move the player, but pet-side farm/tower logic
        -- continues. Only the actual Rebirth action is deferred while in Pit.
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

            -- Rebirth cannot complete while the player is inside the event Pit.
            -- Do NOT stop pet farming; just defer the rebirth transaction until
            -- Hot Egg / Event Capsule returns the player outside.
            if isLocalPlayerInsidePit() then
                afrSetPhase("WAITING_EXIT_PIT_FOR_REBIRTH")
                task.wait(0.35)
                continue
            end

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
                    if isContinueOpen() or getTowerStatus() == "RUN ENDED" then break end
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
                    if State.tower.runActive or getTowerStatus() == "RUNNING" then break end
                    task.wait(0.25)
                end
            else afrSetPhase("ERROR"); task.wait(3) end
        else task.wait(0.4) end
    end
    if not AFR.enabled then afrSetPhase("DISABLED") end
end
local function setAutoFarmRebirth(on)
    on = on == true
    State.toggles.autoFarmRebirth = on
    AFR.enabled = on
    afrCancel()
    if on then
        AFR.generation += 1
        afrSetPhase("CHECKING_REBIRTH")
        log("INFO", "Auto Farm Rebirth enabled")
        maid:Task(afrTick)
    else
        afrSetPhase("DISABLED")
        log("INFO", "Auto Farm Rebirth disabled")
    end
end


local autoRebirthGeneration = 0
local function setAutoRebirth(on)
    State.toggles.autoRebirth = on == true
    autoRebirthGeneration += 1
    local myGeneration = autoRebirthGeneration
    if not State.toggles.autoRebirth then return end

    maid:Task(function(token)
        while not token.cancelled
            and not State.closed
            and State.toggles.autoRebirth
            and myGeneration == autoRebirthGeneration do

            -- Standalone Auto Rebirth is intentionally simple:
            -- when Rebirth is READY, invoke Rebirth directly.
            -- It NEVER starts Tower, NEVER surrenders Tower,
            -- and NEVER touches the Continue prompt.
            --
            -- If Auto Farm Rebirth is enabled, that feature owns
            -- the complete Tower/Rebirth lifecycle instead.
            if not AFR.enabled and next(AFR.coordinatorPauseReasons) == nil then
                refreshData()

                local before, _, ready = getRebirthInfo()
                if ready then
                    if isLocalPlayerInsidePit() then
                        task.wait(0.35)
                        continue
                    end

                    before = tonumber(before) or 0
                    local ok = tryInvoke("Rebirth")
                    if ok then
                        local deadline = os.clock() + 7
                        while os.clock() < deadline
                            and not token.cancelled
                            and State.toggles.autoRebirth
                            and myGeneration == autoRebirthGeneration do

                            refreshData()
                            local after = select(1, getRebirthInfo())
                            after = tonumber(after) or 0

                            if after > before then
                                State.successfulRebirths += 1
                                break
                            end

                            task.wait(0.35)
                        end
                    end
                end
            end

            task.wait(0.8)
        end
    end)
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

--------------------------------------------------------------------
-- Performance Manager + Config Manager (SOURCE B / SOURCE C)
--------------------------------------------------------------------
do
    local function setVisualCover(enabled)
        if enabled then
            if visualCoverGui and visualCoverGui.Parent then
                visualCoverGui.Enabled = true
                return
            end
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
            if visualCoverGui then
                pcall(function() visualCoverGui:Destroy() end)
                visualCoverGui = nil
            end
        end
    end

    local function isProtectedInstance(inst)
        if not inst then return false end
        local node = inst
        for _ = 1, 14 do
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
        local name = ""
        pcall(function() name = inst.Name end)
        local lower = string.lower(tostring(name))
        for _, tok in ipairs({"hotegg", "nestegg", "meteor", "hazard", "pitzone", "carrier", "uno_hub"}) do
            if string.find(lower, tok, 1, true) then return true end
        end
        local tagged = false
        pcall(function()
            if CollectionService:HasTag(inst, "NestEgg") then tagged = true end
        end)
        return tagged
    end

    local function getCosmeticRoots()
        local roots = {}
        if Lighting then table.insert(roots, Lighting) end
        for _, name in ipairs({"Effects", "VFX", "Visuals", "Fx", "FX", "Particles"}) do
            local a = Workspace:FindFirstChild(name)
            if a then table.insert(roots, a) end
            local b = ReplicatedStorage:FindFirstChild(name)
            if b then table.insert(roots, b) end
        end
        return roots
    end

    -- Hide Other Chickens: not verified — always false
    local function isOtherChickenModel()
        return false
    end

    PerformanceManager = createPerformanceManager({
        services = { Players = Players, Lighting = Lighting, Workspace = Workspace },
        localPlayer = LocalPlayer,
        getCosmeticRoots = getCosmeticRoots,
        isProtectedInstance = isProtectedInstance,
        isOtherChickenModel = isOtherChickenModel,
        setVisualCover = setVisualCover,
        log = function(msg, payload)
            log("PERF", tostring(msg) .. (payload ~= nil and (" " .. tostring(payload)) or ""))
        end,
    })
    State.diagnostics["PerformanceManager"] = PerformanceManager and "READY" or "MISSING"

    ConfigManager = createConfigManager({
        HttpService = HttpService,
        log = function(msg, payload)
            log("CFG", tostring(msg) .. (payload ~= nil and (" " .. tostring(payload)) or ""))
        end,
    })
    State.diagnostics["ConfigManager"] = ConfigManager and (ConfigManager.isPersistenceAvailable() and "READY" or "NO FS") or "MISSING"

    if ConfigManager then
        ConfigManager.registerSection("automation", function()
            return {
                autoFarmRebirth = State.toggles.autoFarmRebirth == true,
                autoRebirth = State.toggles.autoRebirth == true,
                autoKoDismiss = State.toggles.autoKoDismiss == true,
                autoCollectEgg = State.toggles.autoCollectEgg == true,
                autoHotEgg = State.toggles.autoHotEgg == true,
                autoUFOAscension = State.toggles.autoUFOAscension == true,
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
            -- Preferences + optional worker start (allowed; user can toggle after)
            applyToggle("autoKoDismiss")
            applyToggle("autoFarmRebirth", setAutoFarmRebirth)
            applyToggle("autoRebirth", setAutoRebirth)
            if AutoCollectEggFeature then applyToggle("autoCollectEgg", function(v) AutoCollectEggFeature.setAutoCollectEggs(v) end) end
            applyToggle("autoHotEgg", setAutoHotEgg)
            applyToggle("autoUFOAscension")
            if HatchFeature then applyToggle("autoHatch", function(v) HatchFeature.setAutoHatch(v) end) end
            if IncubatorClaimFeature then applyToggle("autoIncubatorClaim", function(v) IncubatorClaimFeature.setAutoIncubatorClaim(v) end) end
            if AutoUpgradeIncubatorFeature then applyToggle("autoUpgradeIncubator", function(v) AutoUpgradeIncubatorFeature.setAutoUpgradeIncubator(v) end) end
            applyToggle("autoBuyGenerator", setAutoBuyGenerator)
            applyToggle("autoUpgradeGenerator", setAutoUpgradeGenerator)
            applyToggle("autoExpandCoop", setAutoExpandCoop)
            applyToggle("autoUpgradeRecycler", setAutoUpgradeRecycler)
        end, { defaults = {} })

        ConfigManager.registerSection("hotEgg", function()
            return {
                meteorAvoidance = HE.meteorAvoidance == true,
                movementMode = HE.movementMode or "Tween",
                exitPitAfter = HE.exitPitAfter == true,
            }
        end, function(data)
            if type(data) ~= "table" then return end
            if data.meteorAvoidance ~= nil then HE.meteorAvoidance = data.meteorAvoidance == true end
            if type(data.movementMode) == "string" then HE.movementMode = data.movementMode end
            if data.exitPitAfter ~= nil then HE.exitPitAfter = data.exitPitAfter == true end
        end, { defaults = { meteorAvoidance = true, movementMode = "Tween", exitPitAfter = true } })

        ConfigManager.registerSection("hatch", function()
            local selected = {}
            if HatchFeature and type(HatchFeature.getSelectedEggs) == "function" then
                local ok, list = pcall(HatchFeature.getSelectedEggs)
                if ok and type(list) == "table" then selected = list end
            end
            return { selectedEggs = selected }
        end, function(data)
            if type(data) ~= "table" or not HatchFeature then return end
            if type(HatchFeature.clearEggSelection) == "function" then pcall(HatchFeature.clearEggSelection) end
            if type(data.selectedEggs) == "table" and type(HatchFeature.setEggSelected) == "function" then
                for _, id in ipairs(data.selectedEggs) do
                    pcall(HatchFeature.setEggSelected, id, true)
                end
            end
        end, { defaults = { selectedEggs = {} } })

        ConfigManager.registerSection("sell", function()
            if not AutoSellFeature then return { enabled = false, dryRun = true } end
            return {
                enabled = (AutoSellFeature.isEnabled and AutoSellFeature.isEnabled()) or false,
                dryRun = (AutoSellFeature.getDryRun and AutoSellFeature.getDryRun()) ~= false,
                rarities = (AutoSellFeature.getSelectedRarities and AutoSellFeature.getSelectedRarities()) or {},
                protectFavorites = (AutoSellFeature.getProtectFavorites and AutoSellFeature.getProtectFavorites()) ~= false,
                protectMutated = (AutoSellFeature.getProtectMutated and AutoSellFeature.getProtectMutated()) ~= false,
            }
        end, function(data)
            if type(data) ~= "table" or not AutoSellFeature then return end
            if type(data.rarities) == "table" then
                if AutoSellFeature.clearRaritySelection then pcall(AutoSellFeature.clearRaritySelection) end
                for _, r in ipairs(data.rarities) do
                    if AutoSellFeature.setRaritySelected then pcall(AutoSellFeature.setRaritySelected, r, true) end
                end
            end
            if data.protectFavorites ~= nil and AutoSellFeature.setProtectFavorites then
                pcall(AutoSellFeature.setProtectFavorites, data.protectFavorites == true)
            end
            if data.protectMutated ~= nil and AutoSellFeature.setProtectMutated then
                pcall(AutoSellFeature.setProtectMutated, data.protectMutated == true)
            end
            -- Dry run / enabled: ConfigManager.applyDocument already forces safe values when restoreDestructive=false
            if data.dryRun ~= nil and AutoSellFeature.setDryRun then pcall(AutoSellFeature.setDryRun, data.dryRun == true) end
            if data.enabled ~= nil and AutoSellFeature.setAutoSell then pcall(AutoSellFeature.setAutoSell, data.enabled == true) end
        end, { defaults = { enabled = false, dryRun = true, rarities = {}, protectFavorites = true, protectMutated = true } })

        ConfigManager.registerSection("fuse", function()
            if not AutoFuseFeature then return { enabled = false, dryRun = true, keepCopies = 0 } end
            return {
                enabled = (AutoFuseFeature.isEnabled and AutoFuseFeature.isEnabled()) or false,
                dryRun = (AutoFuseFeature.getDryRun and AutoFuseFeature.getDryRun()) ~= false,
                matchMode = (AutoFuseFeature.getMatchMode and AutoFuseFeature.getMatchMode()) or nil,
                rarities = (AutoFuseFeature.getSelectedRarities and AutoFuseFeature.getSelectedRarities()) or {},
                keepCopies = (AutoFuseFeature.getKeepCopies and AutoFuseFeature.getKeepCopies()) or 0,
                protectFavorites = (AutoFuseFeature.getProtectFavorites and AutoFuseFeature.getProtectFavorites()) ~= false,
                protectMutated = (AutoFuseFeature.getProtectMutated and AutoFuseFeature.getProtectMutated()) ~= false,
            }
        end, function(data)
            if type(data) ~= "table" or not AutoFuseFeature then return end
            if AutoFuseFeature.setMatchMode then
                if data.matchMode == "Same Chicken" or data.matchMode == "Same Rarity" then
                    pcall(AutoFuseFeature.setMatchMode, data.matchMode)
                else
                    pcall(AutoFuseFeature.setMatchMode, nil)
                end
            end
            if data.keepCopies ~= nil and AutoFuseFeature.setKeepCopies then pcall(AutoFuseFeature.setKeepCopies, data.keepCopies) end
            if type(data.rarities) == "table" then
                if AutoFuseFeature.clearRaritySelection then pcall(AutoFuseFeature.clearRaritySelection) end
                for _, r in ipairs(data.rarities) do
                    if AutoFuseFeature.setRaritySelected then pcall(AutoFuseFeature.setRaritySelected, r, true) end
                end
            end
            if data.protectFavorites ~= nil and AutoFuseFeature.setProtectFavorites then
                pcall(AutoFuseFeature.setProtectFavorites, data.protectFavorites == true)
            end
            if data.protectMutated ~= nil and AutoFuseFeature.setProtectMutated then
                pcall(AutoFuseFeature.setProtectMutated, data.protectMutated == true)
            end
            if data.dryRun ~= nil and AutoFuseFeature.setDryRun then pcall(AutoFuseFeature.setDryRun, data.dryRun == true) end
            if data.enabled ~= nil and AutoFuseFeature.setAutoFuse then pcall(AutoFuseFeature.setAutoFuse, data.enabled == true) end
        end, { defaults = { enabled = false, dryRun = true, keepCopies = 0, rarities = {}, protectFavorites = true, protectMutated = true } })

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
        end, { defaults = {
            boostFPS = false, disableVFX = false, disableShadows = false,
            hideOtherPlayers = false, hideOtherChickens = false, whiteScreen = false, ultraPerformance = false,
        } })

        ConfigManager.registerSection("ui", function()
            return {
                showFloatingButton = State.toggles.showFloatingButton ~= false,
                reducedMotion = State.toggles.reducedMotion == true,
                responsiveUI = RESPONSIVE.enabled ~= false,
                uiScaleMode = RESPONSIVE.mode or "Auto",
            }
        end, function(data)
            if type(data) ~= "table" then return end
            if data.showFloatingButton ~= nil then State.toggles.showFloatingButton = data.showFloatingButton == true end
            if data.reducedMotion ~= nil then State.toggles.reducedMotion = data.reducedMotion == true end
            if data.responsiveUI ~= nil then RESPONSIVE.enabled = data.responsiveUI == true end
            if type(data.uiScaleMode) == "string" then RESPONSIVE.mode = data.uiScaleMode end
            if type(updateResponsiveScale) == "function" then pcall(updateResponsiveScale) end
        end, { defaults = { showFloatingButton = true, reducedMotion = false, responsiveUI = true, uiScaleMode = "Auto" } })
    end
end



-- Auto-load config once before UI so switches reflect backend state
if ConfigManager then
    isApplyingConfig = true
    pcall(function() ConfigManager.load() end)
    isApplyingConfig = false
end

-- UNO HUB V2: Anti-AFK is always active and intentionally hidden from UI.
State.toggles.antiAfk = true
setAntiAfk(true)

local Gui = Instance.new("ScreenGui")
Gui.Name = "UNO_HUB"; Gui.ResetOnSpawn = false; Gui.IgnoreGuiInset = true; Gui.DisplayOrder = 50
Gui:SetAttribute("UNO_HUB_Shutdown", false); Gui.Parent = PlayerGui

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(920, 620); Main.Position = UDim2.fromScale(0.5, 0.5); Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.BackgroundColor3 = Theme.Background; Main.BorderSizePixel = 0; Main.ClipsDescendants = true; Main.Parent = Gui
corner(Main, 12); stroke(Main)

-- Responsive UIScale (UI only — does not affect VisualCover ScreenGui)
local MainUIScale = Instance.new("UIScale")
MainUIScale.Name = "ResponsiveScale"
MainUIScale.Scale = 1
MainUIScale.Parent = Main

local RESPONSIVE = {
    enabled = true,
    mode = "Auto", -- Auto | 1.0 | 0.9 | 0.8 | 0.7
    refW = 1920,
    refH = 1080,
    baseW = 920,
    baseH = 620,
    sidebarNormal = 145,
    sidebarSmall = 135,
    sidebarTiny = 125,
    minScale = 0.55,
    maxScale = 1.00,
    maxViewportW = 0.88,
    maxViewportH = 0.84,
}

local function getViewportSize()
    local cam = Workspace.CurrentCamera
    if cam and typeof(cam.ViewportSize) == "Vector2" then
        return cam.ViewportSize
    end
    return Vector2.new(1280, 720)
end

local function clampFloatInViewport()
    if not Float or not Float.Parent then return end
    local vp = getViewportSize()
    local size = Float.AbsoluteSize
    local pos = Float.AbsolutePosition
    local x = math.clamp(pos.X, 8, math.max(8, vp.X - size.X - 8))
    local y = math.clamp(pos.Y, 8, math.max(8, vp.Y - size.Y - 8))
    Float.Position = UDim2.fromOffset(x, y)
end

local function applySidebarWidth(width)
    width = math.floor(width)
    if Sidebar then
        Sidebar.Size = UDim2.fromOffset(width, RESPONSIVE.baseH)
    end
    if ContentRoot then
        ContentRoot.Position = UDim2.fromOffset(width, 0)
        ContentRoot.Size = UDim2.new(1, -width, 1, 0)
    end
end

local function updateResponsiveScale()
    if not Main or not MainUIScale then return end
    if RESPONSIVE.enabled == false then
        MainUIScale.Scale = 1
        applySidebarWidth(RESPONSIVE.sidebarNormal)
        return
    end
    local vp = getViewportSize()
    local scale
    if RESPONSIVE.mode ~= "Auto" then
        scale = tonumber(RESPONSIVE.mode) or 1
    else
        -- Fit base design into a fraction of the viewport
        local fitW = (vp.X * RESPONSIVE.maxViewportW) / RESPONSIVE.baseW
        local fitH = (vp.Y * RESPONSIVE.maxViewportH) / RESPONSIVE.baseH
        -- Also damp by reference desktop resolution
        local refScale = math.min(vp.X / RESPONSIVE.refW, vp.Y / RESPONSIVE.refH)
        scale = math.min(fitW, fitH, math.max(refScale, 0.55))
        scale = math.clamp(scale, RESPONSIVE.minScale, RESPONSIVE.maxScale)
        -- Extra shrink for very small floating windows
        if vp.X < 650 or vp.Y < 450 then
            scale = math.min(scale, 0.62)
        elseif vp.X < 900 or vp.Y < 600 then
            scale = math.min(scale, 0.78)
        end
    end
    MainUIScale.Scale = scale

    -- Sidebar breakpoint (base pixel widths; UIScale shrinks the whole Main)
    if vp.X < 650 or vp.Y < 450 then
        applySidebarWidth(RESPONSIVE.sidebarTiny)
    elseif vp.X < 900 or vp.Y < 600 then
        applySidebarWidth(RESPONSIVE.sidebarSmall)
    else
        applySidebarWidth(RESPONSIVE.sidebarNormal)
    end

    -- Keep floating reopen button on-screen
    pcall(clampFloatInViewport)
end

do
    local dragging, start, startPos
    maid:Connect(Main.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; start = input.Position; startPos = Main.Position end
    end)
    maid:Connect(UserInputService.InputChanged, function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local d = input.Position - start
            -- Pixel deltas are independent of UIScale on the Main frame
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    maid:Connect(UserInputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.fromOffset(145, 620)
Sidebar.BackgroundColor3 = Theme.Sidebar
Sidebar.BorderSizePixel = 0
Sidebar.Parent = Main
corner(Sidebar, 12)

local brand = Instance.new("Frame")
brand.Size = UDim2.new(1, 0, 0, 68)
brand.BackgroundTransparency = 1
brand.Parent = Sidebar

local brandUno = text(brand, "UnO", 16, Theme.TextPrimary, Enum.Font.GothamBold)
brandUno.Position = UDim2.fromOffset(16, 10)
brandUno.Size = UDim2.new(1, -24, 0, 22)

local brandHub = text(brand, "HUB", 10, Theme.TextMuted, Enum.Font.Gotham)
brandHub.Position = UDim2.fromOffset(16, 32)
brandHub.Size = UDim2.new(1, -24, 0, 18)

local NavScroll = Instance.new("ScrollingFrame")
NavScroll.Position = UDim2.fromOffset(0, 70); NavScroll.Size = UDim2.new(1, 0, 1, -130)
NavScroll.BackgroundTransparency = 1; NavScroll.BorderSizePixel = 0; NavScroll.ScrollBarThickness = 2
NavScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y; NavScroll.CanvasSize = UDim2.new(); NavScroll.Parent = Sidebar
Instance.new("UIListLayout", NavScroll).Padding = UDim.new(0, 2)
pad(NavScroll, 4, 10, 8, 10)

local pages = {
    { id = "Auto Farm", icon = "", title = "Auto Farm" },
    { id = "Auto Hatch Egg", icon = "", title = "Auto Hatch Egg" },
    { id = "Performance", icon = "", title = "Performance" },
    { id = "Webhook", icon = "", title = "Webhook" },
    { id = "Configs", icon = "", title = "Configs" },
}
local navButtons = {}
local pageDescs = {
    Home = "Overview", ["Auto Farm"] = "Farm + Collect", Tower = "Tower",
    Rebirth = "Rebirth", Eggs = "Hatch filter", Chickens = "Auto Sell",
    Fuse = "Auto Fuse", Incubator = "Auto claim", Coop = "Generators", Events = "Hot Egg",
    Utility = "Anti-AFK", Diagnostics = "Integration", Settings = "Actions",
}

local ContentRoot = Instance.new("Frame")
ContentRoot.Position = UDim2.fromOffset(145, 0); ContentRoot.Size = UDim2.new(1, -145, 1, 0)
ContentRoot.BackgroundColor3 = Theme.Background; ContentRoot.BorderSizePixel = 0; ContentRoot.Parent = Main
local Topbar = Instance.new("Frame")
Topbar.Size = UDim2.new(1, 0, 0, 52); Topbar.BackgroundColor3 = Theme.Surface; Topbar.BorderSizePixel = 0; Topbar.Parent = ContentRoot; stroke(Topbar)
local PageTitle = text(Topbar, "Grow A Chicken Fighter | V2", 13, Theme.TextPrimary, Enum.Font.GothamBold)
PageTitle.Position = UDim2.fromOffset(18, 15); PageTitle.Size = UDim2.new(1, -130, 0, 22)
local PageDesc = text(Topbar, "", 1, Theme.TextMuted)
PageDesc.Visible = false
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
Float.BackgroundColor3 = Theme.SurfaceElevated; Float.Text = "UnO"; Float.Font = Enum.Font.GothamBold
Float.TextSize = 12; Float.TextColor3 = Theme.TextPrimary; Float.Visible = false; Float.AutoButtonColor = false; Float.Parent = Gui; corner(Float, 8)

-- Bind responsive scale to camera viewport changes
do
    local function bindViewport(cam)
        if not cam then return end
        maid:Connect(cam:GetPropertyChangedSignal("ViewportSize"), function()
            updateResponsiveScale()
        end)
    end
    if Workspace.CurrentCamera then
        bindViewport(Workspace.CurrentCamera)
    end
    maid:Connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        if Workspace.CurrentCamera then
            bindViewport(Workspace.CurrentCamera)
            updateResponsiveScale()
        end
    end)
    task.defer(updateResponsiveScale)
end

local function setVisible(vis)
    if State.closed then return end
    State.visible = vis
    if vis then Main.Visible = true; Float.Visible = false
    else Main.Visible = false; if State.toggles.showFloatingButton then Float.Visible = true end end
end
local function shutdown()
    local env = (getgenv and getgenv()) or _G
    local phase9 = env.UNO_HUB_PHASE9
    if phase9 and type(phase9.destroy) == "function" then
        pcall(phase9.destroy)
    end
    local integration = env.UNO_HUB_PRIORITY_INTEGRATION
    if integration and type(integration.destroy) == "function" then
        pcall(integration.destroy)
    end
    State.closed = true; State.generation += 1

    -- 1) save config while feature getters still available
    if ConfigManager then pcall(function() ConfigManager.destroy() end) end
    -- 2) stop workers
    if AutoCollectEggFeature then pcall(function() AutoCollectEggFeature.setAutoCollectEggs(false); AutoCollectEggFeature.destroy() end) end
    if AutoSellFeature then pcall(function() AutoSellFeature.setAutoSell(false); AutoSellFeature.destroy() end) end
    if AutoFuseFeature then pcall(function() AutoFuseFeature.setAutoFuse(false); AutoFuseFeature.destroy() end) end
    HatchFeature.setAutoHatch(false)
    IncubatorClaimFeature.setAutoIncubatorClaim(false)
    if AutoUpgradeIncubatorFeature then pcall(function() AutoUpgradeIncubatorFeature.setAutoUpgradeIncubator(false) end) end
    afrCancel(); heCancel(); antiAfkGen += 1
    for name in pairs(Economy.generations) do stopEconomy(name) end
    for k in pairs(State.toggles) do State.toggles[k] = false end
    -- 3) restore visuals
    if PerformanceManager then pcall(function() PerformanceManager.destroy() end) end
    if visualCoverGui then pcall(function() visualCoverGui:Destroy() end); visualCoverGui = nil end
    -- 4) destroy UI
    maid:Cleanup(); Gui:Destroy()
end
minBtn.MouseButton1Click:Connect(function() setVisible(false) end)
local env = (getgenv and getgenv()) or _G
env.UNO_HUB_RUNTIME = {
    State = State,
    Integration = Integration,
    Services = {
        Players = Players,
        ReplicatedStorage = ReplicatedStorage,
        Workspace = Workspace,
        CollectionService = CollectionService,
        TweenService = TweenService,
    },
    MovementAdapter = MovementAdapter,
    cancelMovement = cancelMovement,
    moveTo = moveTo,
    setHotEggCoordinatorPaused = function(reason, value)
        reason = tostring(reason or "COORDINATOR")
        if value == true then HE.coordinatorPauseReasons[reason] = true else HE.coordinatorPauseReasons[reason] = nil end
    end,
    setNormalFarmCoordinatorPaused = function(reason, value)
        reason = tostring(reason or "COORDINATOR")
        if value == true then AFR.coordinatorPauseReasons[reason] = true else AFR.coordinatorPauseReasons[reason] = nil end
    end,
    getHotEggCoordinatorPauseReasons = function() return HE.coordinatorPauseReasons end,
    getNormalFarmCoordinatorPauseReasons = function() return AFR.coordinatorPauseReasons end,
    setAutoHotEgg = setAutoHotEgg,
    setAutoFarmRebirth = setAutoFarmRebirth,
    setAutoUFOAscension = function(value)
        State.toggles.autoUFOAscension = value == true
        local api = env.UNO_HUB_PHASE9
        local ok = false
        if api and type(api.setAutoUFOAscension) == "function" then
            local callOk, result = pcall(api.setAutoUFOAscension, value == true)
            ok = callOk and result ~= false
        end
        markConfigDirty()
        return ok
    end,
    getAutoUFOState = function()
        local api = env.UNO_HUB_PHASE9
        if api and type(api.getAutoUFOState) == "function" then
            local ok, result = pcall(api.getAutoUFOState)
            if ok and type(result) == "table" then return result end
        end
        return { status = "Waiting for UFO", enabled = State.toggles.autoUFOAscension }
    end,
    isTowerActive = isTowerActive,
    requestUFOTowerExit = requestUFOTowerExit,
    markConfigDirty = markConfigDirty,
    getHotEggState = function() return HE end,
    getNormalFarmState = function() return AFR end,
    shutdown = shutdown,
}
closeBtn.MouseButton1Click:Connect(shutdown)

do
    Float.Active = true
    local dragging = false
    local dragStart = nil
    local startPosition = nil
    local moved = false
    local suppressClickUntil = 0

    maid:Connect(Float.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            dragStart = input.Position
            startPosition = Float.Position
        end
    end)

    maid:Connect(UserInputService.InputChanged, function(input)
        if not dragging or not dragStart or not startPosition then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local delta = input.Position - dragStart
        if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
            moved = true
        end

        Float.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end)

    maid:Connect(UserInputService.InputEnded, function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
            if moved then suppressClickUntil = os.clock() + 0.18 end
        end
    end)

    Float.MouseButton1Click:Connect(function()
        if os.clock() < suppressClickUntil then return end
        setVisible(true)
    end)
end
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
    sc.Size = UDim2.fromScale(1, 1); sc.BackgroundTransparency = 1; sc.BorderSizePixel = 0
    sc.ScrollBarThickness = 3; sc.AutomaticCanvasSize = Enum.AutomaticSize.Y; sc.CanvasSize = UDim2.new()
    sc.Visible = false; sc.Parent = PageHost
    local lay = Instance.new("UIListLayout"); lay.Padding = UDim.new(0, 10); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Parent = sc
    pad(sc, 16, 18, 20, 18)
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

local function uiButton(parent, order, label, onClick)
    local holder = Instance.new("Frame")
    holder.LayoutOrder = order or 0
    holder.Size = UDim2.new(1, 0, 0, 36)
    holder.BackgroundTransparency = 1
    holder.Parent = parent

    local button = Instance.new("TextButton")
    button.Size = UDim2.fromScale(1, 1)
    button.BackgroundColor3 = Theme.SurfaceElevated
    button.BorderSizePixel = 0
    button.Text = label
    button.Font = Enum.Font.GothamMedium
    button.TextSize = 12
    button.TextColor3 = Theme.TextPrimary
    button.AutoButtonColor = false
    button.Parent = holder
    corner(button, 7)
    stroke(button)

    if onClick then
        button.MouseButton1Click:Connect(onClick)
    end
    return button
end

local function createTabbedPage(tabNames)
    local root = Instance.new("Frame")
    root.Size = UDim2.fromScale(1, 1)
    root.BackgroundTransparency = 1
    root.Visible = false
    root.Parent = PageHost

    local tabsBar = Instance.new("Frame")
    tabsBar.Position = UDim2.fromOffset(18, 8)
    tabsBar.Size = UDim2.new(1, -36, 0, 36)
    tabsBar.BackgroundTransparency = 1
    tabsBar.Parent = root

    local tabsLayout = Instance.new("UIListLayout")
    tabsLayout.FillDirection = Enum.FillDirection.Horizontal
    tabsLayout.Padding = UDim.new(0, 8)
    tabsLayout.Parent = tabsBar

    local body = Instance.new("Frame")
    body.Position = UDim2.fromOffset(0, 48)
    body.Size = UDim2.new(1, 0, 1, -48)
    body.BackgroundTransparency = 1
    body.Parent = root

    local bodies = {}
    local buttons = {}
    local activeTab = tabNames[1]

    local function selectTab(name)
        activeTab = name
        for tabName, frame in pairs(bodies) do
            frame.Visible = tabName == name
        end
        for tabName, button in pairs(buttons) do
            local selected = tabName == name
            button.TextColor3 = selected and Theme.TextPrimary or Theme.TextMuted
            button.BackgroundTransparency = selected and 0 or 1
        end
    end

    for index, name in ipairs(tabNames) do
        local tabButton = Instance.new("TextButton")
        tabButton.LayoutOrder = index
        tabButton.Size = UDim2.fromOffset(math.max(68, #name * 7 + 22), 30)
        tabButton.BackgroundColor3 = Theme.SurfaceElevated
        tabButton.BackgroundTransparency = 1
        tabButton.BorderSizePixel = 0
        tabButton.Text = name
        tabButton.Font = Enum.Font.GothamMedium
        tabButton.TextSize = 12
        tabButton.TextColor3 = Theme.TextMuted
        tabButton.AutoButtonColor = false
        tabButton.Parent = tabsBar
        corner(tabButton, 5)
        buttons[name] = tabButton

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.fromScale(1, 1)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 3
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.CanvasSize = UDim2.new()
        scroll.Visible = false
        scroll.Parent = body
        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 10)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = scroll
        pad(scroll, 12, 18, 18, 18)
        bodies[name] = scroll

        tabButton.MouseButton1Click:Connect(function()
            selectTab(name)
        end)
    end

    selectTab(tabNames[1])
    return root, bodies, function() return activeTab end
end

local function makeCollapsibleFilter(parent, order, label, buildRows)
    local wrap = Instance.new("Frame")
    wrap.LayoutOrder = order or 0
    wrap.Size = UDim2.new(1, 0, 0, 38)
    wrap.AutomaticSize = Enum.AutomaticSize.Y
    wrap.BackgroundTransparency = 1
    wrap.Parent = parent

    local bar = Instance.new("TextButton")
    bar.Size = UDim2.new(1, 0, 0, 36)
    bar.BackgroundColor3 = Theme.SurfaceElevated
    bar.BorderSizePixel = 0
    bar.Text = label .. "   ▾"
    bar.TextXAlignment = Enum.TextXAlignment.Left
    bar.Font = Enum.Font.Gotham
    bar.TextSize = 12
    bar.TextColor3 = Theme.TextSecondary
    bar.AutoButtonColor = false
    bar.Parent = wrap
    corner(bar, 7)
    stroke(bar)
    pad(bar, 0, 12, 0, 12)

    local list = Instance.new("Frame")
    list.Position = UDim2.fromOffset(0, 42)
    list.Size = UDim2.new(1, 0, 0, 0)
    list.AutomaticSize = Enum.AutomaticSize.Y
    list.BackgroundTransparency = 1
    list.Visible = false
    list.Parent = wrap
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.Parent = list

    local built = false

    local function clearRows()
        for _, child in ipairs(list:GetChildren()) do
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
                child:Destroy()
            end
        end
    end

    local function rebuild()
        clearRows()
        built = true
        buildRows(list)
    end

    bar.MouseButton1Click:Connect(function()
        list.Visible = not list.Visible
        bar.Text = label .. (list.Visible and "   ▴" or "   ▾")
        if list.Visible and not built then rebuild() end
    end)

    return rebuild
end

local function safeBuild(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        log("ERROR", "Build " .. name .. ": " .. tostring(err))
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

local function getPhase9API()
    local env = (getgenv and getgenv()) or _G
    local api = env.UNO_HUB_PHASE9
    return type(api) == "table" and api or nil
end

local function setPhase9Toggle(toggleKey, setterName, value)
    local api = getPhase9API()
    if not api or type(api[setterName]) ~= "function" then
        State.toggles[toggleKey] = false
        log("ERROR", setterName .. " unavailable; Phase 9 bootstrap not READY")
        return false
    end
    local ok, result = pcall(api[setterName], value == true)
    if not ok or result == false then
        State.toggles[toggleKey] = false
        log("ERROR", setterName .. " failed: " .. tostring(result))
        return false
    end
    State.toggles[toggleKey] = value == true
    return true
end

local function setAutoArenaPhase9(v)
    return setPhase9Toggle("autoArena", "setAutoArenaEnabled", v)
end
local function setEventCapsulePhase9(v)
    return setPhase9Toggle("autoEventCapsule", "setEventCapsuleEnabled", v)
end
local function setKrakenPhase9(v)
    return setPhase9Toggle("autoKraken", "setKrakenEnabled", v)
end

safeBuild("Auto Farm", function()
    local root, tabs, getActiveTab = createTabbedPage({
        "Farm", "Events", "Incubator", "Coop", "Chicken", "Fuse"
    })

    -- FARM
    local farm = tabs.Farm
    local _, farmCard = card(farm, 1, "Farm")
    settingRow(farmCard, 1, "Auto Farm Rebirth", nil, "autoFarmRebirth", setAutoFarmRebirth)
    settingRow(farmCard, 2, "Auto Rebirth", nil, "autoRebirth", setAutoRebirth)
    settingRow(farmCard, 3, "Auto K.O. Dismiss", nil, "autoKoDismiss")
    if AutoCollectEggFeature then
        settingRow(farmCard, 4, "Collect Laid Eggs", nil, "autoCollectEgg", function(v)
            AutoCollectEggFeature.setAutoCollectEggs(v)
        end)
    end
    local farmPhaseLabel = row(farmCard, 5, "Farm Status")

    -- EVENTS
    local events = tabs.Events
    local _, eventCard = card(events, 1, "Events")
    settingRow(eventCard, 1, "Auto Hot Egg", nil, "autoHotEgg", setAutoHotEgg)
    settingRow(eventCard, 2, "Event Capsule", nil, "autoEventCapsule", setEventCapsulePhase9)
    settingRow(eventCard, 3, "Auto Kraken Eggs", nil, "autoKraken", setKrakenPhase9)
    settingRow(eventCard, 4, "Auto Arena", nil, "autoArena", setAutoArenaPhase9)

    -- INCUBATOR
    local incubator = tabs.Incubator
    local _, incubatorCard = card(incubator, 1, "Incubator")
    settingRow(incubatorCard, 1, "Auto Claim Eggs", nil, "autoIncubatorClaim", function(v)
        IncubatorClaimFeature.setAutoIncubatorClaim(v)
    end)
    if AutoUpgradeIncubatorFeature then
        settingRow(incubatorCard, 2, "Auto Upgrade Incubator", nil, "autoUpgradeIncubator", function(v)
            AutoUpgradeIncubatorFeature.setAutoUpgradeIncubator(v)
        end)
    end

    -- COOP
    local coop = tabs.Coop
    local _, coopCard = card(coop, 1, "Coop")
    settingRow(coopCard, 1, "Auto Buy Generator", nil, "autoBuyGenerator", setAutoBuyGenerator)
    settingRow(coopCard, 2, "Auto Upgrade Generator", nil, "autoUpgradeGenerator", setAutoUpgradeGenerator)
    settingRow(coopCard, 3, "Auto Expand Coop", nil, "autoExpandCoop", setAutoExpandCoop)
    settingRow(coopCard, 4, "Auto Upgrade Recycler", nil, "autoUpgradeRecycler", setAutoUpgradeRecycler)

    -- CHICKEN
    local chicken = tabs.Chicken
    local _, chickenCard = card(chicken, 1, "Chicken")
    if AutoSellFeature then
        settingRow(chickenCard, 1, "Auto Sell Chickens", nil, "autoSell", function(v)
            AutoSellFeature.setAutoSell(v)
        end)

        local _, chickenFilters = card(chicken, 2, "Filters")
        makeCollapsibleFilter(chickenFilters, 1, "Rarity", function(host)
            local rarities = AutoSellFeature.getAvailableRarities()
            if #rarities == 0 then
                rarities = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "divine", "celestial", "cosmic", "secret" }
            end
            for i, rarityId in ipairs(rarities) do
                makeFilterRow(
                    host,
                    i,
                    resolveRarityDisplayName(rarityId),
                    nil,
                    AutoSellFeature.isRaritySelected(rarityId),
                    function(checkBtn)
                        local now = not AutoSellFeature.isRaritySelected(rarityId)
                        AutoSellFeature.setRaritySelected(rarityId, now)
                        checkBtn.Text = now and "✓" or ""
                    end
                )
            end
        end)

        makeCollapsibleFilter(chickenFilters, 2, "Protected Abilities", function(host)
            local abilities = AutoSellFeature.getAvailableAbilities()
            table.sort(abilities, function(a, b)
                return resolveAbilityDisplayName(a) < resolveAbilityDisplayName(b)
            end)
            for i, ability in ipairs(abilities) do
                local abilityId = ability.id
                makeFilterRow(
                    host,
                    i,
                    resolveAbilityDisplayName(ability),
                    nil,
                    AutoSellFeature.isAbilityWhitelisted(abilityId),
                    function(checkBtn)
                        local now = not AutoSellFeature.isAbilityWhitelisted(abilityId)
                        AutoSellFeature.setAbilityWhitelisted(abilityId, now)
                        checkBtn.Text = now and "✓" or ""
                    end
                )
            end
        end)
    else
        setText(row(chickenCard, 1, "Status"), "Unavailable")
    end

    -- FUSE
    local fuse = tabs.Fuse
    local _, fuseCard = card(fuse, 1, "Fuse")
    if AutoFuseFeature then
        pcall(AutoFuseFeature.setAutoFuse, false)
        pcall(AutoFuseFeature.setMatchMode, nil)
        pcall(AutoFuseFeature.setKeepCopies, 0)
        State.toggles.autoFuse = false

        -- V2 rule:
        -- Auto Fuse may only be enabled after exactly one match mode is selected.
        -- Same Chicken and Same Rarity behave like an exclusive radio pair.
        local selectedFuseMode = nil
        local setAutoFuseVisual = nil
        local setSameChickenVisual = nil
        local setSameRarityVisual = nil

        -- Do not inherit an old enabled state without an explicit V2 mode choice.
        if AutoFuseFeature.isEnabled and AutoFuseFeature.isEnabled() then
            pcall(AutoFuseFeature.setAutoFuse, false)
        end
        State.toggles.autoFuse = false

        local autoFuseRow = Instance.new("Frame")
        autoFuseRow.LayoutOrder = 1
        autoFuseRow.Size = UDim2.new(1, 0, 0, 34)
        autoFuseRow.BackgroundTransparency = 1
        autoFuseRow.Parent = fuseCard

        local autoFuseLabel = text(autoFuseRow, "Auto Fuse Chickens", 13, Theme.TextPrimary, Enum.Font.GothamMedium)
        autoFuseLabel.Size = UDim2.new(1, -350, 1, 0)

        local fuseRequirement = text(
            autoFuseRow,
            "",
            10,
            Theme.Danger,
            Enum.Font.Gotham,
            Enum.TextXAlignment.Right
        )
        fuseRequirement.Position = UDim2.new(1, -326, 0, 0)
        fuseRequirement.Size = UDim2.fromOffset(270, 34)

        local autoFuseTrack
        autoFuseTrack, setAutoFuseVisual = makeSwitch(autoFuseRow, false, function(v)
            if v and selectedFuseMode == nil then
                State.toggles.autoFuse = false
                setAutoFuseVisual(false, true)
                fuseRequirement.Text = "Select Same Chicken or Same Rarity first"
                return
            end

            fuseRequirement.Text = ""
            State.toggles.autoFuse = v == true
            AutoFuseFeature.setAutoFuse(v == true)
            markConfigDirty()
        end)
        autoFuseTrack.Position = UDim2.new(1, -40, 0.5, -11)

        local function disableAutoFuseBecauseNoMode()
            if State.toggles.autoFuse then
                State.toggles.autoFuse = false
                pcall(AutoFuseFeature.setAutoFuse, false)
                if setAutoFuseVisual then
                    setAutoFuseVisual(false, true)
                end
            end
        end

        local function selectFuseMode(mode, enabled)
            if enabled then
                selectedFuseMode = mode
                fuseRequirement.Text = ""
                pcall(AutoFuseFeature.setMatchMode, mode)

                if mode == "Same Chicken" then
                    if setSameChickenVisual then setSameChickenVisual(true, true) end
                    if setSameRarityVisual then setSameRarityVisual(false, true) end
                else
                    if setSameChickenVisual then setSameChickenVisual(false, true) end
                    if setSameRarityVisual then setSameRarityVisual(true, true) end
                end
            elseif selectedFuseMode == mode then
                selectedFuseMode = nil
                pcall(AutoFuseFeature.setMatchMode, nil)
                if mode == "Same Chicken" then
                    if setSameChickenVisual then setSameChickenVisual(false, true) end
                else
                    if setSameRarityVisual then setSameRarityVisual(false, true) end
                end
                disableAutoFuseBecauseNoMode()
            end
            markConfigDirty()
        end

        local sameChickenRow = Instance.new("Frame")
        sameChickenRow.LayoutOrder = 2
        sameChickenRow.Size = UDim2.new(1, 0, 0, 30)
        sameChickenRow.BackgroundTransparency = 1
        sameChickenRow.Parent = fuseCard

        local sameChickenLabel = text(
            sameChickenRow,
            "Same Chicken",
            12,
            Theme.TextPrimary,
            Enum.Font.GothamMedium
        )
        sameChickenLabel.Size = UDim2.new(1, -50, 1, 0)

        local sameChickenTrack
        sameChickenTrack, setSameChickenVisual = makeSwitch(sameChickenRow, false, function(v)
            selectFuseMode("Same Chicken", v)
        end)
        sameChickenTrack.Position = UDim2.new(1, -40, 0.5, -11)

        local sameRarityRow = Instance.new("Frame")
        sameRarityRow.LayoutOrder = 3
        sameRarityRow.Size = UDim2.new(1, 0, 0, 30)
        sameRarityRow.BackgroundTransparency = 1
        sameRarityRow.Parent = fuseCard

        local sameRarityLabel = text(
            sameRarityRow,
            "Same Rarity",
            12,
            Theme.TextPrimary,
            Enum.Font.GothamMedium
        )
        sameRarityLabel.Size = UDim2.new(1, -50, 1, 0)

        local sameRarityTrack
        sameRarityTrack, setSameRarityVisual = makeSwitch(sameRarityRow, false, function(v)
            selectFuseMode("Same Rarity", v)
        end)
        sameRarityTrack.Position = UDim2.new(1, -40, 0.5, -11)

        local _, fuseFilters = card(fuse, 2, "Filters")
        makeCollapsibleFilter(fuseFilters, 1, "Rarity", function(host)
            local rarities = AutoFuseFeature.getAvailableRarities()
            for i, rarityId in ipairs(rarities) do
                makeFilterRow(
                    host,
                    i,
                    resolveRarityDisplayName(rarityId),
                    nil,
                    AutoFuseFeature.isRaritySelected(rarityId),
                    function(checkBtn)
                        local now = not AutoFuseFeature.isRaritySelected(rarityId)
                        AutoFuseFeature.setRaritySelected(rarityId, now)
                        checkBtn.Text = now and "✓" or ""
                    end
                )
            end
        end)
    else
        setText(row(fuseCard, 1, "Status"), "Unavailable")
    end

    Views["Auto Farm"] = {
        root = root,
        update = function()
            local _ = getActiveTab()
            local phase = tostring(AFR.phase or "IDLE")
            if AFR.countdown and AFR.countdown > 0 then
                phase = phase .. " (" .. tostring(AFR.countdown) .. "s)"
            end
            setText(farmPhaseLabel, phase)
        end,
    }
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

safeBuild("Auto Hatch Egg", function()
    local sc = createScrollPage()

    local _, hatchCard = card(sc, 1, "Auto Hatch Egg")
    settingRow(hatchCard, 1, "Auto Hatch Eggs", nil, "autoHatch", function(v)
        HatchFeature.setAutoHatch(v)
    end)

    local _, filterCard = card(sc, 2, "Egg Filter")

    local function buildEggRows(host)
        local controls = Instance.new("Frame")
        controls.LayoutOrder = 0
        controls.Size = UDim2.new(1, 0, 0, 32)
        controls.BackgroundTransparency = 1
        controls.Parent = host

        local selectAll = Instance.new("TextButton")
        selectAll.Size = UDim2.new(0.5, -4, 0, 28)
        selectAll.BackgroundColor3 = Theme.SurfaceElevated
        selectAll.BorderSizePixel = 0
        selectAll.Text = "Select All"
        selectAll.Font = Enum.Font.Gotham
        selectAll.TextSize = 11
        selectAll.TextColor3 = Theme.TextPrimary
        selectAll.AutoButtonColor = false
        selectAll.Parent = controls
        corner(selectAll, 6)
        selectAll.MouseButton1Click:Connect(function()
            HatchFeature.selectAllAvailableEggs()
            HatchFeature.userCustomized = true
        end)

        local clear = selectAll:Clone()
        clear.Position = UDim2.new(0.5, 4, 0, 0)
        clear.Text = "Clear"
        clear.Parent = controls
        clear.MouseButton1Click:Connect(function()
            HatchFeature.clearEggSelection()
        end)

        refreshData()
        local available = HatchFeature.getAvailableEggTypes()

        if #available == 0 then
            local empty = text(host, "No eggs detected.", 11, Theme.TextMuted)
            empty.LayoutOrder = 10
            empty.Size = UDim2.new(1, 0, 0, 26)
            return
        end

        for i, egg in ipairs(available) do
            local friendly = egg.displayName
            if type(friendly) ~= "string" or friendly == "" then
                friendly = resolveEggDisplayName(egg.id)
            end
            makeFilterRow(
                host,
                10 + i,
                friendly,
                "x" .. tostring(egg.quantity or 0),
                HatchFeature.isEggSelected(egg.id),
                function(checkBtn)
                    local now = not HatchFeature.isEggSelected(egg.id)
                    HatchFeature.setEggSelected(egg.id, now)
                    checkBtn.Text = now and "✓" or ""
                end
            )
        end
    end

    local rebuildEggFilter = makeCollapsibleFilter(filterCard, 1, "Select Eggs", buildEggRows)

    uiButton(filterCard, 2, "Refresh", function()
        refreshData()
        rebuildEggFilter()
    end)

    Views["Auto Hatch Egg"] = { root = sc, update = function() end }
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

    local _, phase9Card = card(sc, 1, "PHASE 9 EVENTS")
    settingRow(phase9Card, 1, "Event Capsule", nil, "autoEventCapsule", setEventCapsulePhase9)
    settingRow(phase9Card, 2, "Auto Arena", nil, "autoArena", setAutoArenaPhase9)
    settingRow(phase9Card, 3, "Auto Kraken Eggs", nil, "autoKraken", setKrakenPhase9)
    local p9Status = row(phase9Card, 4, "Phase 9 Status")
    local p9Owner = row(phase9Card, 5, "Priority Owner")
    local p9Error = row(phase9Card, 6, "Last Error")

    local _, ufoCard = card(sc, 2, "UFO ASCENSION", "Current equipped chicken • Until Max Genes")
    settingRow(ufoCard, 1, "Auto UFO Ascension", nil, "autoUFOAscension", function(value)
        State.toggles.autoUFOAscension = value == true
        local api = getPhase9API()
        if api and type(api.setAutoUFOAscension) == "function" then pcall(api.setAutoUFOAscension, value == true) end
        markConfigDirty()
    end)
    local ufoChicken = row(ufoCard, 2, "Equipped")
    local ufoTarget = row(ufoCard, 3, "Target")
    local ufoStatus = row(ufoCard, 4, "Status")
    local ufoGenes = {}
    for index, key in ipairs({ "vigor", "furia", "velocidad", "impetu", "fertility" }) do
        ufoGenes[key] = row(ufoCard, 4 + index, string.upper(key))
    end

    Views.Events = { root = sc, update = function()
        local api = getPhase9API()
        if api then
            setText(p9Status, type(api.getStatus) == "function" and api.getStatus() or "READY")
            local cs = type(api.getCoordinatorState) == "function" and api.getCoordinatorState() or nil
            local owner = cs and (cs.currentMovementOwner or cs.owner or cs.currentOwner) or "NONE"
            setText(p9Owner, owner)
            setText(p9Error, type(api.getLastError) == "function" and (api.getLastError() or "—") or "—")
        else
            setText(p9Status, "BOOTSTRAPPING")
            setText(p9Owner, "NONE")
            setText(p9Error, "—")
        end

        local ufoState = api and type(api.getAutoUFOState) == "function" and api.getAutoUFOState() or nil
        setText(ufoChicken, ufoState and (ufoState.targetName or ufoState.targetId) or "Equipped chicken")
        setText(ufoTarget, "Until Max Genes")
        setText(ufoStatus, ufoState and ufoState.status or "Waiting for UFO")
        local genes = ufoState and ufoState.genes or nil
        local rarity = ufoState and ufoState.targetRarity or nil
        if type(rarity) == "table" then rarity = rarity.id or rarity.name end
        local caps = { common=8, uncommon=12, rare=16, epic=20, legendary=24, mythic=27, divine=29, celestial=30, cosmic=31, secret=31 }
        local cap = caps[string.lower(tostring(rarity or ""))]
        for key, label in pairs(ufoGenes) do
            setText(label, genes and genes[key] ~= nil and (tostring(genes[key]) .. " / " .. tostring(cap or "?")) or "—")
        end
    end }
end)


safeBuild("Performance", function()
    local sc = createScrollPage()
    local _, perfCard = card(sc, 1, "Performance")

    if PerformanceManager then
        local function perfToggle(order, title, getter, setter)
            local f = Instance.new("Frame")
            f.LayoutOrder = order
            f.Size = UDim2.new(1, 0, 0, 34)
            f.BackgroundTransparency = 1
            f.Parent = perfCard

            local label = text(f, title, 12, Theme.TextPrimary, Enum.Font.GothamMedium)
            label.Size = UDim2.new(1, -52, 1, 0)

            local sw = select(1, makeSwitch(f, getter() == true, function(v)
                setter(v)
                markConfigDirty()
            end))
            sw.Position = UDim2.new(1, -40, 0.5, -11)
        end

        perfToggle(1, "Boost FPS", PerformanceManager.getBoostFPS, PerformanceManager.setBoostFPS)
        perfToggle(2, "Disable VFX", PerformanceManager.getDisableVFX, PerformanceManager.setDisableVFX)
        perfToggle(3, "Disable Shadows", PerformanceManager.getDisableShadows, PerformanceManager.setDisableShadows)
        perfToggle(4, "Hide Other Players", PerformanceManager.getHideOtherPlayers, PerformanceManager.setHideOtherPlayers)
        perfToggle(5, "White Screen / AFK Saver", PerformanceManager.getWhiteScreen, PerformanceManager.setWhiteScreen)
        perfToggle(6, "Ultra Performance", PerformanceManager.getUltraPerformance, PerformanceManager.setUltraPerformance)
    else
        setText(row(perfCard, 1, "Status"), "Unavailable")
    end

    Views.Performance = { root = sc, update = function() end }
end)

safeBuild("Webhook", function()
    local sc = createScrollPage()
    Views.Webhook = { root = sc, update = function() end }
end)

safeBuild("Configs", function()
    local sc = createScrollPage()
    local _, cfgCard = card(sc, 1, "Configs")

    if not ConfigManager then
        setText(row(cfgCard, 1, "Status"), "Unavailable")
        Views.Configs = { root = sc, update = function() end }
        return
    end

    local configNameLabel = text(cfgCard, "Config name", 12, Theme.TextSecondary)
    configNameLabel.LayoutOrder = 1
    configNameLabel.Size = UDim2.new(1, 0, 0, 18)

    local configName = Instance.new("TextBox")
    configName.LayoutOrder = 2
    configName.Size = UDim2.new(1, 0, 0, 36)
    configName.BackgroundColor3 = Theme.SurfaceElevated
    configName.BorderSizePixel = 0
    configName.ClearTextOnFocus = false
    configName.Text = ConfigManager.getConfigName()
    configName.PlaceholderText = "default"
    configName.Font = Enum.Font.Gotham
    configName.TextSize = 12
    configName.TextColor3 = Theme.TextPrimary
    configName.PlaceholderColor3 = Theme.TextMuted
    configName.TextXAlignment = Enum.TextXAlignment.Left
    configName.Parent = cfgCard
    corner(configName, 7)
    stroke(configName)
    pad(configName, 0, 12, 0, 12)

    local loadLabel = text(cfgCard, "Load config", 12, Theme.TextSecondary)
    loadLabel.LayoutOrder = 3
    loadLabel.Size = UDim2.new(1, 0, 0, 18)

    local loadName = configName:Clone()
    loadName.LayoutOrder = 4
    loadName.Parent = cfgCard

    local actions = Instance.new("Frame")
    actions.LayoutOrder = 5
    actions.Size = UDim2.new(1, 0, 0, 36)
    actions.BackgroundTransparency = 1
    actions.Parent = cfgCard

    local saveButton = Instance.new("TextButton")
    saveButton.Size = UDim2.new(0.5, -4, 1, 0)
    saveButton.BackgroundColor3 = Theme.SurfaceElevated
    saveButton.BorderSizePixel = 0
    saveButton.Text = "Save config"
    saveButton.Font = Enum.Font.GothamMedium
    saveButton.TextSize = 12
    saveButton.TextColor3 = Theme.TextPrimary
    saveButton.AutoButtonColor = false
    saveButton.Parent = actions
    corner(saveButton, 7)
    stroke(saveButton)

    local loadButton = saveButton:Clone()
    loadButton.Position = UDim2.new(0.5, 4, 0, 0)
    loadButton.Text = "Load config"
    loadButton.Parent = actions

    saveButton.MouseButton1Click:Connect(function()
        ConfigManager.setConfigName(configName.Text)
        configName.Text = ConfigManager.getConfigName()
        loadName.Text = configName.Text
        ConfigManager.saveNow()
    end)

    loadButton.MouseButton1Click:Connect(function()
        ConfigManager.setConfigName(loadName.Text)
        loadName.Text = ConfigManager.getConfigName()
        configName.Text = loadName.Text
        isApplyingConfig = true
        ConfigManager.load()
        isApplyingConfig = false
        State.toggles.antiAfk = true
        setAntiAfk(true)
    end)

    local autoSaveRow = Instance.new("Frame")
    autoSaveRow.LayoutOrder = 6
    autoSaveRow.Size = UDim2.new(1, 0, 0, 44)
    autoSaveRow.BackgroundColor3 = Theme.SurfaceElevated
    autoSaveRow.BorderSizePixel = 0
    autoSaveRow.Parent = cfgCard
    corner(autoSaveRow, 7)
    stroke(autoSaveRow)

    local asTitle = text(autoSaveRow, "Auto Save & Load Config", 12, Theme.TextPrimary, Enum.Font.GothamMedium)
    asTitle.Position = UDim2.fromOffset(12, 3)
    asTitle.Size = UDim2.new(1, -64, 0, 20)

    local asSub = text(autoSaveRow, "Save changes automatically.", 10, Theme.TextMuted)
    asSub.Position = UDim2.fromOffset(12, 21)
    asSub.Size = UDim2.new(1, -64, 0, 16)

    local autoSaveSwitch = select(1, makeSwitch(autoSaveRow, ConfigManager.getAutoSave() == true, function(v)
        ConfigManager.setAutoSave(v)
    end))
    autoSaveSwitch.Position = UDim2.new(1, -44, 0.5, -11)

    local status = row(cfgCard, 7, "Status")
    local path = row(cfgCard, 8, "File")

    Views.Configs = {
        root = sc,
        update = function()
            setText(status, ConfigManager.getStatus())
            setText(path, ConfigManager.getConfigPath())
        end,
    }
end)

safeBuild("Settings", function()
    local sc = createScrollPage()

    local _, perfCard = card(sc, 1, "PERFORMANCE")
    if PerformanceManager then
        local function perfToggle(order, title, getter, setter)
            local f = Instance.new("Frame"); f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, 28)
            f.BackgroundTransparency = 1; f.Parent = perfCard
            text(f, title, 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
            local sw = select(1, makeSwitch(f, getter() == true, function(v)
                setter(v)
                markConfigDirty()
            end))
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
            local sw = select(1, makeSwitch(f, ConfigManager.getAutoSave() == true, function(v)
                ConfigManager.setAutoSave(v)
            end))
            sw.Position = UDim2.new(1, -40, 0.5, -11)
        end
        do
            local f = Instance.new("Frame"); f.LayoutOrder = 2; f.Size = UDim2.new(1, 0, 0, 28)
            f.BackgroundTransparency = 1; f.Parent = cfgCard
            text(f, "Restore Destructive Automation", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
            local sw = select(1, makeSwitch(f, ConfigManager.getRestoreDestructiveAutomation() == true, function(v)
                ConfigManager.setRestoreDestructiveAutomation(v)
            end))
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
            isApplyingConfig = true
            ConfigManager.load()
            isApplyingConfig = false
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
            isApplyingConfig = true
            ConfigManager.resetToDefaults(true)
            isApplyingConfig = false
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

    local _, uiCard = card(sc, 3, "UI SCALE")
    do
        local f = Instance.new("Frame"); f.LayoutOrder = 1; f.Size = UDim2.new(1, 0, 0, 28)
        f.BackgroundTransparency = 1; f.Parent = uiCard
        text(f, "Responsive UI (Auto)", 13, Theme.TextPrimary, Enum.Font.GothamMedium).Size = UDim2.new(1, -50, 1, 0)
        local sw = select(1, makeSwitch(f, RESPONSIVE.enabled ~= false, function(v)
            RESPONSIVE.enabled = v == true
            if v then RESPONSIVE.mode = "Auto" end
            updateResponsiveScale()
            markConfigDirty()
        end))
        sw.Position = UDim2.new(1, -40, 0.5, -11)
    end
    local function scaleBtn(parent, order, label, modeVal)
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
            RESPONSIVE.enabled = true
            RESPONSIVE.mode = modeVal
            updateResponsiveScale()
            markConfigDirty()
        end)
    end
    scaleBtn(uiCard, 2, "Auto (viewport)", "Auto")
    scaleBtn(uiCard, 3, "100%", "1")
    scaleBtn(uiCard, 4, "90%", "0.9")
    scaleBtn(uiCard, 5, "80%", "0.8")
    scaleBtn(uiCard, 6, "70%", "0.7")
    local scaleStatus = row(uiCard, 7, "Current Scale")
    local prevUpdate = Views._cfgUpdate
    Views._cfgUpdate = function()
        if type(prevUpdate) == "function" then pcall(prevUpdate) end
        if MainUIScale then
            setText(scaleStatus, string.format("%.0f%%", MainUIScale.Scale * 100))
        end
    end

    local _, actions = card(sc, 4, "ACTIONS")
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
    State.page = id
    PageTitle.Text = "Grow A Chicken Fighter | V2"
    for pid, view in pairs(Views) do
        if type(view) == "table" and typeof(view.root) == "Instance" then
            view.root.Visible = (pid == id)
        end
    end
    for pid, btn in pairs(navButtons) do
        local selected = pid == id
        btn.BackgroundTransparency = selected and 0 or 1
        btn.BackgroundColor3 = selected and Theme.SurfaceElevated or Color3.new(0, 0, 0)
        local accent = btn:FindFirstChild("Accent"); if accent then accent.Visible = selected end
        local label = btn:FindFirstChild("Label")
        if label then label.TextColor3 = selected and Theme.TextPrimary or Theme.TextSecondary end
    end
    local view = Views[id]
    if view and view.update then pcall(view.update) end
end

for i, p in ipairs(pages) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 32); btn.BackgroundTransparency = 1; btn.Text = ""
    btn.AutoButtonColor = false; btn.LayoutOrder = i; btn.Parent = NavScroll; corner(btn, 6)
    local accent = Instance.new("Frame"); accent.Name = "Accent"; accent.Size = UDim2.fromOffset(3, 16)
    accent.Position = UDim2.fromOffset(0, 8); accent.BackgroundColor3 = Theme.Primary
    accent.BorderSizePixel = 0; accent.Visible = false; accent.Parent = btn; corner(accent, 2)
    local label = text(btn, (p.icon ~= "" and (p.icon .. "   ") or "") .. p.title, 12, Theme.TextSecondary)
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


refreshData()
refreshEconomyStatus()
showPage("Auto Farm")

log("INFO", "UNO HUB — Responsive UIScale enabled")
print("[UNO HUB] AutoSellFeature =", AutoSellFeature and "READY" or State.diagnostics["AutoSell.Feature"])
print("[UNO HUB] AutoFuseFeature =", AutoFuseFeature and "READY" or State.diagnostics["AutoFuse.Feature"])
print("[UNO HUB] HatchFeature =", HatchFeature and "READY" or "MISSING")
print("[UNO HUB] AutoCollectEggFeature =", AutoCollectEggFeature and "READY" or "MISSING")
print("[UNO HUB] IncubatorClaimFeature =", IncubatorClaimFeature and "READY" or "MISSING")
print("[UNO HUB] AutoUpgradeIncubatorFeature =", AutoUpgradeIncubatorFeature and "READY" or "MISSING")


do
    local env = (getgenv and getgenv()) or _G
    env.UNO_HUB_RUNTIME = {
        State = State,
        Integration = Integration,
        Services = {
            Players = Players,
            ReplicatedStorage = ReplicatedStorage,
            Workspace = Workspace,
            CollectionService = CollectionService,
            TweenService = TweenService,
        },
        MovementAdapter = MovementAdapter,
        cancelMovement = cancelMovement,
        moveTo = moveTo,
        setHotEggCoordinatorPaused = function(reason, value)
            reason = tostring(reason or "COORDINATOR")
            if value == true then
                HE.coordinatorPauseReasons[reason] = true
            else
                HE.coordinatorPauseReasons[reason] = nil
            end
        end,
        setNormalFarmCoordinatorPaused = function(reason, value)
            reason = tostring(reason or "COORDINATOR")
            if value == true then
                AFR.coordinatorPauseReasons[reason] = true
            else
                AFR.coordinatorPauseReasons[reason] = nil
            end
        end,
        getHotEggCoordinatorPauseReasons = function() return HE.coordinatorPauseReasons end,
        getNormalFarmCoordinatorPauseReasons = function() return AFR.coordinatorPauseReasons end,
        setAutoHotEgg = setAutoHotEgg,
        setAutoFarmRebirth = setAutoFarmRebirth,
        setAutoRebirth = setAutoRebirth,
        getHotEggState = function() return HE end,
        getNormalFarmState = function() return AFR end,
        shutdown = shutdown,
    }
    print("[UNO HUB] Core runtime bridge READY")
end
end


__unoRunStage("01 CORE/UI + RUNTIME BRIDGE", __unoStage01)


local function __unoStage02()
-- AUTO EVENT CAPSULE
-- Standalone integration-ready backend for UFO/Admin Scrap-style capsules.
-- This module intentionally excludes Kraken Rain Eggs and does not inspect or filter egg IDs.
-- It uses only the normal world interaction path: move to a capsule or owner Recycler,
-- then wait for authoritative replicated state/events.

local function createEventCapsuleCollector(deps)
    deps = deps or {}

    local player = assert(deps.player, "player is required")
    local workspace = assert(deps.workspace, "workspace is required")
    local scheduler = deps.task or task
    local logger = deps.log
    local collectionService = deps.collectionService
    local scrapDeposited = deps.scrapDeposited
    local movement = deps.movement
    local moveTo = deps.moveTo or (movement and movement.moveTo)
    local acquireMovement = deps.acquireMovement
    local releaseMovement = deps.releaseMovement

    assert(type(moveTo) == "function", "deps.moveTo or deps.movement.moveTo is required")

    local enabled = false
    local destroyed = false
    local pausedReasons = {}
    local generation = 0
    local activeWorkerGeneration = nil
    local workerRunning = false
    local restartRequested = false
    local inProgress = false
    local activeMove = nil
    local activeTarget = nil
    local ownerRecycler = nil
    local pendingCapsules = {}
    local records = {}
    local connections = {}
    local looseConnections = {}
    local status = "DISABLED"
    local maxCarry = tonumber(deps.maxCarry) or 5
    local movementMode = deps.movementMode or "Tween"
    local lastError = nil
    local lastPickup = nil
    local lastDeposit = nil
    local lastDepositError = nil
    local depositFailed = false
    local depositFailureOverride = false
    local depositAttemptActive = false
    local lastObservedCarry = nil
    local depositEventSerial = 0
    local characterSerial = 0

    local pickupTimeout = tonumber(deps.pickupTimeout) or 8
    local depositTimeout = tonumber(deps.depositTimeout) or 12
    local movementTimeout = tonumber(deps.movementTimeout) or 15
    local capsuleRetargetInterval = tonumber(deps.capsuleRetargetInterval) or 0.35
    local capsuleRetargetDistance = tonumber(deps.capsuleRetargetDistance) or 3
    local capsuleFollowDistance = tonumber(deps.capsuleFollowDistance) or 3
    local recyclerFrontDistance = tonumber(deps.recyclerFrontDistance) or 5
    local recyclerFrontSign = tonumber(deps.recyclerFrontSign) or 1
    local retryBackoff = tonumber(deps.retryBackoff) or 2
    local pollInterval = tonumber(deps.pollInterval) or 0.25

    local function log(level, message)
        if type(logger) == "function" then
            pcall(logger, level, message)
        end
    end

    local function wait(seconds)
        if scheduler and type(scheduler.wait) == "function" then
            scheduler.wait(seconds)
        end
    end

    local function spawn(fn)
        if scheduler and type(scheduler.spawn) == "function" then
            return scheduler.spawn(fn)
        end
        return nil
    end

    local function now()
        return os.clock()
    end

    local function signalChanged(signal, callback, bucket)
        if not signal or type(signal.Connect) ~= "function" then
            return nil
        end
        local ok, connection = pcall(function()
            return signal:Connect(callback)
        end)
        if ok and connection then
            table.insert(bucket or connections, connection)
            return connection
        end
        return nil
    end

    local function isCurrentWorker(workerGeneration)
        return enabled and not destroyed and workerGeneration == generation
    end

    local function wake()
        -- State changes are observed by the single worker on its next bounded poll.
    end

    local function setStatus(nextStatus)
        if status ~= nextStatus then
            status = nextStatus
        end
    end

    local function setError(message)
        lastError = tostring(message)
        log("warn", "[Capsule] " .. lastError)
    end

    local function clearDepositFailureOverride(reason)
        if depositFailureOverride then
            depositFailureOverride = false
            log("info", "[Capsule] deposit failure override cleared")
        end
        if reason == "confirmed" or reason == "manual_or_external" then
            depositFailed = false
        end
    end

    local function readAttribute(instance, name)
        if not instance then
            return nil
        end
        local ok, value = pcall(function()
            return instance:GetAttribute(name)
        end)
        return ok and value or nil
    end

    local function carryCount()
        local value = readAttribute(player, "scrapCarry")
        return type(value) == "number" and value or tonumber(value)
    end

    local function getCharacterRoot()
        local character = player.Character
        if not character then
            return nil
        end
        return character:FindFirstChild("HumanoidRootPart")
            or character.PrimaryPart
    end

    local function getPosition(instance)
        if not instance then
            return nil
        end
        local ok, position = pcall(function()
            if instance:IsA("BasePart") then
                return instance.Position
            end
            if instance:IsA("Model") then
                return instance:GetPivot().Position
            end
            if instance:IsA("Attachment") then
                return instance.WorldPosition
            end
            return nil
        end)
        return ok and position or nil
    end

    local function isLiveCapsule(instance)
        return instance ~= nil
            and instance:IsA("Model")
            and instance.Name == "Egg"
            and instance.Parent ~= nil
            and instance.Parent.Name == "Loose"
            and instance.Parent.Parent ~= nil
            and instance.Parent.Parent.Name == "PitScrap"
    end

    local function findLoose()
        local pitScrap = workspace:FindFirstChild("PitScrap")
        return pitScrap and pitScrap:FindFirstChild("Loose") or nil
    end

    local function resolveOwnerRecycler()
        local plot = readAttribute(player, "Plot")
        local recyclers = workspace:FindFirstChild("Recyclers")
        if plot == nil or not recyclers then
            ownerRecycler = nil
            return nil
        end
        local candidate = recyclers:FindFirstChild("Recycler" .. tostring(plot))
        ownerRecycler = candidate
        return candidate
    end

    local function resolveRecyclerPosition(recycler)
        if not recycler then
            return nil
        end
        local preferredNames = {
            "Origin", "DepositZone", "Deposit", "Interaction", "Interact", "PromptPart", "Hitbox"
        }
        for _, preferredName in ipairs(preferredNames) do
            local candidate = recycler:FindFirstChild(preferredName, true)
            local position = getPosition(candidate)
            if position then
                return position, preferredName, recycler:GetPivot()
            end
        end
        for _, descendant in ipairs(recycler:GetDescendants()) do
            if descendant:IsA("Attachment") then
                local lowered = string.lower(descendant.Name)
                if lowered:find("deposit", 1, true) or lowered:find("origin", 1, true)
                    or lowered:find("interact", 1, true) then
                    return descendant.WorldPosition, "Attachment", recycler:GetPivot()
                end
            end
        end
        local pivot = recycler:GetPivot()
        local characterRoot = getCharacterRoot()
        local y = characterRoot and characterRoot.Position.Y or pivot.Position.Y
        local frontDirection = Vector3.new(pivot.LookVector.X, 0, pivot.LookVector.Z)
        if frontDirection.Magnitude < 0.01 then
            frontDirection = Vector3.new(0, 0, 1)
        else
            frontDirection = frontDirection.Unit
        end
        local candidatePlus = Vector3.new(
            pivot.Position.X + frontDirection.X * recyclerFrontDistance,
            y,
            pivot.Position.Z + frontDirection.Z * recyclerFrontDistance
        )
        local candidateMinus = Vector3.new(
            pivot.Position.X - frontDirection.X * recyclerFrontDistance,
            y,
            pivot.Position.Z - frontDirection.Z * recyclerFrontDistance
        )
        local chosenSign = recyclerFrontSign == -1 and -1 or 1
        local fallback = chosenSign == -1 and candidateMinus or candidatePlus
        log("info", "[Capsule] recycler LookVector=" .. tostring(pivot.LookVector))
        log("info", "[Capsule] candidate sign +1=" .. tostring(candidatePlus))
        log("info", "[Capsule] candidate sign -1=" .. tostring(candidateMinus))
        log("info", "[Capsule] chosen sign=" .. tostring(chosenSign))
        log("info", "[Capsule] chosen distance=" .. tostring(recyclerFrontDistance))
        return fallback, "FrontOffsetFallback", pivot
    end

    local function addCapsule(instance)
        if not isLiveCapsule(instance) or records[instance] then
            return
        end
        records[instance] = {
            instance = instance,
            createdAt = now(),
            invalid = false,
            processed = false,
            disappearanceObserved = false,
            queuedDuringDeposit = false,
            lastMovementTargetPosition = nil,
            currentCapsulePosition = nil,
        }
        pendingCapsules[instance] = true
        log("info", "[Capsule] detected")
        if (status == "DEPOSITING" or status == "WAITING_FOR_DEPOSIT_CONFIRMATION")
            and records[instance] and not records[instance].queuedDuringDeposit then
            records[instance].queuedDuringDeposit = true
            log("info", "[Capsule] queued during deposit")
        end
        wake()
    end

    local function invalidateCapsule(instance, reason)
        local record = records[instance]
        pendingCapsules[instance] = nil
        if record then
            record.invalid = true
            record.invalidReason = reason
        end
        if activeTarget == instance then
            activeTarget = nil
        end
        if reason then
            log("warn", "[Capsule] target invalid: " .. tostring(reason))
        end
        wake()
    end

    local function removeDeadCapsules()
        for instance, record in pairs(records) do
            if not isLiveCapsule(instance) then
                if pendingCapsules[instance] or activeTarget == instance then
                    invalidateCapsule(instance, "claimed_or_removed")
                end
                if record.processed or record.invalid then
                    records[instance] = nil
                end
            end
        end
    end

    local function capsuleDistance(instance)
        local root = getCharacterRoot()
        local position = getPosition(instance)
        if not root or not position then
            return math.huge
        end
        return (root.Position - position).Magnitude
    end

    local function selectNearestCapsule()
        removeDeadCapsules()
        local selected = nil
        local selectedDistance = math.huge
        for instance in pairs(pendingCapsules) do
            if isLiveCapsule(instance) then
                local distance = capsuleDistance(instance)
                if distance < selectedDistance then
                    selected = instance
                    selectedDistance = distance
                end
            else
                invalidateCapsule(instance, "not_live_under_loose")
            end
        end
        return selected
    end

    local function cancelActiveMove(reason)
        local handle = activeMove
        activeMove = nil
        if handle then
            local cancel = handle.cancel or handle.stop or handle.destroy
            if type(cancel) == "function" then
                pcall(cancel, handle, reason)
            end
        end
    end

    local function movementResult(handle, timeout, workerGeneration, characterAtStart, shouldPreempt)
        if type(handle) == "boolean" then
            return handle
        end
        if type(handle) ~= "table" then
            return false, "movement_handle_invalid"
        end
        if type(handle.isComplete) ~= "function" and handle.completed ~= true and handle.done ~= true then
            return false, "movement_handle_not_cancellable"
        end
        local deadline = now() + timeout
        while isCurrentWorker(workerGeneration) and now() < deadline do
            if characterSerial ~= characterAtStart then
                return false, "character_reset"
            end
            if type(shouldPreempt) == "function" and shouldPreempt() then
                return false, "return_preempted"
            end
            if type(handle.isComplete) == "function" then
                local ok, complete = pcall(handle.isComplete, handle)
                if ok and complete then
                    return true
                end
            elseif handle.completed == true or handle.done == true then
                return true
            end
            wait(0.1)
        end
        return false, "movement_timeout_or_cancel"
    end

    local function moveToPosition(position, purpose, workerGeneration, shouldPreempt)
        if not position or not isCurrentWorker(workerGeneration) then
            return false
        end
        local characterAtStart = characterSerial
        cancelActiveMove("replace")
        local cancelToken = { cancelled = false }
        local options = {
            mode = movementMode,
            purpose = purpose,
            cancelToken = cancelToken,
            isCancelled = function()
                return cancelToken.cancelled or not isCurrentWorker(workerGeneration)
            end,
        }
        local ok, handle = pcall(moveTo, position, options)
        if not ok then
            setError("movement failed: " .. tostring(handle))
            return false
        end
        activeMove = handle
        local completed, movementReason = movementResult(handle, movementTimeout, workerGeneration, characterAtStart, shouldPreempt)
        if not completed then
            cancelToken.cancelled = true
            cancelActiveMove(movementReason or "movement_timeout_or_cancel")
            return false, movementReason
        end
        activeMove = nil
        if characterSerial ~= characterAtStart or not isCurrentWorker(workerGeneration) then
            return false, "worker_or_character_changed"
        end
        return true
    end

    local function beginMovement(position, purpose, workerGeneration)
        if not position or not isCurrentWorker(workerGeneration) then
            return nil, "invalid_movement_request"
        end
        cancelActiveMove("replace")
        local cancelToken = { cancelled = false }
        local options = {
            mode = movementMode,
            purpose = purpose,
            cancelToken = cancelToken,
            isCancelled = function()
                return cancelToken.cancelled or not isCurrentWorker(workerGeneration)
            end,
        }
        local ok, handle = pcall(moveTo, position, options)
        if not ok then
            return nil, tostring(handle)
        end
        if type(handle) == "boolean" then
            return handle, nil
        end
        if type(handle) ~= "table" then
            return nil, "movement_handle_invalid"
        end
        if type(handle.isComplete) ~= "function" and handle.completed ~= true and handle.done ~= true then
            return nil, "movement_handle_not_cancellable"
        end
        activeMove = handle
        return handle, nil
    end

    local function movementComplete(handle)
        if type(handle) == "boolean" then
            return handle
        end
        if type(handle) ~= "table" then
            return false
        end
        if type(handle.isComplete) == "function" then
            local ok, complete = pcall(handle.isComplete, handle)
            return ok and complete == true
        end
        return handle.completed == true or handle.done == true
    end

    local function moveToCapsuleDynamic(instance, workerGeneration)
        local initialPosition = getPosition(instance)
        if not initialPosition then
            return false, "capsule_position_unavailable"
        end
        local targetPosition = initialPosition
        local lastMovementTargetPosition = targetPosition
        local record = records[instance]
        if record then
            record.lastMovementTargetPosition = lastMovementTargetPosition
            record.currentCapsulePosition = initialPosition
        end
        log("info", "[Capsule] moving target=" .. tostring(targetPosition))
        local handle, movementError = beginMovement(targetPosition, "EVENT_CAPSULE", workerGeneration)
        if not handle then
            return false, movementError
        end
        if type(handle) == "boolean" then
            return handle, nil
        end
        local startedAt = now()
        local nextRetargetAt = startedAt + capsuleRetargetInterval
        local followingLogged = false
        while isCurrentWorker(workerGeneration) and now() - startedAt < movementTimeout do
            if not isLiveCapsule(instance) then
                cancelActiveMove("capsule_disappeared")
                log("info", "[Capsule] capsule disappeared")
                return true, "capsule_disappeared"
            end

            if now() >= nextRetargetAt then
                nextRetargetAt = now() + capsuleRetargetInterval
                local currentCapsulePosition = getPosition(instance)
                local currentPlayerRoot = getCharacterRoot()
                if record then
                    record.currentCapsulePosition = currentCapsulePosition
                end
                if currentCapsulePosition and currentPlayerRoot then
                    local playerDistance = (currentPlayerRoot.Position - currentCapsulePosition).Magnitude
                    local delta = (currentCapsulePosition - lastMovementTargetPosition).Magnitude
                    local completed = movementComplete(handle)

                    if completed then
                        activeMove = nil
                        if playerDistance > capsuleFollowDistance then
                            log("info", "[Capsule] target moved old=" .. tostring(lastMovementTargetPosition)
                                .. " new=" .. tostring(currentCapsulePosition)
                                .. " delta=" .. string.format("%.2f", delta))
                            log("info", "[Capsule] retargeting")
                            local replacement, replacementError = beginMovement(currentCapsulePosition, "EVENT_CAPSULE", workerGeneration)
                            if not replacement then
                                return false, replacementError
                            end
                            handle = replacement
                            targetPosition = currentCapsulePosition
                            lastMovementTargetPosition = targetPosition
                            followingLogged = false
                            if record then
                                record.lastMovementTargetPosition = lastMovementTargetPosition
                            end
                        else
                            if not followingLogged then
                                log("info", "[Capsule] reached current target; capsule still live")
                                log("info", "[Capsule] following live capsule")
                                followingLogged = true
                            end
                            handle = nil
                        end
                    elseif delta >= capsuleRetargetDistance then
                        log("info", "[Capsule] target moved old=" .. tostring(lastMovementTargetPosition)
                            .. " new=" .. tostring(currentCapsulePosition)
                            .. " delta=" .. string.format("%.2f", delta))
                        log("info", "[Capsule] retargeting")
                        local replacement, replacementError = beginMovement(currentCapsulePosition, "EVENT_CAPSULE", workerGeneration)
                        if not replacement then
                            return false, replacementError
                        end
                        handle = replacement
                        targetPosition = currentCapsulePosition
                        lastMovementTargetPosition = targetPosition
                        followingLogged = false
                        if record then
                            record.lastMovementTargetPosition = lastMovementTargetPosition
                        end
                    elseif playerDistance <= capsuleFollowDistance then
                        if not followingLogged then
                            log("info", "[Capsule] following live capsule")
                            followingLogged = true
                        end
                    end
                end
            end
            wait(0.1)
        end
        cancelActiveMove("capsule_movement_timeout")
        return false, "capsule_movement_timeout"
    end

    local function acquire(owner, priority)
        if type(acquireMovement) ~= "function" then
            return true
        end
        local ok, result = pcall(acquireMovement, owner, priority)
        return ok and result ~= false
    end

    local function release(owner)
        if type(releaseMovement) == "function" then
            pcall(releaseMovement, owner)
        end
    end

    local function waitForPickup(instance, carryBefore, workerGeneration)
        local deadline = now() + pickupTimeout
        while isCurrentWorker(workerGeneration) and now() < deadline do
            local carry = carryCount()
            local gone = records[instance] and records[instance].disappearanceObserved or not isLiveCapsule(instance)
            if gone and carry and carry > (carryBefore or 0) then
                return true, carry
            end
            -- A root can disappear one replication step before scrapCarry updates.
            -- Keep the bounded wait open so both authoritative signals can correlate.
            wait(pollInterval)
        end
        local carry = carryCount()
        return false, carry
    end

    local function collectCapsule(instance, workerGeneration)
        if not isLiveCapsule(instance) then
            invalidateCapsule(instance, "not_live_before_move")
            return false
        end
        local position = getPosition(instance)
        if not position then
            invalidateCapsule(instance, "no_root_position")
            return false
        end
        local carryBefore = carryCount() or 0
        activeTarget = instance
        setStatus("MOVING_TO_CAPSULE")
        log("info", "[Capsule] target selected")
        log("info", "[Capsule] moving")
        if not acquire("EVENT_CAPSULE", 50) then
            setError("movement ownership unavailable")
            return false
        end
        local moved, moveReason = moveToCapsuleDynamic(instance, workerGeneration)
        release("EVENT_CAPSULE")
        if not moved then
            setError("capsule movement did not complete: " .. tostring(moveReason))
            return false
        end
        setStatus("WAITING_FOR_PICKUP_CONFIRMATION")
        local confirmed, carryAfter = waitForPickup(instance, carryBefore, workerGeneration)
        if confirmed then
            pendingCapsules[instance] = nil
            records[instance].disappearanceObserved = true
            records[instance].processed = true
            activeTarget = nil
            lastPickup = {
                instance = instance,
                carryBefore = carryBefore,
                carryAfter = carryAfter,
                delta = carryAfter - carryBefore,
                at = now(),
            }
            log("info", "[Capsule] pickup confirmed")
            log("info", "[Capsule] carry=" .. tostring(carryAfter))
            return true
        end
        invalidateCapsule(instance, "removed_without_local_carry_increase")
        return false
    end

    local function waitForDeposit(carryBefore, eventSerialAtStart, workerGeneration)
        local deadline = now() + depositTimeout
        local sawEvent = false
        while isCurrentWorker(workerGeneration) and now() < deadline do
            local carry = carryCount()
            if depositEventSerial > eventSerialAtStart then
                sawEvent = true
            end
            if sawEvent and carry ~= nil and carry <= carryBefore then
                return true, carry, "ScrapDeposited+carry_reconciled"
            end
            if carry ~= nil and carry < carryBefore then
                return true, carry, "carry_decreased"
            end
            wait(pollInterval)
        end
        return false, carryCount(), "deposit_timeout"
    end

    local function deposit(workerGeneration)
        local carryBefore = carryCount() or 0
        if carryBefore <= 0 then
            return true
        end
        local recycler = resolveOwnerRecycler()
        if not recycler then
            setStatus("OWNER_RECYCLER_NOT_FOUND")
            log("warn", "[Capsule] owner Recycler missing")
            return false
        end
        local approachAttempts = 0
        local maxApproachAttempts = 2
        while approachAttempts < maxApproachAttempts and isCurrentWorker(workerGeneration) do
            approachAttempts += 1
            recycler = resolveOwnerRecycler()
            local position, resolverSource, recyclerPivot = resolveRecyclerPosition(recycler)
            if not position then
                setError("owner Recycler has no verified target position")
                return false
            end
            log("info", "[Capsule] recycler pivot=" .. tostring(recyclerPivot and recyclerPivot.Position))
            log("info", "[Capsule] recycler target=" .. tostring(position))
            log("info", "[Capsule] recycler target source=" .. tostring(resolverSource))
            setStatus("RETURNING_TO_RECYCLER")
            log("info", "[Capsule] returning to Recycler")
            if not acquire("EVENT_CAPSULE", 50) then
                setError("movement ownership unavailable")
                return false
            end
            local moved, moveReason = moveToPosition(position, "EVENT_CAPSULE_RECYCLER", workerGeneration, function()
                return (carryCount() or 0) < maxCarry and next(pendingCapsules) ~= nil
            end)
            if not moved then
                release("EVENT_CAPSULE")
                if moveReason == "return_preempted" then
                    setStatus("RETURN_PREEMPTED")
                    log("info", "[Capsule] return preempted")
                    return true
                end
                setError("Recycler movement did not complete: " .. tostring(moveReason))
                return false
            end
            log("info", "[Capsule] recycler approach reached")
            setStatus("DEPOSITING")
            log("info", "[Capsule] deposit started")
            setStatus("WAITING_FOR_DEPOSIT_CONFIRMATION")
            local eventSerialAtStart = depositEventSerial
            depositAttemptActive = true
            local confirmed, carryAfter, evidence = waitForDeposit(carryBefore, eventSerialAtStart, workerGeneration)
            depositAttemptActive = false
            release("EVENT_CAPSULE")
            if confirmed then
                lastDeposit = {
                    carryBefore = carryBefore,
                    carryAfter = carryAfter,
                    evidence = evidence,
                    at = now(),
                }
                depositFailed = false
                lastDepositError = nil
                clearDepositFailureOverride("confirmed")
                log("info", "[Capsule] deposit confirmed")
                log("info", "[Capsule] carry=" .. tostring(carryAfter))
                removeDeadCapsules()
                if next(pendingCapsules) ~= nil then
                    log("info", "[Capsule] processing pending capsule")
                end
                return true
            end
            log("warn", "[Capsule] deposit confirmation timeout")
            if approachAttempts < maxApproachAttempts then
                log("warn", "[Capsule] recycler approach retry 1/1")
                wait(retryBackoff)
            end
        end
        local currentCarry = carryCount()
        depositFailed = true
        lastDepositError = "deposit confirmation timeout after bounded approach retries"
        depositFailureOverride = true
        log("warn", "[Capsule] DEPOSIT FAILED carry=" .. tostring(currentCarry))
        log("warn", "[Capsule] deposit failure override enabled")
        log("info", "[Capsule] resuming capsule collection")
        setError(lastDepositError)
        return false
    end

    local function reconcile(workerGeneration)
        removeDeadCapsules()
        ownerRecycler = resolveOwnerRecycler()
        local carry = carryCount() or 0
        if depositFailureOverride and carry < maxCarry then
            clearDepositFailureOverride("below_capacity")
        end
        if carry >= maxCarry and not depositFailureOverride then
            setStatus("FORCE_DEPOSIT")
            log("info", "[Capsule] force deposit")
            return "deposit"
        end
        if carry > 0 and next(pendingCapsules) == nil then
            return "deposit"
        end
        if next(pendingCapsules) ~= nil and not next(pausedReasons) then
            return "collect"
        end
        if carry > 0 and next(pausedReasons) == nil then
            return "deposit"
        end
        return "wait"
    end

    local function runWorker(workerGeneration)
        while isCurrentWorker(workerGeneration) do
            inProgress = false
            if next(pausedReasons) ~= nil and (carryCount() or 0) <= 0 then
                setStatus("PAUSED")
                wait(pollInterval)
            else
                local action = reconcile(workerGeneration)
                if action == "collect" then
                    local target = selectNearestCapsule()
                    if target then
                        inProgress = true
                        setStatus("TARGET_READY")
                        collectCapsule(target, workerGeneration)
                    else
                        wait(pollInterval)
                    end
                elseif action == "deposit" then
                    inProgress = true
                    deposit(workerGeneration)
                else
                    setStatus(next(pausedReasons) and "PAUSED" or "WAITING_FOR_CAPSULE")
                    wait(pollInterval)
                end
            end
            if lastError then
                wait(retryBackoff)
                lastError = nil
            end
        end
    end

    local function startWorker()
        if destroyed or not enabled or workerRunning then
            return
        end
        generation += 1
        activeWorkerGeneration = generation
        restartRequested = false
        workerRunning = true
        spawn(function()
            local workerGeneration = activeWorkerGeneration
            runWorker(workerGeneration)
            if activeWorkerGeneration == workerGeneration then
                workerRunning = false
            end
            if enabled and not destroyed and restartRequested then
                restartRequested = false
                startWorker()
            end
        end)
    end

    local function requestRestart(reason)
        if destroyed then
            return
        end
        restartRequested = true
        generation += 1
        cancelActiveMove(reason or "restart")
        wake()
        if enabled and not workerRunning then
            startWorker()
        end
    end

    local function setEnabled(value)
        if destroyed then
            return
        end
        local nextEnabled = value == true
        if enabled == nextEnabled then
            if nextEnabled then startWorker() end
            return
        end
        clearDepositFailureOverride("enabled_changed")
        enabled = nextEnabled
        generation += 1
        cancelActiveMove("enabled_changed")
        if enabled then
            restartRequested = workerRunning
            log("info", "[Capsule] enabled")
            setStatus("WAITING_FOR_CAPSULE")
            startWorker()
        else
            log("info", "[Capsule] disabled")
            setStatus("DISABLED")
        end
    end

    local function setPaused(reason, value)
        if type(reason) ~= "string" or reason == "" then
            reason = "external"
        end
        if value == true then
            pausedReasons[reason] = true
            log("info", "[Capsule] paused: " .. reason)
        else
            pausedReasons[reason] = nil
            log("info", "[Capsule] resumed: " .. reason)
        end
        wake()
        if enabled then startWorker() end
    end

    local function watchLoose(container)
        for _, connection in ipairs(looseConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(looseConnections)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            addCapsule(child)
        end
        signalChanged(container.ChildAdded, function(child)
            addCapsule(child)
        end, looseConnections)
        signalChanged(container.ChildRemoved, function(child)
            local record = records[child]
            if not record then
                return
            end
            if child == activeTarget and status == "WAITING_FOR_PICKUP_CONFIRMATION" then
                record.disappearanceObserved = true
                wake()
                return
            end
            if pendingCapsules[child] or activeTarget == child then
                invalidateCapsule(child, "removed_from_loose")
            end
        end, looseConnections)
    end

    local function watchPitScrap()
        local pitScrap = workspace:FindFirstChild("PitScrap")
        if not pitScrap then
            watchLoose(nil)
            return
        end
        watchLoose(pitScrap:FindFirstChild("Loose"))
        signalChanged(pitScrap.ChildAdded, function(child)
            if child.Name == "Loose" then
                watchLoose(child)
            end
        end)
    end

    local function watchCharacter()
        signalChanged(player.CharacterAdded, function()
            characterSerial += 1
            cancelActiveMove("character_reset")
            requestRestart("character_reset")
        end)
    end

    local function watchPlayerState()
        signalChanged(player:GetAttributeChangedSignal("Plot"), function()
            ownerRecycler = nil
            wake()
        end)
        lastObservedCarry = carryCount()
        signalChanged(player:GetAttributeChangedSignal("scrapCarry"), function()
            local previousCarry = lastObservedCarry
            local currentCarry = carryCount()
            lastObservedCarry = currentCarry
            if previousCarry ~= nil and currentCarry ~= nil and currentCarry < previousCarry then
                if not depositAttemptActive then
                    log("info", "[Capsule] external/manual deposit detected carry "
                        .. tostring(previousCarry) .. " -> " .. tostring(currentCarry))
                    clearDepositFailureOverride("manual_or_external")
                end
            end
            wake()
        end)
    end

    local function watchDeposit()
        if scrapDeposited then
            signalChanged(scrapDeposited, function()
                depositEventSerial += 1
                clearDepositFailureOverride("confirmed")
                wake()
            end)
        end
    end

    local function getPending()
        local result = {}
        for instance in pairs(pendingCapsules) do
            if isLiveCapsule(instance) then
                table.insert(result, instance)
            end
        end
        return result
    end

    local function getDebugState()
        local pending = getPending()
        return {
            status = status,
            carry = carryCount(),
            maxCarry = maxCarry,
            pendingCount = #pending,
            activeTarget = activeTarget,
            isReturning = status == "RETURNING_TO_RECYCLER",
            isDepositing = status == "DEPOSITING" or status == "WAITING_FOR_DEPOSIT_CONFIRMATION",
            depositFailed = depositFailed,
            depositFailureOverride = depositFailureOverride,
        }
    end

    local function destroy()
        if destroyed then
            return
        end
        destroyed = true
        enabled = false
        generation += 1
        cancelActiveMove("destroy")
        release("EVENT_CAPSULE")
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        for _, connection in ipairs(looseConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        table.clear(looseConnections)
        table.clear(pendingCapsules)
        activeTarget = nil
        setStatus("DISABLED")
    end

    watchPitScrap()
    signalChanged(workspace.ChildAdded, function(child)
        if child.Name == "PitScrap" then
            watchPitScrap()
        end
    end)
    signalChanged(workspace.ChildRemoved, function(child)
        if child.Name == "PitScrap" then
            watchLoose(nil)
        end
    end)
    watchCharacter()
    watchPlayerState()
    watchDeposit()

    return {
        setEnabled = setEnabled,
        isEnabled = function() return enabled end,
        setPaused = setPaused,
        isPaused = function() return next(pausedReasons) ~= nil end,
        getPauseReasons = function()
            local result = {}
            for reason in pairs(pausedReasons) do result[reason] = true end
            return result
        end,
        setMaxCarry = function(value)
            local parsed = tonumber(value)
            if parsed and parsed > 0 then maxCarry = parsed end
        end,
        getMaxCarry = function() return maxCarry end,
        getStatus = function() return status end,
        getCarryCount = carryCount,
        getActiveTarget = function() return activeTarget end,
        getPendingCapsules = getPending,
        getOwnerRecycler = function() return resolveOwnerRecycler() end,
        isReturning = function() return status == "RETURNING_TO_RECYCLER" end,
        isDepositing = function()
            return status == "DEPOSITING" or status == "WAITING_FOR_DEPOSIT_CONFIRMATION"
        end,
        getDebugState = getDebugState,
        getLastPickup = function() return lastPickup end,
        getLastDeposit = function() return lastDeposit end,
        getLastDepositError = function() return lastDepositError end,
        isDepositFailed = function() return depositFailed end,
        isDepositFailureOverride = function() return depositFailureOverride end,
        getLastError = function() return lastError end,
        resolveOwnerRecycler = resolveOwnerRecycler,
        cancelMovement = function(reason)
            cancelActiveMove(reason or "coordinator_preempt")
            return true
        end,
        destroy = destroy,
        -- Integration hooks for the future coordinator; no coordinator is installed here.
        acquireMovement = function(owner, priority) return acquire(owner, priority) end,
        releaseMovement = release,
    }
end

local globalEnv = (getgenv and getgenv()) or _G
globalEnv.UNO_EVENT_CAPSULE_COLLECTOR_FACTORY = createEventCapsuleCollector

return createEventCapsuleCollector
end


__unoRunStage("02 02_UNO_HUB_EVENT_CAPSULE_COLLECTOR_PHASE9(1).lua", __unoStage02)


local function __unoStage03()
-- AUTO ARENA
-- Standalone integration-ready backend.
-- This module automates only the outer Arena loop through injected normal game APIs.
-- It does not build teams, claim rewards, control abilities, click UI, or use coordinates.

local function createAutoArena(deps)
    deps = deps or {}

    local ArenaClient = assert(deps.ArenaClient, "ArenaClient is required")
    local ArenaState = assert(deps.ArenaState, "ArenaState is required")
    local ArenaRankSettings = deps.ArenaRankSettings
    local Remotes = deps.Remotes
    local Charm = deps.Charm
    local scheduler = deps.task or task
    local logger = deps.log

    local function log(level, message)
        if type(logger) == "function" then
            pcall(logger, level, message)
        end
    end

    local function wait(seconds)
        if scheduler and type(scheduler.wait) == "function" then
            scheduler.wait(seconds)
        end
    end

    local function spawn(fn)
        if scheduler and type(scheduler.spawn) == "function" then
            return scheduler.spawn(fn)
        end
        return nil
    end

    local function defer(fn)
        if scheduler and type(scheduler.defer) == "function" then
            return scheduler.defer(fn)
        end
        return spawn(fn)
    end

    local function now()
        return os.clock()
    end

    local suffixMultiplier = {
        [""] = 1,
        K = 1e3,
        M = 1e6,
        B = 1e9,
        T = 1e12,
        Qa = 1e15,
        Qi = 1e18,
        Sx = 1e21,
        Sp = 1e24,
        Oc = 1e27,
        No = 1e30,
        Dc = 1e33,
    }

    local function parsePower(value)
        if type(value) == "number" then
            if value == value and value ~= math.huge and value ~= -math.huge then
                return value
            end
            return nil
        end
        if type(value) ~= "string" then
            return nil
        end

        local numberText, suffix = string.match(value, "^%s*([%+%-]?[%d,]*%.?%d+)%s*([%a]*)%s*$")
        if not numberText then
            return nil
        end

        numberText = string.gsub(numberText, ",", "")
        local coefficient = tonumber(numberText)
        local multiplier = suffixMultiplier[suffix]
        if not coefficient or not multiplier then
            return nil
        end

        local normalized = coefficient * multiplier
        if normalized ~= normalized or normalized == math.huge or normalized == -math.huge then
            return nil
        end
        return normalized
    end

    local enabled = false
    local destroyed = false
    local generation = 0
    local workerRunning = false
    local activeWorkerGeneration = nil
    local restartRequested = false
    local processQueued = false
    local requestInProgress = false
    local requestKind = nil
    local pauseReasons = {}
    local eventPending = false
    local status = "DISABLED"
    local decision = "WAIT_FOR_ARENA"
    local lastError = nil
    local lastResult = nil
    local lastTrophyChange = nil
    local resultHandled = false
    local lastRefreshAt = 0
    local nextAllowedAt = 0
    local lastOpponentFingerprint = nil
    local lastSkipFingerprint = nil
    local refreshInterval = tonumber(deps.refreshInterval) or 10
    local refillPollInterval = tonumber(deps.refillPollInterval) or 10
    local startTimeout = tonumber(deps.startTimeout) or 12
    local reconcileTimeout = tonumber(deps.reconcileTimeout) or 8
    local failureBackoff = tonumber(deps.failureBackoff) or 3
    local connections = {}

    local function isCurrentWorker(workerGeneration)
        return enabled and not destroyed and workerGeneration == generation
    end

    local function readAtom(atom)
        if type(atom) ~= "function" then
            return nil
        end
        local ok, value = pcall(atom)
        return ok and value or nil
    end

    local function clone(value, depth)
        if type(value) ~= "table" or (depth or 0) > 4 then
            return value
        end
        local result = {}
        for key, item in pairs(value) do
            result[key] = clone(item, (depth or 0) + 1)
        end
        return result
    end

    local function getView()
        return readAtom(ArenaState.view)
    end

    local function getBattle()
        return readAtom(ArenaState.battle)
    end

    local function isBattling()
        if readAtom(ArenaState.battling) == true then
            return true
        end
        local battle = getBattle()
        return type(battle) == "table" and battle.phase == "started"
    end

    local function currentOpponent(view)
        if type(view) ~= "table" or type(view.opponents) ~= "table" then
            return nil, nil
        end
        local count = #view.opponents
        if count == 0 then
            return nil, nil
        end
        local cursor = tonumber(view.cursor) or 0
        local index = math.min(cursor + 1, count)
        return view.opponents[index], index
    end

    local function opponentId(opponent)
        if type(opponent) ~= "table" then
            return nil
        end
        return opponent.id or opponent.userId or opponent.name
    end

    local function opponentFingerprint(view)
        local opponent, index = currentOpponent(view)
        if not opponent then
            return nil
        end
        return table.concat({
            tostring(tonumber(view.cursor) or 0),
            tostring(index or 0),
            tostring(opponentId(opponent) or ""),
            tostring(opponent.power or ""),
        }, "|")
    end

    local function viewReady(view)
        if type(view) ~= "table" then
            return false
        end
        if view.available ~= true or view.unlocked ~= true then
            return false
        end
        local opponent = currentOpponent(view)
        if not opponent then
            return false
        end
        if readAtom(ArenaState.busy) == true or isBattling() then
            return false
        end
        if readAtom(ArenaState.result) ~= nil then
            return false
        end
        return true
    end

    local function safeRequest(kind, fn, ...)
        if requestInProgress then
            return false, nil, "request_in_progress"
        end
        requestInProgress = true
        requestKind = kind
        local ok, response = pcall(fn, ...)
        requestInProgress = false
        requestKind = nil
        if not ok then
            return false, nil, tostring(response)
        end
        if type(response) ~= "table" then
            return false, response, "invalid_response"
        end
        if response.ok ~= true then
            return false, response, tostring(response.error or "request_failed")
        end
        return true, response, nil
    end

    local function recordError(message)
        lastError = tostring(message)
        log("warn", "[Arena] " .. lastError)
        nextAllowedAt = now() + failureBackoff
    end

    local function refresh(force, ownerGeneration)
        if ownerGeneration and not isCurrentWorker(ownerGeneration) then
            return false
        end
        if requestInProgress then
            return false
        end
        if not force and now() - lastRefreshAt < refreshInterval then
            return true
        end
        local ok, response, errorMessage = safeRequest("refresh", ArenaClient.refresh)
        if ok then
            lastRefreshAt = now()
            lastError = nil
            return true, response
        end
        if errorMessage ~= "request_in_progress" then
            recordError("refresh failed: " .. tostring(errorMessage))
        end
        return false, response
    end

    local function ensureOfficialAuto()
        if not ArenaRankSettings or type(ArenaRankSettings.autoAbility) ~= "function" or type(ArenaRankSettings.setAutoAbility) ~= "function" then
            return true
        end
        local ok, current = pcall(ArenaRankSettings.autoAbility)
        if not ok or current == true then
            return ok
        end
        local setOk, setError = pcall(ArenaRankSettings.setAutoAbility, true)
        if not setOk then
            recordError("official Arena AUTO enable failed: " .. tostring(setError))
            return false
        end
        log("info", "[Arena] official AUTO enabled")
        return true
    end

    local function scheduleProcess()
        if not enabled or destroyed or processQueued then
            return
        end
        processQueued = true
        defer(function()
            processQueued = false
            if enabled and not destroyed then
                -- The worker owns all actions. This callback only wakes it by leaving
                -- the next loop iteration to observe authoritative state.
            end
        end)
    end

    local function waitForViewChange(oldFingerprint, timeout)
        local deadline = now() + timeout
        while enabled and not destroyed and now() < deadline do
            local view = getView()
            local fingerprint = opponentFingerprint(view)
            if fingerprint and fingerprint ~= oldFingerprint then
                return true
            end
            wait(0.25)
        end
        return false
    end

    local function reconcileAfterSkip(oldFingerprint, oldSkips, workerGeneration)
        local function changed(view)
            local fingerprint = opponentFingerprint(view)
            local skips = tonumber(view and view.skips) or 0
            return fingerprint and fingerprint ~= oldFingerprint or skips < oldSkips
        end

        local deadline = now() + reconcileTimeout
        while isCurrentWorker(workerGeneration) and now() < deadline do
            if changed(getView()) then
                log("info", "[Arena] opponent reconciled after Skip")
                return true
            end
            wait(0.25)
        end

        local refreshed = refresh(true, workerGeneration)
        if refreshed then
            deadline = now() + reconcileTimeout
            while isCurrentWorker(workerGeneration) and now() < deadline do
                if changed(getView()) then
                    log("info", "[Arena] opponent reconciled after refresh")
                    return true
                end
                wait(0.25)
            end
        end
        return false
    end

    local function waitForBattleStart(timeout, workerGeneration)
        local deadline = now() + timeout
        while isCurrentWorker(workerGeneration) and now() < deadline do
            if isBattling() then
                return true
            end
            local battle = getBattle()
            if type(battle) == "table" and battle.phase == "started" then
                return true
            end
            wait(0.25)
        end
        return false
    end

    local function handleResultReconciliation(workerGeneration)
        status = "RECONCILE"
        decision = "WAIT_FOR_ARENA"
        refresh(true, workerGeneration)
        if eventPending or next(pauseReasons) ~= nil then
            status = "PAUSED FOR EVENT"
            decision = "PAUSED_FOR_EVENT"
        else
            status = "RESULT"
        end
    end

    local function processCycle(workerGeneration)
        if not isCurrentWorker(workerGeneration) then
            return
        end
        if now() < nextAllowedAt then
            wait(math.min(0.5, math.max(0, nextAllowedAt - now())))
            return
        end

        if next(pauseReasons) ~= nil then
            if isBattling() then
                eventPending = true
                status = "EVENT PENDING"
                decision = "BATTLE_IN_PROGRESS"
            else
                status = "PAUSED FOR EVENT"
                decision = "PAUSED_FOR_EVENT"
            end
            wait(0.25)
            return
        end

        if eventPending and not isBattling() then
            if next(pauseReasons) == nil and readAtom(ArenaState.result) == nil then
                eventPending = false
            else
                status = "PAUSED FOR EVENT"
                decision = "PAUSED_FOR_EVENT"
                wait(0.25)
                return
            end
        end

        if isBattling() then
            status = "BATTLE"
            decision = "BATTLE_IN_PROGRESS"
            wait(0.25)
            return
        end

        if readAtom(ArenaState.result) ~= nil then
            if not resultHandled then
                resultHandled = true
                handleResultReconciliation(workerGeneration)
            end
            wait(0.5)
            return
        else
            resultHandled = false
        end

        local view = getView()
        if type(view) ~= "table" then
            status = "WAITING FOR ARENA"
            decision = "WAIT_FOR_ARENA"
            refresh(true, workerGeneration)
            wait(1)
            return
        end

        if view.available ~= true then
            status = "ARENA UNAVAILABLE"
            decision = "WAIT_FOR_ARENA"
            refresh(false, workerGeneration)
            wait(refreshInterval)
            return
        end
        if view.unlocked ~= true then
            status = "ARENA LOCKED"
            decision = "WAIT_FOR_ARENA"
            wait(refreshInterval)
            return
        end

        if not viewReady(view) then
            status = "WAITING FOR ARENA"
            decision = "WAIT_FOR_OPPONENT"
            refresh(false, workerGeneration)
            wait(1)
            return
        end

        local opponent, index = currentOpponent(view)
        local myPowerRaw = view.teamPower
        local opponentPowerRaw = opponent and opponent.power
        local myPower = parsePower(myPowerRaw)
        local opponentPower = parsePower(opponentPowerRaw)
        if not myPower or not opponentPower then
            status = "POWER UNAVAILABLE"
            decision = "POWER_UNAVAILABLE"
            recordError("power parse failed; my=" .. tostring(myPowerRaw) .. " opponent=" .. tostring(opponentPowerRaw))
            refresh(true, workerGeneration)
            wait(failureBackoff)
            return
        end

        local fingerprint = opponentFingerprint(view)
        if fingerprint ~= lastOpponentFingerprint then
            lastOpponentFingerprint = fingerprint
            log("info", "[Arena] opponent ready index=" .. tostring(index) .. " id=" .. tostring(opponentId(opponent)))
        end

        if opponentPower > myPower then
            if (tonumber(view.skips) or 0) <= 0 then
                status = "WAITING FOR SKIP REFILL"
                decision = "WAIT_FOR_SKIP_REFILL"
                log("info", "[Arena] waiting for skip refill; skips=" .. tostring(view.skips) .. "/" .. tostring(view.maxSkips))
                refresh(false, workerGeneration)
                wait(refillPollInterval)
                return
            end

            status = "SKIPPING"
            decision = "SKIP"
            local oldFingerprint = fingerprint
            local oldSkips = tonumber(view.skips) or 0
            if oldFingerprint == lastSkipFingerprint then
                wait(0.25)
                return
            end
            lastSkipFingerprint = oldFingerprint
            if not isCurrentWorker(workerGeneration) then
                return
            end
            local ok, _, errorMessage = safeRequest("skip", ArenaClient.skip)
            if not ok then
                lastSkipFingerprint = nil
                recordError("Skip failed: " .. tostring(errorMessage))
                refresh(true, workerGeneration)
                wait(failureBackoff)
                return
            end
            log("info", "[Arena] skip success")
            if not reconcileAfterSkip(oldFingerprint, oldSkips, workerGeneration) then
                recordError("Skip succeeded but opponent reconciliation timed out")
                -- Keep the old fingerprint locked. A later worker pass may observe
                -- the authoritative change; it must not send a duplicate Skip first.
                wait(failureBackoff)
                return
            end
            lastSkipFingerprint = nil
            return
        end

        decision = "BATTLE"
        if not isCurrentWorker(workerGeneration) then
            return
        end
        if not ensureOfficialAuto() then
            status = "ERROR / RETRY"
            wait(failureBackoff)
            return
        end

        status = "STARTING BATTLE"
        if not isCurrentWorker(workerGeneration) then
            return
        end
        local ok, _, errorMessage = safeRequest("fight", ArenaClient.fight)
        if not ok then
            recordError("Fight failed: " .. tostring(errorMessage))
            refresh(true, workerGeneration)
            wait(failureBackoff)
            return
        end
        log("info", "[Arena] fight requested")
        status = "BATTLE"
        if not waitForBattleStart(startTimeout, workerGeneration) then
            recordError("Fight returned success but battle start was not confirmed")
            refresh(true, workerGeneration)
            wait(failureBackoff)
            return
        end
        log("info", "[Arena] battle started")
    end

    local function worker(workerGeneration)
        if workerRunning then
            restartRequested = true
            return
        end
        workerRunning = true
        activeWorkerGeneration = workerGeneration
        while isCurrentWorker(workerGeneration) do
            local ok, errorMessage = pcall(processCycle, workerGeneration)
            if not ok then
                recordError("worker error: " .. tostring(errorMessage))
                wait(failureBackoff)
            end
            wait(0.1)
        end
        if activeWorkerGeneration == workerGeneration then
            activeWorkerGeneration = nil
        end
        workerRunning = false
        if restartRequested then
            restartRequested = false
            if enabled and not destroyed then
                local newestGeneration = generation
                spawn(function()
                    worker(newestGeneration)
                end)
            end
        end
    end

    local function startWorker()
        if not enabled or destroyed then
            return
        end
        if workerRunning then
            restartRequested = true
            return
        end
        local workerGeneration = generation
        spawn(function()
            worker(workerGeneration)
        end)
    end

    local function onBattleState(payload)
        if type(payload) ~= "table" then
            return
        end
        if payload.phase == "started" then
            status = "BATTLE"
            decision = "BATTLE_IN_PROGRESS"
            log("info", "[Arena] battle phase started")
        elseif payload.phase == "finished" then
            status = "WAITING FOR RESULT"
            decision = "BATTLE_IN_PROGRESS"
            log("info", "[Arena] battle phase finished; waiting for result")
        end
    end

    local function onBattleResult(payload)
        if type(payload) ~= "table" then
            return
        end
        lastResult = clone(payload)
        lastTrophyChange = payload.delta
        resultHandled = false
        status = "RESULT"
        decision = "WAIT_FOR_ARENA"
        log("info", "[Arena] battle result " .. (payload.won == true and "WIN" or "LOSS") .. " delta=" .. tostring(payload.delta))
        if eventPending or next(pauseReasons) ~= nil then
            status = "PAUSED FOR EVENT"
            decision = "PAUSED_FOR_EVENT"
        end
    end

    local function addConnection(connection)
        if connection then
            table.insert(connections, connection)
        end
        return connection
    end

    local function subscribeAtom(atom)
        if not Charm or type(Charm.subscribe) ~= "function" or type(atom) ~= "function" then
            return nil
        end
        local ok, connection = pcall(function()
            return Charm.subscribe(atom, scheduleProcess)
        end)
        return ok and connection or nil
    end

    local function subscribeRemote(definition, callback)
        if not Remotes or type(Remotes.onClient) ~= "function" or not definition then
            return nil
        end
        local ok, connection = pcall(function()
            return Remotes.onClient(definition, callback)
        end)
        if not ok then
            log("warn", "[Arena] event subscription failed: " .. tostring(connection))
            return nil
        end
        return connection
    end

    local function disconnectAll()
        for i = #connections, 1, -1 do
            local connection = connections[i]
            if typeof(connection) == "RBXScriptConnection" then
                pcall(function() connection:Disconnect() end)
            elseif type(connection) == "function" then
                pcall(connection)
            end
            connections[i] = nil
        end
    end

    local API = {}

    function API.setAutoArena(value)
        if destroyed then return false end
        local nextValue = value == true
        enabled = nextValue
        generation += 1
        if not enabled then
            status = "DISABLED"
            decision = "WAIT_FOR_ARENA"
            log("info", "[Arena] Auto Arena disabled; active battle is not cancelled")
            return true
        end
        if not ensureOfficialAuto() then
            enabled = false
            status = "ERROR / RETRY"
            return false
        end
        status = "WAITING FOR ARENA"
        decision = "WAIT_FOR_ARENA"
        nextAllowedAt = 0
        startWorker()
        log("info", "[Arena] Auto Arena enabled")
        return true
    end

    function API.isEnabled()
        return enabled
    end

    function API.setPaused(value, reason)
        reason = tostring(reason or "EXTERNAL_EVENT")
        if value == true then
            pauseReasons[reason] = true
            if isBattling() then
                eventPending = true
                status = "EVENT PENDING"
                decision = "BATTLE_IN_PROGRESS"
            elseif requestInProgress then
                status = "PAUSED FOR EVENT"
                decision = "PAUSED_FOR_EVENT"
            else
                status = "PAUSED FOR EVENT"
                decision = "PAUSED_FOR_EVENT"
            end
            log("info", "[Arena] paused " .. reason)
            return true
        end

        pauseReasons[reason] = nil
        if next(pauseReasons) == nil and not isBattling() and readAtom(ArenaState.result) == nil then
            eventPending = false
            status = enabled and "RECONCILE" or "DISABLED"
            decision = enabled and "WAIT_FOR_ARENA" or "WAIT_FOR_ARENA"
            nextAllowedAt = 0
            if enabled then
                -- The worker owns Arena requests. If another request is active,
                -- leave reconciliation to that worker after it returns.
                if not requestInProgress then
                    refresh(true)
                end
                startWorker()
            end
        end
        return true
    end

    function API.isPaused()
        return next(pauseReasons) ~= nil
    end

    function API.getPauseReasons()
        return clone(pauseReasons)
    end

    function API.isBattling()
        return isBattling()
    end

    function API.isEventPending()
        return eventPending
    end

    function API.getStatus()
        return status
    end

    function API.getMyPower()
        local view = getView()
        return view and view.teamPower or nil
    end

    function API.getOpponentPower()
        local view = getView()
        local opponent = currentOpponent(view)
        return opponent and opponent.power or nil
    end

    function API.getOpponent()
        local view = getView()
        local opponent = currentOpponent(view)
        return clone(opponent)
    end

    function API.getSkips()
        local view = getView()
        return view and view.skips or nil
    end

    function API.getMaxSkips()
        local view = getView()
        return view and view.maxSkips or nil
    end

    function API.getDecision()
        return decision
    end

    function API.getCurrentRank()
        local view = getView()
        return view and (view.rankId or view.rank) or nil
    end

    function API.getTrophies()
        local view = getView()
        return view and view.trophies or nil
    end

    function API.getSeasonWins()
        local view = getView()
        return view and view.wins or nil
    end

    function API.getLastResult()
        return clone(lastResult)
    end

    function API.getLastTrophyChange()
        return lastTrophyChange
    end

    function API.getLastError()
        return lastError
    end

    function API.refreshNow()
        return refresh(true)
    end

    function API.destroy()
        if destroyed then return end
        destroyed = true
        enabled = false
        generation += 1
        disconnectAll()
        status = "DISABLED"
        decision = "WAIT_FOR_ARENA"
        log("info", "[Arena] Auto Arena destroyed; no active battle was cancelled")
    end

    if Remotes and Remotes.defs then
        addConnection(subscribeRemote(Remotes.defs.ArenaBattleState, onBattleState))
        addConnection(subscribeRemote(Remotes.defs.ArenaBattleResult, onBattleResult))
    end
    for _, name in ipairs({ "view", "loading", "busy", "picking", "battling", "result", "battle" }) do
        addConnection(subscribeAtom(ArenaState[name]))
    end

    return API
end

-- Integration example:
-- local AutoArenaFeature = createAutoArena({
--     ArenaClient = Integration.modules.ArenaClient,
--     ArenaState = Integration.modules.ArenaState,
--     ArenaRankSettings = Integration.modules.ArenaRankSettings,
--     Remotes = Integration.modules.Remotes,
--     Charm = Integration.modules.Charm,
--     log = log,
-- })
-- AutoArenaFeature.setAutoArena(true)

local globalEnv = (getgenv and getgenv()) or _G
globalEnv.UNO_AUTO_ARENA_FACTORY = createAutoArena
return createAutoArena
end


__unoRunStage("03 03_UNO_HUB_AUTO_ARENA_PHASE9(1).lua", __unoStage03)


local function __unoStage04()
-- KRAKEN EGG COLLECTOR
-- EXPERIMENTAL — SOURCE VERIFIED, RUNTIME UNVALIDATED
-- Standalone integration-ready backend. No UI, Config Manager, Auto Arena, or golden-egg fight integration.
-- The injected fireClientSignal dependency must map to the verified Event contract:
-- LiveEventClientSignal({ eventName = "kraken", action = action, args = { eggId } })

local function createKrakenEggCollector(deps)
    assert(type(deps) == "table", "createKrakenEggCollector requires deps")

    local taskWait = deps.taskWait or task.wait
    local now = deps.now or os.clock
    local log = deps.log or function(message) print("[Kraken] " .. tostring(message)) end

    local getEventState = deps.getKrakenEventState
    local isEventActive = deps.isKrakenActive
    local getLandedEggs = deps.getLandedEggs
    local getEggId = deps.getEggId
    local getEggPosition = deps.getEggPosition
    local getEggExpiry = deps.getEggExpiry
    local isEggReady = deps.isEggReady
    local moveTo = deps.moveTo
    local fireClientSignal = deps.fireClientSignal
    local onLiveEventSignal = deps.onLiveEventSignal

    local enabled = false
    local destroyed = false
    local workerRunning = false
    local requestInProgress = false
    local generation = 0
    local restartRequested = false
    local signalDirty = true
    local signalDisconnect = nil
    local target = nil
    local pending = {}
    local attempted = {}
    local completed = {}
    local lastSuccess = nil
    local lastError = nil
    local status = "DISABLED"
    local eventState = nil
    local retryAt = 0
    local openDeadline = 0
    local claimDeadline = 0
    local targetReward = nil
    local pauseReasons = {}

    local function setStatus(nextStatus, detail)
        if status == nextStatus and detail == nil then return end
        status = nextStatus
        if detail then
            log("[Kraken] " .. tostring(nextStatus) .. " " .. tostring(detail))
        else
            log("[Kraken] " .. tostring(nextStatus))
        end
    end

    local function safeCall(callback, ...)
        if type(callback) ~= "function" then
            return false, "dependency unavailable"
        end
        local args = table.pack(...)
        return pcall(function()
            return callback(table.unpack(args, 1, args.n))
        end)
    end

    local function currentWorker(myGeneration)
        return enabled and not destroyed and myGeneration == generation
    end

    local function clearTarget()
        target = nil
        targetReward = nil
        openDeadline = 0
        claimDeadline = 0
        requestInProgress = false
    end

    local function eventActive()
        local ok, value = safeCall(isEventActive)
        if ok and type(value) == "boolean" then
            return value
        end
        if type(getEventState) == "function" then
            local stateOk, state = safeCall(getEventState)
            if stateOk and type(state) == "table" then
                eventState = state
                return state.active == true or state.id == "kraken" or state.eventName == "kraken"
            end
        end
        return false
    end

    local function snapshotEventState()
        if type(getEventState) == "function" then
            local ok, value = safeCall(getEventState)
            if ok then eventState = value end
        end
        return eventState
    end

    local function modelValid(item, expectedId)
        if not item or not item.Parent then return false end
        local ok, id = safeCall(getEggId, item)
        if not ok or id == nil or tostring(id) ~= tostring(expectedId) then return false end
        local expiryOk, expiresAt = safeCall(getEggExpiry, item)
        if expiryOk and type(expiresAt) == "number" and expiresAt <= os.time() then return false end
        if type(isEggReady) == "function" then
            local readyOk, ready = safeCall(isEggReady, item)
            if readyOk and ready == false then return false end
        end
        return true
    end

    local function scanTargets()
        local found = {}
        local ok, eggs = safeCall(getLandedEggs)
        if not ok or type(eggs) ~= "table" then
            return found
        end
        local characterPosition = nil
        if type(deps.getPlayerPosition) == "function" then
            local positionOk, position = safeCall(deps.getPlayerPosition)
            if positionOk then characterPosition = position end
        end
        for _, item in pairs(eggs) do
            if item and item.Parent then
                local idOk, id = safeCall(getEggId, item)
                if idOk and id ~= nil then
                    id = tostring(id)
                    local expiryOk, expiresAt = safeCall(getEggExpiry, item)
                    if not (expiryOk and type(expiresAt) == "number" and expiresAt <= os.time()) then
                        local positionOk, position = safeCall(getEggPosition, item)
                        local distance = math.huge
                        if positionOk and characterPosition and position then
                            local delta = position - characterPosition
                            distance = delta.Magnitude
                        end
                        found[id] = {
                            id = id,
                            instance = item,
                            position = positionOk and position or nil,
                            distance = distance,
                            expiresAt = expiryOk and expiresAt or nil,
                        }
                    end
                end
            end
        end
        pending = found
        return found
    end

    local function chooseTarget(found)
        local best = nil
        for id, item in pairs(found) do
            if not completed[id] and not attempted[id] then
                if not best or item.distance < best.distance then
                    best = item
                end
            end
        end
        return best
    end

    local function fireAction(action, eggId)
        if requestInProgress then
            return false, "request already in progress"
        end
        if type(fireClientSignal) ~= "function" then
            return false, "fireClientSignal dependency unavailable"
        end
        requestInProgress = true
        local ok, result = safeCall(fireClientSignal, {
            eventName = "kraken",
            action = action,
            args = { eggId },
        })
        requestInProgress = false
        if not ok then
            return false, result
        end
        if result == false then
            return false, "action dependency rejected request"
        end
        return true
    end

    local function invalidate(reason)
        if target then
            log("[Kraken] target invalid id=" .. tostring(target.id) .. " reason=" .. tostring(reason))
        end
        clearTarget()
        retryAt = now() + 1
        setStatus("TARGET_INVALID", reason)
        signalDirty = true
    end

    local function handleEggRoll(data)
        if type(data) ~= "table" or data.id == nil then return end
        local id = tostring(data.id)
        if not target or tostring(target.id) ~= id then
            return
        end
        if status ~= "WAITING_FOR_EGG_ROLL" then return end
        targetReward = data.reward
        local ok, result = fireAction("claimEgg", id)
        if not ok then
            lastError = "claimEgg: " .. tostring(result)
            clearTarget()
            retryAt = now() + 3
            setStatus("ERROR_RETRY", lastError)
            return
        end
        attempted[id] = true
        claimDeadline = now() + 12
        setStatus("WAITING_FOR_CONFIRMATION", "id=" .. id)
        log("[Kraken] interaction accepted id=" .. id .. " reward=" .. tostring(data.reward))
    end

    local function onSignal(payload)
        if type(payload) ~= "table" or payload.eventName ~= "kraken" then return end
        signalDirty = true
        local action = payload.action
        local args = payload.args
        local data = type(args) == "table" and args[1] or nil
        if action == "eggRoll" then
            handleEggRoll(data)
        end
    end

    local function attachSignalObserver()
        if signalDisconnect or type(onLiveEventSignal) ~= "function" then return end
        local ok, disconnect = safeCall(onLiveEventSignal, onSignal)
        if ok and type(disconnect) == "function" then
            signalDisconnect = disconnect
        elseif ok and disconnect == nil then
            signalDisconnect = function() end
        end
    end

    local function detachSignalObserver()
        if signalDisconnect then
            pcall(signalDisconnect)
            signalDisconnect = nil
        end
    end

    local function finishIfRemoved(myGeneration)
        if not target or not currentWorker(myGeneration) then return false end
        if target.instance and target.instance.Parent then
            local idOk, currentId = safeCall(getEggId, target.instance)
            if idOk and currentId ~= nil and tostring(currentId) == tostring(target.id) then
                return false
            end
        end
        completed[target.id] = true
        lastSuccess = {
            eggId = target.id,
            reward = targetReward,
            at = now(),
        }
        log("[Kraken] success id=" .. tostring(target.id))
        clearTarget()
        signalDirty = true
        setStatus("SEARCH_NEXT")
        return true
    end

    local function waitForMove(myGeneration, item)
        if type(moveTo) ~= "function" then
            return false, "moveTo dependency unavailable"
        end
        if not item.position then
            return false, "egg position unavailable"
        end
        local ok, result = safeCall(moveTo, item.position, {
            mode = "Tween",
            stopDistance = 12,
            maxInteractionDistance = 13,
            target = item.instance,
            eggId = item.id,
            isCurrent = function() return currentWorker(myGeneration) and modelValid(item.instance, item.id) end,
        })
        if not currentWorker(myGeneration) then
            return false, "worker superseded"
        end
        if not ok then return false, result end
        if result == false then return false, "movement rejected" end
        return true
    end

    local function work(myGeneration)
        while currentWorker(myGeneration) do
            if next(pauseReasons) ~= nil then
                setStatus("PAUSED_FOR_EVENT")
                taskWait(0.35)
                continue
            end
            snapshotEventState()
            if not eventActive() then
                clearTarget()
                setStatus("WAITING_FOR_KRAKEN")
                taskWait(1)
            elseif now() < retryAt then
                taskWait(math.min(1, retryAt - now()))
            elseif target and status == "WAITING_FOR_EGG_ROLL" then
                if finishIfRemoved(myGeneration) then
                    continue
                end
                if now() >= openDeadline then
                    lastError = "eggRoll timeout for " .. tostring(target.id)
                    attempted[target.id] = true
                    clearTarget()
                    retryAt = now() + 4
                    setStatus("ERROR_RETRY", lastError)
                else
                    taskWait(0.25)
                end
            elseif target and status == "WAITING_FOR_CONFIRMATION" then
                if finishIfRemoved(myGeneration) then
                    continue
                end
                if now() >= claimDeadline then
                    lastError = "claim confirmation timeout for " .. tostring(target.id)
                    clearTarget()
                    retryAt = now() + 5
                    setStatus("ERROR_RETRY", lastError)
                else
                    taskWait(0.25)
                end
            else
                local found = scanTargets()
                if target and not modelValid(target.instance, target.id) then
                    invalidate("despawned, expired, or no longer landed")
                elseif not target then
                    local selected = chooseTarget(found)
                    if selected then
                        target = selected
                        setStatus("TARGET_READY", "id=" .. selected.id)
                        log("[Kraken] target selected id=" .. selected.id)
                        setStatus("MOVING_TO_EGG", "id=" .. selected.id)
                        local moved, moveError = waitForMove(myGeneration, selected)
                        if not moved then
                            lastError = tostring(moveError)
                            clearTarget()
                            retryAt = now() + 3
                            setStatus("ERROR_RETRY", lastError)
                        elseif modelValid(selected.instance, selected.id) and eventActive() then
                            local actionOk, actionError = fireAction("openEgg", selected.id)
                            if actionOk then
                                openDeadline = now() + 8
                                setStatus("WAITING_FOR_EGG_ROLL", "id=" .. selected.id)
                                log("[Kraken] interaction started id=" .. selected.id)
                            else
                                lastError = "openEgg: " .. tostring(actionError)
                                attempted[selected.id] = true
                                clearTarget()
                                retryAt = now() + 3
                                setStatus("ERROR_RETRY", lastError)
                            end
                        else
                            invalidate("target invalid after movement")
                        end
                    else
                        setStatus("WAITING_FOR_LANDED_EGG")
                        taskWait(signalDirty and 0.25 or 1)
                    end
                end
            end
            signalDirty = false
        end
        workerRunning = false
        if enabled and not destroyed and generation ~= myGeneration then
            restartRequested = false
            task.spawn(function()
                local currentGeneration = generation
                if enabled and not workerRunning then
                    workerRunning = true
                    work(currentGeneration)
                end
            end)
        end
    end

    local api = {}

    function api.setEnabled(value)
        if destroyed then return false end
        value = value == true
        if enabled == value then
            if value and not workerRunning then restartRequested = true end
            return true
        end
        enabled = value
        generation += 1
        restartRequested = value
        if enabled then
            lastError = nil
            attachSignalObserver()
            if not workerRunning then
                workerRunning = true
                local myGeneration = generation
                task.spawn(function() work(myGeneration) end)
            end
        else
            detachSignalObserver()
            clearTarget()
            setStatus("DISABLED")
        end
        return true
    end

    function api.isEnabled()
        return enabled and not destroyed
    end
    function api.setPaused(reason, value)
        reason = tostring(reason or "EXTERNAL_EVENT")
        if value == true then
            pauseReasons[reason] = true
        else
            pauseReasons[reason] = nil
        end
        generation += 1
        restartRequested = enabled
        return true
    end
    function api.isPaused()
        return next(pauseReasons) ~= nil
    end
    function api.getPauseReasons()
        local result = {}
        for reason in pairs(pauseReasons) do result[reason] = true end
        return result
    end
    function api.cancelMovement()
        generation += 1
        restartRequested = enabled
        return true
    end

    function api.getStatus()
        return status
    end

    function api.getKrakenEventState()
        snapshotEventState()
        return eventState
    end

    function api.getActiveTarget()
        if not target then return nil end
        return {
            eggId = target.id,
            instance = target.instance,
            position = target.position,
            status = status,
        }
    end

    function api.getPendingEggs()
        local result = {}
        for id, item in pairs(pending) do
            result[id] = {
                eggId = id,
                instance = item.instance,
                position = item.position,
                distance = item.distance,
                completed = completed[id] == true,
                attempted = attempted[id] == true,
            }
        end
        return result
    end

    function api.getLastEggId()
        return lastSuccess and lastSuccess.eggId or nil
    end

    function api.getLastSuccess()
        return lastSuccess
    end

    function api.getLastError()
        return lastError
    end

    function api.destroy()
        if destroyed then return end
        destroyed = true
        enabled = false
        generation += 1
        table.clear(pauseReasons)
        detachSignalObserver()
        clearTarget()
        setStatus("DISABLED")
    end

    api.isWorkerRunning = function() return workerRunning end
    api.isRequestInProgress = function() return requestInProgress end
    api.getGeneration = function() return generation end
    api.getAttempted = function() return attempted end
    api.getCompleted = function() return completed end
    api.isRestartRequested = function() return restartRequested end

    return api
end

local globalEnv = (getgenv and getgenv()) or _G
globalEnv.UNO_KRAKEN_EGG_COLLECTOR_FACTORY = createKrakenEggCollector
return createKrakenEggCollector
end


__unoRunStage("04 04_UNO_HUB_KRAKEN_EGG_COLLECTOR_PHASE9(1).lua", __unoStage04)


local function __unoStage05()
-- EVENT PRIORITY COORDINATOR
-- Standalone Phase 7 arbitration module.
-- This file coordinates injected feature adapters only; it does not implement feature logic.

local PRIORITY = {
    HOT_EGG = 100,
    EVENT_CAPSULE = 80,
    UFO_ASCENSION = 75,
    KRAKEN_EGG = 70,
    AUTO_ARENA = 40,
    NORMAL_FARM = 10,
}

local DEFAULT_FEATURES = {
    "HOT_EGG",
    "EVENT_CAPSULE",
    "UFO_ASCENSION",
    "KRAKEN_EGG",
    "AUTO_ARENA",
    "NORMAL_FARM",
}

local function createEventPriorityCoordinator(deps)
    deps = type(deps) == "table" and deps or {}
    local logger = deps.log or deps.logger
    local features = deps.features or {}
    local featureState = {}
    local currentMovementOwner = nil
    local currentPriority = nil
    local lastPreemption = nil
    local lastRelease = nil
    local lastError = nil
    local destroyed = false

    local function log(level, message)
        if type(logger) == "function" then
            pcall(logger, level, message)
        end
    end

    local function now()
        return os.clock()
    end

    local function adapter(owner)
        local feature = features[owner]
        return type(feature) == "table" and feature or {}
    end

    local function ensureFeature(owner, priority)
        if type(owner) ~= "string" or owner == "" then
            return nil
        end
        local state = featureState[owner]
        if not state then
            state = {
                owner = owner,
                priority = tonumber(priority) or tonumber(PRIORITY[owner]) or 0,
                requested = false,
                enabled = true,
                critical = false,
                pauseReasons = {},
                eventPending = false,
                requestOptions = {},
            }
            featureState[owner] = state
        elseif priority ~= nil then
            state.priority = tonumber(priority) or state.priority
        end
        return state
    end

    for _, owner in ipairs(DEFAULT_FEATURES) do
        ensureFeature(owner, PRIORITY[owner])
    end
    for owner, feature in pairs(features) do
        ensureFeature(owner, type(feature) == "table" and feature.priority or nil)
    end

    local function isCriticalInternal(owner)
        local state = ensureFeature(owner)
        if not state then
            return false
        end
        if state.critical then
            return true
        end
        local feature = adapter(owner)
        if type(feature.isCritical) == "function" then
            local ok, result = pcall(feature.isCritical)
            return ok and result == true
        end
        return false
    end

    local function setFeaturePaused(owner, reason, value)
        local state = ensureFeature(owner)
        if not state then
            return false
        end
        reason = tostring(reason or "COORDINATOR")
        if value == true then
            if state.pauseReasons[reason] then
                return true
            end
            state.pauseReasons[reason] = true
            local feature = adapter(owner)
            if type(feature.setPaused) == "function" then
                local ok, result = pcall(feature.setPaused, reason, true)
                if not ok then
                    lastError = "pause failed for " .. owner .. ": " .. tostring(result)
                    log("warn", "[Coordinator] " .. lastError)
                    return false
                end
            end
            log("info", "[Coordinator] paused " .. owner .. " reason=" .. reason)
            return true
        end
        if not state.pauseReasons[reason] then
            return true
        end
        state.pauseReasons[reason] = nil
        local feature = adapter(owner)
        if type(feature.setPaused) == "function" then
            local ok, result = pcall(feature.setPaused, reason, false)
            if not ok then
                lastError = "resume failed for " .. owner .. ": " .. tostring(result)
                log("warn", "[Coordinator] " .. lastError)
                return false
            end
        end
        log("info", "[Coordinator] resumed " .. owner)
        return true
    end

    local function setArenaEventPending(value, reason)
        local state = ensureFeature("AUTO_ARENA", PRIORITY.AUTO_ARENA)
        if not state then
            return
        end
        state.eventPending = value == true
        local feature = adapter("AUTO_ARENA")
        if type(feature.setEventPending) == "function" then
            pcall(feature.setEventPending, state.eventPending, reason)
        elseif type(feature.markEventPending) == "function" then
            pcall(feature.markEventPending, state.eventPending, reason)
        end
    end

    local function clearOwner(reason)
        local oldOwner = currentMovementOwner
        if not oldOwner then
            return
        end
        currentMovementOwner = nil
        currentPriority = nil
        lastRelease = {
            owner = oldOwner,
            reason = reason,
            at = now(),
        }
        if oldOwner == "AUTO_ARENA" then
            setArenaEventPending(false, reason)
        end
        log("info", "[Coordinator] released " .. oldOwner)
    end

    local function cancelForPreemption(owner, byOwner)
        local feature = adapter(owner)
        if type(feature.cancelMovement) == "function" then
            local ok, result = pcall(feature.cancelMovement, byOwner)
            if not ok then
                lastError = "cancel failed for " .. owner .. ": " .. tostring(result)
                log("warn", "[Coordinator] " .. lastError)
                return false
            end
        end
        return true
    end

    local arbitrate

    local function syncPauses()
        if not currentMovementOwner then
            for owner, state in pairs(featureState) do
                for reason in pairs(state.pauseReasons) do
                    if string.sub(reason, 1, 17) == "COORDINATOR_OWNER:" then
                        setFeaturePaused(owner, reason, false)
                    end
                end
            end
            return
        end
        local ownerState = ensureFeature(currentMovementOwner, currentPriority)
        for owner, state in pairs(featureState) do
            if owner ~= currentMovementOwner then
                local desiredReason = "COORDINATOR_OWNER:" .. currentMovementOwner
                local staleReasons = {}
                for reason in pairs(state.pauseReasons) do
                    if string.sub(reason, 1, 18) == "COORDINATOR_OWNER:" and reason ~= desiredReason then
                        table.insert(staleReasons, reason)
                    end
                end
                for _, reason in ipairs(staleReasons) do
                    setFeaturePaused(owner, reason, false)
                end
                if state.priority < ownerState.priority then
                    setFeaturePaused(owner, desiredReason, true)
                else
                    setFeaturePaused(owner, desiredReason, false)
                end
            end
        end
    end

    local function transferTo(owner, reason)
        local state = ensureFeature(owner)
        if not state then
            return false
        end
        currentMovementOwner = owner
        currentPriority = state.priority
        if owner == "AUTO_ARENA" then
            setArenaEventPending(false, reason)
        end
        local stateForOwner = ensureFeature(owner)
        if stateForOwner then
            stateForOwner.eventPending = false
        end
        syncPauses()
        log("info", "[Coordinator] owner " .. tostring(reason and reason.oldOwner or "NONE")
            .. " -> " .. owner)
        return true
    end

    arbitrate = function()
        if destroyed then
            return false
        end
        local bestOwner = nil
        local bestPriority = -math.huge
        for owner, state in pairs(featureState) do
            if state.requested and state.enabled and state.priority > bestPriority then
                bestOwner = owner
                bestPriority = state.priority
            end
        end
        if currentMovementOwner then
            local currentState = ensureFeature(currentMovementOwner)
            if currentState and currentState.requested and currentState.enabled then
                if bestOwner == currentMovementOwner or bestPriority <= (currentPriority or -math.huge) then
                    syncPauses()
                    return true
                end
                if isCriticalInternal(currentMovementOwner) then
                    if bestOwner then
                        currentState.eventPending = true
                        if currentMovementOwner == "AUTO_ARENA" then
                            setArenaEventPending(true, bestOwner)
                        end
                        log("info", "[Coordinator] current owner critical; " .. bestOwner .. " pending")
                    end
                    syncPauses()
                    return true
                end
                local oldOwner = currentMovementOwner
                lastPreemption = {
                    from = oldOwner,
                    to = bestOwner,
                    at = now(),
                }
                log("info", "[Coordinator] preempt requested " .. bestOwner)
                cancelForPreemption(oldOwner, bestOwner)
                setFeaturePaused(oldOwner, "COORDINATOR_OWNER:" .. bestOwner, true)
                clearOwner({ oldOwner = oldOwner, reason = "preempted_by_" .. bestOwner })
            else
                clearOwner("stale_owner")
            end
        end
        if bestOwner then
            return transferTo(bestOwner, { oldOwner = lastRelease and lastRelease.owner or "NONE" })
        end
        syncPauses()
        return true
    end

    local function requestPriority(owner, priority, options)
        if destroyed then
            return false
        end
        local state = ensureFeature(owner, priority)
        if not state then
            return false
        end
        options = type(options) == "table" and options or {}
        state.requested = true
        state.enabled = options.enabled ~= false
        state.requestOptions = options
        if options.critical ~= nil then
            state.critical = options.critical == true
        end
        log("info", "[Coordinator] request " .. owner .. " priority=" .. tostring(state.priority))
        return arbitrate()
    end

    local function releasePriority(owner)
        local state = ensureFeature(owner)
        if not state then
            return false
        end
        state.requested = false
        state.requestOptions = {}
        if owner == "AUTO_ARENA" then
            setArenaEventPending(false, "release")
        end
        if currentMovementOwner == owner then
            clearOwner("releasePriority")
        end
        return arbitrate()
    end

    local function acquireMovement(owner, priority)
        return requestPriority(owner, priority)
    end

    local function releaseMovement(owner)
        return releasePriority(owner)
    end

    local function setFeatureEnabled(owner, value)
        local state = ensureFeature(owner)
        if not state then
            return false
        end
        state.enabled = value == true
        if not state.enabled and currentMovementOwner == owner then
            clearOwner("feature_disabled")
        end
        return arbitrate()
    end

    local function setCritical(owner, value)
        local state = ensureFeature(owner)
        if not state then
            return false
        end
        state.critical = value == true
        if not state.critical then
            if owner == "AUTO_ARENA" then
                setArenaEventPending(false, "critical_ended")
            end
            log("info", "[Coordinator] critical ended " .. owner)
        end
        return arbitrate()
    end

    local function isOwnerActive(owner)
        return currentMovementOwner == owner
    end

    local function getCurrentOwner()
        return currentMovementOwner
    end

    local function getCurrentPriority()
        return currentPriority
    end

    local function getPendingRequests()
        local result = {}
        for owner, state in pairs(featureState) do
            result[owner] = {
                requested = state.requested,
                priority = state.priority,
                critical = isCriticalInternal(owner),
                eventPending = state.eventPending,
            }
        end
        return result
    end

    local function getPausedFeatures()
        local result = {}
        for owner, state in pairs(featureState) do
            local reasons = {}
            for reason in pairs(state.pauseReasons) do
                table.insert(reasons, reason)
            end
            result[owner] = reasons
        end
        return result
    end

    local function getDebugState()
        return {
            owner = currentMovementOwner,
            priority = currentPriority,
            pending = getPendingRequests(),
            critical = (function()
                local result = {}
                for owner in pairs(featureState) do result[owner] = isCriticalInternal(owner) end
                return result
            end)(),
            paused = getPausedFeatures(),
            eventPending = (function()
                local result = {}
                for owner, state in pairs(featureState) do result[owner] = state.eventPending end
                return result
            end)(),
            lastPreemption = lastPreemption,
            lastRelease = lastRelease,
            lastError = lastError,
        }
    end

    local function destroy()
        if destroyed then
            return
        end
        destroyed = true
        for owner, state in pairs(featureState) do
            for reason in pairs(state.pauseReasons) do
                local feature = adapter(owner)
                if type(feature.setPaused) == "function" then
                    pcall(feature.setPaused, reason, false)
                end
            end
            state.pauseReasons = {}
        end
        setArenaEventPending(false, "destroy")
        currentMovementOwner = nil
        currentPriority = nil
        log("info", "[Coordinator] destroyed")
    end

    return {
        PRIORITY = PRIORITY,
        requestPriority = requestPriority,
        releasePriority = releasePriority,
        acquireMovement = acquireMovement,
        releaseMovement = releaseMovement,
        setFeatureEnabled = setFeatureEnabled,
        setCritical = setCritical,
        isCritical = isCriticalInternal,
        isOwnerActive = isOwnerActive,
        getCurrentOwner = getCurrentOwner,
        getCurrentPriority = getCurrentPriority,
        getPendingRequests = getPendingRequests,
        getPausedFeatures = getPausedFeatures,
        getStatus = getDebugState,
        getDebugState = getDebugState,
        destroy = destroy,
    }
end

local globalEnv = (getgenv and getgenv()) or _G
globalEnv.UNO_EVENT_PRIORITY_COORDINATOR_FACTORY = createEventPriorityCoordinator

globalEnv.UNO_EVENT_PRIORITY = PRIORITY

return createEventPriorityCoordinator

end

__unoRunStage("05 05_UNO_HUB_EVENT_PRIORITY_COORDINATOR_PHASE9(1).lua", __unoStage05)


local function __unoStage06()
-- UNO HUB PRIORITY INTEGRATION
-- Phase 8 thin compatibility bridge. It does not duplicate feature logic.

local function createUNOHubPriorityIntegration(deps)
    deps = type(deps) == "table" and deps or {}
    local env = (getgenv and getgenv()) or _G
    local runtime = deps.runtime or env.UNO_HUB_RUNTIME
    local coordinatorFactory = deps.coordinatorFactory or env.UNO_EVENT_PRIORITY_COORDINATOR_FACTORY
    local scheduler = deps.task or task
    local logger = deps.log or function(level, message)
        if runtime and runtime.State and runtime.State.log then
            table.insert(runtime.State.log, 1, {
                t = os.clock(),
                level = level,
                text = tostring(message),
            })
        end
    end

    assert(type(runtime) == "table", "UNOHUB runtime bridge is required")
    assert(type(coordinatorFactory) == "function", "priority coordinator factory is required")

    local backends = deps.backends or {}
    local destroyed = false
    local running = false
    local workerToken = { cancelled = false }
    local connections = {}
    local requestCache = {}
    local criticalCache = {}

    local function log(level, message)
        pcall(logger, level, message)
    end

    local function safeCall(fn, ...)
        if type(fn) ~= "function" then
            return false, nil
        end
        local ok, result = pcall(fn, ...)
        return ok, result
    end

    local function wait(seconds)
        if scheduler and type(scheduler.wait) == "function" then
            scheduler.wait(seconds)
        end
    end

    local function spawn(fn)
        if scheduler and type(scheduler.spawn) == "function" then
            return scheduler.spawn(fn)
        end
        return nil
    end

    local function setMainPause(kind, reason, value)
        local fn = kind == "HOT_EGG"
            and runtime.setHotEggCoordinatorPaused
            or runtime.setNormalFarmCoordinatorPaused
        if type(fn) == "function" then
            return pcall(fn, reason, value)
        end
        return false
    end

    local function makeHotEggAdapter()
        return {
            setPaused = function(reason, value)
                setMainPause("HOT_EGG", reason, value)
            end,
            cancelMovement = function(byOwner)
                if type(runtime.cancelMovement) == "function" then
                    return runtime.cancelMovement(byOwner)
                end
                return true
            end,
            isCritical = function()
                return false
            end,
        }
    end

    local function makeNormalFarmAdapter()
        return {
            setPaused = function(reason, value)
                setMainPause("NORMAL_FARM", reason, value)
            end,
            cancelMovement = function(byOwner)
                if type(runtime.cancelMovement) == "function" then
                    return runtime.cancelMovement(byOwner)
                end
                return true
            end,
            isCritical = function()
                return false
            end,
        }
    end

    local function makeEventAdapter()
        local backend = backends.EVENT_CAPSULE
        assert(type(backend) == "table", "EVENT_CAPSULE backend is required")
        return {
            setPaused = function(reason, value)
                if type(backend.setPaused) == "function" then
                    return backend.setPaused(reason, value)
                end
                return false
            end,
            cancelMovement = function(byOwner)
                if type(backend.cancelMovement) == "function" then
                    return backend.cancelMovement("coordinator_preempt:" .. tostring(byOwner))
                end
                return false
            end,
            isCritical = function()
                if type(backend.isDepositing) == "function" then
                    return backend.isDepositing() == true
                end
                local status = type(backend.getStatus) == "function" and backend.getStatus() or nil
                return status == "DEPOSITING" or status == "WAITING_FOR_DEPOSIT_CONFIRMATION"
            end,
        }
    end

    local function makeArenaAdapter()
        local backend = backends.AUTO_ARENA
        if type(backend) ~= "table" then
            return {}
        end
        return {
            setPaused = function(reason, value)
                if type(backend.setPaused) == "function" then
                    return backend.setPaused(value == true, reason)
                end
                return false
            end,
            cancelMovement = function(byOwner)
                -- Arena cancellation is deliberately not requested for a critical battle.
                if type(backend.cancelMovement) == "function" then
                    return backend.cancelMovement(byOwner)
                end
                return true
            end,
            isCritical = function()
                if type(backend.isBattling) == "function" then
                    return backend.isBattling() == true
                end
                return false
            end,
            setEventPending = function(value, reason)
                if type(backend.setEventPending) == "function" then
                    return backend.setEventPending(value == true, reason)
                end
                return true
            end,
        }
    end

    local function makeUFOAdapter()
        local backend = backends.UFO_ASCENSION
        if type(backend) ~= "table" then return {} end
        return {
            setPaused = function(reason, value)
                if type(backend.setPaused) == "function" then
                    return backend.setPaused(value == true, reason)
                end
                return false
            end,
            cancelMovement = function(byOwner)
                if type(backend.cancelMovement) == "function" then
                    return backend.cancelMovement(byOwner)
                end
                return true
            end,
            isCritical = function()
                return type(backend.isCritical) == "function" and backend.isCritical() == true
            end,
        }
    end

    local function makeKrakenAdapter()
        local backend = backends.KRAKEN_EGG
        if type(backend) ~= "table" then
            return {}
        end
        return {
            setPaused = function(reason, value)
                if type(backend.setPaused) == "function" then
                    return backend.setPaused(reason, value)
                end
                return false
            end,
            isCritical = function()
                return false
            end,
            cancelMovement = function(byOwner)
                if type(backend.cancelMovement) == "function" then
                    return backend.cancelMovement(byOwner)
                end
                return true
            end,
        }
    end

    local features = {
        HOT_EGG = makeHotEggAdapter(),
        EVENT_CAPSULE = makeEventAdapter(),
        UFO_ASCENSION = makeUFOAdapter(),
        KRAKEN_EGG = makeKrakenAdapter(),
        AUTO_ARENA = makeArenaAdapter(),
        NORMAL_FARM = makeNormalFarmAdapter(),
    }
    for _, owner in ipairs({ "HOT_EGG", "EVENT_CAPSULE", "UFO_ASCENSION", "KRAKEN_EGG", "AUTO_ARENA", "NORMAL_FARM" }) do
        requestCache[owner] = false
        criticalCache[owner] = false
    end

    local coordinator = coordinatorFactory({
        features = features,
        log = function(level, message)
            log(level, message)
        end,
    })

    local function hotEggRequested()
        local state = runtime.getHotEggState and runtime.getHotEggState() or runtime.State.hotEgg
        if type(state) ~= "table" or state.enabled ~= true then
            return false
        end
        if state.eventActive == true or state.holding == true then
            return true
        end
        local phase = state.phase
        return phase == "EVENT_STARTED" or phase == "SEARCHING_HOT_EGG"
            or phase == "MOVING_TO_HOT_EGG" or phase == "VERIFYING_PICKUP"
            or phase == "HOLDING_HOT_EGG" or phase == "EVADING_METEOR"
            or phase == "METEOR_WARNING" or phase == "EXITING_PIT"
    end

    local function eventRequested()
        local backend = backends.EVENT_CAPSULE
        if type(backend) ~= "table" then return false end
        local ok, pending = safeCall(backend.getPendingCapsules)
        if ok and type(pending) == "table" and #pending > 0 then
            return true
        end
        local carryOk, carry = safeCall(backend.getCarryCount)
        if carryOk and tonumber(carry) and tonumber(carry) > 0 then
            return true
        end
        local statusOk, status = safeCall(backend.getStatus)
        return statusOk and (status == "RETURNING_TO_RECYCLER"
            or status == "DEPOSITING"
            or status == "WAITING_FOR_DEPOSIT_CONFIRMATION")
    end

    local function ufoRequested()
        local backend = backends.UFO_ASCENSION
        if type(backend) ~= "table" or type(backend.isEnabled) ~= "function" or backend.isEnabled() ~= true then
            return false
        end
        local ok, state = safeCall(backend.getState)
        if not ok or type(state) ~= "table" then return false end
        return state.state ~= "WAIT_EVENT" and state.state ~= "DISABLED" and state.state ~= "COMPLETE"
    end

    local function krakenRequested()
        local backend = backends.KRAKEN_EGG
        if type(backend) ~= "table" then return false end
        local stateOk, state = safeCall(backend.getKrakenEventState)
        if not stateOk or type(state) ~= "table" or state.active ~= true then
            return false
        end
        local pendingOk, pending = safeCall(backend.getPendingEggs)
        return pendingOk and type(pending) == "table" and next(pending) ~= nil
    end

    local function arenaRequested()
        local backend = backends.AUTO_ARENA
        return type(backend) == "table"
            and type(backend.isEnabled) == "function"
            and backend.isEnabled() == true
            and (type(backend.isPaused) ~= "function" or backend.isPaused() == false)
    end

    local function normalFarmRequested()
        local state = runtime.getNormalFarmState and runtime.getNormalFarmState() or runtime.State.autoFarmRebirth
        return type(state) == "table" and state.enabled == true
    end

    local function syncFeature(owner, requested, critical)
        requested = requested == true
        critical = critical == true
        if requestCache[owner] ~= requested then
            requestCache[owner] = requested
            if requested then
                log("info", "[UNO Integration] request " .. owner)
                coordinator.requestPriority(owner, nil, { critical = critical })
            else
                coordinator.releasePriority(owner)
            end
        end
        if criticalCache[owner] ~= critical then
            criticalCache[owner] = critical
            coordinator.setCritical(owner, critical)
            if owner == "EVENT_CAPSULE" and critical then
                log("info", "[UNO Integration] EVENT_CAPSULE critical=true deposit")
            elseif owner == "EVENT_CAPSULE" and not critical then
                log("info", "[UNO Integration] EVENT_CAPSULE critical=false")
            elseif owner == "AUTO_ARENA" and critical then
                log("info", "[UNO Integration] AUTO_ARENA critical=true battle")
            end
        end
    end

    local function sync()
        syncFeature("HOT_EGG", hotEggRequested(), false)
        syncFeature("EVENT_CAPSULE", eventRequested(), features.EVENT_CAPSULE.isCritical())
        syncFeature("UFO_ASCENSION", ufoRequested(), features.UFO_ASCENSION.isCritical())
        syncFeature("KRAKEN_EGG", krakenRequested(), false)
        local arenaCritical = features.AUTO_ARENA.isCritical()
        syncFeature("AUTO_ARENA", arenaRequested(), arenaCritical)
        syncFeature("NORMAL_FARM", normalFarmRequested(), false)
    end

    local function run()
        if running then return end
        running = true
        spawn(function()
            while not workerToken.cancelled and not destroyed do
                local ok, err = pcall(sync)
                if not ok then
                    log("warn", "[UNO Integration] sync error: " .. tostring(err))
                end
                wait(0.25)
            end
            running = false
        end)
    end

    local function getState()
        return coordinator.getDebugState()
    end

    local function destroy()
        if destroyed then return end
        destroyed = true
        workerToken.cancelled = true
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(connections)
        if coordinator then coordinator.destroy() end
        if deps.destroyBackends == true then
            for _, backend in pairs(backends) do
                if type(backend.destroy) == "function" then pcall(backend.destroy) end
            end
        end
        if env.UNO_HUB_PRIORITY_INTEGRATION == api then
            env.UNO_HUB_PRIORITY_INTEGRATION = nil
        end
    end

    local api = {
        coordinator = coordinator,
        backends = backends,
        run = run,
        sync = sync,
        getState = getState,
        getCoordinator = function() return coordinator end,
        destroy = destroy,
    }
    env.UNO_HUB_PRIORITY_INTEGRATION = api
    return api
end

local globalEnv = (getgenv and getgenv()) or _G
globalEnv.UNO_HUB_PRIORITY_INTEGRATION_FACTORY = createUNOHubPriorityIntegration
return createUNOHubPriorityIntegration

end

__unoRunStage("06 06_UNO_HUB_PRIORITY_INTEGRATION_PHASE9(1).lua", __unoStage06)


local function __unoStage07()
-- Embedded Auto UFO factory (no extra runtime stage)
-- UNO HUB — AUTO UFO ASCENSION
-- Dependency-injected backend. No module requiring, broad scanning, product purchase,
-- eligibility bypass, or UI clicking is performed here.

local PRIORITY = 75
local GENE_KEYS = { "vigor", "furia", "velocidad", "impetu", "fertility" }
local DEFAULT_CAPS = {
    common = 8, uncommon = 12, rare = 16, epic = 20, legendary = 24,
    mythic = 27, divine = 29, celestial = 30, cosmic = 31, secret = 31,
}

local function createAutoUFOAscension(deps)
    deps = type(deps) == "table" and deps or {}
    local schedule = deps.task or task
    local logger = deps.log
    local destroyed, enabled, paused = false, false, false
    local generation, workerRunning = 0, false
    local eventWasActive, sentForEvent, requestInFlight = false, false, false
    local targetId, beforeGenes, lastGenes, lastRarity = nil, nil, nil, nil
    local mutationPayload, mutationAt, lastActionAt = nil, 0, 0
    local lastGeneChange, lastResult, lastError = nil, nil, nil
    local state, status = "IDLE", "DISABLED"
    local mutationConnection
    local actionCooldown = tonumber(deps.actionCooldown) or 1.5
    local timeout = tonumber(deps.timeout) or 45

    local function log(level, message)
        if type(logger) == "function" then pcall(logger, level, message) end
    end
    local function wait(seconds)
        if schedule and type(schedule.wait) == "function" then schedule.wait(seconds) end
    end
    local function spawn(fn)
        if schedule and type(schedule.spawn) == "function" then return schedule.spawn(fn) end
        return nil
    end
    local function call(name, ...)
        local fn = deps[name]
        if type(fn) ~= "function" then return false, nil end
        return pcall(fn, ...)
    end
    local function setState(nextState, nextStatus)
        state = tostring(nextState or state)
        if nextStatus ~= nil then status = tostring(nextStatus) end
    end
    local function cloneGenes(genes)
        if type(genes) ~= "table" then return nil end
        local out, found = {}, false
        for _, key in ipairs(GENE_KEYS) do
            local value = tonumber(genes[key])
            if value ~= nil then out[key] = value; found = true end
        end
        return found and out or nil
    end
    local function genesChanged(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return false end
        for _, key in ipairs(GENE_KEYS) do
            if tonumber(a[key]) ~= tonumber(b[key]) then return true end
        end
        return false
    end
    local function getTarget()
        local ok, chicken = call("getEquippedChicken")
        if not ok or type(chicken) ~= "table" then return nil, nil end
        local id = chicken.id or chicken.uuid or chicken.UID
        return chicken, id ~= nil and tostring(id) or nil
    end
    local function getGenes(chicken)
        local ok, genes = call("getGenes", chicken)
        if ok and type(genes) == "table" then return cloneGenes(genes) end
        return cloneGenes(chicken and chicken.genome)
    end
    local function getCap(chicken)
        local ok, cap = call("getRarityCap", chicken)
        if ok and tonumber(cap) then return tonumber(cap) end
        local rarity = chicken and chicken.rarity
        if type(rarity) == "table" then rarity = rarity.id or rarity.name end
        return tonumber((deps.geneCaps or DEFAULT_CAPS)[string.lower(tostring(rarity or ""))])
    end
    local function isMaxed(chicken, genes)
        local cap = getCap(chicken)
        if not cap or type(genes) ~= "table" then return false end
        for _, key in ipairs(GENE_KEYS) do
            if tonumber(genes[key]) == nil or tonumber(genes[key]) < cap then return false end
        end
        return true
    end
    local function canRun()
        if destroyed or not enabled or paused then return false end
        local ok, allowed = call("canRun")
        return ok and allowed == true
    end
    local function releasePriority() call("releasePriority", "UFO_ASCENSION") end
    local function disableMaxed()
        enabled, requestInFlight, sentForEvent = false, false, true
        generation += 1
        setState("COMPLETE", "Genes Maxed")
        call("onAutoOff")
        releasePriority()
    end
    local function stopForEvent(reason)
        requestInFlight, sentForEvent = false, true
        mutationPayload, targetId, beforeGenes = nil, nil, nil
        lastResult = reason
        setState("WAIT_EVENT_END", reason)
        releasePriority()
    end
    local function mutationMatches(payload)
        if type(payload) ~= "table" then return false end
        local payloadId = payload.id or payload.uuid or payload.chickenId or payload.roosterId
        if payloadId ~= nil and (targetId == nil or tostring(payloadId) ~= tostring(targetId)) then return false end
        return payloadId == nil and targetId ~= nil or payloadId ~= nil
    end
    local function onMutation(payload)
        if not mutationMatches(payload) then return end
        mutationPayload, mutationAt = payload, os.clock()
        local changes = payload.changes
        if type(changes) == "table" and #changes > 0 and type(changes[1]) == "table" then
            lastGeneChange = { gene = changes[1].gene, from = tonumber(changes[1].from), to = tonumber(changes[1].to) }
        end
        log("info", "[UFO] ChickenMutated observed")
    end
    local function sendChaos(myGeneration)
        if requestInFlight or sentForEvent or os.clock() - lastActionAt < actionCooldown or not canRun() then return false end
        local chicken, id = getTarget()
        if not chicken or not id then setState("CHECK_EQUIPPED", "Equipped Chicken Unavailable"); return false end
        local genes = getGenes(chicken)
        if isMaxed(chicken, genes) then disableMaxed(); return false end
        local okWhere, where = call("getChickenWhere")
        if okWhere and (where == "pit" or where == "chaos") then setState("WAIT_CHAOS_ACCEPT", "Chicken Already in Chaos"); return false end
        targetId, beforeGenes, lastGenes, lastRarity = id, genes, genes, chicken.rarity
        mutationPayload, requestInFlight, lastActionAt = nil, true, os.clock()
        setState("SEND_TO_CHAOS", "Sending Chicken to Chaos")
        local sentOk, accepted = call("sendToChaos")
        if not sentOk or accepted == false then
            requestInFlight = false; lastError = "SetChickenOrder was not accepted locally"
            setState("ERROR_RECOVERY", lastError); return false
        end
        if myGeneration ~= generation then return false end
        setState("WAIT_CHAOS_ACCEPT", "Waiting for Chaos")
        return true
    end
    local function waitForResult(myGeneration)
        local deadline = os.clock() + timeout
        while enabled and not paused and not destroyed and myGeneration == generation and os.clock() < deadline do
            local chicken, id = getTarget()
            if not chicken or id ~= targetId then
                requestInFlight = false; lastError = "Equipped chicken changed during UFO cycle"
                setState("ERROR_RECOVERY", lastError); return false
            end
            local genes = getGenes(chicken)
            local validPayload = mutationPayload ~= nil and mutationAt >= lastActionAt
            if validPayload and (genesChanged(beforeGenes, genes) or mutationPayload.ascended == true or type(mutationPayload.beamGenes) == "table") then
                requestInFlight, lastGenes = false, genes
                if isMaxed(chicken, genes) then disableMaxed(); return true end
                sentForEvent = true
                setState("WAIT_REPEAT_ELIGIBILITY", "Waiting for Next Eligible Beam")
                releasePriority()
                return true
            end
            setState("WAIT_UFO_RESULT", "Waiting for UFO Beam")
            wait(0.25)
        end
        requestInFlight = false; lastError = "UFO result timeout"
        setState("ERROR_RECOVERY", lastError); releasePriority(); return false
    end
    local function exitTower(myGeneration)
        local ok, active = call("isTowerActive")
        if not ok or active ~= true then return true end
        setState("EXITING_TOWER", "Suspending Tower")
        local requested, result = call("requestTowerExit", myGeneration)
        if not requested or result == false then
            lastError = "Tower exit was not confirmed"; setState("ERROR_RECOVERY", lastError); return false
        end
        setState("WAIT_TOWER_EXIT", "Tower Exit Confirmed")
        return true
    end
    local function tick(myGeneration)
        local activeOk, active = call("isEventActive")
        if not activeOk or active ~= true then setState("WAIT_EVENT", "Waiting for UFO"); return end
        if not canRun() then setState("REQUEST_PRIORITY", "Waiting for UFO Priority"); return end
        if not sentForEvent then
            if not exitTower(myGeneration) then return end
            setState("CHECK_EQUIPPED", "Checking Equipped Chicken")
            sendChaos(myGeneration)
        elseif requestInFlight then
            waitForResult(myGeneration)
        else
            setState("WAIT_REPEAT_ELIGIBILITY", "Waiting for Next Eligible Beam")
        end
    end
    local function runWorker()
        if workerRunning then return end
        workerRunning = true
        local myGeneration = generation
        spawn(function()
            while enabled and not paused and not destroyed and myGeneration == generation do
                local ok, err = pcall(tick, myGeneration)
                if not ok then lastError = tostring(err); setState("ERROR_RECOVERY", lastError); log("warn", lastError) end
                wait(0.35)
            end
            workerRunning = false
        end)
    end
    if type(deps.onMutation) == "function" then
        local ok, connection = pcall(deps.onMutation, onMutation)
        if ok then mutationConnection = connection end
    end
    local function setEnabled(value)
        if destroyed then return false end
        enabled = value == true; generation += 1
        if not enabled then requestInFlight = false; setState("DISABLED", "Disabled"); releasePriority(); return true end
        sentForEvent, eventWasActive = false, false
        setState("WAIT_EVENT", "Waiting for UFO"); return true
    end
    local function setPaused(value, reason)
        paused = value == true
        if paused then setState("REQUEST_PRIORITY", "Paused: " .. tostring(reason or "Coordinator"))
        elseif enabled then setState("WAIT_EVENT", "Waiting for UFO"); runWorker() end
        return true
    end
    local function step()
        if destroyed or not enabled or paused then return end
        local ok, active = call("isEventActive")
        if not ok then return end
        if active == true and not eventWasActive then
            eventWasActive, sentForEvent, requestInFlight = true, false, false
            mutationPayload, targetId, beforeGenes = nil, nil, nil
            setState("UFO_DETECTED", "UFO Active")
        elseif active ~= true and eventWasActive then
            eventWasActive = false; stopForEvent("Event Ended"); return
        end
        if active == true then
            local requestedOk, requested = call("requestPriority", "UFO_ASCENSION", PRIORITY)
            if requestedOk and requested ~= false then runWorker() else setState("REQUEST_PRIORITY", "Waiting for UFO Priority") end
        else setState("WAIT_EVENT", "Waiting for UFO") end
    end
    local function getState()
        return { state = state, status = status, enabled = enabled, paused = paused, targetId = targetId,
            targetRarity = lastRarity, genes = lastGenes, beforeGenes = beforeGenes, sentForEvent = sentForEvent,
            requestInFlight = requestInFlight, lastGeneChange = lastGeneChange, lastResult = lastResult,
            lastError = lastError, priority = PRIORITY }
    end
    local function destroy()
        if destroyed then return end
        destroyed, enabled, generation = true, false, generation + 1
        releasePriority()
        if mutationConnection and type(mutationConnection.Disconnect) == "function" then pcall(function() mutationConnection:Disconnect() end) end
        mutationConnection = nil; setState("DISABLED", "Destroyed")
    end
    return {
        PRIORITY = PRIORITY, GENE_KEYS = GENE_KEYS, setEnabled = setEnabled, setPaused = setPaused,
        step = step, getState = getState, getStatus = function() return status end,
        isEnabled = function() return enabled end, isCritical = function() return requestInFlight end,
        cancelMovement = function() return true end, destroy = destroy,
    }
end

-- UNO HUB PHASE 9 AUTOMATIC RUNTIME BOOTSTRAP
-- Constructs real backend instances from source-backed game modules.
-- It never fabricates Arena/Kraken dependencies and never claims runtime PASS.

local env = (getgenv and getgenv()) or _G
local old = env.UNO_HUB_PHASE9
if old and type(old.destroy) == "function" then
    pcall(old.destroy)
end

local status = "BOOTSTRAPPING"
local lastError = nil
local backends: {[string]: any} = {}
local integration = nil
local destroyed = false
local ownedBackends: {[string]: any} = {}
local movementBroker = { integration = nil }
local runtimeRef = nil

local function log(message)
    print("[UNO Bootstrap] " .. tostring(message))
end

local function block(reason)
    status = "BLOCKED"
    lastError = tostring(reason)
    for key, backend in pairs(ownedBackends) do
        if backend and type(backend.destroy) == "function" then pcall(backend.destroy) end
        ownedBackends[key] = nil
    end
    backends = {}
    env.UNO_HUB_BACKENDS = nil
    env.UNO_REAL_BACKENDS = nil
    log("BLOCKED " .. lastError)
    print("PHASE 9 BOOTSTRAP: BLOCKED — " .. lastError)
end

local function safeRequire(instance)
    if not instance then return nil end
    local ok, result = pcall(require, instance)
    return ok and result or nil
end

local function child(root, name)
    return root and root:FindFirstChild(name) or nil
end

local function getRoot()
    local runtime = env.UNO_HUB_RUNTIME
    if type(runtime) ~= "table" then
        return nil, "UNOHUB_PHASE9.lua runtime bridge unavailable"
    end
    local services = runtime.Services
    if type(services) ~= "table" then
        return nil, "UNOHUB_PHASE9.lua runtime services unavailable"
    end
    return {
        runtime = runtime,
        Players = services.Players,
        ReplicatedStorage = services.ReplicatedStorage,
        Workspace = services.Workspace,
        CollectionService = services.CollectionService,
        TweenService = services.TweenService,
        player = services.Players and services.Players.LocalPlayer,
    }
end

local function createTweenMovement(root)
    local active = nil
    local serial = 0
    local function getRootPart()
        local character = root.player and root.player.Character
        return character and character:FindFirstChild("HumanoidRootPart")
    end
    local function cancel(reason)
        serial += 1
        local current = active
        active = nil
        if current and current.tween then
            pcall(function() current.tween:Cancel() end)
        end
        return true
    end
    local function moveTo(position, options)
        if typeof(position) ~= "Vector3" then return false end
        options = type(options) == "table" and options or {}
        cancel("replace")
        serial += 1
        local mySerial = serial
        local hrp = getRootPart()
        if not hrp then return false end
        local distance = (hrp.Position - position).Magnitude
        local speed = tonumber(options.speed) or 45
        local duration = math.max(0.05, distance / math.max(1, speed))
        local tween = root.TweenService:Create(
            hrp,
            TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            { CFrame = CFrame.new(position + Vector3.new(0, 3, 0)) }
        )
        local handle = {
            completed = false,
            cancelled = false,
            done = false,
            cancel = function(self)
                if self.cancelled or self.done then return end
                self.cancelled = true
                cancel("handle_cancel")
            end,
            stop = function(self) self:cancel() end,
            destroy = function(self) self:cancel() end,
            isComplete = function(self) return self.completed or self.done end,
        }
        active = { tween = tween, handle = handle, serial = mySerial }
        tween.Completed:Connect(function()
            if mySerial ~= serial then return end
            handle.completed = true
            handle.done = true
            if active and active.serial == mySerial then active = nil end
        end)
        tween:Play()
        task.spawn(function()
            while mySerial == serial and not handle.done do
                if type(options.isCancelled) == "function" then
                    local ok, cancelled = pcall(options.isCancelled)
                    if ok and cancelled == true then
                        handle:cancel()
                        break
                    end
                end
                task.wait(0.1)
            end
        end)
        return handle
    end
    return {
        moveTo = moveTo,
        cancelMovement = cancel,
    }
end

local function resolveArena(root, remotes, charm)
    local scripts = root.player and root.player:FindFirstChild("PlayerScripts")
    local ui = scripts and scripts:FindFirstChild("UI")
    local ui2d = ui and ui:FindFirstChild("2d")
    local arenaFolder = ui2d and ui2d:FindFirstChild("Arena")
    local settingsFolder = ui2d and ui2d:FindFirstChild("Settings")
    local arenaClient = safeRequire(arenaFolder and arenaFolder:FindFirstChild("ArenaClient"))
    local arenaState = safeRequire(arenaFolder and arenaFolder:FindFirstChild("ArenaState"))
    local rankSettings = safeRequire(settingsFolder and settingsFolder:FindFirstChild("ArenaRankSettings"))
    if not arenaClient then return nil, "ArenaClient source path unresolved" end
    if not arenaState then return nil, "ArenaState source path unresolved" end
    if not rankSettings then return nil, "ArenaRankSettings source path unresolved" end
    if not remotes then return nil, "ReplicatedStorage.Core.Remotes unresolved" end
    if not charm then return nil, "ReplicatedStorage.Packages.Charm unresolved" end
    return {
        ArenaClient = arenaClient,
        ArenaState = arenaState,
        ArenaRankSettings = rankSettings,
        Remotes = remotes,
        Charm = charm,
    }
end

local function resolveKraken(root, remotes)
    if not remotes or type(remotes.fire) ~= "function" or type(remotes.onClient) ~= "function" then
        return nil, "ReplicatedStorage.Core.Remotes fire/onClient API unresolved"
    end
    if type(remotes.defs) ~= "table" or not remotes.defs.LiveEventClientSignal or not remotes.defs.LiveEventSignal then
        return nil, "Core.Remotes LiveEventClientSignal/LiveEventSignal definitions unresolved"
    end
    -- Source-backed runtime path:
    -- PlayerScripts.Features.Admin.controllers.LiveEventController
    local scripts = root.player and root.player:FindFirstChild("PlayerScripts")
    local features = scripts and scripts:FindFirstChild("Features")
    local admin = features and features:FindFirstChild("Admin")
    local controllers = admin and admin:FindFirstChild("controllers")
    local liveEventController = safeRequire(controllers and controllers:FindFirstChild("LiveEventController"))
    if not liveEventController then
        return nil, "PlayerScripts.Features.Admin.controllers.LiveEventController unresolved"
    end
    if type(liveEventController.isEventActive) ~= "function" or type(liveEventController.getEventState) ~= "function" then
        return nil, "LiveEventController isEventActive/getEventState API unresolved"
    end
    local function getLandedEggs()
        -- Source-backed runtime path: Workspace.KrakenEggs
        local folder = root.Workspace:FindFirstChild("KrakenEggs")
        local result = {}
        if not folder then return result end
        for _, instance in ipairs(folder:GetChildren()) do
            if instance:IsA("Model") then table.insert(result, instance) end
        end
        return result
    end
    local function getEggId(instance)
        return instance and instance:GetAttribute("eggId")
    end
    local function getEggPosition(instance)
        return instance and instance:GetPivot().Position
    end
    local function getEggExpiry(instance)
        -- The official controller keeps expiresAt in the event record and
        -- schedules despawn there; it does not replicate an expiry attribute
        -- onto the visual Model. The backend therefore receives nil.
        return nil
    end
    local function isEggReady(instance)
        local prompt = instance and instance:FindFirstChildWhichIsA("ProximityPrompt", true)
        return prompt ~= nil and prompt.Enabled == true
    end
    local function onLiveEventSignal(callback)
        return remotes.onClient(remotes.defs.LiveEventSignal, callback)
    end
    local function fireClientSignal(payload)
        return remotes.fire(remotes.defs.LiveEventClientSignal, payload)
    end
    local function getPlayerPosition()
        local character = root.player and root.player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position
    end
    return {
        getKrakenEventState = function()
            return liveEventController:getEventState("kraken")
        end,
        isKrakenActive = function()
            return liveEventController:isEventActive("kraken")
        end,
        getLandedEggs = getLandedEggs,
        getEggId = getEggId,
        getEggPosition = getEggPosition,
        getEggExpiry = getEggExpiry,
        isEggReady = isEggReady,
        fireClientSignal = fireClientSignal,
        onLiveEventSignal = onLiveEventSignal,
        getPlayerPosition = getPlayerPosition,
        moveTo = createTweenMovement(root).moveTo,
    }
end

local function resolveUFO(root, remotes)
    if not remotes or type(remotes.onClient) ~= "function" or type(remotes.defs) ~= "table" then
        return nil, "Core.Remotes ChickenMutated API unresolved"
    end
    local scripts = root.player and root.player:FindFirstChild("PlayerScripts")
    local features = scripts and scripts:FindFirstChild("Features")
    local chickenFolder = features and features:FindFirstChild("Chicken")
    local controllers = chickenFolder and chickenFolder:FindFirstChild("controllers")
    local chickenController = safeRequire(controllers and controllers:FindFirstChild("ChickenController"))
    local chickenMode = safeRequire(chickenFolder and chickenFolder:FindFirstChild("ChickenMode"))
    local admin = features and features:FindFirstChild("Admin")
    local adminControllers = admin and admin:FindFirstChild("controllers")
    local liveEventController = safeRequire(adminControllers and adminControllers:FindFirstChild("LiveEventController"))
    if not chickenController or type(chickenController.setOrder) ~= "function" then
        return nil, "ChickenController:setOrder unresolved"
    end
    if not liveEventController or type(liveEventController.isEventActive) ~= "function" then
        return nil, "LiveEventController:isEventActive unresolved"
    end
    if not remotes.defs.ChickenMutated then return nil, "ChickenMutated definition unresolved" end
    local function getEquippedChicken()
        local dc = root.runtime.Integration and root.runtime.Integration.modules and root.runtime.Integration.modules.DataController
        local roster = dc and type(dc.roster) == "function" and dc.roster() or nil
        if type(roster) ~= "table" then return nil end
        for _, chicken in pairs(roster.chickens or {}) do
            if chicken and roster.activeId ~= nil and tostring(chicken.id) == tostring(roster.activeId) then return chicken end
        end
        return nil
    end
    local function onMutation(callback)
        return remotes.onClient(remotes.defs.ChickenMutated, callback)
    end
    local function getChickenWhere()
        return chickenMode and type(chickenMode.where) == "function" and chickenMode.where() or nil
    end
    local geneCaps = { common=8, uncommon=12, rare=16, epic=20, legendary=24, mythic=27, divine=29, celestial=30, cosmic=31, secret=31 }
    return {
        isEventActive = function() return liveEventController:isEventActive("ufo") end,
        getEquippedChicken = getEquippedChicken,
        getGenes = function(chicken) return chicken and chicken.genome end,
        getRarityCap = function(chicken)
            local rarity = chicken and chicken.rarity
            if type(rarity) == "table" then rarity = rarity.id or rarity.name end
            return geneCaps[string.lower(tostring(rarity or ""))]
        end,
        getChickenWhere = getChickenWhere,
        sendToChaos = function() return chickenController:setOrder("chaos") end,
        onMutation = onMutation,
        isTowerActive = root.runtime.isTowerActive,
        requestTowerExit = root.runtime.requestUFOTowerExit,
        geneCaps = geneCaps,
    }
end

local function createBootstrap()
    local root, rootError = getRoot()
    if not root then block(rootError) return end
    runtimeRef = root.runtime
    status = "RESOLVING_DEPENDENCIES"
    local integrationModules = root.runtime.Integration and root.runtime.Integration.modules or {}
    local remotes = integrationModules.Remotes
        or safeRequire(child(child(root.ReplicatedStorage, "Core"), "Remotes"))
    local charm = integrationModules.Charm
        or safeRequire(child(child(root.ReplicatedStorage, "Packages"), "Charm"))
    local eventFactory = env.UNO_EVENT_CAPSULE_COLLECTOR_FACTORY
    local arenaFactory = env.UNO_AUTO_ARENA_FACTORY
    local krakenFactory = env.UNO_KRAKEN_EGG_COLLECTOR_FACTORY
    local ufoFactory = createAutoUFOAscension
    local integrationFactory = env.UNO_HUB_PRIORITY_INTEGRATION_FACTORY
    if type(eventFactory) ~= "function" then block("Event Capsule factory unavailable: UNO_EVENT_CAPSULE_COLLECTOR_FACTORY") return end
    if type(arenaFactory) ~= "function" then block("Auto Arena factory unavailable: UNO_AUTO_ARENA_FACTORY") return end
    if type(krakenFactory) ~= "function" then block("Kraken factory unavailable: UNO_KRAKEN_EGG_COLLECTOR_FACTORY") return end
    if type(ufoFactory) ~= "function" then block("UFO factory unavailable") return end
    if type(integrationFactory) ~= "function" then block("Priority integration factory unavailable: UNO_HUB_PRIORITY_INTEGRATION_FACTORY") return end
    status = "CONSTRUCTING_BACKENDS"
    local tween = createTweenMovement(root)
    local looseRemotes = child(root.ReplicatedStorage, "Remotes")
    local scrapDepositedRemote = looseRemotes and looseRemotes:FindFirstChild("ScrapDeposited")
    local scrapDeposited = scrapDepositedRemote
    if scrapDepositedRemote and scrapDepositedRemote:IsA("RemoteEvent") then
        scrapDeposited = scrapDepositedRemote.OnClientEvent
    end
    if not scrapDeposited or type(scrapDeposited.Connect) ~= "function" then
        block("ScrapDeposited client signal unresolved")
        return
    end
    local eventOk, eventBackend = pcall(eventFactory, {
        player = root.player,
        workspace = root.Workspace,
        collectionService = root.CollectionService,
        scrapDeposited = scrapDeposited,
        task = task,
        log = function(level, message) log(message) end,
        movement = tween,
        moveTo = tween.moveTo,
        acquireMovement = function(owner, priority)
            if not movementBroker.integration then return false end
            return movementBroker.integration.getCoordinator().acquireMovement("EVENT_CAPSULE", priority)
        end,
        releaseMovement = function(owner)
            if movementBroker.integration then
                return movementBroker.integration.getCoordinator().releaseMovement("EVENT_CAPSULE")
            end
            return false
        end,
        maxCarry = 5,
        movementMode = "Tween",
        capsuleRetargetInterval = 0.35,
        capsuleRetargetDistance = 3,
        capsuleFollowDistance = 3,
        recyclerFrontDistance = 5,
        recyclerFrontSign = 1,
    })
    if not eventOk or type(eventBackend) ~= "table" then block("Event Capsule construction failed: " .. tostring(eventBackend)) return end
    backends.EVENT_CAPSULE = eventBackend
    ownedBackends.EVENT_CAPSULE = eventBackend
    log("Event Capsule dependencies READY")
    local arenaDeps, arenaError = resolveArena(root, remotes, charm)
    if not arenaDeps then block(arenaError) return end
    local arenaOk, arenaBackend = pcall(arenaFactory, {
        ArenaClient = arenaDeps.ArenaClient,
        ArenaState = arenaDeps.ArenaState,
        ArenaRankSettings = arenaDeps.ArenaRankSettings,
        Remotes = arenaDeps.Remotes,
        Charm = arenaDeps.Charm,
        task = task,
        log = function(level, message) log(message) end,
    })
    if not arenaOk or type(arenaBackend) ~= "table" then block("Auto Arena construction failed: " .. tostring(arenaBackend)) return end
    backends.AUTO_ARENA = arenaBackend
    ownedBackends.AUTO_ARENA = arenaBackend
    log("Arena dependencies READY")
    local krakenDeps, krakenError = resolveKraken(root, remotes)
    if not krakenDeps then block(krakenError) return end
    local krakenOk, krakenBackend = pcall(krakenFactory, krakenDeps)
    if not krakenOk or type(krakenBackend) ~= "table" then block("Kraken construction failed: " .. tostring(krakenBackend)) return end
    backends.KRAKEN_EGG = krakenBackend
    ownedBackends.KRAKEN_EGG = krakenBackend
    log("Kraken dependencies READY")
    local ufoDeps, ufoError = resolveUFO(root, remotes)
    if not ufoDeps then block(ufoError) return end
    local ufoOk, ufoBackend = pcall(ufoFactory, {
        task = task,
        log = function(level, message) log(message) end,
        geneCaps = ufoDeps.geneCaps,
        isEventActive = ufoDeps.isEventActive,
        getEquippedChicken = ufoDeps.getEquippedChicken,
        getGenes = ufoDeps.getGenes,
        getRarityCap = ufoDeps.getRarityCap,
        getChickenWhere = ufoDeps.getChickenWhere,
        sendToChaos = ufoDeps.sendToChaos,
        onMutation = ufoDeps.onMutation,
        isTowerActive = ufoDeps.isTowerActive,
        requestTowerExit = ufoDeps.requestTowerExit,
        canRun = function()
            return integration ~= nil and integration.getCoordinator():isOwnerActive("UFO_ASCENSION")
        end,
        requestPriority = function(owner, priority)
            return integration ~= nil and integration.getCoordinator():requestPriority(owner, priority, { enabled = true }) or false
        end,
        releasePriority = function(owner)
            return integration ~= nil and integration.getCoordinator():releasePriority(owner) or false
        end,
        onAutoOff = function()
            if root.runtime.State and root.runtime.State.toggles then root.runtime.State.toggles.autoUFOAscension = false end
            if type(root.runtime.markConfigDirty) == "function" then pcall(root.runtime.markConfigDirty) end
        end,
    })
    if not ufoOk or type(ufoBackend) ~= "table" then block("UFO construction failed: " .. tostring(ufoBackend)) return end
    backends.UFO_ASCENSION = ufoBackend
    ownedBackends.UFO_ASCENSION = ufoBackend
    log("UFO Ascension dependencies READY")
    status = "CONNECTING_PRIORITY"
    env.UNO_HUB_BACKENDS = backends
    env.UNO_REAL_BACKENDS = backends
    local integrationOk, createdIntegration = pcall(integrationFactory, {
        runtime = root.runtime,
        backends = backends,
        log = function(level, message) log(message) end,
        destroyBackends = false,
    })
    if not integrationOk or type(createdIntegration) ~= "table" then block("Priority integration construction failed: " .. tostring(createdIntegration)) return end
    integration = createdIntegration
    movementBroker.integration = integration
    log("Priority integration READY")
    integration.run()
    if root.runtime.State and root.runtime.State.toggles and root.runtime.State.toggles.autoUFOAscension == true then
        pcall(ufoBackend.setEnabled, true)
    end
    task.spawn(function()
        while not destroyed and not root.runtime.State.closed do
            if ufoBackend and type(ufoBackend.step) == "function" then pcall(ufoBackend.step) end
            task.wait(0.35)
        end
    end)
    status = "READY"
    log("READY")
end

local function destroy()
    if destroyed then return end
    destroyed = true
    if integration and type(integration.destroy) == "function" then pcall(integration.destroy) end
    integration = nil
    movementBroker.integration = nil
    for key, backend in pairs(ownedBackends) do
        if backend and type(backend.destroy) == "function" then pcall(backend.destroy) end
        ownedBackends[key] = nil
    end
    env.UNO_HUB_BACKENDS = nil
    env.UNO_REAL_BACKENDS = nil
    if env.UNO_HUB_PHASE9 == api then env.UNO_HUB_PHASE9 = nil end
end

local function getBackends()
    local result = {}
    for key, backend in pairs(backends) do result[key] = backend end
    return result
end

local api = {
    getStatus = function() return status end,
    getBackends = getBackends,
    getIntegration = function() return integration end,
    getCoordinatorState = function()
        return integration and integration.getState() or nil
    end,
    getLastError = function() return lastError end,
    setEventCapsuleEnabled = function(value)
        local backend = backends.EVENT_CAPSULE
        if not backend or type(backend.setEnabled) ~= "function" then return false end
        return backend.setEnabled(value == true)
    end,
    setAutoArenaEnabled = function(value)
        local backend = backends.AUTO_ARENA
        if not backend or type(backend.setAutoArena) ~= "function" then return false end
        return backend.setAutoArena(value == true)
    end,
    setKrakenEnabled = function(value)
        local backend = backends.KRAKEN_EGG
        if not backend or type(backend.setEnabled) ~= "function" then return false end
        return backend.setEnabled(value == true)
    end,
    setAutoUFOAscension = function(value)
        local backend = backends.UFO_ASCENSION
        if not backend or type(backend.setEnabled) ~= "function" then return false end
        if runtimeRef and runtimeRef.State and runtimeRef.State.toggles then
            runtimeRef.State.toggles.autoUFOAscension = value == true
        end
        local ok = backend.setEnabled(value == true)
        if runtimeRef and type(runtimeRef.markConfigDirty) == "function" then pcall(runtimeRef.markConfigDirty) end
        return ok
    end,
    getAutoUFOState = function()
        local backend = backends.UFO_ASCENSION
        return backend and type(backend.getState) == "function" and backend.getState() or nil
    end,
    destroy = destroy,
}

env.UNO_HUB_PHASE9 = api
createBootstrap()
return api

end

local __unoFinalApi = __unoRunStage("07 07_UNO_HUB_PHASE9_BOOTSTRAP(1).lua", __unoStage07)


local __unoEnv = (getgenv and getgenv()) or _G
if type(__unoEnv.UNO_HUB_PHASE9) == "table" then
    __unoEnv.UNO_HUB = __unoEnv.UNO_HUB_PHASE9
end

local __status = __unoEnv.UNO_HUB_PHASE9
    and type(__unoEnv.UNO_HUB_PHASE9.getStatus) == "function"
    and __unoEnv.UNO_HUB_PHASE9.getStatus()
    or "UNAVAILABLE"

print("[UNO HUB] FINAL MERGE STATUS =", tostring(__status))
if __status == "READY" then
    print("[UNO HUB] FINAL MERGE READY")
else
    warn("[UNO HUB] FINAL MERGE NOT READY; check [UNO Bootstrap] BLOCKED reason above")
end

return __unoFinalApi or __unoEnv.UNO_HUB_PHASE9
