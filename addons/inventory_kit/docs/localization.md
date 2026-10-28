# Inventory Kit — Translating and rewording texts

Inventory Kit ships in English, but every text it shows to players goes through Godot's translation system: item names and descriptions, tooltip lines, set bonuses, pickup notifications and refusal messages. You can translate them, or simply reword the English, without touching the code.

## The templates

`addons/inventory_kit/translations/` holds two CSV files in Godot's translation format. The first column (`keys`) is the English text, the second (`en`) the text actually shown:

| File | Content |
|---|---|
| `inventory_kit_core.csv` | Refusal messages, the 10 Lite sample items (all editions) |
| `inventory_kit_standard.csv` | Tooltips (stats, slots, rarities, categories, comparison), set bonuses, pickup notifications, the 120 library items (Full edition) |

## Translate

1. Open the CSV in a spreadsheet and add one column per language, named with its locale code: `fr`, `de`, `es`, `pt_BR`, `ja`, `zh_CN`…
2. Keep the placeholders: `%s` (a text) and `%d` (a number), in the same order. `%s: %s` (stat lines) becomes `%s : %s` in French.
3. Save as UTF-8 CSV. Godot imports it and creates one `.translation` file per language.
4. *Project > Project Settings > Localization > Translations*: add the `.translation` files.
5. Switch the language from your game: `TranslationServer.set_locale("fr")`. Slots update at once; tooltips on the next hover.

To keep your translations safe from addon updates, copy the CSV next to your own game files and translate the copy.

For Chinese, Japanese or Korean, use a theme font that has those characters: Godot's default font does not.

## Reword the English

Edit the `en` column: "Not enough room." can become "Your bag is full." Or, from code:

```gdscript
IKText.result_texts[IKResult.Code.CONTAINER_FULL] = "Your bag is full."
```

## Refusal messages

When an action is refused, show `IKText.result_message(result)` to players:

```gdscript
inventory_ui.interaction_failed.connect(func(result: IKResult) -> void:
	status_label.text = IKText.result_message(result))
```

It uses, in this order:
1. `result.player_text`: the reason given by what refused the action. A container rule's `refusal_text` (`IKWeightRule`: "Too heavy."), or the `IKUseContext.message` of an item effect ("This item cannot be used right now.").
2. The text for its code in `IKText.result_texts` ("Not enough room.", "That item cannot go there."…).

`result.message` stays the technical detail ("Slot 3 does not accept 'sword'."), in English, for logs and debugging.

## Your own items and texts

Item names and descriptions are translated by their English text, so your own items work the same way: add their `display_name` and `description` to a CSV. Set bonus `display_name` and `description`, `refusal_text` of your rules and effect messages too. In your own code, call `IKText.t("Some text")`, or Godot's `tr()`.

After adding a player text to the kit's code, run `python tools/make_translation_template.py` (in the full project) to regenerate the templates. A test checks that none is missing.
