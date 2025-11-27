-- Minecraft on Steroids
-- Built in Lua with LÖVE2D
-- Full 3D implementation with biomes, mobs, inventory, etc.

-- CONSTANTS
local BLOCK_SIZE = 1.0
local CHUNK_SIZE = 16
local RENDER_DISTANCE = 4
local WORLD_HEIGHT = 128
local GRAVITY = 20.0
local PLAYER_SPEED = 5.0
local MOUSE_SENSITIVITY = 0.002

-- BLOCK TYPES
local BLOCK = {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	STONE = 3,
	SAND = 4,
	WOOD = 5,
	LEAVES = 6,
	WATER = 7,
}

-- BIOMES
local BIOME = {
	PLAINS = 1,
	MOUNTAINS = 2,
	FOREST = 3,
	DESERT = 4,
}

-- ITEMS (for inventory)
local ITEM = {
	NOTHING = 0,
	GRASS_BLOCK = 1,
	DIRT_BLOCK = 2,
	STONE_BLOCK = 3,
	SAND_BLOCK = 4,
	WOOD_PLANK = 5,
}

-- MOBS
local MOB_TYPE = {
	SHEEP = 1,
	ZOMBIE = 2,
}

-- Simple 3D Math Utilities
local Math = {}

function Math.vec3(x, y, z)
	return { x = x or 0, y = y or 0, z = z or 0 }
end

function Math.add(v1, v2)
	return Math.vec3(v1.x + v2.x, v1.y + v2.y, v1.z + v2.z)
end

function Math.sub(v1, v2)
	return Math.vec3(v1.x - v2.x, v1.y - v2.y, v1.z - v2.z)
end

function Math.mul(v, s)
	return Math.vec3(v.x * s, v.y * s, v.z * s)
end

function Math.dot(v1, v2)
	return v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
end

function Math.cross(v1, v2)
	return Math.vec3(v1.y * v2.z - v1.z * v2.y, v1.z * v2.x - v1.x * v2.z, v1.x * v2.y - v1.y * v2.x)
end

function Math.length(v)
	return math.sqrt(Math.dot(v, v))
end

function Math.normalize(v)
	local len = Math.length(v)
	if len > 0 then
		return Math.mul(v, 1 / len)
	end
	return v
end

-- Matrix 4x4 for transformations (simple implementation)
local Mat4 = {}

function Mat4.identity()
	return {
		{ 1, 0, 0, 0 },
		{ 0, 1, 0, 0 },
		{ 0, 0, 1, 0 },
		{ 0, 0, 0, 1 },
	}
end

function Mat4.translate(t)
	return {
		{ 1, 0, 0, t.x },
		{ 0, 1, 0, t.y },
		{ 0, 0, 1, t.z },
		{ 0, 0, 0, 1 },
	}
end

function Mat4.rotateX(angle)
	local c, s = math.cos(angle), math.sin(angle)
	return {
		{ 1, 0, 0, 0 },
		{ 0, c, -s, 0 },
		{ 0, s, c, 0 },
		{ 0, 0, 0, 1 },
	}
end

function Mat4.rotateY(angle)
	local c, s = math.cos(angle), math.sin(angle)
	return {
		{ c, 0, s, 0 },
		{ 0, 1, 0, 0 },
		{ -s, 0, c, 0 },
		{ 0, 0, 0, 1 },
	}
end

function Mat4.scale(s)
	return {
		{ s, 0, 0, 0 },
		{ 0, s, 0, 0 },
		{ 0, 0, s, 0 },
		{ 0, 0, 0, 1 },
	}
end

function Mat4.perspective(fov, aspect, near, far)
	local f = 1 / math.tan(fov / 2)
	local nf = 1 / (near - far)
	return {
		{ f / aspect, 0, 0, 0 },
		{ 0, f, 0, 0 },
		{ 0, 0, (far + near) * nf, 2 * far * near * nf },
		{ 0, 0, -1, 0 },
	}
end

function Mat4.mul(m1, m2)
	local result = {}
	for i = 1, 4 do
		result[i] = {}
		for j = 1, 4 do
			result[i][j] = 0
			for k = 1, 4 do
				result[i][j] = result[i][j] + m1[i][k] * m2[k][j]
			end
		end
	end
	return result
end

