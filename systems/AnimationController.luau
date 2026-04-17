local ContentProvider = game:GetService("ContentProvider")

local AnimationController = {}
AnimationController.__index = AnimationController

export type AnimPriority = "idle" | "movement" | "action" | "override"

local PRIORITY_WEIGHT: { [AnimPriority]: number } = {
	idle = 0,
	movement = 1,
	action = 2,
	override = 3,
}

function AnimationController.new(humanoid: Humanoid)
	local self = setmetatable({}, AnimationController)
	self._humanoid = humanoid
	self._animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	self._loaded = {} :: { [string]: AnimationTrack }
	self._active = {} :: { [string]: boolean }
	self._priorities = {} :: { [string]: AnimPriority }
	return self
end

function AnimationController:load(id: string, assetId: string, priority: AnimPriority?): AnimationTrack
	if self._loaded[id] then
		return self._loaded[id]
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local track = self._animator:LoadAnimation(anim)
	self._loaded[id] = track
	self._priorities[id] = priority or "movement"
	anim:Destroy() -- don't need the instance anymore

	return track
end

function AnimationController:play(id: string, fadeTime: number?, weight: number?, speed: number?)
	local track = self._loaded[id]
	if not track then return end

	-- stop anything at the same or lower priority
	local incoming = PRIORITY_WEIGHT[self._priorities[id] or "movement"]

	for otherId, isPlaying in self._active do
		if not isPlaying then continue end
		if otherId == id then continue end

		local otherWeight = PRIORITY_WEIGHT[self._priorities[otherId] or "movement"]
		if otherWeight <= incoming then
			self:stop(otherId, fadeTime)
		end
	end

	track:Play(fadeTime or 0.2, weight or 1, speed or 1)
	self._active[id] = true

	-- auto-clear when it finishes (for non-looping anims)
	if not track.Looped then
		track.Stopped:Once(function()
			self._active[id] = false
		end)
	end
end

function AnimationController:stop(id: string, fadeTime: number?)
	local track = self._loaded[id]
	if not track then return end

	track:Stop(fadeTime or 0.2)
	self._active[id] = false
end

function AnimationController:isPlaying(id: string): boolean
	return self._active[id] or false
end

function AnimationController:setSpeed(id: string, speed: number)
	local track = self._loaded[id]
	if track then
		track:AdjustSpeed(speed)
	end
end

function AnimationController:setWeight(id: string, weight: number)
	local track = self._loaded[id]
	if track then
		track:AdjustWeight(weight)
	end
end

function AnimationController:getTrack(id: string): AnimationTrack?
	return self._loaded[id]
end

function AnimationController:stopAll(fadeTime: number?)
	for id in self._active do
		self:stop(id, fadeTime)
	end
end

-- preload animations so they don't hitch on first play
function AnimationController:preload(ids: { string })
	local tracks = {}
	for _, id in ids do
		if self._loaded[id] then
			table.insert(tracks, self._loaded[id])
		end
	end

	-- kind of a hack but it works
	local anims = {}
	for _, track in tracks do
		local a = Instance.new("Animation")
		a.AnimationId = track.Animation.AnimationId
		table.insert(anims, a)
	end

	ContentProvider:PreloadAsync(anims)

	for _, a in anims do
		a:Destroy()
	end
end

function AnimationController:destroy()
	self:stopAll(0)
	self._loaded = {}
	self._active = {}
	self._priorities = {}
end

return AnimationController
