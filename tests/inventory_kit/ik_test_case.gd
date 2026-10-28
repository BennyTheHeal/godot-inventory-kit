extends RefCounted
## Base class for Inventory Kit tests: assertions and shared fixtures.

var _failures := PackedStringArray()
var _nodes: Array[Node] = []


func get_failures() -> PackedStringArray:
	return _failures


func get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Adds [param node] to the scene root; it is freed after the test.
func add_to_tree(node: Node) -> Node:
	get_tree().root.add_child(node)
	_nodes.append(node)
	return node


func wait_frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame


## Called by the runner after each test.
func cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	await get_tree().process_frame


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%sexpected <%s> but got <%s>" % [message + ": " if message else "", expected, actual])


func assert_ok(result: IKResult, message: String = "") -> void:
	if result == null or not result.ok:
		fail("%sexpected OK, got %s" % [message + ": " if message else "", result])


func assert_code(result: IKResult, code: IKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", IKResult.Code.keys()[code], result])


## Disconnects every signal of [param objects]. Call at the end of tests whose
## lambdas capture the emitter, otherwise the reference cycle leaks.
func disconnect_all(objects: Array) -> void:
	for object: Object in objects:
		for info in object.get_signal_list():
			for connection in object.get_signal_connection_list(info.name):
				object.disconnect(info.name, connection.callable)


# --- Fixtures ----------------------------------------------------------------

func make_item(id: StringName, max_stack: int = 1, unique: bool = false, category: StringName = &"",
		equip_slot: StringName = &"") -> IKItemDefinition:
	var item := IKItemDefinition.new()
	item.id = id
	item.display_name = String(id).capitalize()
	item.max_stack = max_stack
	item.unique = unique
	item.category = category
	item.equip_slot = equip_slot
	return item


## wood (20), stone (50), potion (5, consumable), gem (1), sword and helmet (unique, equippable).
func make_db() -> IKItemDatabase:
	var db := IKItemDatabase.new()
	db.add_item(make_item(&"wood", 20, false, &"material"))
	db.add_item(make_item(&"stone", 50, false, &"material"))
	db.add_item(make_item(&"potion", 5, false, &"consumable"))
	db.add_item(make_item(&"gem", 1, false, &"valuable"))
	db.add_item(make_item(&"sword", 1, true, &"weapon", &"weapon"))
	db.add_item(make_item(&"helmet", 1, true, &"armor", &"head"))
	return db


## make_db() plus grid sizes: sword 1x3, helmet 2x2, plank 2x1 (stacks of 10),
## armor 2x3 (unique), staff 1x4 (cannot turn), crate 2x2 (cannot turn).
func make_grid_db() -> IKItemDatabase:
	var db := make_db()
	db.get_item(&"sword").grid_size = Vector2i(1, 3)
	db.get_item(&"helmet").grid_size = Vector2i(2, 2)
	var plank := make_item(&"plank", 10, false, &"material")
	plank.grid_size = Vector2i(2, 1)
	db.add_item(plank)
	var armor := make_item(&"armor", 1, true, &"armor", &"body")
	armor.grid_size = Vector2i(2, 3)
	db.add_item(armor)
	var staff := make_item(&"staff", 1, true, &"weapon", &"weapon")
	staff.grid_size = Vector2i(1, 4)
	staff.can_rotate = false
	db.add_item(staff)
	var crate := make_item(&"crate", 1, false, &"material")
	crate.grid_size = Vector2i(2, 2)
	crate.can_rotate = false
	db.add_item(crate)
	return db


const GRID_LETTERS := {"wood": "w", "stone": "o", "potion": "p", "gem": "g", "sword": "S", "helmet": "H",
	"plank": "=", "armor": "A", "staff": "|", "crate": "C"}


## One letter per cell of a grid container ("." = free, see GRID_LETTERS), rows
## separated by "/", for readable asserts.
func grid_map(container: IKContainer) -> String:
	var rows := PackedStringArray()
	for y in container.get_grid_height():
		var row := PackedStringArray()
		for x in container.get_grid_width():
			var anchor := container.get_anchor(container.slot_of(Vector2i(x, y)))
			var item_id := String(container.get_stack(anchor).item_id) if anchor >= 0 else ""
			row.append("." if anchor < 0 else GRID_LETTERS.get(item_id, item_id.substr(0, 1)))
		rows.append("".join(row))
	return "/".join(rows)


## Slot 0: weapon, slot 1: head, slot 2: consumables only.
func make_equipment(db: IKItemDatabase) -> IKContainer:
	var equipment := IKContainer.new(&"equipment", 3, db)
	equipment.set_slot_rule(0, IKEquipSlotRule.new(&"weapon"))
	equipment.set_slot_rule(1, IKEquipSlotRule.new(&"head"))
	var consumables := IKTagSlotRule.new()
	consumables.categories = [&"consumable"]
	equipment.set_slot_rule(2, consumables)
	return equipment
