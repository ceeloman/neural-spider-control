local mod_data = require("scripts.mod_data")

local save_load = {}

-- Utility function for logging
local function log_debug(message)
    -- Logging disabled
end

-- This function should be called before saving the game
function save_load.prepare_for_save()
    -- Clear existing saved connections to prevent stale data
    global.saved_connections = {}
    
    -- Save spidertron connections
    if global.neural_spider_control and global.neural_spider_control.dummy_engineers then
        for player_index, dummy_data in pairs(global.neural_spider_control.dummy_engineers) do
            local dummy_engineer = type(dummy_data) == "table" and dummy_data.entity or dummy_data
            if not dummy_engineer or not dummy_engineer.valid then goto continue end
            
            local original_character = global.neural_spider_control.original_characters[player_index]
            local spidertron = global.neural_spider_control.connected_spidertrons[player_index]
            local original_surface_index = global.neural_spider_control.original_surfaces[player_index]
            
            if original_character and original_character.valid and spidertron and spidertron.valid then
                global.saved_connections[player_index] = {
                    type = "spidertron",
                    original_character_id = original_character.unit_number,
                    original_surface_id = original_surface_index,
                    vehicle_id = spidertron.unit_number,
                    dummy_engineer_id = type(dummy_data) == "table" and dummy_data.unit_number or dummy_engineer.unit_number,
                    original_health = global.neural_spider_control.original_health and global.neural_spider_control.original_health[player_index],
                    original_position = {
                        x = original_character.position.x,
                        y = original_character.position.y
                    }
                }
                log_debug("Saved spidertron connection for player " .. player_index .. 
                          " with spidertron ID " .. spidertron.unit_number)
            end
            
            ::continue::
        end
    end
    -- Log how many connections we saved
    local count = 0
    for _ in pairs(global.saved_connections) do count = count + 1 end
    log_debug("Saved " .. count .. " neural connections for persistence")
end

-- Helper function to find an entity by its unit number
local function find_entity_by_unit_number(unit_number, type_filter)
    if not unit_number then return nil end
    
    for _, surface in pairs(game.surfaces) do
        -- Filter based on the expected entity type
        local filter = {}
        if type_filter == "character" then
            filter = {type = "character"}
        elseif type_filter == "spidertron" then
            filter = {type = "spider-vehicle"}
        end
        
        -- Find entities matching our filter
        for _, entity in pairs(surface.find_entities_filtered(filter)) do
            if entity.unit_number == unit_number then
                return entity
            end
        end
    end
    return nil
end

-- Function to be called when the game loads
function save_load.restore_connections()
    if not global.saved_connections or not next(global.saved_connections) then
        log_debug("No saved connections to restore")
        return
    end
    
    log_debug("Starting to restore " .. table_size(global.saved_connections) .. " neural connections")
    
    -- Initialize global tables
    if not global.neural_spider_control then global.neural_spider_control = {} end
    
    -- Initialize subtables
    for _, table_name in ipairs({
        "dummy_engineers", "original_characters", "connected_spidertrons", 
        "original_surfaces", "original_health", "neural_connections"
    }) do
        global.neural_spider_control[table_name] = global.neural_spider_control[table_name] or {}
    end
    
    -- Store which players were successfully restored
    local restored_players = {}
    
    -- Process each saved connection
    for player_index, connection in pairs(global.saved_connections) do
        local player = game.get_player(player_index)
        if not player or not player.valid then
            log_debug("Player " .. player_index .. " not found or invalid")
            goto continue
        end
        
        log_debug("Attempting to restore connection for player " .. player.name .. 
                  " (type: " .. connection.type .. ")")
        
        -- Skip locomotive connections (feature removed)
        if connection.type == "locomotive" then
            log_debug("Skipping locomotive connection - feature removed")
            -- Clean up the saved connection
            global.saved_connections[player_index] = nil
            goto continue
        end
        
        -- Find the original character by unit number
        local original_character = find_entity_by_unit_number(connection.original_character_id, "character")
        if not original_character then
            log_debug("Couldn't find original character with unit number " .. 
                      (connection.original_character_id or "nil") .. 
                      " for player " .. player.name)
            goto continue
        end
        
        -- Find the vehicle (spidertron)
        local vehicle = find_entity_by_unit_number(connection.vehicle_id, "spidertron")
        if not vehicle then
            log_debug("Couldn't find spidertron with unit number " .. 
                      (connection.vehicle_id or "nil") .. 
                      " for player " .. player.name)
            goto continue
        end
        
        -- Determine if the player is already in control of a dummy engineer in the vehicle
        local in_vehicle_control = false
        if player.character and player.vehicle == vehicle then
            log_debug("Player " .. player.name .. " is already in spidertron control, updating references")
            in_vehicle_control = true
        end
        
        -- Use neural_spider_control
        local control_data = global.neural_spider_control
        
        -- Store the original character info
        control_data.original_characters[player_index] = original_character
        control_data.original_surfaces[player_index] = connection.original_surface_id
        if connection.original_health then
            control_data.original_health[player_index] = connection.original_health
        end
        
        -- Store the vehicle connection
        control_data.connected_spidertrons[player_index] = vehicle
        
        -- If player is in vehicle control mode, update dummy engineer reference
        if in_vehicle_control then
            control_data.dummy_engineers[player_index] = {
                entity = player.character,
                unit_number = player.character.unit_number
            }
            
            -- Restart health monitoring
            local neural_connect = require("scripts.neural_connect")
            neural_connect.start_health_monitor(player)
            
            table.insert(restored_players, player_index)
            log_debug("Successfully restored spidertron connection for player " .. player.name)
        else
            log_debug("Player " .. player.name .. " is not in spidertron control, partial restoration only")
        end
        
        ::continue::
    end
    
    -- Clean up the players we successfully restored
    for _, player_index in ipairs(restored_players) do
        global.saved_connections[player_index] = nil
    end
    
    log_debug("Restored " .. #restored_players .. " neural connections")
    
    -- Compatibility cleanup for old data structures
    global.saved_unit_numbers = nil
    global.saved_neural_connections = nil
    global.neural_connections_to_restore = nil
end

-- Helper function to get table size
function table_size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

return save_load