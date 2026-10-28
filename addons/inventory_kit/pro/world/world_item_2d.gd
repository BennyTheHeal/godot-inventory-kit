@tool
class_name IKWorldItem2D
extends Area2D
## An item lying in a 2D world. Shows its icon, bobs gently, and is collected when
## a body of [member collector_group] touches it (or when you call [method pick_up]).
##
## The collector's inventory is found by [method IKPickup.find_container]: an
## [IKInventory] child, or an [code]inventory[/code] property. What does not fit
## stays on the ground.
## [codeblock]
## IKWorldItem2D.spawn(level, held_stack, database, player.global_position)
## [/codeblock]

## Emitted after items went into an inventory. The node frees itself once empty.
signal picked_up(container: IKContainer, amount: int)
## Emitted when an inventory had no room at all.
signal pickup_failed(container: IKContainer, result: IKResult)

@export var item_id: StringName:
	set(value):
		item_id = value
		_stack = null
		_update_visual()
@export_range(1, 9999) var amount := 1:
	set(value):
		amount = value
		_stack = null
@export var database: IKItemDatabase:
	set(value):
		database = value
		_update_visual()
## Collect automatically when a body of [member collector_group] enters.
@export var auto_pickup := true
@export var collector_group: StringName = &"player"
## Icon size in pixels.
@export var icon_size := 40.0:
	set(value):
		icon_size = value
		_update_visual()
## Bobbing height in pixels (0 = still).
@export var bob_height := 3.0
## Soft shadow under the icon.
@export var shadow := true:
	set(value):
		shadow = value
		queue_redraw()
## Seconds during which touching bodies are ignored. A body already touching the
## item when it ends must step away and come back: a dropped item never jumps
## straight back into the bag of the player who dropped it.
@export var pickup_delay := 0.0

var _stack: IKItemStack
var _ignored := {}  # bodies that touched the item during the pickup delay
var _sprite: Sprite2D
var _time := 0.0


## Creates a world item for [param stack] (uid and data kept) under [param parent].
static func spawn(parent: Node, stack: IKItemStack, p_database: IKItemDatabase, at: Vector2, delay: float = 0.8) -> IKWorldItem2D:
	var item := IKWorldItem2D.new()
	item.database = p_database
	item.set_item_stack(stack)
	item.pickup_delay = delay
	parent.add_child(item)
	item.global_position = at
	return item


func _ready() -> void:
	_update_visual()
	if Engine.is_editor_hint():
		return
	if not _has_shape():
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = icon_size * 0.5
		shape.shape = circle
		add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(func(body: Node) -> void: _ignored.erase(body))
	_time = randf() * TAU


## The stack lying here (a copy). Built from [member item_id] and [member amount]
## unless [method set_stack] was called.
func get_item_stack() -> IKItemStack:
	if _stack == null:
		_stack = IKItemStack.new(item_id, amount)
	return _stack.copy()


func set_item_stack(stack: IKItemStack) -> void:
	item_id = stack.item_id
	amount = stack.amount
	_stack = stack.copy()
	_update_visual()


## Moves as much as fits into [param container]; frees the node when nothing is left.
func pick_up(container: IKContainer) -> IKResult:
	var stack := get_item_stack()
	var result := IKPickup.collect(stack, container)
	if not result.ok:
		pickup_failed.emit(container, result)
		return result
	picked_up.emit(container, stack.amount - result.remainder)
	if result.remainder == 0:
		queue_free()
	else:
		stack.amount = result.remainder
		set_item_stack(stack)
	return result


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _sprite == null:
		return
	_time += delta
	_sprite.position.y = sin(_time * 3.0) * bob_height


# Counted in physics frames: overlaps are only known after a physics step, even
# when a slow frame makes the process delta large.
func _physics_process(delta: float) -> void:
	if not Engine.is_editor_hint() and pickup_delay > 0.0:
		pickup_delay = maxf(0.0, pickup_delay - delta)


func _on_body_entered(body: Node) -> void:
	if not auto_pickup or is_queued_for_deletion() or _ignored.has(body):
		return
	if pickup_delay > 0.0:
		_ignored[body] = true  # must step away and come back
		return
	if collector_group != &"" and not body.is_in_group(collector_group):
		return
	var container := IKPickup.find_container(body)
	if container != null:
		pick_up(container)


func _draw() -> void:
	if shadow:
		draw_set_transform(Vector2(0, icon_size * 0.42), 0.0, Vector2(1.0, 0.35))
		draw_circle(Vector2.ZERO, icon_size * 0.38, Color(0, 0, 0, 0.28))
		draw_set_transform(Vector2.ZERO)


func _has_shape() -> bool:
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			return true
	return false


func _update_visual() -> void:
	if not is_inside_tree():
		return
	if _sprite == null:
		_sprite = Sprite2D.new()
		_sprite.name = "Icon"
		add_child(_sprite, false, INTERNAL_MODE_FRONT)
	var definition := database.get_item(item_id) if database != null else null
	_sprite.texture = definition.icon if definition != null else null
	if _sprite.texture != null:
		_sprite.scale = Vector2.ONE * icon_size / maxf(1.0, _sprite.texture.get_size().x)
