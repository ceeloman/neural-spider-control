-- Modify the spiderbot prototype in data-updates stage
local function modify_spiderbot_prototype()
    local spiderbot = data.raw["spider-vehicle"]["spiderbot"]
    if spiderbot then
        -- Allow passengers
        spiderbot.allow_passengers = true
        
        -- Flag the spiderbot for special handling in control stage
        spiderbot.neural_control_enabled = true
        
        --log("Modified spiderbot prototype for neural control compatibility")
    else
        --log("Spiderbot prototype not found. Make sure Spiderbots mod is loaded before this compatibility file.")
    end
end

-- Check if Spiderbots mod is installed
if mods["spiderbots"] then
    modify_spiderbot_prototype()
end

-- Modify the spiderdrone prototype in data-updates stage
local function modify_spiderdrone_prototype()
    local spiderdrone = data.raw["spider-vehicle"]["spiderdrone"]
    if spiderdrone then
        -- Allow passengers
        spiderdrone.allow_passengers = true
        
        -- Flag the spiderdrone for special handling in control stage
        spiderdrone.neural_control_enabled = true
        
        --log("Modified spiderdrone prototype for neural control compatibility")
    else
        --log("Spiderdrone prototype not found. Make sure Spiderdrone mod is loaded before this compatibility file.")
    end
end

if mods["spiderdrone"] then
    modify_spiderdrone_prototype()
end

-- Modify the spiderdrone prototype in data-updates stage
local function modify_spiderbot_mk2_prototype()
    local spiderbot_mk2 = data.raw["spider-vehicle"]["spiderbot-mk2"]
    if spiderbot_mk2 then
        -- Allow passengers
        spiderbot_mk2.allow_passengers = true
        
        -- Flag the spiderdrone for special handling in control stage
        spiderbot_mk2.neural_control_enabled = true
        
        --log("Modified spiderdrone prototype for neural control compatibility")
    else
        --log("Spiderdrone prototype not found. Make sure Spiderdrone mod is loaded before this compatibility file.")
    end
end

if mods["ceelos-vehicle-tweaks"] then
    modify_spiderbot_mk2_prototype()
end