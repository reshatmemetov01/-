-- LavaConfig (ModuleScript в ReplicatedStorage)
-- Все настройки игры в одном месте. Меняй цифры здесь — код трогать не нужно.

local Config = {}

-- Ключи сохранений. Если поменять — у всех игроков начнётся новый прогресс.
Config.DATA_KEY = "LavaObby_v1"
Config.LEADERBOARD_KEY = "LavaObby_Top_v1"

-- Карта
Config.TOTAL_STAGES = 50 -- игровых этапов; чекпоинт 51 = финиш
Config.STAGES_PER_ZONE = 10
Config.MAP_SEED = 2026 -- поменяй число — получишь другую карту

Config.Zones = {
	{ name = "Гостиная", emoji = "🛋", color = Color3.fromRGB(255, 190, 110) },
	{ name = "Кухня", emoji = "🍳", color = Color3.fromRGB(120, 220, 255) },
	{ name = "Лавовые пещеры", emoji = "🪨", color = Color3.fromRGB(190, 140, 255) },
	{ name = "Жерло вулкана", emoji = "🌋", color = Color3.fromRGB(255, 90, 40) },
	{ name = "Небо над вулканом", emoji = "☁️", color = Color3.fromRGB(255, 240, 140) },
}

-- ============ МОНЕТИЗАЦИЯ ============
-- Создай Game Pass'ы и Developer Product'ы на create.roblox.com
-- и вставь их ID вместо нулей. Пока стоит 0 — кнопка покупки просто
-- покажет сообщение «ещё не настроено».
Config.GamePasses = {
	VIP = 0, -- 👑 VIP (самый важный!)
	Speed = 0, -- ⚡ Скорость x1.5
	SuperJump = 0, -- 🦘 Супер-прыжок
	DoubleCoins = 0, -- 🪙 x2 монеты
	SkinPack = 0, -- 🌈 Эксклюзивные скины
	DragonPet = 0, -- 🐉 Питомец Дракончик
}

Config.Products = {
	SkipStage = 3729632532, -- ⏭ Пропуск этапа (главный заработок в obby)
	SkipZone = 0, -- ⏩ Пропуск зоны (10 этапов)
	LavaShield = 3729634631, -- 🛡 Щит от лавы на 60 сек
	Coins500 = 0, -- 💰 500 монет
	Coins2500 = 3729634408, -- 💰 2 500 монет
	Coins10000 = 0, -- 💰 10 000 монет
	LavaToWater = 0, -- 🌊 Лава → вода для всего сервера
}

-- Бейджи (необязательно). 0 = не выдавать.
Config.Badges = {
	Finish = 0,
	Rebirth = 0,
	AllDucks = 0,
	SecretRoom = 0,
	DontJump = 0,
}

-- Тексты для магазина
Config.ShopPasses = {
	{ key = "VIP", name = "👑 VIP", desc = "Золотой скин, питомец Феникс, королевский след, VIP-зона с сундуком, тег над головой и +25% монет." },
	{ key = "Speed", name = "⚡ Скорость", desc = "Бегаешь в 1.5 раза быстрее. Навсегда." },
	{ key = "SuperJump", name = "🦘 Супер-прыжок", desc = "Прыгаешь выше и дальше. Этапы станут проще!" },
	{ key = "DoubleCoins", name = "🪙 x2 монеты", desc = "Все монеты удваиваются. Навсегда." },
	{ key = "SkinPack", name = "🌈 Скины PRO", desc = "Скины «Радуга» и «Галактика», которых нет ни у кого." },
	{ key = "DragonPet", name = "🐉 Дракончик", desc = "Самый сильный питомец: +75% монет." },
}

Config.ShopProducts = {
	{ key = "SkipStage", name = "⏭ Пропуск этапа", desc = "Сразу на следующий этап." },
	{ key = "SkipZone", name = "⏩ Пропуск зоны", desc = "Сразу в следующую зону." },
	{ key = "LavaShield", name = "🛡 Щит от лавы", desc = "60 секунд лава и ловушки не убивают." },
	{ key = "Coins500", name = "💰 500 монет", desc = "На скин или питомца." },
	{ key = "Coins2500", name = "💰 2 500 монет", desc = "Выгоднее!" },
	{ key = "Coins10000", name = "💰 10 000 монет", desc = "Самый выгодный набор!" },
	{ key = "LavaToWater", name = "🌊 Лава → вода", desc = "Для ВСЕХ на сервере на 20 секунд. Все скажут спасибо!" },
}

