local space_elevator_compatibility = {}

function space_elevator_compatibility.is_near_space_elevator(entity)
    if not entity or not entity.valid then return false end
    
    local nearby_elevator = entity.surface.find_entities_filtered{
        area = {{entity.position.x - 3, entity.position.y - 3}, {entity.position.x + 3, entity.position.y + 3}},
        name = "se-space-elevator", -- Adjust this name if necessary
        limit = 1
    }[1]
    
    return nearby_elevator ~= nil
end

return space_elevator_compatibility