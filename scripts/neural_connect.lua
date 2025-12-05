local mod_data = require("scripts.mod_data")
local neural_disconnect = require("scripts.neural_disconnect")
local SE_compatibility, space_elevator_compatibility

-- Check if Space Exploration mod is active and require compatibility module if it is
if script.active_mods["space-exploration"] then
    SE_compatibility = require("compatibility.se")
    space_elevator_compatibility = require("compatibility.space_elevator_compatibility")
end

-- Constants
local EXTENDED_REACH = 10
local EXTENDED_MINING_DISTANCE = 10
local MINING_SPEED_MULTIPLIER = 2
local PICKUP_DISTANCE = 3
local DROP_DISTANCE = 10
local LOOT_PICKUP_DISTANCE = 10

local function log_debug(message)
    log("[Neural Vehicle Control] " .. message)
end

local neural_connect = {}
local last_connections = {}

-- Track the last connected vehicle
function neural_connect.track_connection(player_index, vehicle_type, vehicle)
    last_connections[player_index] = {
        type = vehicle_type,
        vehicle_id = vehicle.unit_number,
        time = game.tick,
        surface_index = vehicle.surface.index
    }
    log_debug("Tracked connection for player " .. player_index .. " to " .. vehicle_type .. " #" .. vehicle.unit_number)
end

-- Function to reconnect to the last connected vehicle
function neural_connect.reconnect_to_last_vehicle(player_index)
    local player = game.get_player(player_index)
    if not player then return end
    
    log_debug("Trying to reconnect player " .. player.name .. " to last vehicle")
    
    -- Get last connection info
    local last_connection = last_connections[player_index]
    if not last_connection then
        player.print("No previous neural connection found.")
        return
    end
    
    -- Find all entities across all surfaces
    local vehicle
    for _, surface in pairs(game.surfaces) do
        if last_connection.surface_index == surface.index then
            -- Look for specific entity type based on last connection
            local entity_type
            if last_connection.type == "spidertron" then
                entity_type = "spider-vehicle"
            elseif last_connection.type == "locomotive" then
                entity_type = "locomotive"
            elseif last_connection.type == "car" then
                entity_type = "car"
            else
                entity_type = last_connection.type
            end
            
            local entities = surface.find_entities_filtered{type = entity_type}
            
            for _, entity in pairs(entities) do
                if entity.unit_number == last_connection.vehicle_id then
                    vehicle = entity
                    break
                end
            end
            
            if vehicle then break end
        end
    end
    
    if not vehicle or not vehicle.valid then
        player.print("Previous vehicle could not be found. It may have been destroyed.")
        last_connections[player_index] = nil
        return
    end
    
    -- Check if player is already connected to a vehicle
    local already_connected = false
    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers and 
       storage.neural_spider_control.dummy_engineers[player_index] then
        already_connected = true
    end
    
    if already_connected then
        player.print("You are already connected to a vehicle. Disconnect first.")
        return
    end
    
    -- Reconnect based on vehicle type
    if vehicle.type == "spider-vehicle" then
        neural_connect.connect_to_spidertron({player_index = player_index, spidertron = vehicle})
    elseif vehicle.type == "locomotive" then
        neural_connect.connect_to_spidertron({player_index = player_index, spidertron = vehicle})
    elseif vehicle.type == "car" then
        neural_connect.connect_to_spidertron({player_index = player_index, spidertron = vehicle})
    else
        neural_connect.connect_to_spidertron({player_index = player_index, spidertron = vehicle})
    end
    
    log_debug("Reconnection attempt completed for player " .. player.name)
end

-- Update shortcut visibility based on available last connection
function neural_connect.update_shortcut_visibility(player)
    local player_index = player.index
    
    -- Update reconnect shortcut based on last connection availability
    local has_last_connection = last_connections[player_index] ~= nil
    
    -- Enable/disable the reconnect shortcut based on whether there's a last connection
    player.set_shortcut_available("reconnect-last-vehicle", has_last_connection)
    
    log_debug("Updated shortcut visibility for player " .. player.name .. 
              ", has_last_connection=" .. tostring(has_last_connection))
end

-- Helper functions