Config.CoinPacks = { Coins500 = 500, Coins2500 = 2500, Coins10000 = 10000 }

-- ============ НАГРАДЫ ============
Config.NORMAL_WALKSPEED = 16
Config.SPEED_WALKSPEED = 24
Config.NORMAL_JUMP = 7.2
Config.SUPER_JUMP = 11
Config.SHIELD_DURATION = 60

Config.COIN_VALUE = 2 -- за одну монетку на карте
Config.COIN_RESPAWN = 45 -- через сколько секунд монетка появится снова
Config.STAGE_REWARD = 5 -- за каждый новый этап
Config.FINISH_REWARD = 500
Config.REBIRTH_BONUS = 0.5 -- +50% монет за каждое перерождение
Config.REBIRTH_COINS = 250 -- разовая награда x номер перерождения
Config.VIP_COIN_BONUS = 1.25

Config.GIFT_INTERVAL = 300 -- подарок за время в игре каждые 5 минут
Config.GIFT_REWARDS = { 50, 75, 100, 150, 200, 300 }
Config.DAILY_REWARDS = { 50, 80, 120, 160, 220, 300, 500 } -- дни 1..7 подряд

Config.DUCK_COUNT = 5
Config.DUCK_REWARD = 50
Config.ALL_DUCKS_REWARD = 1000
Config.SECRET_REWARD = 250

Config.WATER_BUTTON_DURATION = 12
Config.WATER_BUTTON_COOLDOWN = 180
Config.WATER_PRODUCT_DURATION = 20

Config.VIP_CHEST_REWARD = 150
Config.VIP_CHEST_COOLDOWN = 600

-- ============ СЛЕДЫ ============
-- price > 0 — покупается за монеты; unlock — открывается за достижение.
Config.Trails = {
	{ id = "spark", name = "Искра", price = 150, colors = { Color3.fromRGB(255, 240, 150), Color3.fromRGB(255, 150, 40) } },
	{ id = "ocean", name = "Океан", price = 400, colors = { Color3.fromRGB(80, 200, 255), Color3.fromRGB(20, 60, 200) } },
	{ id = "toxic", name = "Токсик", price = 700, colors = { Color3.fromRGB(180, 255, 60), Color3.fromRGB(30, 140, 30) } },
	{ id = "candy", name = "Конфета", price = 1200, colors = { Color3.fromRGB(255, 120, 200), Color3.fromRGB(140, 220, 255) } },
	{ id = "galaxy", name = "Галактика", price = 2500, colors = { Color3.fromRGB(140, 60, 255), Color3.fromRGB(20, 10, 60) } },
	{
		id = "rainbow",
		name = "Радуга",
		price = 5000,
		colors = {
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(255, 200, 40),
			Color3.fromRGB(60, 220, 90),
			Color3.fromRGB(60, 140, 255),
			Color3.fromRGB(190, 80, 255),
		},
	},
	{ id = "duck", name = "Золотая утка", unlock = "ducks", colors = { Color3.fromRGB(255, 230, 60), Color3.fromRGB(255, 170, 0) } },
	{ id = "vip", name = "Королевский", unlock = "vip", colors = { Color3.fromRGB(255, 215, 80), Color3.fromRGB(160, 60, 255) } },
	{ id = "phoenix", name = "Феникс", unlock = "rebirth3", colors = { Color3.fromRGB(255, 80, 20), Color3.fromRGB(255, 230, 120) } },
}

