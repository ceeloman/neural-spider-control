-- scripts/spidertron-gui.lua
local neural_connect = require("scripts.neural_connect")
local neural_disconnect = require("scripts.neural_disconnect")
local shared_toolbar = require("__ceelos-vehicle-gui-util__/lib/shared_toolbar")
local spidertron_gui = {}

local MOD_NAME = "neural-spider-control"

local function log_debug(message)
    -- Logging disabled
end

-- Function to add button to open orphaned engineer inventory
function spidertron_gui.add_orphaned_engineer_button(player, vehicle_type, orphaned_engineer, entity)
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
        -- For spider-vehicles, use the shared toolbar
        if vehicle_type == "spider-vehicle" then
            -- Use the entity passed in, or fall back to player.opened
            local vehicle = entity or player.opened
            if not vehicle or not vehicle.valid or vehicle.type ~= "spider-vehicle" then
                log_debug("No valid spider-vehicle for shared toolbar")
                return nil
            end
            
            -- Get or create the shared toolbar
            local success, toolbar = pcall(function()
                return shared_toolbar.get_or_create_shared_toolbar(player, vehicle)
            end)
            
            if not success then
                log_debug("pcall failed to get shared toolbar, error: " .. tostring(toolbar))
                return nil
            end
            
            if not toolbar or not toolbar.valid then
                log_debug("Toolbar is nil or invalid: " .. tostring(toolbar))
                return nil
            end
            
            -- Navigate to button_flow
            local button_frame = toolbar["button_frame"]
            if not button_frame or not button_frame.valid then
                log_debug("Button frame not found in toolbar")
                return nil
            end
            
            local button_flow = button_frame["button_flow"]
            if not button_flow or not button_flow.valid then
                log_debug("Button flow not found in button_frame")
                return nil
            end
            
            -- Check if button already exists
            local shared_button_name = MOD_NAME .. "_orphaned_engineer"
            local existing_button = button_flow[shared_button_name]
            if existing_button and existing_button.valid then
                -- Update tags with current engineer unit number
                existing_button.tags = {engineer_unit_number = orphaned_engineer.unit_number}
                log_debug("Orphaned engineer button already exists: " .. shared_button_name)
                return existing_button
            end
            
            -- Create the button in the shared toolbar
            local glib_available, glib = pcall(require, "__glib__/glib")
            local success2, button = pcall(function()
                local btn
                if glib_available and glib then
                    -- Use glib.add like other buttons
                    local refs = {}
                    btn, refs = glib.add(button_flow, {
                        args = {
                            type = "sprite-button",
                            name = shared_button_name,
                            sprite = "utility/player_force_icon",
                            tooltip = "Open Remote Engineer Inventory",
                            style = "slot_sized_button"
                        },
                        ref = "orphaned_engineer"
                    }, refs)
                else
                    -- Fallback to direct add
                    btn = button_flow.add{
                        type = "sprite-button",
                        name = shared_button_name,
                        sprite = "utility/player_force_icon",
                        tooltip = "Open Remote Engineer Inventory",
                        style = "slot_sized_button"
                    }
                end
                return btn
            end)
            
            if not success2 or not button or not button.valid then
                log_debug("Failed to create orphaned engineer button in shared toolbar")
                return nil
            end
            
            -- Store engineer reference in button tags
            button.tags = {engineer_unit_number = orphaned_engineer.unit_number}
            
            log_debug("Added orphaned engineer button to shared toolbar for " .. player.name)
            return button
        elseif vehicle_type == "car" then
            -- For cars, use the relative GUI system
            local gui_anchor = defines.relative_gui_type.car_gui
            local gui_position = defines.relative_gui_position.right

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
            
            log_debug("Added orphaned engineer button for car for " .. player.name)
            return button
        else
            log_debug("Unknown vehicle type for GUI anchor: " .. vehicle_type)
            return nil
        end
    end
end

