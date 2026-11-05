# Booth Item AutoSniper

A Roblox Studio server script that continuously scans a "booth" item feed and automatically buys items that match your configured rules (price range, item name filters, bundle settings). This automation tool helps users quickly secure limited or rare items as soon as they appear in the marketplace feed.

## Install

1. Copy `AutoSniper.server.lua` into `ServerScriptService` (or a folder inside it).
2. Open the script in Roblox Studio and locate the `SnipeConfig` table at the top.
3. Configure the settings:
   - `ScanInterval` — how often to scan (seconds)
   - `MaxPrice` / `MinPrice` — the Robux price window for purchases
   - `ItemNameFilters` — list of name substrings to match (empty `{}` = buy anything)
   - `BuyBundles` — set `true` to also buy bundled items
   - `RequiredBalance` — safety: skip buying if balance is below this
   - `Enabled` — master kill-switch

## Use

1. In the `workspace`, create a `Folder` named `BoothItems`.
2. Add child instances inside the folder representing booth items:
   - A `Model` with a `NumberValue`/`IntValue` named `Price` (optional `StringValue` named `ItemId`), or
   - A plain `NumberValue`/`IntValue` where value = price and name = item name
3. Run the game. The script will:
   - Scan `BoothItems` folder periodically
   - Check each item against configured rules
   - Auto-purchase matching items by removing them from the feed
   - Log purchases and skip processed items

Example folder structure:
```
workspace
└─ BoothItems               (Folder)
   ├─ Gold Limited          (Model)   └─ Price = 200 NumberValue
   ├─ Rare Sword            (Model)   └─ Price = 1500 NumberValue, ItemId StringValue
   └─ Common Trash          (NumberValue, Value = 1)
```

Processed items are stored in `ServerStorage.ProcessedSnipeItems` to prevent duplicates. For real marketplace integration, replace the `FetchBoothItems()` and `PurchaseItem()` functions with your backend calls.

---

More Roblox script projects by EnderDevelopment: https://github.com/EnderDevelopment

Project page: https://dash.enderdevelopment.com/community/ca7dbe6b-cf0c-4fb5-9006-f765a753a9c2?utm_source=github&utm_medium=readme&utm_campaign=auto_publish&utm_content=ca7dbe6b-cf0c-4fb5-9006-f765a753a9c2
