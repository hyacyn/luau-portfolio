local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UIFramework = {}
UIFramework.__index = UIFramework

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

export type ScreenId = string

local FADE_TIME = 0.25
local FADE_INFO = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function UIFramework.new()
	local self = setmetatable({}, UIFramework)
	self._screens = {} :: { [ScreenId]: ScreenGui }
	self._active = {} :: { [ScreenId]: boolean }
	self._stack = {} :: { ScreenId } -- for layered menus
	return self
end

function UIFramework:register(id: ScreenId, screenGui: ScreenGui)
	self._screens[id] = screenGui
	self._active[id] = false

	-- hide by default
	local root = self:_getRoot(screenGui)
	if root then
		root.Visible = false
	end
end

-- expects the first Frame/CanvasGroup child as the main container
function UIFramework:_getRoot(screenGui: ScreenGui): GuiObject?
	for _, child in screenGui:GetChildren() do
		if child:IsA("GuiObject") then
			return child
		end
	end
	return nil
end

function UIFramework:show(id: ScreenId, instant: boolean?)
	local gui = self._screens[id]
	if not gui then return end

	local root = self:_getRoot(gui)
	if not root then return end

	gui.Enabled = true
	root.Visible = true
	self._active[id] = true

	if instant then
		if root:IsA("CanvasGroup") then
			root.GroupTransparency = 0
		end
		return
	end

	if root:IsA("CanvasGroup") then
		root.GroupTransparency = 1
		TweenService:Create(root, FADE_INFO, { GroupTransparency = 0 }):Play()
	end
end

function UIFramework:hide(id: ScreenId, instant: boolean?)
	local gui = self._screens[id]
	if not gui then return end

	local root = self:_getRoot(gui)
	if not root then return end

	self._active[id] = false

	if instant then
		root.Visible = false
		gui.Enabled = false
		return
	end

	if root:IsA("CanvasGroup") then
		local tween = TweenService:Create(root, FADE_INFO, { GroupTransparency = 1 })
		tween:Play()
		tween.Completed:Once(function()
			if not self._active[id] then
				root.Visible = false
				gui.Enabled = false
			end
		end)
	else
		root.Visible = false
		gui.Enabled = false
	end
end

function UIFramework:toggle(id: ScreenId)
	if self._active[id] then
		self:hide(id)
	else
		self:show(id)
	end
end

function UIFramework:isActive(id: ScreenId): boolean
	return self._active[id] or false
end

-- stack-based navigation for menus that layer on top of each other
function UIFramework:push(id: ScreenId)
	table.insert(self._stack, id)
	self:show(id)
end

function UIFramework:pop()
	local top = table.remove(self._stack)
	if top then
		self:hide(top)
	end

	-- show whatever's underneath
	local next = self._stack[#self._stack]
	if next then
		self:show(next)
	end
end

function UIFramework:popAll()
	while #self._stack > 0 do
		self:pop()
	end
end

function UIFramework:hideAll()
	for id in self._screens do
		self:hide(id, true)
	end
	self._stack = {}
end

return UIFramework
