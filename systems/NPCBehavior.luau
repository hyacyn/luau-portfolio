local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local NPCBehavior = {}
NPCBehavior.__index = NPCBehavior

export type AIState = "idle" | "patrol" | "chase" | "attack" | "flee" | "interact"

local DETECTION_RANGE = 50
local ATTACK_RANGE = 6
local FLEE_HEALTH_THRESHOLD = 0.2
local PATH_RECOMPUTE_INTERVAL = 0.5

function NPCBehavior.new(model: Model, config: {}?)
	local self = setmetatable({}, NPCBehavior)
	self._model = model
	self._humanoid = model:FindFirstChildOfClass("Humanoid")
	self._rootPart = model:FindFirstChild("HumanoidRootPart")
	self._state = "idle" :: AIState
	self._target = nil :: Model?
	self._patrolPoints = {} :: { Vector3 }
	self._patrolIndex = 1
	self._active = false
	self._config = config or {}
	self._detectionRange = self._config.detectionRange or DETECTION_RANGE
	self._attackRange = self._config.attackRange or ATTACK_RANGE
	self._onStateChanged = Instance.new("BindableEvent")
	return self
end

function NPCBehavior:onStateChanged(callback: (AIState, AIState) -> ())
	return self._onStateChanged.Event:Connect(callback)
end

function NPCBehavior:setState(state: AIState)
	if self._state == state then return end
	local prev = self._state
	self._state = state
	self._onStateChanged:Fire(state, prev)
end

function NPCBehavior:getState(): AIState
	return self._state
end

function NPCBehavior:setPatrolPoints(points: { Vector3 })
	self._patrolPoints = points
	self._patrolIndex = 1
end

local function distanceTo(rootPart: BasePart, position: Vector3): number
	return (rootPart.Position - position).Magnitude
end

local function findNearestPlayer(rootPart: BasePart, range: number): Model?
	local nearest = nil
	local nearestDist = range

	for _, player in Players:GetPlayers() do
		local char = player.Character
		if not char then continue end

		local targetRoot = char:FindFirstChild("HumanoidRootPart")
		local humanoid = char:FindFirstChild("Humanoid")
		if not targetRoot or not humanoid or humanoid.Health <= 0 then continue end

		local dist = distanceTo(rootPart, targetRoot.Position)
		if dist < nearestDist then
			nearest = char
			nearestDist = dist
		end
	end

	return nearest
end

function NPCBehavior:_moveTo(position: Vector3)
	if not self._humanoid then return end

	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = true,
	})

	local ok, err = pcall(function()
		path:ComputeAsync(self._rootPart.Position, position)
	end)

	if not ok or path.Status ~= Enum.PathStatus.Success then
		-- fallback to direct move if pathfinding fails
		self._humanoid:MoveTo(position)
		return
	end

	for _, waypoint in path:GetWaypoints() do
		if not self._active then return end

		self._humanoid:MoveTo(waypoint.Position)
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			self._humanoid.Jump = true
		end

		self._humanoid.MoveToFinished:Wait()
	end
end

function NPCBehavior:_tickIdle()
	if #self._patrolPoints > 0 then
		self:setState("patrol")
		return
	end

	local player = findNearestPlayer(self._rootPart, self._detectionRange)
	if player then
		self._target = player
		self:setState("chase")
	end
end

function NPCBehavior:_tickPatrol()
	local player = findNearestPlayer(self._rootPart, self._detectionRange)
	if player then
		self._target = player
		self:setState("chase")
		return
	end

	local point = self._patrolPoints[self._patrolIndex]
	if not point then return end

	if distanceTo(self._rootPart, point) < 4 then
		self._patrolIndex = self._patrolIndex % #self._patrolPoints + 1
		task.wait(1.5) -- brief pause at each point
		return
	end

	self:_moveTo(point)
end

function NPCBehavior:_tickChase()
	if not self._target then
		self:setState("idle")
		return
	end

	local targetRoot = self._target:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = self._target:FindFirstChild("Humanoid")

	if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 then
		self._target = nil
		self:setState("idle")
		return
	end

	local dist = distanceTo(self._rootPart, targetRoot.Position)

	-- lost them
	if dist > self._detectionRange * 1.5 then
		self._target = nil
		self:setState("idle")
		return
	end

	-- check if we should flee
	if self._humanoid and self._humanoid.Health / self._humanoid.MaxHealth <= FLEE_HEALTH_THRESHOLD then
		self:setState("flee")
		return
	end

	if dist <= self._attackRange then
		self:setState("attack")
		return
	end

	self._humanoid:MoveTo(targetRoot.Position)
end

function NPCBehavior:_tickAttack()
	if not self._target then
		self:setState("idle")
		return
	end

	local targetRoot = self._target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self._target = nil
		self:setState("idle")
		return
	end

	local dist = distanceTo(self._rootPart, targetRoot.Position)
	if dist > self._attackRange * 1.5 then
		self:setState("chase")
		return
	end

	-- face the target
	if self._rootPart then
		self._rootPart.CFrame = CFrame.lookAt(self._rootPart.Position, Vector3.new(
			targetRoot.Position.X,
			self._rootPart.Position.Y,
			targetRoot.Position.Z
		))
	end

	-- hook your damage logic here
	task.wait(0.8)
end

function NPCBehavior:_tickFlee()
	if not self._target or not self._rootPart then
		self:setState("idle")
		return
	end

	local targetRoot = self._target:FindFirstChild("HumanoidRootPart")
	if not targetRoot then
		self:setState("idle")
		return
	end

	-- run opposite direction from threat
	local fleeDir = (self._rootPart.Position - targetRoot.Position).Unit
	local fleePos = self._rootPart.Position + fleeDir * 30

	self._humanoid:MoveTo(fleePos)
	task.wait(1)

	local dist = distanceTo(self._rootPart, targetRoot.Position)
	if dist > self._detectionRange then
		self._target = nil
		self:setState("idle")
	end
end

local STATE_HANDLERS = {
	idle = NPCBehavior._tickIdle,
	patrol = NPCBehavior._tickPatrol,
	chase = NPCBehavior._tickChase,
	attack = NPCBehavior._tickAttack,
	flee = NPCBehavior._tickFlee,
}

function NPCBehavior:start()
	if self._active then return end
	self._active = true

	task.spawn(function()
		while self._active do
			local handler = STATE_HANDLERS[self._state]
			if handler then
				handler(self)
			end
			task.wait(PATH_RECOMPUTE_INTERVAL)
		end
	end)
end

function NPCBehavior:stop()
	self._active = false
	self._target = nil
	self:setState("idle")
end

return NPCBehavior
