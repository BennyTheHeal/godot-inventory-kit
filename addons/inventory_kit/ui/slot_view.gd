class_name IKSlotView
extends Control
## Displays one slot: background, item icon, amount and tooltip.
##
## Created by [IKContainerView]; it never changes the inventory itself, it only
## reports presses to the [IKInventoryUI] that owns the screen.
##
## In a grid container each view is one cell. The cell holding an item's top-left
## corner (its anchor) draws the item over all the cells it covers; the covered
## cells draw nothing of their own but still receive clicks, hover and focus.

signal pressed(view: IKSlotView, event: InputEventMouseButton)
signal released(view: IKSlotView, event: InputEventMouseButton)

enum State { NORMAL, HOVER, REJECTED, FOCUS, MARKED }

var container: IKContainer
var slot := -1
var skin: IKSkin
## Used to show whether the hovered slot accepts the held item. Optional.
var cursor: IKCursor
## The view this slot belongs to (set by [IKContainerView]). Optional.
var owner_view: IKContainerView

## Selected by keyboard or gamepad navigation (set by an input controller).
var focused := false:
	set(value):
		focused = value
		_redraw()

## Show the mouse hover style. Turned off while a keyboard/gamepad selection is shown.
var hover_enabled := true:
	set(value):
		hover_enabled = value
		queue_redraw()
## Persistent highlight, e.g. the selected hotbar slot.
var marked := false:
	set(value):
		marked = value
		queue_redraw()
## Faded out, e.g. items hidden by a filter.
var dimmed := false:
	set(value):
		dimmed = value
		modulate.a = 0.3 if dimmed else 1.0
## Faint placeholder shown while the slot is empty (e.g. a helmet outline).
var empty_icon: Texture2D:
	set(value):
		empty_icon = value
		if container != null:
			refresh()
## Optional Callable(slot_view: IKSlotView) -> Control building a custom tooltip.
var tooltip_factory: Callable

var _icon: TextureRect
var _amount: Label
var _hovered := false

static var _rotated_textures := {}


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED  # texts are translated by IKText
	_icon = TextureRect.new()
	_icon.name = "Icon"
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = MOUSE_FILTER_IGNORE
	_icon.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_icon)
	_amount = Label.new()
	_amount.name = "Amount"
	_amount.mouse_filter = MOUSE_FILTER_IGNORE
	_amount.set_anchors_preset(PRESET_FULL_RECT)
	_amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_amount.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_amount)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


func setup(p_container: IKContainer, p_slot: int, p_skin: IKSkin, p_cursor: IKCursor = null) -> void:
	container = p_container
	slot = p_slot
	skin = p_skin
	cursor = p_cursor
	custom_minimum_size = skin.slot_size
	_layout_children(Vector2i.ONE)
	skin.apply_amount_label(_amount)
	refresh()


func refresh() -> void:
	var stack := container.get_stack(slot) if container != null else null
	var definition := container.get_definition(slot) if stack != null else null
	var cells := Vector2i.ONE
	if container != null and container.is_grid():
		cells = container.get_size_of(stack) if stack != null else Vector2i.ONE
		_layout_children(cells)
	if stack == null and empty_icon != null and (container == null or container.is_slot_empty(slot)):
		_icon.texture = empty_icon
		_icon.modulate = Color(1, 1, 1, 0.25)
	else:
		var texture := definition.icon if definition != null else null
		if stack != null and container.is_grid() and stack.rotated and definition != null and definition.is_rotatable():
			texture = rotated_texture(texture)
		_icon.texture = texture
		_icon.modulate = Color.WHITE
	_amount.text = str(stack.amount) if stack != null and stack.amount > 1 else ""
	# Covered grid cells show the tooltip of the item over them.
	var shown := stack
	var shown_definition := definition
	if stack == null and container != null and container.is_grid():
		shown = get_item_stack()
		shown_definition = get_item_definition()
	tooltip_text = _tooltip_for(shown, shown_definition)
	queue_redraw()


## Copy of the stack in this slot, or null. In a grid, the item covering this cell.
## (Not named get_stack(): that is a built-in GDScript debug function.)
func get_item_stack() -> IKItemStack:
	if container == null:
		return null
	return container.get_stack(get_anchor_slot())


## Definition of the item shown in this slot (the one covering it, in a grid).
func get_item_definition() -> IKItemDefinition:
	if container == null:
		return null
	return container.get_definition(get_anchor_slot())


## Slot holding the item shown here: this slot, or in a grid the top-left cell
## of the item covering it. [member slot] if empty.
func get_anchor_slot() -> int:
	if container == null or not container.is_grid():
		return slot
	var anchor := container.get_anchor(slot)
	return anchor if anchor >= 0 else slot


## The view drawing the item shown here (the anchor cell's view, in a grid).
func get_display_view() -> IKSlotView:
	var anchor := get_anchor_slot()
	if anchor != slot and owner_view != null:
		var view := owner_view.get_slot_view(anchor)
		if view != null:
			return view
	return self


