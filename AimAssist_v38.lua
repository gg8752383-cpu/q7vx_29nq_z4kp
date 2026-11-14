-- LocalScript -> StarterPlayer > StarterPlayerScripts   (ТОЛЬКО клиент, серверного кода нет)
-- AIM ASSIST v31: FOV 85 | панель | режимы ENEMIES / PLAYERS / NPC | сила 0-100%
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
--   * Сохраняются все 17 настроек панели: enabled, mode, lineOfSight, aimPoint, onlyWhileAiming,
--     unmarkedHostile, espPlayers, espNpcs, maneuver, brighten, speedEnabled, speedValue, juke, jukeX, jukeY, forceTP, moveResp.
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
	AIM_RAMP = 0.08,            -- плавное включение подтягивания на новой цели (сек)
	AIM_SWITCH_HOLD = 0.18,     -- претендент должен быть лучше столько секунд, чтобы прицел перешёл на него
	AIM_OFFSET_SMOOTH = 0.06,   -- сглаживание смещения точки наведения (голова/торс), сек
	AIM_VEL_SMOOTH = 0.08,      -- сглаживание измеренной скорости цели, сек
	AIM_LEAD_MAX = 0.16,        -- максимум упреждения, сек
	AIM_LEAD_STUDS = 6,         -- упреждение не больше стольких студов
	AIM_MAX_SPEED = 120,        -- скорость цели для расчёта упреждения ограничивается (студов/с)
	AIM_TELEPORT = 30,          -- сдвиг цели за кадр больше этого считается телепортом: сглаживание с нуля
	AIM_CONE_DEG = 5.5,         -- радиус зоны захвата (градусы): компактная зона, точнее выбор цели
	AIM_STRENGTH = 1.3,         -- предел скорости поворота камеры: rad(40 + 260 * AIM_STRENGTH) в секунду
	AIM_GAIN = 28,              -- скорость подтягивания к цели (1/с): сильная, быстрая помощь
	AIM_YIELD_MIN = 0.3,        -- остаток помощи, пока игрок сам уводит прицел от цели
	AIM_YIELD_TIME = 0.3,       -- и столько секунд после этого помощь плавно возвращается
	AIM_STD_HEIGHT = 5.5,       -- высота обычного персонажа (R6/R15): выше этого радиус тела цели растёт пропорционально
	AIM_BODY_RADIUS = 1.8,      -- радиус тела цели (студы): вблизи зона захвата считается до тела, а не до центра головы
	AIM_CLOSE_RANGE = 14,       -- ближе этого прицел смещается от головы к корпусу (ближний бой)
	AIM_CLOSE_BLEND = 0.7,      -- насколько сильно (0..1) при нулевой дистанции
	AIM_LEAD_NEAR = 3,          -- упреждение отсутствует ближе этого расстояния
	AIM_LEAD_FAR = 18,          -- и полное дальше этого
	AIM_CATCHUP = 1.8,          -- до +80% к скорости подтягивания на быстро смещающейся цели (0 = выкл.)
	AIM_DEADBAND_DEG = 0.005,
	-- Auto-Maneuver (автоматическое уклонение)
	MV_SCAN_RADIUS = 70,        -- радиус наблюдения за летящими деталями (студы)
	MV_SCAN_IDLE = 0.1,         -- период наблюдения в спокойной обстановке (сек)
	MV_SCAN_ALERT = 1 / 30,     -- и при летящих снарядах/растущих зонах
	MV_SCAN_MELEE = 1 / 30,     -- и когда рядом просто есть враги
	MV_MAX_PARTS = 400,         -- сколько деталей максимум просматривается за раз
	MV_MIN_SPEED = 30,          -- снаряд: относительная скорость не ниже (студов/с)
	MV_MAX_SIZE = 24,           -- снаряд: размер не больше (крупнее - не снаряд)
	MV_BODY_RADIUS = 2.2,       -- радиус тела игрока для расчёта попадания
	MV_BODY_HALF = 2.6,         -- половина высоты тела
	MV_HIT_MARGIN = 1.0,        -- запас вокруг снаряда
	MV_HIT_THRESH = 0.5,        -- зазор меньше этого = попадание
	MV_HORIZON = 1.6,           -- на сколько секунд вперёд считается траектория
	JUKE_HOLD = 1.0,            -- сколько секунд держать кнопку Juke, чтобы её можно было двигать пальцем
	JUKE_SLOP = 14,             -- палец смещается не дальше этого (px) за время удержания, иначе это не удержание
	JUKE_SIZE = 46,             -- размер кнопки (px)
	JUKE_RANGE = 60,            -- Juke работает, если враг ближе этого (студы)
	JUKE_SEG_MIN = 0.28,        -- длительность одного «шага» в сторону (сек), случайно между MIN и MAX
	JUKE_SEG_MAX = 0.75,
	JUKE_FLIP = 0.75,           -- вероятность сменить сторону после шага (иначе продолжает в ту же)
	JUKE_SMOOTH = 0.12,         -- плавность смены направления (сек): без рывков и «зубцов»
	JUKE_WEIGHT = 0.55,         -- вклад Juke, когда игрок сам ведёт персонажа
	JUKE_IDLE = 0.7,            -- скорость Juke (доля ходьбы), когда игрок стоит
	TP_MIN_ZOOM = 2,       -- минимальная дистанция камеры в Force TP (ниже неё Roblox переходит в вид от первого лица)
	TP_MAX_ZOOM = 400,     -- верхняя граница дальности, которую разрешает сам Roblox; игра может только сузить её, мы возвращаем
	TP_DEFAULT_ZOOM = 12,  -- куда один раз отодвинуть камеру, если она оказалась в первом лице
	TP_FIGHT_LIMIT = 5,    -- столько возвратов CameraType за TP_FIGHT_WINDOW секунд = другой скрипт держит камеру, отступаем
	TP_FIGHT_WINDOW = 2,
	RESP_TAU = 0.055,      -- постоянная времени разгона и смены направления, с (меньше = резче; у стандартного Humanoid заметно больше)
	RESP_TAU_STOP = 0.07,  -- то же для торможения (чуть мягче: плавное завершение движения)
	RESP_FULL_AT = 0.75,   -- аналоговый стик даёт полную скорость уже на этой доле хода (клавиатура и так 1)
	RESP_MIN_INPUT = 0.05, -- меньше этого - считаем, что стик отпущен
	RESP_KNOCK = 1.25,     -- горизонтальная скорость выше WalkSpeed * это (+2) = внешний толчок/рывок игры: не вмешиваемся
	RESP_MAX_DT = 0.1,     -- кадры длиннее (лаг) пропускаем
	MV_STYLE = "walk",           -- "walk": обычное движение (Humanoid:Move, без рывков и телепортации); "dash": прежний короткий рывок
	MV_WALK_TIME = 0.45,        -- сколько секунд уклоняющее движение ведёт персонажа (затем управление возвращается игроку)
	MV_WALK_TIME_STATIC = 0.9,  -- то же для неподвижной опасности (лава, пила): нужно выйти из зоны целиком
	MV_WALK_RAMP = 0.08,        -- разгон до скорости ходьбы (сек), учитывается в расчёте траектории
	MV_DASH_DIST = 8,           -- дальность рывка (студы)
	MV_DASH_TIME = 0.2,         -- длительность рывка (сек)
	MV_HINT_SPEED = 12,         -- деталь с «боевым» именем/атрибутом Damage считается снарядом уже с такой скорости (студов/с)
	MV_HAZ_MAX = 12,            -- одновременно отслеживаемых опасных статичных деталей (лава, шипы, ловушки)
	MV_HAZ_RANGE = 30,          -- опасная деталь отслеживается, если игрок ближе этого к её краю
	MV_SPIN_TIP = 30,           -- вращающаяся опасная деталь: скорость края не ниже (студов/с)
	MV_ANIM_ANY = true,         -- реагировать на любую «ударную» анимацию врага (приоритет Action, не зациклена), даже если в названии нет слов attack/slash и т.п.
	MV_ANIM_REACH = 12,         -- анимация атаки врага рассматривается, если враг ближе этого (студы)
	MV_ARC = 1.5,               -- дугой: на сколько радиан (~86°) заворачивает траектория бокового рывка (облёт вокруг/за спину)
	MV_COOLDOWN = 0.5,          -- пауза между рывками
	MV_MIN_CLEARANCE = 0.6,     -- после рывка промах должен быть не меньше (студы)
	MV_REPEAT_PENALTY = 1.0,    -- штраф за повтор той же стороны подряд
	MV_VOID_DEPTH = 12,         -- ниже этой глубины без земли рывок в эту сторону не делается
	MV_MELEE_RANGE = 14,        -- ближний бой: враг ближе этого рассматривается
	MV_MELEE_REACH = 9.5,       -- дальность удара (студы)
	MV_MELEE_TIP_SPEED = 20,    -- скорость оружия/руки к игроку, считающаяся замахом (студов/с)
	MV_MELEE_COOLDOWN = 0.6,    -- один и тот же враг не вызывает рывок чаще
	MV_MELEE_CONE_COS = 0.34,   -- удар идёт вперёд от врага в конусе ~±70°
	MV_ZONE_GROWTH = 8,         -- растущая зона: рост размера не ниже (студов/с)
	MV_ZONE_EXTRAP = 0.6,       -- на сколько секунд вперёд продолжается рост зоны (дальше её размер неизвестен)
	MV_ZONE_SELF = 4,           -- зона, родившаяся ближе этого к игроку, считается его собственной способностью     -- мёртвая зона у центра прицела (против микродрожания)
	LOS_GRACE = 0.18,           -- после потери видимости цель плавно затухает столько секунд
	LOS_NEG_CACHE = 0.2,        -- полностью закрытую цель не перепроверяем чаще
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
	ESP_MAX_TOUCH = 20,         -- на телефоне Highlight дороже: лимит ниже (игроки всегда в приоритете)
	ESP_THROUGH_WALLS = true,   -- контур виден и за стенами: за препятствием он бледнее
	ESP_INTENSITY = 0.6,        -- общая заметность контура и заливки (0 = не видно, 1 = максимум)
	ESP_VIS_ALPHA = 0.5,        -- непрозрачность контура у хорошо видимой цели при интенсивности 100% (без заливки)
	ESP_HIDDEN_ALPHA = 0.9,     -- то же для цели за стеной
	ESP_FILL_ALPHA = 0.3,       -- мягкая заливка (силуэт) только у цели за стеной, при интенсивности 100%
	ESP_FADE_TIME = 0.12,       -- плавность появления/исчезновения/смены (сек): нет миганий
	ESP_FAR_FADE = 0.35,        -- насколько бледнеют цели у предельной дальности (0 = не бледнеют)
	ESP_MAX = 30,               -- лимит Roblox: одновременно рисуется не больше 31 Highlight
	ESP_MAX_DISTANCE = 500,     -- дальше этого (студов) контур не рисуется
	ESP_NAME = "EspOutline",
	ESP_REQUIRE_LOS = true,     -- контур только при реальной прямой видимости (Raycast от камеры)
	ESP_LOS_INTERVAL = 0.15,    -- как часто проверяется видимость обведённых целей (сек)
	ESP_LOS_GRACE = 0.2,        -- после потери видимости контур держится столько секунд (без мерцания)
	ESP_RAY_PARTS = { "Head", "UpperTorso", "Torso", "HumanoidRootPart", "LowerTorso" },
	SELECT_IDLE_INTERVAL = 0.3, -- выбор цели, пока никто не целится (экономия лучей)
	ESP_PLAYER_COLOR = Color3.fromRGB(160, 196, 226),  -- спокойный холодный голубой
	ESP_NPC_COLOR = Color3.fromRGB(224, 172, 152),     -- приглушённый тёплый персиковый

	SPEED_MIN = 8,
	SPEED_MAX = 50,
	SPEED_TICK = 0.1,           -- как часто перепроверяются статусы (оглушение и т.п.); это проверка, а не запись скорости
	SPEED_SETTLE = 4,           -- сколько секунд после появления персонажа игра ещё может выставлять свою «обычную» скорость
	SPEED_ADOPT = 5,            -- если игра подняла обычную скорость (уровень, спринт) и держит её столько секунд, это новая «обычная»
	SPEED_RESUME_DELAY = 0.2,   -- пауза после окончания Stun/Slow/Root, прежде чем вернуть свою скорость (выход из эффекта не ускоряем)
	SPEED_FIGHT_LIMIT = 5,      -- столько откатов нашего значения игрой за SPEED_FIGHT_WINDOW с = игра с нами борется
	SPEED_FIGHT_WINDOW = 2,
	SPEED_PAUSE_MIN = 3,        -- пауза после борьбы (дальше удваивается до SPEED_PAUSE_MAX), потом Speed пробует снова
	SPEED_PAUSE_MAX = 30,
	SPEED_RB_MIN = 8,           -- откат позиции назад на столько стадов за проверку = серверный rubber-band
	SPEED_RB_COUNT = 2,         -- сколько откатов за SPEED_RB_WINDOW с, чтобы признать, что сервер не принимает скорость
	SPEED_RB_WINDOW = 8,
	SPEED_RB_PAUSE = 20,        -- пауза после этого (удваивается до 120 с)
	-- Если у персонажа/Humanoid есть атрибут или Bool/NumberValue с таким словом в имени
	-- и значение true/больше 0, Speed не вмешивается (игра сама управляет скоростью).
	STATUS_PATTERNS = {
		"stun", "slow", "freez", "frozen", "rooted", "immobil", "ragdoll", "paraly",
		"knockback", "casting", "channel", "dash", "usingability", "grabbed", "carried",
		"trapped", "disabled",
	},
	-- жёсткие эффекты контроля: их проверяем и на самом игроке (Player), где «dash»/«casting» могут быть просто настройками
	STATUS_PATTERNS_HARD = { "stun", "slow", "freez", "frozen", "rooted", "immobil", "paraly", "trapped" },

	DEFAULTS = {
		enabled = true,
		mode = "ENEMIES",       -- "ENEMIES" | "PLAYERS" | "NPC"
		lineOfSight = true,     -- не наводиться через стены
		aimPoint = "Head",      -- "Head" | "Torso"
		onlyWhileAiming = true, -- помощь только пока палец крутит камеру
		unmarkedHostile = false, -- NPC без метки команды считать врагами (по умолчанию выкл.)
		espPlayers = true,      -- контур игроков
		espNpcs = true,         -- контур NPC
		maneuver = true,        -- Auto-Maneuver: автоматическое уклонение от реальных угроз
		brighten = true,        -- осветление тёмных сцен
		speedEnabled = false,
		speedValue = 20,
		juke = false,           -- Juke: плавные уходы из стороны в сторону вокруг врага (кнопка на экране)
		jukeX = 0.88,           -- положение кнопки Juke (доля ширины экрана)
		jukeY = 0.72,           -- и высоты
		forceTP = false,        -- Force Third Person: принудительный вид от третьего лица
		moveResp = false,       -- Advanced Movement Responsiveness: отзывчивое управление без роста WalkSpeed
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
	espRec = setmetatable({}, { __mode = "k" }),  -- [model] = текущая и целевая прозрачность контура
	espDist = setmetatable({}, { __mode = "k" }), -- [model] = дистанция до камеры (для бледнения вдали)
	espAnimating = false,
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
		local okPrev, errPrev = pcall(prev)
		if not okPrev then
			warn("[Panel:shutdown] предыдущий экземпляр завершился с ошибкой: " .. tostring(errPrev))
		end
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
local moduleOk = { aim = true, speed = true, esp = true, light = true, scan = true, stick = true, maneuver = true, juke = true, tp = true, resp = true }
local errCount = {}
local onModuleDisabled = nil

-- Корневая часть персонажа/модели: HumanoidRootPart, иначе Humanoid.RootPart (у кастомных ригов корень называется иначе),
-- иначе PrimaryPart. Быстрый путь (обычное имя) без лишних обращений.
function X.root(model)
	local r = model:FindFirstChild("HumanoidRootPart")
	if r then
		return r
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	return (h and h.RootPart) or model.PrimaryPart
end

-- pcall с диагностикой: ошибка не теряется молча, а один раз за метку попадает в консоль (метка = место вызова)
X.tryWarned = {}
function X.try(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not X.tryWarned[label] then
		X.tryWarned[label] = true
		warn(("[Panel:%s] %s"):format(label, tostring(err)))
	end
	return ok
end

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
	juke = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	forceTP = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	moveResp = function(v)
		if type(v) == "boolean" then
			return v
		end
	end,
	jukeX = function(v)
		if type(v) == "number" and v == v then
			return math.clamp(v, 0.02, 0.98)
		end
	end,
	jukeY = function(v)
		if type(v) == "number" and v == v then
			return math.clamp(v, 0.02, 0.98)
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
	maneuver = function(v)
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
		X.try("persist.folder", FS.makefolder, CONFIG.FILE_DIR)
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
-- Враждебность NPC меняется редко, а проверка стоит нескольких обращений к движку на каждого NPC:
-- результат кэшируется на 1 секунду (выбор цели идёт 20 раз в секунду).
X.hostileC = setmetatable({}, { __mode = "k" })
function X.npcHostile(model, now)
	local c = X.hostileC[model]
	if c and now < c.exp then
		return c.v
	end
	local v = not Players:GetPlayerFromCharacter(model) and isHostileNpc(model)
	if not c then
		c = {}
		X.hostileC[model] = c
	end
	c.v = v
	c.exp = now + 1
	return v
end

function X.clearCands()
	X.candN = 0
	for i = 1, #candidates do
		local c = candidates[i]
		c.model = nil
		c.entity = nil
		c.part = nil
	end
end
X.byScore = function(a, b)
	return a.score < b.score
end

-- Радиус тела цели: для обычных персонажей AIM_BODY_RADIUS, для крупных (гиганты, боссы, большие масштабы R15)
-- растёт пропорционально высоте модели. Иначе точка прицеливания (голова) уходит далеко от центра тела и такая цель
-- почти не попадает в конус захвата. Мелкие модели радиус не уменьшают.
X.bodyR = setmetatable({}, { __mode = "k" })
function X.bodyRadius(model)
	local now = os.clock()
	local c = X.bodyR[model]
	if c and now < c.exp then
		return c.r
	end
	if not c then
		c = {}
		X.bodyR[model] = c
	end
	local r = CONFIG.AIM_BODY_RADIUS
	local ok, size = pcall(model.GetExtentsSize, model)
	if ok and size then
		r = r * math.max(1, size.Y / CONFIG.AIM_STD_HEIGHT)
	end
	c.r = r
	c.exp = now + 3
	return r
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
	-- Промах считается до тела (угловой радиус тела), а не до центра головы: вблизи прицел,
	-- лежащий на теле, не теряет цель, а дальняя цель у центра экрана не перебивает ближнюю.
	local miss = angle - math.atan(X.bodyRadius(model) / dist)
	if miss < 0 then
		miss = 0
	end
	local limit = coneRad
	-- в оценке: промах, небольшая добавка за угол до точки прицеливания и за дальность
	local score = miss + angle * 0.02 + dist / CONFIG.MAX_DISTANCE * 0.08
	if target and target.model == model then
		-- текущая цель удерживается чуть дольше (нет дёрганья между целями)
		limit = coneRad * 1.15
		score = score * 0.75
	end
	if miss > limit then
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
function X.clearRay(camPos, part, filter, params)
	params = params or losParams
	for _ = 1, 4 do
		local hit = Workspace:Raycast(camPos, part.Position - camPos, params)
		if not hit then
			return true
		end
		local inst = hit.Instance
		if inst and inst:IsA("BasePart") and inst.ClassName ~= "Terrain"
			and inst.Transparency >= CONFIG.LOS_PASS_TRANSPARENCY then
			filter[#filter + 1] = inst
			params.FilterDescendantsInstances = filter
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
					if checked >= 3 then
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
	local root = X.root(model)
	if not (root and root:IsA("BasePart")) then
		root = part
	end
	target = {
		model = model, entity = c.entity, part = part, kind = c.kind, name = c.name,
		score = c.score, dist = c.dist,
		anchor = root,   -- корень: по нему меряем скорость (без анимационной тряски головы)
		ramp = 0,        -- плавный вход в подтягивание
		yield = 1,       -- уступка игроку, когда он уводит прицел сам
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
		X.clearCands()
		return
	end
	paused = false
	if not state.enabled then
		target = nil
		X.pendModel = nil
		X.clearCands()
		return
	end

	X.candN = 0
	local cf = cam.CFrame
	local camPos, look = cf.Position, cf.LookVector
	local coneRad = math.rad(CONFIG.AIM_CONE_DEG)
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
		local tNow = os.clock()
		for model, e in pairs(entities) do
			if e.confirmed and model ~= char and X.npcHostile(model, tNow) then
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
		-- кнопки игры (стрельба/удар) «съедают» касание, но именно тогда помощь и нужна:
		-- касание в правой части экрана (зона камеры/кнопок) считается прицеливанием; левая часть - стик ходьбы
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if not (vp and input.Position.X > vp.X * 0.45) then
			return
		end
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
	-- Ближний бой: вблизи точка прицеливания плавно уходит от головы к корпусу
	-- (голова на малой дистанции сильно качается от анимаций, а удар идёт по корпусу).
	local camPos0 = cam.CFrame.Position
	local dClose = (rp - camPos0).Magnitude
	if dClose < CONFIG.AIM_CLOSE_RANGE then
		local u = 1 - dClose / CONFIG.AIM_CLOSE_RANGE
		offRaw = offRaw * (1 - CONFIG.AIM_CLOSE_BLEND * u * u * (3 - 2 * u))
	end
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
			local dtp = math.max(now - t.rpT, 1 / 240)
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
			-- резкая смена направления (враг уворачивается): доверие падает быстро (~0,04 с), а скорость переписывается
			-- быстрее; возвращается доверие медленнее, чтобы на «ёлочке» (лево-право) упреждение не дёргало прицел
			local tgt = agree * agree
			local aT = tgt < t.trust and (1 - math.exp(-dtp / 0.04)) or (1 - math.exp(-dtp / 0.12))
			t.trust += (tgt - t.trust) * aT
			local aV = a
			if agree < 0.6 then
				aV = math.max(a, 1 - math.exp(-dtp / 0.03))
			end
			t.vel = t.vel:Lerp(raw, aV)
			t.rp = rp
			t.rpT = now
		elseif now - t.rpT > 0.12 then
			t.vel = t.vel * math.exp(-dt / 0.1) -- цель встала: скорость быстро затухает
		end
		t.off = t.off:Lerp(offRaw, 1 - math.exp(-dt / CONFIG.AIM_OFFSET_SMOOTH))
	end

	local s = CONFIG.AIM_STRENGTH
	local k = CONFIG.AIM_GAIN -- скорость подтягивания (1/с): сильная помощь, но без жёсткой привязки (см. уступку игроку ниже)

	-- Умеренное упреждение: компенсирует отставание плавного подтягивания, но ограничено
	-- по времени, по дальности и гаснет при смене направления. Вертикаль учитывается вдвое слабее.
	-- Быстро уходящая в угловом смысле цель (рядом или быстро бежит): подтягивание чуть сильнее,
	-- чтобы прицел не отставал; на медленных целях ничего не меняется.
	do
		local v0 = t.vel
		local dir0 = (rp + t.off - camPos0)
		local d0 = dir0.Magnitude
		if d0 > 1 then
			dir0 = dir0 / d0
			local perp = (v0 - dir0 * v0:Dot(dir0)).Magnitude
			k = k * (1 + CONFIG.AIM_CATCHUP * math.clamp(perp / d0 / math.rad(90), 0, 1))
		end
	end
	local lead = math.min(CONFIG.AIM_LEAD_MAX, 0.7 / math.max(k, 0.5))
	local v = t.vel
	local leadVec = Vector3.new(v.X, v.Y * 0.4, v.Z) * (lead * t.trust)

	local cf = cam.CFrame
	local pos = cf.Position
	local base = rp + t.off
	local dist = (base - pos).Magnitude
	if dist < 0.5 then
		return
	end
	-- вблизи упреждение не нужно: малейшая боковая скорость даёт огромный угол
	local nearK = math.clamp((dist - CONFIG.AIM_LEAD_NEAR) / (CONFIG.AIM_LEAD_FAR - CONFIG.AIM_LEAD_NEAR), 0, 1)
	leadVec = leadVec * (nearK * nearK * (3 - 2 * nearK))
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
		X.lastLook = look
		return
	end
	local rawAngle = math.atan2(axisMag, look:Dot(dir))
	-- Игрок ведёт камеру сам: если за этот кадр он увёл прицел от цели (угол вырос по сравнению с тем,
	-- что оставила помощь), помощь резко ослабляется и плавно возвращается: цель не "держит".
	local ly = X.lastLook
	if ly then
		local prev = math.acos(math.clamp(ly:Dot(dir), -1, 1))
		if rawAngle - prev > math.rad(0.6) then
			t.yield = CONFIG.AIM_YIELD_MIN
		end
	end
	local yl = t.yield
	if yl < 1 then
		yl = math.min(1, yl + dt / CONFIG.AIM_YIELD_TIME * (1 - CONFIG.AIM_YIELD_MIN))
		t.yield = yl
		w = w * yl
	end
	local angle = rawAngle - math.rad(CONFIG.AIM_DEADBAND_DEG)
	if angle <= 0 then
		X.lastLook = look
		return
	end

	-- Экспоненциальное приближение зависит от dt (одинаково на любом FPS), скорость поворота ограничена.
	local maxStep = math.rad(40 + 260 * s) * dt * w
	local step = math.min(angle * (1 - math.exp(-k * w * dt)), maxStep)

	local ncf = CFrame.new(pos) * CFrame.fromAxisAngle(axis / axisMag, step) * (cf - pos)
	cam.CFrame = ncf
	X.lastLook = ncf.LookVector
end

local aimSelectStep = guarded("aim", function(cam)
	selectTarget(cam)
	notifyStatus()
end)

local aimPullStep = guarded("aim", function(cam, dt)
	if not cam or not target or paused or not state.enabled then
		return
	end
	if state.onlyWhileAiming and not isAiming() then
		-- палец не на экране: устаревшую скорость и "вход" не храним, касание начнётся плавно
		target.init = false
		target.ramp = 0
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
	held = nil,        -- последнее значение, которое мы держали (чтобы узнать его, когда игра вернёт его сама после Slow)
	applied = false,
	settleUntil = 0,
	conns = {},
	resets = {},
	token = 0,
	unsupported = false,
	reason = nil,
	pauseUntil = 0,    -- пауза: игра борется с нами или сервер откатывает позицию
	pauseStep = 3,
	pauseReason = nil,
	pauseShown = false,
	lastFightAt = 0,
	hardPrev = false,  -- в прошлую проверку действовало ограничение игры (Stun/Slow/Root)
	resumeAt = 0,
	delayAt = 0,
	rb = {},
	rbStep = 20,
	lastPos = nil,
	lastPosAt = 0,
	lastDir = nil,
	normals = {},      -- значения, которые игра держала как «обычную» скорость (возврат к любому из них = конец эффекта)
	higherSince = nil, -- с какого момента игра держит значение выше обычного
}
local speedUiHook = nil
local speedEvaluate = nil
local speedUnbind = nil
local speedBind = nil

local function setSpeedUnsupported(reason)
	sp.unsupported = reason ~= nil
	sp.reason = reason
	if speedUiHook then
		speedUiHook()
	end
end

local function matchesStatus(name, list)
	local lower = string.lower(name)
	for _, pat in ipairs(list or CONFIG.STATUS_PATTERNS) do
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

-- эффект ограничения на объекте: атрибут, ValueBase со значением, Folder/Configuration с таким именем (сама папка = эффект активен)
local function statusBlocked(inst, list)
	for name, value in pairs(inst:GetAttributes()) do
		if truthyValue(value) and matchesStatus(name, list) then
			return true
		end
	end
	for _, child in ipairs(inst:GetChildren()) do
		if matchesStatus(child.Name, list) then
			if child:IsA("ValueBase") then
				local ok, v = pcall(function()
					return child.Value
				end)
				if ok and truthyValue(v) then
					return true
				end
			elseif child:IsA("Folder") or child:IsA("Configuration") then
				return true
			end
		end
	end
	local okT, tags = pcall(function()
		return CollectionService:GetTags(inst)
	end)
	if okT and type(tags) == "table" then
		for _, t in ipairs(tags) do
			if type(t) == "string" and matchesStatus(t, list) then
				return true
			end
		end
	end
	return false
end

-- состояния Humanoid, в которых игра сама лишает управления (рэгдолл, оглушение падением): считаем эффектом, а не обычным движением
sp.hardStates = {
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

-- возвращает: можно ли держать нашу скорость, и является ли причина запрета эффектом игры (Stun/Slow/Root и т.п.)
local function speedAllowed()
	local hum, char = sp.hum, sp.char
	if not hum or not char or not hum.Parent or hum.Health <= 0 then
		return false, false
	end
	local hrp = X.root(char)
	if hum.PlatformStand or (hrp and hrp.Anchored) then
		return false, true -- оглушение/рэгдолл или Root через Anchored
	end
	if hum.Sit then
		return false, false
	end
	local st = hum:GetState()
	if st ~= Enum.HumanoidStateType.Running and st ~= Enum.HumanoidStateType.RunningNoPhysics then
		return false, sp.hardStates[st] == true
	end
	if sp.gameValue ~= sp.normal then
		return false, true -- игра сама изменила скорость (Slow/Stun/Root/спринт/бафф); долгий рост принимаем за новую обычную скорость в evaluate
	end
	if statusBlocked(char) or statusBlocked(hum) or statusBlocked(localPlayer, CONFIG.STATUS_PATTERNS_HARD) then
		return false, true
	end
	return true, false
end

local function speedWrite(value)
	local hum = sp.hum
	if not hum then
		return false
	end
	-- lastWritten выставляем ДО записи: при немедленных сигналах (SignalBehavior = Immediate) обработчик
	-- WalkSpeed сработает внутри присваивания и не должен принять наше значение за значение игры
	local prev = sp.lastWritten
	sp.lastWritten = value
	local ok = pcall(function()
		hum.WalkSpeed = value
	end)
	if not ok then
		sp.lastWritten = prev
		setSpeedUnsupported("N/A in this game")
	end
	return ok
end

function sp.pause(now, secs, reason)
	sp.pauseUntil = now + secs
	sp.pauseReason = reason
	table.clear(sp.resets)
	table.clear(sp.rb)
	if speedUiHook then
		speedUiHook()
	end
end

-- Серверный rubber-band: позицию резко возвращает назад, пока мы держим повышенную скорость. Предотвратить это нельзя
-- (проверка на сервере), но можно перестать давить: после повторных откатов Speed уступает на паузу и пробует позже.
function sp.watchRubber(now)
	local hrp = sp.char and X.root(sp.char)
	if not hrp then
		sp.lastPos = nil
		return
	end
	local pos = hrp.Position
	local lp, lt = sp.lastPos, sp.lastPosAt
	sp.lastPos, sp.lastPosAt = pos, now
	if not lp or not sp.applied then
		sp.lastDir = nil
		return
	end
	local dt = now - lt
	if dt <= 0 or dt > 0.5 then
		sp.lastDir = nil
		return
	end
	local dx, dz = pos.X - lp.X, pos.Z - lp.Z
	local d = math.sqrt(dx * dx + dz * dz)
	local lim = math.max(CONFIG.SPEED_RB_MIN, state.speedValue * dt * 2.5)
	local ld = sp.lastDir
	if d > lim then
		if ld and dx * ld.x + dz * ld.z < 0 then
			local rb = sp.rb
			rb[#rb + 1] = now
			while #rb > 0 and now - rb[1] > CONFIG.SPEED_RB_WINDOW do
				table.remove(rb, 1)
			end
			if #rb >= CONFIG.SPEED_RB_COUNT then
				sp.pause(now, sp.rbStep, "server rollback")
				sp.rbStep = math.min(sp.rbStep * 2, 120)
			end
		end
		return -- прыжок позиции (откат или телепорт) не считаем направлением движения
	end
	if d > 0.5 then
		sp.lastDir = { x = dx / d, z = dz / d }
	end
end

local function speedEvaluateImpl()
	local hum = sp.hum
	if not hum then
		return
	end
	local now = os.clock()
	if not hum.Parent then
		-- Humanoid удалён или заменён игрой внутри того же персонажа: подключаемся к новому
		local ch = sp.char
		speedUnbind()
		if ch and ch.Parent and localPlayer.Character == ch and ch:FindFirstChildOfClass("Humanoid") then
			speedBind(ch)
		end
		return
	end
	sp.watchRubber(now)
	-- игра надолго подняла скорость (повышение уровня, постоянный бафф): это новая обычная скорость, иначе Speed
	-- замолчал бы до конца жизни персонажа. Снижение (Slow/Stun/Root) за обычную никогда не принимается.
	if sp.higherSince and sp.gameValue > sp.normal and now - sp.higherSince >= CONFIG.SPEED_ADOPT
		and not statusBlocked(hum) and not statusBlocked(sp.char) then
		sp.normal = sp.gameValue
		sp.normals[sp.normal] = true
		sp.higherSince = nil
	end
	local active = state.speedEnabled and moduleOk.speed and not sp.unsupported
	local paused = now < sp.pauseUntil
	if sp.pauseShown ~= paused then
		sp.pauseShown = paused
		if speedUiHook then
			speedUiHook()
		end
	end
	if not paused and sp.lastFightAt > 0 and now - sp.lastFightAt > 10 then
		sp.pauseStep = CONFIG.SPEED_PAUSE_MIN -- борьба давно закончилась: следующая пауза снова короткая
	end
	local ok, hard = speedAllowed()
	-- окончание эффекта игры: возвращаем свою скорость не сразу, а через SPEED_RESUME_DELAY (игра успевает закончить свою
	-- последовательность, и мы не ускоряем выход из Stun)
	if active and (hard or paused) then
		sp.hardPrev = true
	elseif sp.hardPrev and active then
		sp.hardPrev = false
		sp.resumeAt = now + CONFIG.SPEED_RESUME_DELAY
	end
	local waiting = active and ok and not paused and now < sp.resumeAt
	local want = active and ok and not paused and not waiting
	if waiting and sp.delayAt ~= sp.resumeAt then
		sp.delayAt = sp.resumeAt
		local tok = sp.token
		task.delay(sp.resumeAt - now + 0.02, function()
			if tok == sp.token and not destroyed then
				speedEvaluate()
			end
		end)
	end
	if want then
		if hum.WalkSpeed ~= state.speedValue or sp.lastWritten ~= state.speedValue then
			speedWrite(state.speedValue)
		end
		sp.held = state.speedValue
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
	local now = os.clock()
	if not hadApplied and sp.held ~= nil and ws == sp.held and sp.gameValue ~= sp.normal and state.speedEnabled then
		-- игра сама вернула то значение, которое мы держали (например, умножила скорость на 0.5 и потом на 2):
		-- это возврат к нашему режиму, а не новая «обычная» скорость игры
		sp.gameValue = sp.normal
		sp.lastWritten = ws
		sp.applied = true
		speedEvaluate()
		return
	end
	sp.lastWritten = nil
	sp.applied = false
	sp.gameValue = ws
	if sp.normals[ws] then
		sp.normal = ws -- игра вернулась к скорости, которую уже держала как обычную
	end
	if ws > sp.normal then
		if not sp.higherSince then
			sp.higherSince = now
		end
	else
		sp.higherSince = nil
	end
	if now < sp.settleUntil and ws > 0 and not statusBlocked(hum) and not statusBlocked(sp.char) then
		sp.normal = ws -- игра ещё выставляет стартовую скорость после появления (0 и эффекты контроля за «обычную» не принимаем)
		sp.normals[ws] = true
		sp.higherSince = nil
	end
	if hadApplied and ws == sp.normal then
		-- игра откатила наше значение. Каждый откат исправляем один раз (по событию, не циклом); частые откаты =
		-- игра борется с нами: пауза с нарастанием, потом новая попытка (а не отключение навсегда)
		sp.resets[#sp.resets + 1] = now
		sp.lastFightAt = now
		while #sp.resets > 0 and now - sp.resets[1] > CONFIG.SPEED_FIGHT_WINDOW do
			table.remove(sp.resets, 1)
		end
		if #sp.resets >= CONFIG.SPEED_FIGHT_LIMIT then
			sp.pause(now, sp.pauseStep, "game resets")
			sp.pauseStep = math.min(sp.pauseStep * 2, CONFIG.SPEED_PAUSE_MAX)
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
		X.try("speed.restore", function()
			hum.WalkSpeed = sp.gameValue
		end)
	end
	sp.hum = nil
	sp.char = nil
	sp.applied = false
	sp.lastWritten = nil
	sp.held = nil
	sp.hardPrev = false
	sp.resumeAt = 0
	sp.delayAt = 0
	sp.pauseUntil = 0
	sp.pauseShown = false
	sp.lastPos = nil
	sp.lastDir = nil
	table.clear(sp.resets)
	table.clear(sp.rb)
end

speedBind = function(char)
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
		sp.normals = { [hum.WalkSpeed] = true }
		sp.higherSince = nil
		sp.lastWritten = nil
		sp.applied = false
		sp.settleUntil = os.clock() + CONFIG.SPEED_SETTLE
		sp.pauseStep = CONFIG.SPEED_PAUSE_MIN
		sp.rbStep = CONFIG.SPEED_RB_PAUSE
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
X.try("stick.touchMode", function()
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
		conns = {},          -- подключения именно к этому стику (отключаются, когда игра его уничтожила)
		centerSince = nil,   -- с какого момента шарик стоит по центру при «активном» пальце
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

	local function keep(c)
		X.stickConns[#X.stickConns + 1] = c
		rec.conns[#rec.conns + 1] = c
	end

	keep(frame.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or rec.active then
			return
		end
		rec.active = input
		rec.centerSince = nil
		input.Changed:Connect(function()
			local st = input.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				if rec.active == input then
					rec.active = nil
				end
				task.defer(centerKnob)
			end
		end)
	end))

	keep(stick:GetPropertyChangedSignal("Position"):Connect(function()
		if rec.active then
			local st = rec.active.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				rec.active = nil
			end
		end
		if not rec.active then
			centerKnob()
		end
	end))

	-- Поворот экрана / перестройка интерфейса игрой: пересчитать "своё" положение чуть позже.
	local parent = frame.Parent
	if parent and parent:IsA("GuiObject") then
		keep(parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			rec.relayout = true
			rec.pauseUntil = os.clock() + 0.5
		end))
	end
end

-- Стандартный код Roblox после отпускания пальца возвращает стик на родное место внизу.
-- Пока палец не на стике, возвращаем его на своё место; пока палец на стике, не мешаем.
function X.stickEnforce()
	if not CONFIG.STICK_LOCK then
		return
	end
	local now = os.clock()
	local list = X.stickOrig
	local i = 1
	while i <= #list do
		local rec = list[i]
		local f = rec.frame
		if not f.Parent or not f:IsDescendantOf(playerGui) then
			-- игра пересоздала интерфейс (респавн, смена режима): запись о старом стике не копим
			for _, c in ipairs(rec.conns) do
				c:Disconnect()
			end
			table.remove(list, i)
			i -= 1
		else
			local act = rec.active
			if act then
				local st = act.UserInputState
				if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
					rec.active = nil -- потерянное событие End
				else
					-- «залипший» палец: событие End не пришло (лаги, потеря фокуса), состояние не сменилось.
					-- Если шарик больше секунды стоит ровно по центру, пальца на стике уже нет.
					local centered = rec.stick.Position == UDim2.fromOffset(
						(f.Size.X.Offset - rec.stick.Size.X.Offset) / 2,
						(f.Size.Y.Offset - rec.stick.Size.Y.Offset) / 2
					)
					if centered then
						rec.centerSince = rec.centerSince or now
						if now - rec.centerSince > 1 then
							rec.active = nil
							rec.centerSince = nil
						end
					else
						rec.centerSince = nil
					end
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
		i += 1
	end
end
X.stickGuarded = guarded("stick", X.stickEnforce)

-- Глобальное завершение касания приходит надёжнее, чем изменение состояния объекта ввода конкретного стика.
track(UserInputService.TouchEnded:Connect(function(input)
	for _, rec in ipairs(X.stickOrig) do
		if rec.active == input then
			rec.active = nil
			rec.centerSince = nil
		end
	end
end))

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

---------------------------------------------------------------- AUTO-MANEUVER: умное автоматическое уклонение
-- Игрок управляет сам: модуль НЕ трогает камеру, Humanoid:Move, WalkSpeed и ввод. Единственное его действие -
-- короткий боковой рывок (~0.2 с) через LinearVelocity в режиме "Line": ограничивается скорость ТОЛЬКО вдоль
-- линии рывка, всё остальное (ходьба, прыжок, поворот) продолжает работать от руки.
-- Угрозы определяются только по наблюдаемым данным клиента (никаких выдуманных событий игры):
--   1. Снаряды: свободные детали, быстро летящие к игроку. Скорость берётся из AssemblyLinearVelocity
--      (или по смещению позиции у anchored-деталей), траектория считается заранее, с учётом гравитации.
--   2. Ближний бой: противник (игрок или враждебный NPC) смотрит на игрока, а его оружие/рука быстро
--      движется к игроку на расстоянии удара.
--   3. Зоны: быстро растущие несталкивающиеся детали (расходящиеся круги), которые дойдут до игрока.
-- Рывок включается только если без него попадание предсказывается и с ним зазор действительно появляется.
-- Если игрок уже сам уходит с линии удара, угрозы нет и модуль ничего не делает.
X.mv = {
	char = nil, hum = nil, hrp = nil, att = nil, lv = nil, ovp = nil, rp = nil,
	thr = {}, thrN = 0, pool = {},
	byPart = setmetatable({}, { __mode = "k" }),   -- [деталь] = запись угрозы-снаряда
	seen = setmetatable({}, { __mode = "k" }),     -- [деталь] = наблюдения (позиция, скорость, "пропустить до")
	enemy = setmetatable({}, { __mode = "k" }),    -- [модель врага] = слежение за оружием
	near = {}, nearN = 0, nearAt = 0, pruneAt = 0, meleeUntil = 0,
	hazN = 0, learned = {}, learnedN = 0, attackers = setmetatable({}, { __mode = "k" }),
	nameHint = {}, nameHintN = 0, animCache = {}, hconn = nil, hp = nil, lastHurtAt = 0,
	nextScan = 0, alertUntil = 0, guardAt = 0, ok = false, retryAt = 0, statusAt = 0, statusBad = false,
	dashing = false, dashStart = 0, dashDx = 0, dashDz = 0, dashV0 = 0, dashD = 0, dashA = 0, dashT = 0.45,
	cdUntil = 0, lastSide = 0, lastAt = -10, sameCount = 0,
	ping = 0, pingAt = 0, okStates = nil,
	stats = { dodges = 0, proj = 0, melee = 0, zone = 0, noSafe = 0, haz = 0, anim = 0, hurt = 0, learned = 0 },
	lastDodge = nil,
}

local MV_STEP = 0.04 -- шаг расчёта траектории (сек)

-- смещение при рывке за t секунд: скорость линейно падает от V0 до 0 за T, итоговое смещение D
-- «Ходьба» (Humanoid:Move) или рывок (LinearVelocity). Если игра игнорирует Humanoid:Move, включается запасной рывок.
function X.mv.walkStyle()
	return CONFIG.MV_STYLE == "walk" and not X.mv.fallbackDash
end

function X.mv.disp(t, D, T)
	if t <= 0 then
		return 0
	end
	if t >= T then
		return D
	end
	if X.mv.walkStyle() then
		-- обычная ходьба: короткий разгон, затем постоянная скорость (скорость персонажа не превышается)
		local r = CONFIG.MV_WALK_RAMP
		local V = D / (T - 0.5 * r)
		if t < r then
			return 0.5 * V * t * t / r
		end
		return 0.5 * V * r + V * (t - r)
	end
	local u = t / T
	return D * (0.5 * (2 * u - u * u) + 0.5 * u * u * (3 - 2 * u)) -- смесь: мягкий старт, но без запаздывания
end

---------------------------------------------------------------- объекты рывка
function X.mv.release(destroyObjects)
	local M = X.mv
	M.dashing = false
	if destroyObjects and M.hconn then
		M.hconn:Disconnect()
		M.hconn = nil
	end
	if M.lv then
		X.try("mv.lvOff", function()
			M.lv.Enabled = false
			M.lv.LineVelocity = 0
		end)
		if destroyObjects then
			X.try("mv.lvDestroy", function()
				M.lv:Destroy()
			end)
			M.lv = nil
		end
	end
	if destroyObjects and M.att then
		X.try("mv.attDestroy", function()
			M.att:Destroy()
		end)
		M.att = nil
	end
end

function X.mv.clearThreats()
	local M = X.mv
	for i = 1, M.thrN do
		local t = M.thr[i]
		t.part = nil
		t.model = nil
		M.pool[#M.pool + 1] = t
		M.thr[i] = nil
	end
	M.thrN = 0
	M.hazN = 0
	table.clear(M.byPart)
	M.nearN = 0
	for i = 1, #M.near do
		local n = M.near[i]
		n.model = nil
		n.root = nil
	end
end

function X.mv.attach(char)
	local M = X.mv
	M.release(true)
	M.clearThreats()
	M.char, M.hum, M.hrp, M.ovp, M.rp = char, nil, nil, nil, nil
	M.ok = false
	M.moveFails = 0
	if not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = X.root(char)
	if not (hum and hrp and hrp:IsA("BasePart")) then
		M.retryAt = os.clock() + 0.5 -- персонаж ещё собирается
		return
	end
	for _, n in ipairs({ "AM_LV", "AM_Att" }) do
		local old = hrp:FindFirstChild(n)
		if old then
			old:Destroy()
		end
	end
	local att, lv = nil, nil
	if not X.mv.walkStyle() then
		att = Instance.new("Attachment")
		att.Name = "AM_Att"
		att.Parent = hrp
		lv = Instance.new("LinearVelocity")
		lv.Name = "AM_LV"
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		lv.LineDirection = Vector3.new(1, 0, 0)
		lv.LineVelocity = 0
		lv.MaxForce = 1e7
		lv.Enabled = false
		lv.Parent = hrp
	end

	local ovp = OverlapParams.new()
	ovp.FilterType = Enum.RaycastFilterType.Exclude
	ovp.FilterDescendantsInstances = { char }
	ovp.MaxParts = CONFIG.MV_MAX_PARTS
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char }
	rp.RespectCanCollide = true
	rp.IgnoreWater = true

	M.hum, M.hrp, M.att, M.lv, M.ovp, M.rp = hum, hrp, att, lv, ovp, rp
	M.hp = hum.Health
	local hsig = hum.HealthChanged
	if hsig then
		M.hconn = hsig:Connect(X.mv.onHealth)
	end
	M.okStates = M.okStates or {
		[Enum.HumanoidStateType.Running] = true,
		[Enum.HumanoidStateType.RunningNoPhysics] = true,
		[Enum.HumanoidStateType.Landed] = true,
		[Enum.HumanoidStateType.Jumping] = true,
		[Enum.HumanoidStateType.Freefall] = true,
	}
end

-- Можно ли сейчас вмешиваться: живой персонаж в обычном состоянии, без оглушения/корней/сидения.
function X.mv.canAct(now)
	local M = X.mv
	local hum, hrp, char = M.hum, M.hrp, M.char
	if not (char and hum and hrp) or not char.Parent or not hrp.Parent or not hum.Parent then
		return false
	end
	if hum.Health <= 0 or hum.PlatformStand or hum.Sit or hrp.Anchored or hum.WalkSpeed <= 0.05 then
		return false
	end
	if not M.okStates[hum:GetState()] then
		return false
	end
	if now >= M.statusAt then
		M.statusAt = now + 0.25
		M.statusBad = statusBlocked(char) -- оглушение, захват, способность и т.п. (те же признаки, что у Speed)
	end
	return not M.statusBad
end

---------------------------------------------------------------- угрозы: пул записей
function X.mv.newThreat(kind, now)
	local M = X.mv
	local n = #M.pool
	local t
	if n > 0 then
		t = M.pool[n]
		M.pool[n] = nil
	else
		t = {}
	end
	M.thrN += 1
	M.thr[M.thrN] = t
	t.kind = kind
	t.t = now
	t.seen = now
	t.dead = false
	return t
end

function X.mv.dropThreat(i)
	local M = X.mv
	local t = M.thr[i]
	if t.kind == 4 then
		M.hazN = math.max(M.hazN - 1, 0)
	end
	if t.part then
		M.byPart[t.part] = nil
	end
	t.part = nil
	t.model = nil
	M.pool[#M.pool + 1] = t
	M.thr[i] = M.thr[M.thrN]
	M.thr[M.thrN] = nil
	M.thrN -= 1
end

-- Деталь принадлежит персонажу или NPC (конечности, оружие в руках): это не снаряд.
function X.mv.isBody(part)
	local m = part:FindFirstAncestorWhichIsA("Model")
	local depth = 0
	while m and depth < 4 do
		if entities[m] or m:FindFirstChildOfClass("Humanoid") then
			return true
		end
		m = m.Parent and m.Parent:FindFirstAncestorWhichIsA("Model") or nil
		depth += 1
	end
	return false
end

---------------------------------------------------------------- наблюдение за деталями вокруг
function X.mv.observe(part, now, mvx, mvy, mvz, myx, myy, myz)
	local M = X.mv
	local rec = M.seen[part]
	local first = false
	if not rec then
		rec = { x = 0, y = 0, z = 0, t = 0, m = 0, vx = 0, vy = 0, vz = 0, skip = 0, n = 0 }
		M.seen[part] = rec
		first = true
		if part.ClassName == "Terrain" or M.isBody(part) then
			rec.skip = now + 10 -- часть тела: не снаряд
			return
		end
		rec.hp, rec.hz, rec.hs = M.hintOf(part)
		if not part.CanTouch and not part.CanCollide and not rec.hs then
			rec.skip = now + 10 -- не может нанести урон касанием и не помечена как опасная
			return
		end
		if rec.hz and not rec.hs and not part.CanTouch then
			rec.hz = false -- статичная «опасная» деталь без касаний урона не наносит
		end
	elseif now < rec.skip then
		return
	end
	local p = part.Position
	local px, py, pz = p.X, p.Y, p.Z
	local s = part.Size
	local m = math.max(s.X, s.Y, s.Z)
	if m > 300 then
		rec.skip = now + 5
		return
	end
	local vx, vy, vz
	local anchored = part.Anchored
	local dt = now - rec.t
	if anchored then
		if first or rec.n == 0 or dt > 0.5 then
			rec.x, rec.y, rec.z, rec.t, rec.m, rec.n = px, py, pz, now, m, 1
			return -- нужна вторая точка для скорости
		end
		if dt < 0.02 then
			return
		end
		vx, vy, vz = (px - rec.x) / dt, (py - rec.y) / dt, (pz - rec.z) / dt
		-- растущая круглая зона (расходящийся круг/взрыв): быстро увеличивается, не сталкивается
		local growth = (m - rec.m) / dt
		rec.x, rec.y, rec.z, rec.t = px, py, pz, now
		local dm = m - rec.m
		rec.m = m
		if growth >= CONFIG.MV_ZONE_GROWTH and dm >= 0.3 and m >= 5 and not part.CanCollide then
			M.zoneSeen(part, now, px, py, pz, m, growth, s.Y, myx, myz)
			return
		end
	else
		local v = part.AssemblyLinearVelocity
		vx, vy, vz = v.X, v.Y, v.Z
	end
	local rvx, rvy, rvz = vx - mvx, vy - mvy, vz - mvz
	local sp2 = rvx * rvx + rvy * rvy + rvz * rvz
	local minSp = CONFIG.MV_MIN_SPEED
	local slow = sp2 < minSp * minSp
	if rec.hp or M.learned[part.Name] then
		minSp = CONFIG.MV_HINT_SPEED -- «боевое» имя / атрибут Damage / деталь, которая уже ранила: порог ниже
		-- сниженный порог применяется к собственной скорости детали, иначе стоячая деталь «летит» на бегущего игрока
		slow = vx * vx + vy * vy + vz * vz < minSp * minSp or sp2 < minSp * minSp
	end
	if slow or m > CONFIG.MV_MAX_SIZE then
		rec.skip = now + 0.25
		rec.vx, rec.vy, rec.vz = vx, vy, vz
		if slow then
			local spun = false
			if m >= 6 and m <= 40 and (rec.hz or rec.hp or M.learned[part.Name]) then
				spun = M.spinSeen(part, rec, now, px, py, pz, m, s, anchored, myx, myz)
			end
			if rec.hz and not spun then
				M.hazardSeen(part, rec, now, myx, myy, myz)
			end
		end
		return
	end
	-- должен лететь К игроку (иначе это не угроза)
	local dx, dy, dz = myx - px, myy - py, myz - pz
	if rvx * dx + rvy * dy + rvz * dz <= 0 then
		rec.skip = now + 0.15
		rec.vx, rec.vy, rec.vz = vx, vy, vz
		return
	end
	-- ускорение (гравитация/разгон) по изменению скорости между наблюдениями
	local ay = 0
	local th = M.byPart[part]
	if th then
		local dts = now - th.t
		if dts > 0.02 then
			ay = (vy - th.vy) / dts
			ay = math.clamp(ay, -300, 60)
			if math.abs(ay) < 15 then
				ay = 0
			end
		else
			ay = th.ay
		end
	else
		th = M.newThreat(1, now)
		th.part = part
		M.byPart[part] = th
		M.stats.proj += 1
		ay = 0
	end
	th.px, th.py, th.pz = px, py, pz
	th.vx, th.vy, th.vz = vx, vy, vz
	th.ay = ay
	th.t = now
	th.seen = now
	th.r = m * 0.5 + CONFIG.MV_BODY_RADIUS + CONFIG.MV_HIT_MARGIN * 0.5
	rec.vt = now
	M.alertUntil = now + 0.5
end

---------------------------------------------------------------- подсказки: что в данных детали говорит об опасности
-- Используются только реально доступные клиенту данные: имя детали, атрибуты Damage/DamageAmount/Dmg/Hurt/Kill,
-- дочернее NumberValue/IntValue "Damage". Результат по имени кэшируется (одинаковые имена не проверяются заново).
X.mv.words = {
	proj = { "bullet", "projectile", "missile", "rocket", "arrow", "fireball", "bolt", "shard", "dart", "kunai",
		"shuriken", "spear", "knife", "grenade", "cannon", "spell", "blast", "slash", "hitbox", "laser", "orb" },
	haz = { "lava", "acid", "poison", "toxic", "spike", "trap", "saw", "blade", "laser", "fire", "flame", "burn",
		"hazard", "danger", "kill", "death", "hurt", "damage", "electr", "shock", "mine", "spin", "rotor", "propeller" },
}
X.mv.dmgAttrs = { "Damage", "DamageAmount", "Dmg", "Hurt", "Kill" }

function X.mv.hintOf(part)
	local M = X.mv
	local nm = part.Name
	local h = M.nameHint[nm]
	if not h then
		local l = string.lower(nm)
		h = { p = false, z = false }
		for _, w in ipairs(M.words.proj) do
			if string.find(l, w, 1, true) then
				h.p = true
				break
			end
		end
		for _, w in ipairs(M.words.haz) do
			if string.find(l, w, 1, true) then
				h.z = true
				break
			end
		end
		if h.p and string.find(l, "ball", 1, true) then
			h.z = false -- «fireball» - снаряд, а не лужа огня
		end
		M.nameHintN += 1
		if M.nameHintN > 400 then
			table.clear(M.nameHint)
			M.nameHintN = 0
		end
		M.nameHint[nm] = h
	end
	local strong = false
	for i = 1, #M.dmgAttrs do
		if part:GetAttribute(M.dmgAttrs[i]) ~= nil then
			strong = true
			break
		end
	end
	if not strong then
		local c = part:FindFirstChild("Damage")
		if c and (c:IsA("NumberValue") or c:IsA("IntValue")) then
			strong = true
		end
	end
	return h.p or strong, h.z or strong, strong
end

-- Статичная (или медленная) опасная деталь: лава, шипы, пила, зона урона. Учитывается как прямоугольник на земле.
function X.mv.hazardSeen(part, rec, now, myx, myy, myz)
	local M = X.mv
	local p = part.Position
	local s = part.Size
	local dx, dz = myx - p.X, myz - p.Z
	local far = math.max(s.X, s.Z) * 0.71 + CONFIG.MV_HAZ_RANGE
	if dx * dx + dz * dz > far * far then
		rec.skip = now + 0.6
		return
	end
	local th = M.byPart[part]
	if not th then
		if M.hazN >= CONFIG.MV_HAZ_MAX then
			return
		end
		th = M.newThreat(4, now)
		th.part = part
		M.byPart[part] = th
		M.hazN += 1
		M.stats.haz += 1
	end
	local cf = part.CFrame
	local r, l = cf.RightVector, cf.LookVector
	local rl = math.sqrt(r.X * r.X + r.Z * r.Z)
	local ll = math.sqrt(l.X * l.X + l.Z * l.Z)
	if rl > 0.3 and ll > 0.3 then
		th.ax, th.az, th.bx, th.bz = r.X / rl, r.Z / rl, l.X / ll, l.Z / ll
	else
		th.ax, th.az, th.bx, th.bz = 1, 0, 0, 1
	end
	th.hx, th.hz, th.hh = s.X * 0.5, s.Z * 0.5, s.Y * 0.5
	th.cx, th.cy, th.cz = p.X, p.Y, p.Z
	th.seen = now
	th.t = now
	rec.skip = now + 0.3
end

-- Вращающаяся опасная деталь (пила, пропеллер): круг радиусом в половину размера вокруг её центра.
function X.mv.spinSeen(part, rec, now, px, py, pz, m, s, anchored, myx, myz)
	local M = X.mv
	local omega = 0
	if anchored then
		local l = part.CFrame.LookVector
		local a = math.atan2(l.X, l.Z)
		local pa, dt = rec.ang, now - (rec.angT or 0)
		rec.ang, rec.angT = a, now
		if pa and dt >= 0.04 and dt <= 0.6 then
			local da = a - pa
			if da > math.pi then
				da -= 2 * math.pi
			elseif da < -math.pi then
				da += 2 * math.pi
			end
			omega = math.abs(da) / dt
		end
	else
		omega = part.AssemblyAngularVelocity.Magnitude
	end
	if omega * m * 0.5 >= CONFIG.MV_SPIN_TIP then
		M.zoneSeen(part, now, px, py, pz, m, 0, s.Y, myx, myz)
		return true
	end
	return false
end

---------------------------------------------------------------- обучение на полученном уроне
-- Любой урон, который пришёл не из распознанной угрозы, - источник знаний: детали и враги рядом в момент урона
-- запоминаются, и в следующий раз такие детали считаются опасными с меньшим порогом скорости.
X.mv.generic = { Part = true, Baseplate = true, Terrain = true, Handle = true, Head = true, Torso = true,
	HumanoidRootPart = true, Union = true, MeshPart = true, Wedge = true, SpawnLocation = true, Floor = true, Ground = true }

function X.mv.onHealth(h)
	local M = X.mv
	local prev = M.hp or h
	M.hp = h
	if h >= prev - 0.5 or not M.hrp then
		return
	end
	local now = os.clock()
	if now - M.lastHurtAt < 0.25 then
		return
	end
	M.lastHurtAt = now
	M.stats.hurt += 1
	local p = M.hrp.Position
	local parts = Workspace:GetPartBoundsInRadius(p, 14, M.ovp)
	for i = 1, math.min(#parts, 150) do
		local part = parts[i]
		local nm = part.Name
		if not M.generic[nm] and not M.learned[nm] and part.ClassName ~= "Terrain" then
			local model = part:FindFirstAncestorWhichIsA("Model")
			local body = M.isBody(part)
			if body then
				if model and model ~= M.char then
					M.attackers[model] = now + 20 -- этот враг только что ранил: его замахи ловим с меньшим порогом
				end
			else
				local rec = M.seen[part]
				local moving = rec and (rec.vx * rec.vx + rec.vy * rec.vy + rec.vz * rec.vz) >= 64
				if (moving or (rec and (rec.hp or rec.hz))) and M.learnedN < 40 then
					M.learned[nm] = true
					M.learnedN += 1
					M.stats.learned += 1
				end
			end
		end
	end
end

function X.mv.zoneSeen(part, now, px, py, pz, m, growth, sy, myx, myz)
	local M = X.mv
	if M.byPart[part] then
		local th = M.byPart[part]
		th.cx, th.cz, th.cy = px, pz, py
		th.r0 = m * 0.5
		th.g = growth * 0.5
		th.t = now
		th.seen = now
		return
	end
	local dx, dz = myx - px, myz - pz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < CONFIG.MV_ZONE_SELF then
		return -- круг рождается прямо под игроком: скорее всего его собственная способность
	end
	if d > m * 0.5 + growth * 0.5 * CONFIG.MV_ZONE_EXTRAP + (growth > 0 and 4 or 14) then -- неподвижный круг (вращающаяся деталь) виден заранее
		return -- не дорастёт до игрока за время обзора
	end
	local th = M.newThreat(3, now)
	th.part = part
	M.byPart[part] = th
	th.cx, th.cz, th.cy = px, pz, py
	th.r0 = m * 0.5
	th.g = growth * 0.5
	th.hh = sy * 0.5
	M.stats.zone += 1
	M.alertUntil = now + 0.5
end

function X.mv.scan(now)
	local M = X.mv
	local hrp = M.hrp
	local p = hrp.Position
	local hv = hrp.AssemblyLinearVelocity
	local parts = Workspace:GetPartBoundsInRadius(p, CONFIG.MV_SCAN_RADIUS, M.ovp)
	local mvx, mvy, mvz = hv.X, hv.Y, hv.Z
	local myx, myy, myz = p.X, p.Y, p.Z
	for i = 1, #parts do
		M.observe(parts[i], now, mvx, mvy, mvz, myx, myy, myz)
	end
end

---------------------------------------------------------------- ближний бой
function X.mv.refreshNear(now)
	local M = X.mv
	local hrp = M.hrp
	local p = hrp.Position
	local limit = CONFIG.MV_MELEE_RANGE + 8
	local limit2 = limit * limit
	local n = 0
	local function consider(model)
		local root = X.root(model)
		if not (root and root:IsA("BasePart")) then
			return
		end
		local rp = root.Position
		local dx, dz = rp.X - p.X, rp.Z - p.Z
		if dx * dx + dz * dz > limit2 or math.abs(rp.Y - p.Y) > 14 then
			return
		end
		n += 1
		local rec = M.near[n]
		if not rec then
			rec = {}
			M.near[n] = rec
		end
		rec.model = model
		rec.root = root
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if isEnemyPlayer(pl) then
			local c = pl.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if c and h and isAlive(h) then
				consider(c)
			end
		end
	end
	for model, e in pairs(entities) do
		if e.confirmed and model ~= M.char and X.npcHostile(model, now) and entityAlive(e) then
			consider(model)
		end
	end
	for i = n + 1, M.nearN do
		local r = M.near[i]
		r.model = nil
		r.root = nil
	end
	M.nearN = n
	-- записи слежения хранят деталь оружия (она ссылается на модель): удаляем записи ушедших врагов явно
	if now >= M.pruneAt then
		M.pruneAt = now + 5
		for model in pairs(M.enemy) do
			if not model.Parent then
				M.enemy[model] = nil
			end
		end
	end
end

local MV_HANDS = { "RightHand", "Right Arm", "LeftHand", "Left Arm" }

function X.mv.weaponPart(model)
	local tool = model:FindFirstChildOfClass("Tool")
	if tool then
		local h = tool:FindFirstChild("Handle")
		if h and h:IsA("BasePart") then
			return h
		end
	end
	for _, n in ipairs(MV_HANDS) do
		local p = model:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

-- Анимация атаки врага: самый ранний признак удара (замах ещё не начался в движении руки).
-- Берутся только проигрываемые дорожки Animator врага (реплицируются на клиент); начало ударной фазы оценивается
-- по доле длины дорожки (точный кадр попадания клиенту неизвестен), безопасность проверяется тем же конусом удара.
X.mv.noAttack = { "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "emote", "dance", "wave", "laugh",
	"cheer", "point", "taunt", "gethit", "hurt", "react", "stun", "knock", "damage", "death", "die", "block", "parry",
	"dodge", "roll", "flinch", "equip", "unequip", "toolnone" }
X.mv.attackWords = { "attack", "slash", "swing", "punch", "kick", "strike", "hit", "combo", "stab", "smash", "slam",
	"cleave", "thrust", "swipe", "bite", "claw", "pound", "lunge", "jab", "melee", "chop", "bash", "m1" }

function X.mv.isAttackAnim(name)
	local M = X.mv
	local v = M.animCache[name]
	if v == nil then
		local l = string.lower(name)
		v = false
		for _, w in ipairs(M.noAttack) do
			if string.find(l, w, 1, true) then
				M.animCache[name] = false
				return false
			end
		end
		for _, w in ipairs(M.attackWords) do
			if string.find(l, w, 1, true) then
				v = true
				break
			end
		end
		M.animCache[name] = v
	end
	return v
end

-- Дорожка «ударного» вида: приоритет Action..Action4, не зациклена, разумной длины. Работает и когда название
-- дорожки ничего не говорит (Animation, 123456...). Имена из noAttack (эмоции, получение урона, блок) исключаются.
X.mv.noAttackCache = {}
function X.mv.isActionTrack(tr)
	local M = X.mv
	if not CONFIG.MV_ANIM_ANY or tr.Looped then
		return false
	end
	local pr = tr.Priority
	if pr ~= Enum.AnimationPriority.Action and pr ~= Enum.AnimationPriority.Action2
		and pr ~= Enum.AnimationPriority.Action3 and pr ~= Enum.AnimationPriority.Action4 then
		return false
	end
	local len = tr.Length
	if len < 0.15 or len > 5 then
		return false
	end
	local name = tr.Name
	local blocked = M.noAttackCache[name]
	if blocked == nil then
		blocked = false
		local l = string.lower(name)
		for _, w in ipairs(M.noAttack) do
			if string.find(l, w, 1, true) then
				blocked = true
				break
			end
		end
		M.noAttackCache[name] = blocked
	end
	return not blocked
end

function X.mv.animScan(model, rec, root, now, dist, dx, dz, mx, my, mz)
	local M = X.mv
	if dist > CONFIG.MV_ANIM_REACH or (rec.animAt or 0) > now then
		return
	end
	rec.animAt = now + 0.06
	local an = rec.animator
	if not (an and an.Parent) then
		if (rec.animFind or 0) > now then
			return
		end
		rec.animFind = now + 2
		an = model:FindFirstChildWhichIsA("Animator", true)
		rec.animator = an
		if not an then
			return
		end
	end
	local tracks = an:GetPlayingAnimationTracks()
	local found = nil
	for i = 1, #tracks do
		local tr = tracks[i]
		if M.isAttackAnim(tr.Name) or M.isActionTrack(tr) then
			found = tr
			local len, pos = tr.Length, tr.TimePosition
			local fresh = tr ~= rec.aTrack or pos < (rec.aPos or 0) - 0.01
			rec.aTrack, rec.aPos = tr, pos
			if fresh and len > 0.1 and pos <= len * 0.3 and now >= (rec.cd or 0) then
				local look = root.CFrame.LookVector
				local hl = math.sqrt(look.X * look.X + look.Z * look.Z)
				local facing = hl > 0.01 and (look.X * dx + look.Z * dz) / (hl * dist) or 0
				if facing >= 0.3 and dist <= CONFIG.MV_MELEE_REACH + 2.5 then
					local rv = root.AssemblyLinearVelocity
					local rp = root.Position
					rec.cd = now + CONFIG.MV_MELEE_COOLDOWN
					local th = M.newThreat(2, now)
					th.model = model
					th.ex, th.ez = rp.X, rp.Z
					th.evx, th.evz = rv.X, rv.Z
					th.lx, th.lz = look.X / hl, look.Z / hl
					th.reach = CONFIG.MV_MELEE_REACH
					local spd = math.max(tr.Speed, 0.2)
					th.strikeAt = now + math.max(0.08, (len * 0.35 - pos) / spd)
					th.expire = th.strikeAt + 0.3
					M.stats.melee += 1
					M.stats.anim += 1
					M.alertUntil = now + 0.5
				end
			end
			break
		end
	end
	if not found then
		rec.aTrack = nil
	end
end

function X.mv.meleeScan(now)
	local M = X.mv
	local hrp = M.hrp
	local mp = hrp.Position
	local mx, my, mz = mp.X, mp.Y, mp.Z
	for i = 1, M.nearN do
		local nr = M.near[i]
		local model, root = nr.model, nr.root
		if model and root and root.Parent then
			local rp = root.Position
			local dx, dz = mx - rp.X, mz - rp.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= CONFIG.MV_MELEE_RANGE and dist > 0.05 then
				local rec = M.enemy[model]
				if not rec then
					rec = { tip = nil, tipAt = 0, tx = 0, ty = 0, tz = 0, tt = 0, cd = 0 }
					M.enemy[model] = rec
				end
				if now >= rec.tipAt or not (rec.tip and rec.tip.Parent) then
					rec.tipAt = now + 1
					rec.tip = M.weaponPart(model)
					rec.tt = 0
				end
				M.meleeUntil = now + 0.3
				M.animScan(model, rec, root, now, dist, dx, dz, mx, my, mz)
				local tip = rec.tip
				if tip then
					local tp = tip.Position
					local dt = now - rec.tt
					local tx, ty, tz = tp.X, tp.Y, tp.Z
					local px, py, pz = rec.tx, rec.ty, rec.tz
					rec.tx, rec.ty, rec.tz, rec.tt = tx, ty, tz, now
					if dt >= 0.02 and dt <= 0.25 and now >= rec.cd then
						local rv = root.AssemblyLinearVelocity
						-- скорость кончика оружия относительно корпуса противника
						local vx = (tx - px) / dt - rv.X
						local vy = (ty - py) / dt - rv.Y
						local vz = (tz - pz) / dt - rv.Z
						local ex, ey, ez = mx - tx, my - ty, mz - tz
						local ed = math.sqrt(ex * ex + ey * ey + ez * ez)
						if ed > 0.1 then
							local closing = (vx * ex + vy * ey + vz * ez) / ed
							local look = root.CFrame.LookVector
							local hl = math.sqrt(look.X * look.X + look.Z * look.Z)
							-- (dx, dz) направлен от врага к игроку; facing = 1, когда враг смотрит прямо на игрока
							local facing = hl > 0.01 and (look.X * dx + look.Z * dz) / (hl * dist) or 0
							local tipSpeed = CONFIG.MV_MELEE_TIP_SPEED
							if (M.attackers[model] or 0) > now then
								tipSpeed = tipSpeed * 0.6 -- враг уже ранил нас: реагируем на менее резкие замахи
							end
							if closing >= tipSpeed and ed <= CONFIG.MV_MELEE_REACH + 3 and facing >= 0.3 then
								rec.cd = now + CONFIG.MV_MELEE_COOLDOWN
								local th = M.newThreat(2, now)
								th.model = model
								th.ex, th.ez = rp.X, rp.Z
								th.evx, th.evz = rv.X, rv.Z
								th.lx, th.lz = look.X / hl, look.Z / hl
								th.reach = CONFIG.MV_MELEE_REACH
								th.strikeAt = now + math.max(0.05, (ed - 1.5) / closing)
								th.expire = th.strikeAt + 0.25
								M.stats.melee += 1
							end
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- расчёт зазора
-- Минимальный зазор (студы, меньше CONFIG.MV_HIT_THRESH = попадание) между телом и угрозой на tmax секунд вперёд.
-- Тело стартует в (qx, qz), идёт со своей скоростью (vx, vz) и дополнительно смещается рывком (dx, dz, D, T).
-- Возвращает зазор и время первого попадания (nil, если попадания нет).
function X.mv.clearance(th, now, qx, qy, qz, vx, vz, dx, dz, D, T, delay, tmax, arc)
	local best = 1e9
	local tFirst = nil
	local kind = th.kind
	local base = now - th.t
	local thresh = CONFIG.MV_HIT_THRESH
	local bodyHalf = CONFIG.MV_BODY_HALF
	local nSteps = math.floor(tmax / MV_STEP)
	local walk = X.mv.walkStyle()
	local insideStart = false
	for k = 0, nSteps do
		local t = k * MV_STEP
		local ox, oz = qx + vx * t, qz + vz * t
		if D > 0 and walk then
			-- пока ведёт уклоняющее движение, собственное движение игрока заменено им
			local te = math.min(t, delay) + math.max(t - delay - T, 0)
			ox, oz = qx + vx * te, qz + vz * te
		end
		if D > 0 then
			local s = X.mv.disp(t - delay, D, T)
			if arc and arc ~= 0 then
				local u = math.clamp((t - delay) / T, 0, 1)
				local psi = 0.5 * arc * u * u * (3 - 2 * u)
				local cs, sn = math.cos(psi), math.sin(psi)
				ox += s * (dx * cs - dz * sn)
				oz += s * (dx * sn + dz * cs)
			else
				ox += dx * s
				oz += dz * s
			end
		end
		local c = 99
		local tau = base + t
		if kind == 1 then
			local px = th.px + th.vx * tau
			local pz = th.pz + th.vz * tau
			local py = th.py + th.vy * tau + 0.5 * th.ay * tau * tau
			local hx, hz = px - ox, pz - oz
			local vo = math.abs(py - qy) - bodyHalf
			if vo < 0 then
				vo = 0
			end
			c = math.sqrt(hx * hx + hz * hz + vo * vo) - th.r
		elseif kind == 2 then
			local ts = th.strikeAt - now
			if t >= ts - 0.06 and t <= ts + 0.2 then
				local rx, rz = ox - (th.ex + th.evx * tau), oz - (th.ez + th.evz * tau)
				local d = math.sqrt(rx * rx + rz * rz)
				if d < 0.1 then
					c = -th.reach
				elseif (th.lx * rx + th.lz * rz) / d >= CONFIG.MV_MELEE_CONE_COS then
					c = d - th.reach -- удар идёт только вперёд от врага: вне конуса безопасно
				else
					c = 2
				end
			end
		elseif kind == 4 then
			-- статичная опасная деталь: расстояние до её прямоугольника на земле (внутри = ноль).
			-- Для оценки рывка время до его завершения не считается: из зоны, в которой игрок уже стоит, иначе не выйти.
			if math.abs(qy - th.cy) <= th.hh + 3.5 then
				local rx, rz = ox - th.cx, oz - th.cz
				local lx = math.abs(rx * th.ax + rz * th.az) - th.hx
				local lz = math.abs(rx * th.bx + rz * th.bz) - th.hz
				if lx < 0 then
					lx = 0
				end
				if lz < 0 then
					lz = 0
				end
				c = math.sqrt(lx * lx + lz * lz) - 1.5
				if k == 0 then
					insideStart = c < thresh
					if insideStart and D > 0 then
						c = 99
					end
				elseif insideStart and D > 0 and t < delay + T then
					c = 99 -- игрок уже в зоне: пока он из неё выходит, это не считается новым попаданием
				end
			end
		else
			if math.abs(qy - th.cy) <= th.hh + 3 then
				local rx, rz = ox - th.cx, oz - th.cz
				c = math.sqrt(rx * rx + rz * rz) - (th.r0 + th.g * math.min(tau, CONFIG.MV_ZONE_EXTRAP) + 1)
			end
		end
		if c < best then
			best = c
		end
		if c < thresh and tFirst == nil then
			tFirst = t
		end
	end
	return best, tFirst
end

---------------------------------------------------------------- уклонение
local MV_DIRS = 10 -- 0..7 прямые рывки, 8..9 боковые рывки дугой (облёт вокруг угрозы)

-- Свободно ли пространство для рывка: стена на пути уменьшает дистанцию, пустота под ногами исключает направление.
function X.mv.space(dx, dz, D)
	local M = X.mv
	local p = M.hrp.Position
	local origin = Vector3.new(p.X, p.Y, p.Z)
	local hit = Workspace:Raycast(origin, Vector3.new(dx * (D + 1.6), 0, dz * (D + 1.6)), M.rp)
	local Dc = D
	if hit then
		local hp = hit.Position
		local w = math.sqrt((hp.X - p.X) ^ 2 + (hp.Z - p.Z) ^ 2)
		Dc = w - 1.6
		if Dc < 1.5 then
			return 0
		end
		Dc = math.min(Dc, D)
	end
	local fx, fz = p.X + dx * Dc, p.Z + dz * Dc
	local ground = Workspace:Raycast(Vector3.new(fx, p.Y, fz), Vector3.new(0, -CONFIG.MV_VOID_DEPTH, 0), M.rp)
	if not ground then
		return 0
	end
	return Dc
end

-- сколько времени нужно уклоняющему движению, чтобы заметно сместить тело (для момента «как можно позже»)
function X.mv.leadTime()
	if X.mv.walkStyle() then
		return CONFIG.MV_WALK_TIME * 0.75
	end
	return CONFIG.MV_DASH_TIME * 0.7
end

function X.mv.decide(now)
	local M = X.mv
	local hrp = M.hrp
	local p = hrp.Position
	local hv = hrp.AssemblyLinearVelocity
	local qx, qy, qz = p.X, p.Y, p.Z
	local vx, vz = hv.X, hv.Z
	local horizon = CONFIG.MV_HORIZON
	local best, bestT = nil, 1e9
	local i = 1
	while i <= M.thrN do
		local th = M.thr[i]
		local drop = false
		if th.kind == 1 then
			local part = th.part
			if not part or not part.Parent or now - th.seen > 0.3 then
				drop = true
			end
		elseif th.kind == 2 then
			drop = now > th.expire
		elseif th.kind == 4 then
			local part = th.part
			drop = not part or not part.Parent or now - th.seen > 1.2
		else
			local part = th.part
			drop = not part or not part.Parent or now - th.seen > 0.6 or now - th.t > 3
		end
		if drop then
			M.dropThreat(i)
		else
			local c, tf = M.clearance(th, now, qx, qy, qz, vx, vz, 0, 0, 0, 1, 0, horizon)
			th.clr, th.hit = c, tf
			if tf and tf < bestT then
				best, bestT = th, tf
			end
			i += 1
		end
	end
	if not best or M.dashing or now < M.cdUntil then
		return
	end
	-- "как можно позже": рывок включается, когда осталось ровно столько времени, сколько нужно для ухода
	local delay = 0.03 + M.ping / 2000
	local lead = delay + X.mv.leadTime() + MV_STEP
	if best.kind == 4 or (best.kind == 3 and best.g == 0) then
		lead = lead + 0.3 -- неподвижная опасность (лава, пила): тянуть нечего, уходим с запасом
	end
	if bestT > lead then
		return
	end
	M.dodge(now, best, qx, qy, qz, vx, vz, delay)
end

function X.mv.dodge(now, main, qx, qy, qz, vx, vz, delay)
	local M = X.mv
	-- базовое направление: куда движется угроза (от источника к игроку)
	local bx, bz
	if main.kind == 1 then
		bx, bz = main.vx, main.vz
	elseif main.kind == 2 then
		bx, bz = main.lx, main.lz
	else
		bx, bz = qx - main.cx, qz - main.cz
	end
	local bl = math.sqrt(bx * bx + bz * bz)
	if bl < 0.01 then
		bx, bz = 0, -1
	else
		bx, bz = bx / bl, bz / bl
	end
	local D0, T = CONFIG.MV_DASH_DIST, CONFIG.MV_DASH_TIME
	if X.mv.walkStyle() then
		T = CONFIG.MV_WALK_TIME
		if main.kind == 4 or (main.kind == 3 and main.g == 0) then
			T = CONFIG.MV_WALK_TIME_STATIC
		end
		D0 = math.max(M.hum.WalkSpeed, 4) * (T - 0.5 * CONFIG.MV_WALK_RAMP) -- дальше, чем персонаж способен дойти, не планируем
	end
	local mdx, mdz = 0, 0
	local md = M.hum.MoveDirection
	if md then
		local l = math.sqrt(md.X * md.X + md.Z * md.Z)
		if l > 0.1 then
			mdx, mdz = md.X / l, md.Z / l
		end
	end
	local recent = now - M.lastAt < 2.5
	local bestScore, bd = -1e9, nil
	local bdx, bdz, bD, bClr, bSide, bArc = 0, 0, 0, 0, 0, 0
	local base0 = math.huge
	for _, th in ipairs(M.thr) do
		if th.clr and th.clr < base0 then
			base0 = th.clr
		end
	end
	local r2 = 0.70710678
	for k = 0, MV_DIRS - 1 do
		-- k: 0,1 = влево/вправо от линии угрозы; 2..5 = диагонали; 6 = вдоль угрозы (прочь); 7 = навстречу;
		-- 8,9 = как 0,1, но траектория заворачивает в сторону «прочь от угрозы» (дуга)
		local kb = k >= 8 and k - 8 or k
		local dx, dz
		if kb == 0 then
			dx, dz = -bz, bx
		elseif kb == 1 then
			dx, dz = bz, -bx
		elseif kb == 2 then
			dx, dz = (-bz + bx) * r2, (bx + bz) * r2
		elseif kb == 3 then
			dx, dz = (bz + bx) * r2, (-bx + bz) * r2
		elseif kb == 4 then
			dx, dz = (-bz - bx) * r2, (bx - bz) * r2
		elseif kb == 5 then
			dx, dz = (bz - bx) * r2, (-bx - bz) * r2
		elseif kb == 6 then
			dx, dz = bx, bz
		else
			dx, dz = -bx, -bz
		end
		if k ~= 7 then -- навстречу угрозе не уклоняемся
			local arc = 0
			local sx, sz = dx, dz -- направление проверки места (для дуги - средний курс)
			if k >= 8 then
				local cr = dx * bz - dz * bx
				-- снаряд/зона: дуга уходит прочь от линии угрозы; удар в ближнем бою: облёт врага сбоку к его спине
				arc = (cr >= 0 and 1 or -1) * CONFIG.MV_ARC * (main.kind == 2 and -1 or 1)
				local cs, sn = math.cos(arc * 0.25), math.sin(arc * 0.25)
				sx, sz = dx * cs - dz * sn, dx * sn + dz * cs
			end
			local Dc = M.space(sx, sz, D0)
			if Dc > 0 then
				-- итоговый зазор по ВСЕМ угрозам (другая опасность на пути уклонения учитывается тут же)
				local clr = 1e9
				for ti = 1, M.thrN do
					local th = M.thr[ti]
					local c = M.clearance(th, now, qx, qy, qz, vx, vz, dx, dz, Dc, T, delay, CONFIG.MV_HORIZON, arc)
					if c < clr then
						clr = c
					end
				end
				if clr >= CONFIG.MV_MIN_CLEARANCE then
					local side = 0
					local cr = bx * dz - bz * dx
					if cr > 0.3 then
						side = 1
					elseif cr < -0.3 then
						side = -1
					end
					local score = math.min(clr, 3)
					score += 0.5 * (mdx * dx + mdz * dz) -- по возможности по ходу намерения игрока
					score += 0.3 * (Dc / D0)
					if side ~= 0 and side == M.lastSide and recent then
						score -= CONFIG.MV_REPEAT_PENALTY * math.min(M.sameCount, 2) -- не одно и то же направление подряд
					end
					if kb >= 2 and kb <= 3 then
						score -= 0.15 -- боковой шаг предпочтительнее передней диагонали при равных условиях
					elseif k >= 8 then
						score += main.kind == 2 and 0.45 or 0.2 -- дуга (облёт) выглядит естественнее; в ближнем бою - облёт врага
					elseif kb >= 4 and main.kind <= 2 then
						score += 0.35 -- назад / назад по диагонали (за спину), если там свободно: мягче и безопаснее
					end
					score += (math.random() - 0.5) * 0.3
					if score > bestScore then
						bestScore, bd = score, k
						bdx, bdz, bD, bClr, bSide, bArc = dx, dz, Dc, clr, side, arc
					end
				end
			end
		end
	end
	if not bd then
		M.stats.noSafe += 1
		M.cdUntil = now + 0.15 -- безопасного направления нет: бессмысленный рывок не делаем
		return
	end
	-- не выполняем бессмысленное: рывок должен реально улучшить положение
	if bClr < base0 + 0.4 then
		M.cdUntil = now + 0.1
		return
	end
	M.start(now, bdx, bdz, bD, T, bArc)
	if bSide ~= 0 then
		if bSide == M.lastSide and recent then
			M.sameCount += 1
		else
			M.sameCount = 1
		end
		M.lastSide = bSide
	end
	M.lastAt = now
	M.stats.dodges += 1
	M.lastDodge = { dx = bdx, dz = bdz, dist = bD, kind = main.kind, side = bSide, clearance = bClr, arc = bArc, at = now }
end

function X.mv.start(now, dx, dz, D, T, arc)
	local M = X.mv
	M.dashing = true
	M.dashStart = now
	M.dashDx, M.dashDz, M.dashD = dx, dz, D
	M.dashA = arc or 0
	M.dashT = T
	M.dashV0 = D / T -- профиль скорости: D/T * (1 + 2*u*(1-u) - u) = производная disp, см. dashStep
	local p0 = M.hrp.Position
	M.dashX0, M.dashZ0, M.dashChecked = p0.X, p0.Z, false
	if M.walkStyle() then
		M.cdUntil = now + math.max(CONFIG.MV_COOLDOWN, T + 0.05)
		M.dashStep(now)
		return
	end
	if not M.ensureDash() then
		M.dashing = false
		return
	end
	M.cdUntil = now + CONFIG.MV_COOLDOWN
	M.lv.LineDirection = Vector3.new(dx, 0, dz)
	M.lv.LineVelocity = M.dashV0 * 1
	M.lv.Enabled = true
end

-- Объекты рывка создаются по требованию (запасной режим, когда игра игнорирует Humanoid:Move)
function X.mv.ensureDash()
	local M = X.mv
	if M.lv and M.lv.Parent and M.att and M.att.Parent then
		return true
	end
	local hrp = M.hrp
	if not (hrp and hrp.Parent) then
		return false
	end
	return X.try("mv.ensureDash", function()
		if M.lv then M.lv:Destroy() end
		if M.att then M.att:Destroy() end
		local att = Instance.new("Attachment")
		att.Name = "AM_Att"
		att.Parent = hrp
		local lv = Instance.new("LinearVelocity")
		lv.Name = "AM_LV"
		lv.Attachment0 = att
		lv.RelativeTo = Enum.ActuatorRelativeTo.World
		lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		lv.LineDirection = Vector3.new(1, 0, 0)
		lv.LineVelocity = 0
		lv.MaxForce = 1e7
		lv.Enabled = false
		lv.Parent = hrp
		M.att, M.lv = att, lv
		return true
	end) == true
end

-- Проверка «двигает ли Humanoid:Move»: на середине уклонения персонаж обязан был сместиться в заданную сторону.
-- Два провала подряд (и ни одного успеха между ними) = игра игнорирует Humanoid:Move (свои контролы, стан, якорь):
-- переходим на рывок LinearVelocity для остальной игры.
function X.mv.checkMoveWorked(u)
	local M = X.mv
	if M.dashChecked or u < 0.55 or M.dashD < 3 then
		return
	end
	M.dashChecked = true
	local hrp = M.hrp
	if not (hrp and hrp.Parent) or M.hum.Sit or M.hum.PlatformStand or hrp.Anchored then
		return
	end
	local p = hrp.Position
	local moved = (p.X - M.dashX0) * M.dashDx + (p.Z - M.dashZ0) * M.dashDz
	if moved >= 0.2 * M.dashD * u then
		M.moveFails = 0
		return
	end
	M.moveFails = (M.moveFails or 0) + 1
	M.stats.moveFail = (M.stats.moveFail or 0) + 1
	if M.moveFails >= 2 and not M.fallbackDash then
		M.fallbackDash = true
		M.stats.fallback = true
		warn("[Auto-Maneuver] Humanoid:Move не двигает персонажа (игра использует своё управление): перехожу на рывок LinearVelocity")
	end
end

function X.mv.dashStep(now)
	local M = X.mv
	if M.walkStyle() then
		-- обычное движение: направление ходьбы задаётся каждый кадр после ввода игрока (приоритет выше Input)
		local u = (now - M.dashStart) / M.dashT
		if u >= 1 or not M.hum or not M.hum.Parent then
			M.release(false)
			return
		end
		M.checkMoveWorked(u)
		local ex, ez = M.dashDx, M.dashDz
		local A = M.dashA
		if A ~= 0 then
			local psi = A * u * u * (3 - 2 * u) -- курс плавно заворачивает (облёт), без резких поворотов
			local cs, sn = math.cos(psi), math.sin(psi)
			ex, ez = M.dashDx * cs - M.dashDz * sn, M.dashDx * sn + M.dashDz * cs
		end
		M.hum:Move(Vector3.new(ex, 0, ez), false)
		return
	end
	local u = (now - M.dashStart) / CONFIG.MV_DASH_TIME
	if u >= 1 or not (M.lv and M.lv.Parent) then
		M.release(false)
		return
	end
	local sp = M.dashV0 * (1 + 2 * u - 3 * u * u) -- продольная скорость (производная disp)
	local A = M.dashA
	if A == 0 then
		M.lv.LineVelocity = sp
		return
	end
	-- дуга: курс плавно заворачивает на A/2; скорость = продольная + поперечная (от поворота курса)
	local T = CONFIG.MV_DASH_TIME
	local psi = 0.5 * A * u * u * (3 - 2 * u)
	local dpsi = 0.5 * A * 6 * u * (1 - u) / T
	local sOff = M.dashD * (0.5 * (2 * u - u * u) + 0.5 * u * u * (3 - 2 * u))
	local cs, sn = math.cos(psi), math.sin(psi)
	local ex, ez = M.dashDx * cs - M.dashDz * sn, M.dashDx * sn + M.dashDz * cs
	local vx, vz = sp * ex - sOff * dpsi * ez, sp * ez + sOff * dpsi * ex
	local vm = math.sqrt(vx * vx + vz * vz)
	if vm > 0.01 then
		M.lv.LineDirection = Vector3.new(vx / vm, 0, vz / vm)
		M.lv.LineVelocity = vm
	end
end

---------------------------------------------------------------- шаг модуля (каждый кадр, дёшево)
function X.mv.step(dt)
	local M = X.mv
	local now = os.clock()
	if not state.maneuver and not state.juke then
		if M.dashing or (M.lv and M.lv.Enabled) then
			M.release(false)
		end
		if M.thrN > 0 then
			M.clearThreats()
		end
		return
	end
	local char = localPlayer.Character
	if char ~= M.char or (char and not M.hrp and now >= M.retryAt) then
		M.attach(char)
	end
	if not M.hrp then
		return
	end
	if now >= M.guardAt then
		M.guardAt = now + 0.1
		M.ok = M.canAct(now)
	end
	if not M.ok then
		if M.dashing then
			M.release(false)
		end
		if M.thrN > 0 then
			M.clearThreats()
		end
		return
	end
	if M.dashing then
		M.dashStep(now)
	elseif state.juke then
		X.jukeGuarded(now, dt)
	end
	if not state.maneuver then
		-- Juke работает и без Auto-Maneuver; угрозы не отслеживаем
		if M.dashing then
			M.release(false)
		end
		if M.thrN > 0 then
			M.clearThreats()
		end
		return
	end
	if now >= M.pingAt then
		M.pingAt = now + 2
		local ok, v = pcall(function()
			return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
		end)
		if ok and type(v) == "number" then
			M.ping = math.clamp(v, 0, 600)
		end
	end
	if now >= M.nextScan then
		M.nextScan = now + (now < M.alertUntil and CONFIG.MV_SCAN_ALERT or (now < M.meleeUntil and CONFIG.MV_SCAN_MELEE or CONFIG.MV_SCAN_IDLE))
		M.scan(now)
		if now >= M.nearAt then
			M.nearAt = now + 0.25
			M.refreshNear(now)
		end
		if M.nearN > 0 then
			M.meleeScan(now)
		end
	end
	if M.thrN > 0 then
		M.decide(now)
	end
end

---------------------------------------------------------------- Juke: красивые плавные уходы вокруг врага
-- Работает вместе с Auto-Maneuver (комбо): пока идёт уклонение, Juke молчит, остальное время персонаж плавно
-- «танцует» из стороны в сторону относительно ближайшего врага. Управление игрока сохраняется: его собственное
-- движение (из ControlModule) складывается с Juke, а если игрок стоит, персонаж идёт только по Juke.
-- Если ControlModule недоступен (своя система управления), Juke не включается: не отбираем управление вслепую.
X.mv.juke = {
	scanAt = 0, root = nil, side = 1, fb = 0, segEnd = 0, spaceAt = 0, dx = 0, dz = 0, ctl = nil, warned = false,
}

function X.mv.jukeEnemy(now)
	local M = X.mv
	local J = M.juke
	local p = M.hrp.Position
	local best, bestD = nil, CONFIG.JUKE_RANGE * CONFIG.JUKE_RANGE
	local function consider(model)
		local root = X.root(model)
		if root and root:IsA("BasePart") then
			local rp = root.Position
			local dx, dz = rp.X - p.X, rp.Z - p.Z
			local d2 = dx * dx + dz * dz
			if d2 < bestD and math.abs(rp.Y - p.Y) < 20 then
				best, bestD = root, d2
			end
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if isEnemyPlayer(pl) then
			local c = pl.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			if c and h and isAlive(h) then
				consider(c)
			end
		end
	end
	for model, e in pairs(entities) do
		if e.confirmed and model ~= M.char and X.npcHostile(model, now) and entityAlive(e) then
			consider(model)
		end
	end
	J.root = best
end

-- Движение, которое игрок задаёт сам (в мировых координатах), или nil, если определить нельзя.
function X.mv.playerIntent()
	local J = X.mv.juke
	if J.ctl == nil then
		J.ctl = false
		local ok, res = pcall(function()
			local ps = localPlayer:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm then
				return require(pm):GetControls()
			end
		end)
		if ok and type(res) == "table" and res.GetMoveVector then
			J.ctl = res
		end
	end
	if not J.ctl then
		return nil
	end
	local ok, mv = pcall(J.ctl.GetMoveVector, J.ctl)
	local cam = Workspace.CurrentCamera
	if not ok or not mv or not cam then
		return nil
	end
	local cf = cam.CFrame
	local look, right = cf.LookVector, cf.RightVector
	return right.X * mv.X - look.X * mv.Z, right.Z * mv.X - look.Z * mv.Z
end

function X.mv.jukeStep(now, dt)
	local M = X.mv
	local J = M.juke
	if now >= J.scanAt then
		J.scanAt = now + 0.3
		M.jukeEnemy(now)
	end
	local er = J.root
	if not er or not er.Parent then
		J.root = nil
		return
	end
	local ix, iz = M.playerIntent()
	if not ix then
		if not J.warned then
			J.warned = true
			warn("[Juke] ControlModule недоступен: Juke не вмешивается в управление")
		end
		return
	end
	local p = M.hrp.Position
	local rp = er.Position
	local ex, ez = rp.X - p.X, rp.Z - p.Z
	local d = math.sqrt(ex * ex + ez * ez)
	if d < 2 or d > CONFIG.JUKE_RANGE + 10 then
		return
	end
	ex, ez = ex / d, ez / d
	local newSeg = false
	if now >= J.segEnd then
		J.segEnd = now + CONFIG.JUKE_SEG_MIN + math.random() * (CONFIG.JUKE_SEG_MAX - CONFIG.JUKE_SEG_MIN)
		if math.random() < CONFIG.JUKE_FLIP then
			J.side = -J.side
		end
		J.fb = (math.random() - 0.5) * 0.7 -- чуть к врагу или от него, чтобы шаблон не был чисто боковым
		newSeg = true
	end
	local function target()
		local tx, tz = -ez * J.side + ex * J.fb, ex * J.side + ez * J.fb
		local l = math.sqrt(tx * tx + tz * tz)
		return tx / l, tz / l
	end
	local tx, tz = target()
	if newSeg or now >= J.spaceAt then
		J.spaceAt = now + 0.15
		if M.space(tx, tz, 4.5) < 3 then
			J.side = -J.side -- упёрлись в стену или край: уходим в другую сторону
			tx, tz = target()
			if M.space(tx, tz, 4.5) < 3 then
				J.blocked = true
			else
				J.blocked = false
			end
		else
			J.blocked = false
		end
	end
	if J.blocked then
		return
	end
	local a = 1 - math.exp(-dt / CONFIG.JUKE_SMOOTH)
	J.dx += (tx - J.dx) * a
	J.dz += (tz - J.dz) * a
	local ox, oz
	if ix * ix + iz * iz > 0.01 then
		ox, oz = ix + J.dx * CONFIG.JUKE_WEIGHT, iz + J.dz * CONFIG.JUKE_WEIGHT
		local l = math.sqrt(ox * ox + oz * oz)
		if l > 1 then
			ox, oz = ox / l, oz / l
		end
	else
		ox, oz = J.dx * CONFIG.JUKE_IDLE, J.dz * CONFIG.JUKE_IDLE
	end
	M.hum:Move(Vector3.new(ox, 0, oz), false)
end
X.jukeGuarded = guarded("juke", X.mv.jukeStep)

---------------------------------------------------------------- Force Third Person
-- Почему игра может держать первое лицо (все причины, которые мы устраняем):
--   1) Player.CameraMode = LockFirstPerson;
--   2) Player.CameraMaxZoomDistance слишком мал (<= порога первого лица) или MinZoomDistance < порога: колесо/щипок
--      уводят зум в первое лицо;
--   3) Camera.CameraType не Custom (Scriptable/Fixed/...): стандартный камера-скрипт не работает;
--   4) Camera.CameraSubject = nil / уничтожен после респавна / голова или деталь персонажа вместо Humanoid;
--   5) камера пересоздана (Workspace.CurrentCamera другая), персонаж пересоздан;
--   6) игра сама каждый кадр возвращает значения 1-3.
-- Решение: пока включено, каждый кадр ДО камера-скрипта (приоритет Camera-1) сверяем эти значения и правим только то,
-- что мешает. Дальность не фиксируется: зум остаётся полностью в руках игрока (колесо, щипок), мы лишь поднимаем нижнюю
-- границу над порогом первого лица и возвращаем широкий верхний предел, если игра его сузила.
-- Что хотела игра, запоминаем отдельно: при OFF возвращаем именно это. Если другой скрипт отнимает у нас CameraType
-- (TP_FIGHT_LIMIT раз за TP_FIGHT_WINDOW с), мы отступаем на паузу, а не дерёмся каждый кадр (иначе мерцание).
X.tp = { on = false, conns = {}, game = {}, mine = {}, writes = {}, pauseUntil = 0, pauseStep = 8, zoomAt = 0, camConns = {}, cam = nil, nowFix = false }

function X.tp.zoomCtl()
	local T = X.tp
	if T.zc == nil then
		T.zc = false
		local ok, res = pcall(function()
			local ps = localPlayer:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			local cm = pm and pm:FindFirstChild("CameraModule")
			local z = cm and cm:FindFirstChild("ZoomController")
			if z then
				return require(z)
			end
		end)
		if ok and type(res) == "table" then
			T.zc = res
		end
	end
	return T.zc or nil
end

-- желаемое значение свойства по тому, что хочет игра
local TP_PROPS = {
	{ "CameraMode", function(g)
		return Enum.CameraMode.Classic
	end },
	{ "CameraMinZoomDistance", function(g)
		return math.max(type(g) == "number" and g or 0, CONFIG.TP_MIN_ZOOM)
	end },
	{ "CameraMaxZoomDistance", function(g)
		return math.max(type(g) == "number" and g or 0, CONFIG.TP_MAX_ZOOM)
	end },
}

function X.tp.syncProps(apply)
	local T = X.tp
	-- порядок записи: сначала верхний предел вверх, потом нижний (чтобы Min никогда не оказался выше Max)
	for n = 1, 3 do
		local i = n == 1 and 1 or (n == 2 and 3 or 2)
		local name, want = TP_PROPS[i][1], TP_PROPS[i][2]
		local cur = localPlayer[name] -- чтение свойства Player не бросает ошибок: без pcall и замыканий каждый кадр
		if cur ~= T.mine[name] then
			T.game[name] = cur -- это значение выставила игра (или оно было с самого начала)
		end
		if apply then
			local w = want(T.game[name])
			if cur ~= w then
				-- mine выставляем до записи: при немедленных сигналах обработчик не должен принять наше значение за игры
				local prev = T.mine[name]
				T.mine[name] = w
				if pcall(X.tp.write, name, w) then
					T.fixed = (T.fixed or 0) + 1
				else
					T.mine[name] = prev
				end
			else
				T.mine[name] = w
			end
		end
	end
end

function X.tp.write(name, w)
	localPlayer[name] = w
end

-- Стандартная камера Roblox (PlayerModule/CameraModule) жива? Если игра её удалила и ведёт камеру сама, переключение
-- CameraType на Custom ничего не даёт, кроме замороженной камеры: тогда CameraType не трогаем.
function X.tp.defaultCamAlive()
	local ps = localPlayer:FindFirstChild("PlayerScripts")
	local pm = ps and ps:FindFirstChild("PlayerModule")
	local cm = pm and pm:FindFirstChild("CameraModule")
	return cm ~= nil and cm.Parent ~= nil
end

-- После нашего переключения CameraType камера обязана ехать за персонажем. Если персонаж ушёл далеко, а камера не сдвинулась,
-- стандартная камера не работает: возвращаем CameraType, как был, и надолго отступаем (иначе камера «замирает»).
function X.tp.watchFreeze(cam, hum, now)
	local T = X.tp
	local fz = T.freeze
	if not fz then
		return
	end
	if cam.CameraType ~= Enum.CameraType.Custom then
		T.freeze = nil
		return
	end
	local root = X.root(hum.Parent)
	if not root then
		return
	end
	local cp, rp = cam.CFrame.Position, root.Position
	if (cp - fz.camPos).Magnitude > 0.5 then
		T.freeze = nil -- камера двигается: всё в порядке
		return
	end
	if (rp - fz.rootPos).Magnitude > 4 then
		T.freeze = nil
		T.giveUp = now + 60
		T.freezeHits = (T.freezeHits or 0) + 1
		local back = fz.prevType
		if back and back ~= Enum.CameraType.Custom then
			cam.CameraType = back
		end
		warn(("[Force TP] камера не следует за персонажем после переключения CameraType: игра ведёт камеру сама (%s). Возвращаю её и не вмешиваюсь 60 с."):format(tostring(back)))
		return
	end
	if now - fz.t > 6 then
		T.freeze = nil -- персонаж стоял на месте: проверка неинформативна
	end
end

function X.tp.inner(now)
	X.tp.syncProps(true)
	X.tp.fixCamera(now)
end

function X.tp.fixCamera(now)
	local T = X.tp
	local cam = Workspace.CurrentCamera
	if cam ~= T.cam then
		T.cam = cam
		for _, c in ipairs(T.camConns) do
			c:Disconnect()
		end
		table.clear(T.camConns)
		if cam then
			T.camConns[1] = cam:GetPropertyChangedSignal("CameraType"):Connect(function()
				T.nowFix = true
			end)
			T.camConns[2] = cam:GetPropertyChangedSignal("CameraSubject"):Connect(function()
				T.nowFix = true
			end)
		end
		T.zoomAt = 0
	end
	if not cam then
		return
	end
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum or not hum.Parent or hum.Health <= 0 then
		return -- мёртв или персонаж ещё не готов: камерой управляет игра (экран смерти, респавн)
	end
	-- CameraSubject: nil, уничтоженный или деталь собственного персонажа вместо Humanoid. Чужую цель (наблюдение,
	-- транспорт) не трогаем.
	local subj = cam.CameraSubject
	local bad = subj == nil
	if not bad and subj ~= hum then
		if not subj:IsDescendantOf(Workspace) then
			bad = true
		elseif subj:IsDescendantOf(char) then
			bad = true
		end
	end
	if bad then
		cam.CameraSubject = hum
		T.fixed = (T.fixed or 0) + 1
	end
	-- CameraType должен быть Custom, иначе стандартная камера (с зумом) не работает
	X.tp.watchFreeze(cam, hum, now)
	if cam.CameraType ~= Enum.CameraType.Custom and now >= T.pauseUntil and now >= (T.giveUp or 0) and X.tp.defaultCamAlive() then
		local w = T.writes
		w[#w + 1] = now
		while #w > 0 and now - w[1] > CONFIG.TP_FIGHT_WINDOW do
			table.remove(w, 1)
		end
		if #w >= CONFIG.TP_FIGHT_LIMIT then
			T.pauseUntil = now + T.pauseStep
			T.pauseStep = math.min(T.pauseStep * 2, 60)
			table.clear(w)
			warn(("[Force TP] другой скрипт возвращает CameraType (%s), пауза %d с"):format(tostring(cam.CameraType), math.floor(T.pauseUntil - now)))
		else
			local root = X.root(char)
			T.freeze = { t = now, prevType = cam.CameraType, camPos = cam.CFrame.Position, rootPos = root and root.Position or Vector3.zero }
			cam.CameraType = Enum.CameraType.Custom
			T.fixed = (T.fixed or 0) + 1
		end
	end
	-- если зум уже внутри первого лица (был до включения), один раз отодвигаем; дальше зум свободный
	if now >= T.zoomAt and cam.CameraType == Enum.CameraType.Custom then
		T.zoomAt = now + 1
		local z = X.tp.zoomCtl()
		if z and z.GetZoomRadius and z.SetZoomParameters then
			local ok, r = pcall(z.GetZoomRadius)
			if ok and type(r) == "number" and r < CONFIG.TP_MIN_ZOOM - 0.05 then
				X.try("tp.zoom", z.SetZoomParameters, CONFIG.TP_DEFAULT_ZOOM, 0)
				T.zoomSet = (T.zoomSet or 0) + 1
			end
		end
	end
end

function X.tp.step()
	local T = X.tp
	if T.busy then
		return -- сигнал сработал внутри нашей же записи
	end
	T.busy = true
	T.nowFix = false
	local ok, err = pcall(X.tp.inner, os.clock())
	T.busy = false
	if not ok then
		error(err, 0)
	end
end
X.tpGuarded = guarded("tp", X.tp.step)

function X.tp.enable()
	local T = X.tp
	if T.on or destroyed then
		return
	end
	T.on = true
	T.mine, T.game = {}, {}
	T.pauseUntil, T.pauseStep, T.zoomAt, T.cam = 0, 8, 0, nil
	T.freeze, T.giveUp = nil, 0
	local function kick()
		if T.on then
			X.tpGuarded() -- немедленно, не дожидаясь кадра
		end
	end
	for _, name in ipairs({ "CameraMode", "CameraMinZoomDistance", "CameraMaxZoomDistance" }) do
		T.conns[#T.conns + 1] = localPlayer:GetPropertyChangedSignal(name):Connect(kick)
	end
	T.conns[#T.conns + 1] = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(kick)
	T.conns[#T.conns + 1] = localPlayer.CharacterAdded:Connect(function()
		T.zoomAt = 0
		T.pauseUntil = 0
		task.defer(kick)
	end)
	X.try("tp.bind", function()
		RunService:BindToRenderStep(X.renderName .. "_TP", Enum.RenderPriority.Camera.Value - 1, X.tpGuarded)
	end)
	X.tpGuarded()
end

-- полностью прекратить управление и вернуть то, что хотела игра
function X.tp.disable()
	local T = X.tp
	if not T.on then
		return
	end
	T.on = false
	X.try("tp.unbind", function()
		RunService:UnbindFromRenderStep(X.renderName .. "_TP")
	end)
	for _, c in ipairs(T.conns) do
		c:Disconnect()
	end
	table.clear(T.conns)
	for _, c in ipairs(T.camConns) do
		c:Disconnect()
	end
	table.clear(T.camConns)
	X.tp.syncProps(false) -- узнать, не поменяла ли игра значения, пока мы их держали
	for _, i in ipairs({ 2, 3, 1 }) do
		local name = TP_PROPS[i][1]
		local g = T.game[name]
		if g ~= nil and T.mine[name] ~= nil and g ~= T.mine[name] then
			X.try("tp.restore", X.tp.write, name, g)
		end
	end
	T.cam = nil
	T.mine, T.game = {}, {}
end

-- включено = переключатель ON, модуль жив. Вызывается каждый кадр: подхватывает и загрузку настроек, и самоотключение модуля.
function X.tp.sync()
	local want = state.forceTP and moduleOk.tp
	if want ~= X.tp.on then
		if want then
			X.tp.enable()
		else
			X.tp.disable()
		end
	end
end

---------------------------------------------------------------- Advanced Movement Responsiveness
-- Откуда берётся «вялость» управления в Roblox:
--   1) Humanoid разгоняется и тормозит не мгновенно: скорость плавно подтягивается к WalkSpeed * MoveDirection,
--      а при отпускании персонаж ещё скользит по трению;
--   2) при развороте нужно сначала погасить старую скорость - поэтому резкая смена направления «тянется»;
--   3) аналоговый стик даёт магнитуду < 1, пока палец не дотянулся до края (наш увеличенный стик делает это дальше):
--      персонаж идёт медленнее, чем WalkSpeed, хотя игрок «упёрся» стиком.
-- Решение без изменения WalkSpeed: каждый кадр на земле
--   * магнитуду стика растягиваем так, что полная скорость достигается на RESP_FULL_AT хода (Humanoid:Move, как в
--     ControlModule); клавиатура/геймпад (магнитуда 1) не меняются;
--   * горизонтальную скорость персонажа (относительно пола) плавно, экспоненциально подтягиваем к желаемой
--     WalkSpeed * направление * магнитуда: быстрее разгон, смена направления и остановка, но без рывков.
--     Результат всегда лежит между текущей и желаемой скоростью, поэтому выше WalkSpeed не поднимается никогда.
-- Не трогаем: воздух/прыжок/падение/приземление, лазание, воду, сидение, PlatformStand, Anchored, чужие BodyMover/
-- LinearVelocity на HRP, внешние толчки (скорость выше WalkSpeed*RESP_KNOCK), вращающийся пол, лаг-кадры, рывок режима dash.
-- Вертикальная скорость не меняется. Движущийся пол учитывается (скорость считается относительно него).
-- Состояния нет: при OFF просто прекращаются записи, ничего восстанавливать не нужно.
X.resp = { rp = nil, rpChar = nil, floorCheckAt = 0, floorAt = 0, fvx = 0, fvz = 0, foreignAt = 0, foreign = false, floorPart = nil, floorPos = nil, ctl = nil, writes = 0, moves = 0 }

local RESP_MOVERS = {
	BodyVelocity = true, BodyPosition = true, BodyForce = true, BodyThrust = true,
	LinearVelocity = true, VectorForce = true, AlignPosition = true, LineForce = true,
}

function X.resp.rawMove()
	local R = X.resp
	if R.ctl == nil then
		R.ctl = false
		local ok, res = pcall(function()
			local ps = localPlayer:FindFirstChild("PlayerScripts")
			local pm = ps and ps:FindFirstChild("PlayerModule")
			if pm then
				return require(pm):GetControls()
			end
		end)
		if ok and type(res) == "table" and res.GetMoveVector then
			R.ctl = res
		end
	end
	if not R.ctl then
		return nil
	end
	local ok, mv = pcall(R.ctl.GetMoveVector, R.ctl)
	if ok and mv then
		return mv
	end
	return nil
end

function X.resp.hasForeignMover(hrp, now)
	local R = X.resp
	if now >= R.foreignAt then
		R.foreignAt = now + 0.5
		R.foreign = false
		for _, c in ipairs(hrp:GetChildren()) do
			if RESP_MOVERS[c.ClassName] and string.sub(c.Name, 1, 3) ~= "AM_" and c.Enabled ~= false then
				R.foreign = true
				break
			end
		end
	end
	return R.foreign
end

-- чтение скорости детали пола без замыканий (вызывается через pcall(f, part, ...))
function X.resp.readFloor(part, now, dt)
	local R = X.resp
	if part.AssemblyAngularVelocity.Magnitude > 0.05 then
		return nil
	end
	if part.Anchored then
		-- анкерная платформа, которую двигает скрипт: скорость по смещению за интервал между проверками пола
		local pos = part.Position
		if R.floorPart == part and R.floorPos then
			local d = pos - R.floorPos
			local span = math.max(now - R.floorAt, 1 / 240)
			R.floorPart, R.floorPos, R.floorAt = part, pos, now
			return Vector3.new(d.X / span, 0, d.Z / span)
		end
		R.floorPart, R.floorPos, R.floorAt = part, pos, now
		return false -- первый раз на этой детали: скорости ещё нет
	end
	R.floorPart = nil
	return part.AssemblyLinearVelocity
end

-- скорость пола под ногами (горизонтальная); nil = пол вращается или неизвестен, вмешиваться нельзя.
-- Луч вниз нужен только чтобы знать, движется ли пол: пол не меняется за 1/20 с, поэтому проверяем 20 раз в секунду, а между
-- проверками используем прошлый результат (раньше луч летел каждый кадр).
function X.resp.floorVelocity(char, hrp, hum, now)
	local R = X.resp
	if R.rpChar ~= char or not R.rp then
		R.rpChar = char
		R.rp = RaycastParams.new()
		R.rp.FilterType = Enum.RaycastFilterType.Exclude
		R.rp.FilterDescendantsInstances = { char }
		R.rp.IgnoreWater = true
		R.floorCheckAt = 0
	end
	if now < R.floorCheckAt then
		return R.fvx, R.fvz
	end
	R.floorCheckAt = now + 0.05
	local p = hrp.Position
	local hit = Workspace:Raycast(Vector3.new(p.X, p.Y, p.Z), Vector3.new(0, -((hum.HipHeight or 0) + hrp.Size.Y * 0.5 + 4), 0), R.rp)
	local part = hit and hit.Instance
	if not part then
		R.floorPart = nil
		R.fvx, R.fvz = 0, 0
		return 0, 0
	end
	local ok, res = pcall(X.resp.readFloor, part, now, 0)
	if not ok or res == nil or res == false then
		R.fvx, R.fvz = nil, nil
		return nil
	end
	R.fvx, R.fvz = res.X, res.Z
	return R.fvx, R.fvz
end

function X.resp.step(dt)
	local R = X.resp
	local char = localPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and X.root(char)
	if not hum or not hrp or not hrp.Parent or hum.Health <= 0 or dt <= 0 or dt > CONFIG.RESP_MAX_DT then
		return
	end
	local ws = hum.WalkSpeed
	if type(ws) ~= "number" or ws <= 0 then
		return
	end
	if X.mv.dashing or hum.Sit or hum.PlatformStand or hrp.Anchored then
		return
	end
	local st = hum:GetState()
	if st ~= Enum.HumanoidStateType.Running and st ~= Enum.HumanoidStateType.RunningNoPhysics then
		return -- прыжок, падение, приземление, лазание, вода и т.д. остаются стандартными
	end
	if hum.FloorMaterial == Enum.Material.Air then
		return
	end
	local now = os.clock()
	if R.hasForeignMover(hrp, now) then
		return
	end

	-- 1) растягиваем магнитуду аналогового стика (как ControlModule: камера-относительный Move)
	local mv = R.rawMove()
	local stretched = false
	if mv then
		local mi = math.sqrt(mv.X * mv.X + mv.Z * mv.Z)
		if mi > CONFIG.RESP_MIN_INPUT and mi < 0.999 then
			local k = math.min(1 / CONFIG.RESP_FULL_AT, 1 / mi)
			hum:Move(Vector3.new(mv.X * k, 0, mv.Z * k), true)
			R.moves += 1
			stretched = true
		end
	end

	-- 2) подтягиваем скорость к желаемой
	local v = hrp.AssemblyLinearVelocity
	local mdI = hum.MoveDirection
	if not stretched and mdI.X * mdI.X + mdI.Z * mdI.Z < 0.0025 and v.X * v.X + v.Z * v.Z < 0.0025 then
		return -- стоим и не двигаемся: тормозить и разгонять нечего, луч не нужен
	end
	local fvx, fvz = R.floorVelocity(char, hrp, hum, now)
	if not fvx then
		return
	end
	local rx, rz = v.X - fvx, v.Z - fvz
	local sp = math.sqrt(rx * rx + rz * rz)
	if sp > ws * CONFIG.RESP_KNOCK + 2 then
		return -- внешний толчок или рывок: не гасим и не добавляем
	end
	local md = hum.MoveDirection
	local m = math.sqrt(md.X * md.X + md.Z * md.Z)
	local tx, tz = 0, 0
	if m > CONFIG.RESP_MIN_INPUT then
		-- желаемая магнитуда: если стик растянули мы, то она по входу игрока; чужой Move (уклонение, Juke, игра) берём как есть
		local f = math.min(1, m)
		if stretched then
			f = math.min(1, math.sqrt(mv.X * mv.X + mv.Z * mv.Z) / CONFIG.RESP_FULL_AT)
		elseif not mv then
			f = math.min(1, m / CONFIG.RESP_FULL_AT) -- свой стик игры без ControlModule: растягиваем так же
		end
		tx, tz = md.X / m * ws * f, md.Z / m * ws * f
	end
	local tsp = math.sqrt(tx * tx + tz * tz)
	local tau = tsp >= sp and CONFIG.RESP_TAU or CONFIG.RESP_TAU_STOP
	local a = 1 - math.exp(-dt / tau)
	local nx, nz = rx + (tx - rx) * a, rz + (tz - rz) * a
	if tsp == 0 and nx * nx + nz * nz < 0.09 then
		nx, nz = 0, 0 -- без бесконечного «ползания»
	end
	local dx, dz = nx - rx, nz - rz
	if dx * dx + dz * dz > 0.0004 then
		hrp.AssemblyLinearVelocity = Vector3.new(nx + fvx, v.Y, nz + fvz)
		R.writes += 1
	end
end
X.respGuarded = guarded("resp", X.resp.step)

X.mvGuarded = guarded("maneuver", X.mv.step)

---------------------------------------------------------------- ESP: тонкий контур игроков и NPC
-- Один Highlight на цель, без циклов на каждую цель: один общий проход раз в ESP_INTERVAL.
-- ESP_THROUGH_WALLS = true: контур виден и за стенами (AlwaysOnTop), за препятствием бледнее.
-- false: Occluded, контур только на видимых частях тела.
-- Заливки нет (FillTransparency = 1), цвет контура белый (игроки) / мягкий красный (NPC).
local espMap = {} -- [model] = Highlight

local function espRemove(model)
	local h = espMap[model]
	if h then
		espMap[model] = nil
		X.espRec[model] = nil
		h:Destroy()
	end
end

local function espClear()
	for model in pairs(espMap) do
		espRemove(model)
	end
	for _, e in ipairs(X.espPool or {}) do
		e.model = nil
	end
end

-- Прямая видимость: луч от камеры до части не должен упереться в препятствие.
-- Тот же луч, что и у наведения: стекло и невидимые барьеры препятствием не считаются.
function X.rayClear(camPos, part)
	local delta = part.Position - camPos
	if delta.Magnitude < 3 then
		return true
	end
	return X.clearRay(camPos, part, X.espFilter, X.espParams)
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

-- Визуальный стиль: хорошо видимая цель почти не подсвечивается (тонкий бледный контур, без заливки),
-- цель за стеной получает более заметный контур и очень мягкий силуэт. Всё умножается на интенсивность
-- из панели и немного бледнеет с расстоянием. Переходы плавные (X.espAnimStep), поэтому нет миганий.
function X.espTargets(model, rec, vis)
	local I = CONFIG.ESP_INTENSITY
	local d = X.espDist[model] or 0
	local far = 1 - CONFIG.ESP_FAR_FADE * math.clamp((d - 60) / math.max(CONFIG.ESP_MAX_DISTANCE - 60, 1), 0, 1)
	local oa, fa = 0, 0
	if vis then
		oa = CONFIG.ESP_VIS_ALPHA * I
	elseif CONFIG.ESP_THROUGH_WALLS then
		oa = CONFIG.ESP_HIDDEN_ALPHA * I
		fa = CONFIG.ESP_FILL_ALPHA * I
	end
	local to, tf = 1 - oa * far, 1 - fa * far
	if math.abs(to - rec.to) > 0.002 or math.abs(tf - rec.tf) > 0.002 then
		rec.to, rec.tf = to, tf
		X.espAnimating = true
	end
end

-- Плавное движение текущей прозрачности к целевой; работает только пока что-то меняется.
function X.espAnimStep(dt)
	if not X.espAnimating then
		return
	end
	local k = 1 - math.exp(-dt / CONFIG.ESP_FADE_TIME)
	local busy = false
	for model, h in pairs(espMap) do
		local rec = X.espRec[model]
		if rec and (rec.o ~= rec.to or rec.f ~= rec.tf) then
			local o = rec.o + (rec.to - rec.o) * k
			local f = rec.f + (rec.tf - rec.f) * k
			if math.abs(rec.to - o) < 0.003 then
				o = rec.to
			end
			if math.abs(rec.tf - f) < 0.003 then
				f = rec.tf
			end
			rec.o, rec.f = o, f
			h.OutlineTransparency = o
			h.FillTransparency = f
			local off = o >= 0.995 and f >= 0.995
			if h.Enabled == off then
				h.Enabled = not off -- полностью прозрачный контур не рисуется вообще (экономия)
			end
			if o ~= rec.to or f ~= rec.tf then
				busy = true
			end
		end
	end
	X.espAnimating = busy
end

-- Раз в ESP_LOS_INTERVAL: смерть, видимость (Raycast) и целевые значения прозрачности.
function X.espUpdate()
	if next(espMap) == nil then
		return
	end
	local cam = Workspace.CurrentCamera
	local useLos = (CONFIG.ESP_REQUIRE_LOS or CONFIG.ESP_THROUGH_WALLS) and cam ~= nil
	local camPos = useLos and cam.CFrame.Position or nil
	local char = localPlayer.Character
	local now = os.clock()
	X.espTick += 1
	for model, h in pairs(espMap) do
		local rec = X.espRec[model]
		-- умерший контур гаснет сразу, не дожидаясь очередной сверки списка
		local hum = model:FindFirstChildOfClass("Humanoid")
		local dead = false
		if hum then
			dead = not isAlive(hum)
		else
			local e = entities[model]
			dead = e ~= nil and not entityAlive(e)
		end
		if dead then
			if rec then
				rec.o, rec.f, rec.to, rec.tf = 1, 1, 1, 1
				h.OutlineTransparency = 1
				h.FillTransparency = 1
			end
			if h.Enabled then
				h.Enabled = false
			end
			X.espDirty = true
		elseif rec then
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
			X.espTargets(model, rec, vis)
		end
	end
end

local espWant = {}
local espList = {}
X.espPool = {}
X.espN = 0
X.espCmp = function(a, b)
	if a.kind ~= b.kind then
		return a.kind == "player"
	end
	return a.dist < b.dist
end

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
	X.espN = 0
	local incomplete = false

	local function add(model, kind)
		local root = X.root(model) or model:FindFirstChildWhichIsA("BasePart")
		if not root then
			return
		end
		local dist = (root.Position - camPos).Magnitude
		if dist > CONFIG.ESP_MAX_DISTANCE then
			return
		end
		X.espDist[model] = dist
		if espMap[model] then
			dist *= 0.85 -- уже обведённые держатся чуть дольше: нет мерцания на границе лимита
		end
		local n = X.espN + 1
		X.espN = n
		local rec = X.espPool[n]
		if not rec then
			rec = {}
			X.espPool[n] = rec
		end
		rec.model = model
		rec.kind = kind
		rec.dist = dist
		espList[n] = rec
	end

	if state.espPlayers then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= localPlayer then
				local c = p.Character
				local h = c and c:FindFirstChildOfClass("Humanoid")
				if c and h and c:IsDescendantOf(Workspace) and isAlive(h) then
					add(c, "player")
				elseif c and not h then
					incomplete = true -- персонаж ещё собирается: сверим заново чуть позже
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
	for i = #espList, X.espN + 1, -1 do
		espList[i] = nil
	end
	for i = X.espN + 1, #X.espPool do
		X.espPool[i].model = nil
	end
	table.sort(espList, X.espCmp)
	local limit = UserInputService.TouchEnabled and CONFIG.ESP_MAX_TOUCH or CONFIG.ESP_MAX
	for i = 1, math.min(#espList, limit) do
		espWant[espList[i].model] = espList[i].kind
	end
	-- не больше 5 быстрых повторов подряд, чтобы странный персонаж без Humanoid не гонял сверку часто
	if incomplete and (X.espRetry or 0) < 5 then
		X.espRetry = (X.espRetry or 0) + 1
		X.espDirty = true
	elseif not incomplete then
		X.espRetry = 0
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
			-- контур появляется плавно из полной прозрачности (без вспышки при создании)
			h.FillTransparency = 1
			h.OutlineTransparency = 1
			-- за стенами: AlwaysOnTop (за препятствием заметнее); иначе только видимые части
			h.DepthMode = CONFIG.ESP_THROUGH_WALLS and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
			h.Enabled = false
			h.Parent = model
			espMap[model] = h
			X.espRec[model] = { o = 1, f = 1, to = 1, tf = 1 }
		end
		local color = kind == "player" and CONFIG.ESP_PLAYER_COLOR or CONFIG.ESP_NPC_COLOR
		if h.OutlineColor ~= color then
			h.OutlineColor = color
			h.FillColor = color
		end
	end
	X.espUpdate()
end

local espGuarded = guarded("esp", espReconcile)
local espVisGuarded = guarded("esp", X.espUpdate)
X.espAnimGuarded = guarded("esp", X.espAnimStep)

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
	X.tp.sync()
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
	if state.moveResp then
		X.respGuarded(dt)
	end
	X.mvGuarded(dt)
	X.espAnimGuarded(dt)
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
			X.try("watchdog", X.watchdog)
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
	if not state.enabled then
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

---------------------------------------------------------------- кнопка Juke (маленькая, двигается после удержания 1 с)
-- Короткое нажатие включает/выключает Juke. Чтобы переместить кнопку, её нужно удерживать JUKE_HOLD секунд
-- (палец при этом не двигается), затем вести пальцем. До этого сдвиг пальца кнопку не двигает: никакого дёрганья.
X.jukeUI = {}
do
	local J = X.jukeUI
	local size = CONFIG.JUKE_SIZE
	local btn = make("TextButton", {
		Name = "JukeButton",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(state.jukeX, state.jukeY),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.bg,
		BackgroundTransparency = 0.15,
		Text = "JUKE",
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextColor3 = C.sub,
		AutoButtonColor = false,
		Active = true,
		ZIndex = 5,
	}, gui)
	round(btn, UDim.new(1, 0))
	local stroke = outline(btn, C.stroke, 2, 0.2)
	J.btn = btn
	J.input, J.startPos, J.startAt, J.dragging, J.moved = nil, nil, 0, false, false
	J.beat, J.endConn, J.moveConn = nil, nil, nil

	local function viewport()
		local cam = Workspace.CurrentCamera
		local vp = cam and cam.ViewportSize
		if vp and vp.X > 0 and vp.Y > 0 then
			return vp.X, vp.Y
		end
		return 1000, 500
	end

	function J.render()
		local on = state.juke
		btn.TextColor3 = on and C.on or C.sub
		stroke.Color = on and C.on or C.stroke
		btn.BackgroundTransparency = on and 0.05 or 0.15
		if not J.dragging then
			btn.Position = UDim2.fromScale(state.jukeX, state.jukeY)
		end
	end
	uiRefreshers[#uiRefreshers + 1] = J.render
	J.render()

	local function setPos(px, py)
		local w, h = viewport()
		local mx, my = (size / 2 + 4) / w, (size / 2 + 4) / h
		state.jukeX = math.clamp(px / w, mx, 1 - mx)
		state.jukeY = math.clamp(py / h, my, 1 - my)
		btn.Position = UDim2.fromScale(state.jukeX, state.jukeY)
	end

	function J.finish(cancelled)
		if J.beat then
			J.beat:Disconnect()
			J.beat = nil
		end
		if J.endConn then
			J.endConn:Disconnect()
			J.endConn = nil
		end
		if J.moveConn then
			J.moveConn:Disconnect()
			J.moveConn = nil
		end
		local wasDrag = J.dragging
		local tap = (not cancelled) and (not wasDrag) and (not J.moved) and (os.clock() - J.startAt) < CONFIG.JUKE_HOLD
		J.input, J.dragging = nil, false
		btn.Size = UDim2.fromOffset(size, size)
		if wasDrag then
			commit("jukeX")
			commit("jukeY")
		elseif tap then
			state.juke = not state.juke
			commit("juke")
			notifyStatus()
		end
		J.render()
	end

	btn.InputBegan:Connect(function(input)
		if destroyed or J.input then
			return
		end
		local t = input.UserInputType
		if t ~= Enum.UserInputType.Touch and t ~= Enum.UserInputType.MouseButton1 then
			return
		end
		J.input, J.startPos, J.startAt = input, input.Position, os.clock()
		J.dragging, J.moved = false, false
		J.endConn = UserInputService.InputEnded:Connect(function(i)
			if i == J.input then
				J.finish(false)
			end
		end)
		J.moveConn = UserInputService.InputChanged:Connect(function(i)
			if i ~= J.input and not (J.input and J.input.UserInputType == Enum.UserInputType.MouseButton1
				and i.UserInputType == Enum.UserInputType.MouseMovement) then
				return
			end
			if J.dragging then
				setPos(i.Position.X, i.Position.Y)
			elseif not J.moved then
				local dp = i.Position - J.startPos
				if dp.X * dp.X + dp.Y * dp.Y > CONFIG.JUKE_SLOP * CONFIG.JUKE_SLOP then
					J.moved = true -- палец поехал до истечения удержания: это не нажатие и не перетаскивание
				end
			end
		end)
		J.beat = RunService.Heartbeat:Connect(function()
			if J.dragging or J.moved or not J.input then
				return
			end
			local st = J.input.UserInputState
			if st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel then
				J.finish(true) -- потерянное событие End
				return
			end
			if os.clock() - J.startAt >= CONFIG.JUKE_HOLD then
				J.dragging = true
				btn.Size = UDim2.fromOffset(size + 8, size + 8) -- кнопка слегка увеличилась: можно двигать
				stroke.Color = C.accent
			end
		end)
	end)
end

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
	elseif os.clock() < sp.pauseUntil then
		speedLabel.Text = "Speed (" .. (sp.pauseReason or "paused") .. ")"
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

local maneuverRow = makeRow(28)
makeLabel(maneuverRow, { Text = "Auto-Maneuver", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(maneuverRow, function()
	return state.maneuver
end, function(v)
	state.maneuver = v
	commit("maneuver")
	if not v then
		X.mv.release(false)
		X.mv.clearThreats()
	end
end)

local forceTpRow = makeRow(28)
makeLabel(forceTpRow, { Text = "Force Third Person", Size = UDim2.new(1, -56, 1, 0) })
makeSwitch(forceTpRow, function()
	return state.forceTP
end, function(v)
	state.forceTP = v
	commit("forceTP")
	X.tp.sync()
end)

local respRow = makeRow(36)
makeLabel(respRow, {
	Text = "Advanced Movement Responsiveness",
	Size = UDim2.new(1, -56, 1, 0),
	TextSize = 12,
	TextWrapped = true,
	TextTruncate = Enum.TextTruncate.None,
})
makeSwitch(respRow, function()
	return state.moveResp
end, function(v)
	state.moveResp = v
	commit("moveResp")
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
	Size = UDim2.new(0.44, 0, 0, 58),
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
			X.try("persist.backup", function()
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
	if name == "maneuver" and X.mv then
		X.mv.release(false)
		X.mv.clearThreats()
	end
	if name == "tp" then
		X.tp.disable()
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
	X.tp.disable()
	if X.jukeUI and X.jukeUI.finish then
		X.jukeUI.finish(true)
	end
	for _, s in ipairs(sliders) do
		s.stop()
	end
	X.try("destroy.unbind", function()
		RunService:UnbindFromRenderStep(X.renderName)
	end)
	speedUnbind()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	table.clear(connections)
	releaseFov(true)
	target = nil
	X.clearCands()
	if X.mv then
		X.mv.release(true)
		X.mv.clearThreats()
	end
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
		X.try("stick.restore", function()
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
