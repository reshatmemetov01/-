-- LavaClient (LocalScript в StarterPlayer > StarterPlayerScripts)
-- Интерфейс игрока: этап, монеты, магазин, подарки, перерождение,
-- а также батуты, вращение монет, VIP-дверь и эффекты.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local LocalizationService = game:GetService("LocalizationService")

local player = Players.LocalPlayer
local Config = require(ReplicatedStorage:WaitForChild("LavaConfig"))
local Text = require(ReplicatedStorage:WaitForChild("LavaText"))

-- Язык игрока: берём из настроек его аккаунта Roblox
local locale = player.LocaleId
if not locale or locale == "" then
	locale = LocalizationService.RobloxLocaleId
end
local LANG = Text.LangFor(locale)
local function tr(key, ...)
	return Text.Format(LANG, key, { ... })
end
local remotes = ReplicatedStorage:WaitForChild("LavaRemotes")
local NotifyRE = remotes:WaitForChild("Notify")
local CoinRE = remotes:WaitForChild("CoinHidden")
local EffectRE = remotes:WaitForChild("Effect")
local ActionRE = remotes:WaitForChild("Action")

local TOTAL = Config.TOTAL_STAGES
local FINISH = TOTAL + 1

-- ============ UI-ПОМОЩНИКИ ============
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 12) }, o)
end

local function outline(o, color, thick)
	new("UIStroke", { Color = color or Color3.new(0, 0, 0), Thickness = thick or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, o)
end

local function textStroke(o)
	new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }, o)
end

local DARK = Color3.fromRGB(30, 20, 25)
local GOLD = Color3.fromRGB(255, 205, 60)
local scales = {}

local function scaled(o)
	local s = new("UIScale", { Scale = 1 }, o)
	table.insert(scales, s)
	return o
end

local function button(props, parent)
	local b = new("TextButton", {
		AutoButtonColor = true,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		BackgroundColor3 = props.color or Color3.fromRGB(255, 120, 40),
		Size = props.size or UDim2.new(1, 0, 0, 46),
		Position = props.position or UDim2.new(),
		Text = props.text or "",
		LayoutOrder = props.order or 0,
	}, parent)
	corner(b, 12)
	outline(b, Color3.new(0, 0, 0), 2)
	textStroke(b)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, b)
	return b
end

local gui = new("ScreenGui", { Name = "LavaUI", ResetOnSpawn = false, AutoLocalize = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- ============ ВЕРХНЯЯ ПАНЕЛЬ: ЭТАП ============
local top = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 8),
	Size = UDim2.fromOffset(300, 70),
	BackgroundColor3 = DARK,
	BackgroundTransparency = 0.15,
}, gui))
corner(top, 14)
outline(top, Color3.fromRGB(255, 120, 40), 2)
local stageLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 32),
	Position = UDim2.fromOffset(0, 4),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = tr("ui_stage", 1, TOTAL),
}, top)
textStroke(stageLabel)
local zoneLabel = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 18),
	Position = UDim2.fromOffset(0, 36),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 200, 120),
	Text = "",
}, top)
local barBack = new("Frame", { Size = UDim2.new(1, -24, 0, 8), Position = UDim2.fromOffset(12, 57), BackgroundColor3 = Color3.fromRGB(60, 40, 40) }, top)
corner(barBack, 4)
local barFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 40) }, barBack)
corner(barFill, 4)

local prevBtn = button({ text = "◀", size = UDim2.fromOffset(50, 50), position = UDim2.new(0, -58, 0, 10), color = Color3.fromRGB(80, 60, 70) }, top)
local nextBtn = button({ text = "▶", size = UDim2.fromOffset(50, 50), position = UDim2.new(1, 8, 0, 10), color = Color3.fromRGB(80, 60, 70) }, top)

-- ============ ЛЕВАЯ КОЛОНКА: КНОПКИ ============
local left = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 10, 0.45, 0),
	Size = UDim2.fromOffset(160, 460),
	BackgroundTransparency = 1,
}, gui))
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, left)
local shopBtn = button({ text = tr("ui_shop"), color = Color3.fromRGB(60, 170, 90), order = 1 }, left)
local vipBtn = button({ text = tr("ui_vip"), color = Color3.fromRGB(230, 170, 20), order = 2 }, left)
local giftBtn = button({ text = "🎁 5:00", color = Color3.fromRGB(150, 90, 200), order = 3 }, left)
local skipBtn = button({ text = tr("ui_skip"), color = Color3.fromRGB(230, 140, 30), order = 4 }, left)
local shieldBtn = button({ text = tr("ui_shield"), color = Color3.fromRGB(40, 130, 230), order = 5 }, left)
local respawnBtn = button({ text = tr("ui_respawn"), color = Color3.fromRGB(90, 90, 100), order = 6 }, left)
local lobbyBtn = button({ text = tr("ui_lobby"), color = Color3.fromRGB(60, 160, 120), order = 6 }, left)
lobbyBtn.Activated:Connect(function()
	ActionRE:FireServer("ToLobby")
end)
local rebirthBtn = button({ text = tr("ui_rebirth"), color = Color3.fromRGB(200, 60, 200), order = 7 }, left)
rebirthBtn.Visible = false

-- ============ ПРАВАЯ КОЛОНКА: СЧЁТЧИКИ ============
local right = scaled(new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -10, 0.4, 0),
	Size = UDim2.fromOffset(160, 260),
	BackgroundTransparency = 1,
}, gui))
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
local function counter(text, order)
	local f = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.2,
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = text,
		LayoutOrder = order,
	}, right)
	corner(f, 10)
	textStroke(f)
	new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, f)
	return f
end
local coinsLabel = counter("💰 0", 1)
local ducksLabel = counter("🦆 0/" .. Config.DUCK_COUNT, 2)
local multLabel = counter("x1", 3)

-- ============ КРУГЛЫЙ ТАЙМЕР ЩИТА (наверху) ============
local shieldCircle = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 86),
	Size = UDim2.fromOffset(66, 66),
	BackgroundColor3 = Color3.fromRGB(20, 40, 70),
	BackgroundTransparency = 0.1,
	Visible = false,
}, gui))
new("UICorner", { CornerRadius = UDim.new(1, 0) }, shieldCircle)
local shieldRing = new("UIStroke", { Color = Color3.fromRGB(90, 190, 255), Thickness = 4 }, shieldCircle)
new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.fromOffset(0, 5),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	Text = "🛡",
}, shieldCircle)
local shieldNum = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 30),
	Position = UDim2.fromOffset(0, 26),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "60",
}, shieldCircle)
textStroke(shieldNum)

-- ============ УВЕДОМЛЕНИЯ ============
local toastArea = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 210),
	Size = UDim2.new(0.6, 0, 0, 220),
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, toastArea)
local toastOrder = 0

local function toast(text, color)
	toastOrder += 1
	local t = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = DARK,
		BackgroundTransparency = 0.15,
		Font = Enum.Font.GothamBold,
		TextScaled = true,
		TextColor3 = color or Color3.new(1, 1, 1),
		Text = text,
		LayoutOrder = toastOrder,
	}, toastArea)
	corner(t, 10)
	textStroke(t)
	new("UIPadding", { PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, t)
	local kids = {}
	for _, c in ipairs(toastArea:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(kids, c)
		end
	end
	if #kids > 5 then
		table.sort(kids, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		kids[1]:Destroy()
	end
	task.delay(4.5, function()
		if t.Parent then
			TweenService:Create(t, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.45)
			t:Destroy()
		end
	end)
end

NotifyRE.OnClientEvent:Connect(function(key, color, args)
	toast(Text.Format(LANG, key, args), color)
end)

-- ============ БОЛЬШОЙ БАННЕР ============
local banner = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.3),
	Size = UDim2.new(0.8, 0, 0, 90),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	TextTransparency = 1,
	Text = "",
}, gui)
local bannerStroke = new("UIStroke", { Thickness = 4, Color = Color3.new(0, 0, 0), Transparency = 1 }, banner)

