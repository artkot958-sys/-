--[[
	Минимальная заглушка Roblox API для проверки кода без Studio.

	Реализует только то, что использует наша игра:
	Instance.new, дерево Parent/Child, Vector3, CFrame, Color3,
	Enum, сигналы (Connect/Fire), task, game:GetService, Workspace и т.д.

	Задача — поймать ошибки ЛОГИКИ и опечатки, а не отрендерить игру.
]]

-- ============================================================
-- ВЕКТОРЫ / ЦВЕТА / CFrame
-- ============================================================

local Vector3 = {}
Vector3.__index = Vector3

local function vec3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3)
end

function Vector3.new(x, y, z)
	return vec3(x, y, z)
end

Vector3.__add = function(a, b)
	return vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end

Vector3.__sub = function(a, b)
	return vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end

Vector3.__mul = function(a, b)
	if type(b) == "number" then
		return vec3(a.X * b, a.Y * b, a.Z * b)
	elseif type(a) == "number" then
		return vec3(a * b.X, a * b.Y, a * b.Z)
	end
	return vec3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end

Vector3.__div = function(a, b)
	return vec3(a.X / b, a.Y / b, a.Z / b)
end

Vector3.__unm = function(a)
	return vec3(-a.X, -a.Y, -a.Z)
end

Vector3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end

Vector3.__tostring = function(a)
	return string.format("%.2f, %.2f, %.2f", a.X, a.Y, a.Z)
end

function Vector3:__index(key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	elseif key == "Unit" then
		local m = math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
		if m == 0 then
			return vec3(0, 0, 0)
		end
		return vec3(self.X / m, self.Y / m, self.Z / m)
	end
	return nil
end

local Vector2
Vector2 = {}
Vector2.__index = Vector2

function Vector2.new(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, Vector2)
end

-- CFrame: храним позицию, повороты игнорируем (для проверки логики не важны)
local CFrame = {}
CFrame.__index = CFrame

local function cframe(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, Position = vec3(x or 0, y or 0, z or 0) }, CFrame)
end

function CFrame.new(x, y, z)
	if type(x) == "table" then
		-- CFrame.new(position) или CFrame.new(position, lookAt)
		return cframe(x.X, x.Y, x.Z)
	end
	return cframe(x, y, z)
end

function CFrame.Angles(rx, ry, rz)
	return cframe(0, 0, 0)
end

function CFrame.fromEulerAnglesXYZ(rx, ry, rz)
	return cframe(0, 0, 0)
end

function CFrame:__mul(other)
	if getmetatable(other) == CFrame then
		return cframe(self.X + other.X, self.Y + other.Y, self.Z + other.Z)
	end
	if getmetatable(other) == Vector3 then
		return vec3(self.X + other.X, self.Y + other.Y, self.Z + other.Z)
	end
	return self
end

CFrame.identity = cframe(0, 0, 0)

-- Color3
local Color3 = {}
local colorMeta = {
	__index = {
		Lerp = function(self, other, alpha)
			return Color3.new(
				self.R + (other.R - self.R) * alpha,
				self.G + (other.G - self.G) * alpha,
				self.B + (other.B - self.B) * alpha
			)
		end,
	},
}

function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, colorMeta)
end

function Color3.fromRGB(r, g, b)
	return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, colorMeta)
end

-- UDim / UDim2
local UDim2 = {}
function UDim2.new(xs, xo, ys, yo)
	return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }
end
function UDim2.fromOffset(x, y)
	return UDim2.new(0, x or 0, 0, y or 0)
end
function UDim2.fromScale(x, y)
	return UDim2.new(x or 0, 0, y or 0, 0)
end

local UDim = {}
function UDim.new(scale, offset)
	return { Scale = scale or 0, Offset = offset or 0 }
end

-- ============================================================
-- ENUM (принимает любое поле, возвращает заглушку)
-- ============================================================

local enumCache = {}

local function makeEnum(categoryName)
	return setmetatable({}, {
		__index = function(_, itemName)
			local key = categoryName .. "." .. itemName
			if not enumCache[key] then
				enumCache[key] = {
					Name = itemName,
					EnumType = categoryName,
					Value = math.random(0, 100),
					__tostring = function() return "Enum." .. key end,
				}
			end
			return enumCache[key]
		end,
	})
end

local Enum = setmetatable({}, {
	__index = function(_, categoryName)
		return makeEnum(categoryName)
	end,
})

-- ============================================================
-- СИГНАЛЫ
-- ============================================================

local Signal = {}
Signal.__index = Signal

local function newSignal()
	return setmetatable({ handlers = {} }, Signal)
end

function Signal:Connect(fn)
	table.insert(self.handlers, fn)
	return {
		Disconnect = function()
			for i, h in ipairs(self.handlers) do
				if h == fn then
					table.remove(self.handlers, i)
					break
				end
			end
		end,
	}
