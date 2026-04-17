local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local MovementController = {}
MovementController.__index = MovementController

local player = Players.LocalPlayer

local SPEEDS = {
	walk = 16,
	sprint = 28,
	crouch = 8,
}

local STAMINA_MAX = 100
local STAMINA_DRAIN = 12 -- per second while sprinting
local STAMINA_REGEN = 6  -- per second while not sprinting

function MovementController.new()
	local self = setmetatable({}, MovementController)
	self._sprinting = false
	self._crouching = false
	self._stamina = STAMINA_MAX
	self._enabled = true
	self._connections = {}
	return self
end

local function getHumanoid(): Humanoid?
	local char = player.Character
	return if char then char:FindFirstChild("Humanoid") else nil
end

local function setSpeed(speed: number)
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.WalkSpeed = speed
	end
end

function MovementController:setSprinting(sprinting: boolean)
	if not self._enabled then return end
	if sprinting and self._stamina <= 0 then return end

	self._sprinting = sprinting
	self._crouching = if sprinting then false else self._crouching

	setSpeed(if sprinting then SPEEDS.sprint else SPEEDS.walk)
end

function MovementController:setCrouching(crouching: boolean)
	if not self._enabled then return end

	self._crouching = crouching
	self._sprinting = if crouching then false else self._sprinting

	setSpeed(if crouching then SPEEDS.crouch else SPEEDS.walk)

	-- scale the character down a bit for crouching
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.HipHeight = if crouching then 0 else 2
	end
end

function MovementController:getStamina(): number
	return self._stamina
end

function MovementController:setEnabled(enabled: boolean)
	self._enabled = enabled
	if not enabled then
		self._sprinting = false
		self._crouching = false
		setSpeed(0)
	else
		setSpeed(SPEEDS.walk)
	end
end

function MovementController:_updateStamina(dt: number)
	if self._sprinting then
		self._stamina = math.max(0, self._stamina - STAMINA_DRAIN * dt)
		if self._stamina <= 0 then
			self:setSprinting(false)
		end
	else
		self._stamina = math.min(STAMINA_MAX, self._stamina + STAMINA_REGEN * dt)
	end
end

function MovementController:_bindInputs()
	-- sprint on left shift
	ContextActionService:BindAction("Sprint", function(_name, state)
		if state == Enum.UserInputState.Begin then
			self:setSprinting(true)
		elseif state == Enum.UserInputState.End then
			self:setSprinting(false)
		end
	end, false, Enum.KeyCode.LeftShift)

	-- toggle crouch on C
	ContextActionService:BindAction("Crouch", function(_name, state)
		if state == Enum.UserInputState.Begin then
			self:setCrouching(not self._crouching)
		end
	end, false, Enum.KeyCode.C)
end

function MovementController:start()
	self:_bindInputs()

	local conn = RunService.Heartbeat:Connect(function(dt)
		self:_updateStamina(dt)
	end)
	table.insert(self._connections, conn)

	-- reset on respawn
	local conn2 = player.CharacterAdded:Connect(function()
		self._sprinting = false
		self._crouching = false
		self._stamina = STAMINA_MAX
		setSpeed(SPEEDS.walk)
	end)
	table.insert(self._connections, conn2)
end

function MovementController:stop()
	ContextActionService:UnbindAction("Sprint")
	ContextActionService:UnbindAction("Crouch")

	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._connections = {}
end

return MovementController