local function showBanner(text, color)
	banner.Text = text
	banner.TextColor3 = color or Color3.new(1, 1, 1)
	banner.TextTransparency = 0
	bannerStroke.Transparency = 0
	banner.Size = UDim2.new(0.5, 0, 0, 60)
	TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.new(0.8, 0, 0, 90) }):Play()
	task.delay(2.6, function()
		if banner.Text == text then
			TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1 }):Play()
			TweenService:Create(bannerStroke, TweenInfo.new(0.6), { Transparency = 1 }):Play()
		end
	end)
end

local warnLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.42),
	Size = UDim2.new(0.7, 0, 0, 50),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.fromRGB(255, 80, 40),
	Text = "",
	Visible = false,
}, gui)
textStroke(warnLabel)

-- ============ МАГАЗИН ============
local shop = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(780, 470),
	BackgroundColor3 = Color3.fromRGB(40, 28, 34),
	Visible = false,
	ZIndex = 5,
}, gui))
corner(shop, 18)
outline(shop, Color3.fromRGB(255, 140, 50), 3)
local shopTitle = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -80, 0, 44),
	Position = UDim2.fromOffset(16, 8),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextColor3 = GOLD,
	Text = tr("ui_shop_title"),
	ZIndex = 6,
}, shop)
textStroke(shopTitle)
local closeBtn = button({ text = "✕", size = UDim2.fromOffset(44, 44), position = UDim2.new(1, -56, 0, 10), color = Color3.fromRGB(200, 50, 50) }, shop)
closeBtn.ZIndex = 6
local TABS = {
	{ "trails", tr("tab_trails") },
	{ "skins", tr("tab_skins") },
	{ "pets", tr("tab_pets") },
	{ "auras", tr("tab_auras") },
	{ "perks", tr("tab_perks") },
	{ "robux", tr("tab_robux") },
}
local tabButtons = {}
for i, t in ipairs(TABS) do
	local b = button({ text = t[2], size = UDim2.fromOffset(118, 38), position = UDim2.fromOffset(16 + (i - 1) * 124, 60), color = Color3.fromRGB(90, 70, 80) }, shop)
	b.ZIndex = 6
	tabButtons[t[1]] = b
end
local list = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 110),
	Size = UDim2.new(1, -32, 1, -126),
	BackgroundTransparency = 1,
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ZIndex = 6,
}, shop)
new("UIGridLayout", { CellSize = UDim2.fromOffset(172, 180), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)

local currentTab = "trails"

local function csvSet(str)
	local set = {}
	for id in string.gmatch(str or "", "[^,]+") do
		set[id] = true
	end
	return set
end

local function attrGetter(name)
	return player:GetAttribute(name)
end
local CAT_ATTR = {
	trails = { "Trails", "Trail" },
	skins = { "Skins", "Skin" },
	pets = { "Pets", "Pet" },
	auras = { "Auras", "Aura" },
	perks = { "Perks", nil },
}

local function ownsItem(category, item)
	if item.unlock then
		return Config.UnlockMet(item.unlock, attrGetter)
	end
	return csvSet(player:GetAttribute(CAT_ATTR[category][1]))[item.id] == true
end

local function card(order, title, desc, colors, btnText, btnColor, onClick, rarity)
	local c = new("Frame", { BackgroundColor3 = Color3.fromRGB(60, 45, 52), LayoutOrder = order, ZIndex = 6 }, list)
	corner(c, 12)
	local rarityColor = rarity and Config.Rarities[rarity]
	if rarityColor then
		new("UIStroke", { Color = rarityColor, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, c)
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(rarityColor:Lerp(Color3.new(1, 1, 1), 0.2), Color3.new(0.35, 0.3, 0.33)),
			Transparency = NumberSequence.new(0.55, 0),
		}, c)
		local rl = new("TextLabel", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(8, 24),
			Size = UDim2.new(1, -16, 0, 14),
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextColor3 = rarityColor,
			Text = tr("rarity_" .. rarity),
			ZIndex = 7,
		}, c)
		textStroke(rl)
	end
	if colors then
		local strip = new("Frame", { Size = UDim2.new(1, -16, 0, 12), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 7 }, c)
		corner(strip, 7)
		local kps = {}
		for i, col in ipairs(colors) do
			table.insert(kps, ColorSequenceKeypoint.new(#colors == 1 and 0 or (i - 1) / (#colors - 1), col))
		end
		if #colors == 1 then
			table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
		end
		new("UIGradient", { Color = ColorSequence.new(kps) }, strip)
	end
	local t = new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 40),
		Size = UDim2.new(1, -16, 0, 26),
		Font = Enum.Font.GothamBlack,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Text = title,
		ZIndex = 7,
	}, c)
	textStroke(t)
	new("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, 68),
		Size = UDim2.new(1, -16, 0, 58),
		Font = Enum.Font.Gotham,
		TextWrapped = true,
		TextSize = 13,
		TextColor3 = Color3.fromRGB(230, 220, 220),
		Text = desc,
		ZIndex = 7,
	}, c)
	local b = button({ text = btnText, size = UDim2.new(1, -16, 0, 40), position = UDim2.new(0, 8, 1, -48), color = btnColor }, c)
	b.ZIndex = 7
	b.Activated:Connect(onClick)
end

local function clearList()
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
end

local function notConfigured()
	toast(tr("not_configured"), Color3.fromRGB(255, 200, 120))
end

local function promptProduct(key)
	local id = Config.Products[key]
	if not id or id == 0 then
		notConfigured()
		return
	end
	MarketplaceService:PromptProductPurchase(player, id)
end

local function promptPass(key)
	local id = Config.GamePasses[key]
	if not id or id == 0 then
		notConfigured()
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, id)
end