-- Check if a character is a dummy engineer
local function is_dummy_engineer(character)
    if not character or not character.valid then return false end
    if not storage then return false end
    
    -- Check if the character is in our dummy engineers storage
    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
        for player_index, dummy_data in pairs(storage.neural_spider_control.dummy_engineers) do
            if dummy_data then
                -- If it's stored as a table with entity reference and unit_number
                if type(dummy_data) == "table" and dummy_data.entity then
                    if dummy_data.entity == character then
                        return true
                    elseif character.unit_number and dummy_data.unit_number == character.unit_number then
                        return true
                    end
                -- Fallback for old format where we just stored the entity
                elseif dummy_data == character then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Check if a spider vehicle is in the restricted list
local function is_restricted_spider_vehicle(vehicle)
    -- Implement your logic to determine if a spider vehicle is restricted
    return false -- Placeholder
end

-- Clean up data when a connection is broken
local function clean_up_connection_data(player_index)
    local function safely_clear_data(control_data)
        if control_data then
            for _, table_name in ipairs({
                "original_characters", 
                "dummy_engineers", 
                "connected_spidertrons", 
                "connected_locomotives", 
                "original_health", 
                "original_surfaces", 
                "neural_connections",
                "original_character_ids",
                "dummy_engineer_ids",
                "connected_spidertron_ids",
                "connected_locomotive_ids"
            }) do
                if control_data[table_name] then
                    control_data[table_name][player_index] = nil
                end
            end
        end
    end

    safely_clear_data(storage.neural_spider_control)
    
    -- Clear health check function
    if storage.health_check_functions then
        storage.health_check_functions[player_index] = nil
    end
end

-- Event handlers
script.on_event(defines.events.on_entity_died, function(event)
    neural_connect.check_original_engineer_death(event)
    neural_connect.on_vehicle_destroyed(event)
end)

script.on_event(defines.events.on_player_driving_changed_state, function(event)
    local player = game.get_player(event.player_index)
    local vehicle = event.entity

    log_debug(string.format("Player %s driving state changed. Vehicle: %s", player.name, vehicle and vehicle.name or "None"))

    if player.vehicle then
        neural_connect.handle_player_entered_vehicle(player, vehicle)
    else
        neural_connect.handle_player_exited_vehicle(player, vehicle)
    end
end)

-- Neural connect functions

function neural_connect.handle_player_entered_vehicle(player, vehicle)
    log_debug(string.format("Player %s entered a vehicle: %s", player.name, vehicle.name))

    if vehicle.type == "locomotive" then
        neural_connect.handle_locomotive_entry(player, vehicle)
    elseif vehicle.type == "car" then
        neural_connect.handle_car_entry(player, vehicle)
    elseif is_restricted_spider_vehicle(vehicle) then
        neural_connect.handle_restricted_spider_entry(player, vehicle)
    end
end

function neural_connect.handle_player_exited_vehicle(player, vehicle)
    log_debug(string.format("Player %s exited a vehicle", player.name))

    if is_dummy_engineer(player.character) then
        neural_connect.handle_dummy_engineer_exit(player)
    end
end

function neural_connect.handle_locomotive_entry(player, locomotive)
    if space_elevator_compatibility then
        if space_elevator_compatibility.is_near_space_elevator(locomotive) or (storage.locomotives_near_elevators and storage.locomotives_near_elevators[locomotive.unit_number]) then
            neural_connect.handle_locomotive_near_elevator(player, locomotive)
        end
    else
        neural_connect.connect_to_spidertron({player_index = player.index, spidertron = locomotive})
    end
end

function neural_connect.handle_car_entry(player, car)
    -- Similar to locomotive entry but for cars
    neural_connect.connect_to_spidertron({player_index = player.index, spidertron = car})
end

function neural_connect.handle_restricted_spider_entry(player, vehicle)
    log_debug(string.format("WARNING: %s attempted to enter restricted spider vehicle: %s", player.name, vehicle.name))
    
    if not is_dummy_engineer(player.character) then
        player.driving = false
        player.print("You cannot directly control this type of spider vehicle.")
        log_debug(string.format("Player %s prevented from entering restricted spider vehicle: %s", player.name, vehicle.name))
    else
        log_debug(string.format("Dummy engineer allowed to enter restricted spider vehicle: %s", vehicle.name))
    end
end

function neural_connect.handle_locomotive_near_elevator(player, locomotive)
    local is_dummy_engineer = storage.neural_spider_control and
                              storage.neural_spider_control.dummy_engineers and
                              storage.neural_spider_control.dummy_engineers[player.index] == player.character

    if is_dummy_engineer then
        player.print("Cannot establish Remote connection near Space Elevator.", {r=1, g=0.5, b=0})
        neural_disconnect.disconnect_from_spidertron({player_index = player.index})
    end
