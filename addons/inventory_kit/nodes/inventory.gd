class_name IKInventory
extends Node
## Scene-friendly owner of one [IKContainer]: set it up in the inspector, then
## point an [IKContainerView] at it. Access the data through [member container].

@export var container_id: StringName = &"inventory"
## Number of slots (grid mode: cells, rounded up to whole rows).
@export_range(0, 512) var size: int = 20
@export var database: IKItemDatabase
## Grid mode: number of columns, items take [member IKItemDefinition.grid_size]
## cells. 0 = classic slots (default).
@export_range(0, 64) var grid_width: int = 0
## Added once, when the node is ready. Loading a save afterwards replaces them.
@export var initial_items: Dictionary[StringName, int] = {}

var container: IKContainer:
	get:
		if _container == null:
			if grid_width > 0:
				var rows := ceili(size / float(grid_width))
				_container = IKContainer.create_grid(container_id, grid_width, rows, database)
			else:
				_container = IKContainer.new(container_id, size, database)
			_configure_container(_container)
		return _container

var _container: IKContainer


## Called once when the container is created. Override to add rules, connect signals...
func _configure_container(_new_container: IKContainer) -> void:
	pass


func _ready() -> void:
	for item_id in initial_items:
		var result := container.add(item_id, initial_items[item_id], true)
		if not result.ok or result.remainder > 0:
			push_warning("IKInventory '%s': could not add all initial '%s' (%s)." % [container_id, item_id, result])