local function refreshShop()
	if not shop.Visible then
		return
	end
	clearList()
	if currentTab ~= "robux" then
		local category = currentTab
		local cat = Config.ItemCategories[category]
		local isPerk = category == "perks"
		local equipped = (not isPerk and player:GetAttribute(CAT_ATTR[category][2])) or ""
		if not isPerk then
			card(0, tr("none_" .. category), tr("none_desc"), nil, equipped == "" and tr("selected") or tr("take_off"), Color3.fromRGB(90, 90, 100), function()
				ActionRE:FireServer("EquipItem", { category = category, id = "" })
			end)
		end
		for i, item in ipairs(Config[cat.list]) do
			local owned = ownsItem(category, item)
			local colors = item.colors or (item.color and { item.color }) or nil
			local desc
			if item.price then
				desc = owned and tr("yours") or tr("price", item.price)
			else
				desc = tr("unlock_" .. tostring(item.unlock))
			end
			if item.bonus then
				desc = tr("bonus", math.floor(item.bonus * 100 + 0.5)) .. "\n" .. desc
			end
			if isPerk then
				desc = tr("perk_" .. item.id) .. "\n" .. desc
			end
			local btnText, btnColor, action
			if isPerk and owned then
				btnText, btnColor = tr("active"), Color3.fromRGB(60, 170, 90)
				action = function() end
			elseif equipped == item.id and owned then
				btnText, btnColor = tr("equipped"), Color3.fromRGB(60, 170, 90)
				action = function() end
			elseif owned then
				btnText, btnColor = tr("equip"), Color3.fromRGB(60, 140, 230)
				action = function()
					ActionRE:FireServer("EquipItem", { category = category, id = item.id })
				end
			elseif item.price then
				btnText, btnColor = tr("buy_coins", item.price), Color3.fromRGB(255, 140, 40)
				action = function()
					ActionRE:FireServer("BuyItem", { category = category, id = item.id })
				end
			elseif item.unlock == "vip" or string.sub(item.unlock or "", 1, 5) == "pass:" then
				local key = item.unlock == "vip" and "VIP" or string.sub(item.unlock, 6)
				btnText, btnColor = tr("get_robux"), Color3.fromRGB(0, 170, 110)
				action = function()
					promptPass(key)
				end
			else
				btnText, btnColor = tr("locked"), Color3.fromRGB(80, 70, 75)
				action = function()
					toast("🔒 " .. desc)
				end
			end
			card(i, tr("item_" .. category .. "_" .. item.id), desc, colors, btnText, btnColor, action, item.rarity)
		end
	else
		local order = 0
		for _, key in ipairs(Config.ShopPasses) do
			order += 1
			local owned = player:GetAttribute("Pass" .. key) == true
			card(order, tr("pass_" .. key), tr("pass_" .. key .. "_desc"), nil, owned and tr("owned") or tr("buy_robux"), owned and Color3.fromRGB(60, 170, 90) or Color3.fromRGB(0, 170, 110), function()
				if not owned then
					promptPass(key)
				end
			end)
		end
		for _, key in ipairs(Config.ShopProducts) do
			order += 1
			card(order, tr("prod_" .. key), tr("prod_" .. key .. "_desc"), nil, tr("buy_robux"), Color3.fromRGB(0, 170, 110), function()
				promptProduct(key)
			end)
		end
	end
end

local function setTab(tab)
	currentTab = tab
	for key, b in pairs(tabButtons) do
		b.BackgroundColor3 = key == tab and Color3.fromRGB(255, 120, 40) or Color3.fromRGB(90, 70, 80)
	end
	refreshShop()
end
setTab("trails")

shopBtn.Activated:Connect(function()
	shop.Visible = not shop.Visible
	refreshShop()
end)
closeBtn.Activated:Connect(function()
	shop.Visible = false
end)
for key, b in pairs(tabButtons) do
	b.Activated:Connect(function()
		setTab(key)
	end)
end

local function openShop(tab)
	shop.Visible = true
	setTab(tab)
end

-- ============ ОКНО ПЕРЕРОЖДЕНИЯ ============
local rebirthWin = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(400, 220),
	BackgroundColor3 = Color3.fromRGB(45, 25, 55),
	Visible = false,
	ZIndex = 8,
}, gui))
corner(rebirthWin, 18)
outline(rebirthWin, Color3.fromRGB(200, 90, 255), 3)
local rebirthText = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -32, 0, 130),
	Font = Enum.Font.GothamBold,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
	ZIndex = 9,
}, rebirthWin)
local yesBtn = button({ text = tr("yes_rebirth"), size = UDim2.new(0.5, -24, 0, 48), position = UDim2.new(0, 16, 1, -62), color = Color3.fromRGB(200, 60, 200) }, rebirthWin)
local noBtn = button({ text = tr("later"), size = UDim2.new(0.5, -24, 0, 48), position = UDim2.new(0.5, 8, 1, -62), color = Color3.fromRGB(90, 90, 100) }, rebirthWin)
yesBtn.ZIndex = 9
noBtn.ZIndex = 9

local function openRebirthWin()
	local reb = (player:GetAttribute("Rebirths") or 0) + 1
	rebirthText.Text = tr("rebirth_text", reb, string.format("%.1f", 1 + reb * Config.REBIRTH_BONUS), Config.REBIRTH_COINS * reb)
	rebirthWin.Visible = true
end
rebirthBtn.Activated:Connect(openRebirthWin)
yesBtn.Activated:Connect(function()
	rebirthWin.Visible = false
	ActionRE:FireServer("Rebirth")
end)
noBtn.Activated:Connect(function()
	rebirthWin.Visible = false
end)

-- ============ КНОПКИ ============
prevBtn.Activated:Connect(function()
	local st = player:GetAttribute("Stage") or 1
	if st > 1 then
		ActionRE:FireServer("Teleport", st - 1)
	end
end)
nextBtn.Activated:Connect(function()
	local st = player:GetAttribute("Stage") or 1
	local mx = player:GetAttribute("MaxStage") or 1
	if st < mx then
		ActionRE:FireServer("Teleport", st + 1)
	else
		toast(tr("beat_stage_first"))
	end
end)
skipBtn.Activated:Connect(function()
	promptProduct("SkipStage")
end)
shieldBtn.Activated:Connect(function()
	promptProduct("LavaShield")
end)
vipBtn.Activated:Connect(function()
	if player:GetAttribute("PassVIP") then
		openShop("skins") -- у VIP уже всё есть: открываем, чтобы надеть золотой скин
	elseif Config.GamePasses.VIP ~= 0 then
		promptPass("VIP")
	else
		openShop("robux")
	end
end)
respawnBtn.Activated:Connect(function()
	ActionRE:FireServer("Respawn")
end)
giftBtn.Activated:Connect(function()
	local nextGift = player:GetAttribute("NextGift") or 0
	if os.time() >= nextGift then
		ActionRE:FireServer("ClaimGift")
	else
		toast(tr("gift_soon"))
	end
end)

-- ============ ОБНОВЛЕНИЕ HUD ============
local lastZone = nil

local function refreshHud()
	local st = player:GetAttribute("Stage") or 1
	local mx = player:GetAttribute("MaxStage") or 1
	local inLobby = player:GetAttribute("InLobby") == true
	if inLobby then
		stageLabel.Text = tr("ui_in_lobby")
		zoneLabel.Text = tr("ui_in_lobby_sub")
		zoneLabel.TextColor3 = Color3.fromRGB(255, 220, 120)
		barFill.Size = UDim2.fromScale(math.clamp((mx - 1) / TOTAL, 0, 1), 1)
	elseif st >= FINISH then
		stageLabel.Text = tr("ui_finish")
		zoneLabel.Text = tr("ui_finish_sub", TOTAL)
		barFill.Size = UDim2.fromScale(1, 1)
	else
		stageLabel.Text = tr("ui_stage", st, TOTAL)
		local z = Config.ZoneOfStage(st)
		local zone = Config.Zones[z]
		zoneLabel.Text = zone.emoji .. " " .. tr("zone_" .. z)
		zoneLabel.TextColor3 = zone.color
		barFill.Size = UDim2.fromScale((st - 1) / TOTAL, 1)
		barFill.BackgroundColor3 = zone.color
	end
	-- стрелки работают только внутри текущего мира
	local w = Config.ZoneOfStage(math.min(st, TOTAL))
	local wFirst = (w - 1) * Config.STAGES_PER_ZONE + 1
	local wLast = math.min(w * Config.STAGES_PER_ZONE, TOTAL)
	prevBtn.Visible = not inLobby and st > wFirst
	nextBtn.Visible = not inLobby and st < mx and st < wLast
	lobbyBtn.Visible = not inLobby
	respawnBtn.Visible = not inLobby
	rebirthBtn.Visible = mx >= FINISH
	coinsLabel.Text = "💰 " .. (player:GetAttribute("Coins") or 0)
	ducksLabel.Text = "🦆 " .. (player:GetAttribute("Ducks") or 0) .. "/" .. Config.DUCK_COUNT
	local mult = player:GetAttribute("Multiplier") or 1
	local reb = player:GetAttribute("Rebirths") or 0
	multLabel.Text = "x" .. string.format("%.2g", mult) .. " 💰" .. (reb > 0 and ("  🔁" .. reb) or "")
	skipBtn.Visible = not inLobby and st < FINISH
	shieldBtn.Visible = not inLobby
	-- замки на порталах
	for _, lock in ipairs(CollectionService:GetTagged("PortalLock")) do
		local lw = lock:GetAttribute("World") or 1
		local open = mx >= (lw - 1) * Config.STAGES_PER_ZONE + 1
		lock.Transparency = open and 1 or 0.15
		local sg = lock:FindFirstChildOfClass("SurfaceGui")
		if sg then
			sg.Enabled = not open
		end
	end
	vipBtn.Text = player:GetAttribute("PassVIP") and tr("ui_vip_owned") or tr("ui_vip")
