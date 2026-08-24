local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

local env = (getgenv and getgenv()) or _G

-- Cleanup versi lama jika re-execute.
if env.UNO_ANTI_AFK and type(env.UNO_ANTI_AFK.disable) == "function" then
    pcall(env.UNO_ANTI_AFK.disable)
end

local AntiAFK = {
    disabledConnections = {},
    enabled = false,
}

local function disableConnections(signal)
    if type(getconnections) ~= "function" then
        return false, "getconnections unavailable"
    end

    local ok, connections = pcall(getconnections, signal)
    if not ok or type(connections) ~= "table" then
        return false, "failed to read connections"
    end

    for _, connection in ipairs(connections) do
        pcall(function()
            connection:Disable()
            table.insert(AntiAFK.disabledConnections, connection)
        end)
    end

    return true
end

function AntiAFK.enable()
    if AntiAFK.enabled then
        return true
    end

    AntiAFK.enabled = true

    local ok, err = disableConnections(LocalPlayer.Idled)

    if ok then
        print("[UNO AntiAFK] ENABLED")
    else
        warn("[UNO AntiAFK] FAILED:", err)
    end

    return ok
end

function AntiAFK.disable()
    if not AntiAFK.enabled then
        return true
    end

    AntiAFK.enabled = false

    for _, connection in ipairs(AntiAFK.disabledConnections) do
        pcall(function()
            connection:Enable()
        end)
    end

    table.clear(AntiAFK.disabledConnections)

    print("[UNO AntiAFK] DISABLED")

    return true
end

function AntiAFK.getStatus()
    return {
        enabled = AntiAFK.enabled,
        disabledConnections = #AntiAFK.disabledConnections,
    }
end

env.UNO_ANTI_AFK = AntiAFK

AntiAFK.enable()

return AntiAFK
