class_name IKMigrations
extends RefCounted
## Upgrades saved documents from older format versions, one step at a time.
##
## Each step is a Callable taking the document at version N and returning it at
## version N + 1. Documents newer than [member target_version] are refused, so a
## save written by a newer build is never loaded and then overwritten.

## Current save format version written by [IKSerializer].
const CURRENT_VERSION := 1

var target_version := CURRENT_VERSION
var _steps: Dictionary = {}  # from_version -> Callable(doc: Dictionary) -> Dictionary


## The built-in migration chain (empty while the format is at version 1).
static func default() -> IKMigrations:
	return IKMigrations.new()


func register(from_version: int, step: Callable) -> IKMigrations:
	_steps[from_version] = step
	return self


## Returns the document at [member target_version], or an empty Dictionary
## with [member IKLoadReport.error] set.
func migrate(doc: Dictionary, report: IKLoadReport) -> Dictionary:
	var version := _read_version(doc)
	if version < 1:
		report.fail("Missing or invalid format version.")
		return {}
	report.source_version = version
	if version > target_version:
		report.fail("Save format v%d is newer than this build (v%d)." % [version, target_version])
		return {}
	var current := doc.duplicate(true)
	while version < target_version:
		if not _steps.has(version):
			report.fail("No migration from format v%d." % version)
			return {}
		var next: Variant = (_steps[version] as Callable).call(current)
		if not next is Dictionary:
			report.fail("Migration from v%d did not return a Dictionary." % version)
			return {}
		current = next
		version += 1
		current["version"] = version
	return current


static func _read_version(doc: Dictionary) -> int:
	var value: Variant = doc.get("version")
	if value is int:
		return value
	if value is float and value == floorf(value):
		return int(value)
	return 0