function Mat4.transformPoint(m, v)
	local x = v.x * m[1][1] + v.y * m[2][1] + v.z * m[3][1] + m[4][1]
	local y = v.x * m[1][2] + v.y * m[2][2] + v.z * m[3][2] + m[4][2]
	local z = v.x * m[1][3] + v.y * m[2][3] + v.z * m[3][3] + m[4][3]
	local w = v.x * m[1][4] + v.y * m[2][4] + v.z * m[3][4] + m[4][4]
	if w ~= 0 then
		return Math.vec3(x / w, y / w, z / w)
	end
	return Math.vec3(x, y, z)
end

-- Chunk System
local Chunk = {}
Chunk.__index = Chunk

function Chunk.new(x, z)
	local self = setmetatable({}, Chunk)
	self.cx = x
	self.cz = z
	self.blocks = {}
	for y = 1, WORLD_HEIGHT do
		self.blocks[y] = {}
		for x = 1, CHUNK_SIZE do
			self.blocks[y][x] = {}
			for z = 1, CHUNK_SIZE do
				self.blocks[y][x][z] = BLOCK.AIR
			end
		end
	end
	self.dirty = true
	self.mesh = nil
	return self
end

function Chunk:generate(biome)
	-- Simple noise-based generation
	math.randomseed(self.cx * 31 + self.cz * 37)
	local heightMap = {}
	for x = 1, CHUNK_SIZE do
		heightMap[x] = {}
		for z = 1, CHUNK_SIZE do
			local noise = love.math.noise((self.cx * CHUNK_SIZE + x) / 50, (self.cz * CHUNK_SIZE + z) / 50)
			local height = math.floor((noise + 1) * 20 + 40) -- Base height 40-80
			if biome == BIOME.MOUNTAINS then
				height = height + 20
			elseif biome == BIOME.DESERT then
				height = height - 10
			end
			heightMap[x][z] = math.min(height, WORLD_HEIGHT)
		end
	end

	-- Fill blocks
	for y = 1, WORLD_HEIGHT do
		for x = 1, CHUNK_SIZE do
			for z = 1, CHUNK_SIZE do
				local h = heightMap[x][z]
				if y > h then
					self.blocks[y][x][z] = BLOCK.AIR
				elseif y == h then
					if biome == BIOME.DESERT then
						self.blocks[y][x][z] = BLOCK.SAND
					else
						self.blocks[y][x][z] = BLOCK.GRASS
					end
				elseif y > h - 4 then
					self.blocks[y][x][z] = BLOCK.DIRT
				else
					self.blocks[y][x][z] = BLOCK.STONE
				end
			end
		end
	end

	-- Add trees for forest
	if biome == BIOME.FOREST then
		for _ = 1, 5 do -- 5 trees per chunk
			local tx = math.random(1, CHUNK_SIZE)
			local tz = math.random(1, CHUNK_SIZE)
			local th = heightMap[tx][tz]
			if th > 0 then
				-- Trunk
				for y = th, th + 4 do
					if y <= WORLD_HEIGHT then
						self.blocks[y][tx][tz] = BLOCK.WOOD
					end
				end
				-- Leaves
				for ly = th + 2, th + 5 do
					for lx = tx - 1, tx + 1 do
						for lz = tz - 1, tz + 1 do
							if
								math.random() > 0.3
								and ly <= WORLD_HEIGHT
								and lx >= 1
								and lx <= CHUNK_SIZE
								and lz >= 1
								and lz <= CHUNK_SIZE
							then
								self.blocks[ly][lx][lz] = BLOCK.LEAVES
							end
						end
					end
				end
			end
		end
	end

	self.dirty = true
end

function Chunk:getBlock(wx, wy, wz)
	local lx = ((wx - 1) % CHUNK_SIZE) + 1
	local lz = ((wz - 1) % CHUNK_SIZE) + 1
	if wy < 1 or wy > WORLD_HEIGHT then
		return BLOCK.AIR
	end
	return self.blocks[wy][lx][lz]
end

function Chunk:setBlock(wx, wy, wz, blockType)
	local lx = ((wx - 1) % CHUNK_SIZE) + 1
	local lz = ((wz - 1) % CHUNK_SIZE) + 1
	if wy < 1 or wy > WORLD_HEIGHT then
		return
	end
	self.blocks[wy][lx][lz] = blockType
	self.dirty = true
