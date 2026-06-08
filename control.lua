-- control.lua - Neural Vehicle Control

local function log_debug(message)
    -- Logging disabled
end

-- Require modules
local neural_connect = require("scripts.neural_connect")
local neural_disconnect = require("scripts.neural_disconnect")
local mod_data = require("scripts.mod_data")
-- local local_control_centre = require("scripts.control_centre")  -- Use VCC mod now


-- Variable to hold the control_centre reference
local control_centre = nil
local use_control_centre = false

if script.active_mods["space-exploration"] then
    SE_compatibility = require("compatibility.se")
    space_elevator_compatibility = require("compatibility.space_elevator_compatibility")
    log_debug("Space Exploration compatibility loaded")
end

-- Track connections
local last_connections = {}
local dropdown_open = {}
local pending_dropdown_updates = {}

-- Helper function to count table entries
function count_table(t)
    if not t then return "nil" end
    
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return tostring(count)
end

-- Handle shortcut clicks
script.on_event(defines.events.on_lua_shortcut, function(event)
    local player = game.get_player(event.player_index)
    
    if event.prototype_name == "reconnect-last-vehicle" then
        neural_connect.reconnect_to_last_vehicle(event.player_index)
    elseif event.prototype_name == "open-neural-control" then
        if use_control_centre then
            -- Open Vehicle Control centre instead
            remote.call("vehicle-control-center", "open_control_centre", player.index)
        else
            -- Fall back to our own control centre
            control_centre.toggle_gui(player)
        end
    end
end)


script.on_event("reconnect-to-last-vehicle", function(event)
    local player = game.get_player(event.player_index)
    neural_connect.reconnect_to_last_vehicle(event.player_index)
end)

script.on_event(defines.events.on_player_joined_game, function(event)
    local player = game.get_player(event.player_index)
    
    -- Update shortcut visibility when player joins
    neural_connect.update_shortcut_visibility(player)
end)

-- Initialize global data
local function init_globals()
    mod_data.init()
    
    -- Initialize all storage tables needed for entity tracking
    storage.neural_spider_control = storage.neural_spider_control or {}
    storage.neural_spider_control.dummy_engineers = storage.neural_spider_control.dummy_engineers or {}
    storage.neural_spider_control.original_characters = storage.neural_spider_control.original_characters or {}
    storage.neural_spider_control.connected_spidertrons = storage.neural_spider_control.connected_spidertrons or {}
    storage.neural_spider_control.original_surfaces = storage.neural_spider_control.original_surfaces or {}
    storage.neural_spider_control.neural_connections = storage.neural_spider_control.neural_connections or {}
    storage.neural_spider_control.vehicle_types = storage.neural_spider_control.vehicle_types or {}
    
    -- Add ID tracking for persistent references
    storage.neural_spider_control.connected_spidertron_ids = storage.neural_spider_control.connected_spidertron_ids or {}
    storage.neural_spider_control.original_character_ids = storage.neural_spider_control.original_character_ids or {}
    storage.neural_spider_control.dummy_engineer_ids = storage.neural_spider_control.dummy_engineer_ids or {}
    -- Helper table to track entities by unit_number for quick lookup
    storage.neural_spider_control.units = storage.neural_spider_control.units or {}
    
    
    -- Health check functions
    storage.health_check_functions = storage.health_check_functions or {}
end

-- Migration function to clean up locomotive connections (removed feature)
local function migrate_remove_locomotives()
    log_debug("Migrating: Removing locomotive connections")
    
    -- Disconnect any active locomotive connections
    if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
        for player_index, vehicle in pairs(storage.neural_spider_control.connected_spidertrons) do
            if vehicle and vehicle.valid and vehicle.type == "locomotive" then
                local player = game.get_player(player_index)
                if player and player.valid then
                    log_debug("Disconnecting locomotive connection for player " .. player.name)
                    neural_disconnect.disconnect_from_spidertron({player_index = player_index})
                    player.print("Locomotive neural connection removed - feature discontinued (use in-game remote driving).", {r=1, g=0.5, b=0})
                end
            end
        end
    end
    
    -- Clean up locomotive data from global storage
    if global and global.neural_locomotive_control then
        log_debug("Cleaning up global.neural_locomotive_control")
        global.neural_locomotive_control = nil
    end
    
    -- Clean up locomotive data from storage
    if storage and storage.neural_locomotive_control then
        log_debug("Cleaning up storage.neural_locomotive_control")
        storage.neural_locomotive_control = nil
    end
    
    -- Clean up locomotive connections from saved_connections
    if global and global.saved_connections then
        local cleaned = false
        for player_index, connection in pairs(global.saved_connections) do
            if connection.type == "locomotive" then
                global.saved_connections[player_index] = nil
                cleaned = true
            end
        end
        if cleaned then
            log_debug("Cleaned locomotive connections from saved_connections")
        end
    end
    
    -- Clean up locomotives_near_elevators (Space Exploration compatibility)
    if storage and storage.locomotives_near_elevators then
        storage.locomotives_near_elevators = nil
    end
    
    log_debug("Locomotive migration complete")
end

-- Clean up storage data for a player
local function clean_up_storage_data(player_index)
    local function safely_clear_data(control_data)
        if control_data then
            for _, table_name in ipairs({
                "dummy_engineers", 
                "original_characters", 
                "connected_spidertrons", 
                "original_surfaces", 
                "neural_connections",
                "connected_spidertron_ids",
                "original_character_ids",
                "dummy_engineer_ids",
                "vehicle_types",
                "units"
            }) do
                if control_data[table_name] then
                    control_data[table_name][player_index] = nil
                end
            end
            
            if control_data.health_check_functions and control_data.health_check_functions[player_index] then
                script.on_nth_tick(60, nil)
                control_data.health_check_functions[player_index] = nil
            end
        end
    end

    safely_clear_data(storage.neural_spider_control)
    
    -- Clear health check function
    if storage.health_check_players then
        storage.health_check_players[player_index] = nil
    end
end

local function find_vehicle_by_unit_and_surface(unit_number, surface_index)
    if storage.neural_spider_control.units[unit_number] then
        local entity = storage.neural_spider_control.units[unit_number]
        if entity and entity.valid and entity.surface_index == surface_index then
            return entity
        end
    end
    local surface = game.get_surface(surface_index)
    if not surface then
        return nil
    end
    local entities = surface.find_entities_filtered{type = {"spider-vehicle", "car", "locomotive"}}
    for _, entity in ipairs(entities) do
        if entity.unit_number == unit_number then
            storage.neural_spider_control.units[unit_number] = entity
            return entity
        end
    end
    return nil
end

local function get_remote_selected_spider_vehicle(payload)
    if not payload or payload.context ~= "player_left_toolbar" then
        return nil
    end

    local player = game.get_player(payload.player_index)
    if not player or not player.valid then
        return nil
    end

    local stack = player.cursor_stack
    local holding_remote = stack and stack.valid_for_read and (stack.name == "spidertron-remote" or (stack.prototype and stack.prototype.type == "spidertron-remote"))
    if not holding_remote then
        return nil
    end

    local selected = payload.selected_vehicles or {}
    local selected_ref = selected[1]
    if not selected_ref or not selected_ref.unit_number or not selected_ref.surface_index then
        return nil
    end

    local vehicle = find_vehicle_by_unit_and_surface(selected_ref.unit_number, selected_ref.surface_index)
    if vehicle and vehicle.valid and vehicle.type == "spider-vehicle" then
        return vehicle
    end

    return nil
end

local function find_dummy_engineer_for_vehicle(vehicle)
    if not vehicle or not vehicle.valid then
        return nil
    end

    if neural_disconnect and neural_disconnect.find_orphaned_engineer_for_vehicle then
        local orphaned_engineer = neural_disconnect.find_orphaned_engineer_for_vehicle(vehicle)
        if orphaned_engineer and orphaned_engineer.valid then
            return orphaned_engineer
        end
    end

    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
        for _, dummy_data in pairs(storage.neural_spider_control.dummy_engineers) do
            local dummy_entity = type(dummy_data) == "table" and dummy_data.entity or dummy_data
            if dummy_entity and dummy_entity.valid and dummy_entity.vehicle == vehicle then
                return dummy_entity
            end
        end
    end

    return nil
end

local function same_vehicle_entity(a, b)
    if not a or not b or not a.valid or not b.valid then
        return false
    end
    if a == b then
        return true
    end
    return a.unit_number == b.unit_number and a.surface.index == b.surface.index
end

local function player_controls_vehicle(player_index, vehicle)
    if not player_index or not vehicle or not vehicle.valid then
        return false
    end
    if not storage.neural_spider_control then
        return false
    end

    local connected = storage.neural_spider_control.connected_spidertrons and
        storage.neural_spider_control.connected_spidertrons[player_index]
    if same_vehicle_entity(connected, vehicle) then
        return true
    end

    local connected_id = storage.neural_spider_control.connected_spidertron_ids and
        storage.neural_spider_control.connected_spidertron_ids[player_index]
    if connected_id and connected_id == vehicle.unit_number then
        if connected and connected.valid then
            return connected.surface.index == vehicle.surface.index
        end
        return true
    end

    return false
end

local function refresh_vcc_context_toolbar(player_index)
    if remote.interfaces["vehicle-control-center"] and
        remote.interfaces["vehicle-control-center"]["refresh_context_buttons"] then
        pcall(remote.call, "vehicle-control-center", "refresh_context_buttons", player_index)
    end