end

CollectionService:GetInstanceAddedSignal("PortalLock"):Connect(function()
	task.defer(refreshHud)
end)
for _, attr in ipairs({ "Stage", "MaxStage", "Coins", "Ducks", "Multiplier", "Rebirths", "PassVIP", "InLobby" }) do
	player:GetAttributeChangedSignal(attr):Connect(refreshHud)
end
for _, attr in ipairs({
	"Coins", "Trails", "Trail", "Skins", "Skin", "Pets", "Pet", "Auras", "Aura", "Perks", "Ducks", "Rebirths",
	"PassVIP", "PassSpeed", "PassSuperJump", "PassDoubleCoins", "PassSkinPack", "PassDragonPet",
}) do
	player:GetAttributeChangedSignal(attr):Connect(refreshShop)
end
refreshHud()

-- таймер подарка
task.spawn(function()
	while true do
		local nextGift = player:GetAttribute("NextGift")
		if nextGift then
			local leftSec = nextGift - os.time()
			if leftSec <= 0 then
				giftBtn.Text = tr("ui_gift_ready")
				giftBtn.BackgroundColor3 = Color3.fromRGB(255, 180, 30)
			else
				giftBtn.Text = string.format("🎁 %d:%02d", math.floor(leftSec / 60), leftSec % 60)
				giftBtn.BackgroundColor3 = Color3.fromRGB(150, 90, 200)
			end
		end
		task.wait(0.5)
	end
end)

-- ============ ЭФФЕКТЫ ============
local function burst(count, colors)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local att = new("Attachment", {}, root)
	local kps = {}
	for i, c in ipairs(colors) do
		table.insert(kps, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	if #kps == 1 then
		table.insert(kps, ColorSequenceKeypoint.new(1, colors[1]))
	end
	local em = new("ParticleEmitter", {
		Color = ColorSequence.new(kps),
		LightEmission = 0.6,
		Size = NumberSequence.new(0.5, 0.1),
		Speed = NumberRange.new(15, 30),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -35, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Rate = 0,
	}, att)
	em:Emit(count)
	task.delay(3, function()
		att:Destroy()
	end)
end

local CONFETTI = { Color3.fromRGB(255, 70, 70), Color3.fromRGB(255, 210, 50), Color3.fromRGB(70, 220, 100), Color3.fromRGB(70, 150, 255), Color3.fromRGB(200, 90, 255) }

EffectRE.OnClientEvent:Connect(function(kind, arg)
	if kind == "checkpoint" then
		burst(25, { Color3.fromRGB(255, 200, 60), Color3.fromRGB(255, 120, 40) })
	elseif kind == "zone" then
		local zone = Config.Zones[arg]
		if zone then
			showBanner(tr("zone_banner", arg, zone.emoji, "@zone_" .. arg), zone.color)
		end
		burst(60, CONFETTI)
	elseif kind == "finish" then
		showBanner(tr("victory"), GOLD)
		burst(150, CONFETTI)
	elseif kind == "duck" then
		burst(40, { Color3.fromRGB(255, 230, 60), Color3.new(1, 1, 1) })
	end
end)

-- ============ ВОЛНА ЛАВЫ / ВОДА ============
local function inZone4()
	local st = player:GetAttribute("Stage") or 1
	return not player:GetAttribute("InLobby") and Config.ZoneOfStage(math.min(st, TOTAL)) == 4 and st <= TOTAL
end

local function refreshWarn()
	local state = workspace:GetAttribute("WaveState")
	if workspace:GetAttribute("LavaIsWater") then
		local leftSec = (workspace:GetAttribute("WaterUntil") or 0) - os.time()
		warnLabel.Visible = true
		warnLabel.TextColor3 = Color3.fromRGB(90, 190, 255)
		warnLabel.Text = tr("water_warn", math.max(leftSec, 0))
		return
	end
	warnLabel.TextColor3 = Color3.fromRGB(255, 80, 40)
	if inZone4() and (state == "warn" or state == "up") then
		warnLabel.Visible = true
		warnLabel.Text = state == "warn" and tr("wave_warn") or tr("wave_up")
	else
		warnLabel.Visible = false
	end
end
workspace:GetAttributeChangedSignal("WaveState"):Connect(refreshWarn)
workspace:GetAttributeChangedSignal("LavaIsWater"):Connect(refreshWarn)
task.spawn(function()
	while true do
		task.wait(1)
		if workspace:GetAttribute("LavaIsWater") then
			refreshWarn()
		end
	end
end)

-- ============ МОНЕТЫ: ВРАЩЕНИЕ И СКРЫТИЕ ============
local coins = {}
local coinById = {}

local function registerCoin(c)
	if coins[c] then
		return
	end
	coins[c] = c.CFrame
	local id = c:GetAttribute("CoinId")
	if id then
		coinById[id] = c
	end
end
for _, c in ipairs(CollectionService:GetTagged("Coin")) do
	registerCoin(c)
end
CollectionService:GetInstanceAddedSignal("Coin"):Connect(registerCoin)

RunService.RenderStepped:Connect(function()
	local a = os.clock() * 2
	local rot = CFrame.Angles(0, a, 0)
	local bob = math.sin(a * 1.5) * 0.3
	for c, base in pairs(coins) do
		if c.Parent then
			c.CFrame = (base + Vector3.new(0, bob, 0)) * rot
		end
	end
end)

CoinRE.OnClientEvent:Connect(function(id)
	local c = coinById[id]
	if c then
		c.Transparency = 1
		task.delay(Config.COIN_RESPAWN, function()
			c.Transparency = 0
		end)
	end
end)

-- ============ УТКИ: СКРЫВАЕМ НАЙДЕННЫХ ============
local function refreshDucks()
	local found = csvSet(player:GetAttribute("DucksList"))
	for _, body in ipairs(CollectionService:GetTagged("Duck")) do
		local id = tostring(body:GetAttribute("DuckId"))
		local model = body.Parent
		if found[id] and model then
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					p.Transparency = 0.85
				elseif p:IsA("PointLight") then
					p.Enabled = false
				end
			end
		end
	end
end
player:GetAttributeChangedSignal("DucksList"):Connect(refreshDucks)
CollectionService:GetInstanceAddedSignal("Duck"):Connect(refreshDucks)
refreshDucks()

-- ============ VIP-ДВЕРЬ ============
local function refreshVipDoor()
	local vip = player:GetAttribute("PassVIP") == true
	for _, door in ipairs(CollectionService:GetTagged("VipDoor")) do
		door.CanCollide = not vip
		door.Transparency = vip and 0.75 or 0.35
	end
end
player:GetAttributeChangedSignal("PassVIP"):Connect(refreshVipDoor)
CollectionService:GetInstanceAddedSignal("VipDoor"):Connect(refreshVipDoor)
refreshVipDoor()

-- ============ БАТУТЫ ============
local lastBounce = 0
local function registerBounce(pad)
	pad.Touched:Connect(function(hit)
		local char = player.Character
		if not char or not hit:IsDescendantOf(char) then
			return
		end
		if os.clock() - lastBounce < 0.4 then
			return
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not hum or not root or hum.Health <= 0 then
			return
		end
		lastBounce = os.clock()
		local launch = pad:GetAttribute("Launch") or Vector3.new(0, 95, 0)
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		root.AssemblyLinearVelocity = launch
	end)
end
for _, pad in ipairs(CollectionService:GetTagged("Bounce")) do
	registerBounce(pad)
end
CollectionService:GetInstanceAddedSignal("Bounce"):Connect(registerBounce)

-- ============ МАСШТАБ ПОД ЭКРАН (телефоны) ============
local function rescale()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local vp = cam.ViewportSize
	local k = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.1)
	for _, s in ipairs(scales) do
		s.Scale = k
	end
