--[[
	DataStoreManager.luau
	Handles player data persistence with session locking and auto save
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local DataStoreManager = {}
DataStoreManager.__index = DataStoreManager

local MAX_RETRIES = 3
local AUTO_SAVE_INTERVAL = 300

local activeSessions: { [number]: {} } = {}
local sessionLocks: { [number]: boolean } = {}

local DATA_TEMPLATE = {
	coins = 0,
	inventory = {},
	settings = {
		musicEnabled = true,
		sfxEnabled = true,
	},
	stats = {
		playtime = 0,
		joinCount = 0,
	},
}

function DataStoreManager.new(storeName: string, template: {}?)
	local self = setmetatable({}, DataStoreManager)
	self._store = DataStoreService:GetDataStore(storeName)
	self._template = template or DATA_TEMPLATE
	self._autoSaveThread = nil
	return self
end

local function deepCopy(tbl: {}): {}
	local copy = {}
	for k, v in tbl do
		copy[k] = if type(v) == "table" then deepCopy(v) else v
	end
	return copy
end

-- fills in any missing keys from template so we don't break
-- when adding new fields to the schema down the line
local function reconcile(saved: {}, template: {}): {}
	local result = deepCopy(saved)
	for key, default in template do
		if result[key] == nil then
			result[key] = if type(default) == "table" then deepCopy(default) else default
		elseif type(default) == "table" and type(result[key]) == "table" then
			result[key] = reconcile(result[key], default)
		end
	end
	return result
end

local function withRetry(callback: () -> any): (boolean, any)
	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(callback)
		if ok then return true, result end

		if attempt < MAX_RETRIES then
			task.wait(attempt) -- backoff scales with attempt number
		end
	end

	return false, nil
end

function DataStoreManager:load(player: Player): {}?
	local userId = player.UserId

	if sessionLocks[userId] then
		return activeSessions[userId]
	end

	local ok, data = withRetry(function()
		return self._store:GetAsync(`player_{userId}`)
	end)

	if not ok then
		player:Kick("Couldn't load your data — try rejoining.")
		return nil
	end

	local playerData = reconcile(data or {}, self._template)
	playerData.stats.joinCount += 1

	activeSessions[userId] = playerData
	sessionLocks[userId] = true
	return playerData
end

function DataStoreManager:save(player: Player): boolean
	local data = activeSessions[player.UserId]
	if not data then return false end

	local ok = withRetry(function()
		self._store:SetAsync(`player_{player.UserId}`, data)
	end)

	return ok
end

function DataStoreManager:get(player: Player): {}?
	return activeSessions[player.UserId]
end

-- supports dot paths like "settings.musicEnabled"
function DataStoreManager:set(player: Player, path: string, value: any)
	local data = activeSessions[player.UserId]
	if not data then return end

	local keys = string.split(path, ".")
	local ref = data

	for i = 1, #keys - 1 do
		ref = ref[keys[i]]
		if type(ref) ~= "table" then return end
	end

	ref[keys[#keys]] = value
end

function DataStoreManager:release(player: Player)
	self:save(player)
	activeSessions[player.UserId] = nil
	sessionLocks[player.UserId] = nil
end

function DataStoreManager:startAutoSave()
	if self._autoSaveThread then return end

	self._autoSaveThread = task.spawn(function()
		while true do
			task.wait(AUTO_SAVE_INTERVAL)
			for _, player in Players:GetPlayers() do
				if activeSessions[player.UserId] then
					self:save(player)
				end
			end
		end
	end)
end

function DataStoreManager:bind()
	Players.PlayerAdded:Connect(function(player)
		self:load(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:release(player)
	end)

	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			self:release(player)
		end
	end)

	self:startAutoSave()
end

return DataStoreManager
