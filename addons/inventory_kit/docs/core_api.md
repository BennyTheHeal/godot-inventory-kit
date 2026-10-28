# Inventory Kit — Core API

> Status: milestones M1 (data + logic), M2 (saving, see [saving.md](saving.md)) and M3 (mouse UI, see [ui.md](ui.md)).
> Requires Godot 4.5+. Pure GDScript, no dependencies.

## Concepts

| Class | Role |
|---|---|
| `IKItemDefinition` | Resource describing an item type (id, name, icon, max stack, tags, equip slot…). Read-only at runtime. |
| `IKItemDatabase` | Resource listing definitions, looked up by `id`. |
| `IKItemStack` | A quantity of one item in a slot: `item_id`, `amount`, `uid` (unique items), `data` (per-copy state). |
| `IKContainer` | A fixed number of slots: bag, chest, equipment, hotbar… |
| `IKSlotRule` / `IKContainerRule` | Filters for one slot or a whole container. |
| `IKTransaction` | Atomic batch of operations over one or more containers. |
| `IKResult` | Outcome of every change: `ok`, `code`, `message`, `remainder`. |
| `IKAudit` | Consistency checks (totals, duplicate uids, invalid stacks). |

## Stable ids

- **Item ids** (`IKItemDefinition.id`) are what save files store. Pick them once (`&"iron_sword"`) and never change them. Moving or renaming the `.tres` file is safe.
- **Unique items** (`unique = true`) get a 128-bit `uid` per copy. They never stack and keep their `data` (durability, enchantments…) when moved.
- **Container ids** (`IKContainer.container_id`) identify containers in save files.

## Quick start

```gdscript
var db: IKItemDatabase = preload("res://items/database.tres")
var bag := IKContainer.new(&"player_bag", 24, db)

bag.add(&"wood", 30)                       # tops up existing stacks, then empty slots
var result := bag.add(&"stone", 500, true) # allow_partial: what doesn't fit is reported
if result.remainder > 0:
	drop_on_ground(&"stone", result.remainder)

bag.move(0, 5)            # place, merge or swap
bag.split(5, 10)          # 10 items into the first suitable empty slot
bag.transfer_to(5, chest) # quick move: merge first, then empty slots
bag.remove(&"wood", 4)
bag.set_data(2, {"durability": 80}) # per-copy data of one stack
print(bag.count(&"wood"))
```

## Equipment slots

```gdscript
var equipment := IKContainer.new(&"equipment", 2, db)
equipment.set_slot_rule(0, IKEquipSlotRule.new(&"weapon")) # only items with equip_slot == &"weapon"
equipment.set_slot_rule(1, IKEquipSlotRule.new(&"head"))
bag.move_to(3, equipment, 0)   # fails with RULE_REJECTED if slot 3 is not a weapon
```

`IKTagSlotRule` filters by `categories` and/or `any_tags`. Extend `IKSlotRule` (per slot) or `IKContainerRule` (whole container) for custom rules. An `IKContainerRule` can override `accepts()` (per item), `validate_slots(after)` or `validate_change(before, after)`. Use `validate_change` for limits that must still let players fix an invalid state, such as the Full edition's weight limit.

## Custom layouts

`IKTransaction.rearrange(container, slots)` replaces the whole content of a container (same size, stacks or null). All commit checks still apply, so items can be reordered, merged or split, but never created or lost. The Standard sorter is built on it.

## Grid containers

`IKContainer.create_grid(id, width, height, database)` (or `set_grid_width(width)` on an existing container, or `IKInventory.grid_width`) turns slots into cells, row by row. Items take `IKItemDefinition.grid_size` cells (`get_grid_size(rotated)`, `can_rotate`, `is_rotatable()`); a stack is stored in its top-left cell and `IKItemStack.rotated` says whether it is turned.

