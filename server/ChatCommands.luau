local Players = game:GetService("Players")

local ChatCommands = {}
ChatCommands.__index = ChatCommands

local PREFIX = "/"

function ChatCommands.new()
	local self = setmetatable({}, ChatCommands)
	self._commands = {}
	self._cooldowns = {} -- per player per command
	return self
end

export type CommandDef = {
	description: string,
	cooldown: number?, -- seconds, optional
	execute: (player: Player, args: { string }) -> (),
}

function ChatCommands:register(name: string, def: CommandDef)
	self._commands[string.lower(name)] = {
		description = def.description,
		cooldown = def.cooldown or 0,
		execute = def.execute,
	}
end

local function isOnCooldown(self, player: Player, commandName: string): boolean
	local key = `{player.UserId}_{commandName}`
	local last = self._cooldowns[key]
	if not last then return false end

	local command = self._commands[commandName]
	return (os.clock() - last) < (command.cooldown or 0)
end

local function setCooldown(self, player: Player, commandName: string)
	self._cooldowns[`{player.UserId}_{commandName}`] = os.clock()
end

function ChatCommands:_parse(message: string): (string?, { string })
	if string.sub(message, 1, #PREFIX) ~= PREFIX then
		return nil, {}
	end

	local parts = string.split(string.sub(message, #PREFIX + 1), " ")
	local name = string.lower(table.remove(parts, 1) or "")
	return name, parts
end

function ChatCommands:_handle(player: Player, message: string)
	local name, args = self:_parse(message)
	if not name or not self._commands[name] then return end

	if isOnCooldown(self, player, name) then return end

	local command = self._commands[name]
	local ok, err = pcall(command.execute, player, args)
	if not ok then
		warn(`[ChatCommands] /{name} errored: {err}`)
	end

	setCooldown(self, player, name)
end

-- some basic commands most games would have
function ChatCommands:registerDefaults()
	self:register("help", {
		description = "Lists available commands.",
		execute = function(player, _args)
			local lines = {}
			for name, cmd in self._commands do
				table.insert(lines, `/{name} — {cmd.description}`)
			end
			table.sort(lines)
			-- wire this into your chat or notification system
			print(table.concat(lines, "\n"))
		end,
	})

	self:register("playtime", {
		description = "Shows your session playtime.",
		cooldown = 5,
		execute = function(player, _args)
			-- os.clock gives uptime, not join time — you'd
			-- track actual join time somewhere in practice
			local minutes = math.floor(os.clock() / 60)
			print(`{player.Name} has been playing for {minutes}m`)
		end,
	})

	self:register("dice", {
		description = "Rolls a dice. /dice or /dice 20",
		cooldown = 3,
		execute = function(player, args)
			local sides = tonumber(args[1]) or 6
			sides = math.clamp(sides, 2, 100)
			local result = math.random(1, sides)
			print(`{player.DisplayName} rolled a {result} (d{sides})`)
		end,
	})
end

function ChatCommands:bind()
	Players.PlayerAdded:Connect(function(player)
		player.Chatted:Connect(function(message)
			self:_handle(player, message)
		end)
	end)

	-- clean up cooldowns when players leave
	Players.PlayerRemoving:Connect(function(player)
		for key in self._cooldowns do
			if string.find(key, tostring(player.UserId), 1, true) then
				self._cooldowns[key] = nil
			end
		end
	end)
end

return ChatCommands
