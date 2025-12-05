-- scripts/mod_data.lua
-- Module for managing mod data and initialization

local mod_data = {}

local function log_debug(message)
    log("[Neural Vehicle Control] " .. message)
end

-- Initialize mod data
function mod_data.init()
    log_debug("Initializing mod data")
    
    -- Initialize neural control data
    if not storage.neural_spider_control then
        storage.neural_spider_control = {}
    end
    
    -- Initialize tables for tracking connections and entities
    storage.neural_spider_control.dummy_engineers = storage.neural_spider_control.dummy_engineers or {}
    storage.neural_spider_control.original_characters = storage.neural_spider_control.original_characters or {}
    storage.neural_spider_control.connected_spidertrons = storage.neural_spider_control.connected_spidertrons or {}
    storage.neural_spider_control.original_surfaces = storage.neural_spider_control.original_surfaces or {}
    storage.neural_spider_control.neural_connections = storage.neural_spider_control.neural_connections or {}
    storage.neural_spider_control.original_health = storage.neural_spider_control.original_health or {}
    storage.neural_spider_control.vehicle_types = storage.neural_spider_control.vehicle_types or {}
    
    -- Initialize ID tracking for persistence
    storage.neural_spider_control.connected_spidertron_ids = storage.neural_spider_control.connected_spidertron_ids or {}
    storage.neural_spider_control.original_character_ids = storage.neural_spider_control.original_character_ids or {}
    storage.neural_spider_control.dummy_engineer_ids = storage.neural_spider_control.dummy_engineer_ids or {}
    
    -- Legacy compatibility
    storage.player_connections = storage.player_connections or {}
    
    log_debug("Mod data initialization complete")
end

-- Get storage data for neural vehicles
function mod_data.get_spider_dummy_engineers()
    if not storage.neural_spider_control then return nil end
    return storage.neural_spider_control.dummy_engineers
end

function mod_data.get_connected_spidertrons()
    if not storage.neural_spider_control then return nil end
    return storage.neural_spider_control.connected_spidertrons
end

function mod_data.get_original_characters()
    if not storage.neural_spider_control then return nil end
    return storage.neural_spider_control.original_characters
end

function mod_data.get_vehicle_types()
    if not storage.neural_spider_control then return nil end
    return storage.neural_spider_control.vehicle_types
end

-- Return the module
return mod_data