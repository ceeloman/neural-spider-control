local neural_connect = require("scripts.neural_connect")
local neural_disconnect = require("scripts.neural_disconnect")

local function log_debug(message)
    -- Logging disabled
end

local control_centre = {}

-- Helper function to get valid Spidertrons
local function get_valid_spidertrons(player)
    local valid_spidertrons = {}
    local all_spidertrons = player.surface.find_entities_filtered{type="spider-vehicle", force=player.force}
    
    for _, spidertron in ipairs(all_spidertrons) do
        if spidertron.prototype.allow_passengers then
            table.insert(valid_spidertrons, spidertron)
        end
    end
    
    return valid_spidertrons
end

-- Helper function to get display name for Spidertron
local function get_display_name(spidertron)
    if spidertron.entity_label and spidertron.entity_label ~= "" then
        return spidertron.entity_label
    elseif spidertron.backer_name and spidertron.backer_name ~= "" then
        return spidertron.backer_name
    else
        return {string.format("entity-name.%s", spidertron.name)}
    end
end

-- Create the control centre GUI
function control_centre.create_gui(player)
    if player.gui.screen.neural_control_centre then
        --log_debug("GUI already exists")
        return
    end
    
    local valid_spidertrons = get_valid_spidertrons(player)
    
    if #valid_spidertrons == 0 then
        player.print({"neural-spidertron-gui.no-valid-spidertrons"})
        return
    end
    
    -- Create main frame without caption (we'll add our own titlebar)
    local frame = player.gui.screen.add{type="frame", name="neural_control_centre", caption=""}
    frame.auto_center = true
    
    -- Create a vertical flow for the entire content
    local main_flow = frame.add{type="flow", direction="vertical"}
    main_flow.style.padding = 0
    main_flow.style.margin = 0
    
    -- Create title bar with close button
    local titlebar = main_flow.add{type="flow", direction="horizontal"}
    titlebar.drag_target = frame
    titlebar.style.horizontally_stretchable = true
    titlebar.style.padding = {2, 4}
    
    -- Add title
    local title = titlebar.add{type="label", caption={"neural-spidertron-gui.title"}}
    title.style.font = "heading-2"
    
    -- Add spacer to push close button to the right
    local spacer = titlebar.add{type="empty-widget"}
    spacer.style.horizontally_stretchable = true
    
    -- Add close button (X)
    local close_button = titlebar.add{
        type="sprite-button",
        name="close_neural_control_centre",
        sprite="utility/close",
        tooltip={"gui.close"},
        style="frame_action_button"
    }
    
    -- Add a line separator after the titlebar
    main_flow.add{type="line", direction="horizontal"}
    
    -- Main content container
    local content = main_flow.add{type="flow", direction="vertical", name="content"}
    content.style.padding = {4, 4}
    
    -- Spidertron list
    local spidertron_list = content.add{type="scroll-pane", name="spidertron_list"}
    spidertron_list.style.maximal_height = 300
    
    -- Add header for current surface
    local surface_name = player.surface.name
    local capitalized_surface_name = surface_name:sub(1,1):upper() .. surface_name:sub(2)
    local header = spidertron_list.add{type="label", caption="Available Connections on " .. capitalized_surface_name}
    header.style.font = "default-bold"
    
    -- Add divider
    spidertron_list.add{type="line", direction="horizontal"}.style.margin = {top=2, bottom=5}
    
    for _, spidertron in ipairs(valid_spidertrons) do
        local row = spidertron_list.add{type="flow", direction="horizontal"}
        row.style.vertical_align = "center"
        
        local display_name = get_display_name(spidertron)
        
        local name_label = row.add{type="label", caption=display_name}
        name_label.style.minimal_width = 200
        name_label.style.maximal_width = 200
        
        local spacer = row.add{type="empty-widget"}
        spacer.style.horizontally_stretchable = true
        
        row.add{
            type="button", 
            name="connect_" .. spidertron.unit_number, 
            caption={"neural-spidertron-gui.connect"}
        }
    end
    
    -- Add buttons at the bottom
    local button_flow = content.add{type="flow", direction="horizontal"}
    button_flow.style.horizontal_align = "center"
    button_flow.style.top_margin = 8
    
    button_flow.add{type="button", name="neural_disconnect", caption={"neural-spidertron-gui.disconnect"}}
    button_flow.add{type="button", name="close_control_centre", caption={"neural-spidertron-gui.close"}}
    
    player.opened = frame
end

-- Destroy the control centre GUI
function control_centre.destroy_gui(player)
    if player.gui.screen.neural_control_centre then
        player.gui.screen.neural_control_centre.destroy()
        --log_debug("GUI destroyed")
    end
end

-- Toggle GUI visibility
function control_centre.toggle_gui(player)
    if player.gui.screen.neural_control_centre then
        control_centre.destroy_gui(player)
    else
        local valid_spidertrons = get_valid_spidertrons(player)
        if #valid_spidertrons == 0 then
            player.create_local_flying_text{
                text = {"neural-spidertron-gui.no-valid-spidertrons"},
                position = player.position,
                color = {r=1, g=0.5, b=0.5}
            }
        else
            control_centre.create_gui(player)
        end
    end
end

-- Handle GUI click events
function control_centre.on_gui_click(event)
    local player = game.get_player(event.player_index)
    local element = event.element
    
    if not element or not element.valid then return end
    
    if element.name == "neural_disconnect" then
        log_debug("Processing neural disconnect button")
        
        -- Try a safe neural disconnect directly
        if storage and storage.neural_spider_control then
            log_debug("Storage table available for disconnect")
            
            -- Check if player is connected to a spidertron
            if storage.neural_spider_control.connected_spidertrons and 
               storage.neural_spider_control.connected_spidertrons[player.index] then
                log_debug("Found spidertron connection for player " .. player.name)
                neural_disconnect.disconnect_from_spidertron({player_index = player.index})
            elseif storage.neural_locomotive_control and 
                   storage.neural_locomotive_control.connected_locomotives and 
                   storage.neural_locomotive_control.connected_locomotives[player.index] then
                log_debug("Found locomotive connection for player " .. player.name)
                neural_disconnect.disconnect_from_locomotive({player_index = player.index})
            else
                log_debug("No neural connection found for player " .. player.name)
                player.print("No active neural connection.")
            end
        else
            log_debug("Storage table not available for disconnect")
            player.print("Cannot disconnect at this time. Please try again in a moment.")
        end
        
        control_centre.destroy_gui(player)
    elseif element.name == "close_control_centre" then
        control_centre.destroy_gui(player)
    elseif element.name == "close_neural_control_centre" then
        control_centre.destroy_gui(player)
    elseif element.name:find("^connect_") then
        -- Parse the spidertron unit number from the button name
        local unit_number = tonumber(element.name:match("connect_(%d+)"))
        
        if unit_number then
            -- Find the spidertron with this unit number
            local valid_spidertrons = get_valid_spidertrons(player)
            local spidertron = nil
            
            for _, spider in ipairs(valid_spidertrons) do
                if spider.unit_number == unit_number then
                    spidertron = spider
                    break
                end
            end
            
            if spidertron and spidertron.valid then
                log_debug("Connecting to spidertron #" .. unit_number)
                neural_connect.connect_to_spidertron({player_index = player.index, spidertron = spidertron})
                control_centre.destroy_gui(player)
            else
                player.print("Selected Spidertron is no longer available.")
            end
        end
    end
end

-- Open the control centre GUI
function control_centre.open_gui(command)
    local player = game.get_player(command.player_index)
    control_centre.create_gui(player)
end

-- Handle GUI close events
function control_centre.on_gui_closed(event)
    -- Check if the event is related to our GUI
    if event.gui_type and event.gui_type == defines.gui_type.custom then
        local player = game.get_player(event.player_index)
        -- Check if our GUI exists before destroying it
        if player.gui.screen.neural_control_centre then
            control_centre.destroy_gui(player)
        end
    end
end

-- Register GUI event handlers
function control_centre.register_gui()
end

return control_centre