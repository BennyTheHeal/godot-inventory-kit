# Changelog

All notable changes to Inventory Kit are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-10-28

### Added
- Grid inventories (Diablo / Resident Evil style), optional: classic slots stay the default and both mix on one screen.
  - `IKItemDefinition.grid_size` (default 1 x 1), `can_rotate`, `get_grid_size()`, `is_rotatable()`; `IKItemStack.rotated`.
  - `IKContainer.create_grid()`, `set_grid_width()`, `is_grid()`, `get_grid_width()` / `get_grid_height()`, `cell_of()` / `slot_of()`, `get_anchor()`, `get_footprint()`, `get_item_size()`, `get_size_of()`, `can_place()`, `can_drop()`, `get_overlapping()`, `find_place()`, `rotate()`; `IKInventory.grid_width`.
  - Every operation works on grids: automatic placement (first free place, turned if needed), moves by top-left cell with merge or swap, transfers, splits, rotation (`IKTransaction.rotate()`); any covered cell can be used to pick an item. Commits and `IKAudit.validate()` reject overlapping or out-of-grid layouts.
  - UI: grid views draw items over their cells, preview the drop (`IKSkin.grid_valid_color` / `grid_invalid_color`), draw the held item at its size; `IKCursor.rotate_held()`, `IKInventoryUI.rotate_held()`, middle click turns the held item. `IKSlotView.get_item_definition()`, `get_anchor_slot()`, `get_display_view()`.
  - Full: `ik_rotate` action (T, left stick press), second finger tap to turn, navigation that jumps over the item under the selection, `IKSorter` packs grids, tooltips and slot animations follow multi-cell items.
  - Saves keep cells and rotation (`"rot": true`, format version 1 unchanged); old saves load into grids, with relocation or overflow when an item no longer fits.
- Grid inventory demo (`demo/grid/grid_demo.tscn`), reachable from the Full demo.
- Recipe "Grid inventory" in `docs/recipes.md`; 2 new player texts in the translation template.
- 93 new tests (275 in total).

### Changed
- `IKContainer.new()` takes an optional 4th argument, the grid width. Existing calls are unchanged.

## [1.1.1] - 2026-10-26

### Changed
- Inventory Kit is now pay what you want (from $0). The former Standard and Ultimate editions are merged into one free Full edition (all modules and the four art directions); the Lite edition stays.
- All source code is under the MIT license (`LICENSE.txt`, replacing `LICENSE_LITE.txt` and `LICENSE_COMMERCIAL.txt`). The art stays free to use in games, without re-uploading (`LICENSE_ART.txt`).

## [1.1.0] - 2026-10-23

### Added
- Standard: armor set bonuses (`IKSetBonus`, `IKSetBonusList`): `IKEquipment.set_bonuses`, `count_set_pieces()`, `get_active_set_bonuses()`, `set_bonus_changed` signal; `sum_property()` includes active bonuses. The library ships 16 bonuses for its 8 armor sets (`art/shared/set_bonuses.tres`).
- Standard: tooltips compare equippable items with the worn one (`IKTooltipPresenter.equipment`, `compare_properties`), with green and red differences, and show set progress with its bonuses.
- Standard: `IKSlotFeedback`: item-received pop, refused-action wiggle and red flash.
- Standard: world items `IKWorldItem2D` and `IKWorldItem3D` (automatic or manual pickup, partial pickup, uid and data kept, `spawn()` for loot and drops), `IKItemDropper` (click outside the inventory to drop) and `IKPickupNotifier` ("+5 Oak Log" lines).
- World pickups demo (`demo/world/world_demo.tscn`), reachable from the Standard demo.
- Every text shown to players is translatable and rewordable through Godot's translation system: `IKText` (`t()`, `result_message()`, `result_texts`), templates in `translations/` (33 Lite texts, 248 Standard texts), `docs/localization.md`.
- Player-facing refusal messages: `IKResult.player_text`, `IKContainerRule.refusal_text` ("Too heavy." for `IKWeightRule`); `IKResult.message` stays the technical detail.
- 24 new tests (182 in total).

- Core: `IKContainer.set_data()` / `IKTransaction.set_data()` change the per-copy data of a stack (durability, charges, enchantments), atomically like every other change.
- Docs: `docs/recipes.md` (items in code, autoload, saving, durability, rewards, drops, slot rules, safe updates), "Updates" policy in the README.
- Tests: the runner also works inside exported release builds; source-only checks are skipped there.

