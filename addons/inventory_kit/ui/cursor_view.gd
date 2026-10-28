class_name IKCursorView
extends Control
## Draws the held stack under the mouse pointer. Created by [IKInventoryUI].
##
## Items bigger than one cell ([member IKItemDefinition.grid_size]) are drawn at
## their grid size, turned if they are turned, with their top-left cell under
## the pointer: that cell is where a click puts them.

var cursor: IKCursor
var skin: IKSkin
## Draw items at their grid size (false: always one slot).
var show_grid_size := true
## When set, the held stack is drawn next to this control (keyboard/gamepad
## selection) instead of under the mouse pointer.
var anchor: Control:
	set(value):
		anchor = value
		if visible:
			_follow()

var _icon: TextureRect
var _amount: Label


func _init() -> void:
	top_level = true
	z_index = 100
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_icon = TextureRect.new()
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_icon)
	_amount = Label.new()
	_amount.mouse_filter = MOUSE_FILTER_IGNORE
	_amount.set_anchors_preset(PRESET_FULL_RECT)
	_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_amount.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_amount)


func setup(p_cursor: IKCursor, p_skin: IKSkin) -> void:
	cursor = p_cursor
	skin = p_skin
	size = skin.slot_size
	skin.apply_amount_label(_amount)
	cursor.container.changed.connect(refresh)
	refresh()


func set_skin(p_skin: IKSkin) -> void:
	skin = p_skin
	size = skin.slot_size
	skin.apply_amount_label(_amount)
	refresh()


## Cells the held item is drawn over (1 x 1 when nothing is held).
func get_held_cells() -> Vector2i:
	var held := cursor.get_held() if cursor != null else null
	var definition := cursor.container.get_definition(0) if held != null else null
	if held == null or definition == null or not show_grid_size:
		return Vector2i.ONE
	return definition.get_grid_size(held.rotated)


func refresh() -> void:
	if cursor == null:
		return
	var held := cursor.get_held()
	visible = held != null
	if held == null:
		return
	var definition := cursor.container.get_definition(0)
	var texture := definition.icon if definition != null else null
	if show_grid_size and held.rotated and definition != null and definition.is_rotatable():
		texture = IKSlotView.rotated_texture(texture)
	_icon.texture = texture
	_amount.text = str(held.amount) if held.amount > 1 else ""
	var cells := get_held_cells()
	var gap := float(skin.slot_separation) if skin != null else 0.0
	var cell := skin.slot_size if skin != null else Vector2(56, 56)
	size = Vector2(cells.x * cell.x + (cells.x - 1) * gap, cells.y * cell.y + (cells.y - 1) * gap)
	_follow()


func _process(_delta: float) -> void:
	if visible:
		_follow()


func _follow() -> void:
	if not is_inside_tree():
		return
	var cell := skin.slot_size if skin != null else size
	if anchor != null and is_instance_valid(anchor) and anchor.is_visible_in_tree():
		var rect := anchor.get_global_rect()
		global_position = rect.position + rect.size * 0.35
	else:
		# The top-left cell is centred on the pointer (same as before for one-cell items).
		global_position = get_global_mouse_position() - cell * 0.5
