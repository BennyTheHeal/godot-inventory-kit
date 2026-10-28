class_name IKSetBonus
extends Resource
## Bonus granted while enough pieces of one item set are worn in an [IKEquipment].
##
## An item belongs to a set through its [code]properties["set"][/code] entry
## (e.g. [code]"iron"[/code]). Give a set several bonuses for 2 and 4 pieces.

@export var set_id: StringName
## Name shown in tooltips (e.g. "Iron set"), translated through [IKText].
## Empty: generated from [member set_id].
@export var display_name := ""
@export_range(1, 16) var pieces_required := 2
## Added to [method IKEquipment.sum_property] while active, e.g. {"armor": 4}.
@export var properties: Dictionary = {}
## Shown in tooltips, translated through [IKText]. Empty: generated from
## [member properties] ("+4 Armor").
@export var description := ""


func _init(p_set_id: StringName = &"", p_pieces_required: int = 2, p_properties: Dictionary = {}) -> void:
	set_id = p_set_id
	pieces_required = p_pieces_required
	properties = p_properties.duplicate()


func get_set_name() -> String:
	if not display_name.is_empty():
		return IKText.t(display_name)
	return IKText.t("%s set") % IKText.label(set_id)


func describe() -> String:
	if not description.is_empty():
		return IKText.t(description)
	var parts := PackedStringArray()
	for key in properties:
		var value: Variant = properties[key]
		var text := str(value)
		if value is float or value is int:
			text = ("+" if value >= 0 else "") + IKTooltip._format(value)
		parts.append(IKText.t("%s %s") % [text, IKText.label(StringName(key))])
	return ", ".join(parts)
