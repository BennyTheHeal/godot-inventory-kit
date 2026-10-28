# Inventory Kit — Recipes

Short answers to the questions people ask most about inventory addons. Each recipe is complete: copy it, rename, done.

## Create items in code (no .tres file)

```gdscript
var db := IKItemDatabase.new()
var sword := IKItemDefinition.new()
sword.id = &"sword"            # saved in save files: never change it
sword.display_name = "Sword"
sword.unique = true            # one uid per copy, can hold durability...
sword.equip_slot = &"weapon"
sword.properties = {"damage": 12}
db.add_item(sword)
```

## Keep the player's inventory across scenes (autoload)

Containers are plain objects: keep them in an autoload, and let each scene only display them.

```gdscript
# player_data.gd, added in Project Settings > Globals > Autoload as "PlayerData"
extends Node

var database: IKItemDatabase = preload("res://addons/inventory_kit/art/painted/painted_items.tres")
var bag := IKContainer.new(&"bag", 24, database)
var equipment := IKContainer.new(&"equipment", 4, database)
```

```gdscript
# in the inventory screen of any scene
func _ready() -> void:
	$Screen/BagView.bind(PlayerData.bag)
```

## Save and load

```gdscript
var save := IKSaveFile.new("user://slot1/inventory.json")
save.save([PlayerData.bag, PlayerData.equipment])

var report := save.load_into([PlayerData.bag, PlayerData.equipment])
if not report.ok:
	push_warning(report.error)  # the containers are left unchanged
```

A crash during saving never destroys the previous save, and loading repairs what it can (see saving.md). Containers are matched by `container_id`, so keep those ids stable.

## Durability, charges, enchantments (per-copy data)

Item definitions are shared by every copy; per-copy values live in the stack's `data`:

```gdscript
bag.add(&"sword", 1, false, {"durability": 100})
var stack := bag.get_stack(slot)                       # a copy: editing it changes nothing
bag.set_data(slot, {"durability": stack.data.durability - 1})
if bag.get_stack(slot).data.durability <= 0:
	bag.remove_at(slot)
```

Show it in tooltips with `IKTooltipPresenter.shown_data = [&"durability"]`. Stacks with different data never merge.

## Give a reward only if everything fits

```gdscript
var result := IKTransaction.new() \
	.consume(bag, {&"oak_log": 4, &"iron_ingot": 1}) \
	.add(bag, &"iron_chest") \
	.commit()
if not result.ok:
	status.text = IKText.result_message(result)  # nothing was taken or given
```

## React when the player picks something up

```gdscript
bag.item_added.connect(func(item_id: StringName, amount: int) -> void:
	quests.on_collected(item_id, amount))
```

`item_added` / `item_removed` give net amounts per commit: moving items inside the bag fires nothing.

## Drop the held item when the player clicks outside the inventory

Standard: add an `IKItemDropper` (see standard_modules.md). By hand, in any edition:

```gdscript
var stack := inventory_ui.cursor.take_held()  # leaves the inventory: your game owns it now
if stack != null:
	spawn_pickup(stack)  # your own node, or IKWorldItem2D.spawn(level, stack, database, position) in Standard
```

## Close the inventory without losing the held item

Hiding the `IKInventoryUI` puts the held item back automatically (`return_held_on_hide`). Call `inventory_ui.return_held()` to do it yourself, for example before saving.

## Only potions in the belt, only rings in ring slots

```gdscript
var potions := IKTagSlotRule.new()
potions.categories = [&"consumable"]
belt.set_slot_rule(0, potions)
equipment.set_slot_rule(3, IKEquipSlotRule.new(&"ring"))
```

## Show a message when an action is refused

```gdscript
inventory_ui.interaction_failed.connect(func(result: IKResult) -> void:
	status.text = IKText.result_message(result))  # "Too heavy.", "Not enough room."...
```

## Keep your changes safe from addon updates

Updates replace `addons/inventory_kit/`. Keep everything you change outside it: copy the item databases, skins, themes, set bonuses and translation CSV files you edit into your own folders and point your nodes at the copies. Item ids and save files stay compatible across 1.x versions (see "Updates" in the README).

## Grid inventory (Diablo / Resident Evil style)

Items take several cells, can turn a quarter turn, and must find room. Classic slots stay the default: only the containers you create as grids behave like this, and the same screen can mix both (a grid backpack and classic equipment slots).

1. Give items a size in cells (inspector: *Grid Size*). One cell is the default, so items you do not touch keep working.

```gdscript
sword.grid_size = Vector2i(1, 3)   # 1 wide, 3 tall
armor.grid_size = Vector2i(2, 3)
staff.grid_size = Vector2i(1, 4)
staff.can_rotate = false           # never turned (default: true)
```

2. Make the container a grid: `width x height` cells.

```gdscript
var backpack := IKContainer.create_grid(&"backpack", 10, 6, database)
# or, no code: an IKInventory with grid_width = 10 and size = 60
```

3. Show it with a normal `IKContainerView`: it detects the grid, sets its own columns and draws each item over its cells. Mouse, keyboard, gamepad and touch work as usual; see the controls below.

```gdscript
backpack.add(&"sword")            # first free place, row by row; turned if that is the only way it fits
backpack.move(0, 13)              # top-left cell of the item to cell 13 (place, merge or swap)
backpack.rotate(13)               # quarter turn, keeps its top-left cell; refused if there is no room
backpack.get_anchor(23)           # top-left cell of the item covering cell 23 (-1: free)
backpack.can_place(4, stack)      # fits there without covering anything?
backpack.find_place(stack)        # {"slot": 7, "rotated": true}, or {} if it fits nowhere
IKSorter.sort(backpack)           # Full: sorts and packs everything from the top-left corner
```

Rules of the grid:

- A stack lives in its top-left cell (`get_stack(cell)` returns it there only); the cells it covers are taken (`is_slot_empty()` is false) and any of them can be used to pick, move, remove or rotate the item.
- Dropping an item over exactly one other item merges them if they stack, otherwise swaps them (the other one goes where the first came from, or into the hand). Over two items, or sticking out of the grid, the drop is refused with "It does not fit there." (`IKResult.player_text`).
- Transactions keep every guarantee: a commit that would make items overlap or stick out is rejected, totals are checked, and `IKAudit.validate()` reports broken grids.
- `transfer()` and quick moves into a grid use automatic placement; partial adds report the remainder as usual.

| Control | Turn the held item |
|---|---|
| Mouse | Middle click (Lite) |
| Keyboard / gamepad | T / left stick press (`ik_rotate`, Full) |
| Touch | Tap with a second finger while holding (Full) |
| Code / on-screen button | `inventory_ui.rotate_held()` |

Saves store the top-left cell and `"rot": true` for turned items. Old saves load into grids (items that no longer fit are placed elsewhere, turned if needed, or go to `report.overflow`), and grid saves load into classic slots. Changing a container from slots to a grid later is safe.

See `demo/grid/grid_demo.tscn` (Full): a 10 x 6 backpack, a 6 x 5 stash and a classic belt.

## Big inventories

The cost of an operation does not depend on the container size: moving an item in a 500-slot chest takes under 0.1 ms, saving 5 chests of 500 slots about 25 ms (measured on a desktop PC, Godot 4.7). Showing hundreds of slots at once is mostly a layout question: put the view in a `ScrollContainer`.
