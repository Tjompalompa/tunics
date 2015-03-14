local Tree = require 'lib/tree.lua'
local List = require 'lib/list.lua'

local HideTreasuresVisitor = {}

setmetatable(HideTreasuresVisitor, HideTreasuresVisitor)

function HideTreasuresVisitor:visit_room(room)
    room:each_child(function (key, child)
        if child.class == 'Treasure' and child.open ~= 'big_key' then
            room:update_child(key, child:with_needs{see='compass'})
        end
        child:accept(self)
    end)
end
function HideTreasuresVisitor:visit_treasure(treasure)
end
function HideTreasuresVisitor:visit_enemy(enemy)
end

local TreasureCountVisitor = {}

setmetatable(TreasureCountVisitor, TreasureCountVisitor)

function TreasureCountVisitor:visit_room(room)
    local total_keys
    if room.open == 'small_key' then
        total_keys = -1
    else
        total_keys = 0
    end
    room:each_child(function (key, child)
        if (not child.open or child.open == 'nothing') and (not child.reach or child.reach == 'nothing') and (not child.see or child.see == 'nothing') then
            total_keys = total_keys + child:accept(self)
        end
    end)
    return total_keys
end

function TreasureCountVisitor:visit_treasure(treasure)
    local keys
    if treasure.open == 'small_key' then
        keys = -1
    else
        keys = 0
    end
    if treasure.name == 'small_key' then
        return 0, keys + 1
    else
        return 1, keys
    end
end

function TreasureCountVisitor:visit_enemy(enemy)
    return 0, 0
end

local Puzzle = {}

function Puzzle.treasure_step(item_name)
    return function (root)
        root:add_child(Tree.Treasure:new{name=item_name})
    end
end

function Puzzle.boss_step(root)
    root:add_child(Tree.Enemy:new{name='boss'}:with_needs{open='big_key'})
end

function Puzzle.hide_treasures_step(root)
    root:accept(HideTreasuresVisitor)
end

function Puzzle.obstacle_step(item_name)
    return function (root)
        root:each_child(function (key, head)
            root:update_child(key, head:with_needs{reach=item_name})
        end)
    end
end

function Puzzle.big_chest_step(item_name)
    return function (root)
        root:add_child(Tree.Treasure:new{name=item_name, open='big_key'})
    end
end

function Puzzle.bomb_doors_step(root)
    root:each_child(function (key, head)
        root:update_child(key, head:with_needs{see='map',open='bomb'})
    end)
end

function Puzzle.locked_door_step(root)
    function lockable_weight(node)
        if node.class == 'Room' then
            local keys = node:accept(TreasureCountVisitor)
            if keys > 1 then
                return keys
            else
                return 0
            end
        else
            return 0
        end
    end
    local key, child = root:random_child(lockable_weight)
    if key then
        root:update_child(key, child:with_needs{open='small_key'})
        return true
    else
        return false
    end
end

function Puzzle.max_heads(n)
    return function (root)
        while #root.children > n do
            local fork = Tree.Room:new()
            fork:merge_child(root:remove_child(root:random_child()))
            fork:merge_child(root:remove_child(root:random_child()))
            root:add_child(fork)
        end
    end
end

function Puzzle.compass_puzzle()
    return {
        Puzzle.hide_treasures_step,
        Puzzle.treasure_step('compass'),
    }
end

function Puzzle.map_puzzle()
    local steps = {
        Puzzle.treasure_step('bomb'),
        Puzzle.treasure_step('map'),
    }
    List.shuffle(steps)
    table.insert(steps, 1, Puzzle.bomb_doors_step)
    return steps
end

function Puzzle.items_puzzle(item_names)
    List.shuffle(item_names)
    local steps = {}
    for _, item_name in ipairs(item_names) do
        table.insert(steps, Puzzle.obstacle_step(item_name))
        table.insert(steps, Puzzle.big_chest_step(item_name))
    end
    table.insert(steps, Puzzle.treasure_step('big_key'))
    return steps
end

function Puzzle.lock_puzzle()
    return {
        function (root)
            if Puzzle.locked_door_step(root) then
                Puzzle.treasure_step('small_key')(root)
            end
        end,
    }
end

return Puzzle
