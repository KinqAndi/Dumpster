local Dumpster = {}
Dumpster.__index = Dumpster

local RunService = game:GetService('RunService')

--Constructor for Dumpster 
function Dumpster.new()
	local self = setmetatable({
		_dictionaryInstances = {},
		_dictionaryFunctions = {},
		_instances = {},
		_functions = {},
		_subDumpsters = {},
		_bindNames = {},
	}, Dumpster)

	return self
end

--Extends the class into a subclass, gets cleaned up on super:Destroy()
function Dumpster:Extend()
	local subDumpster = self.new()
	table.insert(self._subDumpsters, subDumpster)
	return subDumpster
end

--Add an object to the dumpster
function Dumpster:Add(object: any, cleanUpIdentifier: string?): ()
	assert(object ~= nil, "Object passed for cleanup was nil!")

	if cleanUpIdentifier and typeof(cleanUpIdentifier) ~= "string" then
		self:_sendError("Cleanup identifier must be a string!")
		return
	end

	if typeof(object) == "function" then
		if cleanUpIdentifier then
			if self._dictionaryFunctions[cleanUpIdentifier] then
				warn("A function with ID", cleanUpIdentifier, "already exists!")
				return
			end

			self._dictionaryFunctions[cleanUpIdentifier] = object
			return
		end

		table.insert(self._functions, object)
		return
	end

	if cleanUpIdentifier then
		if self._dictionaryInstances[cleanUpIdentifier] then
			warn("A cleanup method with ID", cleanUpIdentifier, "already exists!")
			return
		end

		self._dictionaryInstances[cleanUpIdentifier] = object
	end

	table.insert(self._instances, object)
end

--Connect method to dumpster
function Dumpster:Connect(signal: RBXScriptSignal, funcCallback: ()->()): ()
	if not signal or not funcCallback then
		self:_sendError("Two arguments must be provided in the Connect method")
		return
	end

	if typeof(signal) ~= "RBXScriptSignal" then
		self:_sendError("First argument of Connect must be of type: RBXScriptSignal")
		return
	end

	if typeof(funcCallback) ~= "function" then
		self:_sendError("Second argument of Connect must be of type: function")
		return
	end

	self:Add(signal:Connect(funcCallback))
end

--Bind a function to render stepped with a render priority
function Dumpster:BindToRenderStep(name: string, priority: number, func: (dt: number)->(any)): ()
	assert(name ~= nil and typeof(name) == "string", "Name must be a string!")
	assert(priority ~= nil and typeof(priority) == "number", "Priority must be a number!")
	assert(func ~= nil and typeof(func) == "function", "Must have a callback function!")

	game:GetService('RunService'):BindToRenderStep(name, priority, func)
	table.insert(self._bindNames, name)
end

--Create a new instance and add it to the dumpster for clean up once Clean() or Destroy() or Remove()
--is called on the identifier
function Dumpster:NewInstance(instanceType: string, cleanUpIdentifier: string?): Instance
	if not instanceType or typeof(instanceType) ~= "string" then
		self:_sendError("Instance Type must be a string!")
	end

	local newInstance = Instance.new(instanceType)
	self:Add(newInstance, cleanUpIdentifier)

	return newInstance
end

--Clones an instance and adds it to the dumpster for cleanup
function Dumpster:Clone(instance: Instance, cleanUpIdentifier: string?): Instance
	if not instance then
		self:_sendError("An instance must be provided for it to be cloned!")
		return
	end

	if typeof(instance) ~= "Instance" then
		self:_sendError("Instance provided to clone was not an instance!")
		return
	end

	local newInstance: Instance = instance:Clone()

	self:Add(newInstance, cleanUpIdentifier)

	return newInstance
end

--Cleans up object with given identifier
function Dumpster:Remove(identifier: string)
	if not identifier then
		self:_sendError("An identifier must be added in this method!")
		return
	end

	local cleaned = false
	
	local bindAt: number = table.find(self._bindNames, identifier)
	
	if bindAt then
		RunService:UnbindFromRenderStep(identifier)
		table.remove(self._bindNames, bindAt)
		cleaned = true
	end
	
	if self._dictionaryInstances[identifier] then
		self._clean(self._dictionaryInstances[identifier])
		self._dictionaryInstances[identifier] = nil
		cleaned = true
	end

	if self._dictionaryFunctions[identifier] then
		cleaned = true
		self._dictionaryFunctions[identifier] = nil
	end

	if not cleaned then
		warn("Could not find instance to remove with identifier:", identifier)
		return
	end
end

--You can attach a dumpster to an object such as Tween/AnimationTrack/Instance
--When object is completed/destroyed, Dumpster will automatically clean up
function Dumpster:AttachTo(item: any): ()
	if not item then
		self:_sendError("An Item must be provided for the dumpster to be attached to!")
		return
	end
	
	table.insert(self._instances, item)

	if typeof(item) == "Tween" then
		table.insert(self._instances, item.Completed:Connect(function()
			self:Destroy()
		end))
		return
	elseif typeof(item) == "AnimationTrack" then
		table.insert(self._instances, item.Stopped:Connect(function()
			self:Destroy()
		end))
		return
	end

	if not item:IsDescendantOf(game) then
		self:_sendError("Instance is not a member of the game hiearchy, cannot be attached!")
		return
	end

	table.insert(self._instances, item.AncestryChanged:Connect(function(child: Instance, newParent: Instance)
		if newParent then
			return
		end

		self:Destroy()
	end))
end

--Alias for Destroy()
function Dumpster:Clean(): ()
	self:Destroy()
end

--Clean up method for dumpster
function Dumpster:Destroy(): ()
	--In case something was attached, we don't want this method to be recalled again.
	if self._destroyed then
		return
	end

	self._destroyed = true

	--First clean up sub dumpsters
	for _, subDumpster in ipairs(self._subDumpsters) do
		if not subDumpster then
			continue
		end

		subDumpster:Destroy()
	end

	--First clean up connections and instances!
	for _, item: any in ipairs(self._instances) do
		--Stopping animations/tweens if added for cleanup
		self._clean(item)
	end

	for _, item: any in pairs(self._dictionaryInstances) do
		self._clean(item)
	end

	for _, func in ipairs(self._functions) do
		func()
	end

	for _, func in pairs(self._dictionaryFunctions) do
		func()
	end
	
	for _, bindName in ipairs(self._bindNames) do
		local s, e = pcall(function() 
			game:GetService('RunService'):UnbindFromRenderStep(bindName)
		end)
		if not s then
			warn(e)
		end
	end
	
	self = nil
	--rip self.
end

--clean up private function for item
function Dumpster._clean(item: any): ()
	local itemType = typeof(item)

	if itemType == "RBXScriptConnection" then
		item:Disconnect()
		return
	elseif itemType == "table" then
		if item.Disconnect then
			item:Disconnect()
			return
		end 
	elseif itemType == "AnimationTrack" then
		item:Stop()
	elseif itemType == "Tween" then
		item:Cancel()
	end

	pcall(function()
		item:Destroy()
	end)
end

function Dumpster:_sendError(message: string)
	error(message)
	error(debug.traceback())
end

return Dumpster