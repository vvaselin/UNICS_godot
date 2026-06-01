extends CharacterBody3D

const SPEED = 3.0
const JUMP_VELOCITY = 3.0
const ROTATION_SPEED = 10.0

@onready var sprite: AnimatedSprite3D= $Katawara
@onready var animation_tree = $AnimationTree
@onready var state_machine :AnimationNodeStateMachinePlayback = animation_tree.get("parameters/playback")

@onready var visuals_node: Node3D = $Ruru

var is_facing_right: bool = true
var is_3d_mode: bool = false

func _ready() -> void:
	if is_3d_mode:
		visuals_node.visible = true
		sprite.visible = false
	else:
		visuals_node.visible = false
		sprite.visible = true

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("JUMP") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("LEFT", "RIGHT", "UP", "DOWN")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
	if direction.length() > 0.001:
		var target_angle = atan2(direction.x, direction.z)

		visuals_node.rotation.y = lerp_angle(visuals_node.rotation.y, target_angle, ROTATION_SPEED * delta)

	if input_dir.x > 0:
		is_facing_right = true
	elif input_dir.x < 0:
		is_facing_right = false

	# アニメーション
	var is_moving = Vector2(velocity.x, velocity.z).length() > 0.01
	if is_3d_mode:
		# --- 3Dモデル (Ruru) のアニメーション制御 ---
		if is_moving:
			walk()
		else:
			idle()
	else:
		# --- 2Dスプライト (Katawara) のアニメーション制御 ---
		if is_moving:
			if is_facing_right:
				sprite.play("walk_R")
			else:
				sprite.play("walk_L")
		else:
			if is_facing_right:
				sprite.play("idle_R")
			else:
				sprite.play("idle_L")

func walk():
	state_machine.travel("Walking")
	
func idle():
	state_machine.travel("DwarfIdle")


func _on_player切り替え_pressed() -> void:
	is_3d_mode = !is_3d_mode
	
	# モードに合わせて表示・非表示を切り替える
	if is_3d_mode:
		visuals_node.visible = true
		sprite.visible = false
		
		# 3Dに切り替わった時、2Dのアニメーションを止めておく
		sprite.stop()
	else:
		visuals_node.visible = false
		sprite.visible = true
