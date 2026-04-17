local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local SoundManager = {}
SoundManager.__index = SoundManager

function SoundManager.new()
	local self = setmetatable({}, SoundManager)
	self._groups = {} :: { [string]: SoundGroup }
	self._playing = {} :: { [string]: Sound }
	self._volumes = { master = 1, sfx = 1, music = 0.5, ambient = 0.6 }
	self._currentMusic = nil :: Sound?
	return self
end

function SoundManager:_getOrCreateGroup(name: string): SoundGroup
	if self._groups[name] then
		return self._groups[name]
	end

	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Volume = self._volumes[name] or 1
	group.Parent = SoundService
	self._groups[name] = group
	return group
end

function SoundManager:setVolume(groupName: string, volume: number)
	self._volumes[groupName] = math.clamp(volume, 0, 1)

	local group = self._groups[groupName]
	if group then
		group.Volume = self._volumes[groupName]
	end
end

function SoundManager:getVolume(groupName: string): number
	return self._volumes[groupName] or 1
end

function SoundManager:play(id: string, assetId: string, groupName: string?): Sound
	-- reuse if already exists
	if self._playing[id] and self._playing[id].Parent then
		self._playing[id]:Play()
		return self._playing[id]
	end

	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.SoundGroup = self:_getOrCreateGroup(groupName or "sfx")
	sound.Parent = SoundService

	sound.Ended:Once(function()
		sound:Destroy()
		if self._playing[id] == sound then
			self._playing[id] = nil
		end
	end)

	sound:Play()
	self._playing[id] = sound
	return sound
end

function SoundManager:playMusic(assetId: string, fadeIn: number?)
	-- crossfade from current track
	if self._currentMusic then
		self:_fadeOut(self._currentMusic, fadeIn or 1)
	end

	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = self:_getOrCreateGroup("music")
	sound.Parent = SoundService
	sound:Play()

	local targetVol = self._volumes.music or 0.5
	local duration = fadeIn or 1

	TweenService:Create(sound, TweenInfo.new(duration), { Volume = targetVol }):Play()

	self._currentMusic = sound
end

function SoundManager:stopMusic(fadeOut: number?)
	if not self._currentMusic then return end
	self:_fadeOut(self._currentMusic, fadeOut or 1)
	self._currentMusic = nil
end

function SoundManager:_fadeOut(sound: Sound, duration: number)
	local tween = TweenService:Create(sound, TweenInfo.new(duration), { Volume = 0 })
	tween:Play()
	tween.Completed:Once(function()
		sound:Stop()
		sound:Destroy()
	end)
end

-- fire-and-forget for one-shot sfx
function SoundManager:playSFX(assetId: string)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.SoundGroup = self:_getOrCreateGroup("sfx")
	sound.Parent = SoundService
	sound:Play()

	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

-- preload a list of asset ids so they don't hitch on first play
function SoundManager:preload(assetIds: { string })
	local assets = {}
	for _, id in assetIds do
		local sound = Instance.new("Sound")
		sound.SoundId = id
		table.insert(assets, sound)
	end

	ContentProvider:PreloadAsync(assets)

	for _, sound in assets do
		sound:Destroy()
	end
end

function SoundManager:stopAll()
	for id, sound in self._playing do
		sound:Stop()
		sound:Destroy()
		self._playing[id] = nil
	end

	if self._currentMusic then
		self._currentMusic:Stop()
		self._currentMusic:Destroy()
		self._currentMusic = nil
	end
end

return SoundManager
