-- scripts/locomotive-gui.lua
local neural_connect = require("scripts.neural_connect")
local space_elevator_compatibility
if script.active_mods["space-exploration"] then
    space_elevator_compatibility = require("compatibility.space_elevator_compatibility")
end
local locomotive_gui = {}


local function log_debug(message)
    -- Logging disabled
end

-- Function to add the neural connect button to the locomotive GUI using relative GUI
function locomotive_gui.add_neural_connect_button(player)
    -- For Factorio 2.0, don't add the button as this functionality is now redundant
    -- and the flying-text entity is causing issues
    log_debug("Checking if we should add locomotive connect button")
    
    -- Disable locomotive functionality in Factorio 2.0
    if script.active_mods["base"] then
        local base_version = script.active_mods["base"]
        log_debug("Base version: " .. base_version)
        
        if string.match(base_version, "^2%.") then
            log_debug("Factorio 2.0 detected, skipping locomotive button")
            return
        end
    end
    
    -- Check if the button already exists to avoid duplicates
    if player.gui.relative.locomotive_neural_connect_button then 
        log_debug("Button already exists")
        return 
    end

    -- Create a relative button and attach it to the locomotive GUI
    log_debug("Adding locomotive neural connect button")
    local button = player.gui.relative.add{
        type = "button",
        name = "locomotive_neural_connect_button",
        caption = "⚡ Connect",
        anchor = {
            gui = defines.relative_gui_type.train_gui,
            position = defines.relative_gui_position.right,
        }
    }

    button.style.top_padding = 2
    button.style.left_padding = 10
    log_debug("Button added successfully")
end

-- Function to handle GUI opened event
function locomotive_gui.on_gui_opened(event)
    local player = game.get_player(event.player_index)
    log_debug("GUI opened for player: " .. player.name)

    -- Check if the opened GUI is a locomotive
    if event.gui_type == defines.gui_type.entity and event.entity and event.entity.type == "locomotive" then
        log_debug("Locomotive GUI opened")
        -- Add the neural connect button using relative GUI
        locomotive_gui.add_neural_connect_button(player)
    end
end

-- Function to handle button click events
function locomotive_gui.on_gui_click(event)
    if event.element.name == "locomotive_neural_connect_button" then
        local player = game.get_player(event.player_index)
        local locomotive = player.opened
        player.opened = nil
        player.clear_cursor()
        if locomotive and locomotive.valid and locomotive.type == "locomotive" then
            if space_elevator_compatibility then
                global.locomotives_near_elevators = global.locomotives_near_elevators or {}
                if space_elevator_compatibility.is_near_space_elevator(locomotive) or global.locomotives_near_elevators[locomotive.unit_number] then
                    player.print("Cannot establish neural link near Space Elevator.", {r=1, g=0.5, b=0})
                else
                    neural_connect.connect_to_locomotive({player_index = player.index, locomotive = locomotive})
                end
            else
                neural_connect.connect_to_locomotive({player_index = player.index, locomotive = locomotive})
            end
        else
            player.print("Unable to connect. Please make sure you're interacting with a valid locomotive.")
        end
    end
end

function locomotive_gui.on_gui_closed(event)
    local player = game.get_player(event.player_index)
    if player.gui.screen["locomotive_neural_control_frame"] then
        player.gui.screen["locomotive_neural_control_frame"].destroy()
    end
end

-- Return the locomotive_gui module
return locomotive_gui