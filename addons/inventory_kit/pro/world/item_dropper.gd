class_name IKItemDropper
extends Node
## Lets the player throw the held stack into the world: click outside every panel
## of the [IKInventoryUI] this node is a child of (or press [member drop_action]).
##
## The stack leaves the inventory ([method IKCursor.take_held]) and becomes an
## [IKWorldItem2D] or [IKWorldItem3D] next to [member drop_origin], depending on
## its type. Without a [member spawn_parent], only [signal item_dropped] is
## emitted and the game decides what to do with the stack.

signal item_dropped(stack: IKItemStack, world_item: Node)

@export var enabled := true
@export var drop_on_click_outside := true
## Input action that drops the held stack (e.g. a gamepad button). Empty: none.
@export var drop_action: StringName = &""
## Where dropped items are added (usually the level).
@export var spawn_parent: Node
## Node2D or Node3D the items fall next to (usually the player).
@export var drop_origin: Node
## Random distance from the origin: pixels in 2D, meters in 3D.
@export var scatter := 24.0
## Seconds before a dropped item can be picked up again.
@export var pickup_delay := 0.8

var ui: IKInventoryUI


func _ready() -> void:
	ui = get_parent() as IKInventoryUI
	if ui == null:
		push_error("IKItemDropper must be a child of an IKInventoryUI.")


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or ui == null or not ui.is_visible_in_tree() or not ui.cursor.is_holding():
		return
	var click := event as InputEventMouseButton
	var wanted := drop_on_click_outside and click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	if not wanted and drop_action != &"" and InputMap.has_action(drop_action):
		wanted = event.is_action_pressed(drop_action)
	if wanted:
		drop_held()
		get_viewport().set_input_as_handled()


## Drops the held stack. Returns the world item created (null without a spawn parent).
func drop_held() -> Node:
	if ui == null or not ui.cursor.is_holding():
		return null
	var database := ui.cursor.container.database
	var stack := ui.cursor.take_held()
	var world_item: Node = null
	if spawn_parent != null:
		var angle := randf() * TAU
		var distance := randf_range(scatter * 0.5, scatter)
		if drop_origin is Node3D:
			var origin := (drop_origin as Node3D).global_position
			world_item = IKWorldItem3D.spawn(spawn_parent, stack, database,
				origin + Vector3(cos(angle), 0.0, sin(angle)) * distance, pickup_delay)
		else:
			var origin := (drop_origin as Node2D).global_position if drop_origin is Node2D else Vector2.ZERO
			world_item = IKWorldItem2D.spawn(spawn_parent, stack, database, origin + Vector2.from_angle(angle) * distance, pickup_delay)
	item_dropped.emit(stack, world_item)
	return world_item
