extends Node

# Live dev channel: loopback-only TCP server so Termux can talk to the
# running APK without rebuilding. Line-based text protocol, one command per line.
#
# From Termux (device-local, same phone only):
#   echo state | nc 127.0.0.1 9999
#
# Commands:
#   state              -> JSON telemetry (position, speed, autopilot, collisions)
#   auto on/off        -> toggle self-driving
#   push_brain <b64>   -> write base64-encoded .tres bytes to user://best_genome.tres
#                         (push a freshly-trained genome from Termux with no
#                         reinstall needed; adb is broken in this setup, so this
#                         socket is the delivery channel instead)
#   reload_brain       -> hot-swap the NN weights from user://best_genome.tres
#                         (call after push_brain, or after `termux-open`ing a
#                         new build normally already picks it up on launch)

const PORT := 9999

var server := TCPServer.new()
var clients: Array[StreamPeerTCP] = []
var buffers: Dictionary = {}   # StreamPeerTCP -> String, buffers partial lines across frames
var vehicle: Vehicle

func _ready() -> void:
	var err := server.listen(PORT, "127.0.0.1")
	if err != OK:
		push_warning("debug_server: failed to listen on %d (%s)" % [PORT, err])

func _process(_delta: float) -> void:
	if server.is_listening() and server.is_connection_available():
		var c := server.take_connection()
		clients.append(c)
		buffers[c] = ""

	for c in clients.duplicate():
		c.poll()
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.erase(c)
			buffers.erase(c)
			continue

		var avail: int = c.get_available_bytes()
		if avail > 0:
			buffers[c] += c.get_utf8_string(avail)

		while true:
			var nl: int = (buffers[c] as String).find("\n")
			if nl == -1:
				break
			var line: String = (buffers[c] as String).substr(0, nl).strip_edges()
			buffers[c] = (buffers[c] as String).substr(nl + 1)
			if line != "":
				_handle_command(c, line)

func _handle_command(c: StreamPeerTCP, cmd: String) -> void:
	if vehicle == null:
		vehicle = get_tree().get_first_node_in_group("player_vehicle")

	if cmd.begins_with("push_brain "):
		var content := Marshalls.base64_to_raw(cmd.substr(11)).get_string_from_utf8()
		var f := FileAccess.open("user://best_genome.tres", FileAccess.WRITE)
		f.store_string(content)
		f.close()
		c.put_utf8_string("ok saved\n")
		return

	match cmd:
		"state":
			c.put_utf8_string(_state_json() + "\n")
		"vehicles":
			c.put_utf8_string(_vehicles_json() + "\n")
		"auto on":
			if vehicle: vehicle.autopilot = true
			c.put_utf8_string("ok\n")
		"auto off":
			if vehicle: vehicle.autopilot = false
			c.put_utf8_string("ok\n")
		"reload_brain":
			if vehicle == null:
				c.put_utf8_string("error no vehicle\n")
			else:
				var path := "user://best_genome.tres" if ResourceLoader.exists("user://best_genome.tres") else "res://ai/best_genome.tres"
				vehicle.autopilot_brain = load(path)
				c.put_utf8_string("ok loaded %s\n" % path)
		_:
			c.put_utf8_string("error unknown command: %s\n" % cmd)

func _vehicles_json() -> String:
	var list := []
	for node in get_tree().get_nodes_in_group("all_vehicles"):
		var v: Vehicle = node
		var pos: Vector3 = v.get_vehicle_position()
		list.append({
			"name": v.name,
			"is_player": v.is_player,
			"position": [pos.x, pos.y, pos.z],
		})
	return JSON.stringify(list)

func _state_json() -> String:
	if vehicle == null:
		return "{}"
	var pos := vehicle.get_vehicle_position()
	var data := {
		"position": [pos.x, pos.y, pos.z],
		"speed": vehicle.linear_speed,
		"autopilot": vehicle.autopilot,
		"collisions": vehicle.collision_count,
	}
	return JSON.stringify(data)
