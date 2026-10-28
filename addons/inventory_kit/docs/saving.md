# Inventory Kit — Saving and loading

Two levels, use whichever fits your game:

| Option | Use it when |
|---|---|
| `IKSaveFile` | You want a ready-made, crash-safe file with automatic backups. |
| `IKSerializer` | You already have a save system: embed the Dictionary it produces. |

## IKSaveFile (recommended)

```gdscript
var save := IKSaveFile.new("user://slot1/inventory.json")

# Save
var error := save.save([bag, equipment, chest])

# Load
var report := save.load_into([bag, equipment, chest])
if not report.ok:
	push_warning(report.error)          # e.g. "No save file at ..." on a new game
for lost in report.overflow:            # items that could not be placed back
	spawn_pickup(lost.stack, lost.container_id)
```

### What makes it crash-safe

1. The new save is written to `inventory.json.tmp`, then read back and verified.
2. The current `inventory.json` becomes `inventory.json.bak`. It is only kept as a backup if it is valid; a damaged file is renamed `.corrupt` instead, so it never replaces a good backup.
3. The temp file is renamed to `inventory.json`.

Each file starts with a header line containing a SHA-256 checksum of the content. A truncated or hand-edited file is detected.

When loading, `load_into()` tries the main file, then `.tmp` (a save interrupted just before step 3), then `.bak`. `report.source` tells you which one was used ("main", "tmp" or "backup"), and `report.warnings` lists the damaged files that were skipped.

A file with a **valid** checksum is never skipped. If its content is refused (for example a save written by a newer build of your game), loading fails instead of silently restoring older data that the next save would then overwrite.

Containers present in the file but not passed to `load_into()` (e.g. a bank you load later) are kept and written back on the next `save()`.

## IKSerializer (bring your own save system)

```gdscript
var data := IKSerializer.to_dict([bag, equipment])   # plain, JSON-safe Dictionary
my_save["inventory"] = data
# ...
var report := IKSerializer.load_into(my_save["inventory"], [bag, equipment])
```

`to_dict()` output works with `JSON.stringify`, `var_to_bytes`, `store_var` or any other format.

## Format (version 1)

```json
{
  "format": "inventory_kit",
  "version": 1,
  "containers": {
    "player_bag": {
      "size": 24,
      "slots": [
        {"i": 0, "id": "wood", "n": 12},
        {"i": 5, "id": "iron_sword", "n": 1, "uid": "9f2c…",
         "data": {"type": "Dictionary", "args": ["s:durability", "i:37"]}}
      ]
    }
  }
}
```

- Only occupied slots are written, with their index `i`.
- `data` is type-tagged (`JSON.from_native`): Godot's JSON parser turns every number into a float, and `{"a": 37} != {"a": 37.0}`. Without tagging, loaded items would stop stacking with new ones. Hand-written plain objects are also accepted.
- Objects are never deserialized from `data`, so a modified save cannot inject code.
- Grid containers (1.2): `i` is the cell of the item's top-left corner, and turned items carry `"rot": true`. Nothing else changes: version 1 saves from 1.0 / 1.1 load unchanged, and a grid save loads into classic slots (and back).

## Loading rules

Loading is **all or nothing** for structural problems. If any of these occurs, no container changes and `report.ok` is false:

- not an Inventory Kit document, missing or invalid version;
- version newer than this build;
- a malformed container entry;
- duplicate or empty container ids in the list you pass.

Item-level problems are **repaired** and listed in `report.warnings`:

| Situation | What happens |
|---|---|
| Slot index no longer exists (container got smaller) | Item moved to another slot (merged if possible), else `overflow` |
| Slot rule no longer accepts the item | Same as above |
| Same slot index listed twice | Same as above |
| Grid: the item no longer fits at its cell (overlap, smaller grid, bigger `grid_size`) | Placed in the first cell where it fits, turned if needed, else `overflow` |
| Amount above `max_stack` | Split into several slots, rest to `overflow` |
| Unique item without uid | A new uid is assigned |
| Same uid twice (duplicated item) | Only the first copy is kept; the others are removed and counted in `dropped` |
| Unreadable entry (no id, bad amount) | Dropped and counted in `dropped` |
| Item id missing from the database | Kept untouched in its slot (`unknown_items`) and saved again as-is; it cannot be moved. Set `IKLoadOptions.keep_unknown_items = false` to drop it instead. |

Containers missing from the save are left as they are (useful when a game update adds a new container).

Loading emits `slots_changed` and `changed`, but never `item_added` / `item_removed`: restoring a save is not gameplay, so quests do not count it. Transactions prepared before the load are rejected as stale.

## Renamed items

```gdscript
var options := IKLoadOptions.new()
options.item_aliases = {&"iron_sword": &"sword_iron"}
save.load_into([bag], options)
```

## Format migrations

The format version is checked on every load. When a future version of Inventory Kit changes the format, its migration steps upgrade older saves automatically, one version at a time. You can also chain your own steps:

```gdscript
var migrations := IKMigrations.new()
migrations.target_version = 2
migrations.register(1, func(doc: Dictionary) -> Dictionary:
	# change doc from v1 to v2
	return doc)
```