end

function Signal:ConnectParallel(fn)
	return self:Connect(fn)
end

function Signal:Wait()
	return nil
end

function Signal:Fire(...)
	for _, fn in ipairs(self.handlers) do
		local ok, err = pcall(fn, ...)
		if not ok then
			print("   ⚠️  сигнал: " .. tostring(err))
		end
	end
end

-- ============================================================
-- INSTANCE
-- ============================================================

local Instance = {}

local partProperties = {
	Anchored = true, CanCollide = false, CanQuery = true, CanTouch = true,
	Transparency = 0, Reflectance = 0, Massless = false,
	Position = Vector3.new(0, 0, 0),
	Size = Vector3.new(4, 1, 2),
}

local InstanceMeta = {}
InstanceMeta.__index = function(self, key)
	local props = rawget(self, "_props")
	local children = rawget(self, "_children")
	local signals = rawget(self, "_signals")

	-- методы
	if key == "IsA" then
		return function(obj, className)
			-- упрощённо: сравнение имени класса и «предков»
			if obj.ClassName == className then
				return true
			end
			local inherits = {
				Part = { "BasePart", "Instance" },
				TextButton = { "GuiButton", "GuiObject", "Instance" },
				Frame = { "GuiObject", "Instance" },
				TextLabel = { "GuiObject", "Instance" },
				ModuleScript = { "LuaSourceContainer", "Instance" },
				Script = { "LuaSourceContainer", "Instance" },
				LocalScript = { "LuaSourceContainer", "Instance" },
			}
			for _, parent in ipairs(inherits[obj.ClassName] or {}) do
				if parent == className then
					return true
				end
			end
			return className == "Instance"
		end
	elseif key == "Destroy" then
		return function(obj)
			if obj.Parent then
				for i, child in ipairs(obj.Parent._children) do
					if child == obj then
						table.remove(obj.Parent._children, i)
						break
					end
				end
			end
			obj.Parent = nil
		end
	elseif key == "Clone" then
		return function(obj)
			return obj
		end
	elseif key == "GetChildren" then
		return function(obj)
			local copy = {}
			for i, c in ipairs(obj._children) do
				copy[i] = c
			end
			return copy
		end
	elseif key == "GetDescendants" then
		return function(obj)
			return obj:GetChildren()
		end
	elseif key == "FindFirstChild" then
		return function(obj, name, recursive)
			for _, child in ipairs(obj._children) do
				if child.Name == name then
					return child
				end
			end
			if recursive then
				for _, child in ipairs(obj._children) do
					local found = child:FindFirstChild(name, true)
					if found then
						return found
					end
				end
			end
			return nil
		end
	elseif key == "FindFirstChildOfClass" then
		return function(obj, className)
			for _, child in ipairs(obj._children) do
				if child.ClassName == className then
					return child
				end
			end
			return nil
		end
	elseif key == "WaitForChild" then
		return function(obj, name, timeout)
			local found = obj:FindFirstChild(name)
			if found then
				return found
			end
			-- В эмуляторе создаём «пустышку» с нужным именем,
			-- чтобы require/обращения не падали на nil
			local stub = Instance.new("Stub")
			stub.Name = name
			stub.Parent = obj
			return stub
		end
	elseif key == "GetAttribute" then
		return function(obj, name)
			return (props.Attributes or {})[name]
		end
	elseif key == "SetAttribute" then
		return function(obj, name, value)
			props.Attributes = props.Attributes or {}
			props.Attributes[name] = value
		end
	elseif key == "GetPropertyChangedSignal" then
		return function(obj, name)
			return newSignal()
		end
	elseif key == "GetPivot" then
		return function(obj)
			return cframe(0, 0, 0)
		end
	elseif key == "SetPrimaryPartCFrame" then
		return function() end
	end

	-- сигналы
	if key == "ChildAdded" or key == "ChildRemoved" or key == "AncestryChanged"
		or key == "Destroying" or key == "Changed" or key == "Triggered"
		or key == "Died" or key == "Touched" or key == "MouseButton1Click"
		or key == "MouseEnter" or key == "MouseLeave" or key == "InputBegan"
		or key == "Activated" or key == "CharacterAdded" or key == "PlayerAdded"
		or key == "PlayerRemoving" or key == "Heartbeat" then
		if not signals[key] then
			signals[key] = newSignal()
		end
		return signals[key]
	end

	-- сохранённое свойство
	if props[key] ~= nil then
		return props[key]
	end

	-- свойства по умолчанию для частей
	if partProperties[key] ~= nil then
		return partProperties[key]
	end

	-- неизвестное свойство: возвращаем nil (как Roblox для несуществующих)
	return nil
