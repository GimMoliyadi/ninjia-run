extends SceneTree

const PLAYER_SCENE := preload("res://player.tscn")
const COMBAT_SCRIPT := preload("res://components/player_combat.gd")

func _initialize() -> void:
	call_deferred("check_animation")

func check_animation() -> void:
	var player := PLAYER_SCENE.instantiate()
	root.add_child(player)
	var body := player.get_node("PlayerVisual/Orientation/ActionPivot/Body")
	var visual := player.get_node("PlayerVisual")
	player.movement_state = player.MovementState.GROUNDED
	visual.update_pose(0.0)
	var skeleton := player.get_node("PlayerVisual/Orientation/ActionPivot/Body/RunSkeleton")
	assert(skeleton.visible)
	assert(visual.run_animation.current_animation == "run")
	assert(not body.get_node("Sword").visible)
	var run_weapon := skeleton.get_node("Hip/Torso/UpperArm_R/Forearm_R/WeaponBone")
	assert(not run_weapon.visible)
	player.movement_state = player.MovementState.AIRBORNE
	visual.update_pose(0.0)
	assert(not skeleton.visible)
	var spawner := player.get_node("PlayerVisual/GhostSpawner")
	spawner.spawn_ghost()
	var ghost := spawner.get_child(0)
	assert(ghost.sword_hand_position() == body.sword_hand_position())
	var combat := COMBAT_SCRIPT.new()
	root.add_child(combat)
	combat.slash_remaining = combat.SWORD_DURATION * 0.5
	body.get_node("Sword").combat = combat
	visual.update_pose(0.0)
	assert(body.get_node("Sword").visible)
	combat.slash_remaining = 0.0
	visual.update_pose(0.0)
	assert(not body.get_node("Sword").visible)
	player.movement_state = player.MovementState.GROUNDED
	combat.slash_remaining = combat.SWORD_DURATION * 0.5
	visual.update_pose(0.0)
	assert(body.get_node("Sword").visible)
	assert(not run_weapon.visible)
	combat.slash_remaining = 0.0
	visual.update_pose(0.0)
	assert(not run_weapon.visible)
	await process_frame
	await process_frame
	quit()
