class_name IKEquipSlotRule
extends IKSlotRule
## Accepts only items whose [member IKItemDefinition.equip_slot] matches.

@export var equip_slot: StringName


func _init(p_equip_slot: StringName = &"") -> void:
	equip_slot = p_equip_slot


func accepts(_stack: IKItemStack, definition: IKItemDefinition) -> bool:
	return equip_slot != &"" and definition.equip_slot == equip_slot
