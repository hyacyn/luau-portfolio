local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local AdminSystem = {}
AdminSystem.__index = AdminSystem

export type PermissionLevel = "mod" | "admin" | "owner"

local PERMISSION_WEIGHT: { [PermissionLevel]: number } = {
	mod = 1,
	admin = 2,
	owner = 3,
}

function AdminSystem.new(authorizedUsers: { [number]: PermissionLevel })
	local self = setmetatable({}, AdminSystem)
	self._authorized = authorizedUsers or {}
	self._commands = {}
	self._prefix = "!"
	self._logs = {}
	return self
end

function AdminSystem:getPermission(player: Player): PermissionLevel?
	return self._authorized[player.UserId]
end

local function hasPermission(self, player: Player, required: PermissionLevel): boolean
	local level = self._authorized[player.UserId]
	if not level then return false end
	return PERMISSION_WEIGHT[level] >= PERMISSION_WEIGHT[required]
end

-- find a player by partial name, nil if ambiguous or not found
local function resolvePlayer(query: string): Player?
	query = string.lower(query)
	local match = nil

	for _, player in Players:GetPlayers() do
		local name = string.lower(player.Name)
		local display = string.lower(player.DisplayName)

		if name == query or display == query then
			return player
		end

		if string.find(name, query, 1, true) or string.find(display, query, 1, true) then
			if match then return nil end -- ambiguous
			match = player
		end
	end

	return match
end

function AdminSystem:register(name: string, requiredLevel: PermissionLevel, callback: (Player, ...string) -> ())
	self._commands[string.lower(name)] = {
		level = requiredLevel,
		execute = callback,
	}
end

function AdminSystem:_log(admin: Player, commandName: string, args: { string })
	table.insert(self._logs, {
		admin = admin.Name,
		userId = admin.UserId,
		command = commandName,
		args = args,
		timestamp = os.time(),
	})

	-- keep it from bloating in long sessions
	if #self._logs > 500 then
		table.remove(self._logs, 1)
	end
end

function AdminSystem:_parse(message: string): (string?, { string })
	if string.sub(message, 1, #self._prefix) ~= self._prefix then
		return nil, {}
	end

	local stripped = string.sub(message, #self._prefix + 1)
	local parts = string.split(stripped, " ")
	local commandName = string.lower(table.remove(parts, 1) or "")

	return commandName, parts
end

function AdminSystem:_handleMessage(player: Player, message: string)
	local commandName, args = self:_parse(message)
	if not commandName then return end

	local command = self._commands[commandName]
	if not command then return end

	if not hasPermission(self, player, command.level) then
		warn(`[Admin] {player.Name} tried to use !{commandName} without permission`)
		return
	end

	local ok, err = pcall(command.execute, player, table.unpack(args))
	if not ok then
		warn(`[Admin] Error in !{commandName}: {err}`)
	end

	self:_log(player, commandName, args)
end

-- baseline commands
function AdminSystem:registerDefaults()
	self:register("kick", "mod", function(admin, targetName, ...: string)
		local target = resolvePlayer(targetName or "")
		if not target then return end

		local reason = table.concat({ ... }, " ")
		target:Kick(if #reason > 0 then reason else "Kicked by an administrator.")
	end)

	self:register("ban", "admin", function(admin, targetName, ...: string)
		local target = resolvePlayer(targetName or "")
		if not target then return end

		-- can hook into datastore
		target:Kick("You have been banned.")
	end)

	self:register("tp", "mod", function(admin, targetName)
		local target = resolvePlayer(targetName or "")
		if not target or not target.Character then return end
		if not admin.Character then return end

		local root = admin.Character:FindFirstChild("HumanoidRootPart")
		local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
		if root and targetRoot then
			root.CFrame = targetRoot.CFrame * CFrame.new(0, 0, -5)
		end
	end)

	self:register("bring", "mod", function(admin, targetName)
		local target = resolvePlayer(targetName or "")
		if not target or not target.Character then return end
		if not admin.Character then return end

		local root = admin.Character:FindFirstChild("HumanoidRootPart")
		local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
		if root and targetRoot then
			targetRoot.CFrame = root.CFrame * CFrame.new(0, 0, -5)
		end
	end)

	self:register("announce", "admin", function(_admin, ...: string)
		local text = table.concat({ ... }, " ")
		if #text == 0 then return end

		-- swap this for your own notification system
		for _, player in Players:GetPlayers() do
			player:FindFirstChild("PlayerGui") -- placeholder
		end
	end)
end

function AdminSystem:bind()
	-- hook into the legacy chat system as fallback
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			self:_handleMessage(player, message)
		end)
	end)
end

function AdminSystem:getLogs(): { {} }
	return self._logs
end

return AdminSystem
