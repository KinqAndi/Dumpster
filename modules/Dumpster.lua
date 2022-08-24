local Dumpster = {}
Dumpster.__index = Dumpster

--Constructor for Dumpster 
function Dumpster.new()
	local self = setmetatable({
		_dictionaryInstances = {},
		_dictionaryFunctions = {},
		_instances = {},
		_functions = {},
		_subDumpsters = {},
	}, Dumpster)
	
	return self
end

--Extends the class into a subclass, gets cleaned up on super:Destroy()
function Dumpster:Extend()
	local subDumpster = self.new()
	table.insert(self._subDumpsters, subDumpster)
	return subDumpster
end

--Cleans up object with given identifier
function Dumpster:Remove(identifier: string)
	if not identifier then
		warn("An identifier must be added in this method!")
		return
	end
	
	local cleaned = false
	
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

--Add an object to the dumpster
function Dumpster:Add(object: any, cleanUpIdentifier: string?)
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

--You can attach a dumpster to an object such as Tween/AnimationTrack/Instance
--When object is completed/destroyed, Dumpster will automatically clean up
function Dumpster:AttachTo(item: any)
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
		warn("Instance is not a member of the game hiearchy, cannot be attached!")
		warn(debug.traceback())
		return
	end
	
	table.insert(self._instances, item.AncestryChanged:Connect(function(child: Instance, newParent: Instance)
		if newParent then
			return
		end
		
		self:Destroy()
	end))
end

--Clean up method for dumpster
function Dumpster:Destroy()
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
	
	for _, func in ipairs(self._dictionaryFunctions) do
		func()
	end
	
	self = nil
	--rip self.
end

--clean up private function for item
function Dumpster._clean(item: any)
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

return Dumpster