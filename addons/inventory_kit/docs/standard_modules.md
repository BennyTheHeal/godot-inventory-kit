# Inventory Kit — Standard modules

> Full edition (`addons/inventory_kit/pro/`). Everything here builds on the Lite core, so the same guarantees apply: atomic changes, no item ever duplicated or lost, versioned saves.

## Equipment — `IKEquipment`

A node like `IKInventory`, with one slot per entry of `slot_types`:

```gdscript
equipment.slot_types = [&"head", &"body", &"weapon", &"offhand", &"ring", &"ring"]
```

Each slot only accepts items whose `IKItemDefinition.equip_slot` matches. Repeat a type for several slots.

| Member | Purpose |
|---|---|
| `equip_from(container, slot)` | Equips into the first free matching slot, or swaps with the first matching one |
| `unequip(slot_type, destination)` | Moves the worn item into `destination` |
| `get_equipped(slot_type)` | Copy of the worn stack, or null |
| `sum_property(&"armor")` | Sums a numeric `properties` entry over everything worn, active set bonuses included (`sum_property(&"armor", false)` leaves them out) |
| `equipped(slot_type, stack)` / `unequipped(slot_type, stack)` | Fire for every change, including drag and drop and loading a save, so stats stay in sync |

Show outlines in empty slots with `IKContainerView.empty_icons` (one texture per slot index).

### Set bonuses — `IKSetBonus`, `IKSetBonusList`

An item belongs to a set through its `properties["set"]` entry (for example `"iron"`). Each `IKSetBonus` gives its `properties` once `pieces_required` pieces of its set are worn; give a set one bonus for 2 pieces and one for 4. Put every bonus of the game in one `IKSetBonusList` and assign it to `IKEquipment.set_bonuses`.

```gdscript
equipment.set_bonuses = load("res://addons/inventory_kit/art/shared/set_bonuses.tres")  # the 8 shipped sets
equipment.set_bonus_changed.connect(func(bonus: IKSetBonus, active: bool) -> void:
	print(bonus.get_set_name(), " (", bonus.pieces_required, "): ", bonus.describe(), " ", active))
```

| Member | Purpose |
|---|---|
| `count_set_pieces(&"iron")` | Number of worn pieces of a set |
| `get_active_set_bonuses()` | Bonuses applying now |
| `set_bonus_changed(bonus, active)` | Fires when a bonus starts or stops applying |
| `set_property` | Property naming the set (default `set`) |

The shipped library has 16 bonuses for its 8 armor sets (Mage, Bronze, Iron, Steel, Royal Gold, Mithril, Adamantite, Dragonscale).

## Hotbar — `IKHotbar`

A small container with one selected slot (`selected`). Set `view` to the `IKContainerView` that shows it: the selected slot uses the skin's `slot_marked` style.

| Default input | Action |
|---|---|
| Keys 1–9 | `ik_hotbar_1` … `ik_hotbar_9`: select a slot |
| Mouse wheel | `ik_hotbar_next` / `ik_hotbar_previous` |
| Gamepad right trigger | `ik_hotbar_use`: use the selected item |

`select(index)`, `select_next()`, `use_selected()`, and the signals `selection_changed(index)` and `item_used(stack)` let you drive it from code. Set `user` to the player node, so effects know whom to apply to. Input is read in `_unhandled_input()`; turn off `handle_input` to drive it yourself.

## Chests — `IKChest`

An `IKInventory` for world containers: `open()`, `close()`, `toggle()`, `is_open`, `opened` / `closed` signals, `is_empty()` and `take_all(destination)`. What does not fit stays in the chest; the count is in `result.remainder`. Give every chest its own `container_id`, so each one is saved separately.

## Consumables — `IKUsableItem`, `IKItemEffect`, `IKItemUser`

Create **`IKUsableItem`** resources (a subclass of `IKItemDefinition`) for potions, food, scrolls… and give them **effects**.

- **No code**: `IKCallMethodEffect` calls a method on the user, e.g. `heal` with arguments `[50]`. Set `check_method` (e.g. `can_heal`) to refuse the use when it would be wasted.
- **Custom**: extend `IKItemEffect` and override `can_apply(context)` and `apply(context)`.

```gdscript
var result := IKItemUser.use(bag, slot, player)   # or IKItemUser.can_use(...)
```

1. Every effect is asked first (`can_apply`). If one refuses, **nothing is consumed** and `NOT_USABLE` is returned with the effect's message.
2. One item is removed (unless `consume_on_use` is false).
3. Only then are the effects applied. An item can never be used without being paid for, or twice.

With `IKInputController`, **Use** works on the selected slot: keyboard U, gamepad Back/Select, or a mouse double click. Set `use_target` to the player. If you set `equipment`, using an equippable item equips it, and using a worn one takes it off.

## Weight — `IKWeightRule`

```gdscript
bag.container.rules.append(IKWeightRule.new(40.0))
IKWeightRule.weight_of(bag.container)                   # current total
IKWeightRule.remaining_capacity(bag.container, &"stone") # how many more fit
```

A change is refused (`RULE_REJECTED`) only if it makes the container heavier than the limit. An overloaded container (rule added later, older save…) can always be emptied. `add(..., allow_partial = true)` is all-or-nothing with respect to weight: use `remaining_capacity()` to add only what fits.

