--[[
	RoundManager.luau
	State-driven round loop with configurable phases.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundManager = {}
RoundManager.__index = RoundManager

export type RoundPhase = "waiting" | "intermission" | "active" | "ending"

local DEFAULT_CONFIG = {
	minPlayers = 2,
	intermissionTime = 15,
	roundTime = 180,
	endingTime = 8,
	checkInterval = 1,
}

function RoundManager.new(config: {}?)
	local self = setmetatable({}, RoundManager)
	self._config = config or DEFAULT_CONFIG
	self._phase = "waiting" :: RoundPhase
	self._activePlayers = {} :: { Player }
	self._onPhaseChanged = Instance.new("BindableEvent")
	self._running = false
	self._roundNumber = 0
	return self
end

function RoundManager:getPhase(): RoundPhase
	return self._phase
end

function RoundManager:_setPhase(phase: RoundPhase)
	local previous = self._phase
	self._phase = phase
	self._onPhaseChanged:Fire(phase, previous)
end

function RoundManager:onPhaseChanged(callback: (RoundPhase, RoundPhase) -> ())
	return self._onPhaseChanged.Event:Connect(callback)
end

local function getEligiblePlayers(): { Player }
	local eligible = {}
	for _, player in Players:GetPlayers() do
		-- could add level/team checks here later
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			local humanoid = player.Character.Humanoid
			if humanoid.Health > 0 then
				table.insert(eligible, player)
			end
		end
	end
	return eligible
end

function RoundManager:_waitForPlayers()
	self:_setPhase("waiting")

	while #getEligiblePlayers() < self._config.minPlayers do
		task.wait(self._config.checkInterval)
	end
end

function RoundManager:_intermission()
	self:_setPhase("intermission")
	task.wait(self._config.intermissionTime)
end

function RoundManager:_startRound()
	self._roundNumber += 1
	self._activePlayers = getEligiblePlayers()
	self:_setPhase("active")

	-- track eliminations during the round
	local connections = {}
	for _, player in self._activePlayers do
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			local conn = player.Character.Humanoid.Died:Connect(function()
				self:_removePlayer(player)
			end)
			table.insert(connections, conn)
		end
	end

	local elapsed = 0
	while elapsed < self._config.roundTime do
		task.wait(self._config.checkInterval)
		elapsed += self._config.checkInterval

		-- end early if everyone died or left
		if #self._activePlayers <= 1 then
			break
		end
	end

	for _, conn in connections do
		conn:Disconnect()
	end
end

function RoundManager:_removePlayer(player: Player)
	local idx = table.find(self._activePlayers, player)
	if idx then
		table.remove(self._activePlayers, idx)
	end
end

function RoundManager:_endRound()
	self:_setPhase("ending")

	local winners = self._activePlayers
	-- hook reward logic, stat tracking, etc here

	self._activePlayers = {}
	task.wait(self._config.endingTime)
end

function RoundManager:getActivePlayers(): { Player }
	return self._activePlayers
end

function RoundManager:getRoundNumber(): number
	return self._roundNumber
end

function RoundManager:start()
	if self._running then return end
	self._running = true

	task.spawn(function()
		while self._running do
			self:_waitForPlayers()
			self:_intermission()

			-- re-check after intermission in case people left
			if #getEligiblePlayers() < self._config.minPlayers then
				continue
			end

			self:_startRound()
			self:_endRound()
		end
	end)
end

function RoundManager:stop()
	self._running = false
end

return RoundManager
