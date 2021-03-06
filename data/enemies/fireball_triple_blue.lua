local enemy = ...

local la = require 'lib/la'
local zentropy = require 'lib/zentropy'

-- A bouncing triple fireball, usually shot by another enemy.

local bounces = 0
local max_bounces = 3
local used_sword = false
local sprite2 = nil
local sprite3 = nil
local bounce = nil

local function minrad(angle)
    while angle <= -math.pi do
        angle = angle + 2 * math.pi
    end
    while angle > math.pi do
        angle = angle - 2 * math.pi
    end
    return angle
end

local function get_bounce_info(dir8, x, y)
    local wall = la.Vect2.direction8[(dir8 + 2) % 8]
    local normal = la.Vect2.direction8[(dir8 + 4) % 8]
    return {
        origin = la.Vect2:new{ x, y },
        normal = normal,
        mirror = la.Matrix2.reflect2(x, y, x + wall[1], y + wall[2]),
    }
end

local function get_bounce_angle(dir8, angle)
    return ((dir8 + 2) * math.pi / 2) - angle
end

local function is_outside(pos)
    return bounce and bounce.normal:dot(pos - bounce.origin) < 0
end

local function get_speed()
    return 48 * bounces + 192
end

function enemy:on_created()
    self:set_life(1)
    self:set_damage(4)
    self:create_sprite("enemies/fireball_triple_blue")
    self:set_size(16, 16)
    self:set_origin(8, 8)
    self:set_obstacle_behavior("flying")
    self:set_invincible()
    self:set_attack_consequence("sword", "custom")

    -- Two smaller fireballs just for the displaying.
    sprite2 = sol.sprite.create("enemies/fireball_triple_blue")
    sprite2:set_animation("small")
    sprite3 = sol.sprite.create("enemies/fireball_triple_blue")
    sprite3:set_animation("tiny")
end

function enemy:on_restarted()
    local hero_x, hero_y = self:get_map():get_entity("hero"):get_position()
    local angle = self:get_angle(hero_x, hero_y - 5)
    local m = sol.movement.create("straight")
    m:set_speed(get_speed())
    m:set_angle(angle)
    m:set_smooth(false)
    m:start(self)
end

function enemy:on_obstacle_reached()
    if bounces < max_bounces then
        -- Compute the bouncing angle (works well with horizontal and vertical walls).
        local m = self:get_movement()

        local dir = self:get_obstacle_direction8()
        if dir ~= -1 then
            m:set_angle(get_bounce_angle(dir, m:get_angle()))
            m:set_speed(192 + 48 * bounces)

            bounce = get_bounce_info(dir, self:get_position())
            bounces = bounces + 1
        end
    else
        self:remove()
    end
end

function enemy:on_pre_draw()
    local m = self:get_movement()
    local angle = m:get_angle()
    local x, y = self:get_position()

    local v2 = la.Vect2:new{x - math.cos(angle) * 12, y + math.sin(angle) * 12}
    if is_outside(v2) then v2 = bounce.mirror:vmul(v2) end
    self:get_map():draw_sprite(sprite2, v2[1], v2[2])

    local v3 = la.Vect2:new{x - math.cos(angle) * 24, y + math.sin(angle) * 24}
    if is_outside(v3) then v3 = bounce.mirror:vmul(v3) end
    self:get_map():draw_sprite(sprite3, v3[1], v3[2])
end

-- Method called by other enemies.
function enemy:bounce()
    zentropy.debug('bounce')
    local m = self:get_movement()
    local angle = m:get_angle()
    angle = angle + math.pi

    m:set_angle(angle)
    m:set_speed(get_speed())
    used_sword = false
end
