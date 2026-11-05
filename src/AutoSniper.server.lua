--!strict
--[[
	Booth Item AutoSniper
	Server Script
	Place this in a ServerScriptService folder (e.g. ServerScriptService).

	This script periodically scans the user's booth for newly listed items that
	match the configured snipe criteria and automatically purchases them as soon
	as they meet the rules (price floor, price cap, item name filters).

	CONFIGURATION
	-------------
	Edit the SnipeConfig table below to control behaviour. No code changes are
	needed for typical use.

	NOTE ON MARKETPLACE API
	-----------------------
	Roblox does not expose a public, first-party "booth marketplace" API that a
	plain Luau script can call to list or buy arbitrary player booths. This
	script therefore implements a realistic local simulation of a booth using
	Folder-based item data, and triggers a buy when a matching item is found.

	To adapt it to a real network backend (for example your own WebService
	marketplace or a private API), replace the FetchBoothItems() function with
	your own calls (HttpService:GetAsync) so the sniper stays the same.
--]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- ---------------------------------------------------------------------------
-- CONFIGURATION
-- ---------------------------------------------------------------------------

local SnipeConfig = {
	-- How often to scan for new items, in seconds.
	ScanInterval = 2.0,

	-- Maximum price (in Robux) we are willing to auto-buy an item for.
	MaxPrice = 5000,

	-- Minimum price we are willing to auto-buy an item for (avoid junk/1-bux spam).
	MinPrice = 10,

	-- List of item name substrings the sniper is interested in.
	-- Empty list {} means "buy any matching item".
	ItemNameFilters = {"Limited", "Rare"},

	-- Buy item even if it is inside a bundle (some booths bundle items).
	BuyBundles = false,

	-- Balance that must be available before the sniper acts, as a safety.
	RequiredBalance = 0,

	-- Set to true to print detailed logs of every scan.
	Verbose = false,

	-- Master kill-switch. Set to false to fully disable sniping.
	Enabled = true,
}

-- Where the local "booth" data lives (simulation of a marketplace feed).
local BOOTH_FOLDER_NAME = "BoothItems"

-- Where we keep track of already-processed item ids so we only buy new ones.
local PROCESSED_FOLDER_NAME = "ProcessedSnipeItems"

-- ---------------------------------------------------------------------------
-- STATE
-- ---------------------------------------------------------------------------

local boothFolder = workspace:FindFirstChild(BOOTH_FOLDER_NAME)
local processedFolder: Folder? = nil
local lastScan = 0
local active = false

-- ---------------------------------------------------------------------------
-- HELPERS
-- ---------------------------------------------------------------------------

local function Log(message: string)
	print("[AutoSniper] " .. message)
end

local function VerboseLog(message: string)
	if SnipeConfig.Verbose then
		Log(message)
	end
end

local function EnsureProcessedFolder()
	if processedFolder then
		return processedFolder
	end

	processedFolder = game:GetService("ServerStorage"):FindFirstChild(PROCESSED_FOLDER_NAME)
	if not processedFolder then
		processedFolder = Instance.new("Folder")
		processedFolder.Name = PROCESSED_FOLDER_NAME
		processedFolder.Parent = game:GetService("ServerStorage")
	end
	return processedFolder
end

-- Reads the item feed. In this implementation we scan child Instances of a
-- Folder named BoothItems in workspace, each representing one listed item.
-- Replace the body of this function with a real HTTP/WebService feed to go live.
local function FetchBoothItems(): { any }
	if not boothFolder then
		return {}
	end

	local items: { any } = {}
	for _, child in ipairs(boothFolder:GetChildren()) do
		table.insert(items, child)
	end
	return items
end

-- Whether the item name passes the configured filters.
local function NameMatchesFilters(itemName: string): boolean
	if #SnipeConfig.ItemNameFilters == 0 then
		return true
	end

	local lowered = string.lower(itemName)
	for _, filter in ipairs(SnipeConfig.ItemNameFilters) do
		if string.find(lowered, string.lower(filter), 1, true) then
			return true
		end
	end
	return false
end

-- Reads the Robux price off an item Instance.
local function GetItemPrice(item: Instance): number?
	if item:IsA("NumberValue") then
		return item.Value
	elseif item:IsA("IntValue") then
		return item.Value
	elseif item:IsA("Model") then
		local price = item:FindFirstChild("Price")
		if price and (price:IsA("NumberValue") or price:IsA("IntValue")) then
			return price.Value
		end
	end
	return nil
end

-- Reads an item id (unique identifier) off an item Instance.
local function GetItemId(item: Instance): string
	if item:IsA("ValueBase") and item:IsA("StringValue") then
		return item.Name
	end

	local id = item:FindFirstChild("ItemId")
	if id and id:IsA("StringValue") then
		return id.Value
	end
	return item.Name
end

-- Checks whether this item has already been processed (bought or skipped).
local function IsAlreadyProcessed(itemId: string): boolean
	local folder = EnsureProcessedFolder()
	return folder:FindFirstChild(itemId) ~= nil
end

-- Marks an item id as processed so we never re-buy it.
local function MarkProcessed(itemId: string)
	local folder = EnsureProcessedFolder()
	if folder:FindFirstChild(itemId) then
		return
	end
	local marker = Instance.new("StringValue")
	marker.Name = itemId
	marker.Value = itemId
	marker.Parent = folder
end

-- Simulates the purchase via the marketplace/booth backend. In a live system
-- this is where you would post the buy request (e.g. HttpService or a RemoteEvent
-- to your own server code handling the booth sale).
local function PurchaseItem(player: Player, item: Instance, itemId: string, price: number): boolean
	-- Simulated business logic: in production, verify the item is still listed,
	-- deduct Robux, transfer ownership, and refund/handle the item.
	Log(string.format(
		"Purchased %q (%s) for %d Robux for %s",
		item.Name, itemId, price, player.Name
	))

	-- Fire an event so other systems (UI, inventory, leaderboard) can react.
	local remote = ReplicatedStorage:FindFirstChild("SnipePurchased")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, item.Name, itemId, price)
	end

	-- Remove the item from the local booth feed to simulate it being sold.
	if item.Parent == boothFolder then
		item:Destroy()
	end
	return true
