-- UNO HUB Anti-AFK
-- getconnections-only edition.
-- Re-scans LocalPlayer.Idled every 10 seconds so newly-added idle
-- callbacks are disabled too.

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local AntiAFK = {
    disabledConnections = {},
    seen = {},
    enabled = false,
    generation = 0,
}

local function disableIdleConnections()
    if type(getconnections) ~= "function" then
        return false
    end

    local ok, connections = pcall(
        getconnections,
        LocalPlayer.Idled
    )

    if not ok or type(connections) ~= "table" then
        return false
    end

    for _, connection in ipairs(connections) do
        if not AntiAFK.seen[connection] then
            AntiAFK.seen[connection] = true

            pcall(function()
                if connection.Enabled ~= false then
                    connection:Disable()

                    table.insert(
                        AntiAFK.disabledConnections,
                        connection
                    )
                end
            end)
        end
    end

    return true
end

function AntiAFK.enable()
    if AntiAFK.enabled then
        return true
    end

    AntiAFK.enabled = true
    AntiAFK.generation += 1

    local myGeneration = AntiAFK.generation

    disableIdleConnections()

    task.spawn(function()
        while
            AntiAFK.enabled
            and myGeneration == AntiAFK.generation
        do
            task.wait(10)

            disableIdleConnections()
        end
    end)

    print("[UNO HUB] Anti-AFK ENABLED (getconnections)")
    return true
end

function AntiAFK.disable()
    if not AntiAFK.enabled then
        return
    end

    AntiAFK.enabled = false
    AntiAFK.generation += 1

    for _, connection in ipairs(
        AntiAFK.disabledConnections
    ) do
        pcall(function()
            connection:Enable()
        end)
    end

    table.clear(
        AntiAFK.disabledConnections
    )

    table.clear(
        AntiAFK.seen
    )

    print("[UNO HUB] Anti-AFK DISABLED")
end

function AntiAFK.destroy()
    AntiAFK.disable()
end

function AntiAFK.getStatus()
    return {
        enabled = AntiAFK.enabled,
        disabledCount = #AntiAFK.disabledConnections,
    }
end

AntiAFK.enable()

return AntiAFK
