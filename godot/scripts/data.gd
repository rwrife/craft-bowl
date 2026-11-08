extends RefCounted

const FORMAT_PATH = "res://Packages/CraftBowlKit/Sources/CBPlays/Resources/format.json"
const OFFENSE_PATH = "res://Packages/CraftBowlKit/Sources/CBPlays/Resources/offense.json"
const DEFENSE_PATH = "res://Packages/CraftBowlKit/Sources/CBPlays/Resources/defense.json"
const RATINGS_PATH = "res://Packages/CraftBowlKit/Sources/CBSim/Resources/ratings.json"

const POSITIONS = [
	"qb", "rb", "laneLeft", "laneCenter", "laneRight", "lt", "lg", "rg", "rt",
	"deL", "nt", "deR", "mlb", "olb", "cbL", "cbR", "fs", "ss",
]
const FIRST_NAMES = [
	"Andre", "Beck", "Caleb", "Dante", "Eli", "Finn", "Gabe", "Isaiah", "Jett", "Kai",
	"Leo", "Malik", "Nico", "Owen", "Quinn", "Rafael", "Sam", "Trey", "Victor", "Wes", "Zane",
]
const LAST_NAMES = [
	"Banks", "Cole", "Cross", "Davis", "Ellis", "Frost", "Grant", "Hayes", "Irons", "Jones",
	"Knox", "Lane", "Miles", "North", "Price", "Reed", "Stone", "Turner", "Vale", "West", "Young",
]
const TEAM_DEFINITIONS = [
	["austin", "Austin", "Armadillos", "AUS", "2457d6", "f5b82e", 11, 0],
	["brooklyn", "Brooklyn", "Bolts", "BRK", "121820", "22c8f2", 23, 18],
	["miami", "Miami", "Waves", "MIA", "00a6a6", "ff6b35", 37, 36],
	["chicago", "Chicago", "Foundry", "CHI", "a51c30", "d7dce2", 41, 54],
	["seattle", "Seattle", "Sasquatch", "SEA", "173f35", "9edb4d", 59, 72],
	["phoenix", "Phoenix", "Firebirds", "PHX", "7a1d5d", "ff9e1b", 71, 90],
	["nashville", "Nashville", "Notes", "NSH", "3a1c71", "f4d35e", 83, 108],
	["boston", "Boston", "Minutemen", "BOS", "16324f", "c73737", 97, 126],
	["san-diego", "San Diego", "Surf", "SD", "176b87", "f2e8cf", 109, 144],
]


static func _read_json(path: String):
	if not FileAccess.file_exists(path):
		push_error("Required game data is missing: " + path)
		return null
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open game data %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return null
	var parser = JSON.new()
	var error = parser.parse(file.get_as_text())
	if error != OK:
		push_error("Invalid game data %s, line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return null
	return parser.data


static func load_game_data() -> Dictionary:
	var format = _read_json(FORMAT_PATH)
	var offense = _read_json(OFFENSE_PATH)
	var defense = _read_json(DEFENSE_PATH)
	var curves = _read_json(RATINGS_PATH)
	if not (format is Dictionary and offense is Array and defense is Array and curves is Dictionary):
		push_error("Block Bowl could not load its format, playbooks, or rating curves.")
		return {}
	if format.get("playersPerSide", 0) != 9 or offense.size() < 3 or defense.is_empty():
		push_error("Block Bowl's bundled format or playbooks are incomplete.")
		return {}
	return {"format": format, "offense": offense, "defense": defense, "curves": curves}


static func _base_ratings(position: String) -> Array:
	match position:
		"qb": return [58, 70, 72, 84]
		"rb": return [74, 86, 76, 68]
		"laneLeft", "laneRight": return [54, 88, 70, 76]
		"laneCenter": return [62, 82, 80, 84]
		"lt", "lg", "rg", "rt": return [88, 48, 82, 45]
		"deL", "nt", "deR": return [86, 58, 78, 52]
		"mlb", "olb": return [76, 76, 78, 65]
		"cbL", "cbR": return [54, 89, 74, 72]
		"fs", "ss": return [65, 84, 76, 74]
	push_error("Unknown roster position: " + position)
	return [60, 60, 60, 60]


static func _next_catalog_number(state: Array) -> int:
	# The original catalog uses a wrapping 64-bit LCG and the upper 32 bits.
	state[0] = state[0] * 6364136223846793005 + 1442695040888963407
	return int((state[0] >> 32) & 0xffffffff) % 13


static func make_teams() -> Array:
	var teams = []
	for definition in TEAM_DEFINITIONS:
		var roster = {}
		var state = [int(definition[6])]
		var total = 0
		for i in POSITIONS.size():
			var position: String = POSITIONS[i]
			var combination = ((int(definition[7]) + i) * 179 + 73) % (FIRST_NAMES.size() * LAST_NAMES.size())
			var first: String = FIRST_NAMES[int(combination / LAST_NAMES.size())]
			var last: String = LAST_NAMES[combination % LAST_NAMES.size()]
			if definition[0] == "austin":
				match position:
					"qb": first = "Ryan"
					"rb": first = "Hunter"
					"laneCenter": first = "Jaison"
			var base = _base_ratings(position)
			var values = []
			for value in base:
				values.append(clampi(int(value) + _next_catalog_number(state) - 6, 1, 99))
			var ratings = {
				"power": values[0], "speed": values[1], "endurance": values[2], "ability": values[3],
			}
			total += 3 * values[0] + 3 * values[1] + 2 * values[2] + 2 * values[3]
			roster[position] = {
				"position": position,
				"name": first + " " + last,
				"number": 1 + ((i * 11 + int(definition[6])) % 98),
				"ratings": ratings,
			}
		teams.append({
			"id": definition[0],
			"city": definition[1],
			"nickname": definition[2],
			"name": definition[1] + " " + definition[2],
			"abbr": definition[3],
			"primary": Color(definition[4]),
			"secondary": Color(definition[5]),
			"overall": int(total / (POSITIONS.size() * 10)),
			"roster": roster,
		})
	return teams