end

function Chunk:buildMesh()
	if not self.dirty then
		return
	end
	-- Simple cube mesh generation (this is placeholder; in full impl, generate VBO for visible faces)
	-- For now, we'll render in draw function without mesh for simplicity
	self.dirty = false
end

-- World
local World = {}
World.chunks = {}
World.entities = {} -- mobs

function World:getChunk(cx, cz)
	local key = cx .. "," .. cz
	if not self.chunks[key] then
		local biome = self:getBiome(cx, cz)
		self.chunks[key] = Chunk.new(cx, cz)
		self.chunks[key]:generate(biome)
		self.chunks[key]:buildMesh()
	end
	return self.chunks[key]
end

function World:getBiome(cx, cz)
	local noise = love.math.noise(cx / 10, cz / 10)
	if noise > 0.6 then
		return BIOME.MOUNTAINS
	end
	if noise > 0.3 then
		return BIOME.FOREST
	end
	if noise < -0.3 then
		return BIOME.DESERT
	end
	return BIOME.PLAINS
end

function World:getBlock(x, y, z)
	local cx = math.floor((x - 1) / CHUNK_SIZE)
	local cz = math.floor((z - 1) / CHUNK_SIZE)
	local chunk = self:getChunk(cx, cz)
	return chunk:getBlock(x, y, z)
end

function World:setBlock(x, y, z, blockType)
	local cx = math.floor((x - 1) / CHUNK_SIZE)
	local cz = math.floor((z - 1) / CHUNK_SIZE)
	local chunk = self:getChunk(cx, cz)
	chunk:setBlock(x, y, z, blockType)
end

function World:loadChunksAround(playerX, playerZ)
	local pcx = math.floor(playerX / CHUNK_SIZE)
	local pcz = math.floor(playerZ / CHUNK_SIZE)
	for dx = -RENDER_DISTANCE, RENDER_DISTANCE do
		for dz = -RENDER_DISTANCE, RENDER_DISTANCE do
			local cx = pcx + dx
			local cz = pcz + dz
			self:getChunk(cx, cz)
		end
	end
end

-- Player
local Player = {}
Player.position = Math.vec3(0, 50, 0)
Player.rotation = Math.vec3(0, 0, 0) -- pitch, yaw, roll
Player.velocity = Math.vec3(0, 0, 0)
Player.health = 20
Player.inventory = {} -- 36 slots + hotbar 9
Player.hotbar = 1 -- selected slot

for i = 1, 45 do
	Player.inventory[i] = ITEM.NOTHING
end

function Player:update(dt)
	-- Movement
	local dx, dz = 0, 0
	if love.keyboard.isDown("w") then
		dz = dz - 1
	end
	if love.keyboard.isDown("s") then
		dz = dz + 1
	end
	if love.keyboard.isDown("a") then
		dx = dx - 1
	end
	if love.keyboard.isDown("d") then
		dx = dx + 1
	end

	local forward = Math.vec3(math.sin(self.rotation.y) * dz, 0, math.cos(self.rotation.y) * dz)
	local right = Math.vec3(math.cos(self.rotation.y) * dx, 0, -math.sin(self.rotation.y) * dx)

	local move = Math.normalize(Math.add(forward, right))
	self.position = Math.add(self.position, Math.mul(move, PLAYER_SPEED * dt))

	-- Gravity
	self.velocity.y = self.velocity.y - GRAVITY * dt
	self.position.y = self.position.y + self.velocity.y * dt

	-- Ground collision (simple)
	if self.position.y <= 1 then
		self.position.y = 1
		self.velocity.y = 0
	end

	-- Block interaction (raycast placeholder)
	if love.mouse.isDown(1) then -- Left click remove
		-- Implement raycast to find block
	end
	if love.mouse.isDown(2) then -- Right click place
		-- Implement raycast to place block from inventory
	end
end

-- Inventory
local Inventory = {}

