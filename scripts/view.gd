extends Node3D

@export_group("Properties")
@export var target: Vehicle
@export var camera_height := 3.2
@export var camera_pitch_degrees := -14.0
@export var follow_speed := 4.0
@export var turn_speed := 3.0

@onready var camera = $Camera

func _ready():
	camera.rotation_degrees.x = camera_pitch_degrees

func _physics_process(delta):

	# Ease position towards target vehicle position

	self.position = self.position.lerp(target.get_vehicle_position(), delta * follow_speed)

	# Ease rotation to match vehicle heading, so the camera stays behind the car

	var target_yaw = target.get_vehicle_basis().get_euler().y + PI
	rotation.y = lerp_angle(rotation.y, target_yaw, delta * turn_speed)

	# Zoom camera based on the speed of the vehicle

	var speed_factor = clamp(abs(target.linear_speed), 0.0, 1.0)
	var target_z = remap(speed_factor, 0.0, 1.0, 6, 12)

	camera.position.z = lerp(camera.position.z, target_z, delta * 0.5)
	camera.position.y = camera_height
