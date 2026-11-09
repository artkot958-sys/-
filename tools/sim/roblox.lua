--[[
	Заглушка Roblox API на Lua для запуска игры в настоящем Luau.
	Реализовано только то, что использует наша игра.
]]

local M = {}
-- Собственные итераторы: в Luau через JS-границу ipairs/pairs работают
-- иначе, поэтому определяем их локально и используем во всей заглушке
local function _ipairs(t)
	local i = 0
	return function()
		i = i + 1
		local v = t[i]
		if v ~= nil then
			return i, v
		end
		return nil
	end
end

local function _pairs(t)
	local keys = {}
	local n = 0
	for k in next, t do
		if k ~= "__mt" then
			n = n + 1
			keys[n] = k
		end
	end
	local i = 0
	return function()
		i = i + 1
		local k = keys[i]
		if k == nil then return nil end
		return k, t[k]
	end
end

-- Используем внутри заглушки только локальные версии
local ipairs = _ipairs
local pairs = _pairs

-- ============================================================
-- Vector3
-- ============================================================
local Vector3 = {}
local vecMeta = {}

vecMeta.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then return M.Vector3.new(0, 0, 0) end
		return M.Vector3.new(self.X / m, self.Y / m, self.Z / m)
	elseif key == "Lerp" then
		return function(a, b, alpha)
			return M.Vector3.new(
				a.X + (b.X - a.X) * alpha,
				a.Y + (b.Y - a.Y) * alpha,
				a.Z + (b.Z - a.Z) * alpha
			)
		end
	elseif key == "Cross" then
		return function(a, b)
			return M.Vector3.new(
				a.Y * b.Z - a.Z * b.Y,
				a.Z * b.X - a.X * b.Z,
				a.X * b.Y - a.Y * b.X
			)
		end
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	end
	return nil
end

vecMeta.__add = function(a, b)
	return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vecMeta.__sub = function(a, b)
	return M.Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
vecMeta.__mul = function(a, b)
	if type(b) == "number" then
		return M.Vector3.new(a.X * b, a.Y * b, a.Z * b)
	elseif type(a) == "number" then
		return M.Vector3.new(a * b.X, a * b.Y, a * b.Z)
	end
	return M.Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
vecMeta.__div = function(a, b)
	return M.Vector3.new(a.X / b, a.Y / b, a.Z / b)
end
vecMeta.__unm = function(a)
	return M.Vector3.new(-a.X, -a.Y, -a.Z)
end
vecMeta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
vecMeta.__tostring = function(a)
	return string.format("%.1f, %.1f, %.1f", a.X, a.Y, a.Z)
end

M.Vector3 = {
	new = function(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, vecMeta)
	end,
}

local vec2Meta = {
	__index = function(self, key) return nil end,
	__tostring = function(a) return string.format("%.0f, %.0f", a.X, a.Y) end,
}

M.Vector2 = {
	new = function(x, y)
		return setmetatable({ X = x or 0, Y = y or 0 }, vec2Meta)
	end,
}

-- ============================================================
-- CFrame
-- ============================================================
local cfMeta = {}

cfMeta.__index = function(self, key)
	if key == "Position" then
		return M.Vector3.new(self.X, self.Y, self.Z)
	end
	return nil
end

cfMeta.__mul = function(a, b)
	-- a всегда CFrame (левая часть). b может быть Vector3, CFrame или чем угодно
	if type(a) ~= "table" then
		return a
	end

	if type(b) == "table" and b.__isVector then
		return M.Vector3.new((a.X or 0) + (b.X or 0), (a.Y or 0) + (b.Y or 0), (a.Z or 0) + (b.Z or 0))
	end

	if type(b) == "table" and b.__isCFrame then
		return M.CFrame.new((a.X or 0) + (b.X or 0), (a.Y or 0) + (b.Y or 0), (a.Z or 0) + (b.Z or 0))
	end

	return a
end

