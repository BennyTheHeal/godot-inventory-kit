class_name IKSetBonusList
extends Resource
## Every set bonus of a game, in one resource to assign to [member IKEquipment.set_bonuses].

@export var bonuses: Array[IKSetBonus] = []


## Bonuses of one set, sorted by pieces required.
func get_for_set(set_id: StringName) -> Array[IKSetBonus]:
	var result: Array[IKSetBonus] = []
	for bonus in bonuses:
		if bonus != null and bonus.set_id == set_id:
			result.append(bonus)
	result.sort_custom(func(a: IKSetBonus, b: IKSetBonus) -> bool: return a.pieces_required < b.pieces_required)
	return result


## Number of pieces needed for the biggest bonus of the set (0 if it has none).
func get_full_size(set_id: StringName) -> int:
	var bonuses_of_set := get_for_set(set_id)
	return bonuses_of_set.back().pieces_required if not bonuses_of_set.is_empty() else 0
