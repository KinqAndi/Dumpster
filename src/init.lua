--[[[
	Author @Andi Muhaxheri / KinqAndi
	Date @03/07/21
	Version: 0.3.8
		Version Update Date: 9/02/23
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FUNCTION_CLEAN_UP_ID = newproxy()
local THREAD_CLEAN_UP_ID = newproxy()
local DUMPSTER_CLEAN_UP_ID = newproxy()

local Dumpster = {}
Dumpster.__index = Dumpster

--[[
    Returns: Dumpster
    Description: Constructor for Dumpster.
]]

function Dumpster.new()
	local self = setmetatable({
		suppressWarnings = false,
		suppressErrors = false,

		_objects = {},
		_identifierObjects = {},
		_bindedNames = {},
		_attributes = {},
	}, Dumpster)

	return self
end

--[[
    Returns: any?
    Description: Takes any object as a paremeter and adds it to the dumpster for cleanup.
    Paremeters
        - object: any,
        - cleanUpIdentifier: string? (optional, could be removed from Dumpster:Remove(cleanUpIdentifier))
        - customCleanupMethod: string? (if object is a custom class and has a different cleanup method)
]]

function Dumpster:Add(object: any, cleanUpIdentifier: string?, customCleanupMethod: string?) 
	if self._isCleaning then
		self:_sendWarn("Cannot add item for cleanup when dumpster is being cleaned up/destroyed")
		return
	end

	local cleanUpMethod = self:_getCleanUpMethod(object, customCleanupMethod)

	if not cleanUpMethod then
		if typeof(object) == "table" then
			if self:_isAPromise(object) then
				return self:AddPromise(object, cleanUpIdentifier)
			end
		end

		self:_sendWarn(object, "was not added for cleanup, could not find a cleanup method!")
		return
	end

	if cleanUpIdentifier then
		if not self:_cleanUpIdentifierAvailable(cleanUpIdentifier) then
			return
		end

		self._identifierObjects[cleanUpIdentifier] = {object = object, method = cleanUpMethod}

		return object
	end

	table.insert(self._objects, {object = object, method = cleanUpMethod})

	return object
end

--[[
    Returns: ()
    Description: Add a promise to the dumpster
    Paremeters
        - promise: Promise,
        - cleanUpIdentifier: string? (optional, could be removed from Dumpster:Remove(cleanUpIdentifier))
]]

function Dumpster:AddPromise(promise, cleanUpIdentifier: string?)
	if not self:_isAPromise(promise) then
		self:_sendWarn("This is not a promise!")
		return
	end

	local cleanUpMethod = "cancel"
	cleanUpIdentifier = cleanUpIdentifier or HttpService:GenerateGUID()

	if cleanUpIdentifier then
		if not self:_cleanUpIdentifierAvailable(cleanUpIdentifier) then
			return
		end

		self._identifierObjects[cleanUpIdentifier] = {object = promise, method = cleanUpMethod}
		self:_initPromise(promise, cleanUpIdentifier)
		return
	end

	table.insert(self._objects, {object = promise, method = cleanUpMethod})
	self:_initPromise(promise, cleanUpIdentifier)
end

--[[
    Returns: nil
    Description: Adds an attribute to the dumpster
]]

function Dumpster:SetAttribute(attrName: string, attrVal: any)
	self._attributes[attrName] = attrVal
end

--[[
    Returns: any?
    Description: Retrieves an attribute from the dumpster
]]
function Dumpster:GetAttribute(attrName: string)
	return self._attributes[attrName]
end

--[[
    Returns: Dumpster
    Description: Creates a sub dumpster and then adds it to the parent Dumpster for cleanup.
]]

function Dumpster:Extend()
	local subDumpster = self.new()
    subDumpster._dumpsterProxy = DUMPSTER_CLEAN_UP_ID

	self:Add(subDumpster)

	return subDumpster
end

--[[
    Returns: any?
    Description: Construct an Instance/Class/Function with tuple arguments
    Paremeters
        - object: string | table | function,
        - ... (optional arguments to be passed on to the constructed object.)
]]

function Dumpster:Construct(object: string | table | ()->(), ...)
	if type(object) == "string" then
		local object = Instance.new(object)
		self:Add(object, ...)

		return object
	elseif type(object) == "table" then
		local item = object.new(...)
		self:Add(item)
		return item
	elseif type(object) == "function" then
        local item = object(...)
        
		self:Add(item)
		return item
	else
		self:_sendWarn("Object could not be constructed!")
	end
end

--[[
    Returns: Instance
    Description: Creates a clone of an instance and adds it to the dumpster.
    Paremeters
        - item: Instance,
]]

function Dumpster:Clone(item: Instance)
	if typeof(item) ~= "Instance" then
		self:_sendWarn("Only instances can be cloned")
		return
	end

	local item = item:Clone()
	self:Add(item)

	return item
end

--[[
    Returns: ()
    Description: Connects a callback to render stepped. Will automatically Unbind once Dumpster is destroyed.
    Paremeters
        - name: string,
        - priority: string,
        - func: (deltaTime: number)->(),
]]

function Dumpster:BindToRenderStep(name: string, priority: number, func: (dt: number)->(any)): ()
	assert(name ~= nil and typeof(name) == "string", "Name must be a string!")
	assert(priority ~= nil and typeof(priority) == "number", "Priority must be a number!")
	assert(func ~= nil and typeof(func) == "function", "Must have a callback function!")

	if self._isCleaning then
		self:_sendWarn("Cannot bind function to render step when dumpster is being cleaned up/destroyed")
		return
	end

	if table.find(self._bindedNames, name) then
		self:_sendWarn("The name you're trying to bind the function to render stepped to already exists, please use a unique name!")
		return
	end

	RunService:BindToRenderStep(name, priority, func)

	table.insert(self._bindedNames, name)
end

--[[
    Returns: ()
    Description: This will unbind a function from renderstepped.
    Paremeters
        - name: string,
]]

function Dumpster:UnbindFromRenderStep(name: string)
	local foundAt: number? = table.find(self._bindedNames, name)

	if not foundAt then
		self:_sendWarn("No Bind to render step was found with name:", name)
		return
	end

	table.remove(self._bindedNames, foundAt)
	RunService:UnbindFromRenderStep(name)
end

--[[
    Returns: any?
    Description: Wraps a signal with a function and adds it to the dumpster.
    Paremeters
        - object: any,
        - cleanUpIdentifier: string? (optional, could be removed from Dumpster:Remove(cleanUpIdentifier))
        - customCleanupMethod: string? (if object is a custom class and has a different cleanup method)
]]

function Dumpster:Connect(signal: RBXScriptSignal, connectFunction: (any)->(any), cleanupIdentifier: string?)
	if typeof(signal) ~= "RBXScriptSignal" then
		self:_sendWarn("Attempted to Connect with object not being of type RBXScriptSignal")
		return
	end

	if typeof(connectFunction) ~= "function" then
		self:_sendWarn("attempted to Connect, argument 2 expects function but got", typeof(connectFunction))
		return
	end

	if self._isCleaning then
		self:_sendWarn("Cannot call method when dumpster is being cleaned up/destroyed")
		return
	end

	return self:Add(signal:Connect(connectFunction), cleanupIdentifier)
end

--[[
    Returns: ()
    Description: This will attach the dumpster to provided object. Once that object is destroyed, dumpster will be too.
    Paremeters
        - item: any,
]]

function Dumpster:AttachTo(item: any)
	local itemType = typeof(item)

	if self._isCleaning then
		self:_sendWarn("Cannot called AttachTo when dumpster is being cleaned up/destroyed")
		return
	end

	if itemType == "Instance" and (item:IsA("Tween") or item:IsA("TweenBase")) then
		if item.TweenInfo.RepeatCount < 0 then
			local warnString = "Tried to attach Dumpster to Tween with RepeatCount < 0\n"
			warnString = warnString .. "This tween will loop infinitely until Destroy() is called\n"
			warnString = warnString .. "THEREFORE, it is attached to .Destroying instead of .Completed"

			self:_sendWarn(warnString)

			self:Add(item.Destroying:Connect(function()
				self:Destroy()
			end))
		else
			self:Add(item.Completed:Connect(function()
				self:Destroy()
			end))
		end

		return
	elseif itemType == "Instance" and item:IsA("AnimationTrack") then
		if item.Looped then
			local warnString = "Tried to attach Dumpster to AnimationTrack with Looped set to true\n"
			warnString = warnString .. "This animation will loop infinitely until Destroy() is called\n"
			warnString = warnString .. "THEREFORE, it is attached to .Destroying instead of .Stopped"

			self:_sendWarn(warnString)

			self:Add(item.Destroying:Connect(function()
				self:Destroy()
			end))
		else
			self:Add(item.Stopped:Connect(function()
				self:Destroy()
			end))
		end

		return
	elseif itemType == "Instance" and item:IsA("Player") then
		if not item:IsDescendantOf(game) then
			self:Destroy()
			return
		end

		self:Add(Players.PlayerRemoving:Connect(function(player: Player)
			if player == item then
				self:Destroy()
			end
		end))
	elseif itemType == "Instance" and item:IsA("Sound") then
		if item.Looped then
			self:_sendWarn(item, "is looped, therefore attaching to .Destroying event instead of .Ended event")

			self:Add(item.Destroying:Connect(function()
				self:Destroy()
			end))

			return
		end

		self:Add(item.Ended:Connect(function()
			self:Destroy()
		end))

		self:Add(item.Destroying:Connect(function()
			self:Destroy()
		end))
	elseif itemType == "RBXScriptSignal" then
		self:Connect(item, function()
			self:Destroy()
		end)

		return
	elseif itemType == "table" and typeof(item["Connect"]) == "function" then
		self:Add(item:Connect(function()
			self:Destroy()
		end))

		return
	elseif itemType == "Instance" and item.ClassName == "Model" and Players:GetPlayerFromCharacter(item) then
		local playerInstance = Players:GetPlayerFromCharacter(item)

		if playerInstance then
			self:AttachTo(playerInstance)
			self:AttachTo(playerInstance.CharacterAdded)
		end

		self:_streamWithUID(item, "Humanoid", function(humanoid: Humanoid)
			self:Add(humanoid.Died:Connect(function()
				self:Destroy()
			end))

			-- just in case died doesnt fire, sometimes that be happening lol.
			-- why you may ask? roblok
			self:Add(humanoid.StateChanged:Connect(function(_, newState: Enum.HumanoidStateType)
				if newState == Enum.HumanoidStateType.Dead then
					self:Destroy()
				end
			end))
		end)
	end

	if itemType == "Instance" then
		self:AttachTo(item.Destroying)
		return
	end

	self:_sendWarn("Item was not attached to Dumpster, allowed objects: Instance | Tween | TweenBase | AnimationTrack | Sound | RBXScriptSignal")

	return
end

--[[
    Returns: any?
    Description: Will Remove an object/string reference from the Dumpster.
        - If removed object is a function, and you don't want that function to run, 
          You can pass in the "dontCallCleanMethod" parameter as true.
    Paremeters
        - cleanObject: any,
        - dontCallCleanMethod: boolean?
]]

function Dumpster:Remove(cleanObject: any, dontCallCleanMethod: boolean?): any?
	if self._isCleaning then
		self:_sendWarn("Cannot remove item when dumpster is being cleaned up/destroyed")
		return
	end

	if typeof(cleanObject) == "string" then
		if not self._identifierObjects[cleanObject] then
			if table.find(self._bindedNames, cleanObject) then
				self:UnbindFromRenderStep(cleanObject)
				self._identifierObjects[cleanObject] = nil
				return
			end

			self:_sendWarn("Could find an object to clean with ID:", cleanObject)
			return
		end

		local object = self._identifierObjects[cleanObject].object
		local method = self._identifierObjects[cleanObject].method
		
		self._identifierObjects[cleanObject] = nil

		if dontCallCleanMethod then
			return object
		end

		self:_cleanObject(object, method, true)

		return
	end

	return self:_removeObject(cleanObject, dontCallCleanMethod)
end

--[[
    Returns: ()
    Description: Alias for Destroy()
]]

function Dumpster:Clean()
	self:Destroy()
end
--[[
    Returns: ()
    Description: Cleans up the dumpster.
]]

function Dumpster:Destroy()
	--cleans something based on a cleanup method
	if self._isCleaning then
		self:_sendWarn("Tried to Destroy dumpster when its currently being cleaned up!")
		return
	end

	self:_destroy()
	--commented out so Dumpster could be reused after cleaned/destroyed.
end

--
function Dumpster:_streamWithUID(obj: Instance, childName: string, callback: (Instance)->())
	local found = obj:FindFirstChild(childName)

	if found then
		callback(found)
		return
	end

	local uid = `STREAM_UID_{HttpService:GenerateGUID()}`

	local elapsed = 0

	self:Add(RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local itemExist = obj:FindFirstChild(childName)

		if itemExist or elapsed >= 5 then
			if itemExist then
				callback(itemExist)
			else
				self:_sendWarn("Attempt on streaming for", childName, "resulted in a timeout.")
			end

			self:Remove(uid)
			elapsed = nil
		end
	end), uid)

	return uid
end

function Dumpster:_getCleanUpMethod(object, customCleanupMethod): string?
	local objectType = typeof(object)

	if (objectType ~= "thread" and objectType ~= "function") and customCleanupMethod then
		return customCleanupMethod
	end

	if objectType == "thread" then
		return THREAD_CLEAN_UP_ID
	elseif objectType == "function" then -- clean up functions to run once Destroy | Clean is called
		return FUNCTION_CLEAN_UP_ID
	elseif objectType == "Instance" then
		return "Destroy"
	elseif objectType == "table" then
		if typeof(object.Destroy) == "function" then
			return "Destroy"
		elseif typeof(object.Clean) == "function" then
			return "Clean"
		elseif typeof(object.Disconnect) == "function" then
			return "Disconnect"
		end

		return
	elseif objectType == "RBXScriptConnection" then
		return "Disconnect"
	end

	return
end

function Dumpster:_cleanUpIdentifierAvailable(cleanupIdentifier: string): boolean
	if self._identifierObjects[cleanupIdentifier] then
		self:_sendError("A cleanup identifier with ID: " .. cleanupIdentifier .. "already exists")
		return false
	end

	return true
end

function Dumpster:_removeObject(object: any, dontCallCleanMethod: boolean?)
	local table: table
	local index: (number | string)?

	for i, item in ipairs(self._objects) do
		if item.object == object then
			table = self._objects
			index = i
			break
		end
	end

	if not table then
		for key, item in pairs(self._identifierObjects) do
			if item.object == object then
				table = self._identifierObjects
				index = key
				break
			end
		end
	end

	if not table then
		self:_sendWarn("Could not find object to remove!")
		return
	end

	local object = table[index].object
	local method = table[index].method

	if dontCallCleanMethod then
		local reference = object
		table[index] = nil
		self._identifierObjects[index] = nil
		return reference
	end

	if self:_cleanObject(object, method, true) then
		table[index] = nil
		self._identifierObjects[index] = nil
	end

	return
end

function Dumpster:_destroy()
	self._isCleaning = true

	local functionsToRunOnceCleaned = {}

	local function cleanObject(item, cleanUpMethod)
		if cleanUpMethod == FUNCTION_CLEAN_UP_ID then
			table.insert(functionsToRunOnceCleaned, item)
			return
		end
--[[
        if typeof(item) == "table" and (DUMPSTER_CLEAN_UP_ID == DUMPSTER_CLEAN_UP_ID) and self._destroyed then
            return
        end
--]]
		self:_cleanObject(item, cleanUpMethod)
	end

	for _, item in ipairs(self._objects) do
		cleanObject(item.object, item.method)
	end

	for _, item in pairs(self._identifierObjects) do
		cleanObject(item.object, item.method)
	end

	for _, bindName in ipairs(self._bindedNames) do
		RunService:UnbindFromRenderStep(bindName)
	end

	table.clear(self._objects)
	table.clear(self._identifierObjects)
	table.clear(self._bindedNames)
	table.clear(self._attributes)

	for _, func in ipairs(functionsToRunOnceCleaned) do
		task.spawn(func)
	end

	self._isCleaning = false
end

function Dumpster:_cleanObject(item, cleanUpMethod, callFunction: boolean?)
	if cleanUpMethod == THREAD_CLEAN_UP_ID then
		if coroutine.status(item) ~= "dead" then
			coroutine.close(item)
		end
		return
	end

	if cleanUpMethod == FUNCTION_CLEAN_UP_ID and callFunction then
		item()
		return
	end

	if not item then
		return
	end

	if self._isAPromise(item) then
		pcall(function ()
			item[cleanUpMethod](item)
		end)

		return true
	end

	item[cleanUpMethod](item)

	return true
end

function Dumpster:_sendError(msg: string): ()
	if self.suppressErrors then
		return
	end

	error(msg .. "\n" .. debug.traceback())
end

function Dumpster:_sendWarn(...): ()
	if self.suppressWarnings then
		return
	end

	warn(...)
	warn(debug.traceback())
end

function Dumpster:_isAPromise(object)
	local s,e  = pcall(function()
		local hasCancel = typeof(object.cancel) == "function"
		local hasGetStatus = typeof(object["getStatus"]) == "function"
		local hasFinally = typeof(object["finally"]) == "function"

		local hasAndThen = typeof(object["andThen"]) == "function"

		return hasCancel and hasGetStatus and hasFinally and hasAndThen
	end)

	if not s then
		return false
	end

	return e
end

function Dumpster:_initPromise(object, cleanupIdentifier)
	if object:getStatus() == "Started" then
		object:finally(function()
			if self._isCleaning then
				return
			end

			self:Remove(cleanupIdentifier, true)
		end)
	end

	return true
end

return Dumpster