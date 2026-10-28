class_name IKSlotRule
extends Resource
## Decides whether a stack may occupy one specific slot.
## Extend this class and override [method accepts] for custom slot filters.


func accepts(_stack: IKItemStack, _definition: IKItemDefinition) -> bool:
	return true
