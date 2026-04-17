local DialogSystem = {}
DialogSystem.__index = DialogSystem

export type DialogNode = {
	id: string,
	speaker: string,
	text: string,
	responses: { ResponseOption }?,
	onEnter: (() -> ())?,
	next: string?, -- auto-advance to this node if no responses
}

export type ResponseOption = {
	text: string,
	nextNode: string?,
	condition: (() -> boolean)?,
	onSelect: (() -> ())?,
}

function DialogSystem.new()
	local self = setmetatable({}, DialogSystem)
	self._trees = {} :: { [string]: { [string]: DialogNode } }
	self._activeDialog = nil :: string?
	self._currentNode = nil :: string?
	self._onNodeChanged = Instance.new("BindableEvent")
	self._onDialogEnd = Instance.new("BindableEvent")
	return self
end

function DialogSystem:onNodeChanged(callback: (node: DialogNode) -> ())
	return self._onNodeChanged.Event:Connect(callback)
end

function DialogSystem:onDialogEnd(callback: (treeId: string) -> ())
	return self._onDialogEnd.Event:Connect(callback)
end

function DialogSystem:registerTree(treeId: string, nodes: { DialogNode })
	local nodeMap = {}
	for _, node in nodes do
		nodeMap[node.id] = node
	end
	self._trees[treeId] = nodeMap
end

function DialogSystem:start(treeId: string, startNode: string?)
	local tree = self._trees[treeId]
	if not tree then
		warn(`[Dialog] Tree "{treeId}" not found`)
		return
	end

	self._activeDialog = treeId
	local entryId = startNode or "start"

	if not tree[entryId] then
		warn(`[Dialog] Node "{entryId}" not found in tree "{treeId}"`)
		return
	end

	self:_goToNode(entryId)
end

function DialogSystem:_goToNode(nodeId: string)
	local tree = self._trees[self._activeDialog]
	if not tree then return end

	local node = tree[nodeId]
	if not node then
		self:stop()
		return
	end

	self._currentNode = nodeId

	if node.onEnter then
		node.onEnter()
	end

	self._onNodeChanged:Fire(node)
end

function DialogSystem:getCurrentNode(): DialogNode?
	if not self._activeDialog or not self._currentNode then return nil end

	local tree = self._trees[self._activeDialog]
	return if tree then tree[self._currentNode] else nil
end

-- get only the responses whose conditions pass
function DialogSystem:getAvailableResponses(): { ResponseOption }
	local node = self:getCurrentNode()
	if not node or not node.responses then return {} end

	local available = {}
	for _, response in node.responses do
		if not response.condition or response.condition() then
			table.insert(available, response)
		end
	end
	return available
end

function DialogSystem:selectResponse(index: number)
	local available = self:getAvailableResponses()
	local response = available[index]
	if not response then return end

	if response.onSelect then
		response.onSelect()
	end

	if response.nextNode then
		self:_goToNode(response.nextNode)
	else
		self:stop()
	end
end

-- for nodes with no responses that just advance automatically
function DialogSystem:advance()
	local node = self:getCurrentNode()
	if not node then return end

	if node.next then
		self:_goToNode(node.next)
	else
		self:stop()
	end
end

function DialogSystem:stop()
	local treeId = self._activeDialog
	self._activeDialog = nil
	self._currentNode = nil

	if treeId then
		self._onDialogEnd:Fire(treeId)
	end
end

function DialogSystem:isActive(): boolean
	return self._activeDialog ~= nil
end

return DialogSystem
