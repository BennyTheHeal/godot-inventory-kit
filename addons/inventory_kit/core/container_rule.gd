class_name IKContainerRule
extends Resource
## Constraint applied to a whole container (accepted items, total weight...).
## Extend this class and override one or both methods.

## Shown to players when this rule refuses a change (e.g. "Too heavy."), through
## [method IKText.result_message]. Empty: the generic refusal text.
@export var refusal_text := ""


## Per-item filter, checked whenever a stack enters any slot of the container.
func accepts(_stack: IKItemStack, _definition: IKItemDefinition) -> bool:
	return true


## Whole-container check, run on the final state before a transaction commits.
## [param slots] holds [IKItemStack] or null; do not modify it.
func validate_slots(_slots: Array, _database: IKItemDatabase) -> bool:
	return true


## Called by transactions with the state before and after the change. Override
## it for limits that must still let players fix an invalid state (e.g. allow
## removing items from an overloaded bag). Default: [method validate_slots] on [param after].
func validate_change(_before: Array, after: Array, database: IKItemDatabase) -> bool:
	return validate_slots(after, database)
