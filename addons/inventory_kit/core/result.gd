class_name IKResult
extends RefCounted
## Outcome of an inventory operation or transaction.
##
## Operations never fail silently and never push engine errors for expected
## situations (full bag, missing items...). Check [member ok] and [member code].

enum Code {
	OK,
	INVALID_ARGUMENT,
	UNKNOWN_ITEM,
	SLOT_OUT_OF_RANGE,
	SLOT_EMPTY,
	SLOT_OCCUPIED,
	SLOT_FULL,
	RULE_REJECTED,
	CONTAINER_FULL,
	NOT_ENOUGH_ITEMS,
	NOT_MERGEABLE,
	NOT_SPLITTABLE,
	CONCURRENT_MODIFICATION,
	INVARIANT_VIOLATION,
	TRANSACTION_CLOSED,
	NOT_USABLE,
}

var code: Code = Code.OK
## Technical detail for developers and logs (English, not translated).
var message: String = ""
## Text for players, set by refusals that know a better reason ("Too heavy.").
## Show [method IKText.result_message] to players: it falls back to a text per code.
var player_text: String = ""
## Amount that could not be placed or moved (partial adds, quick transfers).
var remainder: int = 0

var ok: bool:
	get:
		return code == Code.OK


static func success(remainder_amount: int = 0) -> IKResult:
	var result := IKResult.new()
	result.remainder = remainder_amount
	return result


static func failure(error_code: Code, error_message: String = "") -> IKResult:
	var result := IKResult.new()
	result.code = error_code
	result.message = error_message
	return result


func code_name() -> String:
	return Code.keys()[code]


func _to_string() -> String:
	if ok:
		return "IKResult(OK, remainder=%d)" % remainder
	return "IKResult(%s: %s)" % [code_name(), message]
