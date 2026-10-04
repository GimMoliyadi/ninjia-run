extends Node2D

signal jumped(jump_index: int)
signal landed(speed: float)
signal run_reset

enum MovementState { GROUNDED, AIRBORNE, SLIDE, ROPE }
enum RopeSide { TOP, BOTTOM }
enum AirState { NONE, FIRST_JUMP, DOUBLE_JUMP_ROLL, SECOND_JUMP, FALL }

const RUN_SPEED := 400.0
const PLAYER_HEIGHT := 66.0
const ROLL_HEIGHT := 40.0
const DOUBLE_JUMP_ROLL_DURATION := 0.32

var active := true
var movement_state := MovementState.GROUNDED
var air_state := AirState.NONE
var rope_side := RopeSide.TOP
var velocity := Vector2(RUN_SPEED, 0.0)
var rope_flip_progress := 0.0
var rope_flip_angle := 0.0
var roll_remaining := 0.0
var roll_hitbox_active := false
var flipping := false


func is_rope_flipping() -> bool:
	return flipping


func is_sliding() -> bool:
	return movement_state == MovementState.SLIDE


func snapshot() -> Array:
	return [active, movement_state, air_state, rope_side, velocity, rope_flip_progress,
		rope_flip_angle, roll_remaining, roll_hitbox_active, flipping, position]
