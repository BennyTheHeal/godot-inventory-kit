class_name IKLoadOptions
extends RefCounted
## Settings for [method IKSerializer.load_into].

## Renamed items: old id -> new id (e.g. {&"iron_sword": &"sword_iron"}).
var item_aliases: Dictionary = {}
## Keep stacks whose item no longer exists in the database, untouched, so they
## survive the next save (true), or drop them with a warning (false).
var keep_unknown_items := true
## Format migrations to apply. Null = [method IKMigrations.default].
var migrations: IKMigrations = null