## Sorting — `IKSorter`

```gdscript
IKSorter.sort(bag.container)                                        # by category, then name
IKSorter.sort(bag.container, IKSorter.Mode.NAME)
IKSorter.sort(bag.container, IKSorter.Mode.CATEGORY, [&"weapon", &"armor", &"consumable"])
```

Sorting merges matching stacks and reorders them in **one atomic transaction**. Slots with a slot rule (equipment) and unknown items stay in place. Modes: `CATEGORY`, `NAME`, `AMOUNT`. With `IKInputController`, **Sort** is keyboard R or the gamepad right stick press.

## Filters — `IKItemFilter`

```gdscript
bag_view.filter = IKItemFilter.category(&"consumable")
bag_view.filter = IKItemFilter.text(search_box.text)   # name, id, category, tags
bag_view.filter = IKItemFilter.all([IKItemFilter.equippable(), IKItemFilter.tag(&"fire")])
bag_view.filter = Callable()                           # show everything
```

Non-matching items are dimmed, not hidden, so the layout never jumps and drag and drop keeps working. Any `Callable(stack, definition) -> bool` works as a filter.

## Rich tooltips — `IKTooltipPresenter`

Add an `IKTooltipPresenter` as a child of your `IKInventoryUI`. Every slot then gets an `IKTooltip` showing:

- the icon, and the name colored by `properties["rarity"]` (common, uncommon, rare, epic, legendary);
- the category and equipment slot;
- the stats listed in `shown_properties` (e.g. damage, armor, heal);
- per-copy values listed in `shown_data` (e.g. durability);
- the description, the stack count and the weight.

With a keyboard or gamepad selection, the tooltip follows the selection, since Godot's own tooltips only appear on mouse hover.

Set `equipment` to your `IKEquipment` to compare equippable items with what is worn in the same slot type: each stat in `compare_properties` (damage, armor, mana, stamina, fire_resist by default) gets a green `+8` or a red `-3`, followed by "Compared with Iron Helmet" (or "Nothing worn in this slot"). Set pieces also list their set bonuses, active ones in green: "Iron set (2/4)".

## Slot feedback — `IKSlotFeedback`

Add an `IKSlotFeedback` as a child of your `IKInventoryUI`:

- slots that receive an item pop;
- refused actions (full slot, wrong slot type, weight limit) wiggle the slot and flash it red.

`pop_scale`, `pop_duration`, `shake_angle` and `reject_color` tune the effect; `pop(slot_view)` and `shake(slot_view)` can be called from your own code.

## World items — `IKWorldItem2D`, `IKWorldItem3D`

An `Area2D` / `Area3D` that shows the item icon on the ground (bobbing, with a shadow in 2D, as a billboard in 3D). It is collected when a body of `collector_group` (default `player`) touches it. The collector's inventory is its `IKInventory` child, or its `inventory` property (an `IKInventory` or an `IKContainer`).

```gdscript
# In the editor: add an IKWorldItem2D, set item_id, amount and database.
# From code (loot, drops); unique items keep their uid and data:
IKWorldItem2D.spawn(level, IKItemStack.new(&"oak_log", 5), database, position)
```

What does not fit stays on the ground with the remaining amount, and a uid already in the inventory is refused, so picking up can never duplicate an item. `picked_up(container, amount)` and `pickup_failed(container, result)` let you play sounds or show messages. With `auto_pickup = false`, call `pick_up(container)` yourself, for example on an "interact" key.

### Dropping items — `IKItemDropper`

Add an `IKItemDropper` as a child of your `IKInventoryUI` and set `spawn_parent` (the level) and `drop_origin` (the player, a `Node2D` or `Node3D`). Clicking outside every panel while holding a stack, or pressing `drop_action`, puts the stack on the ground next to the player. A dropped item is never collected straight back: the player has to step away from it and come back (`pickup_delay` sets how long touching bodies are ignored). Without a `spawn_parent`, only `item_dropped(stack, null)` fires and your game decides what to do with the stack.

### Pickup notifications — `IKPickupNotifier`

A `VBoxContainer` for your HUD that shows "+5 Oak Log" lines with the item icon. Lines for the same item merge, then fade out after `duration` seconds. World pickups are shown automatically. Add inventories to `watched` to also show rewards or crafting results, and set `hide_while` to your inventory screen so that moving items around there does not count. Call `notify(item_id, amount, database)` for anything else.

## Editor checks

With the plugin enabled, the inspector shows problems at the top of every `IKItemDatabase` and `IKItemDefinition`: empty or duplicate ids, unique items with a stack size, missing icons.

## Standard demo

`res://demo/standard/standard_demo.tscn` puts everything together: equipment with live armor, damage and set bonuses, comparison tooltips, a 40 kg backpack with filters, search and sort, a chest with "Take all", a hotbar, potions that heal a character, and and slot animations. It works with mouse, keyboard, gamepad and touch.

`res://demo/world/world_demo.tscn` (button "World pickups demo") shows world items: walk over them to collect them, open the bag with Tab, and click outside it to drop the held item.
