# Inventory Kit — Keyboard, gamepad and touch

> Full edition (`addons/inventory_kit/pro/input/`).

## Setup

Add an **`IKInputController`** node as a child of your `IKInventoryUI`. That's all: every `IKContainerView` in the screen becomes reachable with the keyboard, a gamepad or touch.

## Default controls

| Action | Keyboard | Gamepad (Xbox / PlayStation) | InputMap action |
|---|---|---|---|
| Move selection | Arrows or WASD | D-pad or left stick | `ik_nav_up/down/left/right` |
| Pick up / put down | Enter, Space | A / Cross | `ik_primary` |
| Take half / put one | X | X / Square | `ik_secondary` |
| Send to the other container | F | Y / Triangle | `ik_quick_move` |
| Put held items back (empty hand: `close_requested`) | Escape | B / Circle | `ik_cancel` |
| Previous / next container | Q / E | LB / RB (L1 / R1) | `ik_previous_panel`, `ik_next_panel` |
| Use / equip (mouse: double click) | U | Back / Select | `ik_use` |
| Sort the selected container | R | Right stick press | `ik_sort` |
| Turn the held item (grid inventories; mouse: middle click) | T | Left stick press (L3) | `ik_rotate` |

Hotbar actions (`ik_hotbar_1`…`9`, `ik_hotbar_next/previous`, `ik_hotbar_use`) are described in [standard_modules.md](standard_modules.md).

Keyboard defaults use **physical** keys, so WASD/Q/E stay in the same place on AZERTY or QWERTZ keyboards.

**Rebinding**: create an action with the same name in *Project Settings > Input Map*. The controller only adds the actions that do not exist yet, so your bindings always win.

| Touch | Effect |
|---|---|
| Tap | Pick up / put down |
| Drag from a slot to another | Move the stack |
| Long press (`long_press_time`, 0.45 s) | Take half / put one |
| Second finger tap while holding | Turn the held item (grid inventories) |

## Navigation

- Inside a grid, the selection moves by row and column. On a shorter last row, Down goes to the last slot.
- At the edge of a grid, it continues to the **nearest slot of another container in that direction on screen** (bag → equipment → chest…), whatever your layout.
- In a grid inventory (see recipes.md), one press moves past the whole item the selection is on; while an item is held, the selection moves cell by cell so you can aim, and the cells the item would cover light up (green: fits, red: does not).
- LB/RB (Q/E) jump between containers and remember the last slot used in each.
- Holding a direction repeats after `repeat_delay` (0.35 s), then every `repeat_interval` (0.09 s).

## Switching devices

The last device used wins:

- Moving the mouse hides the selection and shows the held stack under the pointer.
- Pressing a key or button shows the selection again. **The first press only shows it**, so a player picking up the controller never acts by accident.
- A mouse click moves the selection to the clicked slot, so switching back to the gamepad continues from there.
- While the selection is visible, the mouse hover highlight is hidden: only one highlight is ever on screen.

`input_mode_changed(mode)` (`MOUSE`, `FOCUS`, `TOUCH`) lets you swap button prompts or hide the pointer.

## Signals and properties

| Member | Purpose |
|---|---|
| `close_requested` | Cancel pressed with an empty hand: close the inventory screen. |
| `focus_changed(view, slot)` | Selection moved, e.g. to update a details panel. |
| `start_in_focus_mode` | Show the selection immediately (console, Steam Deck builds). |
| `enabled` | Pause the controller (e.g. while a dialog is open). |
| `handle_touch` | Handle touch directly. When on, the UI ignores the mouse events Godot emulates from touch, so a tap is never handled twice. |
| `focus_slot(view, slot)`, `move_focus(direction)`, `cycle_panel(step)` | Drive the selection from code. |

## Notes

- The controller reads input in `_input()` while its `IKInventoryUI` is visible, and marks handled events, so your game does not also receive them.
- It releases Godot's own GUI focus when the selection appears, so buttons elsewhere in your UI do not react to the same key.