end

function neural_connect.handle_dummy_engineer_exit(player)
    if storage.neural_spider_control.original_characters and storage.neural_spider_control.original_characters[player.index] then
        log_debug(string.format("Player %s returning to original engineer from vehicle", player.name))
        neural_disconnect.return_to_engineer(player, "spidertron")
    else
        log_debug(string.format("Error: Could not find original character for dummy engineer %s", player.name))
        player.print("Error: Could not revert to original character. Please report this issue.")
    end
end

function neural_connect.connect_to_spidertron(command)
    local player = game.get_player(command.player_index)
    local vehicle = command.spidertron
    
    -- Determine the vehicle type
    local vehicle_type = vehicle.type
    
    -- Vehicle-specific validations
    if vehicle_type == "spider-vehicle" and not vehicle.prototype.allow_passengers then
        player.print("This Spidertron model cannot take passengers. Neural connection aborted.")
        return
    end

    -- Check for Space Exploration compatibility if the mod is active
    if SE_compatibility and SE_compatibility.is_in_remote_view(player) then
        if SE_compatibility.toggle_off_remote_view(player) then
            --player.print("Remote view has been deactivated.")
        else
            --player.print("Failed to deactivate remote view. Please try again.")
            return
        end
    end

    if player.opened and player.opened.name == "map" then
        player.opened = nil
    end

    if player.opened_gui_type == defines.gui_type.map then
        player.close_map()
    end
    
    if not player.character then
        --player.print("Unable to connect. You don't have a character.")
        return
    end

    if vehicle.get_driver() then
        player.print("This vehicle is already occupied.")
        return
    end
    
    -- Disconnect from any existing connections first
    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers and 
       storage.neural_spider_control.dummy_engineers[player.index] then
        -- Store the current vehicle BEFORE disconnecting
        local source_vehicle = storage.neural_spider_control.connected_spidertrons[player.index]
        
        if source_vehicle then
            log_debug("Disconnecting from source vehicle #" .. source_vehicle.unit_number)
        else
            log_debug("Disconnecting but no source vehicle found")
        end
        
        neural_disconnect.disconnect_from_spidertron({
            player_index = player.index,
            source_spidertron = source_vehicle
        })
    end

    -- Initialize all necessary storage tables
    if not storage.neural_spider_control then storage.neural_spider_control = {} end
    if not storage.neural_spider_control.neural_connections then storage.neural_spider_control.neural_connections = {} end
    if not storage.neural_spider_control.connected_spidertrons then storage.neural_spider_control.connected_spidertrons = {} end
    if not storage.neural_spider_control.original_characters then storage.neural_spider_control.original_characters = {} end
    if not storage.neural_spider_control.original_health then storage.neural_spider_control.original_health = {} end
    if not storage.neural_spider_control.original_surfaces then storage.neural_spider_control.original_surfaces = {} end
    if not storage.neural_spider_control.dummy_engineers then storage.neural_spider_control.dummy_engineers = {} end
    
    -- Initialize ID tracking tables
    if not storage.neural_spider_control.connected_spidertron_ids then storage.neural_spider_control.connected_spidertron_ids = {} end
    if not storage.neural_spider_control.original_character_ids then storage.neural_spider_control.original_character_ids = {} end
    if not storage.neural_spider_control.dummy_engineer_ids then storage.neural_spider_control.dummy_engineer_ids = {} end
    
    -- Initialize vehicle type tracking
    if not storage.neural_spider_control.vehicle_types then storage.neural_spider_control.vehicle_types = {} end

    -- Store the neural connection details
    storage.neural_spider_control.neural_connections[player.index] = {
        spidertron = vehicle,
        original_character = player.character,
        original_surface = player.surface,
        original_position = player.position,
        connected_at = game.tick,
        vehicle_type = vehicle_type
    }
    
    -- Store the connected vehicle
    storage.neural_spider_control.connected_spidertrons[player.index] = vehicle
    storage.neural_spider_control.connected_spidertron_ids[player.index] = vehicle.unit_number
    storage.neural_spider_control.vehicle_types[player.index] = vehicle_type
    
    -- Store the original character and its initial health
    storage.neural_spider_control.original_characters[player.index] = player.character
    storage.neural_spider_control.original_character_ids[player.index] = player.character.unit_number
    storage.neural_spider_control.original_health[player.index] = player.character.health
    storage.neural_spider_control.original_surfaces[player.index] = player.surface.index

    -- Get zone information if Space Exploration is active
    local vehicle_zone, player_zone
    if SE_compatibility then
        vehicle_zone = SE_compatibility.get_zone_from_surface_index(vehicle.surface.index)
        player_zone = SE_compatibility.get_zone_from_surface_index(player.surface.index)
    end

    local dummy_engineer = vehicle.surface.create_entity{
        name = "character",
        position = vehicle.position,
        force = player.force
    }
    
    if not dummy_engineer then
        --player.print("Failed to create dummy engineer. Connection aborted.")
        return
    end

    -- Store in storage only
    storage.neural_spider_control.dummy_engineers[player.index] = {
        entity = dummy_engineer,
        unit_number = dummy_engineer.unit_number
    }

    -- Extend reach distance
    dummy_engineer.character_reach_distance_bonus = EXTENDED_REACH
    dummy_engineer.character_resource_reach_distance_bonus = EXTENDED_MINING_DISTANCE
    dummy_engineer.character_mining_speed_modifier = MINING_SPEED_MULTIPLIER
    dummy_engineer.character_item_pickup_distance_bonus = PICKUP_DISTANCE
    dummy_engineer.character_item_drop_distance_bonus = DROP_DISTANCE
    dummy_engineer.character_loot_pickup_distance_bonus = LOOT_PICKUP_DISTANCE

    -- Store the dummy engineer with its unit number
    storage.neural_spider_control.dummy_engineers[player.index] = {
        entity = dummy_engineer,
        unit_number = dummy_engineer.unit_number
    }
    storage.neural_spider_control.dummy_engineer_ids[player.index] = dummy_engineer.unit_number
    
    -- Disconnect the player from their current character
    local original_character = player.character
    player.character = nil

    -- Teleport the player to the vehicle's surface if necessary
    if player.surface ~= vehicle.surface then
        player.teleport(vehicle.position, vehicle.surface)
    end

    -- Now that the player is on the correct surface, assign the dummy engineer
    player.character = dummy_engineer

    -- Put the dummy engineer into the vehicle
    vehicle.set_driver(dummy_engineer)

    -- Store connection data for persistence
    storage.player_connections = storage.player_connections or {}
    storage.player_connections[player.index] = {
        original_character = original_character.unit_number,
        original_surface = player.surface.index,
        vehicle = vehicle.unit_number,
        position = {x = player.position.x, y = player.position.y}
    }

    -- Start health monitoring
    neural_connect.start_health_monitor(player)

    -- Display a message above the character's head
    player.create_local_flying_text{
        text = "Remote connection established.",
        position = vehicle.position,
        color = {r=0, g=1, b=0}
    }

    -- Format a user-friendly vehicle type name
    local vehicle_type_name = "Vehicle"
    if vehicle_type == "spider-vehicle" then
        vehicle_type_name = "Spidertron"
    elseif vehicle_type == "locomotive" then
        vehicle_type_name = "Locomotive"
    elseif vehicle_type == "car" then
        vehicle_type_name = "Car"
    end

    local connection_message = "Remote connection established with " .. vehicle_type_name .. " on surface: " .. vehicle.surface.name
    if vehicle_zone and player_zone then
        connection_message = connection_message .. " (Zone " .. vehicle_zone.name .. ")"
        if vehicle_zone.index ~= player_zone.index then
            connection_message = connection_message .. " (Different from your original zone: " .. player_zone.name .. ")"
        end
    end
    --player.print(connection_message)
    
    log_debug("Neural connection established for player " .. player.name .. " with vehicle #" .. vehicle.unit_number)

    -- Track this connection for later reconnection
    neural_connect.track_connection(player.index, vehicle_type_name:lower(), vehicle)

    -- Update shortcut visibility
    neural_connect.update_shortcut_visibility(player)