end

InstanceMeta.__newindex = function(self, key, value)
	local props = rawget(self, "_props")

	if key == "Parent" then
		local old = props.Parent
		if old and old._children then
			for i, child in ipairs(old._children) do
				if child == self then
					table.remove(old._children, i)
					break
				end
			end
		end
		props.Parent = value
		if value and value._children then
			table.insert(value._children, self)
		end
		return
	end

	props[key] = value
end

InstanceMeta.__tostring = function(self)
	return self.Name or self.ClassName
end

function Instance.new(className, parent)
	local obj = setmetatable({
		ClassName = className,
		Name = className,
		_children = {},
		_signals = {},
		_props = { Parent = nil },
	}, InstanceMeta)

	obj.Parent = parent
	return obj
end

-- ============================================================
-- СЕРВИСЫ И GAME
-- ============================================================

local services = {}

local function getService(name)
	if not services[name] then
		local service = Instance.new(name .. "Service")
		service.Name = name

		if name == "Players" then
			service.GetPlayers = function()
				return {}
			end
			service.PlayerAdded = newSignal()
			service.PlayerRemoving = newSignal()
			service.LocalPlayer = nil
		end

		if name == "RunService" then
			service.Heartbeat = newSignal()
			service.RenderStepped = newSignal()
			service.Stepped = newSignal()
			service.IsServer = function() return true end
			service.IsClient = function() return false end
			service.IsStudio = function() return true end
		end

		if name == "TweenService" then
			service.Create = function(_, obj, info, goal)
				return {
					Play = function() end,
					Completed = { Wait = function() end },
					Cancel = function() end,
					Pause = function() end,
					Completed = newSignal(),
				}
			end
		end

		if name == "UserInputService" then
			service.InputBegan = newSignal()
			service.InputEnded = newSignal()
			service.GetMouseLocation = function() return Vector2.new(0, 0) end
			service.TouchEnabled = false
			service.KeyboardEnabled = true
		end

		if name == "DataStoreService" then
			service.GetDataStore = function()
				return {
					GetAsync = function() return nil end,
					SetAsync = function() end,
					UpdateAsync = function(_, key, fn)
						return fn(nil)
					end,
				}
			end
		end

		if name == "Lighting" then
			service.FindFirstChildOfClass = function() return nil end
		end

		services[name] = service
	end
	return services[name]
end

local game = Instance.new("DataModel")
game.Name = "Game"
game.GetService = function(_, name)
	return getService(name)
end
game.BindToClose = function() end
game.IsLoaded = function() return true end

local workspace = getService("Workspace")

local shared = {}
local script = Instance.new("Script")
script.Name = "EggGameMain"

-- ============================================================
-- TASK
-- ============================================================

local task = {
	wait = function(t)
		-- В эмуляторе не ждём реально, просто "передаём управление"
		return 0
	end,
	spawn = function(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			print("   ⚠️  task.spawn: " .. tostring(err))
		end
	end,
	delay = function(t, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			print("   ⚠️  task.delay: " .. tostring(err))
		end
	end,
	defer = function(fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then
			print("   ⚠️  task.defer: " .. tostring(err))
		end
	end,
	cancel = function() end,
}

-- ============================================================
-- ГЛОБАЛЫ
-- ============================================================

_G.game = game
_G.workspace = workspace
_G.Workspace = workspace
_G.script = GetScriptRef and GetScriptRef() or script
_G.Instance = Instance
_G.Enum = Enum
_G.Vector3 = Vector3
_G.Vector2 = Vector2
_G.CFrame = CFrame
_G.Color3 = Color3
_G.UDim = UDim
_G.UDim2 = UDim2
_G.task = task
_G.shared = shared
_G.Random = {
	new = function()
		return {
			NextNumber = function(_, a, b)
				if a and b then
					return a + math.random() * (b - a)
				elseif a then
					return math.random() * a
				end
				return math.random()
			end,
			NextInteger = function(_, a, b)
				return math.random(a, b)
			end,
		}
	end,
}
_G.TweenInfo = {
	new = function(...) return { ... } end,
}
_G.RaycastParams = { new = function() return {} end }
_G.NumberRange = { new = function(a, b) return { Min = a, Max = b } end }

function _G.warn(...)
	local parts = {}
	for _, v in ipairs({ ... }) do
		table.insert(parts, tostring(v))
	end
	print("   ⚠️  WARN: " .. table.concat(parts, " "))
end

-- os.clock есть в Lua, time/tick добавим
_G.tick = os.clock
_G.time = os.clock
_G.wait = function(t) return 0 end
_G.spawn = function(fn) pcall(fn) end
_G.delay = function(t, fn) pcall(fn) end

print("  ✓ Roblox API заглушка загружена")
