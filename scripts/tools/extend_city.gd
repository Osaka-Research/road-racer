extends SceneTree

# One-off track generator: scales up the existing rectangular loop by
# lengthening each straight run (same pieces/orientations, just more of
# them), keeping every corner's turn direction identical to the original
# hand-authored track (so connections stay geometrically correct), then
# fills the surrounding area with decoration-forest to read as a bigger
# "city block". Self-verifies the loop closes before saving anything.
#
# Run: godot --headless --script res://scripts/tools/extend_city.gd

const SCALE := 2  # multiply each straight run's length by this

# Original path, decoded from the shipped track via dump_track.gd:
# each entry: [dir_x, dir_z, steps, straight_orientation, corner_item, corner_orientation]
# steps = 0 means "no straight, place the corner immediately" (the S-kink).
const MOVES := [
	[0, -1, 2, 0, 3, 0],
	[-1, 0, 2, 22, 3, 16],
	[0, 1, 1, 0, 3, 10],
	[1, 0, 0, 16, 3, 0],
	[0, 1, 2, 10, 3, 10],
	[1, 0, 1, 16, 3, 22],
	[0, -1, 1, 0, -1, -1],  # last leg: runs straight back into the finish tile, no corner
]

const ITEM_FOREST := 1
const ITEM_FINISH := 4
const ITEM_STRAIGHT := 6
const ITEM_CORNER := 3

func _initialize() -> void:
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var gm: GridMap = main.get_node("GridMap")

	# Clear the old (small) track pieces so nothing is left floating inside
	# the new bigger loop -- replace with forest to match the surrounding dressing.
	for c in gm.get_used_cells():
		var item := gm.get_cell_item(c)
		if item == ITEM_CORNER or item == ITEM_STRAIGHT:
			gm.set_cell_item(c, ITEM_FOREST, 10)
		elif item == ITEM_FINISH:
			pass  # keep the finish tile where it is

	var pos := Vector3i(0, 0, 0)
	var new_track_cells: Dictionary = {}  # Vector3i -> [item, orientation]
	new_track_cells[pos] = [ITEM_FINISH, 0]

	for move in MOVES:
		var dx: int = move[0]
		var dz: int = move[1]
		var steps: int = move[2]
		var straight_o: int = move[3]
		var corner_item: int = move[4]
		var corner_o: int = move[5]

		# Every leg ends with one extra step (placing a corner, or closing
		# onto the finish tile) beyond its straight run. Scale the leg's
		# TOTAL displacement uniformly, not just the straight-cell count --
		# that's what keeps sum(x)=0 and sum(z)=0, i.e. the loop closes,
		# for a non-rectangular path (this one has a jog in it).
		var total_disp := steps + 1
		var scaled_total := total_disp * SCALE
		var scaled_steps := scaled_total - 1

		for i in scaled_steps:
			pos += Vector3i(dx, 0, dz)
			new_track_cells[pos] = [ITEM_STRAIGHT, straight_o]

		if corner_item != -1:
			pos += Vector3i(dx, 0, dz)
			new_track_cells[pos] = [corner_item, corner_o]
		else:
			# Last leg: one more step lands exactly on the pre-placed finish
			# tile -- don't overwrite it, just close the loop onto it.
			pos += Vector3i(dx, 0, dz)

	# Self-check: the path must close exactly back onto the finish tile.
	if pos != Vector3i(0, 0, 0):
		push_error("TRACK DOES NOT CLOSE: ended at %s, expected (0,0,0). Aborting, nothing saved." % pos)
		print("ABORT: track does not close, ended at ", pos)
		quit(1)
		return

	print("track closes correctly, %d cells" % new_track_cells.size())

	var min_x := 0
	var max_x := 0
	var min_z := 0
	var max_z := 0
	for c in new_track_cells.keys():
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.z)
		max_z = maxi(max_z, c.z)

	for c in new_track_cells.keys():
		var v = new_track_cells[c]
		gm.set_cell_item(c, v[0], v[1])

	# City dressing: fill everything in a padded bounding box around the new
	# track that isn't a track cell with forest, so there's no bare gap.
	const PAD := 2
	for x in range(min_x - PAD, max_x + PAD + 1):
		for z in range(min_z - PAD, max_z + PAD + 1):
			var c := Vector3i(x, 0, z)
			if not new_track_cells.has(c) and gm.get_cell_item(c) == GridMap.INVALID_CELL_ITEM:
				gm.set_cell_item(c, ITEM_FOREST, 10)

	var packed := PackedScene.new()
	packed.pack(main)
	var err := ResourceSaver.save(packed, "res://scenes/main.tscn")
	if err != OK:
		print("ABORT: save failed with error ", err)
		quit(1)
		return

	print("saved scenes/main.tscn, bounds x[%d,%d] z[%d,%d]" % [min_x, max_x, min_z, max_z])
	quit()
