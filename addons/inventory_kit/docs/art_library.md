# Inventory Kit — Art library

Ready-made items, icons and UI skins in `addons/inventory_kit/art/`.

| Edition | Included |
|---|---|
| Lite | `art/lite/`: 10 sample icons and `lite_items.tres` |
| Full | all four art directions: `painted`, `realistic`, `cartoon`, `flat`, and `art/shared/` |
| Art pack (free, separate download) | one art direction: PNG files usable in any engine, plus its Godot resources |

## What each art direction contains

| File | Content |
|---|---|
| `<da>_items.tres` | `IKItemDatabase` with **120 items**: names, descriptions, categories, stack sizes, weights, equipment slots and stats |
| `<da>_skin.tres` | `IKSkin`: slot styles (normal, hover, focus, rejected, marked) |
| `<da>_theme.tres` | `Theme`: `PanelContainer`, `Panel`, `Button` (4 states), `TooltipPanel`, text colors |
| `icons/*.png` | 128 × 128 icons, transparent background |
| `ui/*.png` | 9-slice frames (slots, panels, buttons, tooltip) |

`art/shared/silhouettes/` holds 8 outlines for empty equipment slots: head, body, hands, feet, weapon, offhand, ring and amulet.

**Every art direction uses the same item ids.** Switching art direction only changes the look, never your save files:

```gdscript
var database: IKItemDatabase = load("res://addons/inventory_kit/art/cartoon/cartoon_items.tres")
bag.container.database = database          # same items, cartoon icons
inventory_ui.cursor.container.database = database
inventory_ui.theme = load("res://addons/inventory_kit/art/cartoon/cartoon_theme.tres")
inventory_ui.skin = load("res://addons/inventory_kit/art/cartoon/cartoon_skin.tres")  # restyles every view
```

The Standard demo (`demo/standard/standard_demo.tscn`) has a live art direction picker that does exactly this.

## The 120 items

| Group | Items |
|---|---|
| Basics | wood_log, stone, iron_ore, iron_ingot, leather, cloth, herb, crystal |
| Consumables | health_potion, mana_potion, stamina_potion, antidote, bread, apple, cheese, roast_meat |
| Weapons | sword, axe, bow, dagger, staff, mace, spear, shield |
| Gear | helmet, chest_armor, gloves, boots, ring, amulet, cloak, belt |
| Misc | key, gold_coins, map, scroll, ruby, sapphire, arrows, torch |
| Woods (tiers 1–5) | oak, pine, birch, ebony, ancient — as `_log` and `_planks` |
| Stones | granite, marble, obsidian, clay, sand, coal |
| Metals | ores: copper, tin, silver, gold, mithril, adamantite · ingots: copper, tin, bronze, steel, silver, gold, mithril, adamantite · iron_nugget, gold_nugget |
| Organics and gems | plant_fiber, linen_thread, wool, silk, rawhide, hardened_leather, scaled_hide, bone, feather, resin, rough_amethyst, amethyst, emerald, topaz, diamond, magic_essence |
| Armor sets (tiers 1–8) | cloth, bronze, iron, steel, gold, mithril, adamantite, dragon — each as `_helmet`, `_chest`, `_gloves`, `_boots` |

`properties` holds `tier`, `rarity` (common to legendary, colored in rich tooltips), `value`, and `damage`, `armor`, `heal`, `mana`, `stamina` where relevant. Armor grows with the tier, so the sets form a ready-made progression.

**Consumables** are `IKUsableItem` with an `IKCallMethodEffect`. For example, `health_potion` calls `heal(50)` on the user, but only if `can_heal(50)` returns true. Give your player node these methods, or replace the effects with your own:

| Method on the user | Used by |
|---|---|
| `heal(amount)` / `can_heal(amount)` | health potion, food |
| `restore_mana(amount)` / `can_restore_mana(amount)` | mana potion |
| `restore_stamina(amount)` / `can_restore_stamina(amount)` | stamina potion |
| `cure_poison(amount)` / `is_poisoned(amount)` | antidote |

The Lite sample uses plain `IKItemDefinition` resources (no Standard classes).

## Using only some items

Duplicate a database, remove the items you do not need, or build your own `IKItemDatabase` from the `.tres` items you want. Icons are plain PNG files and can be used anywhere.

## License

The art is free and may be used in commercial and non-commercial games. It may not be sold or re-uploaded on its own, as an asset pack or in a template: link to the official page instead (https://banc-essai.site-testeurs.workers.dev/inventory-kit/). The icons and UI art were generated with AI image tools, then curated, processed and checked by hand.
