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
	Speed = 0, -- ⚡ Скорость x1.5
	DoubleCoins = 0, -- 🪙 x2 монеты
	VIP = 0, -- 👑 VIP
}

Config.Products = {
	SkipStage = 0, -- ⏭ Пропуск этапа
	Coins500 = 0, -- 💰 500 монет
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
	{ key = "Speed", name = "⚡ Скорость", desc = "Бегаешь в 1.5 раза быстрее. Навсегда." },
	{ key = "DoubleCoins", name = "🪙 x2 монеты", desc = "Все монеты удваиваются. Навсегда." },
	{ key = "VIP", name = "👑 VIP", desc = "VIP-зона с сундуком, тег над головой, +25% монет и королевский след." },
}

Config.ShopProducts = {
	{ key = "SkipStage", name = "⏭ Пропуск этапа", desc = "Сразу на следующий этап." },
	{ key = "Coins500", name = "💰 500 монет", desc = "Купи себе крутой след." },
	{ key = "LavaToWater", name = "🌊 Лава → вода", desc = "Для ВСЕХ на сервере на 20 секунд. Все скажут спасибо!" },
}

-- ============ НАГРАДЫ ============
Config.NORMAL_WALKSPEED = 16
Config.SPEED_WALKSPEED = 24

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

Config.UnlockText = {
	ducks = "Найди все 5 уточек 🦆",
	vip = "Только для 👑 VIP",
	rebirth3 = "3 перерождения 🔁",
}

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
