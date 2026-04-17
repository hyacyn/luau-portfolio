local InventorySystem = {}
InventorySystem.__index = InventorySystem

export type Item = {
	id: string,
	name: string,
	quantity: number,
	metadata: {}?,
}

local MAX_SLOTS = 30

function InventorySystem.new(maxSlots: number?)
	local self = setmetatable({}, InventorySystem)
	self._items = {} :: { [string]: Item }
	self._maxSlots = maxSlots or MAX_SLOTS
	self._onChanged = Instance.new("BindableEvent")
	return self
end

function InventorySystem:onChanged(callback: (action: string, item: Item) -> ())
	return self._onChanged.Event:Connect(callback)
end

function InventorySystem:getSlotCount(): number
	local count = 0
	for _ in self._items do
		count += 1
	end
	return count
end

function InventorySystem:isFull(): boolean
	return self:getSlotCount() >= self._maxSlots
end

function InventorySystem:add(id: string, name: string, quantity: number?, metadata: {}?): boolean
	local amount = quantity or 1

	if self._items[id] then
		self._items[id].quantity += amount
	else
		if self:isFull() then return false end

		self._items[id] = {
			id = id,
			name = name,
			quantity = amount,
			metadata = metadata,
		}
	end

	self._onChanged:Fire("add", self._items[id])
	return true
end

function InventorySystem:remove(id: string, quantity: number?): boolean
	local item = self._items[id]
	if not item then return false end

	local amount = quantity or 1
	if item.quantity < amount then return false end

	item.quantity -= amount
	if item.quantity <= 0 then
		self._items[id] = nil
	end

	self._onChanged:Fire("remove", { id = id, name = item.name, quantity = amount })
	return true
end

function InventorySystem:has(id: string, quantity: number?): boolean
	local item = self._items[id]
	if not item then return false end
	return item.quantity >= (quantity or 1)
end

function InventorySystem:get(id: string): Item?
	return self._items[id]
end

function InventorySystem:getAll(): { Item }
	local list = {}
	for _, item in self._items do
		table.insert(list, item)
	end
	return list
end

function InventorySystem:clear()
	self._items = {}
	self._onChanged:Fire("clear", {} :: any)
end

-- for saving/loading with a datastore
function InventorySystem:serialize(): { {} }
	local data = {}
	for id, item in self._items do
		table.insert(data, {
			id = item.id,
			name = item.name,
			quantity = item.quantity,
			metadata = item.metadata,
		})
	end
	return data
end

function InventorySystem:deserialize(data: { {} })
	self._items = {}
	for _, entry in data do
		self._items[entry.id] = {
			id = entry.id,
			name = entry.name,
			quantity = entry.quantity or 1,
			metadata = entry.metadata,
		}
	end
end

-- move items between two inventories
function InventorySystem:transferTo(other: any, itemId: string, quantity: number?): boolean
	local amount = quantity or 1
	if not self:has(itemId, amount) then return false end

	local item = self._items[itemId]
	if not other:add(itemId, item.name, amount, item.metadata) then
		return false
	end

	self:remove(itemId, amount)
	return true
end

return InventorySystem
