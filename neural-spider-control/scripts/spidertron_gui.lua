-- scripts/spidertron-gui.lua
local neural_connect = require("scripts.neural_connect")
local spidertron_gui = {}

local function log_debug(message)
    log("[Neural Vehicle Control] " .. message)
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
end

-- Return the spidertron_gui module
return spidertron_gui