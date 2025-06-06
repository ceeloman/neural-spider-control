local neural_connect = require("scripts.neural_connect")
local neural_disconnect = require("scripts.neural_disconnect")

local control_centre = {}

local function get_all_zones()
    return remote.call("space-exploration", "get_zone_index", {})
end

local function get_surface_from_zone(zone)
    return remote.call("space-exploration", "zone_get_surface", {zone_index = zone.index})
end

local function get_zone_from_surface_index(surface_index)
    return remote.call("space-exploration", "get_zone_from_surface_index", {surface_index = surface_index})
end

local function get_zone_from_name(zone_name)
    return remote.call("space-exploration", "get_zone_from_name", {zone_name = zone_name})
end

local function get_display_name(spidertron)
    if spidertron.entity_label and spidertron.entity_label ~= "" then
        return spidertron.entity_label
    elseif spidertron.backer_name and spidertron.backer_name ~= "" then
        return spidertron.backer_name
    else
        -- Use locale file for translation, falling back to the entity name if no translation exists
        return {string.format("entity-name.%s", spidertron.name)}
    end
end

local function get_zones_with_valid_spidertrons(player)
    local zones_with_spidertrons = {}
    local all_zones = get_all_zones()
    
    for _, zone in ipairs(all_zones) do
        local surface = get_surface_from_zone(zone)
        if surface then
            local spidertrons = surface.find_entities_filtered{
                type="spider-vehicle",
                force=player.force
            }
            local valid_spidertrons = {}
            for _, spidertron in ipairs(spidertrons) do
                if spidertron.prototype.allow_passengers then
                    table.insert(valid_spidertrons, spidertron)
                end
            end
            if #valid_spidertrons > 0 then
                table.insert(zones_with_spidertrons, {zone = zone, spidertrons = valid_spidertrons})
            end
        end
    end
    
    return zones_with_spidertrons
end

function control_centre.create_gui(player)
    if player.gui.screen.neural_control_centre then return end
    
    local zones_with_spidertrons = get_zones_with_valid_spidertrons(player)
    
    if #zones_with_spidertrons == 0 then
        player.print({"neural-spidertron-gui.no-valid-spidertrons"})
        return
    end
    
    local frame = player.gui.screen.add{type="frame", name="neural_control_centre", caption={"neural-spidertron-gui.title"}}
    frame.auto_center = true
    
    local content = frame.add{type="flow", direction="vertical", name="content"}
    
    -- Add zone selector
    local zone_flow = content.add{type="flow", direction="horizontal", name="zone_flow"}
    zone_flow.add{type="label", caption={"neural-spidertron-gui.select-zone"}}
    local zone_dropdown = zone_flow.add{type="drop-down", name="zone_selector"}
    
    local player_current_zone = get_zone_from_surface_index(player.surface.index)
    local default_index = 1
    
    for i, zone_data in ipairs(zones_with_spidertrons) do
        zone_dropdown.add_item(zone_data.zone.name)
        if zone_data.zone.index == player_current_zone.index then
            default_index = i
        end
    end
    
    zone_dropdown.selected_index = default_index
    
    -- Add Spidertron list
    local spidertron_list = content.add{type="scroll-pane", name="spidertron_list"}
    spidertron_list.style.maximal_height = 300
    
    content.add{type="button", name="neural_disconnect", caption={"neural-spidertron-gui.disconnect"}}
    content.add{type="button", name="close_control_centre", caption={"neural-spidertron-gui.close"}}

    control_centre.update_spidertron_list(player)

    player.opened = frame
end

function control_centre.update_spidertron_list(player)
    local frame = player.gui.screen.neural_control_centre
    if not frame then return end
    
    local content = frame.content
    if not content then return end

    local spidertron_list = content.spidertron_list
    if not spidertron_list then return end

    spidertron_list.clear()
    
    local zone_selector = content.zone_flow.zone_selector
    if zone_selector.selected_index == 0 then return end
    
    local selected_zone_name = zone_selector.get_item(zone_selector.selected_index)
    local selected_zone = get_zone_from_name(selected_zone_name)
    if not selected_zone then return end
    
    local surface = get_surface_from_zone(selected_zone)
    if not surface then return end
    
    local spidertrons = surface.find_entities_filtered{type="spider-vehicle", force=player.force}
    
    for _, spidertron in ipairs(spidertrons) do
        if spidertron.prototype.allow_passengers then
            local row = spidertron_list.add{type="flow", direction="horizontal"}
            row.style.vertical_align = "center"
            
            local display_name = get_display_name(spidertron)
            
            local name_label = row.add{type="label", caption=display_name}
            name_label.style.minimal_width = 200
            name_label.style.maximal_width = 200
            
            local spacer = row.add{type="empty-widget"}
            spacer.style.horizontally_stretchable = true
            
            row.add{type="button", name="connect_" .. spidertron.unit_number .. "_" .. selected_zone_name, caption={"neural-spidertron-gui.connect"}}
        end
    end
end

function control_centre.on_gui_click(event)
    if not event.element or not event.element.valid then return end

    local player = game.get_player(event.player_index)
    local element = event.element
    
    if element.name == "zone_selector" then
        control_centre.update_spidertron_list(player)
    elseif element.name:find("^connect_") then
        local spidertron_unit_number, zone_name = element.name:match("connect_(%d+)_(.+)")
        spidertron_unit_number = tonumber(spidertron_unit_number)
        local zone = get_zone_from_name(zone_name)
        if not zone then
            player.print("Unable to find zone: " .. zone_name)
            return
        end
        local surface = get_surface_from_zone(zone)
        
        if not surface then
            player.print("Selected zone no longer exists.")
            return
        end
        
        local spidertrons = surface.find_entities_filtered{type="spider-vehicle", force=player.force}
        local spidertron = nil
        for _, spider in pairs(spidertrons) do
            if spider.unit_number == spidertron_unit_number then
                spidertron = spider
                break
            end
        end
        
        if spidertron and spidertron.valid and spidertron.prototype.allow_passengers then
            neural_connect.connect_to_spidertron({player_index = player.index, spidertron = spidertron})
            control_centre.destroy_gui(player)
        else
            player.print("Selected Spidertron is no longer available.")
        end
    elseif element.name == "neural_disconnect" then
        neural_disconnect.disconnect_from_spidertron({player_index = player.index})
        control_centre.destroy_gui(player)
    elseif element.name == "close_control_centre" then
        control_centre.destroy_gui(player)
    end
end

function control_centre.on_gui_selection_state_changed(event)
    if event.element.name == "zone_selector" then
        local player = game.get_player(event.player_index)
        control_centre.update_spidertron_list(player)
    end
end

function control_centre.on_gui_closed(event)
    if event.element and event.element.name == "neural_control_centre" then
        local player = game.get_player(event.player_index)
        control_centre.destroy_gui(player)
    end
end

function control_centre.destroy_gui(player)
    if player.gui.screen.neural_control_centre then
        player.gui.screen.neural_control_centre.destroy()
    end
end

function control_centre.toggle_gui(player)
    if player.gui.screen.neural_control_centre then
        control_centre.destroy_gui(player)
    else
        local zones_with_spidertrons = get_zones_with_valid_spidertrons(player)
        if #zones_with_spidertrons == 0 then
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

function control_centre.open_gui(command)
    local player = game.get_player(command.player_index)
    control_centre.create_gui(player)
end

function control_centre.register_gui()
    script.on_event(defines.events.on_gui_selection_state_changed, control_centre.on_gui_selection_state_changed)
    script.on_event(defines.events.on_gui_closed, control_centre.on_gui_closed)
end

return control_centre