end
rescale()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

-- ============ ПИТОМЦЫ ЛЕТАЮТ ЗА ХОЗЯЕВАМИ ============
local petFolder = workspace:WaitForChild("LavaPets", 30)
local petState = {}
local petFlaps = {}
RunService.RenderStepped:Connect(function(dt)
	if not petFolder then
		return
	end
	local t = os.clock()
	for _, model in ipairs(petFolder:GetChildren()) do
		local owner = Players:GetPlayerByUserId(model:GetAttribute("OwnerId") or 0)
		local char = owner and owner.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and model.PrimaryPart then
			local target = root.CFrame * CFrame.new(2.6, 1.2 + math.sin(t * 3) * 0.4, 2.2)
			local cur = petState[model] or target
			cur = cur:Lerp(target, math.clamp(dt * 8, 0, 1))
			petState[model] = cur
			model:PivotTo(cur)
			-- крылья, хвосты и огоньки машут
			local flaps = petFlaps[model]
			if not flaps then
				flaps = {}
				for _, d in ipairs(model:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("Flap") then
						table.insert(flaps, d)
					end
				end
				petFlaps[model] = flaps
			end
			for _, part in ipairs(flaps) do
				local hinge = part:GetAttribute("Hinge")
				local fromHinge = part:GetAttribute("FromHinge")
				if hinge and fromHinge then
					local angle = part:GetAttribute("Flap") * math.sin(t * (part:GetAttribute("FlapSpeed") or 8))
					local axis = part:GetAttribute("FlapAxis")
					local rot
					if axis == "x" then
						rot = CFrame.Angles(angle, 0, 0)
					elseif axis == "y" then
						rot = CFrame.Angles(0, angle, 0)
					else
						rot = CFrame.Angles(0, 0, angle)
					end
					part.CFrame = cur * hinge * rot * fromHinge
				end
			end
		end
	end
	for model in pairs(petState) do
		if not model.Parent then
			petState[model] = nil
			petFlaps[model] = nil
		end
	end
end)

-- ============ ЩИТ: ТАЙМЕР 60 → 0 ============
task.spawn(function()
	local lastShown = -1
	while true do
		local leftSec = math.max((player:GetAttribute("ShieldUntil") or 0) - os.time(), 0)
		shieldCircle.Visible = leftSec > 0
		if leftSec > 0 and leftSec ~= lastShown then
			lastShown = leftSec
			shieldNum.Text = tostring(leftSec)
			-- последние 10 секунд — красный
			local low = leftSec <= 10
			shieldRing.Color = low and Color3.fromRGB(255, 80, 60) or Color3.fromRGB(90, 190, 255)
			shieldNum.TextColor3 = low and Color3.fromRGB(255, 120, 100) or Color3.new(1, 1, 1)
			-- «тук» каждую секунду
			shieldRing.Thickness = 7
			TweenService:Create(shieldRing, TweenInfo.new(0.4), { Thickness = 4 }):Play()
		end
		task.wait(0.2)
	end
end)

-- ============ «СЛОЖНО? ПРОПУСТИ ЭТАП» ПОСЛЕ 3 СМЕРТЕЙ ============
local helpWin = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.55),
	Size = UDim2.fromOffset(380, 230),
	BackgroundColor3 = Color3.fromRGB(45, 28, 30),
	Visible = false,
	ZIndex = 8,
}, gui))
corner(helpWin, 18)
outline(helpWin, Color3.fromRGB(255, 140, 50), 3)
local helpTitle = new("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(12, 10),
	Size = UDim2.new(1, -24, 0, 60),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = tr("help_title"),
	ZIndex = 9,
}, helpWin)
textStroke(helpTitle)
local helpSkip = button({ text = tr("help_skip"), size = UDim2.new(1, -24, 0, 44), position = UDim2.fromOffset(12, 78), color = Color3.fromRGB(230, 140, 30) }, helpWin)
local helpShield = button({ text = tr("help_shield"), size = UDim2.new(0.5, -18, 0, 44), position = UDim2.fromOffset(12, 130), color = Color3.fromRGB(40, 130, 230) }, helpWin)
local helpJump = button({ text = tr("help_jump"), size = UDim2.new(0.5, -18, 0, 44), position = UDim2.new(0.5, 6, 0, 130), color = Color3.fromRGB(60, 170, 90) }, helpWin)
local helpClose = button({ text = tr("help_close"), size = UDim2.new(1, -24, 0, 36), position = UDim2.new(0, 12, 1, -46), color = Color3.fromRGB(90, 90, 100) }, helpWin)
for _, b in ipairs({ helpSkip, helpShield, helpJump, helpClose }) do
	b.ZIndex = 9
end
helpSkip.Activated:Connect(function()
	helpWin.Visible = false
	promptProduct("SkipStage")
end)
helpShield.Activated:Connect(function()
	helpWin.Visible = false
	promptProduct("LavaShield")
end)
helpJump.Activated:Connect(function()
	helpWin.Visible = false
	promptPass("SuperJump")
end)
helpClose.Activated:Connect(function()
	helpWin.Visible = false
end)

local deathsOnStage = 0
local deathStage = 0
local function watchDeaths(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then
		return
	end
	hum.Died:Connect(function()
		local st = player:GetAttribute("Stage") or 1
		if st ~= deathStage then
			deathStage = st
			deathsOnStage = 0
		end
		deathsOnStage += 1
		if deathsOnStage % 3 == 0 and st < FINISH then
			task.delay(1.2, function()
				helpJump.Visible = player:GetAttribute("PassSuperJump") ~= true
				helpWin.Visible = true
			end)
		end
	end)
end
if player.Character then
	task.spawn(watchDeaths, player.Character)
end
player.CharacterAdded:Connect(watchDeaths)

-- ============ ПОДНИМАЮЩАЯСЯ ЛАВА ============
-- У каждого игрока своя: после чекпоинта лава ползёт вверх. Стоишь — догонит.
local lavaMeter = counter("🔥", 5)
lavaMeter.Visible = false
local rising = { active = false, y = -1e6, startPos = nil }
local lavaSheet, lavaGlow
if Config.RISING_LAVA then
	lavaSheet = new("Part", {
		Name = "RisingLava",
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Size = Vector3.new(500, 2, 500),
		Material = Enum.Material.CrackedLava,
		Color = Color3.fromRGB(255, 100, 10),
		CFrame = CFrame.new(0, -500, 0),
	}, workspace)
	lavaGlow = new("Part", {
		Name = "RisingLavaGlow",
		Anchored = true,
		CanCollide = false,
		CanTouch = false,
		CanQuery = false,
		CastShadow = false,
		Size = Vector3.new(500, 0.3, 500),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 150, 30),
		Transparency = 0.5,
		CFrame = CFrame.new(0, -500, 0),
	}, workspace)