M.CFrame = {
	new = function(x, y, z)
		-- CFrame.new(position) или CFrame.new(position, lookAt)
		if type(x) == "table" then
			return setmetatable({ X = x.X or 0, Y = x.Y or 0, Z = x.Z or 0, __isCFrame = true }, cfMeta)
		end
		-- CFrame.new(x, y, z) — но y может быть таблицей (lookAt)
		if type(y) == "table" then
			return setmetatable({ X = x or 0, Y = 0, Z = z or 0, __isCFrame = true }, cfMeta)
		end
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __isCFrame = true }, cfMeta)
	end,
	Angles = function()
		return setmetatable({ X = 0, Y = 0, Z = 0, __isCFrame = true }, cfMeta)
	end,
	lookAt = function(from, to)
		return M.CFrame.new(from)
	end,
}

-- ============================================================
-- Color3
-- ============================================================
local colorMeta = {}

colorMeta.__index = function(self, key)
	if key == "Lerp" then
		return function(c, other, alpha)
			return M.Color3.new(
				c.R + (other.R - c.R) * alpha,
				c.G + (other.G - c.G) * alpha,
				c.B + (other.B - c.B) * alpha
			)
		end
	end
	return nil
end

M.Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, colorMeta)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, colorMeta)
	end,
}

-- ============================================================
-- UDim / UDim2
-- ============================================================
M.UDim = {
	new = function(scale, offset)
		return { Scale = scale or 0, Offset = offset or 0 }
	end,
}

M.UDim2 = {
	new = function(xs, xo, ys, yo)
		return {
			X = { Scale = xs or 0, Offset = xo or 0 },
			Y = { Scale = ys or 0, Offset = yo or 0 },
		}
	end,
	fromOffset = function(x, y)
		return M.UDim2.new(0, x or 0, 0, y or 0)
	end,
	fromScale = function(x, y)
		return M.UDim2.new(x or 0, 0, y or 0, 0)
	end,
}

-- ============================================================
-- Enum: принимает любое поле
-- ============================================================
local enumInstances = {}

M.Enum = setmetatable({}, {
	__index = function(_, categoryName)
		local category = setmetatable({}, {
			__index = function(_, itemName)
				local key = categoryName .. "." .. itemName
				if not enumInstances[key] then
					enumInstances[key] = {
						Name = itemName,
						EnumType = categoryName,
						__tostring = function() return "Enum." .. key end,
					}
				end
				return enumInstances[key]
			end,
		})
		return category
	end,
})

-- ============================================================
-- Сигналы
-- ============================================================
local function newSignal()
	local signal = { handlers = {} }

	function signal:Connect(fn)
		table.insert(self.handlers, fn)
		return {
			Disconnect = function() end,
			Connected = true,
		}
	end

	function signal:Once(fn)
		return self:Connect(fn)
	end

	function signal:Wait()
		return nil
	end

	function signal:Fire(...)
		for _, fn in ipairs(self.handlers) do
			local ok, err = pcall(fn, ...)
			if not ok then
				M.log("сигнал: " .. tostring(err))
			end
		end
	end

	return signal
end

M.newSignal = newSignal

-- ============================================================
-- Instance
-- ============================================================
local InstanceMeta = {}
local instanceCount = 0

local SIGNAL_NAMES = {
	ChildAdded = true, ChildRemoved = true, AncestryChanged = true,
	Destroying = true, Changed = true, Triggered = true, Died = true,
	Touched = true, MouseButton1Click = true, MouseEnter = true,
	MouseLeave = true, InputBegan = true, InputEnded = true, Activated = true,
	CharacterAdded = true, PlayerAdded = true, PlayerRemoving = true,
	Heartbeat = true, RenderStepped = true, GetPropertyChangedSignal = true,
}