-- ============ СКИНЫ ============
-- Перекрашивают всего персонажа. Одежда снимается, чтобы скин было видно.
Config.Skins = {
	{ id = "stone", name = "Каменный", price = 400, color = Color3.fromRGB(110, 105, 100), material = "Slate" },
	{ id = "lava", name = "Лавовый", price = 600, color = Color3.fromRGB(255, 90, 20), material = "CrackedLava" },
	{ id = "ice", name = "Ледяной", price = 900, color = Color3.fromRGB(160, 220, 255), material = "Ice" },
	{ id = "neon", name = "Неоновый", price = 1500, color = Color3.fromRGB(255, 60, 200), material = "Neon" },
	{ id = "ghost", name = "Призрак", price = 2500, color = Color3.fromRGB(200, 230, 255), material = "ForceField" },
	{ id = "robot", name = "Робот", price = 3500, color = Color3.fromRGB(150, 155, 165), material = "DiamondPlate" },
	{ id = "gold", name = "Золотой", unlock = "vip", color = Color3.fromRGB(255, 200, 50), material = "Foil" },
	{ id = "duckskin", name = "Утиный", unlock = "ducks", color = Color3.fromRGB(255, 225, 40), material = "SmoothPlastic" },
	{
		id = "rainbow",
		name = "Радуга",
		unlock = "pass:SkinPack",
		material = "Neon",
		colors = {
			Color3.fromRGB(255, 60, 60),
			Color3.fromRGB(255, 170, 40),
			Color3.fromRGB(255, 240, 60),
			Color3.fromRGB(60, 220, 90),
			Color3.fromRGB(60, 140, 255),
			Color3.fromRGB(170, 80, 255),
		},
	},
	{ id = "galaxy", name = "Галактика", unlock = "pass:SkinPack", color = Color3.fromRGB(70, 20, 140), material = "Neon" },
}

-- ============ ПИТОМЦЫ ============
-- Летают рядом с игроком и дают бонус к монетам.
Config.Pets = {
	{ id = "duckling", name = "Утёнок", price = 300, bonus = 0.1, color = Color3.fromRGB(255, 220, 40) },
	{ id = "flame", name = "Огонёк", price = 1000, bonus = 0.2, color = Color3.fromRGB(255, 120, 30) },
	{ id = "cubecat", name = "Кубокот", price = 2500, bonus = 0.3, color = Color3.fromRGB(240, 240, 240) },
	{ id = "slime", name = "Лавовый слайм", price = 5000, bonus = 0.4, color = Color3.fromRGB(255, 80, 20) },
	{ id = "goldduck", name = "Золотая утка", unlock = "ducks", bonus = 0.25, color = Color3.fromRGB(255, 200, 40) },
	{ id = "phoenix", name = "Феникс", unlock = "vip", bonus = 0.5, color = Color3.fromRGB(255, 160, 40) },
	{ id = "dragon", name = "Дракончик", unlock = "pass:DragonPet", bonus = 0.75, color = Color3.fromRGB(80, 200, 90) },
}

Config.UnlockText = {
	ducks = "Найди все 5 уточек 🦆",
	vip = "Только для 👑 VIP",
	rebirth3 = "3 перерождения 🔁",
	["pass:SkinPack"] = "Пропуск 🌈 Скины PRO",
	["pass:DragonPet"] = "Пропуск 🐉 Дракончик",
}

-- Категории предметов магазина за монеты
Config.ItemCategories = {
	trails = { list = "Trails", owned = "trails", equipped = "trail" },
	skins = { list = "Skins", owned = "skins", equipped = "skin" },
	pets = { list = "Pets", owned = "pets", equipped = "pet" },
}

function Config.GetItem(category, id)
	local cat = Config.ItemCategories[category]
	if not cat then
		return nil
	end
	for _, item in ipairs(Config[cat.list]) do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Проверка «открыт ли предмет за достижение». getAttr(name) -> значение атрибута игрока.
function Config.UnlockMet(unlock, getAttr)
	if unlock == "ducks" then
		return (getAttr("Ducks") or 0) >= Config.DUCK_COUNT
	elseif unlock == "vip" then
		return getAttr("PassVIP") == true
	elseif unlock == "rebirth3" then
		return (getAttr("Rebirths") or 0) >= 3
	elseif type(unlock) == "string" and string.sub(unlock, 1, 5) == "pass:" then
		return getAttr("Pass" .. string.sub(unlock, 6)) == true
	end
	return false
end

function Config.ZoneOfStage(stage)
	return math.clamp(math.ceil(stage / Config.STAGES_PER_ZONE), 1, #Config.Zones)
end

function Config.GetTrail(id)
	for _, t in ipairs(Config.Trails) do
		if t.id == id then
			return t
		end
	end
	return nil
end

return Config
