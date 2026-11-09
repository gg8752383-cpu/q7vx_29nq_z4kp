-- LocalScript -> StarterPlayer > StarterPlayerScripts   (ТОЛЬКО клиент, серверного кода нет)
-- AIM ASSIST v14: FOV 85 | панель | режимы ENEMIES / PLAYERS / NPC | сила 0-100%
--                | Speed (только обычная ходьба) | универсальный детектор NPC и мобов
--                | ESP-контур игроков и NPC (Highlight, только то, что видно) | осветление | классический стик побольше, выше и правее | левая половина экрана без камеры | модули с безопасным отключением
--
-- СОХРАНЕНИЕ НАСТРОЕК:
--   * Если в среде есть writefile/readfile (экзекутор вроде Delta), все настройки панели
--     сами сохраняются в файл workspace/Delta/AimAssist_config.json и загружаются при следующем запуске.
--     Папка создаётся автоматически. Если вложенную папку создать нельзя, файл кладётся в корень workspace.
--   * Нет файловых функций -> используется серверный Script AimPanelSettingsServer
--     (ServerScriptService, DataStore, проверка данных на сервере). Клиент находит его сам.
--   * Нет ни того, ни другого -> панель честно показывает "Saving: OFF" с причиной,
--     настройки живут только в этой сессии, а значения по умолчанию берутся из CONFIG.DEFAULTS.
--   * Сохраняются все 12 настроек панели: enabled, mode, strength, lineOfSight, aimPoint, onlyWhileAiming,
--     unmarkedHostile, espPlayers, espNpcs, brighten, speedEnabled, speedValue.
--   * FOV 85 это константа CONFIG.FOV, а не настройка пользователя: он применяется при каждом запуске.
--
-- ВРАГИ (без угадывания):
--   Игроки: враг = у него есть команда, отличная от твоей. Без команды у тебя (FFA) и
--           CONFIG.FFA_WHEN_NO_TEAM = true врагами считаются другие игроки тоже без команды.
--   NPC:    враждебный, если у модели атрибут "Team" (строка) с командой, отличной от твоей,
--           ИЛИ тег "HostileNPC". Теги "AlliedNPC"/"NeutralNPC" исключают NPC.
--           NPC без метки считается нейтральным и игнорируется.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONFIG = {
	FOV = 85,
	HOLD_TIME = 2.5,            -- секунд удержания для открытия меню
	SELECT_INTERVAL = 1 / 20,   -- как часто выбирается цель (пока идёт прицеливание)
	AIM_RAMP = 0.10,            -- плавное включение подтягивания на новой цели (сек)
	AIM_SWITCH_HOLD = 0.22,     -- претендент должен быть лучше столько секунд, чтобы прицел перешёл на него
	AIM_OFFSET_SMOOTH = 0.06,   -- сглаживание смещения точки наведения (голова/торс), сек
	AIM_VEL_SMOOTH = 0.08,      -- сглаживание измеренной скорости цели, сек
	AIM_LEAD_MAX = 0.12,        -- максимум упреждения, сек
	AIM_LEAD_STUDS = 6,         -- упреждение не больше стольких студов
	AIM_MAX_SPEED = 120,        -- скорость цели для расчёта упреждения ограничивается (студов/с)
	AIM_TELEPORT = 30,          -- сдвиг цели за кадр больше этого считается телепортом: сглаживание с нуля
	AIM_DEADBAND_DEG = 0.1,     -- мёртвая зона у центра прицела (против микродрожания)
	LOS_GRACE = 0.18,           -- после потери видимости цель плавно затухает столько секунд
	LOS_NEG_CACHE = 0.15,       -- полностью закрытую цель не перепроверяем чаще
	LOS_PASS_TRANSPARENCY = 0.75, -- детали прозрачнее этого не считаются препятствием
	MAX_DISTANCE = 300,         -- студов
	FFA_WHEN_NO_TEAM = true,
	TAG_HOSTILE = "HostileNPC",
	TAG_ALLIED = "AlliedNPC",
	TAG_NEUTRAL = "NeutralNPC",
	ATTR_TEAM = "Team",
	RENDER_NAME = "AimAssistStep",
	SIDE_MARGIN = 8,            -- отступ панелей от правого края

	SWEEP_INTERVAL = 1,         -- как часто чистится/пересчитывается реестр NPC (сек)
	MOVE_CONFIRM_STUDS = 3,     -- сколько студов должен пройти моб без Humanoid, чтобы считаться живым мобом
	MOVE_WINDOW = 10,           -- за какое время (сек) отслеживается это перемещение
	CONFIRM_SCORE = 4,          -- сколько "очков структуры" нужно, чтобы модель без Humanoid считалась мобом
	MAX_MODEL_CHILDREN = 150,   -- модели крупнее (карты, здания) в детектор не берутся
	ANALYZE_INTERVAL = 3,       -- как часто пересматривается структура известной модели (сек)
	ANALYZE_PER_SWEEP = 40,     -- не больше стольких пересмотров за один проход
	VIS_PER_SWEEP = 40,         -- не больше стольких проверок прозрачности за один проход
	DEEP_SCAN = true,           -- фоновый поиск мобов без Humanoid/аниматора (порциями, без фризов)
	SCAN_BUDGET = 250,          -- сколько объектов обрабатывается за кадр при фоновом поиске
	SCAN_REST = 30,             -- пауза между полными проходами фонового поиска (сек)
	INVISIBLE_TRANSPARENCY = 0.9, -- модель, у которой все части прозрачнее, считается невидимой
	AIM_AT_INVISIBLE = false,   -- наводиться ли на невидимых NPC (по умолчанию нет)

	STICK_SCALE = 1.3,          -- размер классического стика (1 = обычный)
	STICK_SHIFT_X = 30,         -- пикселей вправо
	STICK_SHIFT_Y = -30,        -- пикселей вверх (минус = выше)
	STICK_LOCK = true,          -- держать стик на своём месте, когда палец не на нём (игра сама возвращает его вниз)
	LEFT_BLOCK = 0.5,           -- доля экрана слева, которая не крутит камеру (кнопки там работают)

	-- Осветление: поднимаются только нижние пороги. Если игра уже светлее, ничего не меняется.
	-- Если всё ещё темно, увеличь MIN_AMBIENT (до ~170) и MIN_EXPOSURE (до ~1).
	MIN_AMBIENT = Color3.fromRGB(135, 135, 135),
	MIN_OUTDOOR_AMBIENT = Color3.fromRGB(135, 135, 135),
	MIN_BRIGHTNESS = 2,
	MIN_EXPOSURE = 0.5,
	CC_BRIGHTNESS = 0.06,       -- лёгкий подъём теней отдельным эффектом
	CC_CONTRAST = 0.08,
	REMOVE_FOG = true,          -- убирает густой туман (FogEnd меньше 50000)

	REMOTES_FOLDER = "AimPanelSettings", -- папка Load/Save, которую создаёт серверный Script
	SAVE_DEBOUNCE = 1.5,        -- пауза после последнего изменения перед сохранением (сек)
	FILE_DIR = "Delta",         -- папка внутри workspace экзекутора
	FILE_NAME = "AimAssist_config.json",

	ESP_INTERVAL = 0.4,         -- как часто сверяется набор контуров (сек)
	ESP_MAX = 30,               -- лимит Roblox: одновременно рисуется не больше 31 Highlight
	ESP_MAX_DISTANCE = 500,     -- дальше этого (студов) контур не рисуется
	ESP_NAME = "EspOutline",
	ESP_REQUIRE_LOS = true,     -- контур только при реальной прямой видимости (Raycast от камеры)
	ESP_LOS_INTERVAL = 0.15,    -- как часто проверяется видимость обведённых целей (сек)
	ESP_LOS_GRACE = 0.2,        -- после потери видимости контур держится столько секунд (без мерцания)
	ESP_RAY_PARTS = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" },
	SELECT_IDLE_INTERVAL = 0.3, -- выбор цели, пока никто не целится (экономия лучей)
	ESP_PLAYER_COLOR = Color3.fromRGB(255, 255, 255),
	ESP_NPC_COLOR = Color3.fromRGB(255, 120, 120),

	SPEED_MIN = 8,
	SPEED_MAX = 50,
	SPEED_TICK = 0.25,          -- как часто перепроверяются статусы (оглушение и т.п.)
	-- Если у персонажа/Humanoid есть атрибут или Bool/NumberValue с таким словом в имени
	-- и значение true/больше 0, Speed не вмешивается (игра сама управляет скоростью).
	STATUS_PATTERNS = {
		"stun", "slow", "freez", "frozen", "rooted", "immobil", "ragdoll", "paraly",
		"knockback", "casting", "channel", "dash", "usingability", "grabbed", "carried",
		"trapped", "disabled",
	},

	DEFAULTS = {
		enabled = true,
		mode = "ENEMIES",       -- "ENEMIES" | "PLAYERS" | "NPC"
		strength = 50,          -- 0..100
		lineOfSight = true,     -- не наводиться через стены
		aimPoint = "Head",      -- "Head" | "Torso"
		onlyWhileAiming = true, -- помощь только пока палец крутит камеру
		unmarkedHostile = false, -- NPC без метки команды считать врагами (по умолчанию выкл.)
		espPlayers = true,      -- белый контур игроков
		espNpcs = true,         -- контур NPC
		brighten = true,        -- осветление тёмных сцен
		speedEnabled = false,
		speedValue = 20,
	},
}

local C = {
	bg = Color3.fromRGB(18, 20, 26),
	card = Color3.fromRGB(34, 37, 47),
	stroke = Color3.fromRGB(64, 70, 88),
	text = Color3.fromRGB(236, 240, 247),
	sub = Color3.fromRGB(150, 158, 175),
	accent = Color3.fromRGB(70, 160, 255),
	on = Color3.fromRGB(74, 214, 130),
	warn = Color3.fromRGB(255, 190, 70),
	off = Color3.fromRGB(120, 126, 140),
}

local state = table.clone(CONFIG.DEFAULTS)

-- общие служебные таблицы (в одной переменной, чтобы не упереться в лимит локальных переменных)
local X = {
	signal = { Humanoid = true, AnimationController = true, Animator = true, Motor6D = true, NumberValue = true, IntValue = true },
	aim = setmetatable({}, { __mode = "k" }),   -- кэш части для наведения
	pents = {},                                 -- [Player] = запись для выбора цели (без новых таблиц на каждый тик)
	retry = {},                                 -- сколько раз модуль уже самовосстанавливался
	stickConns = {},                            -- подключения к стику игры (отключаются при выходе)
	stickOrig = {},                             -- исходные размеры стика игры
	saveFails = 0,
	onEnabled = nil,
	espConns = {},                              -- [Player] = подключения CharacterAdded/Removing для ESP
	espSeen = setmetatable({}, { __mode = "k" }), -- [model] = когда цель последний раз была видна
	espFilter = {},
	espVisAcc = 0,
	espTick = 0,
	wdAcc = 0,
	espDirty = false,
}
-- Прошлый запуск завершается СРАЗУ и целиком (иначе его отложенный destroy снимал шаг рендера нового).
X.registry = (type(shared) == "table" and shared) or _G
X.renderName = CONFIG.RENDER_NAME .. "_" .. string.sub(game:GetService("HttpService"):GenerateGUID(false), 1, 8)
X.espParams = RaycastParams.new()
X.espParams.FilterType = Enum.RaycastFilterType.Exclude
X.espParams.RespectCanCollide = true
X.espParams.IgnoreWater = true
do
	local prev = X.registry.__AimAssistShutdown
	if type(prev) == "function" then
		pcall(prev)
	end
	X.registry.__AimAssistShutdown = nil
end

---------------------------------------------------------------- служебное: очистка, защита модулей
local connections = {}
local destroyed = false
local uiRefreshers = {}
local sliders = {}

