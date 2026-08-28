class_name Vehicle extends Node3D

# Nodes

@onready var sphere: RigidBody3D = $Sphere
@onready var raycast: RayCast3D = $Ground

@onready var auto_rays: Array[RayCast3D] = [
	$Container/AutoRay0, $Container/AutoRay1, $Container/AutoRay2,
	$Container/AutoRay3, $Container/AutoRay4,
]

# Vehicle elements

@onready var vehicle_model = $Container
@onready var vehicle_body = get_node_or_null("Container/Model/body")

# (Optional) wheels

@onready var wheel_fl = get_node_or_null("Container/Model/wheel-front-left")
@onready var wheel_fr = get_node_or_null("Container/Model/wheel-front-right")
@onready var wheel_bl = get_node_or_null("Container/Model/wheel-back-left")
@onready var wheel_br = get_node_or_null("Container/Model/wheel-back-right")

# Effects

@onready var trail_left = get_node_or_null("Container/TrailLeft")
@onready var trail_right = get_node_or_null("Container/TrailRight")

# Sounds

@onready var screech_sound: AudioStreamPlayer3D = $Container/ScreechSound
@onready var engine_sound: AudioStreamPlayer3D = $Container/EngineSound
@onready var impact_sound: AudioStreamPlayer3D = $Container/ImpactSound

var input: Vector3
var normal: Vector3

var acceleration: float
var angular_speed: float
var linear_speed: float

var colliding: bool

var linear_velocity: Vector3
var prev_position: Vector3

var calculated_lean: float

@export var autopilot: bool = false
var autopilot_brain: Genome = null
var collision_count: int = 0

@export var is_player: bool = false

const AUTO_RAY_RANGE := 10.0

# Public Functions

func get_vehicle_position() -> Vector3: return vehicle_model.global_position
func get_vehicle_basis() -> Basis: return vehicle_model.global_transform.basis

func side_touching_wall() -> bool:
	for r in auto_rays:
		if r.is_colliding() and r.global_position.distance_to(r.get_collision_point()) < 1.8:
			return true
	return false

# Functions

func _ready():
	add_to_group("all_vehicles")
	if is_player:
		add_to_group("player_vehicle")

	if autopilot_brain == null:
		if ResourceLoader.exists("user://best_genome.tres"):
			autopilot_brain = load("user://best_genome.tres")
		elif ResourceLoader.exists("res://ai/best_genome.tres"):
			autopilot_brain = load("res://ai/best_genome.tres")

const FALL_RESET_Y := -5.0
const SPAWN_LOCAL_SPHERE_POS := Vector3(0, 0.5, 0)

func _physics_process(delta):

	# Safety net: driving off the paved cells into decoration-only area (or
	# any other physics glitch) means no floor underneath -- freefall forever
	# otherwise. Teleport back to this vehicle's own spawn point instead.
	if sphere.position.y < FALL_RESET_Y:
		sphere.position = SPAWN_LOCAL_SPHERE_POS
		sphere.linear_velocity = Vector3.ZERO
		sphere.angular_velocity = Vector3.ZERO
		linear_speed = 0.0
		acceleration = 0.0
		angular_speed = 0.0
		return

	handle_input(delta)

	var direction = sign(linear_speed)
	if direction == 0: direction = sign(input.z) if abs(input.z) > 0.1 else 1

	var steering_grip = clamp(abs(linear_speed), 0.35, 1.0)

	var target_angular = -input.x * steering_grip * 3.2 * direction
	angular_speed = lerp(angular_speed, target_angular, delta * 5)

	vehicle_model.rotate_y(angular_speed * delta)

	# Ground alignment

	if raycast.is_colliding():
		if !colliding:
			if vehicle_body != null: vehicle_body.position = Vector3(0, 0.1, 0) # Bounce
			input.z = 0

		normal = raycast.get_collision_normal()

		# Orient model to colliding normal

		if normal.dot(vehicle_model.global_basis.y) > 0.5:
			var xform = align_with_y(vehicle_model.global_transform, normal)
			vehicle_model.global_transform = vehicle_model.global_transform.interpolate_with(xform, 0.2).orthonormalized()

	colliding = raycast.is_colliding()

	var target_speed = input.z

	if (target_speed < 0 and linear_speed > 0.01):
		linear_speed = lerp(linear_speed, 0.0, delta * 8)
	else:
		if (target_speed < 0):
			linear_speed = lerp(linear_speed, target_speed / 2, delta * 2)
		else:
			linear_speed = lerp(linear_speed, target_speed, delta * 6)

	acceleration = lerpf(acceleration, linear_speed + (abs(sphere.angular_velocity.length() * linear_speed) / 100), delta * 1)

	# Match vehicle model to physics sphere

	vehicle_model.position = sphere.position - Vector3(0, 0.65, 0)
	raycast.position = sphere.position

	# Calculate vehicle model linear velocity

	linear_velocity = (vehicle_model.position - prev_position) / delta
	prev_position = vehicle_model.position

	# Visual and audio effects

	effect_engine(delta)
	effect_body(delta)
	effect_wheels(delta)
	effect_trails()

# Handle input when vehicle is colliding with ground

