extends Node3D

## Speed-boost pickup: spins in place, boosts whichever vehicle drives
## through it (player or AI -- anything with an apply_speed_boost method),
## then hides and respawns after a cooldown.

@export var boost_multiplier: float = 1.8
@export var boost_duration: float = 2.2
@export var respawn_time: float = 4.0

@onready var ring: MeshInstance3D = $Ring
@onready var collision_shape: CollisionShape3D = $Area3D/CollisionShape3D

var _cooldown: float = 0.0

func _process(delta: float) -> void:
	ring.rotate_y(delta * 2.0)
	if _cooldown > 0.0:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_activate()

func _on_area_3d_body_entered(body: Node) -> void:
	if _cooldown > 0.0:
		return
	if not (body is RigidBody3D) or body.name != "Sphere":
		return
	var vehicle = body.get_parent()
	if vehicle == null or not vehicle.has_method("apply_speed_boost"):
		return
	vehicle.apply_speed_boost(boost_multiplier, boost_duration)
	_deactivate()

func _deactivate() -> void:
	visible = false
	collision_shape.disabled = true
	_cooldown = respawn_time

func _activate() -> void:
	visible = true
	collision_shape.disabled = false