local DEFAULTS = {
	Anchored = true,
	CanCollide = false,
	CanQuery = true,
	CanTouch = true,
	Transparency = 0,
	Reflectance = 0,
	Massless = false,
	Enabled = true,
	Visible = true,
	Text = "",
	TextSize = 14,
	TextScaled = false,
	ZIndex = 1,
	AutoButtonColor = true,
	BackgroundTransparency = 0,
	ResetOnSpawn = true,
	IgnoreGuiInset = false,
	DisplayOrder = 0,
	AlwaysOnTop = false,
	MaxDistance = 1000,
	LightInfluence = 0,
	HoldDuration = 0,
	MaxActivationDistance = 10,
	RequiresLineOfSight = true,
	Duration = 10,
	Neutral = true,
	Brightness = 1,
	Range = 8,
	ScrollBarThickness = 12,
	CanvasSize = nil,
	AutomaticCanvasSize = nil,
	ScrollingDirection = nil,
}

InstanceMeta.__index = function(self, key)
	local props = rawget(self, "_props")
	local signals = rawget(self, "_signals")
	local children = rawget(self, "_children")

	-- методы
	if key == "IsA" then
		return function(obj, className)
			if obj.ClassName == className then return true end
			local inherit = {
				Part = { "BasePart", "PVInstance", "Instance" },
				MeshPart = { "BasePart", "Instance" },
				TextButton = { "GuiButton", "GuiObject", "Instance" },
				TextLabel = { "GuiObject", "Instance" },
				Frame = { "GuiObject", "Instance" },
				ScrollingFrame = { "GuiObject", "Instance" },
				Script = { "BaseScript", "Instance" },
				LocalScript = { "BaseScript", "Instance" },
				ModuleScript = { "Instance" },
			}
			for _, parent in ipairs(inherit[obj.ClassName] or {}) do
				if parent == className then return true end
			end
			return className == "Instance"
		end
	elseif key == "Destroy" then
		return function(obj)
			local parent = rawget(obj, "_props").Parent
			if parent then
				local pc = rawget(parent, "_children")
				for i, child in ipairs(pc) do
					if child == obj then
						table.remove(pc, i)
						break
					end
				end
			end
			rawget(obj, "_props").Parent = nil
		end
	elseif key == "Clone" then
		return function(obj) return obj end
	elseif key == "GetChildren" then
		return function(obj)
			local copy = {}
			for i, c in ipairs(rawget(obj, "_children")) do
				copy[i] = c
			end
			return copy
		end
	elseif key == "GetDescendants" then
		return function(obj)
			local out = {}
			local function walk(node)
				for _, child in ipairs(rawget(node, "_children")) do
					table.insert(out, child)
					walk(child)
				end
			end
			walk(obj)
			return out
		end
	elseif key == "FindFirstChild" then
		return function(obj, name, recursive)
			for _, child in ipairs(rawget(obj, "_children")) do
				if child.Name == name then return child end
			end
			if recursive then
				for _, child in ipairs(rawget(obj, "_children")) do
					local found = child:FindFirstChild(name, true)
					if found then return found end
				end
			end
			return nil
		end
	elseif key == "FindFirstChildOfClass" or key == "FindFirstChildWhichIsA" then
		return function(obj, className)
			for _, child in ipairs(rawget(obj, "_children")) do
				if child.ClassName == className then return child end
				if child.IsA and type(className) == "string" and child:IsA(className) then
					return child
				end
			end
			return nil
		end
	elseif key == "FindFirstAncestorOfClass" then
		return function() return nil end
	elseif key == "WaitForChild" then
		return function(obj, name, timeout)
			local found = obj:FindFirstChild(name)
			if found then return found end
			-- ВАЖНО: в реальном Roblox это ждёт вечно.
			-- В заглушке возвращаем nil, чтобы поймать баг, а не зависнуть.
			return nil
		end
	elseif key == "GetAttribute" then
		return function(obj, name)
			local attrs = rawget(obj, "_props").Attributes
			return attrs and attrs[name] or nil
		end
	elseif key == "SetAttribute" then
		return function(obj, name, value)
			local props = rawget(obj, "_props")
			props.Attributes = props.Attributes or {}
			props.Attributes[name] = value
		end
	elseif key == "GetFullName" then
		return function(obj)
			local parts = { obj.Name }
			local node = rawget(obj, "_props").Parent
			while node do
				table.insert(parts, 1, node.Name)
				node = rawget(node, "_props").Parent
			end
			return table.concat(parts, ".")
		end
	end

	-- сигналы
	if SIGNAL_NAMES[key] then
		if not signals[key] then
			signals[key] = newSignal()
		end
		return signals[key]
	end

	-- явно заданные свойства
	if props[key] ~= nil then
		return props[key]
	end

	-- значения по умолчанию
	if DEFAULTS[key] ~= nil then
		return DEFAULTS[key]
	end

	return nil
