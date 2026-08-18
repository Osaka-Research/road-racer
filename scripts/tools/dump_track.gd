extends SceneTree

# One-off inspector: decode the GridMap's cells into human-readable
# (x, z, item name, orientation) tuples so a track layout can be understood
# and edited programmatically without a visual editor.
# Run: godot --headless --script res://scripts/tools/dump_track.gd

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var gm: GridMap = main.get_node("GridMap")
	var lib: MeshLibrary = gm.mesh_library

	print("--- mesh library items ---")
	for id in lib.get_item_list():
		print("%d: %s" % [id, lib.get_item_name(id)])

	print("--- cells (sorted) ---")
	var cells := gm.get_used_cells()
	var arr: Array = []
	for c in cells:
		arr.append(c)
	arr.sort_custom(func(a, b):
		if a.x != b.x: return a.x < b.x
		return a.z < b.z
	)
	for c in arr:
		var item := gm.get_cell_item(c)
		var orientation := gm.get_cell_item_orientation(c)
		print("(%d, %d, %d) item=%d (%s) orientation=%d" % [c.x, c.y, c.z, item, lib.get_item_name(item), orientation])

	print("total cells: %d" % arr.size())
	quit()
