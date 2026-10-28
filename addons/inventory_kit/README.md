# Inventory Kit for Godot 4

An inventory system that works with a **gamepad**, saves **without ever losing or duplicating items**, and **looks finished** from the first run.

**Pay what you want, from $0.** Code under MIT, art free to use in your games. A tip on itch.io keeps new kits coming. Official page, downloads and playable web demo: https://banc-essai.site-testeurs.workers.dev/inventory-kit/
More free kits, and our game prototypes waiting for testers: https://banc-essai.site-testeurs.workers.dev/

- Pure GDScript, no dependencies. Tested on Godot **4.5** and **4.7**.
- Atomic transactions: every change applies fully or not at all; item totals are checked on every commit.
- Versioned, crash-safe saves with automatic backups and self-repairing loads.
- Optional grid inventories (Diablo / Resident Evil style): items take several cells, turn a quarter turn, swap and pack themselves. Classic slots stay the default, and both mix on one screen.
- Mouse, keyboard, gamepad and touch with one interaction model (Full).
- Equipment with set bonuses and comparison tooltips, hotbar, chests, consumables, weight, sort, filters (Full).
- Items on the ground in 2D and 3D, dropping, "+5 Oak Log" pickup notifications (Full).
- Slot animations: items pop in, refused moves shake (Full).
- 120 ready-made items in 4 art directions, with matching UI skins (Full edition).
- Every player-facing text is translatable or rewordable (Godot CSV templates included). Ships in English.
- 275 automated tests you can run yourself.

## Install

1. Copy `addons/inventory_kit/` into your project's `addons/` folder.
2. *Project > Project Settings > Plugins*: enable **Inventory Kit** (optional: it only adds inspector checks).
3. Open `demo/lite/lite_demo.tscn`, `demo/standard/standard_demo.tscn`, `demo/world/world_demo.tscn` or `demo/grid/grid_demo.tscn` (grid inventory) to see it running.

Grid inventory in one line: `var bag := IKContainer.create_grid(&"bag", 10, 6, database)` (or set `grid_width` on an `IKInventory`), and give items a `grid_size` such as `Vector2i(1, 3)`. See "Grid inventory" in docs/recipes.md.

## Five-minute setup

1. Add an `IKInventoryUI` (full-screen Control) as the root of your inventory screen.
2. Under it, add an `IKInventory` node: set `container_id`, `size` and `database` (for example `addons/inventory_kit/art/painted/painted_items.tres`).
3. Add an `IKContainerView`, set its `inventory` and `columns`.
4. Full edition: add an `IKInputController` (gamepad, keyboard, touch), an `IKTooltipPresenter` and an `IKSlotFeedback` as children of the `IKInventoryUI`.
5. Pick a look: set the `IKInventoryUI` `skin` and `theme` to the `<art>_skin.tres` and `<art>_theme.tres` files.

```gdscript
var save := IKSaveFile.new("user://slot1/inventory.json")
save.save([bag.container, equipment.container])
var report := save.load_into([bag.container, equipment.container])
```

## Documentation

| Guide | Content |
|---|---|
| [docs/recipes.md](docs/recipes.md) | Copy-paste answers: items in code, autoload, saving, durability, rewards, drops, rules, grid inventory |
| [docs/core_api.md](docs/core_api.md) | Items, containers, rules, transactions, signals, running the tests |
| [docs/saving.md](docs/saving.md) | Save files, recovery, format, migrations |
| [docs/ui.md](docs/ui.md) | Mouse UI, cursor, skins, extension points |
| [docs/input.md](docs/input.md) | Keyboard, gamepad and touch (Full) |
| [docs/standard_modules.md](docs/standard_modules.md) | Equipment and set bonuses, hotbar, chests, consumables, weight, sort, filters, tooltips, feedback, world items (Full) |
| [docs/localization.md](docs/localization.md) | Translating or rewording every text shown to players |
| [docs/art_library.md](docs/art_library.md) | The 120 items, art directions, skins and themes |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

## Editions

Both editions are pay what you want, $0 included. Pick the Lite one if you only want the core and the mouse UI with a tiny footprint.

| | Lite | Full |
|---|---|---|
| Core, transactions, saves, mouse UI | ✓ | ✓ |
| Grid inventories (multi-cell items, rotation) | ✓ | ✓ |
| Gamepad / keyboard / touch | | ✓ |
| Equipment, set bonuses, hotbar, chests, consumables, weight, sort, filters, rich tooltips | | ✓ |
| World items (2D/3D), dropping, pickup notifications, slot animations | | ✓ |
| Item library and UI skins | 10 sample icons | Hand-painted, Realistic, Cartoon, Flat (4 × 120) |

In the docs, "Standard" refers to the modules in `addons/inventory_kit/pro/`, all included in the Full edition.

## Updates

- Versions follow semantic versioning: 1.x updates are free and never break your code, your item ids or your save files. A 2.0 would come with a migration guide, and saves would still load (format migrations).
- Supported: Godot 4.5 and newer. Every release is tested on the oldest and newest supported versions, in the editor and in an exported release build.
- Updates replace `addons/inventory_kit/`: keep the files you edit (item databases, skins, translations) in your own folders. See docs/recipes.md.

## Licenses

- Source code (Lite and Full, `pro/` included): MIT (`LICENSE.txt`).
- Art: free to use in your games, commercial or not; please do not re-upload it, link to the official page instead (`LICENSE_ART.txt`). The art was generated with AI image tools, then curated and processed by hand.
- Found a bug or want a feature? Tell us on the official page: https://banc-essai.site-testeurs.workers.dev/inventory-kit/
