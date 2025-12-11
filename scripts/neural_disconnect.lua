local mod_data = require("scripts.mod_data")

local neural_disconnect = {}

-- Configuration: Periodic cleanup interval (in ticks, 60 ticks = 1 second)
local CLEANUP_INTERVAL_TICKS = 54000  -- 15 minutes

local function log_debug(message)
    -- Logging disabled
end

-- ============================================================================
-- ORPHANED ENGINEER MANAGEMENT
-- ============================================================================
-- Future Vehicle Control Centre features:
-- - Show list of all active/orphaned connections
-- - Display vehicle name/type, time since disconnect, reason kept alive
-- - Quick reconnect button for each connection
-- - Manual cleanup button
-- ============================================================================

-- Check if dummy engineer should be kept alive
function neural_disconnect.should_keep_alive(dummy_engineer)
    if not dummy_engineer or not dummy_engineer.valid then
        return false
    end
    
    -- Keep alive if crafting
    if dummy_engineer.crafting_queue_size > 0 then
        return true
    end
    
    -- Keep alive if has items in main inventory
    local main_inventory = dummy_engineer.get_main_inventory()
    if main_inventory and not main_inventory.is_empty() then
        return true
    end
    
    -- Keep alive if has logistic trash items
    local trash_inventory = dummy_engineer.get_inventory(defines.inventory.character_trash)
    if trash_inventory and not trash_inventory.is_empty() then
        return true
    end
    
    return false
end

-- Get disconnect reason for why engineer is kept alive
function neural_disconnect.get_disconnect_reason(dummy_engineer)
    if not dummy_engineer or not dummy_engineer.valid then
        return "invalid"
    end
    
    local reasons = {}
    
    if dummy_engineer.crafting_queue_size > 0 then
        table.insert(reasons, "crafting")
    end
    
    local main_inventory = dummy_engineer.get_main_inventory()
    if main_inventory and not main_inventory.is_empty() then
        table.insert(reasons, "has_items")
    end
    
    local trash_inventory = dummy_engineer.get_inventory(defines.inventory.character_trash)
    if trash_inventory and not trash_inventory.is_empty() then
        table.insert(reasons, "has_logistic_items")
    end
    
    if #reasons == 0 then
        return "none"
    elseif #reasons == 1 then
        return reasons[1]
    else
        return "multiple"
    end
end

-- Mark dummy engineer as orphaned (disconnected but kept alive)
function neural_disconnect.mark_as_orphaned(dummy_engineer, player_index, vehicle, vehicle_type)
    if not dummy_engineer or not dummy_engineer.valid then
        return false
    end
    
    -- Initialize orphaned engineers storage
    storage.orphaned_dummy_engineers = storage.orphaned_dummy_engineers or {}
    
    -- Get disconnect reason
    local disconnect_reason = neural_disconnect.get_disconnect_reason(dummy_engineer)
    
    -- Store orphaned engineer with metadata
    storage.orphaned_dummy_engineers[dummy_engineer.unit_number] = {
        entity = dummy_engineer,
        unit_number = dummy_engineer.unit_number,
        player_index = player_index,
        vehicle_id = vehicle and vehicle.valid and vehicle.unit_number or nil,
        vehicle_type = vehicle_type or "unknown",
        vehicle_surface = vehicle and vehicle.valid and vehicle.surface.index or nil,
        disconnected_at = game.tick,
        disconnect_reason = disconnect_reason
    }
    
    log_debug("Marked engineer #" .. dummy_engineer.unit_number .. " as orphaned (reason: " .. disconnect_reason .. ")")
    
    -- Register periodic cleanup handler if not already registered
    if not storage.orphaned_cleanup_registered then
        script.on_nth_tick(CLEANUP_INTERVAL_TICKS, function(event)
            neural_disconnect.cleanup_orphaned_engineers()
        end)
        storage.orphaned_cleanup_registered = true
        log_debug("Registered orphaned engineer cleanup handler")
    end
    
    return true
end