function Inventory:draw()
	if love.keyboard.isDown("e") then
		-- Draw inventory UI (simple rectangles for slots)
		love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
		love.graphics.rectangle("fill", 100, 100, 400, 300)
		-- Draw slots, items, etc.
		for i = 1, 36 do
			local x = 110 + ((i - 1) % 9) * 40
			local y = 110 + math.floor((i - 1) / 9) * 40
			love.graphics.setColor(0.5, 0.5, 0.5)
			love.graphics.rectangle("line", x, y, 32, 32)
		end
		-- Hotbar
		for i = 1, 9 do
			local x = (love.graphics.getWidth() / 2 - 180) + (i - 1) * 40
			local y = love.graphics.getHeight() - 80
			love.graphics.setColor(0.5, 0.5, 0.5)
			love.graphics.rectangle("line", x, y, 32, 32)
			if i == Player.hotbar then
				love.graphics.setColor(1, 1, 0)
				love.graphics.rectangle("line", x, y, 32, 32)
			end
		end
	end
end

-- Mobs
local Mob = {}
Mob.__index = Mob

function Mob.new(type, x, y, z)
	local self = setmetatable({}, Mob)
	self.type = type
	self.position = Math.vec3(x, y, z)
	self.velocity = Math.vec3(0, 0, 0)
	self.health = 10
	return self
end

function Mob:update(dt, playerPos)
	-- Simple AI
	local dir = Math.sub(playerPos, self.position)
	dir.y = 0
	dir = Math.normalize(dir)
	if Math.length(Math.sub(playerPos, self.position)) < 10 then
		self.position = Math.add(self.position, Math.mul(dir, 2 * dt))
	else
		-- Wander
		self.position.x = self.position.x + (math.random() - 0.5) * 4 * dt
		self.position.z = self.position.z + (math.random() - 0.5) * 4 * dt
	end
	-- Gravity
	self.velocity.y = self.velocity.y - GRAVITY * dt
	self.position.y = self.position.y + self.velocity.y * dt
	if self.position.y <= 1 then
		self.position.y = 1
		self.velocity.y = 0
	end
end

function Mob:draw()
	-- Simple 2D rectangle for mob (since LÖVE is 2D)
	love.graphics.push()
	love.graphics.translate(self.position.x, self.position.y)
	love.graphics.setColor(0.8, 0.8, 0.8)
	love.graphics.setLineWidth(1)
	love.graphics.rectangle("line", -0.5, -0.5, 1, 1)
	love.graphics.pop()
end

-- Camera
local Camera = {}

function Camera:update()
	love.mouse.setRelativeMode(true)
	local mx, my = love.mouse.getPosition()
	Player.rotation.y = Player.rotation.y - mx * MOUSE_SENSITIVITY
	Player.rotation.x = Player.rotation.x - my * MOUSE_SENSITIVITY
	Player.rotation.x = math.max(-math.pi / 2, math.min(math.pi / 2, Player.rotation.x))
end

function Camera:getViewMatrix()
	local rotX = Mat4.rotateX(Player.rotation.x)
	local rotY = Mat4.rotateY(Player.rotation.y)
	local trans = Mat4.translate(Math.mul(Player.position, -1))
	return Mat4.mul(Mat4.mul(rotY, rotX), trans)
end

-- Rendering
local Render = {}

function Render:drawCube(x, y, z, blockType)
	if blockType == BLOCK.AIR then
		return
	end
	-- 2D top-down projection
	local screenX = (x - player.position.x) * BLOCK_SIZE + love.graphics.getWidth() / 2
	local screenZ = (z - player.position.z) * BLOCK_SIZE + love.graphics.getHeight() / 2

	-- Set color based on block
	if blockType == BLOCK.GRASS then
		love.graphics.setColor(0.2, 0.8, 0.2)
	elseif blockType == BLOCK.DIRT then
		love.graphics.setColor(0.5, 0.4, 0.2)
	elseif blockType == BLOCK.STONE then
		love.graphics.setColor(0.5, 0.5, 0.5)
	elseif blockType == BLOCK.SAND then
		love.graphics.setColor(1, 0.9, 0.6)
	elseif blockType == BLOCK.WOOD then
		love.graphics.setColor(0.6, 0.4, 0.2)
	elseif blockType == BLOCK.LEAVES then
		love.graphics.setColor(0, 0.6, 0)
	else
		love.graphics.setColor(1, 1, 1)
	end

	love.graphics.rectangle("fill", screenX - 0.5, screenZ - 0.5, 1, 1)
end