| Method | Use |
|---|---|
| `is_grid()`, `get_grid_width()`, `get_grid_height()` | Mode and size |
| `cell_of(slot)`, `slot_of(cell)` | Index ↔ `Vector2i` coordinates |
| `get_anchor(cell)`, `get_footprint(cell)`, `get_item_size(slot)`, `get_size_of(stack)` | Which item covers a cell, and its cells |
| `can_place(cell, stack, ignore_slot)`, `can_drop(cell, stack)`, `get_overlapping(cell, stack)`, `find_place(stack)` | Room checks without changing anything |
| `rotate(cell)` / `IKTransaction.rotate()` | Quarter turn in place |

Every operation (`add`, `move`, `transfer`, `split`, `remove_at`, `set_data`) works on grids; commits reject overlapping or out-of-grid layouts. In grid mode `is_slot_empty()`, `get_free_slot_count()` and `get_first_free_slot()` count cells. Full guide: "Grid inventory" in [recipes.md](recipes.md).

## Transactions: all or nothing

Every change is a transaction. Helpers such as `bag.add()` run a one-operation transaction. Chain operations to make several changes atomic:

```gdscript
# Crafting: pay and receive in one step. If anything fails, nothing changes.
var result := IKTransaction.new() \
	.consume(bag, {&"wood": 4, &"rope": 1}) \
	.add(bag, &"bow", 1) \
	.commit()
if not result.ok:
	show_error(result.message)
```

Guarantees checked on every `commit()`:

1. **Atomic**: after the first failing operation the transaction does nothing. `commit()` returns that first error and no container changes.
2. **Conservation**: for every item, the change in total equals what `add`/`remove`/`consume` declared. Moves, splits, swaps and transfers can never create or destroy items.
3. **Validity**: every changed slot respects stack limits and slot/container rules, and no uid appears twice.
4. **Freshness**: a transaction prepared before another change to the same container is rejected (`CONCURRENT_MODIFICATION`) instead of overwriting it.
5. **Signals after commit**: listeners always see the final state of every container, and can safely start new transactions.

## Signals (`IKContainer`)

| Signal | When |
|---|---|
| `slots_changed(slot_indices)` | Slots whose content changed. Use it to refresh UI. |
| `item_added(item_id, amount)` | Net gain of an item in this commit (quests: "collect 10 berries"). |
| `item_removed(item_id, amount)` | Net loss of an item in this commit. |
| `changed()` | Once per commit that changed the container. |

Moving items inside one container emits `slots_changed` only, never `item_added` or `item_removed`.

## Reading is safe

`get_stack()` returns a **copy**. Editing it never changes the container. Always change state through the container helpers or `IKTransaction`.

## Result codes

`OK`, `INVALID_ARGUMENT`, `UNKNOWN_ITEM`, `SLOT_OUT_OF_RANGE`, `SLOT_EMPTY`, `SLOT_OCCUPIED`, `SLOT_FULL`, `RULE_REJECTED`, `CONTAINER_FULL`, `NOT_ENOUGH_ITEMS`, `NOT_MERGEABLE`, `NOT_SPLITTABLE`, `CONCURRENT_MODIFICATION`, `INVARIANT_VIOLATION`, `TRANSACTION_CLOSED`, `NOT_USABLE`.

## Running the tests

```bash
godot --headless --path <project> --import
godot --headless --path <project> -s res://tests/inventory_kit/run_tests.gd
godot --headless --path <project> -s res://tests/inventory_kit/run_tests.gd -- fuzz   # one file
```

The exit code is 0 only when every test passes. The fuzz test runs 12,000 random operations (fixed seeds) and checks after each one that no item was lost or duplicated. Every 250 operations it also saves through JSON, loads into fresh containers and checks that the state is identical.

## Compatibility

| Godot | Status |
|---|---|
| 4.5-stable (minimum) | Full test suite passes; editor plugin loads; Lite and Standard work in a blank project |
| 4.7.2-stable | Same, and the development version |

Pure GDScript, no GDExtension: nothing to recompile when Godot updates.
