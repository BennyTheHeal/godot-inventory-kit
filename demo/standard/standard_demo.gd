extends IKInventoryUI
## Standard demo: equipment, weight-limited backpack, chest, hotbar, consumables, sort and
## filters, rich tooltips with equipment comparison, armor set bonuses, slot animations,
## keyboard / gamepad / touch, and a live art direction switcher (every art direction
## installed in addons/inventory_kit/art/ appears in the list).

const ART := "res://addons/inventory_kit/art/"
const DIRECTIONS := {"painted": "Hand-painted", "realistic": "Realistic", "cartoon": "Cartoon", "flat": "Flat"}
const WORLD_DEMO := "res://demo/world/world_demo.tscn"
const GRID_DEMO := "res://demo/grid/grid_demo.tscn"
const SAVE_PATH := "user://standard_demo/inventory.json"
const MAX_WEIGHT := 40.0
const EQUIPMENT_SLOTS: Array[StringName] = [&"head", &"body", &"hands", &"feet", &"weapon", &"offhand"]


class DemoPlayer extends Node:
	signal stats_changed
	var health := 60
	var mana := 10
	var stamina := 30
	var poisoned := true

	func can_heal(_amount: int) -> bool:
		return health < 100

	func heal(amount: int) -> void:
		health = mini(100, health + amount)
		stats_changed.emit()

	func can_restore_mana(_amount: int) -> bool:
		return mana < 50

	func restore_mana(amount: int) -> void:
		mana = mini(50, mana + amount)
		stats_changed.emit()

	func can_restore_stamina(_amount: int) -> bool:
		return stamina < 100

	func restore_stamina(amount: int) -> void:
		stamina = mini(100, stamina + amount)
		stats_changed.emit()

	func is_poisoned(_amount: int) -> bool:
		return poisoned

	func cure_poison(_amount: int) -> void:
		poisoned = false
		stats_changed.emit()


var player := DemoPlayer.new()
var bag: IKInventory
var chest: IKChest
var equipment: IKEquipment
var hotbar: IKHotbar
var controller: IKInputController
var tooltips: IKTooltipPresenter
var feedback: IKSlotFeedback
var bag_view: IKContainerView
var art_direction := ""
var _picker: OptionButton
var _status: Label
var _weight: Label
var _stats: Label
var _save := IKSaveFile.new(SAVE_PATH)


static func available_directions() -> Array[String]:
	var result: Array[String] = []
	for da in DIRECTIONS:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			result.append(da)
	return result


func _ready() -> void:
	var directions := available_directions()
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [directions[0], directions[0]])
	player.name = "Player"
	add_child(player)
	bag = IKInventory.new()
	_setup(bag, &"bag", 18, database, {&"oak_log": 8, &"health_potion": 3, &"mana_potion": 2, &"bread": 4,
		&"copper_ingot": 3, &"iron_chest": 1, &"iron_gloves": 1, &"sword": 1, &"antidote": 1})
	bag.container.rules.append(IKWeightRule.new(MAX_WEIGHT))
	chest = IKChest.new()
	_setup(chest, &"chest", 12, database, {&"iron_ore": 10, &"mithril_ingot": 3, &"ruby": 2, &"arrows": 60,
		&"dragon_helmet": 1, &"steel_gloves": 1, &"gold_coins": 250, &"diamond": 1})
	equipment = IKEquipment.new()
	equipment.slot_types = EQUIPMENT_SLOTS
	equipment.set_bonuses = load(ART + "shared/set_bonuses.tres")
	_setup(equipment, &"equipment", 0, database, {&"iron_helmet": 1})
	hotbar = IKHotbar.new()
	_setup(hotbar, &"hotbar", 8, database, {&"health_potion": 2, &"apple": 3, &"stamina_potion": 1})
	hotbar.user = player
	_build_layout(directions)
	super._ready()

	controller = IKInputController.new()
	controller.name = "InputController"
	controller.use_target = player
	controller.equipment = equipment
	add_child(controller)
	tooltips = IKTooltipPresenter.new()
	tooltips.name = "Tooltips"
	tooltips.shown_properties = [&"damage", &"armor", &"heal", &"mana", &"stamina", &"fire_resist", &"tier", &"value"]
	tooltips.equipment = equipment
	add_child(tooltips)
	feedback = IKSlotFeedback.new()
	feedback.name = "Feedback"
	add_child(feedback)

	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))
	controller.input_mode_changed.connect(func(mode: IKInputController.Mode) -> void:
		_set_status("Input: %s" % IKInputController.Mode.keys()[mode].capitalize()))
	controller.item_used.connect(func(definition: IKUsableItem, _stack: IKItemStack) -> void:
		_set_status("Used %s." % definition.display_name))
	controller.close_requested.connect(func() -> void: _set_status("Cancel with empty hands: a game would close the inventory."))
	hotbar.item_used.connect(func(stack: IKItemStack) -> void: _set_status("Hotbar: used %s." % stack.item_id))
	equipment.equipped.connect(func(_slot: StringName, _stack: IKItemStack) -> void: _refresh_stats())
	equipment.unequipped.connect(func(_slot: StringName, _stack: IKItemStack) -> void: _refresh_stats())
	equipment.set_bonus_changed.connect(func(bonus: IKSetBonus, active: bool) -> void:
		_set_status("%s (%d pieces): %s %s." % [bonus.get_set_name(), bonus.pieces_required, bonus.describe(),
			"active" if active else "lost"], not active))
	player.stats_changed.connect(_refresh_stats)
	bag.container.changed.connect(_refresh_weight)
	apply_art_direction(directions[0])