end

local function lobbyCenter()
	local m = workspace:FindFirstChild("LavaMap")
	local lobby = m and m:FindFirstChild("Lobby")
	local f = lobby and lobby:FindFirstChild("LobbyFloor")
	return f and f.Position
end

local function resetRising()
	rising.active = false
	rising.startPos = nil
	rising.y = -1e6
end
player:GetAttributeChangedSignal("Stage"):Connect(resetRising)
player:GetAttributeChangedSignal("InLobby"):Connect(resetRising)
player.CharacterAdded:Connect(resetRising)

RunService.Heartbeat:Connect(function(dt)
	if not lavaSheet then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local st = player:GetAttribute("Stage") or 1
	local show = false
	local inLobbyNow = player:GetAttribute("InLobby") == true
	local worldLava = Config.WorldRisingLava[Config.ZoneOfStage(math.min(st, TOTAL))] ~= false
	local eruptingNow = workspace:GetAttribute("Event") == "eruption"
	if root and hum and hum.Health > 0 and st < FINISH and not inLobbyNow and (worldLava or eruptingNow) then
		local pos = root.Position
		if not rising.startPos then
			rising.startPos = pos
			rising.y = pos.Y - 3 - Config.RISING_LAVA_START
		end
		if not rising.active then
			local moved = Vector3.new(pos.X - rising.startPos.X, 0, pos.Z - rising.startPos.Z).Magnitude
			local lc = lobbyCenter()
			local inLobby = st == 1 and lc ~= nil and Vector3.new(pos.X - lc.X, 0, pos.Z - lc.Z).Magnitude < 74
			local erupting = workspace:GetAttribute("Event") == "eruption"
			if (moved > 14 or erupting) and not inLobby then
				rising.active = true
				toast(tr("lava_rising"), Color3.fromRGB(255, 120, 40))
			end
		end
		if rising.active then
			show = true
			local water = workspace:GetAttribute("LavaIsWater") == true
			if not water then
				local k = (st - 1) / TOTAL
				local mult = workspace:GetAttribute("Event") == "eruption" and Config.ERUPTION_LAVA_MULT or 1
				rising.y += (Config.RISING_LAVA_SPEED + (Config.RISING_LAVA_SPEED_MAX - Config.RISING_LAVA_SPEED) * k) * dt * mult
			end
			local feet = pos.Y - 3
			if (player:GetAttribute("ShieldUntil") or 0) > os.time() then
				rising.y = math.min(rising.y, feet - 4) -- 🛡 щит не пускает лаву выше ног
			elseif feet < rising.y and not water then
				hum.Health = 0
			end
			local gap = math.max(math.floor(feet - rising.y), 0)
			lavaMeter.Text = tr("lava_meter", gap)
			lavaMeter.TextColor3 = gap < 8 and Color3.fromRGB(255, 90, 60) or Color3.new(1, 1, 1)
			lavaSheet.CFrame = CFrame.new(pos.X, rising.y - 1, pos.Z)
			lavaGlow.CFrame = CFrame.new(pos.X, rising.y + 0.1, pos.Z)
			lavaSheet.Color = water and Color3.fromRGB(40, 140, 255) or Color3.fromRGB(255, 100, 10)
			lavaGlow.Color = water and Color3.fromRGB(120, 200, 255) or Color3.fromRGB(255, 150, 30)
		end
	end
	lavaMeter.Visible = show
	if not show then
		lavaSheet.CFrame = CFrame.new(0, -500, 0)
		lavaGlow.CFrame = CFrame.new(0, -500, 0)
	end
end)

-- ============ КРУТЯЩИЕСЯ ОБЪЕКТЫ И ФЛАГИ ============
local rotors = {}
local function addRotor(p)
	if p:GetAttribute("RotorCenter") then
		table.insert(rotors, p)
	end
end
for _, p in ipairs(CollectionService:GetTagged("Rotor")) do
	addRotor(p)
end
CollectionService:GetInstanceAddedSignal("Rotor"):Connect(addRotor)

local flags = {}
local function scanFlags()
	local m = workspace:FindFirstChild("LavaMap")
	if not m then
		return
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("Wave") then
			table.insert(flags, { part = d, base = d.CFrame, phase = math.random() * 6 })
		end
	end
end
task.spawn(function()
	while not workspace:GetAttribute("MapReady") do
		task.wait(0.5)
	end
	task.wait(1)
	scanFlags()
end)

RunService.RenderStepped:Connect(function()
	local t = os.clock()
	local camPos = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or Vector3.zero
	for _, p in ipairs(rotors) do
		-- далёкие объекты не крутим — экономим кадры
		if (p.Position - camPos).Magnitude < 450 then
			local center = p:GetAttribute("RotorCenter")
			local offset = p:GetAttribute("RotorOffset")
			local a = t * (p:GetAttribute("RotorSpeed") or 0.5)
			local axis = p:GetAttribute("RotorAxis")
			local rot = axis == "y" and CFrame.Angles(0, a, 0) or (axis == "x" and CFrame.Angles(a, 0, 0) or CFrame.Angles(0, 0, a))
			local cf = center * rot * offset
			local hang = p:GetAttribute("RotorHang")
			if hang then
				p.CFrame = CFrame.new(cf.Position - Vector3.new(0, hang, 0)) * center.Rotation
			else
				p.CFrame = cf
			end
		end
	end
	for _, f in ipairs(flags) do
		f.part.CFrame = f.base * CFrame.Angles(0, math.sin(t * 3 + f.phase) * 0.25, 0)
	end
end)

-- ============ ОСВЕЩЕНИЕ КАЖДОГО МИРА ============
local Lighting = game:GetService("Lighting")
local LIGHT = {
	{ ClockTime = 14.5, Brightness = 2.6, Ambient = Color3.fromRGB(130, 120, 140), Outdoor = Color3.fromRGB(170, 160, 180), Atmo = Color3.fromRGB(200, 225, 255), Density = 0.22, Haze = 0.4, Tint = Color3.fromRGB(255, 252, 245), Sat = 0.3 },
	{ ClockTime = 13, Brightness = 2.8, Ambient = Color3.fromRGB(160, 130, 150), Outdoor = Color3.fromRGB(200, 170, 190), Atmo = Color3.fromRGB(255, 205, 235), Density = 0.25, Haze = 0.8, Tint = Color3.fromRGB(255, 240, 248), Sat = 0.4 },
	{ ClockTime = 21.5, Brightness = 1.2, Ambient = Color3.fromRGB(70, 60, 120), Outdoor = Color3.fromRGB(90, 80, 150), Atmo = Color3.fromRGB(90, 70, 170), Density = 0.42, Haze = 2, Tint = Color3.fromRGB(225, 225, 255), Sat = 0.35 },
	{ ClockTime = 17.6, Brightness = 2, Ambient = Color3.fromRGB(120, 80, 70), Outdoor = Color3.fromRGB(170, 110, 90), Atmo = Color3.fromRGB(255, 140, 90), Density = 0.35, Haze = 1.6, Tint = Color3.fromRGB(255, 232, 215), Sat = 0.25 },
	{ ClockTime = 12, Brightness = 3, Ambient = Color3.fromRGB(150, 150, 170), Outdoor = Color3.fromRGB(190, 195, 215), Atmo = Color3.fromRGB(215, 235, 255), Density = 0.15, Haze = 0.2, Tint = Color3.fromRGB(255, 255, 250), Sat = 0.25 },
}
local NIGHT = { ClockTime = 0.5, Brightness = 0.4, Ambient = Color3.fromRGB(25, 25, 45), Outdoor = Color3.fromRGB(35, 35, 70), Atmo = Color3.fromRGB(30, 30, 70), Density = 0.4, Haze = 1.5, Tint = Color3.fromRGB(190, 200, 255), Sat = 0.1 }

