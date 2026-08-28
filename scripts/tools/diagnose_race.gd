extends Node3D

# Headless diagnostic: logs every vehicle's driving state on an interval so
# odd behavior (unexplained braking, reversing, getting stuck) shows up in
# the log instead of only being visible on-screen.
# Run: godot --headless --fixed-fps 60 --audio-driver Dummy scenes/diagnose.tscn

const DURATION := 25.0
const LOG_INTERVAL := 0.5

var elapsed := 0.0
var next_log := 0.0

func _physics_process(delta: float) -> void:
	elapsed += delta
	if elapsed >= next_log:
		next_log += LOG_INTERVAL
		for v in get_tree().get_nodes_in_group("all_vehicles"):
			var rays := []
			for r in v.auto_rays:
				rays.append("%.1f" % (r.global_position.distance_to(r.get_collision_point()) if r.is_colliding() else -1.0))
			var opp = v._nearest_opponent_info() if v.has_method("_nearest_opponent_info") else Vector3.ZERO
			print("%.1fs %s speed=%.2f input=(%.2f,%.2f) rays=[%s] opp=(fwd%.2f,lat%.2f,relspd%.2f) colliding=%s" % [
				elapsed, v.name, v.linear_speed, v.input.x, v.input.z,
				", ".join(rays), opp.x, opp.y, opp.z, v.colliding
			])
	if elapsed >= DURATION:
		print("diagnose done")
		get_tree().quit()