## Swaps icons, slot skin and window theme. Items keep their ids, so nothing in the
## containers changes: only the look.
func apply_art_direction(da: String) -> void:
	art_direction = da
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [da, da])
	for node in [bag, chest, equipment, hotbar]:
		node.container.database = database
	cursor.container.database = database
	theme = load(ART + "%s/%s_theme.tres" % [da, da])
	skin = load(ART + "%s/%s_skin.tres" % [da, da])  # restyles every view and the held item
	tooltips.panel_style = theme.get_stylebox(&"panel", &"TooltipPanel")
	var index := available_directions().find(da)
	if _picker != null and index >= 0 and _picker.selected != index:
		_picker.select(index)
	_refresh_weight()
	_refresh_stats()


func _setup(node: IKInventory, id: StringName, slots: int, database: IKItemDatabase, items: Dictionary) -> void:
	node.name = String(id).capitalize()
	node.container_id = id
	if not node is IKEquipment:
		node.size = slots
	node.database = database
	node.initial_items.assign(items)
	add_child(node)


func _build_layout(directions: Array[String]) -> void:
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
	title.text = "Inventory Kit — Full demo (free)"
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)
	_picker = OptionButton.new()
	for da in directions:
		_picker.add_item(DIRECTIONS[da])
	_picker.item_selected.connect(func(index: int) -> void: apply_art_direction(directions[index]))
	_picker.tooltip_text = "Art direction"
	header.add_child(_picker)
	var site := LinkButton.new()
	site.text = "More free kits & our games »"
	site.uri = "https://banc-essai.site-testeurs.workers.dev/?src=ik-demo"
	site.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(site)

	var panels := HBoxContainer.new()
	panels.add_theme_constant_override(&"separation", 14)
	column.add_child(panels)

	var equipment_box := _panel(panels, "Equipment")
	var equipment_view := _view(equipment_box, equipment, 2)
	var outlines: Array[Texture2D] = []
	for slot_type in EQUIPMENT_SLOTS:
		outlines.append(load(ART + "shared/silhouettes/%s.png" % slot_type))
	equipment_view.empty_icons = outlines
	_stats = Label.new()
	equipment_box.add_child(_stats)

	var bag_box := _panel(panels, "Backpack")
	_weight = Label.new()
	bag_box.add_child(_weight)
	bag_view = _view(bag_box, bag, 6)
	var tools := HBoxContainer.new()
	bag_box.add_child(tools)
	var filter := OptionButton.new()
	for label in ["All", "Consumables", "Equipment", "Resources"]:
		filter.add_item(label)
	filter.item_selected.connect(_on_filter_selected)
	tools.add_child(filter)
	var search := LineEdit.new()
	search.placeholder_text = "Search…"
	search.custom_minimum_size = Vector2(110, 0)
	search.text_changed.connect(func(text: String) -> void: bag_view.filter = IKItemFilter.text(text))
	tools.add_child(search)
	_button(tools, "Sort", func() -> void: report_result(IKSorter.sort(bag.container)))

	var chest_box := _panel(panels, "Chest")
	var chest_view := _view(chest_box, chest, 4)
	_button(chest_box, "Take all", _on_take_all)

	var hotbar_box := _panel(column, "Hotbar — keys 1-8 or mouse wheel to select, gamepad right trigger to use")
	var hotbar_view := _view(hotbar_box, hotbar, 8)
	hotbar.view = hotbar_view

	bag_view.quick_move_target = chest_view
	chest_view.quick_move_target = bag_view
	hotbar_view.quick_move_target = bag_view
	equipment_view.quick_move_target = bag_view

	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	_button(buttons, "Use hotbar item", func() -> void: report_result(hotbar.use_selected()))
	_button(buttons, "Save", _on_save)
	_button(buttons, "Load", _on_load)
	if ResourceLoader.exists(WORLD_DEMO):
		_button(buttons, "World pickups demo", func() -> void: get_tree().change_scene_to_file(WORLD_DEMO))
	if ResourceLoader.exists(GRID_DEMO):
		_button(buttons, "Grid inventory demo", func() -> void: get_tree().change_scene_to_file(GRID_DEMO))
	var help := Button.new()
	help.text = "Controls (hover)"
	help.flat = true
	help.tooltip_text = "Mouse: click, right click, shift+click, drag; double click uses or equips.