func get_state() -> State:
	if not (_hovered and hover_enabled) and not focused:
		return State.MARKED if marked else State.NORMAL
	if cursor != null and cursor.is_holding() and container != null \
			and not container.can_accept(slot, cursor.get_held()):
		return State.REJECTED
	return State.FOCUS if focused else State.HOVER


## True while the mouse is over this slot.
func is_hovered() -> bool:
	return _hovered


## The item icon (null when empty, even if an [member empty_icon] is shown).
func get_icon_texture() -> Texture2D:
	if container != null and container.get_stack(slot) == null:
		return null
	if get_item_stack() == null:
		return null
	return _icon.texture


func _make_custom_tooltip(_for_text: String) -> Object:
	if tooltip_factory.is_valid() and get_item_stack() != null:
		return tooltip_factory.call(self)
	return null


func get_amount_text() -> String:
	return _amount.text


## [param texture] turned a quarter turn clockwise (cached). Returns [param texture]
## itself if its image cannot be read.
static func rotated_texture(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var key := texture.get_instance_id()
	if _rotated_textures.has(key):
		var cached: Array = _rotated_textures[key]
		if is_instance_valid(cached[0]) and cached[0] == texture:
			return cached[1]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.rotate_90(CLOCKWISE)
	var turned := ImageTexture.create_from_image(image)
	_rotated_textures[key] = [texture, turned]
	return turned


func _draw() -> void:
	if skin == null:
		return
	if container != null and container.is_grid():
		_draw_grid_cell()
		return
	draw_style_box(skin.get_slot_style(get_state()), Rect2(Vector2.ZERO, size))


func _draw_grid_cell() -> void:
	var anchor := container.get_anchor(slot)
	var active := owner_view.get_active_slot() if owner_view != null else (slot if (_hovered and hover_enabled) or focused else -1)
	var holding := cursor != null and cursor.is_holding()
	var focus_on := owner_view.is_focus_active() if owner_view != null else focused
	if anchor == slot:
		var cells := container.get_item_size(slot)
		var state := State.MARKED if marked else State.NORMAL
		if not holding and active >= 0 and container.get_anchor(active) == slot:
			state = State.FOCUS if focus_on else State.HOVER
		draw_style_box(skin.get_slot_style(state), Rect2(Vector2.ZERO, _cells_size(cells)))
	elif anchor < 0:
		var state := State.MARKED if marked else State.NORMAL
		if active == slot and not holding:
			state = State.FOCUS if focus_on else State.HOVER
		draw_style_box(skin.get_slot_style(state), Rect2(Vector2.ZERO, size))
	if owner_view != null and owner_view.get_preview_cells().has(slot):
		var fits := owner_view.is_preview_valid()
		draw_rect(Rect2(Vector2.ZERO, size), skin.grid_valid_color if fits else skin.grid_invalid_color)
		if focus_on and active == slot:
			draw_style_box(skin.get_slot_style(State.FOCUS if fits else State.REJECTED), Rect2(Vector2.ZERO, size))


## Pixel size of [param cells] cells, separations included.
func _cells_size(cells: Vector2i) -> Vector2:
	var cell := skin.slot_size if skin != null else size
	var gap := float(skin.slot_separation) if skin != null else 0.0
	return Vector2(cells.x * cell.x + (cells.x - 1) * gap, cells.y * cell.y + (cells.y - 1) * gap)


## Stretches the icon and amount over [param cells] cells (grid items).
func _layout_children(cells: Vector2i) -> void:
	if skin == null:
		return
	var margin := float(skin.icon_margin)
	var extra := _cells_size(cells) - skin.slot_size
	_icon.offset_left = margin
	_icon.offset_top = margin
	_icon.offset_right = extra.x - margin
	_icon.offset_bottom = extra.y - margin
	_amount.offset_right = extra.x - margin * 0.5
	_amount.offset_bottom = extra.y


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index > MOUSE_BUTTON_MIDDLE:
		return  # let the mouse wheel through (scrolling, hotbar selection)
	if button.pressed:
		pressed.emit(self, button)
	else:
		released.emit(self, button)
	accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and container != null:
		refresh()


func _set_hovered(value: bool) -> void:
	_hovered = value
	if owner_view != null and container != null and container.is_grid():
		owner_view._on_cell_hovered(self, value)
	queue_redraw()


func _redraw() -> void:
	if owner_view != null and container != null and container.is_grid():
		owner_view.update_grid_highlight()
	queue_redraw()


func _tooltip_for(stack: IKItemStack, definition: IKItemDefinition) -> String:
	if stack == null:
		return ""
	if definition == null:
		return IKText.t("Unknown item (%s)") % stack.item_id
	var title := IKText.item_name(definition)
	if definition.description.is_empty():
		return title
	return "%s\n%s" % [title, IKText.item_description(definition)]