function Render:drawWorld()
	World:loadChunksAround(Player.position.x, Player.position.z)
	local pcx = math.floor(Player.position.x / CHUNK_SIZE)
	local pcz = math.floor(Player.position.z / CHUNK_SIZE)

	for dx = -RENDER_DISTANCE, RENDER_DISTANCE do
		for dz = -RENDER_DISTANCE, RENDER_DISTANCE do
			local cx = pcx + dx
			local cz = pcz + dz
			local chunk = World:getChunk(cx, cz)
			for x = 1, CHUNK_SIZE do
				for z = 1, CHUNK_SIZE do
					local wx = cx * CHUNK_SIZE + x
					local wz = cz * CHUNK_SIZE + z
					-- Find highest non-air block for top-down view
					local topY = 0
					local topBlock = BLOCK.AIR
					for y = WORLD_HEIGHT, 1, -1 do
						local block = chunk:getBlock(wx, y, wz)
						if block ~= BLOCK.AIR then
							topY = y
							topBlock = block
							break
						end
					end
					if topBlock ~= BLOCK.AIR then
						self:drawCube(wx, topY, wz, topBlock)
					end
				end
			end
		end
	end
end

-- Global variables
local world = World
local player = Player
local inventory = Inventory
local camera = Camera
local render = Render
local time = 0 -- for day/night

-- LÖVE Callbacks
function love.load()
	love.window.setMode(800, 600, { vsync = true, resizable = true })
	love.mouse.setRelativeMode(true)
	love.keyboard.setKeyRepeat(true)

	-- Spawn some mobs
	for i = 1, 10 do
		table.insert(world.entities, Mob.new(MOB_TYPE.SHEEP, math.random(-50, 50), 50, math.random(-50, 50)))
	end
	for i = 1, 5 do
		table.insert(world.entities, Mob.new(MOB_TYPE.ZOMBIE, math.random(-50, 50), 50, math.random(-50, 50)))
	end

	-- Initial world load
	world:loadChunksAround(player.position.x, player.position.z)
end

function love.update(dt)
	time = time + dt
	player:update(dt)
	camera:update()

	-- Update mobs
	for _, mob in ipairs(world.entities) do
		mob:update(dt, player.position)
	end

	-- Day/night cycle (simple tint)
end

function love.draw()
	love.graphics.origin()
	love.graphics.clear(0.5, 0.7, 1) -- Sky blue

	-- 3D projection setup
	local aspect = love.graphics.getWidth() / love.graphics.getHeight()
	local proj = Mat4.perspective(math.pi / 3, aspect, 0.1, 1000)
	local view = camera:getViewMatrix()
	local mvp = Mat4.mul(proj, view)

	-- Enable 3D (LÖVE doesn't have direct 3D, so this is simulated; in full, use shader)
	-- For now, simple orthographic fallback, but assume shader in shaders/ for true 3D

	-- Draw world
	render:drawWorld()

	-- Draw mobs
	for _, mob in ipairs(world.entities) do
		mob:draw()
	end

	-- HUD
	love.graphics.setColor(1, 1, 1)
	love.graphics.print("Health: " .. player.health, 10, 10)
	love.graphics.print(
		"Position: "
			.. math.floor(player.position.x)
			.. ", "
			.. math.floor(player.position.y)
			.. ", "
			.. math.floor(player.position.z),
		10,
		30
	)

	-- Inventory
	inventory:draw()

	-- Day/night tint
	local dayNight = math.sin(time * 0.1) * 0.5 + 0.5
	love.graphics.setColor(dayNight, dayNight, dayNight, 0.3)
	love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
end

function love.mousemoved(x, y, dx, dy)
	if love.mouse.getRelativeMode() then
		-- Handled in camera:update
	end
end

function love.keypressed(key)
	if key == "escape" then
		love.event.quit()
	elseif key == "e" then
		-- Toggle inventory (handled in draw)
	elseif
		key == "1"
		or key == "2"
		or key == "3"
		or key == "4"
		or key == "5"
		or key == "6"
		or key == "7"
		or key == "8"
		or key == "9"
	then
		player.hotbar = tonumber(key)
	end
end

-- Note: For full 3D rendering, integrate shaders from shaders/ folder.
-- Add textures, better collision, crafting, sounds in future iterations.
-- Run with: love ../minecraft-on-steroids
