-- UNO HUB Anti-AFK V2
-- VirtualUser-only edition.
-- Active heartbeat every 55 seconds + LocalPlayer.Idled fallback.

local AntiAFK = {
    disabledConnections = {},
    enabled = false,
    generation = 0,
    idleConnection = nil,
    pulseInterval = 55,
    lastMethod = "NONE",
}

local function getPlayer()
    local Players = game:GetService("Players")
    return Players.LocalPlayer
end

local function disableCurrentIdleConnections()
    local player = getPlayer()
    if not player or type(getconnections) ~= "function" then
        return
    end

    local ok, connections = pcall(getconnections, player.Idled)
    if not ok or type(connections) ~= "table" then
        return
    end

    for _, connection in ipairs(connections) do
        pcall(function()
            if connection.Enabled ~= false then
                connection:Disable()
                table.insert(AntiAFK.disabledConnections, connection)
            end
        end)
    end
end

local function pulse()
    if not AntiAFK.enabled then
        return false
    end

    local success = false
    local camera = workspace.CurrentCamera

    pcall(function()
        local VirtualUser = game:GetService("VirtualUser")
        VirtualUser:CaptureController()

        local cf = camera and camera.CFrame or CFrame.new()
        VirtualUser:Button2Down(Vector2.new(0, 0), cf)
        task.wait(0.03)
        VirtualUser:Button2Up(Vector2.new(0, 0), cf)

        AntiAFK.lastMethod = "VirtualUser"
        success = true
    end)

    return success
end

function AntiAFK.enable()
    if AntiAFK.enabled then
        return true
    end

    AntiAFK.enabled = true
    AntiAFK.generation += 1
    local myGeneration = AntiAFK.generation

    disableCurrentIdleConnections()

    local player = getPlayer()
    if player then
        AntiAFK.idleConnection = player.Idled:Connect(function()
            if AntiAFK.enabled and myGeneration == AntiAFK.generation then
                task.spawn(pulse)
            end
        end)
    end

    task.spawn(function()
        task.wait(2)
        if AntiAFK.enabled and myGeneration == AntiAFK.generation then
            pulse()
        end

        while AntiAFK.enabled and myGeneration == AntiAFK.generation do
            task.wait(AntiAFK.pulseInterval)
            if not AntiAFK.enabled or myGeneration ~= AntiAFK.generation then
                break
            end
            pulse()
        end
    end)

    print("[UNO HUB] Anti-AFK V2 ENABLED (VirtualUser)")
    return true
end

function AntiAFK.disable()
    if not AntiAFK.enabled then
        return
    end

    AntiAFK.enabled = false
    AntiAFK.generation += 1

    if AntiAFK.idleConnection then
        pcall(function()
            AntiAFK.idleConnection:Disconnect()
        end)
        AntiAFK.idleConnection = nil
    end

    for _, connection in ipairs(AntiAFK.disabledConnections) do
        pcall(function()
            connection:Enable()
        end)
    end
    table.clear(AntiAFK.disabledConnections)

    print("[UNO HUB] Anti-AFK V2 DISABLED")
end

function AntiAFK.destroy()
    AntiAFK.disable()
end

function AntiAFK.pulse()
    return pulse()
end

function AntiAFK.getStatus()
    return {
        enabled = AntiAFK.enabled,
        method = AntiAFK.lastMethod,
        interval = AntiAFK.pulseInterval,
    }
end

AntiAFK.enable()
return AntiAFK
