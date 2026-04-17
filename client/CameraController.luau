local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local CameraController = {}
CameraController.__index = CameraController

export type CameraMode = "default" | "fixed" | "freecam" | "follow"

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

function CameraController.new()
	local self = setmetatable({}, CameraController)
	self._mode = "default" :: CameraMode
	self._target = nil :: BasePart?
	self._offset = Vector3.new(0, 5, -12)
	self._fov = 70
	self._locked = false
	self._shakeIntensity = 0
	self._renderConn = nil
	return self
end

function CameraController:setMode(mode: CameraMode)
	self._mode = mode

	if mode == "default" then
		camera.CameraType = Enum.CameraType.Custom
	else
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

function CameraController:setTarget(part: BasePart?)
	self._target = part
end

function CameraController:setOffset(offset: Vector3)
	self._offset = offset
end

function CameraController:setFOV(fov: number, tweenTime: number?)
	if tweenTime and tweenTime > 0 then
		local tween = TweenService:Create(camera, TweenInfo.new(tweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = fov,
		})
		tween:Play()
	else
		camera.FieldOfView = fov
	end
	self._fov = fov
end

function CameraController:shake(intensity: number, duration: number)
	self._shakeIntensity = intensity

	task.delay(duration, function()
		self._shakeIntensity = 0
	end)
end

local function getShakeOffset(intensity: number): Vector3
	if intensity <= 0 then return Vector3.zero end

	return Vector3.new(
		math.random() * intensity * 2 - intensity,
		math.random() * intensity * 2 - intensity,
		0
	)
end

function CameraController:lock()
	self._locked = true
end

function CameraController:unlock()
	self._locked = false
end

function CameraController:_update(_dt: number)
	if self._mode == "default" then return end
	if self._locked then return end

	local targetPart = self._target
	if not targetPart then
		local char = player.Character
		if not char then return end
		targetPart = char:FindFirstChild("HumanoidRootPart")
		if not targetPart then return end
	end

	local targetPos = targetPart.Position
	local shake = getShakeOffset(self._shakeIntensity)

	if self._mode == "follow" then
		local goalCF = CFrame.new(targetPos + self._offset, targetPos)
		camera.CFrame = camera.CFrame:Lerp(goalCF, 0.15) + shake
	elseif self._mode == "fixed" then
		camera.CFrame = CFrame.new(camera.CFrame.Position + shake, targetPos)
	end
end

function CameraController:start()
	if self._renderConn then return end

	self._renderConn = RunService.RenderStepped:Connect(function(dt)
		self:_update(dt)
	end)
end

function CameraController:stop()
	if self._renderConn then
		self._renderConn:Disconnect()
		self._renderConn = nil
	end
	self:setMode("default")
end

return CameraController
