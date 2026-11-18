class_name SaveMigrations
extends RefCounted
## Upgrades saves written by older builds, one version step at a time, so a game update never
## throws a player's progress away. Game._read_json runs every save through migrate() before it
## checks the version.
##
## To change the save format: bump CURRENT, add a `_to_<n>` step below that turns a version n-1
## save into version n (fill new fields with what an old save implies), and add a fixture case to
## tests/expansion_test.gd.

## The save format this build writes.
const CURRENT := 2

## The region every save from before regions existed was in.
const DEFAULT_REGION := "kettle"


## Returns `data` upgraded to CURRENT, or {} when it can't be: not a save, no version, or a save
## from a newer build (refused rather than half-read).
static func migrate(data: Variant) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var save: Dictionary = (data as Dictionary).duplicate(true)
	var version := int(save.get("version", 0))
	if version < 1 or version > CURRENT:
		return {}
	while version < CURRENT:
		version += 1
		save = _step(version, save)
		save["version"] = version
	return save


static func _step(to_version: int, save: Dictionary) -> Dictionary:
	match to_version:
		2:
			return _to_2(save)
	push_error("SaveMigrations: no step to version %d" % to_version)
	return save


## v2 (expansion X1): regions, the quest log, world flags and the campaign act. Every v1 save is
## in the Kettle in Act 1; quest state is rebuilt from the repairs when the game loads.
static func _to_2(save: Dictionary) -> Dictionary:
	save["region"] = DEFAULT_REGION
	save["quests"] = {}
	save["flags"] = {}
	save["act"] = 1
	return save
