extends "res://tests/inventory_kit/ik_test_case.gd"
## The bundled art library: every art direction has the same 120 items, valid
## definitions, icons, a skin and a theme.

const ART := "res://addons/inventory_kit/art/"
const ALL_DIRECTIONS := ["painted", "realistic", "cartoon", "flat"]
const SLOT_STATES := [&"slot_normal", &"slot_hover", &"slot_focus", &"slot_rejected", &"slot_marked"]

## Art directions installed in this edition (Lite: sample only, Full: all four).
var DIRECTIONS: Array = ALL_DIRECTIONS.filter(func(da: String) -> bool:
	return ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]))


func test_edition_has_at_least_one_art_direction() -> void:
	assert_true(DIRECTIONS.has("painted"), "every paid edition includes the hand-painted set")


func _database(da: String) -> IKItemDatabase:
	return load(ART + "%s/%s_items.tres" % [da, da])


func test_every_art_direction_has_the_same_valid_items() -> void:
	var reference := _database("painted").get_ids()
	reference.sort()
	assert_eq(reference.size(), 120)
	for da in DIRECTIONS:
		var database := _database(da)
		assert_eq(database.validate().size(), 0, "%s: %s" % [da, database.validate()])
		var ids := database.get_ids()
		ids.sort()
		assert_eq(ids, reference, "%s has the same ids" % da)
		for definition in database.items:
			if definition.icon == null:
				fail("%s/%s has no icon" % [da, definition.id])
			elif definition.icon.get_width() != 128:
				fail("%s/%s icon is %d px" % [da, definition.id, definition.icon.get_width()])
			if definition.display_name.is_empty():
				fail("%s/%s has no name" % [da, definition.id])


func test_items_are_usable_and_equippable() -> void:
	var database := _database("painted")
	var potion := database.get_item(&"health_potion")
	assert_true(potion is IKUsableItem, "consumables are IKUsableItem in the Standard library")
	assert_eq((potion as IKUsableItem).effects.size(), 1)
	assert_eq(database.get_item(&"dragon_helmet").equip_slot, &"head")
	assert_eq(database.get_item(&"steel_boots").equip_slot, &"feet")
	assert_true(database.get_item(&"dragon_chest").unique)
	assert_eq(database.get_item(&"oak_log").max_stack, 50)
	assert_eq(typeof(database.get_item(&"steel_chest").properties.armor), TYPE_INT, "whole numbers stay ints")


func test_tiers_increase_armor() -> void:
	var database := _database("painted")
	var previous := 0
	for set_id in ["cloth", "bronze", "iron", "steel", "gold", "mithril", "adamantite", "dragon"]:
		var armor: int = database.get_item(StringName(set_id + "_chest")).properties.armor
		assert_true(armor > previous, "%s chest armor %d above previous tier" % [set_id, armor])
		previous = armor


func test_skins_and_themes_load() -> void:
	for da in DIRECTIONS:
		var skin: IKSkin = load(ART + "%s/%s_skin.tres" % [da, da])
		for state in SLOT_STATES:
			assert_true(skin.get(state) is StyleBox, "%s skin has %s" % [da, state])
		var theme: Theme = load(ART + "%s/%s_theme.tres" % [da, da])
		for pair in [[&"panel", &"PanelContainer"], [&"panel", &"TooltipPanel"], [&"normal", &"Button"], [&"pressed", &"Button"]]:
			assert_true(theme.has_stylebox(pair[0], pair[1]), "%s theme has %s/%s" % [da, pair[1], pair[0]])
	if DIRECTIONS.has("flat"):
		var flat_skin: IKSkin = load(ART + "flat/flat_skin.tres")
		assert_true(flat_skin.slot_normal is StyleBoxFlat, "the flat UI is drawn in code, crisp at any size")


func test_lite_sample_uses_core_classes_only() -> void:
	var database: IKItemDatabase = load(ART + "lite/lite_items.tres")
	assert_eq(database.items.size(), 10)
	assert_eq(database.validate().size(), 0)
	for definition in database.items:
		assert_false(definition is IKUsableItem, "%s must not need the Standard edition" % definition.id)
		assert_true(definition.icon != null)
	if not OS.has_feature("template"):  # exported games convert .tres files
		var source := FileAccess.get_file_as_string(ART + "lite/lite_items.tres")
		assert_false(source.contains("/pro/"), "the Lite sample references no pro script")


func test_silhouettes_exist() -> void:
	for slot in ["head", "body", "hands", "feet", "weapon", "offhand", "ring", "amulet"]:
		var texture: Texture2D = load(ART + "shared/silhouettes/%s.png" % slot)
		assert_true(texture != null and texture.get_width() == 128, slot)


func test_demo_switches_art_direction_live() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	var demo: IKInventoryUI = load("res://demo/standard/standard_demo.tscn").instantiate()
	add_to_tree(demo)
	await wait_frames(2)
	assert_eq(demo.available_directions(), DIRECTIONS)
	var before: Array = []
	for container in demo._containers():
		before.append(container.to_debug_array())
	var order := DIRECTIONS.duplicate()
	order.reverse()
	for da in order:
		demo.apply_art_direction(da)
		await wait_frames(1)
		assert_eq(demo.art_direction, da)
		var slot_view: IKSlotView = demo.bag_view.get_slot_view(0)
		assert_eq(slot_view.get_icon_texture().resource_path,
			ART + "%s/icons/%s.png" % [da, slot_view.get_item_stack().item_id], "icons follow the art direction")
		assert_eq(demo.skin.resource_path, ART + "%s/%s_skin.tres" % [da, da])
	var after: Array = []
	for container in demo._containers():
		after.append(container.to_debug_array())
	assert_eq(after, before, "switching art direction never touches the items")
