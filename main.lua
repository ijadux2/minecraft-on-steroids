-- minecaft on steroids 
-- by ijadux2 
-- built in lua and frame-work in love 
-- minecaft in lua & love
-- CONSTANTS

local BLOCK_SIZE = 1.0 -- For 3D math, blocks are sized 1x1x1
local CHUNK_SIZE = 16 -- 16x16x16 blocks per chunk
local RENDER_DISTANCE = 4-- How many chunks away to draw
local WORLD_HEIGHT = 128 -- Max world height

-- BLOCK TYPES (Simple enumeration)

local BLOCK = {

AIR = 0,
GRASS = 1,
DIRT = 2,
STONE = 3,

}
-- Game State

local World = {}

local Camera = {}
function love.load()
end

