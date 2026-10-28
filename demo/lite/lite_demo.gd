extends IKInventoryUI
## Lite demo: a backpack and a chest, mouse controls, save and load.

const ITEMS := preload("res://addons/inventory_kit/art/lite/lite_items.tres")
const SAVE_PATH := "user://lite_demo/inventory.json"
const LOOT := [&"wood_log", &"stone", &"apple", &"health_potion", &"mana_potion", &"arrows", &"ruby", &"gold_coins",
	&"sword", &"helmet"]

var bag: IKInventory
var chest: IKInventory
var _status: Label
var _save := IKSaveFile.new(SAVE_PATH)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var database: IKItemDatabase = ITEMS
	bag = _make_inventory(&"bag", 24, database, {&"wood_log": 12, &"apple": 4, &"sword": 1, &"health_potion": 3})
	chest = _make_inventory(&"chest", 12, database, {&"stone": 30, &"arrows": 60, &"helmet": 1, &"ruby": 2, &"gold_coins": 150})
	_build_layout()
	super._ready()
	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))


func _make_inventory(id: StringName, slots: int, database: IKItemDatabase, items: Dictionary) -> IKInventory:
	var inventory := IKInventory.new()
	inventory.name = String(id).capitalize()
	inventory.container_id = id
	inventory.size = slots
	inventory.database = database
	inventory.initial_items.assign(items)
	add_child(inventory)
	return inventory


func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.11)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	center.add_child(column)

	var title := Label.new()
	title.text = _title()
	title.add_theme_font_size_override(&"font_size", 26)
	column.add_child(title)
	var site := LinkButton.new()
	site.text = "Free download, more kits & our games: banc-essai.site-testeurs.workers.dev"
	site.uri = "https://banc-essai.site-testeurs.workers.dev/?src=ik-lite"
	column.add_child(site)

	var panels := HBoxContainer.new()
	panels.add_theme_constant_override(&"separation", 32)
	column.add_child(panels)
	var bag_view := _add_panel(panels, "Backpack", bag, 6)
	var chest_view := _add_panel(panels, "Chest", chest, 4)
	bag_view.quick_move_target = chest_view
	chest_view.quick_move_target = bag_view

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	column.add_child(buttons)
	_add_button(buttons, "Random loot", _on_loot)
	_add_button(buttons, "Save", _on_save)
	_add_button(buttons, "Load", _on_load)
	_add_button(buttons, "Clear backpack", _on_clear)

	var help := Label.new()
	help.text = _help_text()
	help.modulate = Color(1, 1, 1, 0.7)
	column.add_child(help)
	_status = Label.new()
	column.add_child(_status)


func _title() -> String:
	return "Inventory Kit — Lite demo"


func _help_text() -> String:
	return "Left click: pick up / put down  ·  Right click: take half / put one\n" \
		+ "Shift + click: send to the other container  ·  Drag and drop works too"


func _add_panel(parent: Control, title: String, inventory: IKInventory, columns: int) -> IKContainerView:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var label := Label.new()
	label.text = title
	box.add_child(label)
	var view := IKContainerView.new()
	view.name = title + "View"
	view.columns = columns
	view.inventory = inventory
	box.add_child(view)
	return view


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_loot() -> void:
	var item_id: StringName = LOOT[_rng.randi_range(0, LOOT.size() - 1)]
	var amount := _rng.randi_range(1, 8)
	var result := bag.container.add(item_id, amount, true)
	if not result.ok:
		_set_status("Backpack full: %d %s lost." % [amount, item_id], true)
	elif result.remainder > 0:
		_set_status("Looted %d %s, %d did not fit." % [amount - result.remainder, item_id, result.remainder], true)
	else:
		_set_status("Looted %d %s." % [amount, item_id])


func _on_save() -> void:
	return_held()
	var error := _save.save([bag.container, chest.container])
	_set_status("Saved." if error == OK else "Save failed: %s" % error_string(error), error != OK)


func _on_load() -> void:
	return_held()
	var report := _save.load_into([bag.container, chest.container])
	if not report.ok:
		_set_status(report.error, true)
		return
	_set_status("Loaded from %s file (%d warnings)." % [report.source, report.warnings.size()])


func _on_clear() -> void:
	return_held()
	var tx := IKTransaction.new()
	for slot in bag.container.size():
		if not bag.container.is_slot_empty(slot):
			tx.remove_at(bag.container, slot)
	tx.commit()
	_set_status("Backpack cleared.")


func _set_status(text: String, warning: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