local function track(conn)
	connections[#connections + 1] = conn
	return conn
end

-- Каждый модуль изолирован: при повторяющихся ошибках он отключается сам,
-- остальные функции продолжают работать.
local moduleOk = { aim = true, speed = true, esp = true, light = true, scan = true, stick = true }
local errCount = {}
local onModuleDisabled = nil

local function guarded(name, fn)
	return function(...)
		if not moduleOk[name] then
			return
		end
		local ok, err = pcall(fn, ...)
		if ok then
			errCount[name] = 0
			return
		end
		errCount[name] = (errCount[name] or 0) + 1
		warn(("[Panel:%s] %s"):format(name, tostring(err)))
		if errCount[name] >= 3 then
			moduleOk[name] = false
			warn(("[Panel:%s] модуль отключён после повторных ошибок, остальные функции работают"):format(name))
			if onModuleDisabled then
				onModuleDisabled(name)
			end
			-- самовосстановление: временная ошибка (респавн, стриминг) не должна отключать функцию навсегда
			X.retry[name] = (X.retry[name] or 0) + 1
			if X.retry[name] <= 3 then
				task.delay(20 * X.retry[name], function()
					if destroyed or moduleOk[name] then
						return
					end
					moduleOk[name] = true
					errCount[name] = 0
					warn(("[Panel:%s] модуль включён снова (попытка %d)"):format(name, X.retry[name]))
					if X.onEnabled then
						X.onEnabled(name)
					end
				end)
			end
		end
	end
end

---------------------------------------------------------------- сохранение настроек (через серверный Script + DataStore)
local SANITIZE = {
	enabled = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	mode = function(v)
		if v == "ENEMIES" or v == "PLAYERS" or v == "NPC" then
			return v
		end
	end,
	strength = function(v)
		if type(v) == "number" and v == v then
			return math.clamp(math.floor(v + 0.5), 0, 100)
		end
	end,
	lineOfSight = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	aimPoint = function(v)
		if v == "Head" or v == "Torso" then
			return v
		end
	end,
	onlyWhileAiming = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	unmarkedHostile = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	speedEnabled = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	speedValue = function(v)
		if type(v) == "number" and v == v then
			return math.clamp(math.floor(v + 0.5), CONFIG.SPEED_MIN, CONFIG.SPEED_MAX)
		end
	end,
	espPlayers = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	espNpcs = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	brighten = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
}

local persist = {
	available = false, -- серверный Script найден
	loaded = false,    -- сохранённые данные успешно получены (без этого сохранять нельзя)
	saveFn = nil,
	backend = nil,     -- "file" (writefile) или "server" (DataStore)
	touched = {},      -- что игрок менял до окончания загрузки (загрузка этого не перезапишет)
	token = 0,
	dirty = false,
	inFlight = false,
	again = false,
}
local persistListener = nil

local function diag(text, kind)
	if kind == "warn" then
		warn("[Panel] " .. text)
	else
		print("[Panel] " .. text)
	end
	if persistListener then
		persistListener(text, kind)
	end
end

-- файловое сохранение через функции экзекутора (одна таблица, чтобы не упереться в лимит локальных переменных)
local FS = {
	http = game:GetService("HttpService"),
	path = CONFIG.FILE_DIR .. "/" .. CONFIG.FILE_NAME,
}

do
	local function try(getter)
		local ok, fn = pcall(getter)
		if ok and type(fn) == "function" then
			return fn
		end
		return nil
	end
	FS.write = try(function() return writefile end)
	FS.read = try(function() return readfile end)
	FS.isfile = try(function() return isfile end)
	FS.makefolder = try(function() return makefolder end)
	FS.isfolder = try(function() return isfolder end)
end

function FS.ensureFolder()
	if not FS.makefolder then
		return
	end
	local exists = false
	if FS.isfolder then
		local ok, res = pcall(FS.isfolder, CONFIG.FILE_DIR)
		exists = ok and res == true
	end
	if not exists then
		pcall(FS.makefolder, CONFIG.FILE_DIR)
	end
end

function FS.exists(path)
	if FS.isfile then
		local ok, res = pcall(FS.isfile, path)
		return ok and res == true
	end
	return true -- неизвестно: попробуем прочитать
end

function FS.readText()
	for _, path in ipairs({ CONFIG.FILE_DIR .. "/" .. CONFIG.FILE_NAME, CONFIG.FILE_NAME }) do
		if FS.exists(path) then
			local ok, text = pcall(FS.read, path)
			if ok and type(text) == "string" and text ~= "" then
				return text
			end
		end
	end
	return nil
end

function FS.writeText(text)
	FS.ensureFolder()
	local nested = CONFIG.FILE_DIR .. "/" .. CONFIG.FILE_NAME
	if pcall(FS.write, nested, text) then
		FS.path = nested
		return true
	end
	if pcall(FS.write, CONFIG.FILE_NAME, text) then
		FS.path = CONFIG.FILE_NAME
		return true
	end
	return false
end

local function collectSettings()
	local out = {}
	for key in pairs(SANITIZE) do
		out[key] = state[key]
	end
	return out
end

local scheduleSave

local function flushSave()
	if not persist.available or not persist.loaded then
		return
	end
	if persist.backend == "file" then
		persist.dirty = false
		local okEnc, json = pcall(function()
			return FS.http:JSONEncode(collectSettings())
		end)
		if okEnc and FS.writeText(json) then
			X.saveFails = 0
			diag("Saved to " .. FS.path .. " " .. os.date("%H:%M:%S"), "ok")
		else
			persist.dirty = true
			X.saveFails += 1
			diag("Save failed: could not write the file (will retry)", "warn")
			scheduleSave(math.min(15 * 2 ^ (X.saveFails - 1), 120))
			return
		end
		X.saveFails = 0
		return
	end
	if not persist.saveFn then
		return
	end
	if persist.inFlight then
		persist.again = true
		return
	end
	persist.inFlight = true
	persist.dirty = false
	local payload = collectSettings()
	task.spawn(function()
		local ok, res = pcall(function()
			return persist.saveFn:InvokeServer(payload)
		end)
		persist.inFlight = false
		if destroyed then
			return
		end
		if ok and type(res) == "table" and res.ok == true then
			diag("Saved " .. os.date("%H:%M:%S"), "ok")
			if persist.again or persist.dirty then
				persist.again = false
				scheduleSave()
			end
		else
			persist.dirty = true
			local reason = (ok and type(res) == "table" and res.reason) or tostring(res)
			diag("Save failed: " .. tostring(reason) .. " (will retry)", "warn")
			scheduleSave(reason == "throttled" and 4 or 15)
		end
	end)
end

scheduleSave = function(delay)
	persist.dirty = true
	if not persist.available or not persist.loaded then
		return
	end
	persist.token += 1
	local tok = persist.token
	task.delay(delay or CONFIG.SAVE_DEBOUNCE, function()
		if tok == persist.token and not destroyed then
			flushSave()
		end
	end)
end

local function commit(key)
	persist.touched[key] = true
	scheduleSave()
end

local function refreshUI()
	for _, fn in ipairs(uiRefreshers) do
		fn()
	end
end

---------------------------------------------------------------- FOV 85
local fovCam, fovConn, fovOriginal = nil, nil, nil
local fovDepth = 0
local fovGaveUp = false

local function releaseFov(restore)
	if fovConn then
		fovConn:Disconnect()
		fovConn = nil
	end
	if restore and fovCam and fovOriginal and fovCam.Parent then
		fovCam.FieldOfView = fovOriginal
	end
	fovCam = nil
	fovOriginal = nil
end

local function lockFov()
	if fovGaveUp then
		return
	end
	local cam = Workspace.CurrentCamera
	if cam == fovCam and fovConn then
		return
	end
	releaseFov(true)
	if not cam then
		return
	end
	fovCam = cam
	fovOriginal = cam.FieldOfView

	local function apply()
		if math.abs(cam.FieldOfView - CONFIG.FOV) <= 0.01 then
			return
		end
		-- защита от "перетягивания каната" с другим скриптом, который тоже меняет FOV
		if fovDepth >= 6 then
			warn("[Panel] Другой скрипт постоянно меняет FOV. Блокировка FOV отключена.")
			fovGaveUp = true
			releaseFov(false)
			return
		end
		fovDepth += 1
		cam.FieldOfView = CONFIG.FOV
		fovDepth -= 1
	end

	apply()
	if not fovGaveUp then
		fovConn = cam:GetPropertyChangedSignal("FieldOfView"):Connect(apply)
	end
end

local function refreshFov()
	if destroyed then
		return
	end
	if state.enabled then
		lockFov()
	else
		releaseFov(true)
	end
end

track(Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(refreshFov))

---------------------------------------------------------------- команды и цели
local target = nil -- { model, entity, part, kind, name, score, dist }
local paused = false
local acc = 0
local statusListener = nil
local lastStatusText = ""

local function computeStatus()
	if not state.enabled then
		return "OFF", C.off
	end
	if not moduleOk.aim then
		return "UNAVAILABLE", C.off
	end
	if paused then
		return "PAUSED", C.warn
	end
	if state.strength <= 0 then
		return "ON · strength 0%", C.warn
	end
	if target then
		return ("LOCKED · %s · %d studs"):format(target.name, math.floor(target.dist / 5 + 0.5) * 5), C.on
	end
	return "ON · searching", C.accent
end

local function notifyStatus()
	local text, color = computeStatus()
	if text ~= lastStatusText then
		lastStatusText = text
		if statusListener then
			statusListener(text, color)
		end
	end
end

local function teamOf(p)
	if p.Neutral then
		return nil
	end
	return p.Team
end

local function isEnemyPlayer(other)
	if other == localPlayer then
		return false
	end
	local myTeam = teamOf(localPlayer)
	local theirTeam = teamOf(other)
	if myTeam == nil then
		return CONFIG.FFA_WHEN_NO_TEAM and theirTeam == nil
	end
	return theirTeam ~= nil and theirTeam ~= myTeam
end

local function isHostileNpc(model)
	if CollectionService:HasTag(model, CONFIG.TAG_ALLIED) or CollectionService:HasTag(model, CONFIG.TAG_NEUTRAL) then
		return false
	end
	local npcTeam = model:GetAttribute(CONFIG.ATTR_TEAM)
	if typeof(npcTeam) == "string" and npcTeam ~= "" then
		local myTeam = teamOf(localPlayer)
		return npcTeam ~= (myTeam and myTeam.Name or "")
	end
	if CollectionService:HasTag(model, CONFIG.TAG_HOSTILE) then
		return true
	end
	return state.unmarkedHostile -- метки нет: решает переключатель в панели
end

local function findPart(model, names)
	for _, n in ipairs(names) do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local HEAD_FIRST = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
local TORSO_FIRST = { "UpperTorso", "Torso", "HumanoidRootPart", "Head" }

local function getAimPart(model)
	local mode = state.aimPoint
	local now = os.clock()
	local cached = X.aim[model]
	if cached and cached.mode == mode and now < cached.expires and cached.part.Parent == model then
		return cached.part
	end
	local part = findPart(model, mode == "Head" and HEAD_FIRST or TORSO_FIRST)
	if part then
		X.aim[model] = { mode = mode, part = part, expires = now + 2 }
		return part
	end
	X.aim[model] = nil
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	-- нестандартные персонажи: любая часть модели
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function isAlive(humanoid)
	return humanoid.Parent ~= nil
		and humanoid.Health > 0
		and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

---------------------------------------------------------------- универсальный детектор NPC и мобов
-- Распознавание по СТРУКТУРЕ, а не по названию модели. Очки структуры:
--   Humanoid (не игрок)                                   -> NPC сразу;
--   AnimationController/Animator                          +2
--   суставы Motor6D: от 3 штук +2, от 1 штуки +1
--   "план тела": есть часть Head и часть Torso/UpperTorso/LowerTorso/HumanoidRootPart +2
--     (это общие названия частей стандартных риггов Roblox, а не названия мобов)
--   число здоровья (Health/HP: атрибут или NumberValue)   +2, но только если уже есть другие признаки
--   перемещалась сама (>= MOVE_CONFIRM_STUDS за MOVE_WINDOW сек) +3
--   Seat/VehicleSeat                                      -> не моб (техника, мебель)
-- Моб = очков >= CONFIRM_SCORE. Поэтому ложных срабатываний меньше:
--   ломаемый предмет с одним Health (2 очка) мобом не считается,
--   анимированная декорация без движения (2 очка) тоже,
--   а рига без Humanoid с суставами и телом (4 очка) или ходячая модель с аниматором (5 очков) считаются.
-- Обновление списка: события DescendantAdded (новые, респавн, стриминг), фоновый поиск порциями
--   по SCAN_BUDGET объектов за кадр, очистка исчезнувших раз в SWEEP_INTERVAL.
-- Невидимые NPC (все части почти прозрачные) находятся и помечаются; прицел их по умолчанию пропускает.
-- Если сервер вообще не отправляет объект клиенту (скрыт стримингом или не реплицируется), клиент его увидеть не может.
local entities = {} -- [model] = { model, humanoid, sig, score, confirmed, reason, moved, invisible, ... }
local dirty = {}    -- модели, структуру которых нужно переанализировать
local detectorUiHook = nil
local sweepAcc = 0

local HEALTH_NAMES = { "health", "hp", "currenthealth", "curhealth", "hitpoints" }
local DEAD_NAMES = { "dead", "isdead", "died" }
local TORSO_NAMES = { torso = true, uppertorso = true, lowertorso = true, humanoidrootpart = true }

local function nameIn(list, name)
	local lower = string.lower(name)
	for _, n in ipairs(list) do
		if lower == n then
			return true
		end
	end
	return false
end

-- возвращает число здоровья или nil, если у модели нет понятного здоровья
local function readHealth(e)
	local m = e.model
	local inst = e.healthInst
	if inst then
		if inst.Parent then
			local ok, v = pcall(function()
				return inst.Value
			end)
			if ok and type(v) == "number" then
				return v
			end
		end
		e.healthInst = nil
	end
	local attr = e.healthAttr
	if attr then
		local v = m:GetAttribute(attr)
		if type(v) == "number" then
			return v
		end
		e.healthAttr = nil
	end
	local now = os.clock()
	if e.noHealthUntil and now < e.noHealthUntil then
		return nil
	end
	for name, v in pairs(m:GetAttributes()) do
		if type(v) == "number" and nameIn(HEALTH_NAMES, name) then
			e.healthAttr = name
			return v
		end
	end
	for _, c in ipairs(m:GetChildren()) do
		if (c:IsA("NumberValue") or c:IsA("IntValue")) and nameIn(HEALTH_NAMES, c.Name) then
			e.healthInst = c
			return c.Value
		end
	end
	e.noHealthUntil = now + 2
	return nil
end

local function markedDead(model)
	for _, n in ipairs(DEAD_NAMES) do
		if model:GetAttribute(n) == true then
			return true
		end
	end
	return false
end

local function entityAlive(e)
	local m = e.model
	if not m.Parent or not m:IsDescendantOf(Workspace) then
		return false
	end
	local h = e.humanoid
	if h then
		return isAlive(h)
	end
	if not e.confirmed or markedDead(m) then
		return false
	end
	local hp = readHealth(e)
	if hp ~= nil then
		return hp > 0
	end
	return true -- здоровья нет: считаем живым, пока моб на месте и не помечен как мёртвый
end

local function isIgnoredModel(model)
	if model == Workspace or model == localPlayer.Character then
		return true
	end
	if Players:GetPlayerFromCharacter(model) then
		return true
	end
	if model:FindFirstAncestorWhichIsA("Camera") then
		return true
	end
	return false
end

-- собирает признаки структуры модели (один уровень вложенности + суставы в частях)
local function analyze(model)
	local sig = { animator = false, joints = 0, head = false, torso = false, health = false, seat = false, humanoid = nil }
	local children = model:GetChildren()
	local n = #children
	if n > CONFIG.MAX_MODEL_CHILDREN then
		sig.tooBig = true
		return sig, n
	end
	for _, c in ipairs(children) do
		local cls = c.ClassName
		if cls == "Humanoid" then
			sig.humanoid = c
		elseif cls == "AnimationController" or cls == "Animator" then
			sig.animator = true
		elseif cls == "Seat" or cls == "VehicleSeat" then
			sig.seat = true
		elseif c:IsA("BasePart") then
			local lname = string.lower(c.Name)
			if lname == "head" then
				sig.head = true
			elseif TORSO_NAMES[lname] then
				sig.torso = true
			end
			for _, j in ipairs(c:GetChildren()) do
				if j.ClassName == "Motor6D" then
					sig.joints += 1
				end
			end
		elseif (cls == "NumberValue" or cls == "IntValue") and nameIn(HEALTH_NAMES, c.Name) then
			sig.health = true
		end
	end
	if not sig.health then
		for name, v in pairs(model:GetAttributes()) do
			if type(v) == "number" and nameIn(HEALTH_NAMES, name) then
				sig.health = true
				break
			end
		end
	end
	return sig, n
end

local function scoreOf(sig, moved)
	if sig.seat then
		return -10
	end
	local score = 0
	if sig.animator then
		score += 2
	end
	if sig.joints >= 3 then
		score += 2
	elseif sig.joints >= 1 then
		score += 1
	end
	if sig.head and sig.torso then
		score += 2
	end
	if sig.health and score > 0 then
		score += 2
	end
	if moved then
		score += 3
	end
	return score
end

-- создаёт/обновляет запись о модели; возвращает запись (или nil) и объём проделанной работы
local function evaluateModel(model)
	if isIgnoredModel(model) then
		entities[model] = nil
		return nil, 1
	end
	local sig, work = analyze(model)
	local e = entities[model]
	if sig.tooBig then
		return e, work
	end
	if sig.humanoid then
		if not e then
			e = { model = model }
			entities[model] = e
		end
		e.humanoid = sig.humanoid
		e.sig = sig
		e.score = 99
		e.confirmed = true
		e.reason = "humanoid"
		return e, work
	end
	local score = scoreOf(sig, e and e.moved)
	if not e then
		if score < 2 then
			return nil, work
		end
		e = { model = model }
		entities[model] = e
	elseif score < 2 then
		entities[model] = nil -- признаки пропали (труп, разобранная модель)
		return nil, work
	end
	e.humanoid = nil
	e.sig = sig
	e.score = score
	e.confirmed = score >= CONFIG.CONFIRM_SCORE
	e.reason = e.confirmed and "structure" or nil
	return e, work
end

local function modelOfSignal(inst)
	local cls = inst.ClassName
	local parent = inst.Parent
	if not parent then
		return nil
	end
	if cls == "Animator" and (parent.ClassName == "Humanoid" or parent.ClassName == "AnimationController") then
		parent = parent.Parent
	elseif cls == "Motor6D" then
		parent = parent.Parent -- сустав лежит в части, часть лежит в модели
	end
	if parent and parent:IsA("Model") then
		return parent
	end
	return nil
end

local function registerInstance(inst)
	local cls = inst.ClassName
	if not X.signal[cls] then
		return -- большинство добавляемых объектов (снаряды, частицы, детали) нас не интересует
	end
	if cls == "Humanoid" then
		local model = modelOfSignal(inst)
		if model then
			evaluateModel(model)
		end
	elseif cls == "AnimationController" or cls == "Animator" or cls == "Motor6D"
		or ((cls == "NumberValue" or cls == "IntValue") and nameIn(HEALTH_NAMES, inst.Name)) then
		local model
		if cls == "NumberValue" or cls == "IntValue" then
			model = inst.Parent
		else
			model = modelOfSignal(inst)
		end
		if model and model:IsA("Model") then
			dirty[model] = true -- структура может ещё собираться, разберём на ближайшем проходе
		end
	end
end

track(Workspace.DescendantAdded:Connect(registerInstance))
track(Players.PlayerRemoving:Connect(function(p)
	X.pents[p] = nil
	local list = X.espConns[p]
	if list then
		for _, c in ipairs(list) do
			c:Disconnect()
		end
		X.espConns[p] = nil
	end
	X.espDirty = true
end))

-- Контур игрока обновляется сразу при входе, выходе, смерти и возрождении (а не ждёт опроса).
do
	local function hookPlayer(p)
		if p == localPlayer or X.espConns[p] then
			return
		end
		X.espConns[p] = {
			p.CharacterAdded:Connect(function()
				X.espDirty = true
			end),
			p.CharacterRemoving:Connect(function()
				X.espDirty = true
			end),
		}
	end
	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	track(Players.PlayerAdded:Connect(function(p)
		hookPlayer(p)
		X.espDirty = true
	end))
end

-- первичный и периодический фоновый поиск порциями (без больших снимков карты)
local function deepScanLoop()
	while not destroyed do
		local queue = Workspace:GetChildren()
		local qi = 1
		local budget = 0
		while qi <= #queue do
			if destroyed then
				return
			end
			local inst = queue[qi]
			queue[qi] = false
			qi += 1
			if inst and inst.Parent then
				local cls = inst.ClassName
				if cls == "Model" then
					if not isIgnoredModel(inst) then
						local okE, _, work = pcall(evaluateModel, inst)
						budget += (okE and work) or 1
						local kids = inst:GetChildren()
						budget += #kids
						for _, c in ipairs(kids) do
							local ccls = c.ClassName
							if ccls == "Model" or ccls == "Folder" then
								queue[#queue + 1] = c
							end
						end
					end
				elseif cls == "Folder" then
					local kids = inst:GetChildren()
					budget += #kids + 1
					for _, c in ipairs(kids) do
						local ccls = c.ClassName
						if ccls == "Model" or ccls == "Folder" then
							queue[#queue + 1] = c
						end
					end
				end
			end
			if budget >= CONFIG.SCAN_BUDGET then
				budget = 0
				task.wait()
			end
		end
		task.wait(CONFIG.SCAN_REST)
	end
end

if CONFIG.DEEP_SCAN then
	task.spawn(deepScanLoop)
else
	-- без фонового поиска: только разовый проход по Humanoid/аниматорам/суставам
	task.spawn(function()
		local n = 0
		for _, d in ipairs(Workspace:GetDescendants()) do
			if destroyed then
				return
			end
			registerInstance(d)
			n += 1
			if n % 4000 == 0 then
				task.wait()
			end
		end
	end)
end

-- движение подтверждает мобов, которые сами перемещаются
local function updateMovement(e, now)
	local model = e.model
	local root = e.root
	if not root or not root:IsDescendantOf(model) then
		root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		e.root = root
		e.basePos = nil
	end
	if not root then
		return
	end
	local pos = root.Position
	if not e.basePos or now - e.baseT > CONFIG.MOVE_WINDOW then
		e.basePos = pos
		e.baseT = now
	elseif (pos - e.basePos).Magnitude >= CONFIG.MOVE_CONFIRM_STUDS then
		e.moved = true
		dirty[model] = true
	end
end

local function isModelInvisible(model)
	-- быстрый путь: видимая часть почти всегда лежит прямо в модели (без снимка всех потомков)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Transparency < CONFIG.INVISIBLE_TRANSPARENCY and d.LocalTransparencyModifier < CONFIG.INVISIBLE_TRANSPARENCY then
			return false
		end
	end
	local seen = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			seen += 1
			if d.Transparency < CONFIG.INVISIBLE_TRANSPARENCY and d.LocalTransparencyModifier < CONFIG.INVISIBLE_TRANSPARENCY then
				return false
			end
			if seen >= 80 then
				break
			end
		end
	end
	return seen > 0
end

local function sweepEntities()
	local now = os.clock()

	for m in pairs(X.aim) do
		if not m.Parent then
			X.aim[m] = nil
		end
	end

	-- модели, у которых недавно появились признаки структуры
	local processed = 0
	for model in pairs(dirty) do
		dirty[model] = nil
		if model.Parent and model:IsDescendantOf(Workspace) then
			evaluateModel(model)
		end
		processed += 1
		if processed >= CONFIG.ANALYZE_PER_SWEEP then
			break
		end
	end

	local total, hostile, hidden = 0, 0, 0
	local analyzed, visChecked = 0, 0
	for model, e in pairs(entities) do
		if not model:IsDescendantOf(Workspace) or Players:GetPlayerFromCharacter(model) then
			entities[model] = nil
		else
			if analyzed < CONFIG.ANALYZE_PER_SWEEP and (not e.nextAnalyze or now >= e.nextAnalyze) then
				analyzed += 1
				e.nextAnalyze = now + CONFIG.ANALYZE_INTERVAL
				e = evaluateModel(model)
			end
			if e then
				if not e.humanoid and not e.moved then
					updateMovement(e, now)
				end
				if e.confirmed then
					if visChecked < CONFIG.VIS_PER_SWEEP and (not e.nextVis or now >= e.nextVis) then
						visChecked += 1
						e.nextVis = now + 2
						e.invisible = isModelInvisible(model)
					end
					total += 1
					if e.invisible then
						hidden += 1
					end
					if isHostileNpc(model) then
						hostile += 1
					end
				end
			end
		end
	end
	if detectorUiHook then
		detectorUiHook(total, hostile, hidden)
	end
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
losParams.RespectCanCollide = true
losParams.IgnoreWater = true

local candidates = {}
X.candN = 0
X.losFilter = {}
X.losNeg = setmetatable({}, { __mode = "k" }) -- [model] = когда цель последний раз была полностью закрыта
X.pendModel = nil                             -- претендент на смену цели
X.pendSince = 0
X.byScore = function(a, b)
	return a.score < b.score
end

local function consider(model, ent, kind, name, camPos, look, coneRad)
	if not entityAlive(ent) then
		return
	end
	if kind == "npc" and ent.invisible and not CONFIG.AIM_AT_INVISIBLE then
		return
	end
	local part = getAimPart(model)
	if not part then
		return
	end
	local delta = part.Position - camPos
	local dist = delta.Magnitude
	if dist < 1 or dist > CONFIG.MAX_DISTANCE then
		return
	end
	local angle = math.acos(math.clamp(look:Dot(delta) / dist, -1, 1))
	local limit = coneRad
	local score = angle
	if target and target.model == model then
		-- текущая цель удерживается чуть дольше (нет дёрганья между целями)
		limit = coneRad * 1.3
		score = angle * 0.6
	end
	if angle > limit then
		return
	end
	-- записи кандидатов переиспользуются: выбор цели идёт часто, мусор не создаём
	local n = X.candN + 1
	X.candN = n
	local c = candidates[n]
	if not c then
		c = {}
		candidates[n] = c
	end
	c.model = model
	c.entity = ent
	c.part = part
	c.dist = dist
	c.kind = kind
	c.name = name
	c.score = score
end

local ALT_PARTS = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" }

-- Луч от камеры до части. Прозрачные детали (стекло, невидимые барьеры) стеной не считаются:
-- такая деталь добавляется в фильтр, и луч пускается заново.
function X.clearRay(camPos, part, filter)
	for _ = 1, 4 do
		local hit = Workspace:Raycast(camPos, part.Position - camPos, losParams)
		if not hit then
			return true
		end
		local inst = hit.Instance
		if inst and inst:IsA("BasePart") and inst.ClassName ~= "Terrain"
			and inst.Transparency >= CONFIG.LOS_PASS_TRANSPARENCY then
			filter[#filter + 1] = inst
			losParams.FilterDescendantsInstances = filter
		else
			return false
		end
	end
	return false
end

-- Возвращает часть цели, которую камера реально видит (или nil, если цель полностью закрыта).
-- Частично скрытая цель: прицел переходит на любую видимую часть тела.
-- fresh = true: без кэша "закрыта" (для текущей цели, чтобы сразу заметить возвращение в поле зрения).
local function visiblePart(camPos, c, char, now, fresh)
	if not state.lineOfSight then
		return c.part
	end
	local model = c.model
	if not fresh then
		local neg = X.losNeg[model]
		if neg and now - neg < CONFIG.LOS_NEG_CACHE then
			return nil
		end
	end
	local filter = X.losFilter
	table.clear(filter)
	filter[1] = char
	filter[2] = model
	losParams.FilterDescendantsInstances = filter
	local found = nil
	if X.clearRay(camPos, c.part, filter) then
		found = c.part
	else
		for _, n in ipairs(ALT_PARTS) do
			local p = model:FindFirstChild(n)
			if p and p ~= c.part and p:IsA("BasePart") and X.clearRay(camPos, p, filter) then
				found = p
				break
			end
		end
		if not found then
			local checked = 0
			for _, p in ipairs(model:GetChildren()) do
				if p ~= c.part and p:IsA("BasePart") then
					checked += 1
					if X.clearRay(camPos, p, filter) then
						found = p
						break
					end
					if checked >= 6 then
						break
					end
				end
			end
		end
	end
	if found then
		X.losNeg[model] = nil
		return found
	end
	X.losNeg[model] = now
	return nil
end

-- Текущая цель остаётся той же: состояние сглаживания и предсказания сохраняется.
function X.keepTarget(t, c, part)
	t.part = part
	t.dist = c.dist
	t.score = c.score
	t.name = c.name
	t.lostAt = nil
end

function X.newTarget(c, part)
	local model = c.model
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (root and root:IsA("BasePart")) then
		root = part
	end
	target = {
		model = model, entity = c.entity, part = part, kind = c.kind, name = c.name,
		score = c.score, dist = c.dist,
		anchor = root,   -- корень: по нему меряем скорость (без анимационной тряски головы)
		ramp = 0,        -- плавный вход в подтягивание
		fade = 1,        -- плавный выход при потере видимости
		lostAt = nil,
		init = false,
	}
	X.pendModel = nil
end

local function selectTarget(cam)
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not cam or not char or not hum or hum.Health <= 0 then
		paused = true
		target = nil
		X.pendModel = nil
		return
	end
	paused = false
	if not state.enabled or state.strength <= 0 then
		target = nil
		X.pendModel = nil
		return
	end

	X.candN = 0
	local cf = cam.CFrame
	local camPos, look = cf.Position, cf.LookVector
	local coneRad = math.rad(5 + 15 * (state.strength / 100))
	local mode = state.mode

	if mode ~= "NPC" then
		for _, p in ipairs(Players:GetPlayers()) do
			if isEnemyPlayer(p) then
				local c = p.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				if c and h then
					local pe = X.pents[p]
					if not pe then
						pe = {}
						X.pents[p] = pe
					end
					pe.model = c
					pe.humanoid = h
					consider(c, pe, "player", p.DisplayName, camPos, look, coneRad)
				end
			end
		end
	end

	if mode ~= "PLAYERS" then
		for model, e in pairs(entities) do
			if e.confirmed and model ~= char and not Players:GetPlayerFromCharacter(model) and isHostileNpc(model) then
				consider(model, e, "npc", model.Name, camPos, look, coneRad)
			end
		end
	end

	for i = #candidates, X.candN + 1, -1 do
		candidates[i] = nil
	end
	table.sort(candidates, X.byScore)

	local now = os.clock()
	local cur = target
	local curIdx = nil
	if cur then
		for i = 1, #candidates do
			if candidates[i].model == cur.model then
				curIdx = i
				break
			end
		end
	end

	-- 1. Текущая цель: видна ли она сейчас.
	local curPart = curIdx and visiblePart(camPos, candidates[curIdx], char, now, true) or nil

	-- 2. Претендент: если текущая видна, это цель, подходящая лучше (стоит в списке раньше);
	--    если текущей нет или она потеряна, это лучшая видимая из первых трёх.
	local chal, chalPart = nil, nil
	local limit = (curIdx and curPart) and math.min(curIdx - 1, 3) or math.min(#candidates, 3)
	for i = 1, limit do
		local c = candidates[i]
		if not (cur and c.model == cur.model) then
			local part = visiblePart(camPos, c, char, now, false)
			if part then
				chal, chalPart = c, part
				break
			end
		end
	end

	if curPart then
		-- Текущая цель видна: меняем её только если претендент стабильно лучше AIM_SWITCH_HOLD секунд.
		X.keepTarget(cur, candidates[curIdx], curPart)
		if chal then
			if X.pendModel == chal.model then
				if now - X.pendSince >= CONFIG.AIM_SWITCH_HOLD then
					X.newTarget(chal, chalPart)
				end
			else
				X.pendModel = chal.model
				X.pendSince = now
			end
		else
			X.pendModel = nil
		end
	elseif chal then
		X.newTarget(chal, chalPart) -- текущей нет или она потеряна: берём лучшую видимую сразу
	elseif cur then
		-- Цель закрыта или вышла из зоны: подтягивание плавно затухает, затем цель отпускается.
		cur.lostAt = cur.lostAt or now
		if now - cur.lostAt >= CONFIG.LOS_GRACE then
			target = nil
			X.pendModel = nil
		end
	end
end

---------------------------------------------------------------- ввод: "игрок сейчас целится"
local aimTouches = {}
local aimCount = 0
local mouseAim = false

local function isAiming()
	if aimCount > 0 then
		-- потерянное событие TouchEnded не должно навсегда оставлять помощь включённой
		for input in pairs(aimTouches) do
			local st = input.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				aimTouches[input] = nil
				aimCount = math.max(aimCount - 1, 0)
			end
		end
	end
	return aimCount > 0 or mouseAim
end

track(UserInputService.TouchStarted:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not aimTouches[input] then
		aimTouches[input] = true
		aimCount += 1
		acc = math.huge -- цель была "в простое" реже: пересчитать сразу
	end
end))

track(UserInputService.TouchEnded:Connect(function(input)
	if aimTouches[input] then
		aimTouches[input] = nil
		aimCount = math.max(aimCount - 1, 0)
	end
end))

track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton2 then
		mouseAim = true
	end
end))

track(UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		mouseAim = false
	end
end))

track(UserInputService.WindowFocusReleased:Connect(function()
	table.clear(aimTouches)
	aimCount = 0
	mouseAim = false
end))

---------------------------------------------------------------- плавное подтягивание камеры
local function applyPull(cam, dt)
	local t = target
	if not t then
		return
	end
	local part = t.part
	if not entityAlive(t.entity) or not part.Parent then
		target = nil
		notifyStatus()
		return
	end
	local now = os.clock()

	-- Измерение: положение и скорость берём по корню модели (без анимационной тряски),
	-- смещение к голове/торсу сглаживается отдельно, поэтому смена точки прицела не даёт рывка.
	local anchor = t.anchor
	if not anchor.Parent then
		anchor = part
		t.anchor = part
		t.init = false
	end
	local rp = anchor.Position
	local offRaw = part.Position - rp
	if not t.init then
		t.init = true
		t.rp = rp
		t.rpT = now
		t.off = offRaw
		t.vel = Vector3.zero
		t.trust = 1
	else
		local mm = (rp - t.rp).Magnitude
		if mm > CONFIG.AIM_TELEPORT then
			-- телепорт или респавн: сглаживание с нуля, подтягивание включается заново плавно
			t.rp = rp
			t.rpT = now
			t.off = offRaw
			t.vel = Vector3.zero
			t.trust = 1
			t.ramp = 0
		elseif mm > 1e-4 then
			-- скорость считается по времени между реальными обновлениями позиции (устойчиво к ступенчатой репликации)
			local dtp = math.max(now - t.rpT, 1 / 120)
			local raw = (rp - t.rp) / dtp
			local sp = raw.Magnitude
			if sp > CONFIG.AIM_MAX_SPEED then
				raw = raw * (CONFIG.AIM_MAX_SPEED / sp)
				sp = CONFIG.AIM_MAX_SPEED
			end
			local a = 1 - math.exp(-dtp / CONFIG.AIM_VEL_SMOOTH)
			local vs = t.vel.Magnitude
			local agree = 1
			if vs > 3 and sp > 3 then
				agree = math.clamp(t.vel:Dot(raw) / (vs * sp), 0, 1)
			end
			-- доверие к упреждению падает при смене направления и возвращается при устойчивом движении
			t.trust += (agree * agree - t.trust) * a
			t.vel = t.vel:Lerp(raw, a)
			t.rp = rp
			t.rpT = now
		elseif now - t.rpT > 0.12 then
			t.vel = t.vel * math.exp(-dt / 0.1) -- цель встала: скорость быстро затухает
		end
		t.off = t.off:Lerp(offRaw, 1 - math.exp(-dt / CONFIG.AIM_OFFSET_SMOOTH))
	end

	local s = state.strength / 100
	local k = 9 * s ^ 1.6 -- 25%: ~1, 50%: ~3, 75%: ~5.7, 100%: 9

	-- Умеренное упреждение: компенсирует отставание плавного подтягивания, но ограничено
	-- по времени, по дальности и гаснет при смене направления. Вертикаль учитывается вдвое слабее.
	local lead = math.min(CONFIG.AIM_LEAD_MAX, 0.6 / math.max(k, 0.5))
	local v = t.vel
	local leadVec = Vector3.new(v.X, v.Y * 0.4, v.Z) * (lead * t.trust)

	local cf = cam.CFrame
	local pos = cf.Position
	local base = rp + t.off
	local dist = (base - pos).Magnitude
	if dist < 0.5 then
		return
	end
	local lm = leadVec.Magnitude
	local lmax = math.min(CONFIG.AIM_LEAD_STUDS, dist * 0.25)
	if lm > lmax then
		leadVec = leadVec * (lmax / lm)
	end
	local toTarget = base + leadVec - pos
	local tm = toTarget.Magnitude
	if tm < 0.5 then
		return
	end

	-- Вес подтягивания: плавный вход на новой цели и плавный выход при потере видимости.
	local ramp = t.ramp
	if ramp < 1 then
		ramp = math.min(1, ramp + dt / CONFIG.AIM_RAMP)
		t.ramp = ramp
	end
	local fade = t.fade
	if t.lostAt then
		fade = math.max(0, fade - dt / CONFIG.LOS_GRACE)
	elseif fade < 1 then
		fade = math.min(1, fade + dt / CONFIG.AIM_RAMP)
	end
	t.fade = fade
	local w = (ramp * ramp * (3 - 2 * ramp)) * (fade * fade * (3 - 2 * fade))
	if w < 0.002 then
		return
	end

	local dir = toTarget / tm
	local look = cf.LookVector
	local axis = look:Cross(dir)
	local axisMag = axis.Magnitude
	if axisMag < 1e-4 then
		return
	end
	local angle = math.atan2(axisMag, look:Dot(dir)) - math.rad(CONFIG.AIM_DEADBAND_DEG)
	if angle <= 0 then
		return
	end

	-- Экспоненциальное приближение зависит от dt (одинаково на любом FPS), скорость поворота ограничена.
	local maxStep = math.rad(40 + 260 * s) * dt * w
	local step = math.min(angle * (1 - math.exp(-k * w * dt)), maxStep)

	cam.CFrame = CFrame.new(pos) * CFrame.fromAxisAngle(axis / axisMag, step) * (cf - pos)
end

local aimSelectStep = guarded("aim", function(cam)
	selectTarget(cam)
	notifyStatus()
end)

local aimPullStep = guarded("aim", function(cam, dt)
	if not cam or not target or paused or not state.enabled or state.strength <= 0 then
		return
	end
	if state.onlyWhileAiming and not isAiming() then
		return
	end
	applyPull(cam, math.min(dt, 0.1))
end)

---------------------------------------------------------------- SPEED (только обычная ходьба)
-- Принципы:
--  * скорость применяется ТОЛЬКО в состоянии Running на земле;
--  * если игра сама меняет WalkSpeed (оглушение, замедление, спринт, способность),
--    модуль не вмешивается, пока скорость не вернётся к исходной;
--  * при выключении, смерти, плавании, лазании, посадке, рэгдолле и т.п. возвращается значение игры;
--  * если игра постоянно откатывает наше значение или у персонажа нет Humanoid,
--    Speed отключается сам (настройка при этом сохраняется).
local sp = {
	hum = nil,
	char = nil,
	normal = 0,        -- обычная скорость ходьбы игры
	gameValue = 0,     -- последнее значение, выставленное игрой
	lastWritten = nil, -- последнее значение, записанное нами
	applied = false,
	settleUntil = 0,
	conns = {},
	resets = {},
	token = 0,
	unsupported = false,
	reason = nil,
}
local speedUiHook = nil
local speedEvaluate = nil
local speedUnbind = nil

local function setSpeedUnsupported(reason)
	sp.unsupported = reason ~= nil
	sp.reason = reason
	if speedUiHook then
		speedUiHook()
	end
end

local function matchesStatus(name)
	local lower = string.lower(name)
	for _, pat in ipairs(CONFIG.STATUS_PATTERNS) do
		if string.find(lower, pat, 1, true) then
			return true
		end
	end
	return false
end

local function truthyValue(v)
	if type(v) == "boolean" then
		return v
	end
	if type(v) == "number" then
		return v > 0
	end
	return false
end

local function statusBlocked(inst)
	for name, value in pairs(inst:GetAttributes()) do
		if truthyValue(value) and matchesStatus(name) then
			return true
		end
	end
	for _, child in ipairs(inst:GetChildren()) do
		if child:IsA("ValueBase") and matchesStatus(child.Name) then
			local ok, v = pcall(function()
				return child.Value
			end)
			if ok and truthyValue(v) then
				return true
			end
		end
	end
	return false
end

local function speedAllowed()
	local hum, char = sp.hum, sp.char
	if not hum or not char or not hum.Parent or hum.Health <= 0 then
		return false
	end
	if hum.PlatformStand or hum.Sit then
		return false
	end
	local st = hum:GetState()
	if st ~= Enum.HumanoidStateType.Running and st ~= Enum.HumanoidStateType.RunningNoPhysics then
		return false
	end
	if sp.gameValue ~= sp.normal then
		return false -- игра сама изменила скорость
	end
	return not statusBlocked(char) and not statusBlocked(hum)
end

local function speedWrite(value)
	local hum = sp.hum
	if not hum then
		return false
	end
	local ok = pcall(function()
		hum.WalkSpeed = value
	end)
	if ok then
		sp.lastWritten = value
	else
		setSpeedUnsupported("N/A in this game")
	end
	return ok
end

local function speedEvaluateImpl()
	local hum = sp.hum
	if not hum then
		return
	end
	if not hum.Parent then
		speedUnbind()
		return
	end
	local want = state.speedEnabled and moduleOk.speed and not sp.unsupported and speedAllowed()
	if want then
		if hum.WalkSpeed ~= state.speedValue or sp.lastWritten ~= state.speedValue then
			speedWrite(state.speedValue)
		end
		sp.applied = true
	elseif sp.applied then
		-- вернуть значение игры, только если текущее значение всё ещё наше
		if sp.lastWritten ~= nil and hum.WalkSpeed == sp.lastWritten then
			speedWrite(sp.gameValue)
		end
		sp.applied = false
	end
end

speedEvaluate = guarded("speed", speedEvaluateImpl)

local function onGameSpeedChanged()
	local hum = sp.hum
	if not hum then
		return
	end
	local ws = hum.WalkSpeed
	if ws == sp.lastWritten then
		return -- это наше собственное значение
	end
	local hadApplied = sp.applied
	sp.lastWritten = nil
	sp.applied = false
	sp.gameValue = ws
	local now = os.clock()
	if now < sp.settleUntil then
		sp.normal = ws -- игра ещё выставляет стартовую скорость после появления
	end
	if hadApplied and ws == sp.normal then
		-- игра откатила наше значение; частые откаты = игра не даёт менять скорость
		sp.resets[#sp.resets + 1] = now
		while #sp.resets > 0 and now - sp.resets[1] > 3 do
			table.remove(sp.resets, 1)
		end
		if #sp.resets >= 6 then
			setSpeedUnsupported("N/A in this game")
		end
	end
	speedEvaluate()
end

speedUnbind = function()
	sp.token += 1
	for _, c in ipairs(sp.conns) do
		c:Disconnect()
	end
	table.clear(sp.conns)
	local hum = sp.hum
	if hum and sp.applied and hum.Parent and sp.lastWritten ~= nil and hum.WalkSpeed == sp.lastWritten then
		pcall(function()
			hum.WalkSpeed = sp.gameValue
		end)
	end
	sp.hum = nil
	sp.char = nil
	sp.applied = false
	sp.lastWritten = nil
	table.clear(sp.resets)
end

local function speedBind(char)
	speedUnbind()
	local tok = sp.token
	task.spawn(function()
		local hum = char:WaitForChild("Humanoid", 5)
		if tok ~= sp.token or destroyed or localPlayer.Character ~= char then
			return
		end
		if not hum or not hum:IsA("Humanoid") then
			setSpeedUnsupported("no Humanoid")
			return
		end
		setSpeedUnsupported(nil)
		sp.hum = hum
		sp.char = char
		sp.normal = hum.WalkSpeed
		sp.gameValue = hum.WalkSpeed
		sp.lastWritten = nil
		sp.applied = false
		sp.settleUntil = os.clock() + 2
		table.clear(sp.resets)

		local function eval()
			speedEvaluate()
		end
		sp.conns = {
			hum:GetPropertyChangedSignal("WalkSpeed"):Connect(onGameSpeedChanged),
			hum.StateChanged:Connect(eval),
			hum.Died:Connect(eval),
			hum.AttributeChanged:Connect(eval),
			char.AttributeChanged:Connect(eval),
			char.ChildAdded:Connect(eval),
			char.ChildRemoved:Connect(eval),
		}
		speedEvaluate()
	end)
end

track(localPlayer.CharacterAdded:Connect(speedBind))
track(localPlayer.CharacterRemoving:Connect(function()
	speedUnbind()
end))
if localPlayer.Character then
	speedBind(localPlayer.Character)
end

local speedTick = 0

---------------------------------------------------------------- главный шаг и изменения настроек
local stickBlockGui = nil

do
---------------------------------------------------------------- классический Thumbstick
-- Если игра не даёт менять режим из скрипта, выставь в StarterPlayer:
-- DevTouchMovementMode = Thumbstick
pcall(function()
	localPlayer.DevTouchMovementMode = Enum.DevTouchMovementMode.Thumbstick
end)

local hooked = setmetatable({}, { __mode = "k" })

-- Увеличиваем НАСТОЯЩИЕ размеры (рамка, кольцо, шарик), а не UIScale:
-- стандартный код считает радиус и позицию шарика в реальных пикселях,
-- а UIScale сдвигал шарик за край круга.
local function patchStick(frame)
	if hooked[frame] or not frame.Parent or not frame:IsA("GuiObject") then
		return
	end
	local outer = frame:FindFirstChild("OuterImage")
	local stick = frame:FindFirstChild("StickImage")
	if not (outer and stick and outer:IsA("GuiObject") and stick:IsA("GuiObject")) then
		warn("[Stick] неизвестная структура стика, изменение размера пропущено")
		return
	end
	if frame.Size.X.Offset <= 0 or frame.Size.Y.Offset <= 0
		or outer.Size.X.Offset <= 0 or outer.Size.Y.Offset <= 0
		or stick.Size.X.Offset <= 0 or stick.Size.Y.Offset <= 0 then
		warn("[Stick] размеры стика не в пикселях, изменение размера пропущено")
		return
	end
	hooked[frame] = true

	local rec = {
		frame = frame, fs = frame.Size, fp = frame.Position,
		outer = outer, os = outer.Size, stick = stick, ss = stick.Size,
		active = nil,        -- палец, который сейчас ведёт стик
		home = nil,          -- наше положение стика (когда палец не на нём)
		pauseUntil = 0,
		relayout = false,
	}
	X.stickOrig[#X.stickOrig + 1] = rec

	local s = CONFIG.STICK_SCALE
	local oldW = frame.Size.X.Offset
	local oldH = frame.Size.Y.Offset

	local function grow(obj)
		obj.Size = UDim2.fromOffset(obj.Size.X.Offset * s, obj.Size.Y.Offset * s)
	end
	grow(frame)
	grow(outer)
	grow(stick)

	-- растим от центра, затем сдвигаем правее и выше
	rec.offset = UDim2.fromOffset(
		-(frame.Size.X.Offset - oldW) / 2 + CONFIG.STICK_SHIFT_X,
		-(frame.Size.Y.Offset - oldH) / 2 + CONFIG.STICK_SHIFT_Y
	)
	rec.grown = frame.Size
	frame.Position = frame.Position + rec.offset
	rec.home = frame.Position

	-- Шарик в покое всегда строго по центру кольца.

	local function centerKnob()
		local target = UDim2.fromOffset(
			(frame.Size.X.Offset - stick.Size.X.Offset) / 2,
			(frame.Size.Y.Offset - stick.Size.Y.Offset) / 2
		)
		if stick.Position ~= target then
			stick.Position = target
		end
	end
	centerKnob()

	X.stickConns[#X.stickConns + 1] = frame.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or rec.active then
			return
		end
		rec.active = input
		input.Changed:Connect(function()
			local st = input.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				if rec.active == input then
					rec.active = nil
				end
				task.defer(centerKnob)
			end
		end)
	end)

	X.stickConns[#X.stickConns + 1] = stick:GetPropertyChangedSignal("Position"):Connect(function()
		if rec.active then
			local st = rec.active.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				rec.active = nil
			end
		end
		if not rec.active then
			centerKnob()
		end
	end)

	-- Поворот экрана / перестройка интерфейса игрой: пересчитать "своё" положение чуть позже.
	local parent = frame.Parent
	if parent and parent:IsA("GuiObject") then
		X.stickConns[#X.stickConns + 1] = parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			rec.relayout = true
			rec.pauseUntil = os.clock() + 0.5
		end)
	end
end

-- Стандартный код Roblox после отпускания пальца возвращает стик на родное место внизу.
-- Пока палец не на стике, возвращаем его на своё место; пока палец на стике, не мешаем.
function X.stickEnforce()
	if not CONFIG.STICK_LOCK then
		return
	end
	local now = os.clock()
	for _, rec in ipairs(X.stickOrig) do
		local f = rec.frame
		if f.Parent then
			local act = rec.active
			if act then
				local st = act.UserInputState
				if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
					rec.active = nil -- потерянное событие End
				end
			end
			if not rec.active and now >= rec.pauseUntil then
				if rec.relayout then
					rec.relayout = false
					if f.Size ~= rec.grown then
						-- игра вернула обычный размер: растим заново и заново считаем сдвиг
						f.Size = rec.grown
						rec.home = f.Position + rec.offset
					elseif f.Position ~= rec.home then
						-- размер наш, положение игра пересчитала: добавляем только сдвиг вправо/вверх
						rec.home = f.Position + UDim2.fromOffset(CONFIG.STICK_SHIFT_X, CONFIG.STICK_SHIFT_Y)
					end
				end
				if f.Position ~= rec.home then
					f.Position = rec.home
				end
			end
		end
	end
end
X.stickGuarded = guarded("stick", X.stickEnforce)

local function hookControlFrame(controlFrame)
	if hooked[controlFrame] then
		return
	end
	hooked[controlFrame] = true
	for _, d in ipairs(controlFrame:GetDescendants()) do
		if d.Name == "ThumbstickFrame" then
			patchStick(d)
		end
	end
	X.stickConns[#X.stickConns + 1] = controlFrame.DescendantAdded:Connect(function(d)
		if d.Name == "ThumbstickFrame" then
			task.defer(patchStick, d)
		end
	end)
end

local function hookTouchGui(gui)
	if gui.Name ~= "TouchGui" or not gui:IsA("ScreenGui") or hooked[gui] then
		return
	end
	hooked[gui] = true
	local controlFrame = gui:FindFirstChild("TouchControlFrame")
	if controlFrame then
		hookControlFrame(controlFrame)
	end
	X.stickConns[#X.stickConns + 1] = gui.ChildAdded:Connect(function(child)
		if child.Name == "TouchControlFrame" then
			hookControlFrame(child)
		end
	end)
end

if UserInputService.TouchEnabled then
	local existing = playerGui:FindFirstChild("TouchGui")
	if existing then
		hookTouchGui(existing)
	end
	track(playerGui.ChildAdded:Connect(hookTouchGui))
end

---------------------------------------------------------------- левая сторона не крутит камеру
-- Прозрачная панель ПОД всеми интерфейсами (DisplayOrder -100): пустое место
-- слева поглощает касание, камера его не видит; стик и любые кнопки лежат
-- выше и работают. Каждый палец обрабатывается отдельно (мультитач).
if UserInputService.TouchEnabled then
	local old = playerGui:FindFirstChild("LeftSideBlocker")
	if old then
		old:Destroy()
	end

	local blockGui = Instance.new("ScreenGui")
	blockGui.Name = "LeftSideBlocker"
	blockGui.ResetOnSpawn = false
	blockGui.IgnoreGuiInset = true
	blockGui.DisplayOrder = -100
	blockGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local blocker = Instance.new("Frame")
	blocker.Name = "Blocker"
	blocker.BackgroundTransparency = 1
	blocker.BorderSizePixel = 0
	blocker.Active = true
	blocker.Size = UDim2.new(CONFIG.LEFT_BLOCK, 0, 1, 0)
	blocker.Parent = blockGui
	blockGui.Parent = playerGui
	stickBlockGui = blockGui
end

end

---------------------------------------------------------------- ESP: тонкий контур игроков и NPC
-- Один Highlight на цель, без циклов на каждую цель: один общий проход раз в ESP_INTERVAL.
-- DepthMode = Occluded: контур рисуется только на видимых частях тела, за стенами его нет.
-- Заливки нет (FillTransparency = 1), цвет контура белый (игроки) / мягкий красный (NPC).
local espMap = {} -- [model] = Highlight

local function espRemove(model)
	local h = espMap[model]
	if h then
		espMap[model] = nil
		h:Destroy()
	end
end

local function espClear()
	for model in pairs(espMap) do
		espRemove(model)
	end
end

-- Прямая видимость: луч от камеры до части не должен упереться в препятствие.
function X.rayClear(camPos, part)
	local delta = part.Position - camPos
	if delta.Magnitude < 3 then
		return true
	end
	return Workspace:Raycast(camPos, delta, X.espParams) == nil
end

function X.espVisible(camPos, char, model)
	local filter = X.espFilter
	table.clear(filter)
	if char then
		filter[1] = char
	end
	filter[#filter + 1] = model
	X.espParams.FilterDescendantsInstances = filter
	local tried = 0
	for _, n in ipairs(CONFIG.ESP_RAY_PARTS) do
		local part = model:FindFirstChild(n)
		if part and part:IsA("BasePart") then
			tried += 1
			if X.rayClear(camPos, part) then
				return true
			end
			if tried >= 3 then
				break
			end
		end
	end
	if tried == 0 then
		-- нестандартная модель: проверяем главную или любую часть
		local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if part and X.rayClear(camPos, part) then
			return true
		end
	end
	-- торчащая из-за угла рука или нога тоже считается видимостью
	local extra = 0
	for _, part in ipairs(model:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "Head" and part.Name ~= "HumanoidRootPart" and part.Name ~= "Torso"
			and part.Name ~= "UpperTorso" and part.Name ~= "LowerTorso" then
			extra += 1
			if X.rayClear(camPos, part) then
				return true
			end
			if extra >= 1 then
				break
			end
		end
	end
	return false
end

-- Включает контур только у целей, которых реально видно (Raycast). AlwaysOnTop не используется.
function X.espUpdate()
	if next(espMap) == nil then
		return
	end
	local cam = Workspace.CurrentCamera
	local useLos = CONFIG.ESP_REQUIRE_LOS and cam ~= nil
	local camPos = useLos and cam.CFrame.Position or nil
	local char = localPlayer.Character
	local now = os.clock()
	X.espTick += 1
	for model, h in pairs(espMap) do
		local vis = true
		if useLos then
			local seen = X.espSeen[model]
			local hidden = not seen or now - seen > CONFIG.ESP_LOS_GRACE
			-- скрытых NPC проверяем вдвое реже; игроки всегда с полной частотой
			if not (hidden and X.espTick % 2 == 0 and not Players:GetPlayerFromCharacter(model)) then
				if X.espVisible(camPos, char, model) then
					X.espSeen[model] = now
				end
			end
			vis = (now - (X.espSeen[model] or -1e9)) <= CONFIG.ESP_LOS_GRACE
		end
		if h.Enabled ~= vis then
			h.Enabled = vis
		end
	end
end

local espWant = {}
local espList = {}

local function espReconcile()
	if not state.espPlayers and not state.espNpcs then
		if next(espMap) ~= nil then
			espClear()
		end
		return
	end

	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local char = localPlayer.Character
	table.clear(espWant)
	table.clear(espList)

	local function add(model, kind)
		local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if not root then
			return
		end
		local dist = (root.Position - camPos).Magnitude
		if dist > CONFIG.ESP_MAX_DISTANCE then
			return
		end
		if espMap[model] then
			dist *= 0.85 -- уже обведённые держатся чуть дольше: нет мерцания на границе лимита
		end
		espList[#espList + 1] = { model = model, kind = kind, dist = dist }
	end

	if state.espPlayers then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= localPlayer then
				local c = p.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				if c and h and c:IsDescendantOf(Workspace) and isAlive(h) then
					add(c, "player")
				end
			end
		end
	end

	if state.espNpcs then
		for model, e in pairs(entities) do
			if e.confirmed and model ~= char and entityAlive(e) and not Players:GetPlayerFromCharacter(model) then
				add(model, "npc")
			end
		end
	end

	-- игроки всегда раньше NPC: толпа мобов не вытесняет их из лимита Highlight
	table.sort(espList, function(a, b)
		if a.kind ~= b.kind then
			return a.kind == "player"
		end
		return a.dist < b.dist
	end)
	for i = 1, math.min(#espList, CONFIG.ESP_MAX) do
		espWant[espList[i].model] = espList[i].kind
	end

	-- убрать лишние (исчезнувшие, мёртвые, дальние, выключенные)
	for model, h in pairs(espMap) do
		if not espWant[model] or not model:IsDescendantOf(Workspace) or h.Parent ~= model then
			espRemove(model)
		end
	end

	-- создать недостающие и обновить цвет
	for model, kind in pairs(espWant) do
		local h = espMap[model]
		if not h then
			local old = model:FindFirstChild(CONFIG.ESP_NAME)
			if old and old:IsA("Highlight") then
				h = old
			else
				if old then
					old:Destroy()
				end
				h = Instance.new("Highlight")
				h.Name = CONFIG.ESP_NAME
			end
			h.Adornee = model
			h.FillTransparency = 1
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Enabled = not CONFIG.ESP_REQUIRE_LOS -- включится только после проверки видимости
			h.Parent = model
			espMap[model] = h
		end
		local color = kind == "player" and CONFIG.ESP_PLAYER_COLOR or CONFIG.ESP_NPC_COLOR
		if h.OutlineColor ~= color then
			h.OutlineColor = color
		end
	end
	X.espUpdate()
end

local espGuarded = guarded("esp", espReconcile)
local espVisGuarded = guarded("esp", X.espUpdate)

---------------------------------------------------------------- осветление тёмных сцен
-- Работает по событиям (без цикла). Запоминает исходные значения Lighting и возвращает их
-- при выключении, но только если игра сама их с тех пор не меняла.
local light = { cc = nil, orig = {}, written = {}, conns = {}, active = false, pending = false }
local LIGHT_EPS = 0.002
local LIGHT_PROPS = { "Ambient", "OutdoorAmbient", "Brightness", "ExposureCompensation", "FogEnd" }

local function setLight(prop, value)
	if light.orig[prop] == nil then
		light.orig[prop] = Lighting[prop]
	end
	light.written[prop] = value
	Lighting[prop] = value
end

local function liftedColor(current, floor)
	local r, g, b = current.R, current.G, current.B
	local changed = false
	if r < floor.R - LIGHT_EPS then
		r = floor.R
		changed = true
	end
	if g < floor.G - LIGHT_EPS then
		g = floor.G
		changed = true
	end
	if b < floor.B - LIGHT_EPS then
		b = floor.B
		changed = true
	end
	if changed then
		return Color3.new(r, g, b)
	end
	return nil
end

local function applyLighting()
	if not light.active then
		return
	end
	local c = liftedColor(Lighting.Ambient, CONFIG.MIN_AMBIENT)
	if c then
		setLight("Ambient", c)
	end
	c = liftedColor(Lighting.OutdoorAmbient, CONFIG.MIN_OUTDOOR_AMBIENT)
	if c then
		setLight("OutdoorAmbient", c)
	end
	if Lighting.Brightness < CONFIG.MIN_BRIGHTNESS - LIGHT_EPS then
		setLight("Brightness", CONFIG.MIN_BRIGHTNESS)
	end
	if Lighting.ExposureCompensation < CONFIG.MIN_EXPOSURE - LIGHT_EPS then
		setLight("ExposureCompensation", CONFIG.MIN_EXPOSURE)
	end
	if CONFIG.REMOVE_FOG and Lighting.FogEnd < 50000 then
		setLight("FogEnd", 100000)
	end
	if not light.cc or light.cc.Parent ~= Lighting then
		if light.cc then
			light.cc:Destroy()
		end
		local e = Instance.new("ColorCorrectionEffect")
		e.Name = "Brighten_CC"
		e.Brightness = CONFIG.CC_BRIGHTNESS
		e.Contrast = CONFIG.CC_CONTRAST
		e.Parent = Lighting
		light.cc = e
	end
end

local lightGuarded = guarded("light", applyLighting)

local function lightSchedule()
	if light.pending or not light.active then
		return
	end
	light.pending = true
	task.defer(function()
		light.pending = false
		lightGuarded()
	end)
end

local function lightDisable()
	light.active = false
	for _, c in ipairs(light.conns) do
		c:Disconnect()
	end
	table.clear(light.conns)
	for prop, written in pairs(light.written) do
		if Lighting[prop] == written and light.orig[prop] ~= nil then
			Lighting[prop] = light.orig[prop]
		end
	end
	table.clear(light.written)
	table.clear(light.orig)
	if light.cc then
		light.cc:Destroy()
		light.cc = nil
	end
end

local function lightRefresh()
	if state.brighten and moduleOk.light then
		if not light.active then
			light.active = true
			for _, prop in ipairs(LIGHT_PROPS) do
				light.conns[#light.conns + 1] = Lighting:GetPropertyChangedSignal(prop):Connect(lightSchedule)
			end
			light.conns[#light.conns + 1] = Lighting.ChildRemoved:Connect(lightSchedule)
		end
		lightSchedule()
	elseif light.active then
		lightDisable()
	end
end
local espAcc = 0

local sweepGuarded = guarded("scan", sweepEntities)

local function onRender(dt)
	acc += dt
	local cam = Workspace.CurrentCamera
	local interval = CONFIG.SELECT_INTERVAL
	if state.onlyWhileAiming and not isAiming() then
		interval = CONFIG.SELECT_IDLE_INTERVAL
	end
	if acc >= interval then
		acc = 0
		aimSelectStep(cam)
	end
	aimPullStep(cam, dt)
	espAcc += dt
	if espAcc >= CONFIG.ESP_INTERVAL or (X.espDirty and espAcc >= 0.1) then
		espAcc = 0
		X.espDirty = false
		espGuarded()
	end
	X.espVisAcc += dt
	if X.espVisAcc >= CONFIG.ESP_LOS_INTERVAL then
		X.espVisAcc = 0
		espVisGuarded()
	end
	X.stickGuarded()
	X.wdAcc += dt
	if X.wdAcc >= 1 then
		X.wdAcc = 0
		if X.watchdog then
			pcall(X.watchdog)
		end
	end
	sweepAcc += dt
	if sweepAcc >= CONFIG.SWEEP_INTERVAL then
		sweepAcc = 0
		sweepGuarded()
	end
	speedTick += dt
	if speedTick >= CONFIG.SPEED_TICK then
		speedTick = 0
		speedEvaluate()
	end
end

local function onSettingChanged()
	if not state.enabled or state.strength <= 0 then
		target = nil
	end
	acc = math.huge -- пересчитать цель в ближайшем кадре
	notifyStatus()
end

track(localPlayer.CharacterAdded:Connect(function()
	target = nil
	acc = math.huge
end))
track(localPlayer.CharacterRemoving:Connect(function()
	target = nil
	notifyStatus()
end))

---------------------------------------------------------------- интерфейс: помощники
local function make(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function round(inst, radius)
	make("UICorner", { CornerRadius = radius }, inst)
end

local function outline(inst, color, thickness, transparency)
	return make("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

local function makeLabel(parent, props)
	local p = {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in pairs(props) do
		p[k] = v
	end
	return make("TextLabel", p, parent)
end

local function tween(inst, time, goal, style)
	local tw = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		goal
	)
	tw:Play()
	return tw
end

-- Универсальный слайдер (используется и для силы, и для скорости)
local function createSlider(parent, cfg)
	local hit = make("TextButton", {
		Position = cfg.position,
		Size = cfg.size,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Active = true,
	}, parent)

	local bar = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.new(1, -24, 0, 6),
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
	}, hit)
	round(bar, UDim.new(1, 0))

	local fill = make("Frame", {
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
	}, bar)
	round(fill, UDim.new(1, 0))

	for _, p in ipairs(cfg.ticks or {}) do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(p, 0, 0.5, 0),
			Size = UDim2.fromOffset(2, 12),
			BackgroundColor3 = C.stroke,
			BorderSizePixel = 0,
		}, bar)
	end

	local thumb = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 3,
	}, bar)
	round(thumb, UDim.new(1, 0))
	outline(thumb, C.accent, 2, 0)

	local api = {}
	local drag, moveConn, endConn = nil, nil, nil

	function api.render()
		local alpha = math.clamp((cfg.get() - cfg.min) / (cfg.max - cfg.min), 0, 1)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		thumb.Position = UDim2.new(alpha, 0, 0.5, 0)
	end

	function api.stop()
		if moveConn then
			moveConn:Disconnect()
			moveConn = nil
		end
		if endConn then
			endConn:Disconnect()
			endConn = nil
		end
		drag = nil
		if cfg.scroller then
			cfg.scroller.ScrollingEnabled = true
		end
	end

	local function fromX(x)
		local w = bar.AbsoluteSize.X
		if w <= 0 then
			return
		end
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / w, 0, 1)
		cfg.set(math.floor(cfg.min + alpha * (cfg.max - cfg.min) + 0.5))
		api.render()
	end

	hit.InputBegan:Connect(function(input)
		if drag then
			return
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		drag = input
		if cfg.scroller then
			cfg.scroller.ScrollingEnabled = false
		end
		fromX(input.Position.X)
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if not drag then
				return
			end
			if i == drag
				or (drag.UserInputType == Enum.UserInputType.MouseButton1
					and i.UserInputType == Enum.UserInputType.MouseMovement) then
				fromX(i.Position.X)
			end
		end)
		endConn = UserInputService.InputEnded:Connect(function(i)
			if i == drag then
				api.stop()
			end
		end)
	end)

	api.render()
	sliders[#sliders + 1] = api
	uiRefreshers[#uiRefreshers + 1] = api.render
	return api
end

---------------------------------------------------------------- интерфейс: каркас
local oldGui = playerGui:FindFirstChild("AimAssistUI")
if oldGui then
	oldGui:Destroy()
end

local gui = make("ScreenGui", {
	Name = "AimAssistUI",
	ResetOnSpawn = false,
	DisplayOrder = 100,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, nil)

-- Компактный элемент справа по центру (удержание 2.5 с открывает меню)
local handle = make("TextButton", {
	Name = "Handle",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -CONFIG.SIDE_MARGIN + 2, 0.42, 0),
	Size = UDim2.fromOffset(34, 104),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.15,
	Text = "",
	AutoButtonColor = false,
	Active = true,
}, gui)
round(handle, UDim.new(0, 14))
outline(handle, C.stroke, 1, 0.3)

local handleTitle = makeLabel(handle, {
	Text = "AIM",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = C.accent,
	TextXAlignment = Enum.TextXAlignment.Center,
	Position = UDim2.new(0, 0, 0, 6),
	Size = UDim2.new(1, 0, 0, 14),
})

local holdTrack = make("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 26),
	Size = UDim2.fromOffset(8, 70),
	BackgroundColor3 = C.card,
	BorderSizePixel = 0,
}, handle)
round(holdTrack, UDim.new(1, 0))

local holdFill = make("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, 0),
	Size = UDim2.new(1, 0, 0, 0),
	BackgroundColor3 = C.accent,
	BorderSizePixel = 0,
}, holdTrack)
round(holdFill, UDim.new(1, 0))

-- Основная панель (справа по центру)
local PANEL_OPEN = UDim2.new(1, -CONFIG.SIDE_MARGIN, 0.42, 0)
local PANEL_CLOSED = UDim2.new(1, 60, 0.42, 0)

local panel = make("CanvasGroup", {
	Name = "Panel",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = PANEL_CLOSED,
	Size = UDim2.new(0.24, 0, 0.6, 0),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.04,
	GroupTransparency = 1,
	Visible = false,
	Active = true,
}, gui)
make("UISizeConstraint", { MinSize = Vector2.new(190, 200), MaxSize = Vector2.new(250, 330) }, panel)
round(panel, UDim.new(0, 18))
outline(panel, C.stroke, 1, 0.3)

local body = make("ScrollingFrame", {
	Name = "Body",
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 12),
	PaddingRight = UDim.new(0, 12),
}, body)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)

local rowOrder = 0
local function makeRow(height)
	rowOrder += 1
	return make("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		LayoutOrder = rowOrder,
	}, body)
