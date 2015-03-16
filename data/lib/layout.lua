local Class = require 'lib/class'
local Util = require 'lib/util'


local Layout = {}


local WeightVisitor = {}
setmetatable(WeightVisitor, WeightVisitor)

function WeightVisitor:visit_room(room)
    local weights = {
        Room=0,
        Treasure=0,
        Enemy=0,
    }
    room:each_child(function (key, child)
        weights[child.class] = weights[child.class] + child:accept(self)
    end)
    return math.max(1, weights.Room)
end

function WeightVisitor:visit_treasure(treasure)
    return 0
end

function WeightVisitor:visit_enemy(enemy)
    return 0
end


Layout.DIRECTIONS = { east=0, north=1, west=2, south=3, }


local BaseVisitor = Class:new()

function BaseVisitor:visit_enemy(enemy)
    table.insert(self.enemies, enemy)
end

function BaseVisitor:visit_treasure(treasure)
    table.insert(self.items, treasure)
end

function BaseVisitor:visit_room(room)
    local y = self.y
    local x0 = self.x
    local is_heavy = self.is_heavy
    local x1 = x0
    local doors = {}
    local items = {}
    local enemies = {}
    local forward_x, furthest_ew, forward_ew, backward_ew = self:get_directions()

    if self.doors then
        if is_heavy then
            self.doors[forward_ew] = Util.filter_keys(room, {'see','reach','open'})
        else
            self.doors.north = Util.filter_keys(room, {'see','reach','open'})
        end
    end

    local total_weight = 0
    local heavy_weight = 0
    local heavy_key = nil
    room:each_child(function (key, child)
        local child_weight = child:accept(WeightVisitor)
        total_weight = total_weight + child_weight
        if child_weight > heavy_weight then
            heavy_weight = child_weight
            heavy_key = key
        end
    end)
    if total_weight == heavy_weight then
        heavy_key = nil
    end

    self.is_heavy = false
    room:each_child(function (key, child)
        if key ~= heavy_key then
            self.y = y - 1
            self.items = items
            self.enemies = enemies
            if child.class == 'Room' then
                x1 = self.x
                doors[x1] = doors[x1] or {}
                self.doors = doors[x1]
            end
            child:accept(self)
        end
    end)
    self.x = furthest_ew(self.x, x0 + forward_x)

    if heavy_key then
        x1, self.y, self.is_heavy = self:get_heavy_child_properties(self.x, y)
        doors[x1] = doors[x1] or {}
        self.doors = doors[x1]
        room.children[heavy_key]:accept(self)
    end

    for x = x0, x1, forward_x do
        doors[x] = doors[x] or {}
        if x == x0 then
            if is_heavy then
                doors[x][backward_ew] = Util.filter_keys(room, {'open'})
            else
                doors[x].south = Util.filter_keys(room, {'open'})
            end
        end
        if x ~= x1 then doors[x][forward_ew] = {} end
        if x ~= x0 then doors[x][backward_ew] = {} end
        if doors[x].north then
            doors[x].north.name = string.format('door_%d_%d_n', x, y)
        end
        self:render_room{
            x=x,
            y=y,
            doors=doors[x],
            items=items,
            enemies=enemies,
            savegame_variable = room.savegame_variable .. '_' .. (x - x0)
        }
        items = {}
        enemies = {}
    end

end

function BaseVisitor:render(tree)
    if self.on_start then
        self:on_start()
    end
    tree:accept(self)
    if self.on_finish then
        self:on_finish()
    end
end

function BaseVisitor:on_start()
    self.x = self.start_x
    self.y = self.start_y
end


Layout.NorthwardVisitor = BaseVisitor:new{ start_x=0, start_y=9 }

function Layout.NorthwardVisitor:get_heavy_child_properties(x, y)
    return x, y - 1, false
end

function Layout.NorthwardVisitor:get_directions()
    return 1, math.max, 'east', 'west'
end


Layout.NorthEastwardVisitor = BaseVisitor:new{ start_x=0, start_y=9 }

function Layout.NorthEastwardVisitor:get_heavy_child_properties(x, y)
    return x - 1, y, true
end

function Layout.NorthEastwardVisitor:get_directions()
    return 1, math.max, 'east', 'west'
end


Layout.NorthWestwardVisitor = BaseVisitor:new{ start_x=9, start_y=9 }

function Layout.NorthWestwardVisitor:get_heavy_child_properties(x, y)
    return x + 1, y, true
end

function Layout.NorthWestwardVisitor:get_directions()
    return -1, math.min, 'west', 'east'
end