end

-- Unified vehicle destruction handler
function neural_connect.on_vehicle_destroyed(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    
    -- Check for any vehicle types we care about
    if entity.type == "spider-vehicle" or entity.type == "locomotive" or entity.type == "car" then
        if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
            for player_index, connected_vehicle in pairs(storage.neural_spider_control.connected_spidertrons) do
                if connected_vehicle and connected_vehicle.valid and connected_vehicle == entity then
                    local player = game.get_player(player_index)
                    if player and player.valid then
                        log_debug("Connected vehicle destroyed. Emergency disconnecting player " .. player.name)
                        neural_disconnect.emergency_disconnect(player, true)
                    end
                end
            end
        end
    end
end

function neural_connect.start_health_monitor(player)
    -- Instead of storing the function, just store the player index
    storage.health_check_players = storage.health_check_players or {}
    storage.health_check_players[player.index] = true
    
    -- Register the on_nth_tick handler if it's not already registered
    if not storage.health_check_registered then
        script.on_nth_tick(60, function(event)
            -- Call check_health for all players in the health_check_players table
            if storage.health_check_players then
                for player_index, _ in pairs(storage.health_check_players) do
                    local player = game.get_player(player_index)
                    if player then
                        neural_connect.check_engineer_health(player)
                    else
                        storage.health_check_players[player_index] = nil
                    end
                end
            end
        end)
        storage.health_check_registered = true
    end
    
    log_debug("Health monitor started for player " .. player.name)
end

function neural_connect.stop_health_monitor(player)
    storage.health_check_players = storage.health_check_players or {}
    
    if storage.health_check_players[player.index] then
        storage.health_check_players[player.index] = nil
        log_debug("Health monitor stopped for player " .. player.name)
    else
        log_debug("No health check found for player " .. player.name)
    end

    -- If no more players are being monitored, unregister the handler
    local any_monitored = false
    for _, _ in pairs(storage.health_check_players) do
        any_monitored = true
        break
    end
    
    if not any_monitored then
        script.on_nth_tick(60, nil)
        storage.health_check_registered = false
    end
end

function neural_connect.check_engineer_health(player)
    local player_index = player.index
    
    if not storage.neural_spider_control or
       not storage.neural_spider_control.original_characters or
       not storage.neural_spider_control.original_characters[player_index] then
        log_debug("No connection found for player " .. player.name)
        neural_connect.stop_health_monitor(player)
        return
    end

    local original_character = storage.neural_spider_control.original_characters[player_index]
    local initial_health = storage.neural_spider_control.original_health[player_index]

    if original_character and original_character.valid then
        local current_health = original_character.health
        if current_health <= 0 then
            log_debug("Current health <= 0 for player " .. player.name)
            neural_connect.handle_player_death(player, player_index)
        elseif current_health < initial_health then
            local damage_taken = math.floor((initial_health - current_health) * 10) / 10
            player.print({"", "Warning: Engineer taking damage! ", damage_taken, " damage taken."}, {r=1, g=0.5, b=0})
            neural_disconnect.disconnect_from_spidertron({player_index = player_index, reason = "damage"})
            neural_connect.stop_health_monitor(player)
        end
    else
        log_debug("Original character not valid for player " .. player.name)
        neural_connect.handle_player_death(player, player_index)
    end
end

function neural_connect.handle_player_death(player, player_index)
    log_debug("Handling death for player " .. player.name)
    
    -- Determine vehicle type
    local vehicle_type = "unknown"
    if storage.neural_spider_control and 
       storage.neural_spider_control.vehicle_types and 
       storage.neural_spider_control.vehicle_types[player_index] then
        vehicle_type = storage.neural_spider_control.vehicle_types[player_index]
    end
    
    -- Call the disconnect function
    neural_disconnect.disconnect_from_spidertron({player_index = player_index, reason = "death"})
    
    -- Notify the player
    player.print("Remote connection disengaged. Your original character has died.", {r=1, g=0, b=0})
    
    -- Stop health monitoring
    neural_connect.stop_health_monitor(player)
    
    log_debug("Death handling completed for player " .. player.name)
end

function neural_connect.check_original_engineer_death(event)
    local entity = event.entity
    if entity.type ~= "character" then
        return
    end

    log_debug("Character death detected: " .. serpent.line(entity))

    -- Check for original characters in neural control data
    if storage.neural_spider_control and storage.neural_spider_control.original_characters then
        for player_index, original_character in pairs(storage.neural_spider_control.original_characters) do
            if original_character == entity then
                log_debug("Matched dead character to player index: " .. player_index)
                local player = game.get_player(player_index)
                if player then
                    log_debug("Processing death for player: " .. player.name)
                    
                    -- Get vehicle type
                    local vehicle_type = storage.neural_spider_control.vehicle_types and 
                                      storage.neural_spider_control.vehicle_types[player_index] or "spidertron"
                                      
                    neural_disconnect.handle_character_death(player, vehicle_type)
                end
                return  -- Exit after handling the death
            end
        end
    end

    log_debug("No matching player found for the dead character")
end

return neural_connect