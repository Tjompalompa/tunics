local puzzle = {}

local util = require 'lib/util'

function puzzle.init(map, data)

    local chest = map:get_entity('chest')
    local switch = map:get_entity('switch')
    local sensor_north = map:get_entity('sensor_north')
    local sensor_south = map:get_entity('sensor_south')
    local sensor_east = map:get_entity('sensor_east')
    local sensor_west = map:get_entity('sensor_west')

    local function sensor_activated()
        if not switch:is_activated() then
            for dir, _ in pairs(data.doors) do
                map:close_doors('door_' .. dir)
            end
        end
    end

    if data.item_name or next(data.doors) then
        local placeholders = {}
        for entity in map:get_entities('placeholder_') do
            table.insert(placeholders, entity)
        end
        local hideout = placeholders[data.rng:random(#placeholders)]

        hideout:set_enabled(false)
        switch:set_position(hideout:get_position())

        local block = map:get_entity('block_' .. hideout:get_name())
        if block then
            block:set_pushable(true)
            if zentropy.settings.debug_cheat then
                local x, y = block:get_position()
                block:set_position(x, y - 1)
            end
        end

        sensor_north.on_activated = sensor_activated
        sensor_south.on_activated = sensor_activated
        sensor_east.on_activated = sensor_activated
        sensor_west.on_activated = sensor_activated

        function switch:on_activated()
            if data.item_name then
                chest:set_enabled(true)
                sol.audio.play_sound('chest_appears')
            end
            for dir, _ in pairs(data.doors) do
                map:open_doors('door_' .. dir)
                if not next(data.doors, dir) then
                    sol.audio.play_sound('secret')
                end
            end
        end
    else
        switch:set_enabled(false)
    end

    map:add_on_started(function ()
        map:set_doors_open('door_', true)
        for dir, _ in pairs(data.doors) do
            map:get_entity('door_' .. dir .. '_top'):set_enabled(true)
        end
        if chest:is_open() then
            switch:set_activated(true)
        else
            chest:set_enabled(false)
        end
    end)
end

return puzzle