end

InstanceMeta.__newindex = function(self, key, value)
	local props = rawget(self, "_props")

	if key == "Parent" then
		local old = props.Parent
		if old then
			local oc = rawget(old, "_children")
			for i, child in ipairs(oc) do
				if child == self then
					table.remove(oc, i)
					break
				end
			end
		end

		props.Parent = value

		if value then
			table.insert(rawget(value, "_children"), self)
		end
		return
	end

	props[key] = value
end

InstanceMeta.__tostring = function(self)
	return self.Name or self.ClassName
end

M.Instance = {}

function M.Instance.new(className, parent)
	instanceCount += 1

	local obj = setmetatable({
		ClassName = className,
		_props = { Parent = nil },
		_signals = {},
		_children = {},
		_id = instanceCount,
	}, InstanceMeta)

	rawget(obj, "_props").Name = className

	if parent then
		obj.Parent = parent
	end

	return obj
end

-- ============================================================
-- Сервисы
-- ============================================================
local services = {}

local function newService(name, className)
	local service = M.Instance.new(className or "Service")
	service.Name = name
	return service
end

function M.getService(name)
	if services[name] then
		return services[name]
	end

	local service

	if name == "Players" then
		service = newService("Players")
		service.GetPlayers = function() return {} end
		service.GetPlayerFromCharacter = function() return nil end
		service.PlayerAdded = newSignal()
		service.PlayerRemoving = newSignal()
		service.CharacterAutoLoads = true

	elseif name == "RunService" then
		service = newService("RunService")
		service.Heartbeat = newSignal()
		service.RenderStepped = newSignal()
		service.Stepped = newSignal()
		service.IsServer = function() return true end
		service.IsClient = function() return false end
		service.IsStudio = function() return true end

	elseif name == "TweenService" then
		service = newService("TweenService")
		service.Create = function(_, obj, info, goal)
			local tween = newSignal()
			tween.Play = function() end
			tween.Cancel = function() end
			tween.Pause = function() end
			return tween
		end

	elseif name == "Workspace" then
		service = newService("Workspace", "Workspace")
		service.Gravity = 196.2

	elseif name == "ReplicatedStorage" then
		service = newService("ReplicatedStorage")

	elseif name == "ServerScriptService" then
		service = newService("ServerScriptService")

	elseif name == "ServerStorage" then
		service = newService("ServerStorage")

	elseif name == "StarterPlayer" then
		service = newService("StarterPlayer")
		service.StarterPlayerScripts = newService("StarterPlayerScripts")
		service.StarterPlayerScripts.Parent = service

	elseif name == "StarterGui" then
		service = newService("StarterGui")
		service.SetCoreGuiEnabled = function() end

	elseif name == "Lighting" then
		service = newService("Lighting")
		service.FindFirstChildOfClass = function(obj, className)
			for _, child in ipairs(rawget(obj, "_children")) do
				if child.ClassName == className then return child end
			end
			return nil
		end

	elseif name == "DataStoreService" then
		service = newService("DataStoreService")
		local storage = {}
		service.GetDataStore = function(_, storeName)
			return {
				GetAsync = function(_, key) return storage[key] end,
				SetAsync = function(_, key, value) storage[key] = value end,
				UpdateAsync = function(_, key, fn)
					storage[key] = fn(storage[key])
					return storage[key]
				end,
				RemoveAsync = function(_, key) storage[key] = nil end,
			}
		end

	elseif name == "UserInputService" then
		service = newService("UserInputService")
		service.InputBegan = newSignal()
		service.InputEnded = newSignal()
		service.GetMouseLocation = function() return M.Vector2.new(0, 0) end
		service.TouchEnabled = false
		service.KeyboardEnabled = true
		service.MouseEnabled = true

	elseif name == "GuiService" then
		service = newService("GuiService")

	elseif name == "MarketplaceService" then
		service = newService("MarketplaceService")

	else
		service = newService(name)
	end

	services[name] = service
	return service
