extends Node2D
## World pickups demo: walk over items to collect them ("+5 Oak Log" notifications),
## open the bag with Tab, and click outside the bag to drop the held item on the ground.
## What does not fit in the 12-slot bag stays on the ground.

const ART := "res://addons/inventory_kit/art/"
const STANDARD_DEMO := "res://demo/standard/standard_demo.tscn"
const SPEED := 260.0
const LOOT := [
	[&"oak_log", 5, Vector2(300, 220)], [&"oak_log", 5, Vector2(340, 520)], [&"oak_log", 8, Vector2(980, 600)],
	[&"stone", 8, Vector2(520, 160)], [&"stone", 6, Vector2(760, 470)], [&"iron_ore", 4, Vector2(1080, 220)],
	[&"health_potion", 2, Vector2(640, 300)], [&"apple", 3, Vector2(200, 400)], [&"gold_coins", 25, Vector2(880, 140)],
	[&"gold_coins", 40, Vector2(460, 620)], [&"sword", 1, Vector2(1150, 420)], [&"iron_helmet", 1, Vector2(160, 160)],
	[&"iron_boots", 1, Vector2(700, 640)], [&"ruby", 1, Vector2(1000, 330)], [&"bread", 4, Vector2(580, 420)],
	[&"copper_ore", 6, Vector2(260, 650)], [&"mana_potion", 1, Vector2(1180, 620)], [&"leather", 5, Vector2(860, 300)],
]


class Hero extends CharacterBody2D:
	var inventory: IKInventory

	func _ready() -> void:
		add_to_group(&"player")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 16.0
		shape.shape = circle
		add_child(shape)

	func _draw() -> void:
		draw_circle(Vector2(0, 4), 18.0, Color(0, 0, 0, 0.25))
		draw_circle(Vector2.ZERO, 16.0, Color(0.95, 0.75, 0.35))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(0.35, 0.22, 0.1), 3.0)


var database: IKItemDatabase
var level: Node2D
var hero: Hero
var ui: IKInventoryUI
var _help: Label


func _ready() -> void:
	for da in ["painted", "realistic", "cartoon", "flat"]:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			database = load(ART + "%s/%s_items.tres" % [da, da])
			break
	level = Node2D.new()
	level.name = "Level"
	add_child(level)
	hero = Hero.new()
	hero.name = "Hero"
	hero.position = Vector2(640, 380)
	var bag := IKInventory.new()
	bag.name = "Bag"
	bag.container_id = &"bag"
	bag.size = 12
	bag.database = database
	bag.initial_items.assign({&"sword": 1, &"apple": 3})
	hero.add_child(bag)
	hero.inventory = bag
	level.add_child(hero)
	for entry in LOOT:
		IKWorldItem2D.spawn(level, IKItemStack.new(entry[0], entry[1]), database, entry[2], 0.0)
	_build_hud(bag)


func _build_hud(bag: IKInventory) -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	var theme_path := ART + "painted/painted_theme.tres"
	if ResourceLoader.exists(theme_path):
		root.theme = load(theme_path)

	_help = Label.new()
	_help.text = "Move: WASD / arrows / stick   ·   Bag: Tab or Start   ·   Bag open: click outside it to drop the held item"
	_help.position = Vector2(16, 12)
	_help.add_theme_color_override(&"font_outline_color", Color.BLACK)
	_help.add_theme_constant_override(&"outline_size", 4)
	root.add_child(_help)
	var back := Button.new()
	back.text = "Back to the inventory demo"
	back.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back.position = Vector2(-260, 8)
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(STANDARD_DEMO))
	root.add_child(back)

	ui = IKInventoryUI.new()
	ui.name = "BagScreen"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.visible = false
	root.add_child(ui)
	var skin_path := ART + "painted/painted_skin.tres"
	if ResourceLoader.exists(skin_path):
		ui.skin = load(skin_path)
	var frame := PanelContainer.new()
	frame.position = Vector2(820, 90)
	ui.add_child(frame)
	var box := VBoxContainer.new()
	frame.add_child(box)
	var title := Label.new()
	title.text = "Bag (12 slots)"
	box.add_child(title)
	var view := IKContainerView.new()
	view.columns = 4
	view.inventory = bag
	box.add_child(view)

	var dropper := IKItemDropper.new()
	dropper.spawn_parent = level
	dropper.drop_origin = hero
	dropper.scatter = 48.0
	ui.add_child(dropper)
	ui.add_child(IKSlotFeedback.new())
	var tooltips := IKTooltipPresenter.new()
	tooltips.shown_properties = [&"damage", &"armor", &"heal", &"value"]
	ui.add_child(tooltips)
	var controller := IKInputController.new()
	controller.close_requested.connect(func() -> void: ui.visible = false)
	ui.add_child(controller)

	var notifier := IKPickupNotifier.new()
	notifier.watched = [bag]
	notifier.hide_while = ui
	notifier.position = Vector2(16, 520)
	notifier.custom_minimum_size = Vector2(320, 0)
	root.add_child(notifier)


# _input, not _unhandled_input: the GUI would take Tab for focus navigation first.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	var toggle := key != null and key.pressed and not key.echo and key.physical_keycode in [KEY_TAB, KEY_I]
	var button := event as InputEventJoypadButton
	toggle = toggle or (button != null and button.pressed and button.button_index == JOY_BUTTON_START)
	if toggle:
		ui.visible = not ui.visible
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	var direction := Vector2.ZERO
	if not ui.visible:
		direction = Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
		direction.x += float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		direction.y += float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	hero.velocity = direction.limit_length(1.0) * SPEED
	hero.move_and_slide()
	hero.position = hero.position.clamp(Vector2(20, 40), get_viewport_rect().size - Vector2(20, 20))


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.23, 0.33, 0.2))
	var tile := 64.0
	for x in int(size.x / tile) + 1:
		for y in int(size.y / tile) + 1:
			if (x + y) % 2 == 0:
				draw_rect(Rect2(x * tile, y * tile, tile, tile), Color(0.25, 0.36, 0.21))
