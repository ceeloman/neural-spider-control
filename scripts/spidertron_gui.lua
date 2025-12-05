-- scripts/spidertron-gui.lua
local neural_connect = require("scripts.neural_connect")
local neural_disconnect = require("scripts.neural_disconnect")
local spidertron_gui = {}

local function log_debug(message)
    -- Logging disabled
end

-- Function to add button to open orphaned engineer inventory
function spidertron_gui.add_orphaned_engineer_button(player, vehicle_type, orphaned_engineer)
    -- Check if the button already exists to avoid duplicates
    local button_name = "spidertron_orphaned_engineer_flow"
    local screen_button_name = "spidertron_orphaned_engineer_screen_flow"
    
    if player.gui.relative[button_name] then
        player.gui.relative[button_name].destroy()
    end
    
    if player.gui.screen[screen_button_name] then
        player.gui.screen[screen_button_name].destroy()
    end

    -- For train GUIs, use screen positioning
    if vehicle_type == "locomotive" or 
       vehicle_type == "cargo-wagon" or 
       vehicle_type == "fluid-wagon" or 
       vehicle_type == "artillery-wagon" then
        -- Create a manually positioned frame for train GUIs
        local flow = player.gui.screen.add{
            type = "frame",
            name = screen_button_name,
            style = "slot_button_deep_frame"
        }
        
        -- Set position to the right of the left frame (440px) and below the connect button (80px)
        flow.location = {456, 80}
        
        flow.style.padding = 2
        
        -- Create the button inside the frame
        local button = flow.add{
            type = "sprite-button",
            name = "nsc_orphaned_engineer_button",
            sprite = "utility/player_force_icon",
            tooltip = "Open Remote Engineer Inventory",
            style = "slot_button"
        }
        
        -- Store engineer reference in button tags
        button.tags = {engineer_unit_number = orphaned_engineer.unit_number}
        
        -- Set the size to match shortcut buttons
        button.style.size = 36
        
        log_debug("Added orphaned engineer button for train for " .. player.name)
        return button
    else
        -- For other vehicle types, use the relative GUI system
        local gui_anchor
        local gui_position
        
        if vehicle_type == "spider-vehicle" then
            gui_anchor = defines.relative_gui_type.spider_vehicle_gui
            gui_position = defines.relative_gui_position.right
        elseif vehicle_type == "car" then
            gui_anchor = defines.relative_gui_type.car_gui
            gui_position = defines.relative_gui_position.right
        else
            log_debug("Unknown vehicle type for GUI anchor: " .. vehicle_type)
            return nil
        end

        -- Create a flow to contain our button
        local flow = player.gui.relative.add{
            type = "frame",
            name = button_name,
            style = "slot_button_deep_frame",
            anchor = {
                gui = gui_anchor,
                position = gui_position
            }
        }
        
        flow.style.padding = 2
        flow.style.top_margin = 45  -- Below the connect button
        flow.style.left_margin = 5
        
        -- Create the button inside the frame
        local button = flow.add{
            type = "sprite-button",
            name = "nsc_orphaned_engineer_button",
            sprite = "utility/player_force_icon",
            tooltip = "Open Remote Engineer Inventory",
            style = "slot_button"
        }
        
        -- Store engineer reference in button tags
        button.tags = {engineer_unit_number = orphaned_engineer.unit_number}
        
        -- Set the size to match shortcut buttons
        button.style.size = 36
        
        log_debug("Added orphaned engineer button for " .. player.name)
        return button
    end
end

-- Function to add the neural connect button to any vehicle GUI using relative GUI
function spidertron_gui.add_neural_connect_button(player, vehicle_type)
    -- Check if the button already exists to avoid duplicates
    if player.gui.relative["spidertron_neural_connect_flow"] then
        player.gui.relative["spidertron_neural_connect_flow"].destroy()
    end
    
    if player.gui.screen["spidertron_neural_connect_screen_flow"] then
        player.gui.screen["spidertron_neural_connect_screen_flow"].destroy()
    end

    -- For train GUIs, use screen positioning
    if vehicle_type == "locomotive" or 
       vehicle_type == "cargo-wagon" or 
       vehicle_type == "fluid-wagon" or 
       vehicle_type == "artillery-wagon" then
        -- Create a manually positioned frame for train GUIs
        local flow = player.gui.screen.add{
            type = "frame",
            name = "spidertron_neural_connect_screen_flow",
            style = "slot_button_deep_frame"
        }
        
        -- Set position to the right of the left frame (440px) and below the top frame (36px)
        flow.location = {456, 44}
        
        flow.style.padding = 2
        
        -- Create the button inside the frame
        local button = flow.add{
            type = "sprite-button",
            name = "nsc_neural_connect_button",
            sprite = "neural-connection-sprite",
            tooltip = "Neural-Connect",
            style = "slot_button"
        }
        
        -- Set the size to match shortcut buttons
        button.style.size = 36
        
        log_debug("Added neural connect button for train for " .. player.name)
        return button
    else
        -- For other vehicle types, use the relative GUI system as before
        local gui_anchor
        local gui_position
        
        if vehicle_type == "spider-vehicle" then
            gui_anchor = defines.relative_gui_type.spider_vehicle_gui
            gui_position = defines.relative_gui_position.right
        elseif vehicle_type == "car" then
            gui_anchor = defines.relative_gui_type.car_gui
            gui_position = defines.relative_gui_position.right
        else
            -- Default fallback or custom handling
            log_debug("Unknown vehicle type for GUI anchor: " .. vehicle_type)
            return nil
        end

        -- Create a flow to contain our button with appropriate background
        local flow = player.gui.relative.add{
            type = "frame",
            name = "spidertron_neural_connect_flow",
            style = "slot_button_deep_frame",
            anchor = {
                gui = gui_anchor,
                position = gui_position
            }
        }
        
        flow.style.padding = 2
        flow.style.top_margin = 5
        flow.style.left_margin = 5
        
        -- Create the button inside the frame
        local button = flow.add{
            type = "sprite-button",
            name = "nsc_neural_connect_button",
            sprite = "neural-connection-sprite",
            tooltip = "Neural-Connect",
            style = "slot_button"
        }
        
        -- Set the size to match shortcut buttons
        button.style.size = 36
        
        log_debug("Added neural connect button for " .. player.name)
        return button
    end
