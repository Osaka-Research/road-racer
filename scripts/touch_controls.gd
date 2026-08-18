extends CanvasLayer

func _ready() -> void:
	_bind($SteerLeft, "left")
	_bind($SteerRight, "right")
	_bind($Accelerate, "forward")
	_bind($Brake, "back")
	_bind($Bounce, "bounce")
	_bind($Auto, "auto")

func _bind(button: Button, action: String) -> void:
	button.button_down.connect(func(): Input.action_press(action))
	button.button_up.connect(func(): Input.action_release(action))
