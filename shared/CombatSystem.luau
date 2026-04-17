local RunService = game:GetService("RunService")

local CombatSystem = {}
CombatSystem.__index = CombatSystem

export type DamageType = "melee" | "ranged" | "explosive" | "environmental"

export type DamageInfo = {
	amount: number,
	damageType: DamageType,
	source: Player?,
	origin: Vector3?,
	knockback: number?,
}

export type CombatEntity = {
	health: number,
	maxHealth: number,
	armor: number,
	lastDamageInfo: DamageInfo?,
}

local ARMOR_REDUCTION = 0.5 -- each point of armor reduces damage by this %... capped though

function CombatSystem.new()
	local self = setmetatable({}, CombatSystem)
	self._entities = {} :: { [Model]: CombatEntity }
	self._onDamage = Instance.new("BindableEvent")
	self._onDeath = Instance.new("BindableEvent")
	return self
end

function CombatSystem:onDamage(callback: (target: Model, info: DamageInfo) -> ())
	return self._onDamage.Event:Connect(callback)
end

function CombatSystem:onDeath(callback: (target: Model, info: DamageInfo) -> ())
	return self._onDeath.Event:Connect(callback)
end

function CombatSystem:register(model: Model, maxHealth: number?, armor: number?)
	self._entities[model] = {
		health = maxHealth or 100,
		maxHealth = maxHealth or 100,
		armor = armor or 0,
		lastDamageInfo = nil,
	}
end

function CombatSystem:unregister(model: Model)
	self._entities[model] = nil
end

function CombatSystem:getEntity(model: Model): CombatEntity?
	return self._entities[model]
end

function CombatSystem:isAlive(model: Model): boolean
	local entity = self._entities[model]
	return entity ~= nil and entity.health > 0
end

local function calculateDamage(raw: number, armor: number): number
	local reduction = math.clamp(armor * ARMOR_REDUCTION, 0, 80) / 100
	return math.floor(raw * (1 - reduction))
end

function CombatSystem:damage(model: Model, info: DamageInfo)
	local entity = self._entities[model]
	if not entity or entity.health <= 0 then return end

	local finalDamage = calculateDamage(info.amount, entity.armor)
	entity.health = math.max(0, entity.health - finalDamage)
	entity.lastDamageInfo = info

	self._onDamage:Fire(model, info)

	-- apply knockback if the model has a root part
	if info.knockback and info.knockback > 0 and info.origin then
		local root = model:FindFirstChild("HumanoidRootPart")
		if root then
			local dir = (root.Position - info.origin).Unit
			root:ApplyImpulse(dir * info.knockback)
		end
	end

	if entity.health <= 0 then
		self._onDeath:Fire(model, info)
		self:_handleDeath(model)
	end
end

function CombatSystem:heal(model: Model, amount: number)
	local entity = self._entities[model]
	if not entity or entity.health <= 0 then return end

	entity.health = math.min(entity.maxHealth, entity.health + amount)
end

function CombatSystem:setArmor(model: Model, armor: number)
	local entity = self._entities[model]
	if not entity then return end
	entity.armor = math.max(0, armor)
end

function CombatSystem:_handleDeath(model: Model)
	local humanoid = model:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Health = 0
	end
end

-- basic raycast hit detection, returns the model hit if valid
function CombatSystem:raycast(origin: Vector3, direction: Vector3, ignoreList: { Instance }?): (Model?, Vector3?)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}

	local result = workspace:Raycast(origin, direction, params)
	if not result or not result.Instance then return nil, nil end

	-- walk up to find the character model
	local target = result.Instance
	while target and not self._entities[target] do
		target = target.Parent
		if target == workspace then return nil, result.Position end
	end

	return target, result.Position
end

return CombatSystem