end

local function resolve_vehicle_from_payload(payload)
    local remote_selected_spider = get_remote_selected_spider_vehicle(payload)
    if payload and payload.context == "player_left_toolbar" then
        return remote_selected_spider
    end

    local vehicle_ref = payload and payload.vehicle
    local selected = payload and payload.selected_vehicles or {}
    local vehicle = nil

    if vehicle_ref then
        vehicle = find_vehicle_by_unit_and_surface(vehicle_ref.unit_number, vehicle_ref.surface_index)
    elseif selected and selected[1] then
        vehicle = find_vehicle_by_unit_and_surface(selected[1].unit_number, selected[1].surface_index)
    end
    return vehicle
end

local function find_dummy_engineer_by_unit_number(engineer_unit_number)
    if not engineer_unit_number then
        return nil
    end

    if storage.orphaned_dummy_engineers then
        local orphaned_data = storage.orphaned_dummy_engineers[engineer_unit_number]
        if orphaned_data and orphaned_data.entity and orphaned_data.entity.valid then
            return orphaned_data.entity
        end
    end

    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
        for _, dummy_data in pairs(storage.neural_spider_control.dummy_engineers) do
            local dummy_entity = type(dummy_data) == "table" and dummy_data.entity or dummy_data
            if dummy_entity and dummy_entity.valid and dummy_entity.unit_number == engineer_unit_number then
                return dummy_entity
            end
        end
    end

    return nil
end

local function open_engineer_inventory(player, engineer_unit_number)
    local engineer = find_dummy_engineer_by_unit_number(engineer_unit_number)
    if engineer and engineer.valid then
        player.centered_on = engineer
        player.opened = engineer
        return true
    end
    player.print("Engineer no longer exists.", {r=1, g=0.5, b=0})
    return false
end

