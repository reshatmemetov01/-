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
	{ name = "Лавовые пещеры", emoji = "⛰️", color = Color3.fromRGB(190, 140, 255) },
	{ name = "Жерло вулкана", emoji = "🌋", color = Color3.fromRGB(255, 90, 40) },
	{ name = "Небо над вулканом", emoji = "☁️", color = Color3.fromRGB(255, 240, 140) },
}

-- ============ МОНЕТИЗАЦИЯ ============
-- Создай Game Pass'ы и Developer Product'ы на create.roblox.com
-- и вставь их ID вместо нулей. Пока стоит 0 — кнопка покупки просто
-- покажет сообщение «ещё не настроено».
Config.GamePasses = {
	VIP = 1464490994, -- 👑 VIP (самый важный!)
	Speed = 0, -- ⚡ Скорость x1.5
	SuperJump = 0, -- 🚀 Супер-прыжок
	DoubleCoins = 0, -- 💰 x2 монеты
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

-- Порядок товаров в магазине. Названия и описания — в скрипте LavaText.
Config.ShopPasses = { "VIP", "Speed", "SuperJump", "DoubleCoins", "SkinPack", "DragonPet" }
Config.ShopProducts = { "SkipStage", "SkipZone", "LavaShield", "Coins500", "Coins2500", "Coins10000", "LavaToWater" }

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

-- ============ МАГАЗИН ЗА МОНЕТЫ ============
-- price — цена в монетах; unlock — открывается за достижение или пропуск.
-- rarity: common / rare / epic / legendary / exclusive (цвет рамки в магазине).
-- Названия и описания — в скрипте LavaText (item_<категория>_<id>).
local C = Color3.fromRGB

Config.Rarities = {
	common = C(170, 170, 180),
	rare = C(70, 150, 255),
	epic = C(180, 90, 255),
	legendary = C(255, 190, 40),
	exclusive = C(255, 70, 120),
}

-- ✨ СЛЕДЫ (16)
Config.Trails = {
	{ id = "spark", price = 150, rarity = "common", colors = { C(255, 240, 150), C(255, 150, 40) } },
	{ id = "mint", price = 250, rarity = "common", colors = { C(180, 255, 220), C(40, 200, 150) } },
	{ id = "ocean", price = 400, rarity = "rare", colors = { C(80, 200, 255), C(20, 60, 200) } },
	{ id = "sunset", price = 500, rarity = "rare", colors = { C(255, 120, 60), C(160, 60, 200) } },
	{ id = "toxic", price = 700, rarity = "rare", colors = { C(180, 255, 60), C(30, 140, 30) } },
	{ id = "love", price = 900, rarity = "rare", colors = { C(255, 100, 160), C(220, 20, 60) } },
	{ id = "candy", price = 1200, rarity = "epic", colors = { C(255, 120, 200), C(140, 220, 255) } },
	{ id = "ice", price = 1500, rarity = "epic", colors = { C(230, 250, 255), C(100, 190, 255) } },
	{ id = "lava", price = 1800, rarity = "epic", colors = { C(255, 230, 80), C(255, 60, 0) } },
	{ id = "shadow", price = 2200, rarity = "epic", colors = { C(90, 90, 110), C(10, 10, 15) } },
	{ id = "galaxy", price = 2500, rarity = "legendary", colors = { C(140, 60, 255), C(20, 10, 60) } },
	{ id = "sun", price = 3500, rarity = "legendary", colors = { C(255, 255, 200), C(255, 190, 0) } },
	{ id = "rainbow", price = 5000, rarity = "legendary", colors = { C(255, 60, 60), C(255, 200, 40), C(60, 220, 90), C(60, 140, 255), C(190, 80, 255) } },
	{ id = "phoenix", unlock = "rebirth3", rarity = "legendary", colors = { C(255, 80, 20), C(255, 230, 120) } },
	{ id = "duck", unlock = "ducks", rarity = "legendary", colors = { C(255, 230, 60), C(255, 170, 0) } },
	{ id = "vip", unlock = "vip", rarity = "exclusive", colors = { C(255, 215, 80), C(160, 60, 255) } },
}

-- 🎨 СКИНЫ (20) — перекрашивают всего персонажа, одежда снимается
Config.Skins = {
	{ id = "stone", price = 400, rarity = "common", color = C(110, 105, 100), material = "Slate" },
	{ id = "wood", price = 450, rarity = "common", color = C(160, 110, 65), material = "WoodPlanks" },
	{ id = "grass", price = 500, rarity = "common", color = C(80, 170, 70), material = "Grass" },
	{ id = "sand", price = 550, rarity = "common", color = C(225, 200, 140), material = "Sand" },
	{ id = "lava", price = 600, rarity = "rare", color = C(255, 90, 20), material = "CrackedLava" },
	{ id = "brick", price = 700, rarity = "rare", color = C(170, 70, 50), material = "Brick" },
	{ id = "chocolate", price = 800, rarity = "rare", color = C(100, 60, 35), material = "SmoothPlastic" },
	{ id = "ice", price = 900, rarity = "rare", color = C(160, 220, 255), material = "Ice" },
	{ id = "marble", price = 1100, rarity = "epic", color = C(235, 235, 240), material = "Marble" },
	{ id = "metal", price = 1300, rarity = "epic", color = C(180, 185, 195), material = "Metal" },
	{ id = "neon", price = 1500, rarity = "epic", color = C(255, 60, 200), material = "Neon" },
	{ id = "toxicneon", price = 1700, rarity = "epic", color = C(120, 255, 60), material = "Neon" },
	{ id = "shadow", price = 2000, rarity = "legendary", color = C(20, 20, 25), material = "SmoothPlastic" },
	{ id = "ghost", price = 2500, rarity = "legendary", color = C(200, 230, 255), material = "ForceField" },
	{ id = "robot", price = 3500, rarity = "legendary", color = C(150, 155, 165), material = "DiamondPlate" },
	{ id = "diamond", price = 5000, rarity = "legendary", color = C(170, 240, 255), material = "Glass" },
	{ id = "duckskin", unlock = "ducks", rarity = "legendary", color = C(255, 225, 40), material = "SmoothPlastic" },
	{ id = "gold", unlock = "vip", rarity = "exclusive", color = C(255, 200, 50), material = "Foil" },
	{ id = "rainbow", unlock = "pass:SkinPack", rarity = "exclusive", material = "Neon", colors = { C(255, 60, 60), C(255, 170, 40), C(255, 240, 60), C(60, 220, 90), C(60, 140, 255), C(170, 80, 255) } },
	{ id = "galaxy", unlock = "pass:SkinPack", rarity = "exclusive", color = C(70, 20, 140), material = "Neon" },
}

-- 🐾 ПИТОМЦЫ (14) — летают рядом и дают бонус к монетам
Config.Pets = {
	{ id = "duckling", price = 300, rarity = "common", bonus = 0.1, color = C(255, 220, 40) },
	{ id = "frog", price = 500, rarity = "common", bonus = 0.12, color = C(90, 200, 70) },
	{ id = "penguin", price = 800, rarity = "rare", bonus = 0.15, color = C(30, 30, 40) },
	{ id = "flame", price = 1000, rarity = "rare", bonus = 0.2, color = C(255, 120, 30) },
	{ id = "bee", price = 1500, rarity = "rare", bonus = 0.22, color = C(255, 200, 30) },
	{ id = "snowman", price = 2000, rarity = "epic", bonus = 0.25, color = C(245, 250, 255) },
	{ id = "cubecat", price = 2500, rarity = "epic", bonus = 0.3, color = C(240, 240, 240) },
	{ id = "ghostpet", price = 3500, rarity = "epic", bonus = 0.33, color = C(220, 235, 255) },
	{ id = "slime", price = 5000, rarity = "legendary", bonus = 0.4, color = C(255, 80, 20) },
	{ id = "robocube", price = 7500, rarity = "legendary", bonus = 0.5, color = C(160, 165, 175) },
	{ id = "minivolcano", price = 10000, rarity = "legendary", bonus = 0.6, color = C(70, 55, 50) },
	{ id = "goldduck", unlock = "ducks", rarity = "legendary", bonus = 0.25, color = C(255, 200, 40) },
	{ id = "phoenix", unlock = "vip", rarity = "exclusive", bonus = 0.5, color = C(255, 160, 40) },
	{ id = "dragon", unlock = "pass:DragonPet", rarity = "exclusive", bonus = 0.75, color = C(80, 200, 90) },
}

-- 🌟 АУРЫ (9) — эффекты вокруг персонажа
-- kind: sparkles / fire / smoke / particles
Config.Auras = {
	{ id = "sparkle", price = 800, rarity = "rare", kind = "sparkles", colors = { C(255, 255, 255) } },
	{ id = "hearts", price = 1200, rarity = "rare", kind = "particles", colors = { C(255, 120, 180), C(255, 40, 90) } },
	{ id = "fire", price = 2000, rarity = "epic", kind = "fire", colors = { C(255, 140, 30), C(255, 40, 0) } },
	{ id = "frost", price = 2000, rarity = "epic", kind = "particles", colors = { C(220, 245, 255), C(80, 180, 255) } },
	{ id = "stars", price = 3000, rarity = "epic", kind = "particles", colors = { C(255, 250, 180), C(255, 200, 40) } },
	{ id = "electric", price = 4500, rarity = "legendary", kind = "particles", fast = true, colors = { C(200, 255, 255), C(40, 160, 255) } },
	{ id = "shadow", price = 4500, rarity = "legendary", kind = "smoke", colors = { C(30, 30, 40) } },
	{ id = "rainbow", price = 8000, rarity = "legendary", kind = "particles", colors = { C(255, 60, 60), C(255, 200, 40), C(60, 220, 90), C(60, 140, 255), C(190, 80, 255) } },
	{ id = "golden", unlock = "vip", rarity = "exclusive", kind = "particles", colors = { C(255, 240, 150), C(255, 180, 0) } },
}

-- ⭐ ПРИВИЛЕГИИ (6) — покупаются навсегда и работают сами
Config.Perks = {
	{ id = "swift", price = 1500, rarity = "rare" }, -- +3 к скорости бега
	{ id = "fastgift", price = 2500, rarity = "rare" }, -- подарок каждые 3 минуты вместо 5
	{ id = "lucky", price = 3000, rarity = "epic" }, -- +15% монет
	{ id = "shieldplus", price = 3500, rarity = "epic" }, -- щит от лавы длится на 30 сек дольше
	{ id = "magnet", price = 4000, rarity = "legendary" }, -- монетки сами летят к тебе
	{ id = "doublejump", price = 8000, rarity = "legendary" }, -- двойной прыжок
}
Config.PERK_SWIFT_BONUS = 3
Config.PERK_LUCKY_BONUS = 1.15
Config.PERK_FASTGIFT_INTERVAL = 180
Config.PERK_SHIELD_BONUS = 30
Config.PERK_MAGNET_RADIUS = 14

-- Категории магазина за монеты (equipped = nil — предмет не надевается, а работает сам)
Config.ItemCategories = {
	trails = { list = "Trails", owned = "trails", equipped = "trail" },
	skins = { list = "Skins", owned = "skins", equipped = "skin" },
	pets = { list = "Pets", owned = "pets", equipped = "pet" },
	auras = { list = "Auras", owned = "auras", equipped = "aura" },
	perks = { list = "Perks", owned = "perks" },
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
