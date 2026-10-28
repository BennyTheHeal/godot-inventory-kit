extends IKInventoryUI
## Grid inventory demo (Diablo / Resident Evil style): items take several cells,
## turn a quarter turn, swap, stack and pack themselves; a classic belt sits next
## to the grids to show that both modes mix. Keyboard, gamepad, mouse and touch.

const ART := "res://addons/inventory_kit/art/"
const STANDARD_DEMO := "res://demo/standard/standard_demo.tscn"
const SAVE_PATH := "user://grid_demo/inventory.json"
## Cells per item (width x height). Everything else takes one cell.
const GRID_SIZES := {
	&"sword": Vector2i(1, 3), &"axe": Vector2i(2, 3), &"bow": Vector2i(2, 3), &"dagger": Vector2i(1, 2),
	&"staff": Vector2i(1, 4), &"mace": Vector2i(1, 3), &"spear": Vector2i(1, 4), &"shield": Vector2i(2, 2),
	&"cloak": Vector2i(2, 3), &"belt": Vector2i(2, 1), &"map": Vector2i(2, 2), &"scroll": Vector2i(1, 2),
	&"torch": Vector2i(1, 2), &"arrows": Vector2i(1, 2), &"roast_meat": Vector2i(2, 1), &"bread": Vector2i(2, 1),
	&"oak_log": Vector2i(2, 1), &"wood_log": Vector2i(2, 1), &"iron_chest": Vector2i(2, 3), &"cheese": Vector2i(1, 1),
}
const SIZES_BY_SUFFIX := {"_helmet": Vector2i(2, 2), "_chest": Vector2i(2, 3), "_gloves": Vector2i(2, 2),
	"_boots": Vector2i(2, 2)}
const LOOT := [&"sword", &"axe", &"bow", &"dagger", &"shield", &"spear", &"steel_helmet", &"gold_chest",
	&"health_potion", &"mana_potion", &"ruby", &"oak_log", &"arrows", &"bread", &"map", &"gold_coins"]

var backpack: IKInventory
var stash: IKInventory
var belt: IKInventory
var controller: IKInputController
var tooltips: IKTooltipPresenter
var backpack_view: IKContainerView
var stash_view: IKContainerView
var belt_view: IKContainerView
var _status: Label
var _save := IKSaveFile.new(SAVE_PATH)
var _rng := RandomNumberGenerator.new()


## A copy of an item library where weapons and armor take several cells.
static func make_grid_database(source: IKItemDatabase) -> IKItemDatabase:
	var database := IKItemDatabase.new()
	for item in source.items:
		if item == null:
			continue
		var copy: IKItemDefinition = item.duplicate()
		copy.grid_size = _size_for(String(copy.id))
		database.add_item(copy)
	return database


static func _size_for(id: String) -> Vector2i:
	if GRID_SIZES.has(StringName(id)):
		return GRID_SIZES[StringName(id)]
	for suffix in SIZES_BY_SUFFIX:
		if id.ends_with(suffix):
			return SIZES_BY_SUFFIX[suffix]
	return Vector2i.ONE


static func _art_direction() -> String:
	for da in ["painted", "realistic", "cartoon", "flat"]:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			return da
	return ""


func _ready() -> void:
	var da := _art_direction()
	var database := make_grid_database(load(ART + "%s/%s_items.tres" % [da, da]))
	theme = load(ART + "%s/%s_theme.tres" % [da, da])
	skin = load(ART + "%s/%s_skin.tres" % [da, da])
	backpack = _make(&"grid_backpack", 10, 6, database, {&"sword": 1, &"shield": 1, &"iron_chest": 1, &"bow": 1,
		&"health_potion": 4, &"arrows": 40, &"bread": 3, &"ruby": 2})
	stash = _make(&"grid_stash", 6, 5, database, {&"axe": 1, &"spear": 1, &"steel_helmet": 1, &"map": 1,
		&"gold_coins": 120, &"oak_log": 12})
	belt = _make(&"belt", 0, 4, database, {&"mana_potion": 2})
	_build_layout()
	super._ready()

	controller = IKInputController.new()
	controller.name = "InputController"
	add_child(controller)
	tooltips = IKTooltipPresenter.new()
	tooltips.name = "Tooltips"
	tooltips.shown_properties = [&"damage", &"armor", &"heal", &"mana", &"value"]
	tooltips.panel_style = theme.get_stylebox(&"panel", &"TooltipPanel")
	add_child(tooltips)
	add_child(IKSlotFeedback.new())
	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))
	controller.input_mode_changed.connect(func(mode: IKInputController.Mode) -> void:
		_set_status("Input: %s" % IKInputController.Mode.keys()[mode].capitalize()))


