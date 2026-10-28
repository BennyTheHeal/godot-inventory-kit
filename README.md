# Inventory Kit for Godot 4

An inventory system for Godot 4 that works with a gamepad, saves without ever losing or duplicating items, and looks finished from the first run.

**Free and open source (MIT).** Made by Benny, with AI tools.

- Official page, playable web demo and the download with the full art: https://banc-essai.site-testeurs.workers.dev/inventory-kit/
- itch.io: https://elliottfhotmailfr.itch.io/inventory-kit-godot
- More kits, and our game prototypes waiting for testers: https://banc-essai.site-testeurs.workers.dev/

![Inventory Kit screenshot](https://banc-essai.site-testeurs.workers.dev/img/ik-1.jpg)

*Screenshot with the full art from the official page. This repository ships placeholder art, see below.*

## Install

- **From the Asset Library** (inside the Godot editor, *AssetLib* tab): search for "Inventory Kit", download, install. Only the `addons/` folder is installed.
- **By hand**: copy `addons/inventory_kit/` into your project's `addons/` folder.

Documentation: [`addons/inventory_kit/README.md`](addons/inventory_kit/README.md).

## Demo and tests

This repository is a ready-to-open Godot 4.5+ project.

- Open it in Godot and run `demo/standard/standard_demo.tscn`.
- Tests: `godot --headless --path . --import` then `godot --headless --path . -s res://tests/inventory_kit/run_tests.gd`

## About the art

The item icons and UI frames in `addons/inventory_kit/art/` are **placeholders** (coloured shapes with the item initials, drawn by a script, MIT). Same file names and sizes as the real art, so everything works with them. The hand-made art (120 items in 4 art directions with matching UI skins) is free, pay what you want from $0, on the [official page](https://banc-essai.site-testeurs.workers.dev/inventory-kit/): drop its `addons/inventory_kit/art/` folder over this one.

## License

MIT, see [LICENSE](LICENSE).