-- Find orphaned dummy engineer for a vehicle
function neural_disconnect.find_orphaned_engineer_for_vehicle(vehicle)
    if not vehicle or not vehicle.valid or not storage.orphaned_dummy_engineers then
        return nil
    end
    
    local vehicle_id = vehicle.unit_number
    
    -- Check if any orphaned engineer is in this vehicle
    for unit_number, data in pairs(storage.orphaned_dummy_engineers) do
        local engineer = data.entity
        if engineer and engineer.valid then
            -- Check if engineer is in this vehicle
            if engineer.vehicle == vehicle then
                return engineer, data
            end
            -- Also check by vehicle_id if stored
            if data.vehicle_id == vehicle_id then
                return engineer, data
            end
        end
    end
    
    return nil
end

-- Check if vehicle has an active remote connection (any player)
function neural_disconnect.vehicle_has_active_connection(vehicle)
    if not vehicle or not vehicle.valid then
        return false
    end
    
    if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
        for player_index, connected_vehicle in pairs(storage.neural_spider_control.connected_spidertrons) do
            if connected_vehicle and connected_vehicle.valid and connected_vehicle == vehicle then
                return true, player_index
            end
        end
    end
    
    return false
end

-- Force destroy an orphaned engineer (when connecting to different vehicle, interaction, etc.)
function neural_disconnect.force_destroy_orphaned_engineer(dummy_engineer, player_index, show_message)
    if not dummy_engineer or not dummy_engineer.valid then
        return
    end
    
    log_debug("Force destroying orphaned engineer #" .. dummy_engineer.unit_number)
    
    -- Cancel crafting
    neural_disconnect.cancel_crafting_queue(dummy_engineer)
    
    -- Get vehicle for transfer
    local vehicle = nil
    local vehicle_type = nil
    local orphaned_data = nil
    
    if storage.orphaned_dummy_engineers then
        orphaned_data = storage.orphaned_dummy_engineers[dummy_engineer.unit_number]
        if orphaned_data then
            vehicle_type = orphaned_data.vehicle_type
            if orphaned_data.vehicle_id then
                -- Try to find vehicle by ID
                local surface = orphaned_data.vehicle_surface and game.surfaces[orphaned_data.vehicle_surface] or dummy_engineer.surface
                if surface and surface.valid then
                    local entities = surface.find_entities_filtered{type = vehicle_type}
                    for _, ent in pairs(entities) do
                        if ent.unit_number == orphaned_data.vehicle_id then
                            vehicle = ent
                            break
                        end
                    end
                end
            end
        end
    end
    
    -- Transfer or spill inventory
    if vehicle and vehicle.valid then
        neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, vehicle, vehicle_type, player_index)
    else
        neural_disconnect.spill_inventory(dummy_engineer, dummy_engineer.get_main_inventory())
        local trash_inventory = dummy_engineer.get_inventory(defines.inventory.character_trash)
        if trash_inventory and not trash_inventory.is_empty() then
            neural_disconnect.spill_inventory(dummy_engineer, trash_inventory)
        end
    end
    
    -- Show message if requested
    if show_message and dummy_engineer.valid then
        local surface = dummy_engineer.surface
        for _, player in pairs(game.players) do
            if player.surface == surface then
                player.create_local_flying_text{
                    text = "Remote connected engineer destroyed, items have spilled",
                    position = dummy_engineer.position,
                    color = {r=1, g=0.5, b=0}
                }
            end
        end
    end
    
    -- Remove from orphaned list
    if storage.orphaned_dummy_engineers then
        storage.orphaned_dummy_engineers[dummy_engineer.unit_number] = nil
    end
    
    -- Destroy the engineer
    if dummy_engineer.valid then
        dummy_engineer.destroy()
    end
end

-- Periodic cleanup of empty orphaned engineers
function neural_disconnect.cleanup_orphaned_engineers()
    if not storage.orphaned_dummy_engineers then
        return
    end
    
    log_debug("Running periodic cleanup of orphaned engineers")
    
    local to_remove = {}
    
    for unit_number, data in pairs(storage.orphaned_dummy_engineers) do
        local engineer = data.entity
        
        -- Check if engineer is still valid
        if not engineer or not engineer.valid then
            table.insert(to_remove, unit_number)
            log_debug("Orphaned engineer #" .. unit_number .. " is no longer valid")
        elseif not neural_disconnect.should_keep_alive(engineer) then
            -- No longer has items or crafting, destroy it
            log_debug("Orphaned engineer #" .. unit_number .. " is empty, destroying")
            neural_disconnect.force_destroy_orphaned_engineer(engineer, data.player_index, false)
            table.insert(to_remove, unit_number)
        end
    end
    
    -- Remove processed entries
    for _, unit_number in ipairs(to_remove) do
        storage.orphaned_dummy_engineers[unit_number] = nil
    end
    
    -- Unregister handler if no more orphaned engineers
    if next(storage.orphaned_dummy_engineers) == nil then
        script.on_nth_tick(CLEANUP_INTERVAL_TICKS, nil)
        storage.orphaned_cleanup_registered = false
        storage.orphaned_dummy_engineers = nil
        log_debug("Unregistered orphaned cleanup handler (no more orphaned engineers)")
    end
