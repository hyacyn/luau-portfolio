local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local VehicleSystem = {}
VehicleSystem.__index = VehicleSystem

export type SeatRole = "driver" | "passenger"

export type VehicleConfig = {
	maxSpeed: number,
	acceleration: number,
	brakeForce: number,
	turnSpeed: number,
	seats: { [string]: SeatRole },
}

local DEFAULT_CONFIG: VehicleConfig = {
	maxSpeed = 80,
	acceleration = 25,
	brakeForce = 40,
	turnSpeed = 3,
	seats = {},
}

function VehicleSystem.new(model: Model, config: VehicleConfig?)
	local self = setmetatable({}, VehicleSystem)
	self._model = model
	self._config = config or DEFAULT_CONFIG
	self._occupants = {} :: { [BasePart]: Player }
	self._driver = nil :: Player?
	self._speed = 0
	self._active = false
	self._connections = {}
	self._bodyVelocity = nil :: BodyVelocity?
	self._bodyGyro = nil :: BodyGyro?
	return self
end

function VehicleSystem:getDriver(): Player?
	return self._driver
end

function VehicleSystem:getSpeed(): number
	return self._speed
end

function VehicleSystem:getOccupants(): { Player }
	local list = {}
	for _, player in self._occupants do
		table.insert(list, player)
	end
	return list
end

function VehicleSystem:_setupForces()
	local root = self._model.PrimaryPart
	if not root then return end

	if not self._bodyVelocity then
		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(math.huge, 0, math.huge)
		bv.Velocity = Vector3.zero
		bv.Parent = root
		self._bodyVelocity = bv
	end

	if not self._bodyGyro then
		local bg = Instance.new("BodyGyro")
		bg.MaxTorque = Vector3.new(0, math.huge, 0)
		bg.D = 100
		bg.P = 2000
		bg.CFrame = root.CFrame
		bg.Parent = root
		self._bodyGyro = bg
	end
end

function VehicleSystem:_cleanupForces()
	if self._bodyVelocity then
		self._bodyVelocity:Destroy()
		self._bodyVelocity = nil
	end
	if self._bodyGyro then
		self._bodyGyro:Destroy()
		self._bodyGyro = nil
	end
end

function VehicleSystem:_bindSeats()
	for _, descendant in self._model:GetDescendants() do
		if not descendant:IsA("VehicleSeat") and not descendant:IsA("Seat") then
			continue
		end

		local conn = descendant:GetPropertyChangedSignal("Occupant"):Connect(function()
			self:_onSeatChanged(descendant)
		end)
		table.insert(self._connections, conn)
	end
end

function VehicleSystem:_onSeatChanged(seat: BasePart)
	local humanoid = seat.Occupant
	if humanoid then
		local player = Players:GetPlayerFromCharacter(humanoid.Parent)
		if not player then return end

		self._occupants[seat] = player

		local role = self._config.seats[seat.Name] or "passenger"
		if role == "driver" or seat:IsA("VehicleSeat") then
			self._driver = player
			self:_setupForces()
		end
	else
		local wasDriver = self._occupants[seat] == self._driver
		self._occupants[seat] = nil

		if wasDriver then
			self._driver = nil
			self._speed = 0
			self:_cleanupForces()
		end
	end
end

function VehicleSystem:_updatePhysics(dt: number, throttle: number, steer: number)
	local root = self._model.PrimaryPart
	if not root or not self._bodyVelocity or not self._bodyGyro then return end

	local config = self._config

	if throttle > 0 then
		self._speed = math.min(config.maxSpeed, self._speed + config.acceleration * dt)
	elseif throttle < 0 then
		self._speed = math.max(-config.maxSpeed * 0.4, self._speed - config.brakeForce * dt)
	else
		-- natural deceleration
		local decel = config.brakeForce * 0.3 * dt
		if self._speed > 0 then
			self._speed = math.max(0, self._speed - decel)
		elseif self._speed < 0 then
			self._speed = math.min(0, self._speed + decel)
		end
	end

	-- only turn when moving
	if math.abs(self._speed) > 1 and math.abs(steer) > 0 then
		local turnAmount = steer * config.turnSpeed * dt * (self._speed / config.maxSpeed)
		self._bodyGyro.CFrame *= CFrame.Angles(0, -turnAmount, 0)
	end

	local forward = root.CFrame.LookVector
	self._bodyVelocity.Velocity = forward * self._speed
end

function VehicleSystem:start()
	if self._active then return end
	self._active = true

	self:_bindSeats()

	-- physics update reads from the VehicleSeat inputs
	local conn = RunService.Heartbeat:Connect(function(dt)
		if not self._driver then return end

		local driverSeat = nil
		for seat, player in self._occupants do
			if player == self._driver and seat:IsA("VehicleSeat") then
				driverSeat = seat
				break
			end
		end

		if not driverSeat then return end

		self:_updatePhysics(dt, driverSeat.ThrottleFloat, driverSeat.SteerFloat)
	end)
	table.insert(self._connections, conn)
end

function VehicleSystem:stop()
	self._active = false
	self._speed = 0
	self:_cleanupForces()

	for _, conn in self._connections do
		conn:Disconnect()
	end
	self._connections = {}
	self._occupants = {}
	self._driver = nil
end

return VehicleSystem