-- Function to add the neural connect button to any vehicle GUI using relative GUI
function spidertron_gui.add_neural_connect_button(player, vehicle_type, entity)
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
        -- For spider-vehicles, use the shared toolbar
        if vehicle_type == "spider-vehicle" then
            -- Use the entity passed in, or fall back to player.opened
            local vehicle = entity or player.opened
            if not vehicle or not vehicle.valid or vehicle.type ~= "spider-vehicle" then
                log_debug("No valid spider-vehicle for shared toolbar")
                return nil
            end
            
            -- Get or create the shared toolbar
            local success, toolbar = pcall(function()
                return shared_toolbar.get_or_create_shared_toolbar(player, vehicle)
            end)
            
            if not success then
                log_debug("pcall failed to get shared toolbar, error: " .. tostring(toolbar))
                return nil
            end
            
            if not toolbar or not toolbar.valid then
                log_debug("Toolbar is nil or invalid: " .. tostring(toolbar))
                return nil
            end
            
            log_debug("Toolbar found/created: " .. toolbar.name .. ", type: " .. toolbar.type)
            log_debug("Toolbar has " .. #toolbar.children .. " children")
            
            -- Navigate to button_flow
            -- The toolbar structure is: toolbar -> button_frame -> button_flow
            local button_frame = toolbar["button_frame"]
            if not button_frame then
                log_debug("Button frame not found by name, checking children...")
                -- Try to find it in children
                for _, child in ipairs(toolbar.children) do
                    log_debug("Toolbar child: " .. tostring(child.name) .. ", type: " .. child.type)
                    if child.name == "button_frame" then
                        button_frame = child
                        break
                    end
                end
            end
            
            if not button_frame or not button_frame.valid then
                log_debug("Button frame not found in toolbar after search")
                return nil
            end
            
            log_debug("Button frame found: " .. button_frame.name)
            log_debug("Button frame has " .. #button_frame.children .. " children")
            
            local button_flow = button_frame["button_flow"]
            if not button_flow then
                log_debug("Button flow not found by name, checking children...")
                -- Try to find it in children
                for _, child in ipairs(button_frame.children) do
                    log_debug("Button frame child: " .. tostring(child.name) .. ", type: " .. child.type)
                    if child.name == "button_flow" then
                        button_flow = child
                        break
                    end
                end
            end
            
            if not button_flow or not button_flow.valid then
                log_debug("Button flow not found in button_frame after search")
                return nil
            end
            
            log_debug("Button flow found: " .. button_flow.name)
            
            -- Check if button already exists
            local button_name = MOD_NAME .. "_neural_connect"
            local existing_button = button_flow[button_name]
            if existing_button and existing_button.valid then
                log_debug("Neural connect button already exists: " .. button_name)
                return existing_button
            end
            
            -- Debug: Check button_flow children count before adding
            log_debug("Button flow has " .. #button_flow.children .. " children before adding neural connect button")
            
            -- Create the button in the shared toolbar
            -- Try using glib if available, otherwise use direct add
            local glib_available, glib = pcall(require, "__glib__/glib")
            local success2, button = pcall(function()
                local btn
                if glib_available and glib then
                    -- Use glib.add like spidertron-logistics does
                    local refs = {}
                    btn, refs = glib.add(button_flow, {
                        args = {
                            type = "sprite-button",
                            name = button_name,
                            sprite = "neural-connection-sprite",
                            tooltip = "Neural-Connect",
                            style = "slot_sized_button"
                        },
                        ref = "neural_connect"
                    }, refs)
                    log_debug("Button created with glib, name: " .. tostring(btn.name) .. ", valid: " .. tostring(btn.valid))
                else
                    -- Fallback to direct add
                    btn = button_flow.add{
                        type = "sprite-button",
                        name = button_name,
                        sprite = "neural-connection-sprite",
                        tooltip = "Neural-Connect",
                        style = "slot_sized_button"
                    }
                    log_debug("Button created with direct add, name: " .. tostring(btn.name) .. ", valid: " .. tostring(btn.valid))
                end
                return btn
            end)
            
            if not success2 then
                log_debug("pcall failed to create button, error: " .. tostring(button))
                return nil
            end
            
            if not button or not button.valid then
                log_debug("Button is nil or invalid: " .. tostring(button))
                return nil
            end
            
            -- Debug: Check button_flow children count after adding
            log_debug("Button flow has " .. #button_flow.children .. " children after adding neural connect button")
            
            -- Verify the button is actually in the button_flow
            local verify_button = button_flow[button_name]
            if verify_button and verify_button.valid then
                log_debug("Verified button exists in button_flow: " .. button_name)
                log_debug("Button visible: " .. tostring(verify_button.visible))
                log_debug("Button style: " .. tostring(verify_button.style))
                log_debug("Button sprite: " .. tostring(verify_button.sprite))
            else
                log_debug("WARNING: Button not found in button_flow after creation!")
            end
            
            -- Double-check by iterating children
            log_debug("All buttons in button_flow:")
            for i, child in ipairs(button_flow.children) do
                log_debug("  [" .. i .. "] " .. tostring(child.name) .. " (" .. child.type .. ")")
            end
            
            -- Also check if spidertron-logistics buttons exist
            local sl_toggle = button_flow["spidertron-logistics_toggle"]
            local sl_dump = button_flow["spidertron-logistics_dump"]
            local sl_remote = button_flow["spidertron-logistics_remote"]
            log_debug("Spidertron-logistics buttons: toggle=" .. tostring(sl_toggle ~= nil) .. ", dump=" .. tostring(sl_dump ~= nil) .. ", remote=" .. tostring(sl_remote ~= nil))
            
            log_debug("Added neural connect button to shared toolbar for " .. player.name .. " with name: " .. button_name)
            return button
        elseif vehicle_type == "car" then
            -- For cars, use the old relative GUI system
            local gui_anchor = defines.relative_gui_type.car_gui
            local gui_position = defines.relative_gui_position.right

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
            
            log_debug("Added neural connect button for car for " .. player.name)
            return button
        else
            -- Default fallback or custom handling
            log_debug("Unknown vehicle type for GUI anchor: " .. vehicle_type)
            return nil
        end
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
            -- Add the neural connect button using relative GUI, pass the entity
            local button = spidertron_gui.add_neural_connect_button(player, event.entity.type, event.entity)
            if button then
                log_debug("Successfully added neural connect button for " .. event.entity.name)
            else
                log_debug("Failed to add neural connect button for " .. event.entity.name)
            end
            
            -- Check if vehicle has an orphaned dummy engineer
            local orphaned_engineer, orphaned_data = neural_disconnect.find_orphaned_engineer_for_vehicle(event.entity)
            if orphaned_engineer and orphaned_engineer.valid then
                -- Add button to open orphaned engineer inventory
                spidertron_gui.add_orphaned_engineer_button(player, event.entity.type, orphaned_engineer, event.entity)
                log_debug("Added orphaned engineer button for " .. event.entity.name)
            end
        end
    end
end

-- Function to clean up any existing GUI elements
function spidertron_gui.cleanup_old_gui_elements(player)
    -- Remove from shared toolbar
    shared_toolbar.remove_from_shared_toolbar(player, MOD_NAME, "neural_connect")
    shared_toolbar.remove_from_shared_toolbar(player, MOD_NAME, "orphaned_engineer")
    
    -- Only check locations that definitely exist and are safe to access
    local locations = {"screen", "relative", "left", "top", "center"}
    
    for _, location in pairs(locations) do
        -- Safe cleanup of specific elements we know about (old implementation)
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
    -- Handle both old button name and new shared toolbar button name
    if event.element.name == "nsc_neural_connect_button" or event.element.name == MOD_NAME .. "_neural_connect" then
        local player = game.get_player(event.player_index)
        local vehicle = player.opened
        player.opened = nil
        player.clear_cursor()
        if vehicle and vehicle.valid then
            neural_connect.connect_to_spidertron({player_index = player.index, spidertron = vehicle})
        else
            player.print("Unable to connect. Please make sure you're interacting with a valid vehicle.")
        end
    elseif event.element.name == "nsc_orphaned_engineer_button" or event.element.name == MOD_NAME .. "_orphaned_engineer" then
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
    
    -- Remove buttons from shared toolbar for spider-vehicles
    shared_toolbar.remove_from_shared_toolbar(player, MOD_NAME, "neural_connect")
    shared_toolbar.remove_from_shared_toolbar(player, MOD_NAME, "orphaned_engineer")
    
    -- Clean up old button implementation (for backwards compatibility)
    if player.gui.relative["spidertron_neural_connect_flow"] then
        player.gui.relative["spidertron_neural_connect_flow"].destroy()
    end
end

-- Return the spidertron_gui module
return spidertron_gui