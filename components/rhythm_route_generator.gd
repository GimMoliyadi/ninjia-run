class_name RhythmRouteGenerator
extends RefCounted

enum ChunkKind {
	SAFE, SINGLE_JUMP, DOUBLE_JUMP, SLIDE_INTRO, REST, ROPE, MIXED,
	TRIPLE_JUMP, SLALOM, ROPE_SWITCH, COMBO, FINISH, DARTS, JUMP_MAP,
	ROPE_MAP, PLATFORM_DART_MAP, NINJA_MAP,
	JUMP_SLIDE_PHRASE, SLIDE_PLATFORM_PHRASE, DART_JUMP_SLIDE_PHRASE,
	SHORT_RECOVERY,
}

enum Rhythm { REGULAR, RANDOM, SWING }

const GROUP_COUNT := 3
const ENCOUNTERS_PER_GROUP := 3
const COMPLETE_MAPS: Array[int] = [
	ChunkKind.DARTS, ChunkKind.JUMP_MAP, ChunkKind.ROPE_MAP,
	ChunkKind.PLATFORM_DART_MAP, ChunkKind.NINJA_MAP,
]
const REGULAR_ENCOUNTERS: Array[int] = [
	ChunkKind.SINGLE_JUMP, ChunkKind.DOUBLE_JUMP, ChunkKind.SLIDE_INTRO,
]
const RANDOM_ENCOUNTERS: Array[int] = [
	ChunkKind.MIXED, ChunkKind.SLALOM, ChunkKind.ROPE_SWITCH, ChunkKind.COMBO,
]
const SWING_ENCOUNTERS: Array[int] = [
	ChunkKind.SINGLE_JUMP, ChunkKind.COMBO, ChunkKind.SLIDE_INTRO,
]
const ACTION_COMBINATIONS: Array[int] = [
	ChunkKind.JUMP_SLIDE_PHRASE,
	ChunkKind.SLIDE_PLATFORM_PHRASE,
	ChunkKind.DART_JUMP_SLIDE_PHRASE,
]
const CONTENT_PROFILES := {
	ChunkKind.DARTS: {"theme": "Dart", "variant": "Dart_Map_A", "difficulty": 1},
	ChunkKind.JUMP_MAP: {"theme": "Jump", "variant": "Jump_Map_A", "difficulty": 1},
	ChunkKind.ROPE_MAP: {"theme": "Rope", "variant": "Rope_Map_A", "difficulty": 1},
	ChunkKind.PLATFORM_DART_MAP: {"theme": "PlatformDart", "variant": "Platform_Dart_Map_A", "difficulty": 2},
	ChunkKind.NINJA_MAP: {"theme": "Ninja", "variant": "Ninja_Map_A", "difficulty": 2},
	ChunkKind.SINGLE_JUMP: {"theme": "Jump", "variant": "Jump_A", "difficulty": 1},
	ChunkKind.JUMP_SLIDE_PHRASE: {"theme": "Mixed", "variant": "Jump_Slide_Phrase", "difficulty": 1},
	ChunkKind.SLIDE_PLATFORM_PHRASE: {"theme": "Mixed", "variant": "Slide_Platform_Phrase", "difficulty": 1},
	ChunkKind.DART_JUMP_SLIDE_PHRASE: {"theme": "Mixed", "variant": "Dart_Jump_Slide_Phrase", "difficulty": 1},
}

var base_seed: int

func _init(seed: int) -> void:
	base_seed = seed

func build_cycle(cycle_index: int) -> Array[int]:
	var random := RandomNumberGenerator.new()
	random.seed = base_seed + cycle_index
	var route: Array[int] = [ChunkKind.SAFE]
	var map_order := _shuffled_maps(random)
	var map_index := 0
	for group in GROUP_COUNT:
		var group_start := route.size()
		var rhythm := random.randi_range(Rhythm.REGULAR, Rhythm.SWING) if group == 0 else Rhythm.RANDOM
		_append_rhythm_group(route, rhythm, random)
		for encounter in ENCOUNTERS_PER_GROUP:
			if map_index >= map_order.size():
				break
			route[group_start + encounter] = map_order[map_index]
			map_index += 1
		route.append(ChunkKind.FINISH if group == GROUP_COUNT - 1 else ChunkKind.REST)
	return route

func _shuffled_maps(random: RandomNumberGenerator) -> Array[int]:
	var choices: Array[int] = COMPLETE_MAPS.duplicate()
	for index in range(choices.size() - 1, 0, -1):
		var selected := random.randi_range(0, index)
		var previous := choices[index]
		choices[index] = choices[selected]
		choices[selected] = previous
	var opening: Array[int] = []
	var closing: Array[int] = []
	for kind in choices:
		if kind == ChunkKind.DARTS or kind == ChunkKind.JUMP_MAP:
			opening.append(kind)
		elif kind != ChunkKind.ROPE_MAP:
			closing.append(kind)
	opening.append(ChunkKind.ROPE_MAP)
	opening.append_array(closing)
	return opening

func _append_rhythm_group(route: Array[int], rhythm: int, random: RandomNumberGenerator) -> void:
	match rhythm:
		Rhythm.REGULAR:
			var start := random.randi_range(0, REGULAR_ENCOUNTERS.size() - 1)
			for index in ENCOUNTERS_PER_GROUP:
				route.append(REGULAR_ENCOUNTERS[(start + index) % REGULAR_ENCOUNTERS.size()])
		Rhythm.RANDOM:
			var choices: Array[int] = RANDOM_ENCOUNTERS.duplicate()
			var previous: int = route[-2] if route.size() > 1 and route.back() == ChunkKind.REST else -1
			for _index in ENCOUNTERS_PER_GROUP:
				var candidates := choices.filter(func(kind: int) -> bool: return kind != previous)
				var selected: int = candidates[random.randi_range(0, candidates.size() - 1)]
				choices.erase(selected)
				route.append(selected)
				previous = selected
		Rhythm.SWING:
			route.append_array(SWING_ENCOUNTERS)

func content_descriptor(kind: int) -> Dictionary:
	if not CONTENT_PROFILES.has(kind):
		return {"chunk_kind": kind, "theme": ChunkKind.keys()[kind], "variant": "Authored", "difficulty": 1}
	var profile: Dictionary = CONTENT_PROFILES[kind]
	return {"chunk_kind": kind, "theme": profile.theme, "variant": profile.variant, "difficulty": profile.difficulty}