### Changed
- Transactions copy only the slots they change (copy-on-write) and check only those: operations no longer slow down with container size. In a 500-slot container a move takes 0.09 ms instead of 1.5 ms; filling 5 chests of 450 items 0.28 s instead of 2.2 s. Same guarantees (atomicity, conservation, unique ids).

### Fixed
- An `IKInventoryUI` without a skin no longer raises an error when it becomes ready.

## [1.0.0] - 2026-10-23

### Added
- Core data model: `IKItemDefinition`, `IKItemDatabase`, `IKItemStack`, unique item uids (`IKUid`).
- `IKContainer` with add (full or partial), remove, consume, move, merge, swap, split and quick transfer.
- Slot rules (`IKEquipSlotRule`, `IKTagSlotRule`) and container rules (`IKContainerRule`).
- `IKTransaction`: atomic multi-container operations with conservation, validity and freshness checks.
- `IKAudit` consistency checks.
- `IKSerializer`: versioned, JSON-safe save format (v1) with type-preserving item data.
- Self-repairing load with `IKLoadReport` (relocation, overflow, duplicate uid removal, unknown items kept) and `IKLoadOptions` (item aliases).
- `IKMigrations`: step-by-step format upgrades; saves from newer builds are refused.
- `IKSaveFile`: atomic writes with SHA-256 checksum, `.bak` rotation and recovery from interrupted saves.
- `IKCursor`: held items stored in a real one-slot container (pick, place, half, one, swap, quick move, return, take).
- Mouse UI: `IKInventoryUI`, `IKContainerView`, `IKSlotView`, `IKCursorView`, with click, right-click, shift-click and drag-and-drop.
- `IKSkin` with a generated default look (no art required) and built-in tooltips.
- `IKInventory` node for no-code setup, with `initial_items`.
- Lite demo scene (`demo/lite/lite_demo.tscn`).
- Standard: `IKInputController` for keyboard, gamepad and touch (grid and cross-container navigation, held-direction repeat, panel cycling, tap / drag / long press, automatic device switching).
- Standard: `IKInputActions` default bindings (physical keys, Xbox/PlayStation layouts) that never override user-defined actions.
- Standard: `IKEquipment` (typed slots, equip/unequip, stat sums, change signals), `IKHotbar` (selection, keys 1-9, mouse wheel, use), `IKChest` (open state, take all).
- Standard: consumables with `IKUsableItem`, `IKItemEffect`, `IKCallMethodEffect` and `IKItemUser` (check, consume, then apply).
- Standard: `IKWeightRule`, `IKSorter` (category / name / amount, custom category order), `IKItemFilter` (category, tag, equippable, text, all, any).
- Standard: rich tooltips (`IKTooltip`, `IKTooltipPresenter`) for mouse and gamepad selection.
- Standard: inspector checks for item databases and definitions.
- Standard: use/equip (U, Back, double click) and sort (R, right stick) actions in `IKInputController`.
- Core: `IKTransaction.rearrange()`, `IKContainerRule.validate_change()`, `NOT_USABLE` result code.
- UI: slot `marked` / `dimmed` states, empty-slot placeholders, view filters, custom tooltip factory, extension signals.
- Standard demo scene (`demo/standard/standard_demo.tscn`) with equipment, weight, chest, hotbar, consumables, sort and filters.
- Headless test runner with 151 tests: 12,000-operation fuzz test with periodic save round trips, UI tests with simulated mouse, keyboard, gamepad and touch input, Lite isolation checks.

- Art library: 4 art directions (hand-painted, realistic, cartoon, flat), each with 120 items as an `IKItemDatabase` (tiered resources and 8 armor sets), 128 px icons, an `IKSkin` and a `Theme`; shared equipment silhouettes; a 10-icon Lite sample.
- Standard demo rebuilt on the art library, with a live art direction picker.
- Rich tooltips accept a panel style (`IKTooltipPresenter.panel_style`).
- Assigning `IKInventoryUI.skin` at runtime restyles every view and the held item.
- Art: stray specks removed from every icon, stronger outlines and colors for the hand-painted set, natural muted colors for the realistic set, brighter realistic bow.

### Fixed
- Mouse tooltips no longer draw a second frame inside Godot's tooltip panel.

### Compatibility
- Tested on Godot 4.5-stable (minimum supported version) and 4.7.2-stable: 159 tests pass on both, art library included.

### Fixed
- The mouse wheel is no longer swallowed by slot views (scrolling and hotbar selection work over the inventory).