local function applyLight(prof, extraTint)
	local info = TweenInfo.new(2.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, { ClockTime = prof.ClockTime, Brightness = prof.Brightness, Ambient = prof.Ambient, OutdoorAmbient = prof.Outdoor }):Play()
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		TweenService:Create(atmo, info, { Color = prof.Atmo, Density = prof.Density, Haze = prof.Haze }):Play()
	end
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc then
		TweenService:Create(cc, info, { TintColor = extraTint or prof.Tint, Saturation = prof.Sat }):Play()
	end
end

local currentLightKey = nil
local function refreshLighting()
	local ev = workspace:GetAttribute("Event")
	local st = player:GetAttribute("Stage") or 1
	local zone = Config.ZoneOfStage(math.min(st, TOTAL))
	if st >= FINISH then
		zone = 5
	end
	if player:GetAttribute("InLobby") then
		zone = 1
	end
	local key = tostring(ev) .. zone
	if key == currentLightKey then
		return
	end
	currentLightKey = key
	if ev == "night" then
		applyLight(NIGHT)
	elseif ev == "golden" then
		applyLight(LIGHT[zone], Color3.fromRGB(255, 235, 170))
	elseif ev == "eruption" then
		applyLight(LIGHT[4], Color3.fromRGB(255, 200, 180))
	elseif ev == "icestorm" then
		applyLight(LIGHT[zone], Color3.fromRGB(215, 235, 255))
	else
		applyLight(LIGHT[zone])
	end
end
player:GetAttributeChangedSignal("Stage"):Connect(refreshLighting)
player:GetAttributeChangedSignal("InLobby"):Connect(refreshLighting)
workspace:GetAttributeChangedSignal("Event"):Connect(refreshLighting)
task.delay(1, refreshLighting)

-- ============ СОБЫТИЯ СЕРВЕРА: БАННЕР С ОТСЧЁТОМ ============
local EVENT_COLORS = {
	eruption = Color3.fromRGB(255, 80, 30),
	night = Color3.fromRGB(80, 90, 200),
	meteors = Color3.fromRGB(255, 120, 40),
	icestorm = Color3.fromRGB(90, 190, 255),
	golden = Color3.fromRGB(255, 200, 40),
}
local eventBar = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 158),
	Size = UDim2.fromOffset(460, 44),
	BackgroundColor3 = Color3.fromRGB(255, 80, 30),
	Visible = false,
}, gui))
corner(eventBar, 12)
outline(eventBar, Color3.new(0, 0, 0), 3)
local eventText = new("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(1, -16, 1, -8),
	Position = UDim2.fromOffset(8, 4),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextColor3 = Color3.new(1, 1, 1),
	Text = "",
}, eventBar)
textStroke(eventText)

-- ночью у игрока свой фонарик
local nightLight
local function ensureNightLight(on)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if on and root then
		if not nightLight or nightLight.Parent ~= root then
			nightLight = new("PointLight", { Range = 28, Brightness = 2, Color = Color3.fromRGB(255, 230, 180), Shadows = true }, root)
		end
	elseif nightLight then
		nightLight:Destroy()
		nightLight = nil
	end
end

-- снег для ледяного шторма
local snowPart = new("Part", { Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Transparency = 1, Size = Vector3.new(80, 1, 80), CFrame = CFrame.new(0, -500, 0) }, workspace)
local snow = new("ParticleEmitter", {
	Color = ColorSequence.new(Color3.new(1, 1, 1)),
	Size = NumberSequence.new(0.35),
	Transparency = NumberSequence.new(0.1, 0.6),
	Speed = NumberRange.new(10, 18),
	Lifetime = NumberRange.new(2, 3),
	Rate = 0,
	SpreadAngle = Vector2.new(20, 20),
	EmissionDirection = Enum.NormalId.Bottom,
	Acceleration = Vector3.new(12, 0, 4),
}, snowPart)

local lastGust = 0
RunService.Heartbeat:Connect(function()
	local ev = workspace:GetAttribute("Event")
	local ends = workspace:GetAttribute("EventEnds")
	if ev and ends then
		local left = math.max(0, math.ceil(ends - workspace:GetServerTimeNow()))
		eventBar.Visible = true
		eventBar.BackgroundColor3 = EVENT_COLORS[ev] or Color3.fromRGB(255, 120, 40)
		eventText.Text = tr("ev_timer", tr("ev_" .. ev), left)
	else
		eventBar.Visible = false
	end
	ensureNightLight(ev == "night")
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if ev == "icestorm" and root then
		snowPart.CFrame = CFrame.new(root.Position + Vector3.new(0, 30, 0))
		snow.Rate = 220
		-- порывы ветра
		if os.clock() - lastGust > 2.6 and hum and hum.Health > 0 and hum.FloorMaterial ~= Enum.Material.Air then
			lastGust = os.clock()
			local a = math.random() * math.pi * 2
			root:ApplyImpulse(Vector3.new(math.cos(a), 0.15, math.sin(a)) * root.AssemblyMass * 32)
		end
	else
		snow.Rate = 0
	end
end)

-- ============ ТАЙМЕР ЗАБЕГА ============
local timerLabel = counter("⏱ 00:00", 6)
timerLabel.Visible = false
local function fmtTime(t)
	local m = math.floor(t / 60)
	return string.format("%02d:%05.2f", m, t - m * 60)
end
RunService.RenderStepped:Connect(function()
	local start = player:GetAttribute("RunStart")
	local final = player:GetAttribute("RunTime")
	if start then
		timerLabel.Visible = true
		timerLabel.Text = tr("ui_timer", fmtTime(workspace:GetServerTimeNow() - start))
		timerLabel.TextColor3 = player:GetAttribute("RunValid") == false and Color3.fromRGB(170, 170, 170) or Color3.new(1, 1, 1)
	elseif final then
		timerLabel.Visible = true
		timerLabel.Text = "🏁 " .. fmtTime(final)
		timerLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
	else
		timerLabel.Visible = false
	end
end)

