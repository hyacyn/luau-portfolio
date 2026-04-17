local Players = game:GetService("Players")

local EconomyHandler = {}
EconomyHandler.__index = EconomyHandler

export type Currency = "credits" | "tokens"

local DEFAULT_WALLETS = {
	credits = 500,
	tokens = 0,
}

function EconomyHandler.new(dataManager)
	local self = setmetatable({}, EconomyHandler)
	self._dataManager = dataManager -- expects a DataStoreManager or similar
	self._transactions = {}
	return self
end

local function getWallet(self, player: Player): {}?
	local data = self._dataManager:get(player)
	if not data then return nil end

	-- init wallet if first time
	if not data.wallet then
		data.wallet = table.clone(DEFAULT_WALLETS)
	end

	return data.wallet
end

function EconomyHandler:getBalance(player: Player, currency: Currency): number
	local wallet = getWallet(self, player)
	if not wallet then return 0 end
	return wallet[currency] or 0
end

function EconomyHandler:add(player: Player, currency: Currency, amount: number): boolean
	if amount <= 0 then return false end

	local wallet = getWallet(self, player)
	if not wallet then return false end

	wallet[currency] = (wallet[currency] or 0) + amount
	self:_logTransaction(player, currency, amount, "add")
	return true
end

function EconomyHandler:remove(player: Player, currency: Currency, amount: number): boolean
	if amount <= 0 then return false end

	local wallet = getWallet(self, player)
	if not wallet then return false end

	local current = wallet[currency] or 0
	if current < amount then return false end

	wallet[currency] = current - amount
	self:_logTransaction(player, currency, -amount, "remove")
	return true
end

function EconomyHandler:canAfford(player: Player, currency: Currency, cost: number): boolean
	return self:getBalance(player, currency) >= cost
end

function EconomyHandler:transfer(from: Player, to: Player, currency: Currency, amount: number): boolean
	if amount <= 0 then return false end
	if not self:canAfford(from, currency, amount) then return false end

	-- do both or neither
	local wallet1 = getWallet(self, from)
	local wallet2 = getWallet(self, to)
	if not wallet1 or not wallet2 then return false end

	wallet1[currency] -= amount
	wallet2[currency] = (wallet2[currency] or 0) + amount

	self:_logTransaction(from, currency, -amount, "transfer_out", to.UserId)
	self:_logTransaction(to, currency, amount, "transfer_in", from.UserId)
	return true
end

function EconomyHandler:_logTransaction(player: Player, currency: Currency, amount: number, action: string, otherUserId: number?)
	table.insert(self._transactions, {
		userId = player.UserId,
		currency = currency,
		amount = amount,
		action = action,
		other = otherUserId,
		timestamp = os.time(),
	})

	if #self._transactions > 1000 then
		table.remove(self._transactions, 1)
	end
end

function EconomyHandler:getTransactions(player: Player): { {} }
	local filtered = {}
	for _, entry in self._transactions do
		if entry.userId == player.UserId then
			table.insert(filtered, entry)
		end
	end
	return filtered
end

return EconomyHandler