function Layout.print_mixin(object)

    function object:rfinish_room(properties)
        function print_access(thing)
            if thing.see and thing.see ~= 'nothing' then print(string.format("\t\tto see: %s", thing.see)) end
            if thing.reach and thing.reach ~= 'nothing' then print(string.format("\t\tto reach: %s", thing.reach)) end
            if thing.open and thing.open ~= 'nothing' then print(string.format("\t\tto open: %s", thing.open)) end
        end
        print(string.format("Room %d;%d", properties.x, properties.y))
        for dir, door in pairs(properties.doors) do
            print(string.format("  Door %s", dir))
            print_access(door)
        end
        for _, item in ipairs(properties.items) do
            print(string.format("  Item %s", item.name))
            print_access(item)
        end
        for _, enemy in ipairs(properties.enemies) do
            print(string.format("  Enemy %s", enemy.name))
            print_access(enemy)
        end
        print()
    end


    return object
end

function Layout.minimap_mixin(object, map_menu)

    function object:render_room(properties)
        map_menu:draw_room(properties)
    end

    local old_on_start = object.on_start

    function object:on_start()
        if old_on_start then
            old_on_start(self)
        end
        map_menu:clear_map()
    end

    return object
end

function Layout.solarus_mixin(object, map)

    local map_width, map_height = map:get_size()

    function mark_known_room(x, y)
        map:get_game():set_value(string.format('room_%d_%d', x, y), true)
    end

    function add_doorway(separators, x, y, direction, savegame_variable)
        separators[y] = separators[y] or {}
        separators[y][x] = separators[y][x] or {}
        separators[y][x][Layout.DIRECTIONS[direction]] = savegame_variable
    end

    function object:move_hero_to_start()
        local hero = map:get_hero()
        map:get_hero():set_position(320 * self.start_x + 320 / 2, 240 * self.start_y + 232, 1)
        map:get_hero():set_direction(1)
    end

    local old_on_start = object.on_start
    local old_on_finish = object.on_finish

    function object:on_start()
        self.separators = {}
        self.rooms = {}
        if old_on_start then
            old_on_start(self)
        end
    end

    function object:render_room(properties)
        local x = 320 * properties.x
        local y = 240 * properties.y
        local room_properties = Util.filter_keys(properties, {'doors', 'items', 'enemies'})
        room_properties.name = string.format('room_%d_%d', properties.x, properties.y)
        self.rooms[y] = self.rooms[y] or {}
        self.rooms[y][x] = room_properties

        add_doorway(self.separators, properties.x,   properties.y+1, 'north', properties.doors.south and properties.savegame_variable or false)
        add_doorway(self.separators, properties.x,   properties.y,   'east',  properties.doors.west  and properties.savegame_variable or false)
        add_doorway(self.separators, properties.x,   properties.y,   'south', properties.doors.north and properties.savegame_variable or false)
        add_doorway(self.separators, properties.x+1, properties.y,   'west',  properties.doors.east  and properties.savegame_variable or false)
    end

    function object:on_finish()
        if old_on_finish then
            old_on_finish(self)
        end

        for y, row in Util.pairs_by_keys(self.rooms) do
            for x, properties in Util.pairs_by_keys(row) do
                map:include(x, y, 'rooms/room1', properties)
            end
        end

        mark_known_room(self.start_x, self.start_y)
        for y, row in pairs(self.separators) do
            for x, room in pairs(row) do
                if room[Layout.DIRECTIONS.north] ~= nil or room[Layout.DIRECTIONS.south] ~= nil then
                    local properties = {
                        x = 320 * x,
                        y = 240 * y - 8,
                        layer = 1,
                        width = 320,
                        height = 16,
                    }
                    local sep = map:create_separator(properties)
                    if room[Layout.DIRECTIONS.north] then
                        function sep:on_activated(dir)
                            local my_y = (dir == Layout.DIRECTIONS.north) and y - 1 or y
                            local my_x = (dir == Layout.DIRECTIONS.west) and x - 1 or x
                            mark_known_room(my_x, my_y)
                        end
                    end
                end
                if room[Layout.DIRECTIONS.east] ~= nil or room[Layout.DIRECTIONS.west] ~= nil then
                    local properties = {
                        x = 320 * x - 8,
                        y = 240 * y,
                        layer = 1,
                        width = 16,
                        height = 240,
                    }
                    local sep = map:create_separator(properties)
                    if room[Layout.DIRECTIONS.west] then
                        function sep:on_activated(dir)
                            local my_y = (dir == Layout.DIRECTIONS.north) and y - 1 or y
                            local my_x = (dir == Layout.DIRECTIONS.west) and x - 1 or x
                            mark_known_room(my_x, my_y)
                        end
                    end
                end
            end
        end
    end

    return object
end


return Layout