end

-- ============================================================
-- game
-- ============================================================
local game = M.Instance.new("DataModel")
game.Name = "Game"

game.GetService = function(_, name)
	return M.getService(name)
end

game.BindToClose = function() end
game.IsLoaded = function() return true end
game.SetPlaceId = function() end

M.game = game
M.workspace = M.getService("Workspace")

-- ============================================================
-- task
-- ============================================================
--[[
	ВАЖНО: игры используют `while true do task.wait(n) end` для циклов.
	В заглушке нельзя ждать по-настоящему, но и бесконечно крутиться нельзя.

	Решение: task.wait бросает специальный сигнал __YIELD, который
	ловят task.spawn/delay/defer. Так тело цикла выполняется РОВНО ОДИН РАЗ —
	достаточно, чтобы проверить, что код не падает, но без зависания.
]]
-- Строковый маркер: таблицы теряют идентичность при пересечении JS-границы
local YIELD = "__EGGGAME_YIELD__"

M.task = {
	wait = function()
		error(YIELD, 0)
	end,
	spawn = function(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok and not tostring(err):find("EGGGAME_YIELD") then
			M.log("task.spawn ОШИБКА: " .. tostring(err))
		end
	end,
	delay = function(_, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok and not tostring(err):find("EGGGAME_YIELD") then
			M.log("task.delay ОШИБКА: " .. tostring(err))
		end
	end,
	defer = function(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok and not tostring(err):find("EGGGAME_YIELD") then
			M.log("task.defer ОШИБКА: " .. tostring(err))
		end
	end,
	cancel = function() end,
}

-- ============================================================
-- Random / TweenInfo
-- ============================================================
M.Random = {
	new = function()
		return {
			NextNumber = function(_, a, b)
				if a ~= nil and b ~= nil then
					return a + math.random() * (b - a)
				elseif a ~= nil then
					return math.random() * a
				end
				return math.random()
			end,
			NextInteger = function(_, a, b)
				return math.random(a, b)
			end,
			Shuffle = function() end,
		}
	end,
}

M.TweenInfo = {
	new = function() return {} end,
}

M.NumberRange = {
	new = function(a, b) return { Min = a, Max = b } end,
}

M.RaycastParams = { new = function() return {} end }
M.OverlapParams = { new = function() return {} end }

-- ============================================================
-- Логирование
-- ============================================================
M.logs = {}

-- Подсчёт детей: считаем прямо во внутреннем списке заглушки,
-- не выходя за границу JS (pairs/# на JS-массивах в Luau ломаются)
function M.childCount(instance)
	return #rawget(instance, "_children")
end

-- Получить ребёнка по индексу (1-based), без JS-границы
function M.childAt(instance, index)
	return rawget(instance, "_children")[index]
end

-- Все дети как обычная Lua-таблица
function M.childrenOf(instance)
	local out = {}
	local children = rawget(instance, "_children")
	for i = 1, #children do
		out[i] = children[i]
	end
	return out
end

function M.log(text)
	table.insert(M.logs, tostring(text))
	print(tostring(text))
end

return M
