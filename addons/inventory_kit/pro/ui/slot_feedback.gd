class_name IKSlotFeedback
extends Node
## Animations for the [IKInventoryUI] this node is a child of: slots that receive
## an item pop, and refused actions shake the slot and flash it red.

@export var animate := true
## Icon scale at the start of the "item received" pop.
@export var pop_scale := 1.18
@export var pop_duration := 0.18
## Rotation (radians) of the "refused" wiggle.
@export var shake_angle := 0.18
@export var reject_color := Color(1.0, 0.45, 0.4)

var ui: IKInventoryUI
var _last_pressed: IKSlotView


func _ready() -> void:
	ui = get_parent() as IKInventoryUI
	if ui == null:
		push_error("IKSlotFeedback must be a child of an IKInventoryUI.")
		return
	ui.view_registered.connect(_watch_view)
	for view in ui.get_container_views():
		_watch_view(view)
	ui.slot_pressed.connect(func(_view: IKContainerView, slot_view: IKSlotView, _event: InputEvent) -> void:
		_last_pressed = slot_view)
	ui.interaction_failed.connect(_on_failed)


## The "item received" pop on one slot.
func pop(slot_view: IKSlotView) -> void:
	var icon := slot_view.get_node_or_null(^"Icon") as Control
	if not animate or icon == null or not slot_view.is_inside_tree():
		return
	icon.pivot_offset = icon.size / 2.0
	var tween := _restart_tween(icon)
	icon.scale = Vector2.ONE * pop_scale
	tween.tween_property(icon, ^"scale", Vector2.ONE, pop_duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The "refused" wiggle and red flash on one slot.
func shake(slot_view: IKSlotView) -> void:
	var icon := slot_view.get_node_or_null(^"Icon") as Control
	if not animate or icon == null or not slot_view.is_inside_tree():
		return
	icon.pivot_offset = icon.size / 2.0
	var tween := _restart_tween(icon)
	for angle in [shake_angle, -shake_angle, shake_angle * 0.5, 0.0]:
		tween.tween_property(icon, ^"rotation", angle, 0.05)
	slot_view.self_modulate = reject_color
	tween.parallel().tween_property(slot_view, ^"self_modulate", Color.WHITE, 0.3)


func _restart_tween(icon: Control) -> Tween:
	var previous: Tween = icon.get_meta(&"ik_feedback_tween") if icon.has_meta(&"ik_feedback_tween") else null
	if previous != null and previous.is_valid():
		previous.kill()
	icon.rotation = 0.0
	icon.scale = Vector2.ONE
	var tween := icon.create_tween()
	icon.set_meta(&"ik_feedback_tween", tween)
	return tween


func _watch_view(view: IKContainerView) -> void:
	# Views can be rebound to another container (skin change): follow the view, not the container.
	var callback := _on_slots_changed.bind(view, view.container)
	if view.container != null and not view.container.slots_changed.is_connected(callback):
		view.container.slots_changed.connect(callback)
	if not view.slot_view_created.is_connected(_on_slot_view_created):
		view.slot_view_created.connect(_on_slot_view_created.bind(view))


func _on_slot_view_created(_slot_view: IKSlotView, view: IKContainerView) -> void:
	_watch_view(view)


func _on_slots_changed(slots: PackedInt32Array, view: IKContainerView, container: IKContainer) -> void:
	if not is_instance_valid(view) or view.container != container or not view.is_visible_in_tree():
		return
	for slot in slots:
		var slot_view := view.get_slot_view(slot)
		if slot_view != null and container.get_stack(slot) != null:
			pop.call_deferred(slot_view)  # after the view has refreshed the icon


func _on_failed(_result: IKResult) -> void:
	var target := _focused_slot_view()
	if target == null:
		target = _last_pressed
	if target != null and is_instance_valid(target):
		shake(target.get_display_view())  # grid: the cell drawing the item


func _focused_slot_view() -> IKSlotView:
	for child in ui.get_children():
		if child is IKInputController and child.mode == IKInputController.Mode.FOCUS:
			return child.get_focused_slot_view()
	return null
