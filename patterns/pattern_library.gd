class_name PatternLibrary
extends RefCounted

const NAMES := ["P01_SingleSpike", "P04_SingleShuriken", "P08_HighLow", "P14_MiddleGap", "P15_TopGap", "P16_BottomGap", "P17_GapSwitch", "P18_Diagonal", "P21_SpikeShuriken", "P22_GapCeiling", "P24_WallLandingTrap", "P28_RhythmBurst"]

static func load_pattern(index: int) -> ObstaclePatternData:
	return load("res://patterns/library/%s.tres" % NAMES[posmod(index, NAMES.size())])
