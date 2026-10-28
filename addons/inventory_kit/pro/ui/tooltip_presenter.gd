class_name IKTooltipPresenter
extends Node
## Rich tooltips for every slot of the [IKInventoryUI] this node is a child of.
##
## With the mouse, they replace Godot's plain tooltips. With a keyboard or
## gamepad ([IKInputController] in FOCUS mode), a tooltip follows the selection,
## since Godot's tooltips only appear on mouse hover.

## Entries of IKItemDefinition.properties shown as stat lines, in order.
@export var shown_properties: Array[StringName] = [&"damage", &"armor", &"heal", &"mana", &"value"]
## Entries of IKItemStack.data shown as lines (per-copy values).
@export var shown_data: Array[StringName] = [&"durability"]
@export var show_weight := true
## Compare equippable items with what is worn here, and list set bonuses. Optional.
@export var equipment: IKEquipment:
	set(value):
		equipment = value
		if _focus_tooltip != null and is_instance_valid(_focus_tooltip):
			_focus_tooltip.equipment = value
		_shown_key = ""
## Numeric properties compared with the worn item.
@export var compare_properties: Array[StringName] = [&"damage", &"armor", &"mana", &"stamina", &"fire_resist"]
## Show the tooltip next to the keyboard/gamepad selection.
@export var follow_selection := true
## Background of the tooltips (e.g. the TooltipPanel style of an art direction theme).
## Empty: a neutral dark panel.
@export var panel_style: StyleBox:
	set(value):
		panel_style = value
		if _focus_tooltip != null and is_instance_valid(_focus_tooltip):
			_focus_tooltip.set_panel_style(value)
		_shown_key = ""

var ui: IKInventoryUI
var _focus_tooltip: IKTooltip
var _shown_key := ""


func _ready() -> void:
	ui = get_parent() as IKInventoryUI
	if ui == null:
		push_error("IKTooltipPresenter must be a child of an IKInventoryUI.")
		set_process(false)
		return
	ui.view_registered.connect(_configure_view)
	for view in ui.get_container_views():
		_configure_view(view)
	_focus_tooltip = create_tooltip()
	_focus_tooltip.top_level = true
	_focus_tooltip.z_index = 90
	_focus_tooltip.visible = false
	ui.add_child.call_deferred(_focus_tooltip)


func _notification(what: int) -> void:
	# The selection tooltip is added to the UI deferred; free it if that never happened.
	if what == NOTIFICATION_PREDELETE and _focus_tooltip != null and is_instance_valid(_focus_tooltip) \
			and not _focus_tooltip.is_inside_tree():
		_focus_tooltip.free()


func create_tooltip() -> IKTooltip:
	var tooltip := IKTooltip.new()
	tooltip.shown_properties = shown_properties
	tooltip.shown_data = shown_data
	tooltip.show_weight = show_weight
	tooltip.equipment = equipment
	tooltip.compare_properties = compare_properties
	if panel_style != null:
		tooltip.set_panel_style(panel_style)
	return tooltip


func _configure_view(view: IKContainerView) -> void:
	if not view.slot_view_created.is_connected(_configure_slot):
		view.slot_view_created.connect(_configure_slot)
	for slot_view in view.get_slot_views():
		_configure_slot(slot_view)


func _configure_slot(slot_view: IKSlotView) -> void:
	slot_view.tooltip_factory = _build_for_slot


func _build_for_slot(slot_view: IKSlotView) -> Control:
	var tooltip := create_tooltip()
	# Godot already draws its TooltipPanel (from the theme) around custom tooltips.
	tooltip.set_panel_style(StyleBoxEmpty.new())
	tooltip.show_stack(slot_view.get_item_stack(), slot_view.get_item_definition(), slot_view.container)
	return tooltip


func _process(_delta: float) -> void:
	if _focus_tooltip == null or not is_instance_valid(_focus_tooltip):
		return
	var slot_view := _selected_slot_view() if follow_selection and ui.is_visible_in_tree() else null
	var stack := slot_view.get_item_stack() if slot_view != null else null
	if stack == null or ui.cursor.is_holding():
		_focus_tooltip.visible = false
		_shown_key = ""
		return
	var key := "%d:%d:%d:%d:%s" % [slot_view.get_instance_id(), slot_view.slot, slot_view.container.get_revision(),
		equipment.container.get_revision() if equipment != null else 0, TranslationServer.get_locale()]
	if key != _shown_key:
		_shown_key = key
		_focus_tooltip.show_stack(stack, slot_view.get_item_definition(), slot_view.container)
	var rect := slot_view.get_display_view().get_global_rect()
	if slot_view.container.is_grid():
		rect.size = slot_view._cells_size(slot_view.container.get_item_size(slot_view.get_anchor_slot()))
	var viewport_size := ui.get_viewport_rect().size
	var position := Vector2(rect.end.x + 8, rect.position.y)
	if position.x + _focus_tooltip.size.x > viewport_size.x:
		position.x = rect.position.x - _focus_tooltip.size.x - 8
	position.y = clampf(position.y, 0.0, maxf(0.0, viewport_size.y - _focus_tooltip.size.y))
	_focus_tooltip.global_position = position
	_focus_tooltip.visible = true


func _selected_slot_view() -> IKSlotView:
	for child in ui.get_children():
		if child is IKInputController and child.mode == IKInputController.Mode.FOCUS:
			return child.get_focused_slot_view()
	return null