end

-- Function to handle GUI opened event
function spidertron_gui.on_gui_opened(event)
    local player = game.get_player(event.player_index)

    -- Check if the opened GUI is a vehicle entity
    if event.gui_type == defines.gui_type.entity and event.entity and event.entity.valid then
        -- Check for supported vehicle types
        if event.entity.type == "spider-vehicle" or
           event.entity.type == "car" or
           event.entity.type == "locomotive" then
            -- Add the neural connect button using relative GUI
            spidertron_gui.add_neural_connect_button(player, event.entity.type)
            log_debug("Added neural connect button for " .. event.entity.name)
            
            -- Check if vehicle has an orphaned dummy engineer
            local orphaned_engineer, orphaned_data = neural_disconnect.find_orphaned_engineer_for_vehicle(event.entity)
            if orphaned_engineer and orphaned_engineer.valid then
                -- Add button to open orphaned engineer inventory
                spidertron_gui.add_orphaned_engineer_button(player, event.entity.type, orphaned_engineer)
                log_debug("Added orphaned engineer button for " .. event.entity.name)
            end
        end
    end
end

-- Function to clean up any existing GUI elements
function spidertron_gui.cleanup_old_gui_elements(player)
    -- Only check locations that definitely exist and are safe to access
    local locations = {"screen", "relative", "left", "top", "center"}
    
    for _, location in pairs(locations) do
        -- Safe cleanup of specific elements we know about
        local elements_to_check = {
            "spidertron_neural_connect_flow",
            "spidertron_neural_connect_button",
            "neural_connect_flow",
            "neural_connect_button"
        }
        
        for _, element_name in pairs(elements_to_check) do
            if player.gui[location][element_name] then
                log_debug("Removing " .. element_name .. " from " .. location)
                player.gui[location][element_name].destroy()
            end
        end
    end
end

-- Function to handle button click events
function spidertron_gui.on_gui_click(event)
    if event.element.name == "nsc_neural_connect_button" then  -- Changed from "spidertron_neural_connect_button"
        local player = game.get_player(event.player_index)
        local vehicle = player.opened
        player.opened = nil
        player.clear_cursor()
        if vehicle and vehicle.valid then
            neural_connect.connect_to_spidertron({player_index = player.index, spidertron = vehicle})
        else
            player.print("Unable to connect. Please make sure you're interacting with a valid vehicle.")
        end
    elseif event.element.name == "nsc_orphaned_engineer_button" then
        local player = game.get_player(event.player_index)
        local engineer_unit_number = event.element.tags and event.element.tags.engineer_unit_number
        
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
                -- Open the engineer's inventory
                player.opened = engineer
                log_debug("Opened engineer inventory for player " .. player.name .. " (unit #" .. engineer_unit_number .. ")")
            else
                player.print("Engineer no longer exists.", {r=1, g=0.5, b=0})
                log_debug("Could not find engineer with unit_number " .. engineer_unit_number)
            end
        else
            player.print("Unable to find engineer reference.", {r=1, g=0.5, b=0})
        end
    end
end

function spidertron_gui.on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if player.gui.screen["spidertron_neural_control_frame"] then
        player.gui.screen["spidertron_neural_control_frame"].destroy()
    end
    if player.gui.screen["spidertron_neural_connect_screen_flow"] then
        player.gui.screen["spidertron_neural_connect_screen_flow"].destroy()
    end
    if player.gui.screen["spidertron_orphaned_engineer_screen_flow"] then
        player.gui.screen["spidertron_orphaned_engineer_screen_flow"].destroy()
    end
    if player.gui.relative["spidertron_orphaned_engineer_flow"] then
        player.gui.relative["spidertron_orphaned_engineer_flow"].destroy()
    end
end

-- Return the spidertron_gui module
return spidertron_gui