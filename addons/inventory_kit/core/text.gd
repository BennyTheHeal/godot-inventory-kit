class_name IKText
extends RefCounted
## Every text Inventory Kit shows to players goes through here, so it can be
## translated or reworded with Godot's own translation system.
##
## The English text is the translation key: add a column to
## [code]addons/inventory_kit/translations/*.csv[/code] (or your own CSV / PO file),
## register it in Project Settings > Localization, and call
## [code]TranslationServer.set_locale("fr")[/code]. Editing the "en" column rewords
## the English text without touching the code. See docs/localization.md.

## Player text for each failure code. Replace entries to reword them in code, e.g.
## [code]IKText.result_texts[IKResult.Code.CONTAINER_FULL] = "Your bag is full."[/code]
static var result_texts := {
	IKResult.Code.INVALID_ARGUMENT: "That did not work.",
	IKResult.Code.UNKNOWN_ITEM: "Unknown item.",
	IKResult.Code.SLOT_OUT_OF_RANGE: "That did not work.",
	IKResult.Code.SLOT_EMPTY: "There is nothing there.",
	IKResult.Code.SLOT_OCCUPIED: "That slot is taken.",
	IKResult.Code.SLOT_FULL: "That slot is full.",
	IKResult.Code.RULE_REJECTED: "That item cannot go there.",
	IKResult.Code.CONTAINER_FULL: "Not enough room.",
	IKResult.Code.NOT_ENOUGH_ITEMS: "Not enough items.",
	IKResult.Code.NOT_MERGEABLE: "These items do not stack together.",
	IKResult.Code.NOT_SPLITTABLE: "This stack cannot be split.",
	IKResult.Code.CONCURRENT_MODIFICATION: "The inventory changed. Try again.",
	IKResult.Code.INVARIANT_VIOLATION: "That did not work.",
	IKResult.Code.TRANSACTION_CLOSED: "That did not work.",
	IKResult.Code.NOT_USABLE: "This item cannot be used.",
}


## Translates [param text] for the current locale (unchanged without a translation).
static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


## What to tell the player about a refused action: [member IKResult.player_text]
## when the refusal set one (a rule, an item effect), else the text for its code.
## [member IKResult.message] stays the technical detail, for logs.
static func result_message(result: IKResult) -> String:
	if result == null or result.ok:
		return ""
	if not result.player_text.is_empty():
		return t(result.player_text)
	return t(result_texts.get(result.code, "That did not work."))


static func item_name(definition: IKItemDefinition) -> String:
	if definition == null:
		return ""
	return t(definition.display_name) if not definition.display_name.is_empty() else String(definition.id)


static func item_description(definition: IKItemDefinition) -> String:
	return t(definition.description) if definition != null else ""


## A data key shown as a label: &"fire_resist" -> "Fire Resist", translated.
static func label(key: StringName) -> String:
	return t(String(key).capitalize())
