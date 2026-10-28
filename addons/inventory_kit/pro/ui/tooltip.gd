class_name IKTooltip
extends PanelContainer
## Rich item tooltip: icon, name colored by rarity, category, description,
## stats, per-copy data (durability...), weight and stack size. With an
## [member equipment], stats are compared with the worn item ("Armor: 20 +8")
## and set pieces show their set bonuses.
## Built by [IKTooltipPresenter]; can also be used on its own with [method show_stack].

## Default colors for [code]properties["rarity"][/code].
const RARITY_COLORS := {
	"common": Color(0.9, 0.9, 0.9),
	"uncommon": Color(0.45, 0.9, 0.45),
	"rare": Color(0.4, 0.65, 1.0),
	"epic": Color(0.75, 0.45, 1.0),
	"legendary": Color(1.0, 0.7, 0.25),
}

## Entries of IKItemDefinition.properties shown as stat lines, in this order.
var shown_properties: Array[StringName] = []
## Entries of IKItemStack.data shown as lines (per-copy values such as durability).
var shown_data: Array[StringName] = []
var show_weight := true
## Worn items to compare with, and set bonuses to list. Optional.
var equipment: IKEquipment
## Numeric properties compared with the worn item (must also be in [member shown_properties]).
var compare_properties: Array[StringName] = [&"damage", &"armor", &"mana", &"stamina", &"fire_resist"]

const BETTER_COLOR := Color(0.45, 0.95, 0.45)
const WORSE_COLOR := Color(1.0, 0.45, 0.4)
const MUTED_COLOR := Color(0.55, 0.57, 0.62)

var _content: VBoxContainer


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(240, 0)
	_init_default_style()
	auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED  # texts are translated by IKText
	_content = VBoxContainer.new()
	_content.add_theme_constant_override(&"separation", 4)
	_content.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_content)


## Replaces the default dark background (null restores it).
func set_panel_style(style: StyleBox) -> void:
	if style == null:
		_init_default_style()
	else:
		add_theme_stylebox_override(&"panel", style)


func _init_default_style() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.10, 0.97)
	style.border_color = Color(0.45, 0.47, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	add_theme_stylebox_override(&"panel", style)


## [param source] is the container the stack is shown from: items already worn
## in [member equipment] are not compared with themselves.
func show_stack(stack: IKItemStack, definition: IKItemDefinition, source: IKContainer = null) -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	if stack == null:
		return
	if definition == null:
		_add_label(IKText.t("Unknown item (%s)") % stack.item_id, Color(1, 0.5, 0.5))
		return

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	_content.add_child(header)
	if definition.icon != null:
		var icon := TextureRect.new()
		icon.texture = definition.icon
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		header.add_child(icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override(&"separation", 0)
	header.add_child(titles)
	var rarity := String(definition.properties.get("rarity", "")).to_lower()
	var title := IKText.item_name(definition)
	var title_label := _add_label(title, RARITY_COLORS.get(rarity, Color.WHITE), titles)
	title_label.add_theme_font_size_override(&"font_size", 17)
	var subtitle := PackedStringArray()
	if not rarity.is_empty():
		subtitle.append(IKText.label(StringName(rarity)))
	if definition.category != &"":
		subtitle.append(IKText.label(definition.category))
	if definition.equip_slot != &"":
		subtitle.append(IKText.t("Slot: %s") % IKText.label(definition.equip_slot))
	if not subtitle.is_empty():
		_add_label(" · ".join(subtitle), Color(0.65, 0.67, 0.72), titles)

	var worn := _worn_definition(definition, source)
	var comparing := worn != null or _comparable_slot(definition, source)
	for property in shown_properties:
		if definition.properties.has(property):
			var line := _add_label(IKText.t("%s: %s") % [IKText.label(property), _format(definition.properties[property])], Color(0.85, 0.9, 1.0))
			if comparing and compare_properties.has(property):
				_add_difference(line, definition, worn, property)
	for key in shown_data:
		if stack.data.has(key):
			_add_label(IKText.t("%s: %s") % [IKText.label(key), _format(stack.data[key])], Color(1.0, 0.9, 0.7))
	if comparing:
		var against := IKText.t("Compared with %s") % IKText.item_name(worn) if worn != null else IKText.t("Nothing worn in this slot")
		_add_label(against, MUTED_COLOR)
	_add_set_lines(definition)
	if not definition.description.is_empty():
		var description := _add_label(IKText.item_description(definition), Color(0.8, 0.8, 0.8))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size = Vector2(220, 0)
	var footer := PackedStringArray()
	if definition.get_effective_max_stack() > 1:
		footer.append("%d / %d" % [stack.amount, definition.get_effective_max_stack()])
	if show_weight and definition.weight > 0.0:
		footer.append(IKText.t("Weight %s") % _format(definition.weight * stack.amount))
	if not footer.is_empty():
		_add_label("   ".join(footer), MUTED_COLOR)
	reset_size()


func _comparable_slot(definition: IKItemDefinition, source: IKContainer) -> bool:
	return equipment != null and definition.equip_slot != &"" and source != equipment.container \
		and equipment.slot_types.has(definition.equip_slot)


func _worn_definition(definition: IKItemDefinition, source: IKContainer) -> IKItemDefinition:
	if not _comparable_slot(definition, source):
		return null
	var worn := equipment.get_equipped(definition.equip_slot)
	return equipment.container.database.get_item(worn.item_id) if worn != null and equipment.container.database != null else null


# Puts "+8" (green) or "-3" (red) after a stat line; lower stats worn elsewhere count as 0.
func _add_difference(line: Label, definition: IKItemDefinition, worn: IKItemDefinition, property: StringName) -> void:
	var value: Variant = definition.properties[property]
	if not (value is float or value is int):
		return
	var before := float(worn.properties.get(property, 0.0)) if worn != null else 0.0
	var difference := float(value) - before
	if is_zero_approx(difference):
		return
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	_content.add_child(row)
	_content.move_child(row, line.get_index())
	line.reparent(row)
	var delta := _add_label(("+" if difference > 0 else "") + _format(difference), BETTER_COLOR if difference > 0 else WORSE_COLOR, row)
	delta.name = "Difference"


func _add_set_lines(definition: IKItemDefinition) -> void:
	if equipment == null or equipment.set_bonuses == null:
		return
	var set_id := StringName(str(definition.properties.get(equipment.set_property, "")))
	var bonuses: Array = equipment.set_bonuses.get_for_set(set_id) if set_id != &"" else []
	if bonuses.is_empty():
		return
	var worn := equipment.count_set_pieces(set_id)
	_add_label(IKText.t("%s (%d/%d)") % [bonuses[0].get_set_name(), worn, equipment.set_bonuses.get_full_size(set_id)], Color(0.95, 0.85, 0.45))
	for bonus: IKSetBonus in bonuses:
		var active := equipment.is_set_bonus_active(bonus)
		_add_label("  (%d) %s" % [bonus.pieces_required, bonus.describe()], BETTER_COLOR if active else MUTED_COLOR)



func _add_label(text: String, color: Color, parent: Control = null) -> Label:
	var label := Label.new()
	label.text = text
	label.auto_translate_mode = AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	(parent if parent != null else _content).add_child(label)
	return label


static func _format(value: Variant) -> String:
	if value is float:
		return String.num(value, 2).trim_suffix(".0") if value != floorf(value) else str(int(value))
	return str(value)