end

-- ---------------------------------------------------------------------------
-- CORE SNIPE LOGIC
-- ---------------------------------------------------------------------------

local function SnipeOnce(player: Player)
	if not SnipeConfig.Enabled then
		return
	end

	local items = FetchBoothItems()
	VerboseLog(string.format("Scanning %d booth items", #items))

	for _, item in ipairs(items) do
		if not item:IsA("BasePart") and not item:IsA("ValueBase") then
			continue
		end

		local itemId = GetItemId(item)
		if IsAlreadyProcessed(itemId) then
			continue
		end

		-- Skip bundles unless configured to buy them.
		if not SnipeConfig.BuyBundles and item:FindFirstChild("IsBundle") then
			MarkProcessed(itemId)
			continue
		end

		if not NameMatchesFilters(item.Name) then
			MarkProcessed(itemId)
			continue
		end

		local price = GetItemPrice(item)
		if not price then
			MarkProcessed(itemId)
			continue
		end

		if price < SnipeConfig.MinPrice then
			VerboseLog(string.format("Skipping %q: below MinPrice (%d).", item.Name, price))
			MarkProcessed(itemId)
			continue
		end

		if price > SnipeConfig.MaxPrice then
			VerboseLog(string.format("Skipping %q: above MaxPrice (%d > %d).", item.Name, price, SnipeConfig.MaxPrice))
			MarkProcessed(itemId)
			continue
		end

		-- (Optional) balance safety check against leaderstats.
		local leaderstats = player:FindFirstChild("leaderstats")
		local balanceValue = leaderstats and leaderstats:FindFirstChild("Robux")
		if balanceValue and (balanceValue:IsA("NumberValue") or balanceValue:IsA("IntValue")) then
			if balanceValue.Value < SnipeConfig.RequiredBalance then
				VerboseLog(string.format(
					"Skipping %q: balance %d below RequiredBalance %d.",
					item.Name, balanceValue.Value, SnipeConfig.RequiredBalance
				))
				MarkProcessed(itemId)
				continue
			end
		end

		-- Item matches all rules: buy it.
		local bought = PurchaseItem(player, item, itemId, price)
		if bought then
			MarkProcessed(itemId)
		end
	end
end

-- ---------------------------------------------------------------------------
-- LIFECYCLE
-- ---------------------------------------------------------------------------

Players.PlayerAdded:Connect(function(player: Player)
	Log(string.format("Sniper armed for %s.", player.Name))

	-- Arm once the character is ready (or immediately if no character yet).
	task.spawn(function()
		player.CharacterAdded:Wait()

		-- Main scan loop, runs while the player is in the game.
		while player.Parent and RunService:IsRunning() do
			local now = os.clock()
			if now - lastScan >= SnipeConfig.ScanInterval then
				lastScan = now
				SnipeOnce(player)
			end
			task.wait(SnipeConfig.ScanInterval / 2)
		end
	end)
end)

Log("Booth AutoSniper loaded. Configure SnipeConfig in the script to tune it.")