## [param width] 0 = classic slots ([param height] slots).
func _make(id: StringName, width: int, height: int, database: IKItemDatabase, items: Dictionary) -> IKInventory:
	var inventory := IKInventory.new()
	inventory.name = String(id).capitalize()
	inventory.container_id = id
	inventory.grid_width = width
	inventory.size = width * height if width > 0 else height
	inventory.database = database
	inventory.initial_items.assign(items)
	add_child(inventory)
	return inventory


func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	center.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	column.add_child(header)
	var title := Label.new()
	title.text = "Inventory Kit — Grid inventory demo"
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)
	var site := LinkButton.new()
	site.text = "More free kits & our games »"
	site.uri = "https://banc-essai.site-testeurs.workers.dev/?src=ik-grid"
	site.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(site)

	var panels := HBoxContainer.new()
	panels.add_theme_constant_override(&"separation", 14)
	column.add_child(panels)
	var backpack_box := _panel(panels, "Backpack (10 × 6 grid)")
	backpack_view = _view(backpack_box, backpack)
	var side := VBoxContainer.new()
	side.add_theme_constant_override(&"separation", 14)
	panels.add_child(side)
	var stash_box := _panel(side, "Stash (6 × 5 grid)")
	stash_view = _view(stash_box, stash)
	var belt_box := _panel(side, "Belt (classic slots)")
	belt_view = _view(belt_box, belt, 4)
	backpack_view.quick_move_target = stash_view
	stash_view.quick_move_target = backpack_view
	belt_view.quick_move_target = backpack_view

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons, "Rotate held item", func() -> void: rotate_held())
	_button(buttons, "Random loot", _on_loot)
	_button(buttons, "Sort backpack", func() -> void: report_result(IKSorter.sort(backpack.container)))
	_button(buttons, "Save", _on_save)
	_button(buttons, "Load", _on_load)
	if ResourceLoader.exists(STANDARD_DEMO):
		_button(buttons, "Back to the inventory demo", func() -> void: get_tree().change_scene_to_file(STANDARD_DEMO))
	var help := Label.new()
	help.text = "Mouse: click to pick / put (the top-left cell goes where you point), right click half / one, " \
		+ "middle click rotates, shift+click sends.\nKeyboard: arrows, Enter, X, F, T rotates, R sorts.  " \
		+ "Gamepad: A, X, Y, L3 rotates, R3 sorts.  Touch: tap, drag, long press, second finger rotates."
	help.modulate = Color(1, 1, 1, 0.7)
	column.add_child(help)
	_status = Label.new()
	column.add_child(_status)


func _panel(parent: Control, title: String) -> VBoxContainer:
	var frame := PanelContainer.new()
	parent.add_child(frame)
	var box := VBoxContainer.new()
	frame.add_child(box)
	var label := Label.new()
	label.text = title
	box.add_child(label)
	return box


func _view(parent: Control, inventory: IKInventory, columns: int = 0) -> IKContainerView:
	var view := IKContainerView.new()
	view.name = String(inventory.container_id).capitalize() + "View"
	view.columns = maxi(1, columns)  # grid views take the grid width themselves
	view.inventory = inventory
	parent.add_child(view)
	return view


func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_loot() -> void:
	var item_id: StringName = LOOT[_rng.randi_range(0, LOOT.size() - 1)]
	var definition := backpack.container.database.get_item(item_id)
	var amount := 1 if definition == null or definition.get_effective_max_stack() == 1 else _rng.randi_range(1, 6)
	var result := backpack.container.add(item_id, amount, true)
	var label := IKText.item_name(definition) if definition != null else String(item_id)
	var cells := definition.get_grid_size() if definition != null else Vector2i.ONE
	if not result.ok:
		_set_status("No room for %s (%dx%d): rotate or sort to make space." % [label, cells.x, cells.y], true)
	else:
		_set_status("Looted %d %s." % [amount - result.remainder, label])


func _containers() -> Array:
	return [backpack.container, stash.container, belt.container]


func _on_save() -> void:
	return_held()
	var error := _save.save(_containers())
	_set_status("Saved." if error == OK else "Save failed: %s" % error_string(error), error != OK)


func _on_load() -> void:
	return_held()
	var report := _save.load_into(_containers())
	_set_status(report.error if not report.ok else "Loaded (%d warnings)." % report.warnings.size(), not report.ok)


func _set_status(text: String, warning: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