" 		+ "Gamepad: move, A pick/put, X half/one, Y send, Back use, R3 sort, B put back, LB/RB switch.
" 		+ "Keyboard: arrows/WASD, Enter, X, F, U use, R sort, Esc, Q/E.
Touch: tap, drag, long press."
	buttons.add_child(help)
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


func _view(parent: Control, inventory: IKInventory, columns: int) -> IKContainerView:
	var view := IKContainerView.new()
	view.name = String(inventory.container_id).capitalize() + "View"
	view.columns = columns
	view.inventory = inventory
	parent.add_child(view)
	return view


func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_filter_selected(index: int) -> void:
	match index:
		1:
			bag_view.filter = IKItemFilter.category(&"consumable")
		2:
			bag_view.filter = IKItemFilter.equippable()
		3:
			bag_view.filter = IKItemFilter.any([IKItemFilter.category(&"resource"), IKItemFilter.category(&"material")])
		_:
			bag_view.filter = Callable()


func _on_take_all() -> void:
	var result := chest.take_all(bag.container)
	report_result(result)
	if result.ok:
		_set_status("Took everything." if result.remainder == 0 else "%d items did not fit (weight or space)." % result.remainder,
			result.remainder > 0)


func _containers() -> Array:
	return [bag.container, chest.container, equipment.container, hotbar.container]


func _on_save() -> void:
	return_held()
	var error := _save.save(_containers())
	_set_status("Saved." if error == OK else "Save failed: %s" % error_string(error), error != OK)


func _on_load() -> void:
	return_held()
	var report := _save.load_into(_containers())
	_set_status(report.error if not report.ok else "Loaded (%d warnings)." % report.warnings.size(), not report.ok)


func _refresh_weight() -> void:
	if _weight != null:
		_weight.text = "Weight %.1f / %.0f" % [IKWeightRule.weight_of(bag.container), MAX_WEIGHT]


func _refresh_stats() -> void:
	if _stats == null:
		return
	var sets := PackedStringArray()
	for bonus in equipment.get_active_set_bonuses():
		sets.append("%s (%d)" % [bonus.get_set_name(), bonus.pieces_required])
	_stats.text = "HP %d · MP %d · SP %d%s\nArmor %d · Damage %d%s" % [player.health, player.mana, player.stamina,
		" · poisoned" if player.poisoned else "", equipment.sum_property(&"armor"), equipment.sum_property(&"damage"),
		"\n" + "\n".join(sets) if not sets.is_empty() else ""]


func _set_status(text: String, warning: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
