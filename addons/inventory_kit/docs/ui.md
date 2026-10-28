# Inventory Kit — UI (mouse)

> Lite edition: mouse controls. Gamepad, keyboard and touch are part of the Full edition: see [input.md](input.md).

## Five-minute setup (no code)

1. Add an **`IKInventoryUI`** node (a full-screen `Control`) as the root of your inventory screen.
2. Under it, add an **`IKInventory`** node: set `container_id`, `size`, `database` and optionally `initial_items`.
3. Add an **`IKContainerView`** anywhere below the `IKInventoryUI` (inside panels, margins…), set `columns` and point its `inventory` property at the `IKInventory` node.
4. Run. Click, right-click, shift-click and drag work immediately.

For a chest, add a second `IKInventory` + `IKContainerView` and set each view's `quick_move_target` to the other view.

From code, `view.bind(container)` works with any `IKContainer`.

## Controls

| Input | Empty hand | Holding items |
|---|---|---|
| Left click | Pick up the whole stack | Put everything down (merge, or swap with a different item) |
| Right click | Pick up half (rounded up) | Put one item down |
| Shift + left click | Send the stack to `quick_move_target` | — |
| Drag and drop | Press on a slot, release on another | — |
| Middle click (grid inventories) | — | Turn the held item a quarter turn |

Hiding the `IKInventoryUI` puts held items back where they came from (`return_held_on_hide`).

**Grid inventories.** A view of a grid container (`IKContainer.create_grid()` or `IKInventory.grid_width`) shows one cell per slot and sets its own `columns`. Each item is drawn over all its cells; clicking any of them picks it up, and a click puts the held item's top-left cell where you point. While holding, the cells it would cover are tinted (`IKSkin.grid_valid_color` / `grid_invalid_color`). The held item is drawn at its grid size, turned when it is turned. Covered cells answer `IKSlotView.get_item_stack()` / `get_item_definition()` with the item over them; `get_anchor_slot()` and `get_display_view()` give its top-left cell. See the recipe in [recipes.md](recipes.md).

## The cursor (items in hand)

`IKInventoryUI.cursor` is an `IKCursor`. Held items live in `cursor.container`, a one-slot `IKContainer`, so they are covered by every safety check and can be saved:

```gdscript
save.save([bag.container, chest.container, inventory_ui.cursor.container])
```

Or put them back before saving: `inventory_ui.return_held()`.

| Method | Purpose |
|---|---|
| `primary(container, slot)` / `secondary(container, slot)` | The two actions above, for any input device |
| `quick_move(from, slot, to)` | Shift-click behaviour |
| `return_held(fallbacks := [])` | Origin slot, then origin container, then fallbacks. If there is no room, items **stay in hand** and `CONTAINER_FULL` is returned. |
| `take_held()` | Removes and returns the held stack, e.g. to drop it in the world |

## Feedback

- `IKInventoryUI.interaction_failed(result)`: an action was refused (`RULE_REJECTED`, `SLOT_FULL`…). Show `IKText.result_message(result)` to players (translatable, see localization.md); `result.message` is the technical detail.
- While holding an item, hovering a slot that refuses it uses the skin's `slot_rejected` style.
- Tooltips show the item's `display_name` and `description` (Godot's built-in tooltip).

## Extension points

| Member | Purpose |
|---|---|
| `IKContainerView.filter` | `Callable(stack, definition) -> bool`; occupied slots that do not match are dimmed |
| `IKContainerView.empty_icons` | Faint placeholder per slot while it is empty (equipment outlines) |
| `IKContainerView.slot_view_created(slot_view)` | Customize every slot view, including after a rebuild |
| `IKSlotView.marked` / `dimmed` / `focused` | Persistent highlight, faded look, keyboard selection |
| `IKSlotView.tooltip_factory` | `Callable(slot_view) -> Control` for custom tooltips |
| `IKSlotView.get_item_stack()` | Copy of the slot's stack. It is not called `get_stack()`, because that name is a built-in GDScript debug function. |
| `IKInventoryUI.view_registered(view)`, `slot_pressed(view, slot_view, event)` | Hooks for input and tooltip add-ons |

## Skins

`IKSkin` holds every visual setting: slot size and spacing, icon margin, slot styles (`slot_normal`, `slot_hover`, `slot_rejected`) and the amount label font and colors. Assign one to `IKInventoryUI.skin` (whole screen) or to an `IKContainerView.skin` (one view). Without a skin, a neutral grey style is generated, so the UI works with no art at all.

## Lite demo

Open `res://demo/lite/lite_demo.tscn`: a backpack and a chest with save/load buttons. The demo icons are generated shapes; your game uses the `icon` of each `IKItemDefinition`.
