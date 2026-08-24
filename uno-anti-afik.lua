local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local AntiAFK = {
    disabledConnections = {},
    enabled = false,
}

local function disableConnections(signal)
    if type(getconnections) ~= "function" then
        return false
    end

    local ok, connections = pcall(getconnections, signal)
    if not ok or type(connections) ~= "table" then
        return false
    end

    for _, connection in ipairs(connections) do
        pcall(function()
            if connection.Enabled ~= false then
                connection:Disable()
                table.insert(AntiAFK.disabledConnections, connection)
            end
        end)
    end

    return true
end

function AntiAFK.enable()
    if AntiAFK.enabled then
        return true
    end

    AntiAFK.enabled = true

    -- Main idle signal
    disableConnections(LocalPlayer.Idled)

    print("[UNO HUB] Anti-AFK ENABLED")
    return true
end

function AntiAFK.disable()
    if not AntiAFK.enabled then
        return
    end

    AntiAFK.enabled = false

    for _, connection in ipairs(AntiAFK.disabledConnections) do
        pcall(function()
            connection:Enable()
        end)
    end

    table.clear(AntiAFK.disabledConnections)

    print("[UNO HUB] Anti-AFK DISABLED")
end

AntiAFK.enable()
