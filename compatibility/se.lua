-- se_compatibility.lua

local control_centre = {}

-- Check if Space Exploration mod is active
function control_centre.is_se_active()
    return script.active_mods["space-exploration"] ~= nil
end

-- Function to safely get remote interface
local function get_se_interface()
    if remote.interfaces["space-exploration"] then
        return remote.interfaces["space-exploration"]
    end
    return nil
end

function control_centre.is_remote_view_unlocked(player)
    if not control_centre.is_se_active() then return false end
    
    local se_interface = get_se_interface()
    if not se_interface or not se_interface.remote_view_is_unlocked then return false end
    
    return remote.call("space-exploration", "remote_view_is_unlocked", {player=player})
end



-- Register all necessary events
function control_centre.register_events(neural_connect_module)
    if not control_centre.is_se_active() then
        log_debug("Space Exploration mod is not active. Skipping event registration.")
        return
    end

    local se_interface = get_se_interface()
    if not se_interface then
        log_debug("Failed to get Space Exploration interface. Skipping event registration.")
        return
    end

    -- Only register remote view events if it's unlocked for at least one player
    local any_player_unlocked = false
    for _, player in pairs(game.players) do
        if control_centre.is_remote_view_unlocked(player) then
            any_player_unlocked = true
            log_debug("Remote view unlocked for player " .. player.name)
            break
        end
    end

    if any_player_unlocked then
        -- Register for remote view started event
        if se_interface.get_on_remote_view_started_event then
            local status, event_id = pcall(remote.call, "space-exploration", "get_on_remote_view_started_event")
            if status and event_id then
                script.on_event(event_id, function(event)
                    local player = game.get_player(event.player_index)
                    if player and player.valid and neural_connect_module.is_connected_to_spidertron(player) then
                        neural_connect_module.disconnect_from_spidertron(player)
                        player.print("Disconnected from Spidertron due to remote view activation.")
                        log_debug("Player " .. player.name .. " disconnected from Spidertron due to remote view activation.")
                    end
                end)
                log_debug("Registered remote view started event")
            else
                log_debug("Failed to get remote view started event ID: " .. tostring(event_id))
            end
        else
            log_debug("get_on_remote_view_started_event not available in SE interface")
        end

        -- Register for remote view stopped event
        if se_interface.get_on_remote_view_stopped_event then
            local status, event_id = pcall(remote.call, "space-exploration", "get_on_remote_view_stopped_event")
            if status and event_id then
                script.on_event(event_id, function(event)
                    local player = game.get_player(event.player_index)
                    if player and player.valid then
                        player.print("Remote view deactivated. You can reconnect to a Spidertron if desired.")
                        log_debug("Remote view deactivated for player " .. player.name)
                    end
                end)
                log_debug("Registered remote view stopped event")
            else
                log_debug("Failed to get remote view stopped event ID: " .. tostring(event_id))
            end
        else
            log_debug("get_on_remote_view_stopped_event not available in SE interface")
        end
    else
        log_debug("Remote view not yet unlocked for any player. Skipping event registration.")
    end
end

    

-- Function to check if player is in remote view (to be used in events only)
function control_centre.is_in_remote_view(player)
    if not control_centre.is_se_active() then return false end
    
    local se_interface = get_se_interface()
    if not se_interface or not se_interface.remote_view_is_active then return false end
    
    return remote.call("space-exploration", "remote_view_is_active", {player=player})
end

-- Function to toggle off remote view (to be used in events only)
function control_centre.toggle_off_remote_view(player)
    if not control_centre.is_se_active() then return false end
    
    local se_interface = get_se_interface()
    if not se_interface or not se_interface.remote_view_stop then return false end
    
    remote.call("space-exploration", "remote_view_stop", {player=player})
    return true
end

-- Get zone from surface index
function control_centre.get_zone_from_surface_index(surface_index)
    if not control_centre.is_se_active() then return nil end
    local se_interface = get_se_interface()
    if not se_interface or not se_interface.get_zone_from_surface_index then return nil end
    return remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index})
end

-- Get surface from zone index
function control_centre.get_surface_from_zone_index(zone_index)
    if not control_centre.is_se_active() then return nil end
    local se_interface = get_se_interface()
    if not se_interface or not se_interface.zone_get_surface then return nil end
    return remote.call("space-exploration", "zone_get_surface", {zone_index = zone_index})
end

-- Check if zone is space
function control_centre.is_zone_space(zone_index)
    if not control_centre.is_se_active() then return false end
    local se_interface = get_se_interface()
    if not se_interface or not se_interface.get_zone_is_space then return false end
    return remote.call("space-exploration", "get_zone_is_space", {zone_index = zone_index})
end

return control_centre