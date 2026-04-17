local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local DoorSecurity = {}
DoorSecurity.__index = DoorSecurity

export type AccessLevel = number -- higher = more restricted
export type DoorState = "open" | "closed" | "locked"

export type DoorConfig = {
	openOffset: CFrame,
	speed: number,
	autoCloseDelay: number?,
	accessLevel: AccessLevel,
	requiresKeycard: boolean,
}

local DEFAULT_CONFIG: DoorConfig = {
	openOffset = CFrame.new(0, 0, -5),
	speed = 0.6,
	autoCloseDelay = 5,
	accessLevel = 0,
	requiresKeycard = false,
}

function DoorSecurity.new(doorPart: BasePart, config: DoorConfig?)
	local self = setmetatable({}, DoorSecurity)
	self._door = doorPart
	self._config = config or DEFAULT_CONFIG
	self._closedCFrame = doorPart.CFrame
	self._openCFrame = doorPart.CFrame * (config and config.openOffset or DEFAULT_CONFIG.openOffset)
	self._state = "closed" :: DoorState
	self._activeTween = nil :: Tween?
	self._autoCloseThread = nil
	self._onStateChanged = Instance.new("BindableEvent")
	return self
end

function DoorSecurity:onStateChanged(callback: (DoorState) -> ())
	return self._onStateChanged.Event:Connect(callback)
end

function DoorSecurity:getState(): DoorState
	return self._state
end

function DoorSecurity:_setState(state: DoorState)
	self._state = state
	self._onStateChanged:Fire(state)
end

function DoorSecurity:lock()
	if self._state == "open" then
		self:close()
	end
	self:_setState("locked")
end

function DoorSecurity:unlock()
	if self._state == "locked" then
		self:_setState("closed")
	end
end

-- check if a player has clearance to use this door
function DoorSecurity:canAccess(player: Player, playerLevel: AccessLevel, hasKeycard: boolean?): boolean
	if self._state == "locked" then return false end
	if playerLevel < self._config.accessLevel then return false end
	if self._config.requiresKeycard and not hasKeycard then return false end
	return true
end

function DoorSecurity:open()
	if self._state == "open" or self._state == "locked" then return end

	if self._activeTween then
		self._activeTween:Cancel()
	end

	local tween = TweenService:Create(self._door, TweenInfo.new(
		self._config.speed,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), { CFrame = self._openCFrame })

	tween:Play()
	self._activeTween = tween
	self:_setState("open")

	-- auto close after delay
	local delay = self._config.autoCloseDelay
	if delay and delay > 0 then
		if self._autoCloseThread then
			task.cancel(self._autoCloseThread)
		end

		self._autoCloseThread = task.delay(delay, function()
			self:close()
		end)
	end
end

function DoorSecurity:close()
	if self._state == "closed" or self._state == "locked" then return end

	if self._activeTween then
		self._activeTween:Cancel()
	end

	local tween = TweenService:Create(self._door, TweenInfo.new(
		self._config.speed,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), { CFrame = self._closedCFrame })

	tween:Play()
	self._activeTween = tween
	self:_setState("closed")
end

function DoorSecurity:toggle(player: Player, playerLevel: AccessLevel, hasKeycard: boolean?)
	if not self:canAccess(player, playerLevel, hasKeycard) then return end

	if self._state == "open" then
		self:close()
	else
		self:open()
	end
end

-- setup proximity prompt on the door
function DoorSecurity:bindPrompt(getPlayerAccess: (Player) -> (AccessLevel, boolean))
	local prompt = self._door:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Use Door"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.Parent = self._door
	end

	prompt.Triggered:Connect(function(player)
		local level, hasKey = getPlayerAccess(player)
		self:toggle(player, level, hasKey)
	end)
end

return DoorSecurity