end

-- Helper functions

-- Cancel any ongoing crafting operations for a dummy engineer
function neural_disconnect.cancel_crafting_queue(dummy_engineer)
    if dummy_engineer.crafting_queue_size > 0 then
        log_debug("Canceling crafting queue with " .. dummy_engineer.crafting_queue_size .. " items")
        
        -- First, make sure we have the main inventory
        local main_inventory = dummy_engineer.get_main_inventory()
        if not main_inventory then
            log_debug("Warning: Could not get main inventory when canceling crafting")
            return false
        end
        
        -- Cancel each item one by one, from last to first
        for i = dummy_engineer.crafting_queue_size, 1, -1 do
            pcall(function()
                -- Always cancel index 1 as items shift up in the queue
                dummy_engineer.cancel_crafting{index = 1, count = dummy_engineer.crafting_queue[1].count}
                log_debug("Canceled crafting item at index 1")
            end)
        end
        
        return true
    end
    return false
end

-- Helper function to safely get optional stack properties
local function safe_get_property(stack, property_name, getter_func)
    local ok, value = pcall(getter_func)
    if ok then
        return value
    end
    return nil
end

-- Spill the contents of an inventory onto the ground
-- Uses built-in surface.spill_inventory() which automatically preserves quality
function neural_disconnect.spill_inventory(entity, inventory)
    if not inventory or inventory.is_empty() then return end
    
    log_debug("Spilling inventory with " .. inventory.get_item_count() .. " total items")
    
    -- Use built-in spill_inventory which automatically preserves quality
    local success, result = pcall(function()
        return entity.surface.spill_inventory{
            position = entity.position,
            inventory = inventory,
            enable_looted = false,
            allow_belts = true,
            drop_full_stack = false
        }
    end)
    
    if not success then
        game.print("[Spill] ERROR: Failed to spill inventory: " .. tostring(result))
        log_debug("Failed to spill inventory: " .. tostring(result))
    end
    
    log_debug("Spilled inventory using surface.spill_inventory()")
end

