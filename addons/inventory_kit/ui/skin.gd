class_name IKSkin
extends Resource
## Visual settings for inventory UI. Assign another skin to change the whole
## look: no script depends on any image file.

@export var slot_size := Vector2(56, 56)
@export var slot_separation := 4
## Space between the slot border and the item icon.
@export var icon_margin := 6
@export var slot_normal: StyleBox
@export var slot_hover: StyleBox
## Hovered while holding an item this slot does not accept.
@export var slot_rejected: StyleBox
## Selected with a gamepad or keyboard.
@export var slot_focus: StyleBox
## Persistent highlight (selected hotbar slot).
@export var slot_marked: StyleBox
@export var amount_font: Font
@export var amount_font_size := 14
@export var amount_color := Color.WHITE
@export var amount_outline_color := Color(0, 0, 0, 0.85)
@export var amount_outline_size := 4
## Grid containers: tint of the cells the held item would cover, when it fits / when it does not.
@export var grid_valid_color := Color(0.45, 0.95, 0.55, 0.28)
@export var grid_invalid_color := Color(1.0, 0.35, 0.35, 0.32)

static var _fallback: IKSkin


## Neutral grey skin used when none is assigned.
static func create_default() -> IKSkin:
	var skin := IKSkin.new()
	skin.slot_normal = _flat(Color(0.15, 0.16, 0.19, 0.95), Color(0.32, 0.34, 0.40))
	skin.slot_hover = _flat(Color(0.21, 0.23, 0.28, 0.95), Color(0.86, 0.78, 0.45))
	skin.slot_rejected = _flat(Color(0.30, 0.12, 0.12, 0.95), Color(0.86, 0.32, 0.32))
	skin.slot_focus = _flat(Color(0.23, 0.25, 0.31, 0.95), Color(1.0, 0.86, 0.35))
	(skin.slot_focus as StyleBoxFlat).set_border_width_all(3)
	skin.slot_marked = _flat(Color(0.20, 0.22, 0.27, 0.95), Color(0.55, 0.80, 1.0))
	(skin.slot_marked as StyleBoxFlat).set_border_width_all(3)
	return skin


func get_slot_style(state: IKSlotView.State) -> StyleBox:
	var style: StyleBox
	match state:
		IKSlotView.State.HOVER:
			style = slot_hover
		IKSlotView.State.REJECTED:
			style = slot_rejected
		IKSlotView.State.FOCUS:
			style = slot_focus if slot_focus != null else slot_hover
		IKSlotView.State.MARKED:
			style = slot_marked if slot_marked != null else slot_hover
	if style == null:
		style = slot_normal
	if style == null:
		if _fallback == null:
			_fallback = create_default()
		style = _fallback.get_slot_style(state)
	return style


func apply_amount_label(label: Label) -> void:
	if amount_font != null:
		label.add_theme_font_override(&"font", amount_font)
	label.add_theme_font_size_override(&"font_size", amount_font_size)
	label.add_theme_color_override(&"font_color", amount_color)
	label.add_theme_color_override(&"font_outline_color", amount_outline_color)
	label.add_theme_constant_override(&"outline_size", amount_outline_size)


static func _flat(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	return style