end

-- getter() -> текущее значение, onChange(newValue) -> применить; возвращает функцию отрисовки
local function makeSwitch(parent, getter, onChange)
	local btn = make("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(46, 26),
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = C.card,
	}, parent)
	round(btn, UDim.new(1, 0))
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(0, 3, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
	}, btn)
	round(knob, UDim.new(1, 0))

	local function render(animate)
		local on = getter()
		local color = on and C.accent or C.card
		local pos = on and UDim2.new(1, -23, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		if animate then
			tween(btn, 0.15, { BackgroundColor3 = color })
			tween(knob, 0.15, { Position = pos })
		else
			btn.BackgroundColor3 = color
			knob.Position = pos
		end
	end

	btn.Activated:Connect(function()
		onChange(not getter())
		render(true)
	end)
	render(false)
	uiRefreshers[#uiRefreshers + 1] = function()
		render(false)
	end
	return render
end

-- заголовок + кнопка закрытия
local headerRow = makeRow(28)
makeLabel(headerRow, {
	Text = "AIM ASSIST",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	Size = UDim2.new(1, -34, 1, 0),
})
local closeBtn = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(28, 28),
	Text = "X",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = C.sub,
	BackgroundColor3 = C.card,
	AutoButtonColor = false,
}, headerRow)
round(closeBtn, UDim.new(1, 0))