-- Transfer inventory from dummy engineer to vehicle, then player, then spill
-- player_index is optional - if provided, will try to transfer to player inventory before spilling
function neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, vehicle, vehicle_type, player_index)
    log_debug("Starting inventory transfer")
    
    local vehicle_name = "unknown"
    if vehicle and vehicle.valid then
        vehicle_name = vehicle.name .. " #" .. vehicle.unit_number
        log_debug("Vehicle is valid, name: " .. vehicle_name)
    else
        log_debug("Vehicle is nil or invalid!")
    end
    
    -- Get player and player inventory if player_index is provided
    local player = player_index and game.get_player(player_index)
    local player_inventory = nil
    if player and player.valid and player.character and player.character.valid then
        player_inventory = player.character.get_main_inventory()
    end
    
    local dummy_inventory = dummy_engineer.get_main_inventory()
    local items_spilled = false
    
    -- Check if there's anything to transfer (main inventory or logistic trash)
    local has_main_items = not dummy_inventory.is_empty()
    local has_logistic_items = false
    
    -- Check for logistic trash items
    local trash_inventory = dummy_engineer.get_inventory(defines.inventory.character_trash)
        if trash_inventory and not trash_inventory.is_empty() then
            has_logistic_items = true
            log_debug("Found logistic trash items: " .. trash_inventory.get_item_count() .. " items")
    end
    
    -- Exit early if there's nothing to transfer
    if not has_main_items and not has_logistic_items then
        log_debug("Dummy inventory is empty, nothing to transfer")
        return false
    end
    
    -- Determine if we have a valid destination
    if not (vehicle and vehicle.valid) then
        log_debug("No valid vehicle, spilling all items")
        if has_main_items then
            neural_disconnect.spill_inventory(dummy_engineer, dummy_inventory)
        end
        if has_logistic_items and trash_inventory then
            neural_disconnect.spill_inventory(dummy_engineer, trash_inventory)
        end
        return true
    end
    
    -- Get the vehicle inventory based on vehicle type
    local vehicle_inventory = nil
    
    if vehicle.type == "spider-vehicle" then
        vehicle_inventory = vehicle.get_inventory(defines.inventory.spider_trunk)
    elseif vehicle.type == "car" then
        vehicle_inventory = vehicle.get_inventory(defines.inventory.car_trunk)
    end
    
    if not vehicle_inventory then
        log_debug("Vehicle has no inventory, spilling all items")
        if has_main_items then
            neural_disconnect.spill_inventory(dummy_engineer, dummy_inventory)
        end
        if has_logistic_items and trash_inventory then
            neural_disconnect.spill_inventory(dummy_engineer, trash_inventory)
        end
        return true
    end
    
    log_debug("Processing item transfer for " .. dummy_inventory.get_item_count() .. " main items" .. 
              (has_logistic_items and (" and " .. trash_inventory.get_item_count() .. " logistic items") or ""))
    
    local overflow_stacks = {}  -- Store actual stack objects for overflow (preserves quality)
    
    -- Try to insert each stack directly from inventory (this preserves quality)
    -- Process main inventory
    if has_main_items then
        for i = 1, #dummy_inventory do
            local stack = dummy_inventory[i]
            if stack and stack.valid_for_read then
                local original_count = stack.count
                
                -- Insert the stack directly (preserves quality)
                local inserted = vehicle_inventory.insert(stack)
                
                -- If not all were inserted, the remaining items are still in the stack
                if inserted < original_count then
                    table.insert(overflow_stacks, stack)
                end
            end
        end
    end
    
    -- Process logistic trash inventory
    if has_logistic_items and trash_inventory then
        for i = 1, #trash_inventory do
            local stack = trash_inventory[i]
            if stack and stack.valid_for_read then
                local original_count = stack.count
                
                -- Insert the stack directly (preserves quality)
                local inserted = vehicle_inventory.insert(stack)
                
                -- If not all were inserted, the remaining items are still in the stack
                if inserted < original_count then
                    table.insert(overflow_stacks, stack)
                end
            end
        end
    end
    
    -- If any items couldn't fit in vehicle, try player inventory first, then spill
    if #overflow_stacks > 0 then
        log_debug(#overflow_stacks .. " item stacks couldn't fit in vehicle")
        
        -- Try to transfer overflow to player inventory if available
        local final_overflow_stacks = {}
        if player_inventory then
            for _, stack in ipairs(overflow_stacks) do
                if stack and stack.valid_for_read then
                    local original_count = stack.count
                    
                    -- Try to insert into player inventory (preserves quality)
                    local inserted = player_inventory.insert(stack)
                    
                    -- If not all were inserted, add to final overflow for spilling
                    if inserted < original_count then
                        table.insert(final_overflow_stacks, stack)
                    end
                end
            end
        else
            -- No player inventory available, all overflow will be spilled
            final_overflow_stacks = overflow_stacks
        end
        
        -- Spill any remaining overflow using spill_item_stack (preserves quality automatically)
        if #final_overflow_stacks > 0 then
            log_debug(#final_overflow_stacks .. " item stacks couldn't fit, spilling")
            items_spilled = true
            
            -- Spill each overflow stack using built-in spill_item_stack (preserves quality)
            for _, stack in ipairs(final_overflow_stacks) do
                if stack and stack.valid_for_read then
                    local success, result = pcall(function()
                        return dummy_engineer.surface.spill_item_stack{
                            position = dummy_engineer.position,
                            stack = stack,  -- Pass the actual stack object (preserves quality)
                            enable_looted = false,
                            allow_belts = true,
                            drop_full_stack = false
                        }
                    end)
                    
                    if not success then
                        game.print("[Transfer] ERROR: Failed to spill overflow " .. stack.count .. "x " .. stack.name .. ": " .. tostring(result))
                    end
                end
            end
        end
    end
    
    -- Now clear the inventories (after we've spilled overflow)
    if has_main_items then
        dummy_inventory.clear()
    end
    if has_logistic_items and trash_inventory then
        trash_inventory.clear()
    end
    
    return items_spilled
end

-- Clean up connection data for a player
function neural_disconnect.clean_up_connection_data(player_index)
    -- Clean up from storage tables
    local function safely_clear_data(control_data)
        if control_data then
            for _, table_name in ipairs({
                "dummy_engineers", 
                "original_characters", 
                "connected_spidertrons", 
                "original_surfaces", 
                "neural_connections",
                "original_health",
                "connected_spidertron_ids",
                "original_character_ids",
                "dummy_engineer_ids",
                "vehicle_types"
            }) do
                if control_data[table_name] then
                    control_data[table_name][player_index] = nil
                end
            end
        end
    end

    -- Clean control structures
    safely_clear_data(storage.neural_spider_control)
    
    -- Clean up health check player registration
    if storage.health_check_players then
        storage.health_check_players[player_index] = nil
        
        -- If no more players being monitored, remove the on_nth_tick handler
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
    
    -- Clean up legacy data structures
    if storage.player_connections then
        storage.player_connections[player_index] = nil
    end
    
    log_debug("Cleaned up all connection data for player " .. player_index)
end

-- Create flying text for messages
local function create_flying_text(surface_or_player, position, message, color)
    -- Check if we're working with a surface or a player
    if surface_or_player.object_name == "LuaPlayer" then
        -- If it's a player, use create_local_flying_text
        surface_or_player.create_local_flying_text{
            text = message,
            position = position,
            color = color
        }
    else
        -- If it's a surface, try to create a global flying text
        -- Attempt to find a player on this surface to create the text
        local players_on_surface = {}
        for _, player in pairs(game.players) do
            if player.surface == surface_or_player then
                table.insert(players_on_surface, player)
            end
        end
        
        if #players_on_surface > 0 then
            -- Create flying text for each player on this surface
            for _, player in ipairs(players_on_surface) do
                player.create_local_flying_text{
                    text = message,
                    position = position,
                    color = color
                }
            end
        else
            -- If no players on this surface, log the message instead
            log_debug("Flying text (no players to show): " .. message)
        end
    end
end

-- Emergency disconnect function
function neural_disconnect.emergency_disconnect(player, vehicle_destroyed)
    log_debug("Emergency disconnect initiated for player " .. player.name)
    
    -- Find the dummy engineer
    local dummy_engineer
    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
        local dummy_data = storage.neural_spider_control.dummy_engineers[player.index]
        if dummy_data then
            if type(dummy_data) == "table" and dummy_data.entity and dummy_data.entity.valid then
                dummy_engineer = dummy_data.entity
            elseif dummy_data.valid then
                dummy_engineer = dummy_data
            end
        end
    end
    
    if not dummy_engineer or not dummy_engineer.valid then
        log_debug("Error: Unable to find dummy engineer for player " .. player.name)
        player.print("Error: Unable to find your vehicle control state.")
        return
    end

    -- Don't cancel crafting or spill immediately - mark as orphaned if should be kept alive
    local vehicle = nil
    local vehicle_type = "Vehicle"
    
    if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
        vehicle = storage.neural_spider_control.connected_spidertrons[player.index]
    end
    
    if storage.neural_spider_control and storage.neural_spider_control.vehicle_types then
        local raw_type = storage.neural_spider_control.vehicle_types[player.index]
        if raw_type == "spider-vehicle" then
            vehicle_type = "Spidertron"
        elseif raw_type == "car" then
            vehicle_type = "Car"
        end
    end
    
    -- Mark as orphaned if should be kept alive
    if neural_disconnect.should_keep_alive(dummy_engineer) then
        neural_disconnect.mark_as_orphaned(dummy_engineer, player.index, vehicle, vehicle_type)
    else
        -- Otherwise destroy immediately
    neural_disconnect.spill_inventory(dummy_engineer, dummy_engineer.get_main_inventory())
        local trash_inventory = dummy_engineer.get_inventory(defines.inventory.character_trash)
        if trash_inventory and not trash_inventory.is_empty() then
            neural_disconnect.spill_inventory(dummy_engineer, trash_inventory)
        end
    end

    -- Find original character and surface
    local original_character
    local original_surface
    local vehicle_type = "Vehicle"
    
    if storage.neural_spider_control and storage.neural_spider_control.original_characters then
        original_character = storage.neural_spider_control.original_characters[player.index]
        if storage.neural_spider_control.original_surfaces then
            original_surface = game.surfaces[storage.neural_spider_control.original_surfaces[player.index]]
        end
        
        -- Get a friendly name for the vehicle type
        if storage.neural_spider_control.vehicle_types and storage.neural_spider_control.vehicle_types[player.index] then
            local raw_type = storage.neural_spider_control.vehicle_types[player.index]
            if raw_type == "spider-vehicle" then
                vehicle_type = "Spidertron"
            elseif raw_type == "car" then
                vehicle_type = "Car"
            end
        end
    end
    
    if original_character and original_character.valid then
        -- First, disconnect the player from the dummy engineer
        player.character = nil
        
        -- If keeping engineer alive, ensure it stays in the vehicle
        if neural_disconnect.should_keep_alive(dummy_engineer) and vehicle and vehicle.valid then
            -- Make sure dummy engineer is still in the vehicle, put it back if needed
            if dummy_engineer.valid then
                if dummy_engineer.vehicle ~= vehicle then
                    log_debug("Dummy engineer exited vehicle, putting it back in")
                    vehicle.set_driver(dummy_engineer)
                end
            end
        end
        
        -- Ensure player is on the original character's surface
        if original_surface and original_surface.valid and player.surface ~= original_surface then
            log_debug("Surface mismatch for player " .. player.name .. ": player on " .. player.surface.name .. ", original character on " .. original_surface.name)
            local new_position = original_surface.find_non_colliding_position(original_character.name, original_character.position, 10, 0.5)
            if new_position then
                player.teleport(new_position, original_surface)
            else
                log_debug("Error: Could not find a valid position to teleport player on surface " .. original_surface.name)
                player.print("Error: Unable to restore character due to surface mismatch.", {r=1, g=0, b=0})
                if dummy_engineer and dummy_engineer.valid then
                    dummy_engineer.destroy()
                end
                neural_disconnect.clean_up_connection_data(player.index)
                return
            end
        end
        
        -- Assign the character
        player.character = original_character
        
        local message = vehicle_destroyed and "Remote connection lost! " .. vehicle_type .. " destroyed." or "Emergency disconnect initiated."
        create_flying_text(player, player.position, message, {r=1, g=0, b=0})
    else
        log_debug("Error: Original character not found for player " .. player.name)
        player.print("Error: Original character not found. Please report this issue.", {r=1, g=0, b=0})
    end

    -- Don't destroy immediately - already handled above (orphaned or destroyed)
    
    -- Clean up data
    neural_disconnect.clean_up_connection_data(player.index)

    log_debug("Emergency disconnect completed for player " .. player.name)
end

-- Return to original engineer from any vehicle
function neural_disconnect.return_to_engineer(player, vehicle_type, specific_vehicle)
    log_debug("Starting return to engineer process for player " .. player.name)
    
    -- Find the dummy engineer
    local dummy_engineer
    
    if storage.neural_spider_control and storage.neural_spider_control.dummy_engineers then
        local dummy_data = storage.neural_spider_control.dummy_engineers[player.index]
        if dummy_data then
            if type(dummy_data) == "table" and dummy_data.entity and dummy_data.entity.valid then
                dummy_engineer = dummy_data.entity
            elseif dummy_data.valid then
                dummy_engineer = dummy_data
            end
        end
    end
    
    if not dummy_engineer or not dummy_engineer.valid then
        log_debug("Error: Dummy engineer not found or invalid for player " .. player.name)
        return
    end

    -- Find the original surface
    local original_surface
    if storage.neural_spider_control and storage.neural_spider_control.original_surfaces then
        original_surface = game.surfaces[storage.neural_spider_control.original_surfaces[player.index]]
    end
    
    if not original_surface then
        log_debug("Error: Original surface not found for player " .. player.name)
        return
    end

    -- Don't cancel crafting - let it continue if engineer is kept alive
    -- Find the vehicle for inventory transfer (will be done when engineer is destroyed)
    local vehicle = specific_vehicle

    if vehicle and vehicle.valid then
        log_debug("Using specified vehicle #" .. vehicle.unit_number .. " for inventory transfer")
    else
        log_debug("No valid specific vehicle provided, using lookup")
        if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
            vehicle = storage.neural_spider_control.connected_spidertrons[player.index]
        end
    end

    -- Get actual vehicle type from storage or fallback to parameter
    local actual_vehicle_type = vehicle_type
    if storage.neural_spider_control and 
       storage.neural_spider_control.vehicle_types and 
       storage.neural_spider_control.vehicle_types[player.index] then
        actual_vehicle_type = storage.neural_spider_control.vehicle_types[player.index]
    end

    -- Mark as orphaned if should be kept alive, otherwise will be destroyed later
    if neural_disconnect.should_keep_alive(dummy_engineer) then
        neural_disconnect.mark_as_orphaned(dummy_engineer, player.index, vehicle, actual_vehicle_type)
    end

    -- Find and use the original character
    local original_character
    if storage.neural_spider_control and storage.neural_spider_control.original_characters then
        original_character = storage.neural_spider_control.original_characters[player.index]
    end
    
    if original_character and original_character.valid then
        -- First, disconnect the player from the dummy engineer
        player.character = nil
        
        -- If keeping engineer alive, ensure it stays in the vehicle
        if neural_disconnect.should_keep_alive(dummy_engineer) and vehicle and vehicle.valid then
            -- Make sure dummy engineer is still in the vehicle, put it back if needed
            if dummy_engineer.valid then
                if dummy_engineer.vehicle ~= vehicle then
                    log_debug("Dummy engineer exited vehicle, putting it back in")
                    vehicle.set_driver(dummy_engineer)
                end
            end
        end
        
        -- Ensure we're operating on the right surface
        local char_surface = original_character.surface
        
        -- Then teleport the player to the original surface, at the original character's position
        player.teleport(original_character.position, char_surface)
        
        -- Verify player is now on the same surface as the original character
        if player.surface.index == char_surface.index then
            -- Now it's safe to connect to original character
            player.character = original_character
            
            local message = "Remote connection disengaged."
            if neural_disconnect.should_keep_alive(dummy_engineer) then
                message = message .. " Engineer continues working."
            end
            local color = {r=0, g=1, b=0}
            player.create_local_flying_text{
                text = message,
                position = player.position,
                color = color
            }
        else
            -- If teleport didn't work, log error
            log_debug("ERROR: Failed to teleport player to correct surface for character reconnection")
        end
    else
        log_debug("Original character not found for player " .. player.name)
    end

    -- Preserve connection info for reconnection before cleaning up
    if vehicle and vehicle.valid then
        -- Get vehicle type name for tracking
        local vehicle_type_name = "spidertron"
        if actual_vehicle_type == "spider-vehicle" then
            vehicle_type_name = "spidertron"
        elseif actual_vehicle_type == "car" then
            vehicle_type_name = "car"
        end
        
        -- Track connection for reconnection (duplicated from neural_connect to avoid circular dependency)
        -- This tracks the vehicle we just disconnected from, so reconnect will work
        if not storage.last_connections then
            storage.last_connections = {}
        end
        storage.last_connections[player.index] = {
            type = vehicle_type_name,
            vehicle_id = vehicle.unit_number,
            time = game.tick,
            surface_index = vehicle.surface.index
        }
        log_debug("Tracked disconnected vehicle for reconnection: " .. vehicle_type_name .. " #" .. vehicle.unit_number)
        
        -- Update shortcut visibility for reconnect button (will be handled by event handlers)
    end
    
    -- Don't destroy immediately - already marked as orphaned if should be kept alive
    -- If not kept alive, destroy it now
    if dummy_engineer and dummy_engineer.valid then
        if not neural_disconnect.should_keep_alive(dummy_engineer) then
            -- Transfer items before destroying
            if vehicle and vehicle.valid then
                neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, vehicle, actual_vehicle_type, player.index)
            else
                neural_disconnect.spill_inventory(dummy_engineer, dummy_engineer.get_main_inventory())
                local trash_inventory = dummy_engineer.get_inventory(defines.inventory.character_trash)
                if trash_inventory and not trash_inventory.is_empty() then
                    neural_disconnect.spill_inventory(dummy_engineer, trash_inventory)
                end
            end
        dummy_engineer.destroy()
        end
    end
    
    -- Clean up data
    neural_disconnect.clean_up_connection_data(player.index)

    log_debug("Return to engineer completed for player " .. player.name)
end

-- Handle character death
function neural_disconnect.handle_character_death(player, vehicle_type)
    local player_index = player.index
    log_debug("Handling character death for player " .. player.name)

    -- Get control data
    local control_data = storage.neural_spider_control
    
    -- Find the dummy engineer
    local dummy_engineer
    if control_data and control_data.dummy_engineers then
        local dummy_data = control_data.dummy_engineers[player_index]
        if type(dummy_data) == "table" and dummy_data.entity then
            dummy_engineer = dummy_data.entity
        else
            dummy_engineer = dummy_data
        end
    end
    
    -- Find the connected vehicle
    local connected_vehicle
    if control_data and control_data.connected_spidertrons then
        connected_vehicle = control_data.connected_spidertrons[player_index]
    end

    if dummy_engineer and dummy_engineer.valid then
        log_debug("Valid dummy engineer found for player " .. player.name)

        -- Mark as orphaned if should be kept alive, otherwise destroy
        if neural_disconnect.should_keep_alive(dummy_engineer) then
            neural_disconnect.mark_as_orphaned(dummy_engineer, player_index, connected_vehicle, 
                                             control_data.vehicle_types[player_index])
            log_debug("Dummy engineer marked as orphaned for player " .. player.name)
        else
        -- Transfer items from dummy to vehicle or spill them
        local items_spilled = neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, connected_vehicle, 
                                                                           control_data.vehicle_types[player_index], player_index)
        log_debug("Inventory transfer complete. Items spilled: " .. tostring(items_spilled))

        -- Get the position and surface of the dummy engineer before killing it
        local position = dummy_engineer.position
        local surface = dummy_engineer.surface

        -- Kill the dummy engineer
        dummy_engineer.die()

        -- Clean up corpses
        if surface and surface.valid then
            log_debug("Surface valid for player " .. player.name)
        
            -- Find and remove character corpses in the area
            local character_corpses = surface.find_entities_filtered({
                position = position,
                radius = 5,
                name = "character-corpse"
            })
        
            for _, corpse in pairs(character_corpses) do
                corpse.destroy()
                log_debug("Character corpse removed for player " .. player.name)
            end
        else
            log_debug("Invalid surface for dummy engineer corpse removal for player " .. player.name)
        end

        log_debug("Dummy engineer killed for player " .. player.name)
        end
    else
        log_debug("No valid dummy engineer found for player " .. player.name)
    end

    -- Clean up mod data
    neural_disconnect.clean_up_connection_data(player.index)

    -- Handle respawn logic
    if script.active_mods["space-exploration"] then
        log_debug("Space Exploration mod is active, handling respawn differently")
        -- Add SE-specific respawn logic here if needed
    else
        player.print("Your original character has died. Disconnected from " .. vehicle_type .. " and respawning.", {r=1, g=0, b=0})
    end

    log_debug("Character death handling completed for player " .. player.name)
end

-- Disconnect from any vehicle (using spidertron name for backward compatibility)
function neural_disconnect.disconnect_from_spidertron(args)
    local player_index = args.player_index
    local player = game.get_player(player_index)
    
    if not player then
        log_debug("Player not found for index: " .. player_index)
        return
    end

    -- Use the explicitly passed source vehicle if available
    local source_vehicle = args.source_spidertron
    
    -- If no vehicle was provided, try to find it in storage data
    if not source_vehicle then
        if storage.neural_spider_control and storage.neural_spider_control.connected_spidertrons then
            source_vehicle = storage.neural_spider_control.connected_spidertrons[player_index]
            log_debug("Using lookup for source vehicle")
        end
    else
        log_debug("Using explicitly provided source vehicle #" .. source_vehicle.unit_number)
    end
    
    -- Get vehicle type if available
    local vehicle_type = "spidertron"
    if storage.neural_spider_control and 
       storage.neural_spider_control.vehicle_types and 
       storage.neural_spider_control.vehicle_types[player_index] then
        vehicle_type = storage.neural_spider_control.vehicle_types[player_index]
    end
    
    -- Now pass this source_vehicle to return_to_engineer
    neural_disconnect.return_to_engineer(player, vehicle_type, source_vehicle)
end

return neural_disconnect