-- Register remote interface for Vehicle Control Center
remote.add_interface("neural-spider-control", {
    connect_to_vehicle = function(params)
        -- Forward to the connect_to_spidertron function
        neural_connect.connect_to_spidertron({
            player_index = params.player_index,
            spidertron = params.vehicle
        })
    end,
    
    disconnect_from_vehicle = function(params)
        -- Forward to the disconnect_from_spidertron function
        neural_disconnect.disconnect_from_spidertron({
            player_index = params.player_index,
            source_spidertron = params.vehicle
        })
    end,
    
    -- Check if an entity is a dummy engineer
    is_dummy_engineer = function(entity)
        return is_dummy_engineer(entity)
    end,

    --- Vehicle Control Center row: allow neural connect when seat is empty, or only a reusable dummy (e.g. orphan) is driving; block if vehicle has an active NSC link or a real driver.
    vcc_neural_connect_menu_enabled = function(params)
        local unit_number = params and params.unit_number
        local surface_index = params and params.surface_index
        if not unit_number or not surface_index then
            return false
        end
        local vehicle = find_vehicle_by_unit_and_surface(unit_number, surface_index)
        if not vehicle or not vehicle.valid then
            return false
        end
        if neural_disconnect and neural_disconnect.vehicle_has_active_connection and neural_disconnect.vehicle_has_active_connection(vehicle) then
            return false
        end
        local driver = vehicle.get_driver()
        if not driver then
            return true
        end
        return find_dummy_engineer_for_vehicle(vehicle) ~= nil
    end,

    -- Get neural connection data - shows all orphaned dummy engineers
    get_connections = function(player_index)
        -- log("[NSC] get_connections called for player_index: " .. tostring(player_index))
        local result = {
            active = {},
            orphaned = {}
        }
        
        if not storage or not storage.neural_spider_control then
            -- log("[NSC]   storage or storage.neural_spider_control is nil")
            return result
        end
        
        -- log("[NSC]   storage.neural_spider_control exists")
        local control_data = storage.neural_spider_control
        
        -- Get active connections (player's own connection if they have one)
        if control_data.dummy_engineers and control_data.connected_spidertrons then
            -- log("[NSC]   Checking for active connection...")
            local dummy_data = control_data.dummy_engineers[player_index]
            if dummy_data then
                -- log("[NSC]     Found dummy_data for player " .. player_index)
                local dummy_engineer = type(dummy_data) == "table" and dummy_data.entity or dummy_data
                local connected_vehicle = control_data.connected_spidertrons[player_index]
                
                if dummy_engineer and dummy_engineer.valid and connected_vehicle and connected_vehicle.valid then
                    -- log("[NSC]     Adding active connection: engineer=" .. dummy_engineer.unit_number .. ", vehicle=" .. connected_vehicle.unit_number)
                    table.insert(result.active, {
                        player_index = player_index,
                        engineer_unit_number = dummy_engineer.unit_number,
                        vehicle_unit_number = connected_vehicle.unit_number,
                        vehicle_surface_index = connected_vehicle.surface.index,
                        vehicle_name = connected_vehicle.name
                    })
                -- else
                    -- log("[NSC]     Engineer or vehicle invalid")
                end
            -- else
                -- log("[NSC]     No dummy_data for player " .. player_index)
            end
        -- else
            -- log("[NSC]   dummy_engineers or connected_spidertrons doesn't exist")
        end
        
        -- Get ALL orphaned dummy engineers (no filtering)
        -- log("[NSC]   Checking for orphaned dummy engineers...")
        if storage.orphaned_dummy_engineers then
            -- log("[NSC]     storage.orphaned_dummy_engineers exists")
            local count = 0
            for engineer_unit_number, orphaned_data in pairs(storage.orphaned_dummy_engineers) do
                count = count + 1
                -- log("[NSC]     Processing orphaned entry #" .. count .. " (unit_number: " .. tostring(engineer_unit_number) .. ")")
                local engineer = orphaned_data.entity
                -- log("[NSC]       engineer exists: " .. tostring(engineer ~= nil))
                if engineer then
                    -- log("[NSC]       engineer.valid: " .. tostring(engineer.valid))
                    if engineer.valid then
                        -- Can't pass entity references through remote interface, but we have the data
                        table.insert(result.orphaned, {
                            engineer_unit_number = engineer_unit_number,
                            engineer_surface_index = engineer.surface.index,
                            engineer_surface_name = engineer.surface.name,
                            player_index = orphaned_data.player_index,
                            vehicle_id = orphaned_data.vehicle_id,
                            vehicle_surface = orphaned_data.vehicle_surface,
                            vehicle_type = orphaned_data.vehicle_type,
                            disconnected_at = orphaned_data.disconnected_at,
                            disconnect_reason = orphaned_data.disconnect_reason
                        })
                    -- else
                        -- log("[NSC]       Engineer is not valid, skipping")
                    end
                -- else
                    -- log("[NSC]       Engineer is nil, skipping")
                end
            end
            -- log("[NSC]     Processed " .. count .. " orphaned entries, added " .. #result.orphaned .. " to result")
        -- else
            -- log("[NSC]     storage.orphaned_dummy_engineers does not exist")
        end
        
        -- log("[NSC]   Returning result: " .. #result.active .. " active, " .. #result.orphaned .. " orphaned")
        return result
    end,
    
    -- Get all connections (for admins)
    get_all_connections = function()
        local result = {
            active = {},
            orphaned = {}
        }
        
        if not storage or not storage.neural_spider_control then
            return result
        end
        
        local control_data = storage.neural_spider_control
        
        -- Get all active connections
        if control_data.dummy_engineers and control_data.connected_spidertrons then
            for player_index, dummy_data in pairs(control_data.dummy_engineers) do
                local dummy_engineer = type(dummy_data) == "table" and dummy_data.entity or dummy_data
                local connected_vehicle = control_data.connected_spidertrons[player_index]
                
                if dummy_engineer and dummy_engineer.valid and connected_vehicle and connected_vehicle.valid then
                    table.insert(result.active, {
                        player_index = player_index,
                        engineer_unit_number = dummy_engineer.unit_number,
                        vehicle_unit_number = connected_vehicle.unit_number,
                        vehicle_surface_index = connected_vehicle.surface.index,
                        vehicle_name = connected_vehicle.name
                    })
                end
            end
        end
        
        -- Get all orphaned connections
        if storage.orphaned_dummy_engineers then
            for engineer_unit_number, orphaned_data in pairs(storage.orphaned_dummy_engineers) do
                local engineer = orphaned_data.entity
                if engineer and engineer.valid then
                    table.insert(result.orphaned, {
                        engineer_unit_number = engineer_unit_number,
                        player_index = orphaned_data.player_index,
                        vehicle_id = orphaned_data.vehicle_id,
                        vehicle_surface = orphaned_data.vehicle_surface,
                        vehicle_type = orphaned_data.vehicle_type,
                        disconnected_at = orphaned_data.disconnected_at,
                        disconnect_reason = orphaned_data.disconnect_reason
                    })
                end
            end
        end
        
        return result
    end,

    vcc_condition_neural_connect = function(payload)
        local player_index = payload and payload.player_index
        local vehicle = resolve_vehicle_from_payload(payload)

        if not vehicle or not vehicle.valid then
            return false
        end

        if player_controls_vehicle(player_index, vehicle) then
            return false
        end

        if neural_disconnect and neural_disconnect.vehicle_has_active_connection then
            return not neural_disconnect.vehicle_has_active_connection(vehicle)
        end
        return true
    end,

    vcc_condition_neural_disconnect = function(payload)
        local player_index = payload and payload.player_index
        local vehicle = resolve_vehicle_from_payload(payload)

        if not vehicle or not vehicle.valid then
            return false
        end

        return player_controls_vehicle(player_index, vehicle)
    end,

    vcc_tags_neural_connect = function(payload)
        local remote_selected_spider = get_remote_selected_spider_vehicle(payload)
        if payload and payload.context == "player_left_toolbar" then
            if not remote_selected_spider then
                return {}
            end
            return {
                unit_number = remote_selected_spider.unit_number,
                surface_index = remote_selected_spider.surface.index
            }
        end

        local vehicle_ref = payload and payload.vehicle
        local selected = payload and payload.selected_vehicles or {}
        local vehicle = nil
        if vehicle_ref then
            vehicle = find_vehicle_by_unit_and_surface(vehicle_ref.unit_number, vehicle_ref.surface_index)
        elseif selected and selected[1] then
            vehicle = find_vehicle_by_unit_and_surface(selected[1].unit_number, selected[1].surface_index)
        end
        if vehicle and vehicle.valid then
            return {
                unit_number = vehicle.unit_number,
                surface_index = vehicle.surface.index
            }
        end
        return {}
    end,

    vcc_click_neural_connect = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        local tags = payload.button_tags or {}
        local vehicle = nil
        if tags.unit_number and tags.surface_index then
            vehicle = find_vehicle_by_unit_and_surface(tags.unit_number, tags.surface_index)
        elseif payload.vehicle then
            vehicle = find_vehicle_by_unit_and_surface(payload.vehicle.unit_number, payload.vehicle.surface_index)
        elseif payload.selected_vehicles and payload.selected_vehicles[1] then
            local selected = payload.selected_vehicles[1]
            vehicle = find_vehicle_by_unit_and_surface(selected.unit_number, selected.surface_index)
        end

        if not vehicle or not vehicle.valid then
            player.print("Unable to connect. Please select or open a valid vehicle.")
            return false
        end

        local reopen_vehicle = player.opened and player.opened.valid and
            player.opened.unit_number == vehicle.unit_number and
            player.opened.surface.index == vehicle.surface.index

        player.opened = nil
        player.clear_cursor()
        neural_connect.connect_to_spidertron({player_index = player.index, spidertron = vehicle})
        if reopen_vehicle and vehicle.valid then
            player.opened = vehicle
        end
        refresh_vcc_context_toolbar(player.index)
        return true
    end,

    vcc_click_neural_disconnect = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        local tags = payload.button_tags or {}
        local vehicle = nil
        if tags.unit_number and tags.surface_index then
            vehicle = find_vehicle_by_unit_and_surface(tags.unit_number, tags.surface_index)
        elseif payload.vehicle then
            vehicle = find_vehicle_by_unit_and_surface(payload.vehicle.unit_number, payload.vehicle.surface_index)
        elseif payload.selected_vehicles and payload.selected_vehicles[1] then
            local selected = payload.selected_vehicles[1]
            vehicle = find_vehicle_by_unit_and_surface(selected.unit_number, selected.surface_index)
        end

        if not vehicle or not vehicle.valid then
            player.print("Unable to disconnect. Please select or open a valid vehicle.")
            return false
        end

        if not player_controls_vehicle(player.index, vehicle) then
            player.print("You are not remotely controlling this vehicle.")
            return false
        end

        player.opened = nil
        player.clear_cursor()
        neural_disconnect.disconnect_from_spidertron({
            player_index = player.index,
            source_spidertron = vehicle
        })
        refresh_vcc_context_toolbar(player.index)
        return true
    end,

    vcc_condition_orphaned_engineer = function(payload)
        local remote_selected_spider = get_remote_selected_spider_vehicle(payload)
        if payload and payload.context == "player_left_toolbar" then
            if not remote_selected_spider then
                return false
            end
            return find_dummy_engineer_for_vehicle(remote_selected_spider) ~= nil
        end

        local vehicle_ref = payload and payload.vehicle
        local selected = payload and payload.selected_vehicles or {}
        local vehicle = nil
        if vehicle_ref then
            vehicle = find_vehicle_by_unit_and_surface(vehicle_ref.unit_number, vehicle_ref.surface_index)
        elseif selected and selected[1] then
            vehicle = find_vehicle_by_unit_and_surface(selected[1].unit_number, selected[1].surface_index)
        end
        if not vehicle or not vehicle.valid then
            return false
        end
        return find_dummy_engineer_for_vehicle(vehicle) ~= nil
    end,

    vcc_tags_orphaned_engineer = function(payload)
        local remote_selected_spider = get_remote_selected_spider_vehicle(payload)
        if payload and payload.context == "player_left_toolbar" then
            if not remote_selected_spider then
                return {}
            end
            local dummy_engineer = find_dummy_engineer_for_vehicle(remote_selected_spider)
            if dummy_engineer and dummy_engineer.valid then
                return {engineer_unit_number = dummy_engineer.unit_number}
            end
            return {}
        end

        local vehicle_ref = payload and payload.vehicle
        local selected = payload and payload.selected_vehicles or {}
        local vehicle = nil
        if vehicle_ref then
            vehicle = find_vehicle_by_unit_and_surface(vehicle_ref.unit_number, vehicle_ref.surface_index)
        elseif selected and selected[1] then
            vehicle = find_vehicle_by_unit_and_surface(selected[1].unit_number, selected[1].surface_index)
        end
        if not vehicle or not vehicle.valid then
            return {}
        end
        local dummy_engineer = find_dummy_engineer_for_vehicle(vehicle)
        if dummy_engineer and dummy_engineer.valid then
            return {engineer_unit_number = dummy_engineer.unit_number}
        end
        return {}
    end,

    vcc_click_orphaned_engineer = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        local tags = payload.button_tags or {}
        if not tags.engineer_unit_number then
            player.print("Unable to find engineer reference.", {r=1, g=0.5, b=0})
            return false
        end
        return open_engineer_inventory(player, tags.engineer_unit_number)
    end,

    vcc_click_call_spider = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        if not remote.interfaces["vehicle-control-center"] or
           not remote.interfaces["vehicle-control-center"]["call_spidertron_to_location"] then
            return false
        end

        local function call_spidertron(unit_number, surface_index)
            remote.call("vehicle-control-center", "call_spidertron_to_location", {
                player_index = player.index,
                unit_number = unit_number,
                surface_index = surface_index
            })
        end

        if payload and payload.context == "player_left_toolbar" then
            local selected = payload.selected_vehicles or {}
            local called_any = false
            for _, ref in ipairs(selected) do
                if ref.unit_number and ref.surface_index then
                    local vehicle = find_vehicle_by_unit_and_surface(ref.unit_number, ref.surface_index)
                    if vehicle and vehicle.valid and vehicle.type == "spider-vehicle" then
                        call_spidertron(ref.unit_number, ref.surface_index)
                        called_any = true
                    end
                end
            end
            return called_any
        end

        local tags = payload.button_tags or {}
        local unit_number = tags.vehicle_unit_number or tags.unit_number
        local surface_index = tags.surface_index
        if not unit_number or not surface_index then
            return false
        end
        local vehicle = find_vehicle_by_unit_and_surface(unit_number, surface_index)
        if not vehicle or not vehicle.valid or vehicle.type ~= "spider-vehicle" then
            return false
        end
        call_spidertron(unit_number, surface_index)
        return true
    end,

    vcc_click_open_map = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        local tags = payload.button_tags or {}
        local unit_number = tags.vehicle_unit_number or tags.unit_number
        local surface_index = tags.surface_index
        if not unit_number or not surface_index then
            return false
        end
        local vehicle = find_vehicle_by_unit_and_surface(unit_number, surface_index)
        if not vehicle or not vehicle.valid then
            player.print("Vehicle no longer exists.", {r=1, g=0.5, b=0})
            return false
        end
        local follow_payload = {
            player_index = player.index,
            unit_number = unit_number,
            surface_index = surface_index
        }
        if remote.interfaces["vehicle-control-center"] and remote.interfaces["vehicle-control-center"]["follow_vehicle_in_map"] then
            remote.call("vehicle-control-center", "follow_vehicle_in_map", follow_payload)
            return true
        end
        if remote.interfaces["vehicle-control-centre"] and remote.interfaces["vehicle-control-centre"]["follow_vehicle_in_map"] then
            remote.call("vehicle-control-centre", "follow_vehicle_in_map", follow_payload)
            return true
        end
        if player.opened then
            player.opened = nil
        end
        local ok = pcall(function()
            player.centered_on = vehicle
        end)
        return ok
    end,

    vcc_tags_vehicle = function(payload)
        local remote_selected_spider = get_remote_selected_spider_vehicle(payload)
        if payload and payload.context == "player_left_toolbar" then
            if not remote_selected_spider then
                return {}
            end
            return {
                vehicle_unit_number = remote_selected_spider.unit_number,
                surface_index = remote_selected_spider.surface.index,
                unit_number = remote_selected_spider.unit_number
            }
        end

        local vehicle_ref = payload and payload.vehicle
        local selected = payload and payload.selected_vehicles or {}
        if not vehicle_ref and selected and selected[1] then
            vehicle_ref = selected[1]
        end
        if not vehicle_ref or not vehicle_ref.unit_number or not vehicle_ref.surface_index then
            return {}
        end
        return {
            vehicle_unit_number = vehicle_ref.unit_number,
            surface_index = vehicle_ref.surface_index,
            unit_number = vehicle_ref.unit_number
        }
    end,

    --- Keep visible in remote mode too; click handler falls back to remote-centered open.
    vcc_condition_open_inventory = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        local vehicle_ref = payload and payload.vehicle
        if vehicle_ref and vehicle_ref.unit_number and vehicle_ref.surface_index then
            local vehicle = find_vehicle_by_unit_and_surface(vehicle_ref.unit_number, vehicle_ref.surface_index)
            if vehicle and vehicle.valid and player.opened and player.opened.valid then
                if player.opened == vehicle then
                    return false
                end
                if player.opened.unit_number == vehicle.unit_number and player.opened.surface.index == vehicle.surface.index then
                    return false
                end
            end
        end
        return true
    end,

    vcc_click_open_inventory = function(payload)
        local player = payload and game.get_player(payload.player_index)
        if not player or not player.valid then
            return false
        end
        local tags = payload.button_tags or {}
        local vehicle = nil
        if tags.vehicle_unit_number and tags.surface_index then
            vehicle = find_vehicle_by_unit_and_surface(tags.vehicle_unit_number, tags.surface_index)
        elseif tags.unit_number and tags.surface_index then
            vehicle = find_vehicle_by_unit_and_surface(tags.unit_number, tags.surface_index)
        end
        if vehicle and vehicle.valid and player.opened and player.opened.valid then
            if player.opened == vehicle or (player.opened.unit_number == vehicle.unit_number and player.opened.surface.index == vehicle.surface.index) then
                return false
            end
        end
        if vehicle and vehicle.valid then
            local opened_success = pcall(function()
                player.opened = vehicle
            end)
            if opened_success and player.opened and player.opened.valid and player.opened.unit_number == vehicle.unit_number then
                return true
            end

            -- Match VCC inventory behavior: if direct open is not possible, jump to remote/map view first.
            local centered_success = pcall(function()
                player.centered_on = vehicle
            end)
            if not centered_success then
                return false
            end

            opened_success = pcall(function()
                player.opened = vehicle
            end)
            if opened_success and player.opened and player.opened.valid and player.opened.unit_number == vehicle.unit_number then
                return true
            end

            player.print("Unable to open vehicle inventory.", {r=1, g=0.5, b=0})
            return false
        end
        player.print("Vehicle no longer exists.", {r=1, g=0.5, b=0})
        return false
    end
})


-- Register the GUI handlers
function register_gui_handlers()
    -- Register control_centre GUI handlers
    if control_centre and control_centre.register_gui then
        control_centre.register_gui()
    end
end

-- Combined GUI click handler for all neural connection interfaces
function combined_gui_click_handler(event)
    if not event.element or not event.element.valid then return end

    local player = game.get_player(event.player_index)
    local element = event.element
    local element_name = element.name

    -- Handle player GUI toolbar buttons
    -- Handle both our button name and spidertron-logistics button name (in case they handle it but we need fallback)
    if element_name == "neural-spider-control_player_neural_connect" or 
       element_name == "spidertron-logistics_player_neural_connect" then
        local tags = element.tags
        if tags and tags.unit_number and tags.surface_index then
            local surface = game.get_surface(tags.surface_index)
            if surface then
                -- Find the spider by unit number
                local spider = nil
                local entities = surface.find_entities_filtered{type = {"spider-vehicle", "car"}}
                for _, entity in ipairs(entities) do
                    if entity.unit_number == tags.unit_number then
                        spider = entity
                        break
                    end
                end
                
                if spider and spider.valid then
                    -- Use remote interface if available (more reliable)
                    if remote.interfaces["neural-spider-control"] and 
                       remote.interfaces["neural-spider-control"]["connect_to_vehicle"] then
                        remote.call("neural-spider-control", "connect_to_vehicle", {
                            player_index = player.index,
                            vehicle = spider
                        })
                    else
                        -- Fallback to direct function call
                        neural_connect.connect_to_spidertron({player_index = player.index, spidertron = spider})
                    end
                else
                    player.print("Vehicle no longer exists.", {r=1, g=0.5, b=0})
                end
            else
                player.print("Surface not found.", {r=1, g=0.5, b=0})
            end
        else
            player.print("Select a vehicle with the spidertron remote, then use Neural Connect.")
        end
        return
    elseif element_name == "neural-spider-control_player_open_engineer" then
        local engineer_unit_number = element.tags and element.tags.engineer_unit_number
        
        if engineer_unit_number then
            -- Try to find the engineer by unit_number from storage
            local engineer = nil
            if storage.orphaned_dummy_engineers then
                local orphaned_data = storage.orphaned_dummy_engineers[engineer_unit_number]
                if orphaned_data and orphaned_data.entity and orphaned_data.entity.valid then
                    engineer = orphaned_data.entity
                end
            end
            
            -- Also check active connections in case it's no longer orphaned
            if not engineer and storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
                for _, dummy_data in pairs(storage.neural_spider_control.dummy_engineers) do
                    local dummy_entity = type(dummy_data) == "table" and dummy_data.entity or dummy_data
                    if dummy_entity and dummy_entity.valid and dummy_entity.unit_number == engineer_unit_number then
                        engineer = dummy_entity
                        break
                    end
                end
            end
            
            if engineer and engineer.valid then
                -- First center on the engineer (opens map view if needed, works across surfaces)
                player.centered_on = engineer
                
                -- Then open the engineer's inventory
                player.opened = engineer
                
                log_debug("Opened engineer inventory for player " .. player.name .. " (unit #" .. engineer_unit_number .. ")")
            else
                player.print("Engineer no longer exists.", {r=1, g=0.5, b=0})
                log_debug("Could not find engineer with unit_number " .. engineer_unit_number)
            end
        else
            player.print("Unable to find engineer reference.", {r=1, g=0.5, b=0})
        end
        return
    end

    -- Backwards compatibility for old relative button names
    if element_name == "nsc_neural_connect_button" or element_name == "neural-spider-control_neural_connect" then
        remote.call("neural-spider-control", "vcc_click_neural_connect", {
            player_index = player.index,
            button_tags = element.tags or {}
        })
        return
    elseif element_name == "nsc_orphaned_engineer_button" or element_name == "neural-spider-control_orphaned_engineer" then
        remote.call("neural-spider-control", "vcc_click_orphaned_engineer", {
            player_index = player.index,
            button_tags = element.tags or {}
        })
        return
    end

    -- Rest of handler for non-toolbar elements
    if element_name:find("^connect_") or 
       element_name == "neural_disconnect" or 
       element_name == "close_control_centre" then
        log_debug("Delegating to control_centre")
        control_centre.on_gui_click(event)
    elseif element_name == "close_neural_control_centre" then
        if player.gui.screen.neural_control_centre then
            player.gui.screen.neural_control_centre.destroy()
        end
    else
        log_debug("Unhandled GUI element clicked: " .. element_name)
    end
end


-- Helper function to check if a character is a dummy engineer
function is_dummy_engineer(entity)
    if not entity or not entity.valid then
        log_debug("Invalid entity passed to is_dummy_engineer")
        return false
    end
    
    log_debug("Checking if entity #" .. (entity.unit_number or "unknown") .. " is a dummy engineer")
    
    -- Safe check for storage table
    if not storage then
        log_debug("Storage table not available in is_dummy_engineer")
        return false
    end
    
    -- Check spider dummy engineers
    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
        for player_index, dummy_data in pairs(storage.neural_spider_control.dummy_engineers) do
            log_debug("Comparing against dummy for player " .. player_index)
            
            if type(dummy_data) == "table" and dummy_data.entity then
                -- Table format with entity reference and unit number
                log_debug("Dummy is stored as a table with entity reference")
                
                -- Check if entity references match
                if dummy_data.entity == entity then
                    log_debug("Match found by direct entity reference")
                    return true
                end
                
                -- Check if unit numbers match
                if entity.unit_number and dummy_data.unit_number == entity.unit_number then
                    log_debug("Match found by unit number: " .. entity.unit_number)
                    return true
                end
                
                log_debug("No match. Dummy unit number: " .. (dummy_data.unit_number or "nil") .. 
                          ", entity unit number: " .. (entity.unit_number or "nil"))
            elseif dummy_data and dummy_data.valid then
                -- Direct entity reference
                log_debug("Dummy is stored as direct entity reference")
                
                -- Check direct reference
                if dummy_data == entity then
                    log_debug("Match found by direct comparison")
                    return true
                end
                
                -- Check unit numbers as fallback
                if entity.unit_number and dummy_data.unit_number and 
                   dummy_data.unit_number == entity.unit_number then
                    log_debug("Match found by unit number fallback")
                    return true
                end
                
                log_debug("No match. Dummy unit number: " .. (dummy_data.unit_number or "nil") .. 
                          ", entity unit number: " .. (entity.unit_number or "nil"))
            else
                log_debug("Invalid dummy data format or dummy is not valid")
            end
        end
    else
        log_debug("Neural control or dummy engineers table not found")
    end

    -- Orphaned dummy engineers (still in vehicle, not in dummy_engineers table)
    if storage.orphaned_dummy_engineers then
        for _, orphaned_data in pairs(storage.orphaned_dummy_engineers) do
            local eng = orphaned_data.entity
            if eng and eng.valid then
                if eng == entity then
                    log_debug("Match found: orphaned dummy engineer")
                    return true
                end
                if entity.unit_number and eng.unit_number == entity.unit_number then
                    log_debug("Match found: orphaned dummy engineer by unit number")
                    return true
                end
            end
        end
    end

    log_debug("Entity is not a dummy engineer")
    return false
end

-- List of restricted spider vehicles
local restricted_spider_vehicles = {
    "spiderbot",
    "spiderdrone",
    -- Add more as needed
}

-- Function to check if a vehicle is a restricted spider vehicle
local function is_restricted_spider_vehicle(vehicle)
    return vehicle and vehicle.type == "spider-vehicle" and table.find(restricted_spider_vehicles, vehicle.name)
end

-- Helper function to find an element in a table
function table.find(t, value)
    for _, v in pairs(t) do
        if v == value then
            return true
        end
    end
    return false
end

-- Helper function to open the vehicle inventory
local function open_vehicle_inventory(player)
    if player.character and player.vehicle then
        player.opened = player.vehicle
    else
        player.print("You are not currently controlling a vehicle.")
    end
end

-- Helper function to find entities by unit number
function find_entity_by_unit_number(unit_number)
    if not unit_number then return nil end
    
    for _, surface in pairs(game.surfaces) do
        -- Try to find a character first
        local characters = surface.find_entities_filtered{type = "character"}
        for _, character in pairs(characters) do
            if character.unit_number == unit_number then
                return character
            end
        end
        
        -- Try to find a spider vehicle
        local spiders = surface.find_entities_filtered{type = "spider-vehicle"}
        for _, spider in pairs(spiders) do
            if spider.unit_number == unit_number then
                return spider
            end
        end
        
        -- Try to find a car
        local cars = surface.find_entities_filtered{type = "car"}
        for _, car in pairs(cars) do
            if car.unit_number == unit_number then
                return car
            end
        end
    end
    
    return nil
end

-- Function to restore entity references from unit numbers after loading
function restore_entity_references()
    -- log_debug("Starting entity reference restoration")
    
    if not storage then
        log_debug("ERROR: storage table not available")
        return
    end
    
    -- Restore vehicle references
    if storage.neural_spider_control then
        -- Restore connected vehicles
        if storage.neural_spider_control.connected_spidertron_ids then
            for player_index, vehicle_id in pairs(storage.neural_spider_control.connected_spidertron_ids) do
                local vehicle = find_entity_by_unit_number(vehicle_id)
                if vehicle then
                    storage.neural_spider_control.connected_spidertrons[player_index] = vehicle
                    log_debug("Restored vehicle reference for player " .. player_index)
                else
                    log_debug("Failed to restore vehicle reference for player " .. player_index)
                    -- Clean up invalid references
                    storage.neural_spider_control.connected_spidertron_ids[player_index] = nil
                end
            end
        end
        
        -- Restore original characters
        if storage.neural_spider_control.original_character_ids then
            for player_index, character_id in pairs(storage.neural_spider_control.original_character_ids) do
                local character = find_entity_by_unit_number(character_id)
                if character then
                    storage.neural_spider_control.original_characters[player_index] = character
                    log_debug("Restored original character reference for player " .. player_index)
                else
                    log_debug("Failed to restore original character reference for player " .. player_index)
                    -- Clean up invalid references
                    storage.neural_spider_control.original_character_ids[player_index] = nil
                    
                    -- Also clean up the related vehicle connection since we can't restore it properly
                    storage.neural_spider_control.connected_spidertron_ids[player_index] = nil
                    storage.neural_spider_control.connected_spidertrons[player_index] = nil
                end
            end
        end
        
        -- Restore dummy engineers
        if storage.neural_spider_control.dummy_engineer_ids then
            for player_index, dummy_id in pairs(storage.neural_spider_control.dummy_engineer_ids) do
                if type(dummy_id) == "number" then
                    -- If stored as just a unit number
                    local dummy_engineer = find_entity_by_unit_number(dummy_id)
                    if dummy_engineer then
                        storage.neural_spider_control.dummy_engineers[player_index] = {
                            entity = dummy_engineer,
                            unit_number = dummy_id
                        }
                        log_debug("Restored dummy engineer reference for player " .. player_index)
                    else
                        log_debug("Failed to restore dummy engineer reference for player " .. player_index)
                        -- Clean up invalid references
                        storage.neural_spider_control.dummy_engineer_ids[player_index] = nil
                    end
                end
            end
        end
    end
    
    -- Restart health monitoring for all active connections and restore last_connections
    if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
        for player_index, vehicle in pairs(storage.neural_spider_control.connected_spidertrons) do
            local player = game.get_player(player_index)
            if player and player.valid then
                neural_connect.start_health_monitor(player)
                log_debug("Restarted health monitoring for vehicle connection for player " .. player.name)
                
                -- Restore last_connections for reconnection functionality
                if vehicle and vehicle.valid then
                    local vehicle_type = storage.neural_spider_control.vehicle_types and 
                                       storage.neural_spider_control.vehicle_types[player_index] or "spider-vehicle"
                    local vehicle_type_name = "spidertron"
                    if vehicle_type == "spider-vehicle" then
                        vehicle_type_name = "spidertron"
                    elseif vehicle_type == "car" then
                        vehicle_type_name = "car"
                    end
                    neural_connect.track_connection(player_index, vehicle_type_name, vehicle)
                    log_debug("Restored last_connections for player " .. player.name .. " with " .. vehicle_type_name .. " #" .. vehicle.unit_number)
                end
            end
        end
    end
    
    log_debug("Entity reference restoration completed")
end

-- Function to validate connections after loading
local function validate_connections()
    log_debug("Validating neural connections")
    
    -- Check each connected player
    if storage.neural_spider_control and storage.neural_spider_control.connected_spidertron_ids then
        for player_index, _ in pairs(storage.neural_spider_control.connected_spidertron_ids) do
            local player = game.get_player(player_index)
            
            -- Make sure all required references exist and are valid
            local vehicle_valid = storage.neural_spider_control.connected_spidertrons and 
                               storage.neural_spider_control.connected_spidertrons[player_index] and
                               storage.neural_spider_control.connected_spidertrons[player_index].valid
                                  
            local dummy_valid = storage.neural_spider_control.dummy_engineers and
                             storage.neural_spider_control.dummy_engineers[player_index]
                             
            if type(dummy_valid) == "table" then
                dummy_valid = dummy_valid.entity and dummy_valid.entity.valid
            else
                dummy_valid = dummy_valid and dummy_valid.valid
            end
            
            local original_valid = storage.neural_spider_control.original_characters and
                                storage.neural_spider_control.original_characters[player_index] and
                                storage.neural_spider_control.original_characters[player_index].valid
            
            local all_valid = player and player.valid and vehicle_valid and dummy_valid and original_valid
            
            if not all_valid then
                log_debug("Invalid connection found for player " .. player_index .. ", cleaning up")
                clean_up_storage_data(player_index)
                
                -- If player exists, notify them
                if player and player.valid then
                    player.print("Neural connection could not be restored - the connected entity no longer exists.")
                end
            else
                log_debug("Valid connection found for player " .. player.name)
            end
        end
    end
    
    log_debug("Connection validation completed")
end

local function register_with_vehicle_control_centre()
    if not remote.interfaces["vehicle-control-center"] or
       not remote.interfaces["vehicle-control-center"]["register_context_button"] then
        return
    end

    log_debug("Registering NSC context buttons with Vehicle Control Center")

    local registrations = {
        {
            button_id = "neural_connect_vehicle",
            context = "vehicle_relative",
            vehicle_types = {"spider-vehicle", "car"},
            priority = 5,
            sprite = "neural-connection-sprite",
            tooltip = "Neural Connect",
            condition_action = "vcc_condition_neural_connect",
            tags_action = "vcc_tags_neural_connect",
            click_action = "vcc_click_neural_connect"
        },
        {
            button_id = "neural_disconnect_vehicle",
            context = "vehicle_relative",
            vehicle_types = {"spider-vehicle", "car"},
            priority = 5,
            sprite = "neural-connection-sprite",
            tooltip = "Neural Disconnect",
            style = "nsc_neural_disconnect_button",
            toggled = false,
            condition_action = "vcc_condition_neural_disconnect",
            tags_action = "vcc_tags_neural_connect",
            click_action = "vcc_click_neural_disconnect"
        },
        {
            button_id = "orphaned_engineer_vehicle",
            context = "vehicle_relative",
            vehicle_types = {"spider-vehicle", "car"},
            priority = 9,
            sprite = "utility/player_force_icon",
            tooltip = "Open Remote Engineer Inventory",
            condition_action = "vcc_condition_orphaned_engineer",
            tags_action = "vcc_tags_orphaned_engineer",
            click_action = "vcc_click_orphaned_engineer"
        },
        {
            button_id = "call_spider_vehicle",
            context = "vehicle_relative",
            vehicle_types = {"spider-vehicle"},
            priority = 10,
            sprite = "vcc-whistle",
            tooltip = "Call spidertron to this location",
            tags_action = "vcc_tags_vehicle",
            click_action = "vcc_click_call_spider"
        },
        {
            button_id = "open_map_vehicle",
            context = "vehicle_relative",
            vehicle_types = {"spider-vehicle", "car"},
            priority = 11,
            sprite = "vcc-map",
            tooltip = "Open Map at Vehicle Location",
            tags_action = "vcc_tags_vehicle",
            click_action = "vcc_click_open_map"
        },
        {
            button_id = "open_inventory_vehicle",
            context = "vehicle_relative",
            vehicle_types = {"spider-vehicle", "car"},
            priority = 12,
            sprite = "entity/steel-chest",
            tooltip = "Open Vehicle Inventory",
            condition_action = "vcc_condition_open_inventory",
            tags_action = "vcc_tags_vehicle",
            click_action = "vcc_click_open_inventory"
        },
        {
            button_id = "neural_connect_player",
            context = "player_left_toolbar",
            vehicle_types = {"spider-vehicle"},
            priority = 5,
            sprite = "neural-connection-sprite",
            tooltip = "Neural Connect",
            condition_action = "vcc_condition_neural_connect",
            tags_action = "vcc_tags_neural_connect",
            click_action = "vcc_click_neural_connect"
        },
        {
            button_id = "neural_disconnect_player",
            context = "player_left_toolbar",
            vehicle_types = {"spider-vehicle"},
            priority = 5,
            sprite = "neural-connection-sprite",
            tooltip = "Neural Disconnect",
            style = "nsc_neural_disconnect_button",
            toggled = false,
            condition_action = "vcc_condition_neural_disconnect",
            tags_action = "vcc_tags_neural_connect",
            click_action = "vcc_click_neural_disconnect"
        },
        {
            button_id = "orphaned_engineer_player",
            context = "player_left_toolbar",
            vehicle_types = {"spider-vehicle"},
            priority = 9,
            sprite = "utility/player_force_icon",
            tooltip = "Open Remote Engineer Inventory",
            condition_action = "vcc_condition_orphaned_engineer",
            tags_action = "vcc_tags_orphaned_engineer",
            click_action = "vcc_click_orphaned_engineer"
        },
        {
            button_id = "call_spider_player",
            context = "player_left_toolbar",
            vehicle_types = {"spider-vehicle"},
            priority = 10,
            sprite = "vcc-whistle",
            tooltip = "Call spidertron to this location",
            tags_action = "vcc_tags_vehicle",
            click_action = "vcc_click_call_spider"
        },
        {
            button_id = "open_map_player",
            context = "player_left_toolbar",
            vehicle_types = {"spider-vehicle"},
            priority = 11,
            sprite = "vcc-map",
            tooltip = "Open Map at Vehicle Location",
            tags_action = "vcc_tags_vehicle",
            click_action = "vcc_click_open_map"
        },
        {
            button_id = "open_inventory_player",
            context = "player_left_toolbar",
            vehicle_types = {"spider-vehicle"},
            priority = 12,
            sprite = "entity/steel-chest",
            tooltip = "Open Vehicle Inventory",
            condition_action = "vcc_condition_open_inventory",
            tags_action = "vcc_tags_vehicle",
            click_action = "vcc_click_open_inventory"
        }
    }

    for _, registration in ipairs(registrations) do
        pcall(remote.call, "vehicle-control-center", "register_context_button", "neural-spider-control", registration.button_id, registration)
    end

    pcall(remote.call, "vehicle-control-center", "refresh_context_buttons")
    log_debug("Registered NSC context buttons with Vehicle Control Center")
end


-- Event handlers

-- Initialize the mod
script.on_init(function()
    log_debug("Initializing Neural Vehicle Control")
    init_globals()

    if remote.interfaces["vehicle-control-center"] then
        use_control_centre = true
        log_debug("Vehicle Control centre detected, using it")
        register_with_vehicle_control_centre()
    else
        use_control_centre = false
        log_debug("Vehicle Control centre not found, using fallback GUI")
        register_gui_handlers()
    end

    log_debug("Initialization complete")
end)

script.on_configuration_changed(function(data)
    log_debug("Configuration changed, updating storage data")
    init_globals()
    
    -- Migrate: Remove locomotive connections
    migrate_remove_locomotives()

    if remote.interfaces["vehicle-control-center"] then
        use_control_centre = true
        log_debug("Vehicle Control centre detected on config change")
        register_with_vehicle_control_centre()
    else
        use_control_centre = false
        log_debug("Vehicle Control centre not found on config change")
        register_gui_handlers()
    end

    log_debug("Configuration update complete")
end)

-- Handle loading a saved game
script.on_load(function()
    log_debug("on_load running, storage exists: " .. tostring(storage ~= nil))
end)

-- Register first tick handler to restore entity references
script.on_event(defines.events.on_tick, function(event)
    if event.tick == 1 then
        log_debug("First tick, storage exists: " .. tostring(storage ~= nil))
        restore_entity_references()
        validate_connections()
        if remote.interfaces["vehicle-control-center"] then
            use_control_centre = true
            register_with_vehicle_control_centre()
            if remote.interfaces["vehicle-control-center"]["refresh_context_buttons"] then
                pcall(remote.call, "vehicle-control-center", "refresh_context_buttons")
            end
        end
        script.on_event(defines.events.on_tick, nil) -- Unregister this handler
    end
end)

-- Register standard event handlers
script.on_event(defines.events.on_gui_opened, function(event)
    -- Check if player opened an orphaned dummy engineer's inventory directly
    -- Only destroy if the engineer is truly abandoned (not in a vehicle)
    -- If the engineer is still in a vehicle, it's being used and should not be destroyed
    if event.gui_type == defines.gui_type.entity and event.entity and event.entity.valid then
        if event.entity.type == "character" then
            local character = event.entity
            local player = game.get_player(event.player_index)
            
            -- Check if this is an orphaned dummy engineer
            if storage.orphaned_dummy_engineers then
                for unit_number, data in pairs(storage.orphaned_dummy_engineers) do
                    if data.entity == character then
                        -- Only destroy if the engineer is not in a vehicle (truly abandoned)
                        -- If it's still in a vehicle, it's being used and we should allow access
                        if not character.vehicle or not character.vehicle.valid then
                            log_debug("Player " .. player.name .. " interacted with abandoned orphaned dummy engineer #" .. unit_number)
                            -- Force destroy and spill
                            neural_disconnect.force_destroy_orphaned_engineer(character, data.player_index, true)
                            player.print("Dummy engineer cleaned up.", {r=1, g=0.5, b=0})
                            -- Close the GUI since engineer is destroyed
                            player.opened = nil
                            return
                        else
                            -- Engineer is still in a vehicle, allow normal access
                            log_debug("Player " .. player.name .. " opened orphaned dummy engineer #" .. unit_number .. " inventory (still in vehicle)")
                        end
                    end
                end
            end
        elseif event.entity.type == "spider-vehicle" or event.entity.type == "car" then
            local player = game.get_player(event.player_index)
            if player and player.valid and remote.interfaces["vehicle-control-center"] and remote.interfaces["vehicle-control-center"]["refresh_context_buttons"] then
                pcall(remote.call, "vehicle-control-center", "refresh_context_buttons", player.index)
            end
        end
    end
end)

-- Access vehicle inventory (only if SpidertronEnhancements is not installed to avoid conflicts)
if not script.active_mods["SpidertronEnhancements"] and not script.active_mods["spidertron-enhancements"] then
    script.on_event("neural-spidertron-inventory", function(event)
        local player = game.get_player(event.player_index)
        open_vehicle_inventory(player)
    end)
end

-- Handle player entering/exiting vehicles
script.on_event(defines.events.on_player_driving_changed_state, function(event)
    local player = game.get_player(event.player_index)
    local vehicle = event.entity
    
    log_debug(string.format("Player %s driving state changed. Vehicle: %s", player.name, vehicle and vehicle.name or "None"))
    
    if player.vehicle then
        log_debug("Player entered a vehicle")
        
        -- Check if vehicle has an active remote connection
        local has_active_connection, active_player_index = neural_disconnect.vehicle_has_active_connection(vehicle)
        if has_active_connection and not is_dummy_engineer(player.character) then
            -- Player trying to physically enter a vehicle with active remote connection
            player.driving = false
            player.print("Cannot enter: Remote connection active. Disconnect first.", {r=1, g=0.5, b=0})
            log_debug("Player " .. player.name .. " prevented from entering vehicle with active remote connection")
            return
        end
        
        -- Check if vehicle has an orphaned dummy engineer
        local orphaned_engineer, orphaned_data = neural_disconnect.find_orphaned_engineer_for_vehicle(vehicle)
        if orphaned_engineer and orphaned_engineer.valid and not is_dummy_engineer(player.character) then
            -- Player physically entering vehicle with orphaned engineer
            -- Let them enter normally, then clean up the orphaned engineer
            log_debug("Player " .. player.name .. " entering vehicle with orphaned engineer, cleaning up orphaned engineer")
            
            -- Store unit_number before destroying (can't access after destroy)
            local engineer_unit_number = orphaned_engineer.unit_number
            
            -- Cancel crafting queue
            neural_disconnect.cancel_crafting_queue(orphaned_engineer)
            
            -- Transfer inventory: vehicle first, then player, then spill overflow
            -- Get vehicle type from orphaned_data
            local vehicle_type = orphaned_data and orphaned_data.vehicle_type or "spider-vehicle"
            local items_spilled = neural_disconnect.transfer_inventory_to_vehicle(
                orphaned_engineer, 
                vehicle, 
                vehicle_type, 
                player.index
            )
            
            -- Remove from orphaned list BEFORE destroying (need unit_number)
            if storage.orphaned_dummy_engineers then
                storage.orphaned_dummy_engineers[engineer_unit_number] = nil
            end
            
            -- Destroy the orphaned engineer
            if orphaned_engineer.valid then
                orphaned_engineer.destroy()
            end
            
            -- Show message
            local message = items_spilled and 
                "Remote connected engineer destroyed, items transferred (some spilled)" or
                "Remote connected engineer destroyed, items transferred"
            for _, p in pairs(game.players) do
                if p.surface == vehicle.surface then
                    p.create_local_flying_text{
                        text = message,
                        position = vehicle.position,
                        color = {r=1, g=0.5, b=0}
                    }
                end
            end
            
            -- Ensure player's character is in the driver's seat
            if player.character and player.character.valid then
                if player.character.vehicle ~= vehicle or vehicle.get_driver() ~= player.character then
                    log_debug("Player not in driver's seat after entering, moving to driver's seat")
                    vehicle.set_driver(player.character)
                end
            end
        end
        
        if is_restricted_spider_vehicle(vehicle) then
            log_debug(string.format("WARNING: %s attempted to enter restricted spider vehicle: %s", player.name, vehicle.name))
            
            if not is_dummy_engineer(player.character) then
                player.driving = false
                player.print("You cannot directly control this type of spider vehicle.")
                log_debug(string.format("Player %s prevented from entering restricted spider vehicle: %s", player.name, vehicle.name))
            else
                log_debug(string.format("Dummy engineer allowed to enter restricted spider vehicle: %s", vehicle.name))
            end
        end
    else
        log_debug("Player exited a vehicle")
        
        -- Log character details
        log_debug("Character valid: " .. tostring(player.character and player.character.valid))
        if player.character and player.character.valid then
            log_debug("Character unit number: " .. tostring(player.character.unit_number))
        end
        
        -- Check if this is a dummy engineer
        -- Skip if we're in the middle of reconnecting (to prevent exit handler from interfering)
        if storage.reconnecting_players and storage.reconnecting_players[player.index] then
            log_debug("Player is reconnecting, skipping exit handler")
            return
        end
        
        if is_dummy_engineer(player.character) then
            log_debug("Dummy engineer detected, checking for original character")
            
            -- Check if we can find the original character
            if storage and storage.neural_spider_control and
               storage.neural_spider_control.original_characters and
               storage.neural_spider_control.original_characters[player.index] then
                log_debug("Original character found, returning to engineer")
                neural_disconnect.return_to_engineer(player, "spidertron")
            else
                log_debug("No original character found for dummy engineer")
                player.print("Error: Could not revert to original character. Please report this issue.")
            end
        else
            log_debug("Not a dummy engineer, skipping return to engineer")
        end
    end
end)

-- Handle player respawn
script.on_event(defines.events.on_player_respawned, function(event)
    local player = game.get_player(event.player_index)
    if not player then return end

    log_debug("Player " .. player.name .. " has respawned")
    clean_up_storage_data(player.index)
    log_debug("Respawn handling completed for player " .. player.name)
end)

-- Handle entity death events
script.on_event(defines.events.on_entity_died, function(event)
    local entity = event.entity
    -- Pass to appropriate handlers
    if entity.type == "character" then
        log_debug("Character died: " .. entity.unit_number)
        neural_connect.check_original_engineer_death(event)
    elseif entity.type == "spider-vehicle" or entity.type == "car" then
        log_debug(entity.type .. " died: " .. entity.unit_number)
        neural_connect.on_vehicle_destroyed(event)
    end
end)

-- Handle map editor toggle - save connection state before entering editor
script.on_event(defines.events.on_pre_player_toggled_map_editor, function(event)
    local player = game.get_player(event.player_index)
    -- game.print("[MapEditor] on_pre_player_toggled_map_editor fired for player: " .. (player and player.name or "nil"))
    if not player or not player.valid then 
        -- game.print("[MapEditor] Player invalid, returning")
        return 
    end
    
    -- game.print("[MapEditor] Checking for neural connection...")
    -- game.print("[MapEditor] storage.neural_spider_control exists: " .. tostring(storage.neural_spider_control ~= nil))
    
    -- Check if player is in a dummy engineer (has active neural connection)
    if storage.neural_spider_control and 
       storage.neural_spider_control.dummy_engineers and
       storage.neural_spider_control.dummy_engineers[player.index] then
        
        -- game.print("[MapEditor] Found dummy_engineers entry for player")
        local dummy_data = storage.neural_spider_control.dummy_engineers[player.index]
        local dummy_engineer = type(dummy_data) == "table" and dummy_data.entity or dummy_data
        
        -- game.print("[MapEditor] dummy_engineer valid: " .. tostring(dummy_engineer and dummy_engineer.valid))
        -- game.print("[MapEditor] player.character: " .. tostring(player.character ~= nil))
        -- game.print("[MapEditor] player.character == dummy_engineer: " .. tostring(player.character == dummy_engineer))
        
        -- Verify the player is currently controlling this dummy engineer
        if dummy_engineer and dummy_engineer.valid and player.character == dummy_engineer then
            -- game.print("[MapEditor] Player is controlling dummy engineer, saving state...")
            -- Save connection state for restoration after editor
            storage.map_editor_connections = storage.map_editor_connections or {}
            local vehicle = storage.neural_spider_control.connected_spidertrons[player.index]
            local vehicle_unit_number = vehicle and vehicle.valid and vehicle.unit_number or nil
            
            storage.map_editor_connections[player.index] = {
                dummy_engineer_unit_number = dummy_engineer.unit_number,
                vehicle_unit_number = vehicle_unit_number,
                saved_at = game.tick
            }
            -- game.print("[MapEditor] Saved state - dummy_engineer: " .. dummy_engineer.unit_number .. ", vehicle: " .. tostring(vehicle_unit_number))
            log_debug("Saved neural connection state for player " .. player.name .. " before entering map editor")
        else
            -- game.print("[MapEditor] Player is NOT controlling dummy engineer - skipping save")
        end
    else
        -- game.print("[MapEditor] No dummy_engineers entry found for player")
    end
end)

-- Handle map editor toggle - restore connection after exiting editor
script.on_event(defines.events.on_player_toggled_map_editor, function(event)
    local player = game.get_player(event.player_index)
    -- game.print("[MapEditor] on_player_toggled_map_editor fired for player: " .. (player and player.name or "nil"))
    if not player or not player.valid then 
        -- game.print("[MapEditor] Player invalid, returning")
        return 
    end
    
    -- Check player's controller type to determine if they just exited editor mode
    -- If controller_type is NOT editor, they just exited editor mode
    local is_in_editor = player.controller_type == defines.controllers.editor
    -- game.print("[MapEditor] Player controller_type: " .. tostring(player.controller_type) .. ", is_in_editor: " .. tostring(is_in_editor))
    
    -- Only restore when exiting editor mode (controller_type is NOT editor)
    if not is_in_editor then
        -- game.print("[MapEditor] Editor mode turned OFF, checking for saved connection...")
        -- Check if we saved a connection state for this player
        if storage.map_editor_connections and storage.map_editor_connections[player.index] then
            -- game.print("[MapEditor] Found saved connection state!")
            local saved_state = storage.map_editor_connections[player.index]
            -- game.print("[MapEditor] Saved state - dummy_engineer_unit_number: " .. tostring(saved_state.dummy_engineer_unit_number) .. 
            --           ", vehicle_unit_number: " .. tostring(saved_state.vehicle_unit_number))
            
            -- Find the dummy engineer by unit number
            local dummy_engineer = saved_state.dummy_engineer_unit_number and 
                                   find_entity_by_unit_number(saved_state.dummy_engineer_unit_number) or nil
            
            -- game.print("[MapEditor] Found dummy_engineer: " .. tostring(dummy_engineer ~= nil) .. 
            --           ", valid: " .. tostring(dummy_engineer and dummy_engineer.valid))
            
            -- Find the vehicle by unit number
            local vehicle = saved_state.vehicle_unit_number and 
                           find_entity_by_unit_number(saved_state.vehicle_unit_number) or nil
            
            -- game.print("[MapEditor] Found vehicle: " .. tostring(vehicle ~= nil) .. 
            --           ", valid: " .. tostring(vehicle and vehicle.valid))
            
            -- Restore connection if both dummy engineer and vehicle are valid
            if dummy_engineer and dummy_engineer.valid and vehicle and vehicle.valid then
                -- game.print("[MapEditor] Both entities valid, restoring connection...")
                log_debug("Restoring neural connection for player " .. player.name .. " after exiting map editor")
                
                -- Set flag to prevent exit handler from interfering during restoration
                storage.reconnecting_players = storage.reconnecting_players or {}
                storage.reconnecting_players[player.index] = true
                
                -- Ensure storage tables are properly initialized
                if not storage.neural_spider_control then storage.neural_spider_control = {} end
                if not storage.neural_spider_control.dummy_engineers then storage.neural_spider_control.dummy_engineers = {} end
                if not storage.neural_spider_control.connected_spidertrons then storage.neural_spider_control.connected_spidertrons = {} end
                if not storage.neural_spider_control.vehicle_types then storage.neural_spider_control.vehicle_types = {} end
                if not storage.neural_spider_control.dummy_engineer_ids then storage.neural_spider_control.dummy_engineer_ids = {} end
                if not storage.neural_spider_control.connected_spidertron_ids then storage.neural_spider_control.connected_spidertron_ids = {} end
                if not storage.neural_spider_control.original_characters then storage.neural_spider_control.original_characters = {} end
                if not storage.neural_spider_control.original_character_ids then storage.neural_spider_control.original_character_ids = {} end
                if not storage.neural_spider_control.original_surfaces then storage.neural_spider_control.original_surfaces = {} end
                if not storage.neural_spider_control.original_health then storage.neural_spider_control.original_health = {} end
                
                -- Refresh/verify storage entries to ensure connection is properly tracked
                storage.neural_spider_control.dummy_engineers[player.index] = {
                    entity = dummy_engineer,
                    unit_number = dummy_engineer.unit_number
                }
                storage.neural_spider_control.connected_spidertrons[player.index] = vehicle
                storage.neural_spider_control.vehicle_types[player.index] = vehicle.type
                storage.neural_spider_control.dummy_engineer_ids[player.index] = dummy_engineer.unit_number
                storage.neural_spider_control.connected_spidertron_ids[player.index] = vehicle.unit_number
                
                -- Verify original character is still stored (needed for disconnect)
                if not storage.neural_spider_control.original_characters[player.index] or 
                   not storage.neural_spider_control.original_characters[player.index].valid then
                    -- game.print("[MapEditor] WARNING: Original character not found or invalid!")
                    -- game.print("[MapEditor] This may cause issues when disconnecting")
                else
                    -- game.print("[MapEditor] Original character still valid: " .. storage.neural_spider_control.original_characters[player.index].unit_number)
                end
                
                -- game.print("[MapEditor] Storage tables refreshed for connection tracking")
                
                -- Disconnect player from current character (if any)
                -- game.print("[MapEditor] Disconnecting player from current character")
                player.character = nil
                
                -- Teleport player to vehicle's surface if needed
                if player.surface ~= vehicle.surface then
                    -- game.print("[MapEditor] Teleporting player to vehicle surface")
                    player.teleport(vehicle.position, vehicle.surface)
                end
                
                -- Reconnect player to dummy engineer
                -- game.print("[MapEditor] Reconnecting player to dummy engineer")
                player.character = dummy_engineer
                
                -- Ensure dummy engineer is the driver of the vehicle
                local current_driver = vehicle.get_driver()
                -- game.print("[MapEditor] Current driver: " .. tostring(current_driver ~= nil))
                if current_driver ~= dummy_engineer then
                    -- game.print("[MapEditor] Setting dummy engineer as driver")
                    vehicle.set_driver(dummy_engineer)
                end
                
                -- Ensure player is in the driver's seat
                if player.character and player.character.valid then
                    if player.character.vehicle ~= vehicle or vehicle.get_driver() ~= player.character then
                        -- game.print("[MapEditor] Ensuring player character is driver")
                        vehicle.set_driver(player.character)
                    end
                end
                
                -- Verify the connection is properly recognized
                local is_dummy = is_dummy_engineer(player.character)
                -- game.print("[MapEditor] is_dummy_engineer check: " .. tostring(is_dummy))
                
                -- Clear the reconnecting flag now that we're done
                if storage.reconnecting_players then
                    storage.reconnecting_players[player.index] = nil
                end
                
                player.create_local_flying_text{
                    text = "Neural connection restored.",
                    position = vehicle.position,
                    color = {r=0, g=1, b=0}
                }
                
                -- game.print("[MapEditor] Successfully restored neural connection!")
                log_debug("Successfully restored neural connection for player " .. player.name)
            else
                -- game.print("[MapEditor] FAILED to restore - dummy_engineer valid: " .. tostring(dummy_engineer and dummy_engineer.valid) .. 
                --          ", vehicle valid: " .. tostring(vehicle and vehicle.valid))
                log_debug("Could not restore connection: dummy_engineer valid=" .. tostring(dummy_engineer and dummy_engineer.valid) .. 
                         ", vehicle valid=" .. tostring(vehicle and vehicle.valid))
            end
            
            -- Clean up saved state
            storage.map_editor_connections[player.index] = nil
            -- game.print("[MapEditor] Cleaned up saved state")
        else
            -- game.print("[MapEditor] No saved connection state found for player")
        end
    else
        -- game.print("[MapEditor] Player still in editor mode, skipping restore")
    end
end)

-- Add admin command to open neural control centre
--commands.add_command("open_neural_control", "Open the Neural Control Centre", control_centre.open_gui)

-- Add debug command to show neural connection info
commands.add_command("neural_debug", "Show neural connection debug info", function(command)
    local player = game.get_player(command.player_index)
    
    -- Log intro
    -- log_debug("=== Neural Control Debug Info ===")
    -- log_debug("Requested by player: " .. player.name)
    
    -- Check if storage exists
    if not storage then
        log_debug("ERROR: storage table does not exist!")
        player.print("ERROR: storage table not available")
        return
    end
    
    -- Check control data
    log_debug("Vehicle Control Data:")
    if not storage.neural_spider_control then
        log_debug("- neural_spider_control table doesn't exist")
    else
        -- Log dummy engineers
        log_debug("- Dummy Engineers:")
        if storage.neural_spider_control.dummy_engineers then
            for player_index, dummy_data in pairs(storage.neural_spider_control.dummy_engineers) do
                local player_name = game.get_player(player_index) and game.get_player(player_index).name or "unknown"
                if type(dummy_data) == "table" and dummy_data.entity then
                    log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): " .. 
                              (dummy_data.entity and dummy_data.entity.valid and 
                               "valid entity #" .. dummy_data.unit_number or "invalid entity"))
                else
                    log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): " .. 
                              (dummy_data and dummy_data.valid and 
                               "valid entity #" .. dummy_data.unit_number or "invalid entity"))
                end
            end
        else
            log_debug("  - dummy_engineers table doesn't exist")
        end
        
        -- Log original characters
        log_debug("- Original Characters:")
        if storage.neural_spider_control.original_characters then
            for player_index, character in pairs(storage.neural_spider_control.original_characters) do
                local player_name = game.get_player(player_index) and game.get_player(player_index).name or "unknown"
                log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): " .. 
                          (character and character.valid and 
                           "valid entity #" .. character.unit_number or "invalid entity"))
            end
        else
            log_debug("  - original_characters table doesn't exist")
        end
        
        -- Log connected vehicles
        log_debug("- Connected Vehicles:")
        if storage.neural_spider_control.connected_spidertrons then
            for player_index, vehicle in pairs(storage.neural_spider_control.connected_spidertrons) do
                local player_name = game.get_player(player_index) and game.get_player(player_index).name or "unknown"
                local vehicle_type = storage.neural_spider_control.vehicle_types and 
                                   storage.neural_spider_control.vehicle_types[player_index] or "unknown"
                log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): " .. 
                          (vehicle and vehicle.valid and 
                           "valid " .. vehicle_type .. " #" .. vehicle.unit_number or "invalid entity"))
            end
        else
            log_debug("  - connected_vehicles table doesn't exist")
        end
        
        -- Log unit number IDs
        log_debug("- Stored Unit Numbers:")
        if storage.neural_spider_control.connected_spidertron_ids then
            for player_index, unit_number in pairs(storage.neural_spider_control.connected_spidertron_ids) do
                local player_name = game.get_player(player_index) and game.get_player(player_index).name or "unknown"
                log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): vehicle #" .. unit_number)
            end
        else
            log_debug("  - connected_vehicle_ids table doesn't exist")
        end
        
        if storage.neural_spider_control.original_character_ids then
            for player_index, unit_number in pairs(storage.neural_spider_control.original_character_ids) do
                local player_name = game.get_player(player_index) and game.get_player(player_index).name or "unknown"
                log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): original character #" .. unit_number)
            end
        else
            log_debug("  - original_character_ids table doesn't exist")
        end
        
        if storage.neural_spider_control.dummy_engineer_ids then
            for player_index, unit_number in pairs(storage.neural_spider_control.dummy_engineer_ids) do
                local player_name = game.get_player(player_index) and game.get_player(player_index).name or "unknown"
                log_debug("  - Player " .. player_name .. " (#" .. player_index .. "): dummy engineer #" .. unit_number)
            end
        else
            log_debug("  - dummy_engineer_ids table doesn't exist")
        end
    end
    
    -- Print summary to player
    --player.print("Neural connection debug info written to log")
    -- log_debug("=== End Neural Control Debug Info ===")
end)

-- Add function to add buttons to player GUI toolbar (when holding spidertron remote)
local function add_to_player_gui_toolbar(player)
    if remote.interfaces["vehicle-control-center"] and remote.interfaces["vehicle-control-center"]["refresh_context_buttons"] then
        remote.call("vehicle-control-center", "refresh_context_buttons", player.index)
    end
end

-- Toolbar creation is handled by Vehicle Control Center.

-- GUI event handlers
script.on_event(defines.events.on_gui_click, combined_gui_click_handler)

-- Handle GUI closed events with a combined handler
script.on_event(defines.events.on_gui_closed, function(event)
    local player = game.get_player(event.player_index)
    if player and player.valid then
        add_to_player_gui_toolbar(player)
    end
end)