-- невидимая увеличенная зона нажатия: внешний вид и положение кнопки не меняются
X.closeHit = make("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 4, 0.5, 0),
	Size = UDim2.fromOffset(40, 36),
	Text = "",
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	ZIndex = 5,
}, headerRow)

-- главный переключатель
local masterRow = makeRow(28)
makeLabel(masterRow, { Text = "Aim Assist", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(masterRow, function()
	return state.enabled
end, function(v)
	state.enabled = v
	commit("enabled")
	if v then
		fovGaveUp = false
	end
	refreshFov()
	onSettingChanged()
end)

-- индикатор состояния
local statusRow = makeRow(24)
local statusDot = make("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 2, 0.5, 0),
	Size = UDim2.fromOffset(10, 10),
	BackgroundColor3 = C.off,
	BorderSizePixel = 0,
}, statusRow)
round(statusDot, UDim.new(1, 0))
local statusLabel = makeLabel(statusRow, {
	Text = "OFF",
	TextSize = 12,
	TextColor3 = C.sub,
	Position = UDim2.new(0, 20, 0, 0),
	Size = UDim2.new(1, -20, 1, 0),
})

-- основные параметры
local losRow = makeRow(28)
makeLabel(losRow, { Text = "Line of sight", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(losRow, function()
	return state.lineOfSight
end, function(v)
	state.lineOfSight = v
	commit("lineOfSight")
	onSettingChanged()
end)

local aimRow = makeRow(28)
makeLabel(aimRow, { Text = "Aim point", Size = UDim2.new(1, -108, 1, 0) })
local seg = make("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, 0, 0.5, 0),
	Size = UDim2.fromOffset(104, 28),
	BackgroundColor3 = C.card,
	BorderSizePixel = 0,
}, aimRow)
round(seg, UDim.new(0, 8))
local segButtons = {}
local function renderSeg()
	for name, b in pairs(segButtons) do
		local selected = state.aimPoint == name
		b.BackgroundColor3 = selected and C.accent or C.card
		b.TextColor3 = selected and Color3.new(1, 1, 1) or C.sub
	end
end
for i, name in ipairs({ "Head", "Torso" }) do
	local b = make("TextButton", {
		Size = UDim2.new(0.5, -3, 1, -4),
		Position = UDim2.new((i - 1) * 0.5, i == 1 and 2 or 1, 0, 2),
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		AutoButtonColor = false,
		BackgroundColor3 = C.card,
		TextColor3 = C.sub,
	}, seg)
	round(b, UDim.new(0, 6))
	segButtons[name] = b
	b.Activated:Connect(function()
		state.aimPoint = name
		commit("aimPoint")
		renderSeg()
		onSettingChanged()
	end)
end
renderSeg()
uiRefreshers[#uiRefreshers + 1] = renderSeg

local aimingRow = makeRow(28)
makeLabel(aimingRow, { Text = "Only while aiming", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(aimingRow, function()
	return state.onlyWhileAiming
end, function(v)
	state.onlyWhileAiming = v
	commit("onlyWhileAiming")
end)

local unmarkedRow = makeRow(28)
makeLabel(unmarkedRow, { Text = "Unmarked NPC = enemy", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(unmarkedRow, function()
	return state.unmarkedHostile
end, function(v)
	state.unmarkedHostile = v
	commit("unmarkedHostile")
	onSettingChanged()
end)

local npcRow = makeRow(16)
local npcLabel = makeLabel(npcRow, {
	Text = "NPCs found: 0 (enemies 0, hidden 0)",
	TextSize = 11,
	TextColor3 = C.sub,
	Size = UDim2.new(1, 0, 1, 0),
})
detectorUiHook = function(total, hostile, hidden)
	npcLabel.Text = ("NPCs found: %d (enemies %d, hidden %d)"):format(total, hostile, hidden)
end

-- SPEED (внутри существующей панели)
local speedRow = makeRow(28)
local speedLabel = makeLabel(speedRow, { Text = "Speed", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(speedRow, function()
	return state.speedEnabled
end, function(v)
	state.speedEnabled = v
	commit("speedEnabled")
	speedEvaluate()
end)

local speedValueRow = makeRow(34)
local speedValueLabel = makeLabel(speedValueRow, {
	Text = tostring(state.speedValue),
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 36, 1, 0),
})
createSlider(speedValueRow, {
	min = CONFIG.SPEED_MIN,
	max = CONFIG.SPEED_MAX,
	get = function()
		return state.speedValue
	end,
	set = function(v)
		v = math.clamp(v, CONFIG.SPEED_MIN, CONFIG.SPEED_MAX)
		if v == state.speedValue then
			return
		end
		state.speedValue = v
		commit("speedValue")
		speedValueLabel.Text = tostring(v)
		speedEvaluate()
	end,
	position = UDim2.new(0, 0, 0, 0),
	size = UDim2.new(1, -40, 1, 0),
	scroller = body,
})
uiRefreshers[#uiRefreshers + 1] = function()
	speedValueLabel.Text = tostring(state.speedValue)
end

speedUiHook = function()
	if sp.unsupported or not moduleOk.speed then
		speedLabel.Text = "Speed (" .. (sp.reason or "N/A") .. ")"
		speedLabel.TextColor3 = C.warn
	else
		speedLabel.Text = "Speed"
		speedLabel.TextColor3 = C.text
	end
end

-- ESP
local espPlayersRow = makeRow(28)
makeLabel(espPlayersRow, { Text = "ESP players", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(espPlayersRow, function()
	return state.espPlayers
end, function(v)
	state.espPlayers = v
	commit("espPlayers")
	espGuarded()
end)

local espNpcRow = makeRow(28)
makeLabel(espNpcRow, { Text = "ESP NPC", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(espNpcRow, function()
	return state.espNpcs
end, function(v)
	state.espNpcs = v
	commit("espNpcs")
	espGuarded()
end)

local brightenRow = makeRow(28)
makeLabel(brightenRow, { Text = "Brighten dark", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(brightenRow, function()
	return state.brighten
end, function(v)
	state.brighten = v
	commit("brighten")
	lightRefresh()
end)

-- диагностика сохранения
local persistRow = makeRow(30)
local persistLabel = makeLabel(persistRow, {
	Text = "Saving: checking...",
	TextSize = 10,
	TextColor3 = C.sub,
	TextWrapped = true,
	TextTruncate = Enum.TextTruncate.None,
	TextYAlignment = Enum.TextYAlignment.Top,
	Size = UDim2.new(1, 0, 1, 0),
})
persistListener = function(text, kind)
	persistLabel.Text = text
	persistLabel.TextColor3 = kind == "ok" and C.on or (kind == "warn" and C.warn or C.sub)
end

---------------------------------------------------------------- интерфейс: нижняя панель (режимы + сила)
local DOCK_OPEN = UDim2.new(0.5, 0, 1, -10)
local DOCK_CLOSED = UDim2.new(0.5, 0, 1, 120)

local dock = make("CanvasGroup", {
	Name = "Dock",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = DOCK_CLOSED,
	Size = UDim2.new(0.44, 0, 0, 100),
	BackgroundColor3 = C.bg,
	BackgroundTransparency = 0.04,
	GroupTransparency = 1,
	Visible = false,
	Active = true,
}, gui)
make("UISizeConstraint", { MinSize = Vector2.new(300, 96), MaxSize = Vector2.new(430, 110) }, dock)
round(dock, UDim.new(0, 18))
outline(dock, C.stroke, 1, 0.3)

local modeRow = make("Frame", {
	Position = UDim2.new(0, 10, 0, 10),
	Size = UDim2.new(1, -20, 0, 38),
	BackgroundTransparency = 1,
}, dock)
make("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, modeRow)

local modeButtons = {}
local function renderModes()
	for name, b in pairs(modeButtons) do
		local selected = state.mode == name
		b.BackgroundColor3 = selected and C.accent or C.card
		b.TextColor3 = selected and Color3.new(1, 1, 1) or C.sub
	end
end
for i, def in ipairs({
	{ "ENEMIES", "ENEMIES ONLY" },
	{ "PLAYERS", "PLAYERS ONLY" },
	{ "NPC", "NPC ONLY" },
}) do
	local key, text = def[1], def[2]
	local b = make("TextButton", {
		LayoutOrder = i,
		Size = UDim2.new(1 / 3, -4, 1, 0),
		Text = text,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextWrapped = true,
		AutoButtonColor = false,
		BackgroundColor3 = C.card,
		TextColor3 = C.sub,
	}, modeRow)
	round(b, UDim.new(0, 10))
	modeButtons[key] = b
	b.Activated:Connect(function()
		state.mode = key
		commit("mode")
		renderModes()
		onSettingChanged()
	end)
end
renderModes()
uiRefreshers[#uiRefreshers + 1] = renderModes

local sliderRow = make("Frame", {
	Position = UDim2.new(0, 10, 0, 54),
	Size = UDim2.new(1, -20, 0, 36),
	BackgroundTransparency = 1,
}, dock)

local capFrame = make("Frame", {
	Size = UDim2.new(0, 78, 1, 0),
	BackgroundTransparency = 1,
}, sliderRow)
makeLabel(capFrame, {
	Text = "STRENGTH",
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	Size = UDim2.new(1, 0, 0.5, 0),
	Position = UDim2.new(0, 2, 0, 2),
})
local descLabel = makeLabel(capFrame, {
	Text = "MODERATE",
	TextSize = 10,
	TextColor3 = C.sub,
	Size = UDim2.new(1, 0, 0.5, 0),
	Position = UDim2.new(0, 2, 0.5, 0),
})

local valueLabel = makeLabel(sliderRow, {
	Text = "50%",
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Right,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.new(0, 48, 1, 0),
})

local function describeStrength(v)
	if v <= 0 then
		return "OFF"
	elseif v <= 37 then
		return "WEAK"
	elseif v <= 62 then
		return "MODERATE"
	elseif v <= 87 then
		return "STRONG"
	end
	return "MAX"
end

local function renderStrengthLabels()
	valueLabel.Text = state.strength .. "%"
	descLabel.Text = describeStrength(state.strength)
end
renderStrengthLabels()
uiRefreshers[#uiRefreshers + 1] = renderStrengthLabels

createSlider(sliderRow, {
	min = 0,
	max = 100,
	ticks = { 0.25, 0.5, 0.75 },
	get = function()
		return state.strength
	end,
	set = function(v)
		v = math.clamp(v, 0, 100)
		if v == state.strength then
			return
		end
		state.strength = v
		commit("strength")
		renderStrengthLabels()
		onSettingChanged()
	end,
	position = UDim2.new(0, 80, 0, 0),
	size = UDim2.new(1, -130, 1, 0),
})

---------------------------------------------------------------- открытие / закрытие меню
local menuOpen = false
local cooldownUntil = 0
local panelTween, dockTween = nil, nil

local function setMenu(open)
	if destroyed or menuOpen == open then
		return
	end
	menuOpen = open
	cooldownUntil = os.clock() + 0.5
	if panelTween then
		panelTween:Cancel()
	end
	if dockTween then
		dockTween:Cancel()
	end

	if open then
		handle.Visible = false
		panel.Position = PANEL_CLOSED
		panel.GroupTransparency = 1
		panel.Visible = true
		dock.Position = DOCK_CLOSED
		dock.GroupTransparency = 1
		dock.Visible = true
		panelTween = tween(panel, 0.35, { Position = PANEL_OPEN, GroupTransparency = 0 })
		dockTween = tween(dock, 0.35, { Position = DOCK_OPEN, GroupTransparency = 0 })
	else
		panelTween = tween(panel, 0.22, { Position = PANEL_CLOSED, GroupTransparency = 1 }, Enum.EasingStyle.Quad)
		dockTween = tween(dock, 0.22, { Position = DOCK_CLOSED, GroupTransparency = 1 }, Enum.EasingStyle.Quad)
		panelTween.Completed:Connect(function()
			if not menuOpen and not destroyed then
				panel.Visible = false
				dock.Visible = false
				handle.Visible = true
			end
		end)
	end
end

local function closePanel()
	for _, sl in ipairs(sliders) do
		sl.stop()
	end
	setMenu(false)
end

closeBtn.Activated:Connect(closePanel)
X.closeHit.Activated:Connect(closePanel)

-- Сторож раз в секунду: кнопка не может навсегда остаться скрытой или потерять родителя.
X.watchdog = function()
	if destroyed then
		return
	end
	if gui.Parent ~= playerGui then
		gui.Parent = playerGui
	end
	if not gui.Enabled then
		gui.Enabled = true
	end
	if os.clock() > cooldownUntil + 0.6 then
		if menuOpen then
			if not panel.Visible then
				setMenu(false) -- меню числится открытым, но панели нет: вернуть кнопку
			end
		else
			if not handle.Visible then
				handle.Visible = true
			end
			if panel.Visible then
				panel.Visible = false
			end
			if dock.Visible then
				dock.Visible = false
			end
		end
	end
end

-- удержание элемента ровно CONFIG.HOLD_TIME секунд
local holdInput, holdStart, holdBeat, holdEnd = nil, 0, nil, nil

local function cancelHold()
	if holdBeat then
		holdBeat:Disconnect()
		holdBeat = nil
	end
	if holdEnd then
		holdEnd:Disconnect()
		holdEnd = nil
	end
	holdInput = nil
	holdFill.Size = UDim2.new(1, 0, 0, 0)
end

handle.InputBegan:Connect(function(input)
	if destroyed or menuOpen or holdInput or os.clock() < cooldownUntil then
		return
	end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
		return
	end
	holdInput = input
	holdStart = os.clock()
	holdEnd = UserInputService.InputEnded:Connect(function(i)
		if i == holdInput then
			cancelHold() -- отпустил раньше времени: отмена
		end
	end)
	holdBeat = RunService.Heartbeat:Connect(function()
		local p = (os.clock() - holdStart) / CONFIG.HOLD_TIME
		if p >= 1 then
			cancelHold()
			setMenu(true)
		else
			holdFill.Size = UDim2.new(1, 0, p, 0)
		end
	end)
end)

---------------------------------------------------------------- загрузка сохранённых настроек
function FS.load()
	persist.backend = "file"
	local text = FS.readText()
	local data, status = nil, "new"
	if text then
		local ok, decoded = pcall(function()
			return FS.http:JSONDecode(text)
		end)
		if ok and type(decoded) == "table" then
			data = decoded
			status = "loaded"
		else
			-- битый файл: оставляем копию и начинаем с настроек по умолчанию
			status = "broken"
			pcall(function()
				FS.ensureFolder()
				FS.write(FS.path .. ".broken", text)
			end)
		end
	end
	if destroyed then
		return
	end

	local applied, invalid = 0, 0
	if data then
		for key, fn in pairs(SANITIZE) do
			local raw = data[key]
			if raw ~= nil then
				local v = fn(raw)
				if v == nil then
					invalid += 1
				elseif not persist.touched[key] then
					state[key] = v
					applied += 1
				end
			end
		end
	end
	persist.available = true
	persist.loaded = true
	refreshUI()
	refreshFov()
	onSettingChanged()
	speedEvaluate()
	espGuarded()
	lightRefresh()

	local msg
	if status == "new" then
		msg = "Saving: ON (file " .. FS.path .. "). No saved data yet, your changes will be stored."
	elseif status == "broken" then
		msg = "Saving: ON (file). The old file was damaged, a copy was kept (.broken)."
	else
		msg = "Saving: ON (file). Loaded " .. applied .. " saved settings."
	end
	if invalid > 0 then
		msg ..= " " .. invalid .. " invalid value(s) ignored."
	end
	diag(msg, "ok")
	if status ~= "loaded" or next(persist.touched) ~= nil then
		scheduleSave() -- создаст файл и сохранит изменения, сделанные до окончания загрузки
	end
end

local function loadPersisted()
	if FS.write and FS.read then
		FS.load()
		return
	end
	persist.backend = "server"
	local folder = ReplicatedStorage:WaitForChild(CONFIG.REMOTES_FOLDER, 6)
	local loadFn = folder and folder:WaitForChild("Load", 3)
	local saveFn = folder and folder:WaitForChild("Save", 3)
	if destroyed then
		return
	end
	if not (loadFn and saveFn and loadFn:IsA("RemoteFunction") and saveFn:IsA("RemoteFunction")) then
		diag("Saving: OFF. No server script (" .. CONFIG.REMOTES_FOLDER .. ") found. Settings last this session only.", "warn")
		return
	end
	persist.available = true
	persist.saveFn = saveFn
	diag("Saving: loading...")

	local ok, res = pcall(function()
		return loadFn:InvokeServer()
	end)
	if destroyed then
		return
	end
	if not ok or type(res) ~= "table" or res.ok ~= true or type(res.data) ~= "table" then
		-- сохранять нельзя, пока загрузка не удалась: иначе можно затереть старые данные значениями по умолчанию
		local reason = (ok and type(res) == "table" and res.reason) or tostring(res)
		diag("Saving: load failed (" .. tostring(reason) .. "). Not saving this session to protect old data.", "warn")
		return
	end

	local applied, invalid = 0, 0
	for key, fn in pairs(SANITIZE) do
		local raw = res.data[key]
		if raw ~= nil then
			local v = fn(raw)
			if v == nil then
				invalid += 1 -- повреждённое значение: берём текущее/по умолчанию, остальное не страдает
			elseif not persist.touched[key] then
				state[key] = v
				applied += 1
			end
		end
	end
	persist.loaded = true
	refreshUI()
	refreshFov()
	onSettingChanged()
	speedEvaluate()
	espGuarded()
	lightRefresh()

	local msg
	if res.status == "new" then
		msg = "Saving: ON. No saved data yet, your changes will be stored."
	else
		msg = "Saving: ON. Loaded " .. applied .. " saved settings."
	end
	if res.status == "migrated" then
		msg ..= " (old format upgraded)"
	end
	if invalid > 0 then
		msg ..= " " .. invalid .. " invalid value(s) ignored."
	end
	diag(msg, "ok")
	if next(persist.touched) ~= nil then
		scheduleSave() -- изменения игрока, сделанные до окончания загрузки
	end
end

---------------------------------------------------------------- статус и запуск
statusListener = function(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	statusDot.BackgroundColor3 = color
	handleTitle.TextColor3 = (state.enabled and moduleOk.aim) and C.accent or C.off
end

onModuleDisabled = function(name)
	if name == "light" then
		lightDisable()
	end
	if name == "esp" then
		espClear()
	end
	if name == "speed" then
		speedUnbind()
		if speedUiHook then
			speedUiHook()
		end
	end
	notifyStatus()
end

X.onEnabled = function(name)
	if name == "light" then
		lightRefresh()
	elseif name == "speed" then
		local ch = localPlayer.Character
		if ch then
			speedBind(ch)
		end
	end
	notifyStatus()
end

local guiGone = false

local function destroy()
	if destroyed then
		return
	end
	if persist.dirty and persist.loaded then
		flushSave()
	end
	destroyed = true
	if X.registry.__AimAssistShutdown == destroy then
		X.registry.__AimAssistShutdown = nil
	end
	X.watchdog = nil
	cancelHold()
	for _, s in ipairs(sliders) do
		s.stop()
	end
	pcall(function()
		RunService:UnbindFromRenderStep(X.renderName)
	end)
	speedUnbind()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	releaseFov(true)
	target = nil
	espClear()
	for p, list in pairs(X.espConns) do
		for _, c in ipairs(list) do
			c:Disconnect()
		end
		X.espConns[p] = nil
	end
	lightDisable()
	if stickBlockGui then
		stickBlockGui:Destroy()
		stickBlockGui = nil
	end
	for _, c in ipairs(X.stickConns) do
		c:Disconnect()
	end
	table.clear(X.stickConns)
	for _, o in ipairs(X.stickOrig) do
		-- вернуть стик игры в исходный размер и положение
		pcall(function()
			if o.frame.Parent then
				o.frame.Size = o.fs
				o.frame.Position = o.fp
				o.outer.Size = o.os
				o.stick.Size = o.ss
				o.stick.Position = UDim2.fromOffset((o.fs.X.Offset - o.ss.X.Offset) / 2, (o.fs.Y.Offset - o.ss.Y.Offset) / 2)
			end
		end)
	end
	table.clear(X.stickOrig)
	table.clear(aimTouches)
	aimCount = 0
	table.clear(entities)
	if not guiGone then
		gui:Destroy()
	end
end

gui.Destroying:Connect(function()
	guiGone = true
	destroy()
end)

gui.Parent = playerGui
X.registry.__AimAssistShutdown = destroy
RunService:BindToRenderStep(X.renderName, Enum.RenderPriority.Camera.Value + 1, onRender)
refreshFov()
onSettingChanged()
speedUiHook()
lightRefresh()
task.spawn(loadPersisted)