func handle_input(delta):

	# "auto" is a shared global input action -- every vehicle's handle_input()
	# runs each physics frame and would otherwise all see the same button
	# press and toggle their own autopilot together. Only the player's own
	# vehicle should react to it; the AI cars keep whatever autopilot state
	# they were spawned with.
	if is_player and Input.is_action_just_pressed("auto"):
		autopilot = !autopilot

	if raycast.is_colliding():
		if autopilot:
			handle_autopilot(delta)
		else:
			input.x = Input.get_axis("left", "right")
			input.z = Input.get_axis("back", "forward")

	sphere.angular_velocity += vehicle_model.get_global_transform().basis.x * (linear_speed * 100) * delta

# Self-driving: neural net brain (trained via simulation, see scripts/ai/trainer.gd)
# reads the 5-ray sensor fan + speed, outputs steer/throttle. Falls back to a dumb
# wall-avoidance heuristic if no trained genome is loaded.

func handle_autopilot(delta):

	if autopilot_brain == null:
		handle_autopilot_heuristic(delta)
		return

	var inputs := PackedFloat32Array()
	inputs.resize(6)
	for i in auto_rays.size():
		var r = auto_rays[i]
		var dist = AUTO_RAY_RANGE
		if r.is_colliding():
			dist = r.global_position.distance_to(r.get_collision_point())
		inputs[i] = clamp(dist / AUTO_RAY_RANGE, 0.0, 1.0)
	inputs[5] = clamp(linear_speed, -1.0, 1.0)

	var out = autopilot_brain.forward(inputs)
	input.x = lerp(input.x, clamp(out[0], -1.0, 1.0), delta * 8)
	input.z = lerp(input.z, clamp(out[1], -1.0, 1.0), delta * 8)

func handle_autopilot_heuristic(delta):

	input.z = 1.0

	var left = auto_rays[0]
	var right = auto_rays[4]
	var steer = 0.0

	if left.is_colliding() and right.is_colliding():
		var dist_left = left.global_position.distance_to(left.get_collision_point())
		var dist_right = right.global_position.distance_to(right.get_collision_point())
		steer = 1.0 if dist_left < dist_right else -1.0
	elif left.is_colliding():
		steer = 1.0
	elif right.is_colliding():
		steer = -1.0

	input.x = lerp(input.x, steer, delta * 6)

func effect_body(delta):
	
	calculated_lean = lerp_angle(calculated_lean, -input.x / 5 * linear_speed, delta * 5)
	
	# Slightly tilt (and move) body based on acceleration and steering
	
	if vehicle_body != null:
		
		vehicle_body.rotation.x = lerp_angle(vehicle_body.rotation.x, -(linear_speed - acceleration) / 6, delta * 10)
		vehicle_body.rotation.z = calculated_lean
		
		vehicle_body.position = vehicle_body.position.lerp(Vector3(0, 0.2, 0), delta * 5)
	
func effect_wheels(delta):

	# Rotate wheels based on acceleration

	for wheel in [wheel_fl, wheel_fr, wheel_bl, wheel_br]:
		if wheel != null:
			wheel.rotation.x += acceleration

	# Rotate front wheels based on steering direction

	if wheel_fl != null: wheel_fl.rotation.y = lerp_angle(wheel_fl.rotation.y, -input.x / 1.5, delta * 10)
	if wheel_fr != null: wheel_fr.rotation.y = lerp_angle(wheel_fr.rotation.y, -input.x / 1.5, delta * 10)

# Engine sounds

func effect_engine(delta):

	var speed_factor = clamp(abs(linear_speed), 0.0, 1.0)
	var throttle_factor = clamp(abs(input.z), 0.0, 1.0)

	var target_volume = remap(speed_factor + (throttle_factor * 0.5), 0.0, 1.5, -15.0, -5.0)
	engine_sound.volume_db = lerp(engine_sound.volume_db, target_volume, delta * 5.0)

	var target_pitch = remap(speed_factor, 0.0, 1.0, 0.5, 3)
	if throttle_factor > 0.1: target_pitch += 0.2

	engine_sound.pitch_scale = lerp(engine_sound.pitch_scale, target_pitch, delta * 2.0)

# Show trails (and play skid sound)

func effect_trails():

	var drift_intensity = abs(linear_speed - acceleration) + (abs(calculated_lean) * 2.0)
	var should_emit = drift_intensity > 0.25

	if trail_left != null: trail_left.emitting = should_emit
	if trail_right != null: trail_right.emitting = should_emit

	var target_volume = -80.0
	if should_emit: target_volume = remap(clamp(drift_intensity, 0.25, 2.0), 0.25, 2.0, -10.0, 0.0)

	screech_sound.pitch_scale = lerp(screech_sound.pitch_scale, clamp(abs(linear_speed), 1.0, 3.0), 0.1)
	screech_sound.volume_db = lerp(screech_sound.volume_db, target_volume, 10.0 * get_physics_process_delta_time())

# Align vehicle with normal

func align_with_y(xform, new_y):

	xform.basis.y = new_y
	xform.basis.x = -xform.basis.z.cross(new_y)
	xform.basis = xform.basis.orthonormalized()
	return xform

# Detect collisions and play impact sound

func _on_sphere_body_entered(_body: Node) -> void:
	
	if vehicle_body == null: return
	
	collision_count += 1

	if not impact_sound.playing:
		var impact_velocity := absf(linear_velocity.dot(vehicle_body.global_basis.z))
		impact_sound.volume_db = clampf(remap(impact_velocity, 0.0, 6.0, -20.0, 0.0), -20.0, 0.0)
		impact_sound.play()
