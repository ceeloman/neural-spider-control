local mod_data = require("scripts.mod_data")

local neural_disconnect = {}

local function log_debug(message)
    log("[Neural Vehicle Control] " .. message)
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

-- Spill the contents of an inventory onto the ground
function neural_disconnect.spill_inventory(entity, inventory)
    if not inventory or inventory.is_empty() then return end
    
    log_debug("Spilling inventory with " .. inventory.get_item_count() .. " total items")
    
    -- Get all items from inventory before clearing it
    local items_to_spill = {}
    for i = 1, #inventory do
        local stack = inventory[i]
        if stack and stack.valid_for_read then
            table.insert(items_to_spill, {
                name = stack.name,
                count = stack.count
            })
        end
    end
    
    -- Clear the inventory first to avoid duplication
    inventory.clear()
    
    -- Then spill each item
    for _, item in ipairs(items_to_spill) do
        pcall(function()
            -- Create a simpler item stack to spill
            entity.surface.create_entity{
                name = "item-on-ground",
                position = entity.position,
                stack = item
            }
        end)
    end
    
    log_debug("Spilled " .. #items_to_spill .. " items on the ground")
end

-- Transfer inventory from dummy engineer to vehicle
function neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, vehicle, vehicle_type)
    log_debug("Starting inventory transfer")
    
    local vehicle_name = "unknown"
    if vehicle and vehicle.valid then
        vehicle_name = vehicle.name .. " #" .. vehicle.unit_number
        log_debug("Vehicle is valid, name: " .. vehicle_name)
    else
        log_debug("Vehicle is nil or invalid!")
    end
    
    local dummy_inventory = dummy_engineer.get_main_inventory()
    local items_spilled = false
    
    -- Exit early if there's nothing to transfer
    if dummy_inventory.is_empty() then
        log_debug("Dummy inventory is empty, nothing to transfer")
        return false
    end
    
    -- Determine if we have a valid destination
    if not (vehicle and vehicle.valid) then
        log_debug("No valid vehicle, spilling all items")
        neural_disconnect.spill_inventory(dummy_engineer, dummy_inventory)
        return true
    end
    
    -- Get the vehicle inventory based on vehicle type
    local vehicle_inventory = nil
    
    if vehicle.type == "spider-vehicle" then
        vehicle_inventory = vehicle.get_inventory(defines.inventory.spider_trunk)
    elseif vehicle.type == "locomotive" then
        vehicle_inventory = vehicle.get_inventory(defines.inventory.cargo_wagon)
    elseif vehicle.type == "car" then
        vehicle_inventory = vehicle.get_inventory(defines.inventory.car_trunk)
    end
    
    if not vehicle_inventory then
        log_debug("Vehicle has no inventory, spilling all items")
        neural_disconnect.spill_inventory(dummy_engineer, dummy_inventory)
        return true
    end
    
    log_debug("Processing item transfer for " .. dummy_inventory.get_item_count() .. " items")
    
    -- Copy inventory contents before we modify it
    local items_to_transfer = {}
    for i = 1, #dummy_inventory do
        local stack = dummy_inventory[i]
        if stack and stack.valid_for_read then
            table.insert(items_to_transfer, {
                name = stack.name,
                count = stack.count
            })
        end
    end

    log_debug("Found " .. #items_to_transfer .. " items to transfer")
    
    -- Clear dummy inventory
    dummy_inventory.clear()

    local overflow_items = {}
    
    -- Try to insert each item into the vehicle
    for _, item in ipairs(items_to_transfer) do
        -- Try to insert into the vehicle inventory
        local inserted = 0
        
        if pcall(function() 
            inserted = vehicle_inventory.insert(item)
            return true
        end) then
            log_debug("Inserted " .. inserted .. " of " .. item.count .. " " .. item.name)
            
            -- If not all were inserted, add to overflow
            if inserted < item.count then
                table.insert(overflow_items, {
                    name = item.name,
                    count = item.count - inserted
                })
            end
        else
            -- If insert failed, add entire stack to overflow
            table.insert(overflow_items, item)
        end
    end
    
    -- If any items couldn't fit, spill them
    if #overflow_items > 0 then
        log_debug(#overflow_items .. " stacks couldn't fit in vehicle, spilling")
        items_spilled = true
        
        -- Spill each overflow item
        for _, item in ipairs(overflow_items) do
            pcall(function()
                dummy_engineer.surface.create_entity{
                    name = "item-on-ground",
                    position = dummy_engineer.position,
                    stack = item
                }
            end)
        end
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

    -- Cancel crafting and spill inventory
    neural_disconnect.cancel_crafting_queue(dummy_engineer)
    neural_disconnect.spill_inventory(dummy_engineer, dummy_engineer.get_main_inventory())

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
            elseif raw_type == "locomotive" then
                vehicle_type = "Locomotive"
            elseif raw_type == "car" then
                vehicle_type = "Car"
            end
        end
    end
    
    if original_character and original_character.valid then
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

    -- Destroy the dummy engineer
    if dummy_engineer and dummy_engineer.valid then
        dummy_engineer.destroy()
    end
    
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

    -- Cancel any ongoing crafting
    local crafting_cancelled = neural_disconnect.cancel_crafting_queue(dummy_engineer)
    if crafting_cancelled then
        player.print("Crafting queue has been cancelled.", {r=1, g=0.5, b=0})
    end

    -- Find the vehicle for inventory transfer
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

    -- Transfer inventory or spill if necessary
    local items_spilled = neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, vehicle, actual_vehicle_type)

    -- Find and use the original character
    local original_character
    if storage.neural_spider_control and storage.neural_spider_control.original_characters then
        original_character = storage.neural_spider_control.original_characters[player.index]
    end
    
    if original_character and original_character.valid then
        -- First, disconnect the player from the dummy engineer
        player.character = nil
        
        -- Ensure we're operating on the right surface
        local char_surface = original_character.surface
        
        -- Then teleport the player to the original surface, at the original character's position
        player.teleport(original_character.position, char_surface)
        
        -- Verify player is now on the same surface as the original character
        if player.surface.index == char_surface.index then
            -- Now it's safe to connect to original character
            player.character = original_character
            
            local message = items_spilled and "Remote connection disengaged. Some items spilled." or "Remote connection disengaged." 
            local color = items_spilled and {r=1, g=0.5, b=0} or {r=0, g=1, b=0}
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

    -- Destroy the dummy engineer
    if dummy_engineer and dummy_engineer.valid then
        dummy_engineer.destroy()
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

        -- Cancel any ongoing crafting
        neural_disconnect.cancel_crafting_queue(dummy_engineer)

        -- Transfer items from dummy to vehicle or spill them
        local items_spilled = neural_disconnect.transfer_inventory_to_vehicle(dummy_engineer, connected_vehicle, 
                                                                           control_data.vehicle_types[player_index])
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