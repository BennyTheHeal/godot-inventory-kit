class_name IKPickupNotifier
extends VBoxContainer
## Short "+5 Oak Log" lines with the item icon, merged per item, fading out.
##
## Shows world pickups ([IKWorldItem2D], [IKWorldItem3D]) automatically, plus
## anything added to the [member watched] inventories (quest rewards, crafting)
## while [member hide_while] is hidden, so moving items around in the inventory
## screen does not count. Call [method notify] for anything else.

@export var show_world_pickups := true
@export var watched: Array[IKInventory] = []
## Usually the inventory screen: additions to [member watched] made while it is
## visible are not shown.
@export var hide_while: CanvasItem
@export var duration := 2.5
@export var max_lines := 5
@export var icon_size := 28.0

var _lines := {}  # item_id -> {row, label, amount, time, name}
var _watched := {}  # IKContainer -> true


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	if show_world_pickups:
		get_tree().node_added.connect(_on_node_added)
	for inventory in watched:
		if inventory != null:
			watch(inventory.container)


## Shows every future addition to [param container] (see [member hide_while]).
func watch(container: IKContainer) -> void:
	_watched[container] = true
	var callback := _on_item_added.bind(container)
	if not container.item_added.is_connected(callback):
		container.item_added.connect(callback)


func notify(item_id: StringName, amount: int, database: IKItemDatabase = null) -> void:
	if amount <= 0:
		return
	var line: Dictionary = _lines.get(item_id, {})
	if line.is_empty() or not is_instance_valid(line.row):
		line = _create_line(item_id, database)
		_lines[item_id] = line
	line.amount += amount
	line.time = duration
	line.row.modulate.a = 1.0
	move_child(line.row, get_child_count() - 1)
	line.label.text = IKText.t("+%d %s") % [line.amount, IKText.t(line.name)]
	while get_child_count() > max_lines:
		_remove_line(get_child(0))


func _create_line(item_id: StringName, database: IKItemDatabase) -> Dictionary:
	var definition := database.get_item(item_id) if database != null else null
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.set_meta(&"item_id", item_id)
	var icon := TextureRect.new()
	icon.texture = definition.icon if definition != null else null
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var label := Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED  # translated by IKText
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override(&"outline_size", 4)
	row.add_child(label)
	add_child(row)
	var item_name := String(item_id).capitalize()
	if definition != null and not definition.display_name.is_empty():
		item_name = definition.display_name
	return {"row": row, "label": label, "amount": 0, "time": duration, "name": item_name}


func _process(delta: float) -> void:
	for item_id in _lines.keys():
		var line: Dictionary = _lines[item_id]
		if not is_instance_valid(line.row):
			_lines.erase(item_id)
			continue
		line.time -= delta
		if line.time <= 0.0:
			_remove_line(line.row)
		elif line.time < 0.4:
			line.row.modulate.a = line.time / 0.4


func _remove_line(row: Node) -> void:
	_lines.erase(row.get_meta(&"item_id"))
	remove_child(row)
	row.queue_free()


func _on_item_added(item_id: StringName, amount: int, container: IKContainer) -> void:
	if hide_while != null and hide_while.is_visible_in_tree():
		return
	notify(item_id, amount, container.database)


func _on_node_added(node: Node) -> void:
	if node is IKWorldItem2D or node is IKWorldItem3D:
		if not node.picked_up.is_connected(_on_world_pickup):
			node.picked_up.connect(_on_world_pickup.bind(node))


func _on_world_pickup(container: IKContainer, amount: int, world_item: Node) -> void:
	# Watched inventories already report it through item_added.
	if _watched.has(container) and (hide_while == null or not hide_while.is_visible_in_tree()):
		return
	notify(world_item.item_id, amount, world_item.database if world_item.database != null else container.database)