-- ============ ЗАДАНИЯ ДНЯ ============
local HttpService = game:GetService("HttpService")
local tasksBtn = button({ text = tr("ui_tasks"), color = Color3.fromRGB(40, 160, 200), order = 3 }, left)
local tasksWin = scaled(new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(460, 330),
	BackgroundColor3 = Color3.fromRGB(25, 40, 60),
	Visible = false,
	ZIndex = 8,
}, gui))
corner(tasksWin, 18)
outline(tasksWin, Color3.fromRGB(90, 200, 255), 3)
local tTitle = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -80, 0, 40), Font = Enum.Font.GothamBlack, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD, Text = tr("tasks_title"), ZIndex = 9 }, tasksWin)
textStroke(tTitle)
local tClose = button({ text = "✕", size = UDim2.fromOffset(40, 40), position = UDim2.new(1, -52, 0, 10), color = Color3.fromRGB(200, 50, 50) }, tasksWin)
tClose.ZIndex = 9
new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(0, 16, 1, -34), Size = UDim2.new(1, -32, 0, 24), Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(180, 210, 240), Text = tr("tasks_hint"), ZIndex = 9 }, tasksWin)
local taskRows = {}
for i = 1, 3 do
	local row = new("Frame", { Position = UDim2.fromOffset(16, 58 + (i - 1) * 80), Size = UDim2.new(1, -32, 0, 70), BackgroundColor3 = Color3.fromRGB(40, 60, 90), ZIndex = 9 }, tasksWin)
	corner(row, 12)
	local name = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -120, 0, 28), Font = Enum.Font.GothamBold, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 10 }, row)
	local reward = new("TextLabel", { BackgroundTransparency = 1, Position = UDim2.new(1, -108, 0, 6), Size = UDim2.fromOffset(96, 28), Font = Enum.Font.GothamBlack, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = GOLD, Text = "", ZIndex = 10 }, row)
	local barBg = new("Frame", { Position = UDim2.fromOffset(12, 42), Size = UDim2.new(1, -24, 0, 16), BackgroundColor3 = Color3.fromRGB(20, 30, 45), ZIndex = 10 }, row)
	corner(barBg, 8)
	local bar = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(90, 220, 120), ZIndex = 11 }, barBg)
	corner(bar, 8)
	local prog = new("TextLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 12 }, barBg)
	taskRows[i] = { row = row, name = name, reward = reward, bar = bar, prog = prog }
end

local function challengeText(c)
	return tr("ch_" .. c.kind, c.goal)
end

local function refreshTasks()
	local raw = player:GetAttribute("Challenges")
	local ok, list = pcall(function()
		return HttpService:JSONDecode(raw or "[]")
	end)
	if not ok or type(list) ~= "table" then
		list = {}
	end
	local doneCount = 0
	for i = 1, 3 do
		local c = list[i]
		local r = taskRows[i]
		r.row.Visible = c ~= nil
		if c then
			r.name.Text = challengeText(c)
			r.reward.Text = "+" .. c.reward .. " 💰"
			r.bar.Size = UDim2.fromScale(math.clamp(c.progress / c.goal, 0, 1), 1)
			r.prog.Text = c.done and tr("task_done") or (c.progress .. " / " .. c.goal)
			r.row.BackgroundColor3 = c.done and Color3.fromRGB(40, 100, 60) or Color3.fromRGB(40, 60, 90)
			if c.done then
				doneCount += 1
			end
		end
	end
	tasksBtn.Text = tr("ui_tasks") .. " " .. doneCount .. "/" .. #list
	-- табло в лобби
	for _, lbl in ipairs(CollectionService:GetTagged("ChallengeRow")) do
		local idx = tonumber(string.match(lbl.Name, "%d+"))
		local c = idx and list[idx]
		if c then
			lbl.Text = (c.done and "✅ " or "⬜ ") .. challengeText(c) .. "  (" .. c.progress .. "/" .. c.goal .. ")  +" .. c.reward .. "💰"
		end
	end
end
player:GetAttributeChangedSignal("Challenges"):Connect(refreshTasks)
CollectionService:GetInstanceAddedSignal("ChallengeRow"):Connect(refreshTasks)
refreshTasks()
tasksBtn.Activated:Connect(function()
	tasksWin.Visible = not tasksWin.Visible
end)
tClose.Activated:Connect(function()
	tasksWin.Visible = false
end)

-- ============ КНОПКИ-ПОДСКАЗКИ В ЛОББИ (ProximityPrompt) ============
local ProximityPromptService = game:GetService("ProximityPromptService")
local function translatePrompt(pp)
	local a, o = pp:GetAttribute("ActionKey"), pp:GetAttribute("ObjectKey")
	if a then
		pp.ActionText = tr(a)
	end
	if o then
		pp.ObjectText = tr(o)
	end
end
for _, pp in ipairs(CollectionService:GetTagged("LocPrompt")) do
	translatePrompt(pp)
end
CollectionService:GetInstanceAddedSignal("LocPrompt"):Connect(translatePrompt)
ProximityPromptService.PromptTriggered:Connect(function(pp)
	local shopTab = pp:GetAttribute("OpenShop")
	if shopTab then
		openShop(shopTab)
	elseif pp:GetAttribute("OpenTasks") then
		tasksWin.Visible = true
	elseif pp:GetAttribute("OpenRebirth") then
		if (player:GetAttribute("MaxStage") or 1) >= FINISH then
			openRebirthWin()
		else
			toast(tr("n_finish_first"))
		end
	elseif pp:GetAttribute("BuyVip") then
		if player:GetAttribute("PassVIP") then
			openShop("skins")
		else
			promptPass("VIP")
		end
	end
end)

-- ============ СУНДУКИ ДНЯ: прячем найденные ============
local function refreshDailyChests()
	local found = csvSet(player:GetAttribute("DailyFound"))
	for _, base in ipairs(CollectionService:GetTagged("DailyChest")) do
		local model = base.Parent
		local isFound = found[base:GetAttribute("ChestId") or ""] == true
		if model then
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					local orig = p:GetAttribute("OrigT")
					if orig == nil then
						orig = p.Transparency
						p:SetAttribute("OrigT", orig)
					end
					p.Transparency = isFound and 1 or orig
				elseif p:IsA("Sparkles") then
					p.Enabled = not isFound
				end
			end
		end
	end
end
player:GetAttributeChangedSignal("DailyFound"):Connect(refreshDailyChests)
CollectionService:GetInstanceAddedSignal("DailyChest"):Connect(function()
	task.wait(0.5)
	refreshDailyChests()
end)
task.delay(2, refreshDailyChests)

-- ============ ПРИВИЛЕГИЯ «ДВОЙНОЙ ПРЫЖОК» ============
local UserInputService = game:GetService("UserInputService")
local doubleUsed = false
local function hasDoubleJump()
	return csvSet(player:GetAttribute("Perks")).doublejump == true
end
UserInputService.JumpRequest:Connect(function()
	if not hasDoubleJump() then
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or not root or hum.Health <= 0 then
		return
	end
	local state = hum:GetState()
	local inAir = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if inAir and not doubleUsed then
		doubleUsed = true
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(v.X, 50, v.Z)
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		burst(12, { Color3.new(1, 1, 1), Color3.fromRGB(150, 220, 255) })
	end
end)
local function watchLanding(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum then
		hum.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				doubleUsed = false
			end
		end)
	end
end
if player.Character then
	task.spawn(watchLanding, player.Character)
end
player.CharacterAdded:Connect(watchLanding)

-- ============ ПЕРЕВОД ТАБЛИЧЕК НА КАРТЕ ============
local function translateLabel(lbl)
	local key = lbl:GetAttribute("TextKey")
	if not key then
		return
	end
	local argStr = lbl:GetAttribute("TextArgs")
	local args = {}
	if argStr then
		for a in string.gmatch(argStr, "[^|]+") do
			table.insert(args, a)
		end
	end
	lbl.Text = Text.Format(LANG, key, args)
end
for _, lbl in ipairs(CollectionService:GetTagged("LocText")) do
	translateLabel(lbl)
end
CollectionService:GetInstanceAddedSignal("LocText"):Connect(translateLabel)

-- приветствие
task.delay(2, function()
	showBanner(tr("welcome"), Color3.fromRGB(255, 140, 50))
end)
