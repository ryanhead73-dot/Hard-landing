class_name SideJobDB
extends RefCounted
## The optional jobs people hand Juno, as data. SideJobs runs them; QuestDB lists each one in the
## journal as a "side" quest (taken, then one step per stage), and pays its scrap on completion.
##
## A job (its quest id is "job_<id>", for a requirement on it):
##   id, title, act, summary   as for a quest.
##   requires   QuestDB conditions that must hold before the job is offered.
##   giver      who offers it and takes the report: {"region", "pos"} for a lit survey post at a
##              region-local point, or {"region", "npc"} for one of the greenhouse survivors.
##              "label" is the prompt, "offer" HOB's or the giver's lines on taking it.
##   region     where the stages happen unless a stage names its own.
##   scrap      paid once, when the last stage is done.
##   stages     worked in order; each has a "text" (the journal line and the HUD message, with
##              %d/%d filled in for a use stage's count) and optional "say" lines when it's done.
##              Positions are local to the stage's region (the Kettle's are world positions).
## Stage types:
##   reach    get within `radius` (default 4) of `pos`.
##   use      work every point in `points` (E, or hold E for `hold` seconds); `label` is the prompt.
##   clear    `spawns` ([kind, pos]) come out when Juno is within `trigger` (default 30) of `pos`
##            (0: as soon as the stage starts); kill them all.
##   hold     start at `pos` (`label`), then stay within `radius` for `seconds` while `waves`
##            (lists of kinds) come every `every` seconds from `from` (local points). Stray too
##            long or go down and it starts over.
##   report   back to the giver.
## Any stage can name `guards` ([kind, pos]) spawned when it starts in its region.

const POST := "post"

const JOBS: Array[Dictionary] = [
	{
		"id": "weather_eye", "title": "Weather eye", "act": 1,
		"summary": "The Kettle's old survey weather masts still hold their data cores. HOB wants them.",
		"requires": [{"type": "repair", "id": "aux_power"}],
		"giver": {"region": "kettle", "pos": Vector3(-14.0, 0.0, 28.0), "label": "Read the survey post",
			"offer": [["HOB", "A survey post, still logging. If its weather masts kept their cores, I can learn the Kettle's weather. Pulses included."],
				["Juno", "Three masts on the map. I'll pull them."]]},
		"region": "kettle", "scrap": 45,
		"stages": [
			{"type": "use", "text": "Pull the data cores from the survey weather masts (%d/%d)", "label": "Pull the mast's data core", "hold": 2.0,
				"points": [Vector3(-38.0, 0.0, -18.0), Vector3(32.0, 0.0, 52.0), Vector3(56.0, 0.0, -12.0)]},
			{"type": "report", "text": "Bring the cores back to the survey post by Kestrel",
				"say": [["HOB", "Sixty years of weather. Oh, I am going to enjoy this. Thank you, Juno."]]},
		],
	},
	{
		"id": "the_roost", "title": "The roost", "act": 1,
		"summary": "Spitters have roosted in the freighter hollows. Their glands would feed the fabricator.",
		"requires": [{"type": "repair", "id": "cooling"}],
		"giver": {"region": "kettle", "pos": Vector3(-24.0, 0.0, -52.0), "label": "Check the emergency beacon",
			"offer": [["HOB", "That beacon's been marking a roost. Spitters, three at least. Their acid glands would run the fabricator's etch bath for a month."],
				["Juno", "So I go and start a fight. Fine."]]},
		"region": "kettle", "scrap": 60,
		"stages": [
			{"type": "clear", "text": "Clear the spitter roost in the freighter hollows", "pos": Vector3(-50.0, 0.0, -66.0),
				"spawns": [["spitter", Vector3(-52.0, 0.5, -70.0)], ["spitter", Vector3(-46.0, 0.5, -64.0)], ["scuttler", Vector3(-49.0, 0.5, -60.0)], ["scuttler", Vector3(-55.0, 0.5, -63.0)]],
				"say": [["HOB", "Roost's quiet. Their glands are in the nest, there."]]},
			{"type": "use", "text": "Take the acid glands from the roost (%d/%d)", "label": "Take the acid gland",
				"points": [Vector3(-51.0, 0.0, -68.0), Vector3(-47.0, 0.0, -66.5)]},
			{"type": "report", "text": "Log the roost cleared at the emergency beacon",
				"say": [["HOB", "Glands are in the pouch, roost is off the map. The fabricator thanks you."]]},
		],
	},
	{
		"id": "east_glass", "title": "Glass for the east house", "act": 2,
		"summary": "Teo needs glass to reglaze the east greenhouse. The Marigold carried spare panes.",
		"requires": [{"type": "flag", "id": "lamp_cell_fitted"}],
		"giver": {"region": "shatterlands", "npc": "Teo", "label": "Ask Teo what he needs",
			"offer": [["Teo", "The east house lost half its panes in the last pulse. The Marigold carried spares, crated, round her hull."],
				["Juno", "How many?"], ["Teo", "Four crates would do it. Mind the growth, things nest in it."]]},
		"region": "shatterlands", "scrap": 50,
		"stages": [
			{"type": "use", "text": "Find the crated glass panes around the Marigold (%d/%d)", "label": "Take the crated panes", "hold": 1.0,
				"points": [Vector3(30.0, 0.0, -22.0), Vector3(2.0, 0.0, -22.0), Vector3(34.0, 0.0, -4.0), Vector3(4.0, 0.0, 2.0)],
				"guards": [["skimmer", Vector3(18.0, 1.0, -26.0)], ["scuttler", Vector3(32.0, 0.5, -12.0)]]},
			{"type": "report", "text": "Take the glass back to Teo at the greenhouses",
				"say": [["Teo", "Not one cracked. The squash will be thrilled, and so am I."]]},
		],
	},
	{
		"id": "cap_watch", "title": "Cap watch", "act": 2,
		"summary": "Haddad's pulse warning comes from a sensor on a cap. It needs calibrating, under guard.",
		"requires": [{"type": "flag", "id": "greenhouse_open"}],
		"giver": {"region": "shatterlands", "npc": "Haddad", "label": "Ask Haddad about the caps",
			"offer": [["Haddad", "My sensor on the big cap west of the wreck has drifted. Calibrating takes the best part of a minute, and the noise draws scuttlers."],
				["Juno", "So you need someone standing on it with a rifle."], ["Haddad", "I need someone standing on it with a rifle."]]},
		"region": "shatterlands", "scrap": 70,
		"stages": [
			{"type": "hold", "text": "Guard Haddad's cap sensor while it calibrates", "label": "Start the sensor's calibration",
				"pos": Vector3(-14.0, 0.0, -14.0), "radius": 9.0, "seconds": 45.0, "every": 11.0,
				"waves": [["scuttler", "scuttler"], ["scuttler", "skimmer"], ["scuttler", "scuttler", "scuttler"], ["spitter", "scuttler"]],
				"from": [Vector3(-34.0, 0.5, -20.0), Vector3(4.0, 0.5, -30.0), Vector3(-20.0, 0.5, 8.0)],
				"say": [["HOB", "Calibration's holding. Haddad's caps can see the next pulse coming."]]},
			{"type": "report", "text": "Tell Haddad the sensor's calibrated",
				"say": [["Haddad", "Reading clean. Ninety seconds' warning instead of thirty. That's people inside who'd have been out."]]},
		],
	},
	{
		"id": "brandt_flare", "title": "Brandt's flare", "act": 2,
		"summary": "Brandt set a flare stack on the Gillwood outcrop to guide Ferro-9's rescuers. It's gone dark.",
		"requires": [{"type": "flag", "id": "reached_gillwood"}],
		"giver": {"region": "shatterlands", "npc": "Brandt", "label": "Ask Brandt about Ferro-9's crew",
			"offer": [["Brandt", "I built a flare stack on the outcrop south-west of Ferro-9, in case anyone came looking for us. It's gone out."],
				["Brandt", "Relight it? If the next ship over the Kettle sees it, they'll know someone's alive down here."]]},
		"region": "gillwood", "scrap": 80,
		"stages": [
			{"type": "reach", "text": "Find Brandt's flare stack on the Gillwood outcrop", "pos": Vector3(-16.0, 0.0, -38.0), "radius": 6.0},
			{"type": "use", "text": "Relight the flare stack", "label": "Relight the flare stack", "hold": 3.0, "points": [Vector3(-16.0, 0.0, -38.0)],
				"say": [["HOB", "It's lit. And it's drawn the veilwings. Here they come."]]},
			{"type": "clear", "text": "Drive off the veilwings the flare drew in", "pos": Vector3(-16.0, 0.0, -38.0), "trigger": 0.0,
				"spawns": [["veilwing", Vector3(-26.0, 6.0, -30.0)], ["veilwing", Vector3(-6.0, 6.0, -46.0)]]},
			{"type": "report", "text": "Tell Brandt the flare is burning",
				"say": [["Brandt", "Burning. Good. Someone up there might look down for once."]]},
		],
	},
	{
		"id": "stay_line", "title": "Line for the hoist", "act": 2,
		"summary": "Reyes's hoist runs on scavenged cable. Ferro-9 dropped three spools in the Gillwood.",
		"requires": [{"type": "flag", "id": "ferro_canopy"}],
		"giver": {"region": "shatterlands", "npc": "Okafor", "label": "Ask Okafor what the camp is short of",
			"offer": [["Okafor", "Cable. Reyes's hoist line is down to splices. Ferro-9 jettisoned three spools of stay-line when she came down."],
				["Okafor", "The veilwings roost on anything that hangs. You'll find the spools under the roosts."]]},
		"region": "gillwood", "scrap": 55,
		"stages": [
			{"type": "use", "text": "Recover Ferro-9's stay-line spools from under the roosts (%d/%d)", "label": "Shoulder the cable spool", "hold": 1.5,
				"points": [Vector3(-11.0, 0.0, 24.0), Vector3(22.0, 0.0, -7.0), Vector3(-26.0, 0.0, -5.0)],
				"guards": [["veilwing", Vector3(-9.0, 7.0, 22.0)], ["veilwing", Vector3(-24.0, 7.0, -8.0)]]},
			{"type": "report", "text": "Bring the stay-line back to Okafor",
				"say": [["Okafor", "That's a month of hoisting. Reyes will pretend she isn't pleased. She is."]]},
		],
	},
	{
		"id": "survey_stakes", "title": "Survey stakes", "act": 3,
		"summary": "The survey team left a stake line across the Loom unread. Its readings say where the ground moves.",
		"requires": [{"type": "flag", "id": "weave_grips"}],
		"giver": {"region": "loom_expanse", "pos": Vector3(-36.0, 0.0, -58.0), "label": "Read the survey team's logbook",
			"offer": [["HOB", "Their logbook: a line of strain stakes across the Expanse, never read. Each one will tell us how far the ridges moved."],
				["Juno", "And whether they're about to move again. Reading them."]]},
		"region": "loom_expanse", "scrap": 70,
		"stages": [
			{"type": "use", "text": "Read the survey team's strain stakes (%d/%d)", "label": "Read the strain stake", "hold": 2.5,
				"points": [Vector3(-26.0, 0.0, 22.0), Vector3(20.0, 0.0, -24.0), Vector3(-22.0, 0.0, -36.0)],
				"guards": [["ridge_diver", Vector3(-20.0, 0.0, 16.0)]]},
			{"type": "report", "text": "Log the stake readings at the survey camp",
				"say": [["HOB", "The ridges creep two metres a pulse, toward the Crown. Everything here leans in."]]},
		],
	},
	{
		"id": "spindle_chord", "title": "A chord too many", "act": 3,
		"summary": "A chord singer has taken the Spindles. While it sings, the pinweavers there never sleep.",
		"requires": [{"type": "quest", "id": "job_survey_stakes"}],
		"giver": {"region": "loom_expanse", "pos": Vector3(-36.0, 0.0, -58.0), "label": "Read the survey team's last entry",
			"offer": [["HOB", "Last entry: a singer settled in the Spindles and the team stopped going east. Their cache is still out there."],
				["Juno", "Then I'll go and stop it singing."]]},
		"region": "loom_expanse", "scrap": 90,
		"stages": [
			{"type": "clear", "text": "Silence the chord singer in the Spindles", "pos": Vector3(28.0, 0.0, -12.0),
				"spawns": [["chord_singer", Vector3(30.0, 0.5, -14.0)], ["pinweaver", Vector3(24.0, 0.5, -8.0)], ["pinweaver", Vector3(32.0, 0.5, -6.0)]],
				"say": [["HOB", "Quiet. The survey cache should be close."]]},
			{"type": "use", "text": "Open the survey team's cache in the Spindles", "label": "Open the survey cache", "hold": 1.0, "points": [Vector3(26.0, 0.0, -18.0)]},
			{"type": "report", "text": "Log the Spindles clear at the survey camp",
				"say": [["HOB", "Spindles clear, cache recovered. The survey team would have liked you."]]},
		],
	},
	{
		"id": "old_warden", "title": "The old warden", "act": 1,
		"summary": "A warden has dug in by the moss dropship. The survey team tagged it years ago, and the tag still transmits.",
		"requires": [{"type": "repair", "id": "wing"}],
		"giver": {"region": "kettle", "pos": Vector3(36.0, 0.0, 34.0), "label": "Read the survey tracking post",
			"offer": [["HOB", "A tracking post. The survey team tagged a warden here, sixty years ago. The tag's still pinging, by the moss dropship."],
				["Juno", "Sixty years old and still out there. Must be big."], ["HOB", "Must be very big. Its tag holds the whole team's tracking data."]]},
		"region": "kettle", "scrap": 100,
		"stages": [
			{"type": "reach", "text": "Find the warden's den by the moss dropship", "pos": Vector3(60.0, 0.0, 40.0), "radius": 14.0,
				"say": [["HOB", "There. It's waking. Mind the young it calls."]]},
			{"type": "clear", "text": "Bring down the old warden", "pos": Vector3(60.0, 0.0, 40.0), "trigger": 0.0,
				"spawns": [["warden", Vector3(64.0, 0.5, 38.0)], ["scuttler", Vector3(56.0, 0.5, 44.0)]]},
			{"type": "use", "text": "Cut the survey tag from the warden's den", "label": "Cut the survey tag free", "hold": 2.0, "points": [Vector3(62.0, 0.0, 37.0)]},
			{"type": "report", "text": "Plug the tag into the tracking post",
				"say": [["HOB", "Sixty years of where everything went. The roamers have paths, Juno. I can see them now."]]},
		],
	},
	{
		"id": "voss_recorder", "title": "Voss's recorder", "act": 2,
		"summary": "Reyes wants Voss's flight recorders from the Marigold: the last word from the woman who built the greenhouses.",
		"requires": [{"type": "flag", "id": "reyes_talked"}],
		"giver": {"region": "shatterlands", "npc": "Reyes", "label": "Ask Reyes about Voss",
			"offer": [["Reyes", "Voss kept three recorders on the Marigold: cockpit, hold and tail. Nobody's dared the wreck since the growth took it."],
				["Reyes", "I'd like to hear her again. Bring them, Vale."]]},
		"region": "shatterlands", "scrap": 75,
		"stages": [
			{"type": "use", "text": "Pull the Marigold's three flight recorders (%d/%d)", "label": "Pull the flight recorder", "hold": 2.0,
				"points": [Vector3(8.0, 0.0, -16.0), Vector3(26.0, 0.0, -14.0), Vector3(16.0, 0.0, -28.0)]},
			{"type": "clear", "text": "Something heard you pull them: fight your way clear", "pos": Vector3(16.0, 0.0, -18.0), "trigger": 0.0,
				"spawns": [["skimmer", Vector3(4.0, 1.5, -26.0)], ["skimmer", Vector3(30.0, 1.5, -24.0)], ["scuttler", Vector3(20.0, 0.5, -4.0)]]},
			{"type": "report", "text": "Bring Voss's recorders to Reyes",
				"say": [["Reyes", "That's her. Bossy to the last. Thank you, Vale. Truly."]]},
		],
	},
	{
		"id": "spore_count", "title": "Spore count", "act": 2,
		"summary": "Okafor thinks the Gillwood's spores are what keep the veilwings sleepy. She needs samples from the gill caps.",
		"requires": [{"type": "quest", "id": "job_stay_line"}],
		"giver": {"region": "shatterlands", "npc": "Okafor", "label": "Ask Okafor about the Gillwood",
			"offer": [["Okafor", "The veilwings sleep through the day under the caps, and wake angry where the caps die off. I think it's the spores."],
				["Okafor", "Four samples from four caps, and I can make something that keeps them dozy."]]},
		"region": "gillwood", "scrap": 65,
		"stages": [
			{"type": "use", "text": "Scrape spore samples from the Gillwood's gill caps (%d/%d)", "label": "Scrape a spore sample", "hold": 1.5,
				"points": [Vector3(-20.0, 0.0, 30.0), Vector3(26.0, 0.0, -48.0), Vector3(12.0, 0.0, 14.0), Vector3(-30.0, 0.0, -24.0)],
				"guards": [["skimmer", Vector3(20.0, 1.5, -44.0)], ["scuttler", Vector3(-26.0, 0.5, 26.0)]]},
			{"type": "report", "text": "Bring the spore samples to Okafor",
				"say": [["Okafor", "Lovely. Disgusting, and lovely. Give me a day."]]},
		],
	},
	{
		"id": "ridge_watch", "title": "Ridge watch", "act": 3,
		"summary": "The survey team's seismograph at the overlook was never switched on. It needs a minute of quiet ground, and the divers hate it.",
		"requires": [{"type": "all", "of": [{"type": "quest", "id": "job_survey_stakes"}, {"type": "repair", "id": "engine"}]}],
		"giver": {"region": "loom_expanse", "pos": Vector3(-36.0, 0.0, -58.0), "label": "Check the survey camp's seismograph crate",
			"offer": [["HOB", "Their seismograph's packed and labelled for the overlook. It'll tell us when the next big pulse is building."],
				["HOB", "It listens through the ground for a minute. So does everything else that lives in it."]]},
		"region": "loom_expanse", "scrap": 110,
		"stages": [
			{"type": "hold", "text": "Guard the seismograph at the overlook while it listens", "label": "Switch the seismograph on",
				"pos": Vector3(-6.0, 0.0, -68.0), "radius": 10.0, "seconds": 60.0, "every": 12.0,
				"waves": [["ridge_diver"], ["pinweaver", "ridge_diver"], ["ridge_diver", "ridge_diver"], ["pinweaver", "pinweaver"], ["ridge_diver", "pinweaver"]],
				"from": [Vector3(-20.0, 0.0, -50.0), Vector3(12.0, 0.0, -52.0), Vector3(-22.0, 0.0, -66.0)],
				"say": [["HOB", "Got it. Clean minute, clean reading. The big ones build for an hour first. We'll know."]]},
			{"type": "report", "text": "Log the seismograph's reading at the survey camp",
				"say": [["HOB", "Logged. If a big one's coming while we spool, I'll have warning."]]},
		],
	},
	{
		"id": "cold_box", "title": "Cold box", "act": 1,
		"summary": "A medical drop pod burst in the gully west of Kestrel. Its cryo vials are warming.",
		"requires": [{"type": "repair", "id": "landing_gear"}],
		"giver": {"region": "kettle", "pos": Vector3(-28.0, 0.0, 30.0), "label": "Read the drop pod's beacon",
			"offer": [["HOB", "A medical drop pod, ours or someone's. Its cold box split on landing. There are still vials in the grass, and they're warming."],
				["HOB", "Once you've one in the pouch, the cold pack in it keeps for a minute. Get the rest before it's spent."]]},
		"region": "kettle", "scrap": 55,
		"stages": [
			{"type": "use", "text": "Gather the cryo vials before the cold pack is spent (%d/%d)", "label": "Pick up the cryo vial", "timer": 60.0,
				"slip": "The cold pack's spent and the vials have warmed. HOB marks a fresh scatter: start again",
				"points": [Vector3(-34.0, 0.0, 36.0), Vector3(-40.0, 0.0, 26.0), Vector3(-24.0, 0.0, 40.0), Vector3(-44.0, 0.0, 34.0)],
				"guards": [["scuttler", Vector3(-38.0, 0.5, 36.0)], ["scuttler", Vector3(-28.0, 0.5, 26.0)]]},
			{"type": "report", "text": "Log the vials at the drop pod's beacon",
				"say": [["HOB", "Cold and sealed. Antitoxin, mostly. That's a few spitter burns that won't kill you."]]},
		],
	},
	{
		"id": "ghost_signal", "title": "The ghost signal", "act": 3,
		"summary": "Since the engine went in, HOB has heard a signal from the Loom spire. It repeats a call sign nobody has used in sixty years.",
		"requires": [{"type": "repair", "id": "engine"}],
		"giver": {"region": "kettle", "pos": Vector3(-14.0, 0.0, 28.0), "label": "Ask the survey post about the signal",
			"offer": [["HOB", "Juno, the drive's coil is picking something up. A call sign, repeating, from the spire west of the relay. Survey Seven."],
				["Juno", "Survey Seven went down sixty years ago."], ["HOB", "Then something down there is very patient."]]},
		"region": "kettle", "scrap": 120,
		"stages": [
			{"type": "reach", "text": "Follow the signal past the relay toward the spire", "pos": Vector3(-74.0, 0.0, 36.0), "radius": 8.0,
				"say": [["HOB", "Stronger. It's under the spire itself."]]},
			{"type": "use", "text": "Find Survey Seven's transmitter at the foot of the spire", "label": "Open the transmitter's housing", "hold": 2.5,
				"points": [Vector3(-88.0, 0.0, 12.0)], "say": [["HOB", "It's a relay beacon, and it's been answering the Loom all this time. If we key it, it'll call everything for a mile. Hold it."]]},
			{"type": "hold", "text": "Hold the transmitter while HOB copies its log", "label": "Key the transmitter",
				"pos": Vector3(-88.0, 0.0, 12.0), "radius": 10.0, "seconds": 50.0, "every": 10.0,
				"waves": [["scuttler", "scuttler"], ["spitter", "scuttler"], ["ram"], ["scuttler", "spitter", "scuttler"], ["ram", "scuttler"]],
				"from": [Vector3(-104.0, 0.5, 0.0), Vector3(-76.0, 0.5, -4.0), Vector3(-98.0, 0.5, 30.0)],
				"say": [["HOB", "Copied. Sixty years of Loom pulses, timed to the second. That's how we'll find the gap."]]},
			{"type": "report", "text": "Bring the log back to the survey post",
				"say": [["HOB", "Survey Seven's log is aboard. They nearly made it out. We will."]]},
		],
	},
	{
		"id": "glowcaps", "title": "Glowcaps", "act": 2,
		"summary": "Teo wants glowcap spores for the east house's seed beds. Cut, they last under a minute.",
		"requires": [{"type": "quest", "id": "job_east_glass"}],
		"giver": {"region": "shatterlands", "npc": "Teo", "label": "Ask Teo about the seed beds",
			"offer": [["Teo", "The new glass is lovely. Now the beds want glowcap spores, from the caps' lips, fresh."],
				["Teo", "Fresh means fast. Cut one and the rest have to be in your pouch inside the minute, or the lot goes grey."]]},
		"region": "shatterlands", "scrap": 55,
		"stages": [
			{"type": "use", "text": "Cut glowcap spores from three caps inside a minute (%d/%d)", "label": "Cut the glowcap's lip", "timer": 55.0,
				"slip": "The spores have gone grey. Cut three fresh ones",
				"points": [Vector3(31.0, 0.0, 14.0), Vector3(-6.0, 0.0, -15.0), Vector3(-10.0, 0.0, 8.0)]},
			{"type": "report", "text": "Bring the spores to Teo",
				"say": [["Teo", "Still glowing. Perfect. You'd make a gardener, Vale, if you ever sat still."]]},
		],
	},
	{
		"id": "night_gate", "title": "Night at the gate", "act": 3,
		"summary": "Reyes's gate takes a beating every few nights. She'd like a rifle on it, just once, while her people sleep.",
		"requires": [{"type": "quest", "id": "job_voss_recorder"}],
		"giver": {"region": "shatterlands", "npc": "Reyes", "label": "Ask Reyes how the camp's holding",
			"offer": [["Reyes", "They come at the gate when the caps dim. Every few nights. We patch it in the morning."],
				["Reyes", "Hold it for me, Vale. One night where nobody has to stand there but you."]]},
		"region": "shatterlands", "scrap": 110,
		"stages": [
			{"type": "hold", "text": "Hold the greenhouse gate while the camp sleeps", "label": "Take the gate watch",
				"pos": Vector3(15.0, 0.0, -38.0), "radius": 10.0, "seconds": 60.0, "every": 10.0,
				"waves": [["scuttler", "scuttler", "scuttler"], ["skimmer", "scuttler"], ["spitter", "spitter"], ["scuttler", "scuttler", "skimmer"], ["ram", "scuttler"], ["spitter", "scuttler", "scuttler"]],
				"from": [Vector3(-4.0, 0.5, -24.0), Vector3(34.0, 0.5, -26.0), Vector3(14.0, 0.5, -18.0)],
				"say": [["HOB", "Dawn's coming up the canyon. Gate's still standing."]]},
			{"type": "report", "text": "Tell Reyes the gate held",
				"say": [["Reyes", "Not a scratch on it. I slept, Vale. First time in a month."]]},
		],
	},
	{
		"id": "black_box", "title": "Ferro-9's black box", "act": 2,
		"summary": "Brandt wants to know what brought Ferro-9 down. Her black box is under the aft section.",
		"requires": [{"type": "quest", "id": "job_brandt_flare"}],
		"giver": {"region": "shatterlands", "npc": "Brandt", "label": "Ask Brandt about the crash",
			"offer": [["Brandt", "I've told it a hundred ways and I still don't know. The engine just stopped, on the pulse."],
				["Brandt", "Her black box is in the aft section. It'll have the last minute. Will you get it?"]]},
		"region": "gillwood", "scrap": 75,
		"stages": [
			{"type": "use", "text": "Cut Ferro-9's black box free of her aft section", "label": "Cut the black box free", "hold": 3.0,
				"points": [Vector3(18.0, 0.0, -12.0)], "say": [["HOB", "Got it. And the cutting's woken something. Skimmers, two."]]},
			{"type": "clear", "text": "Fight off the skimmers", "pos": Vector3(18.0, 0.0, -12.0), "trigger": 0.0,
				"spawns": [["skimmer", Vector3(28.0, 2.0, -4.0)], ["skimmer", Vector3(8.0, 2.0, -2.0)], ["veilwing", Vector3(22.0, 6.0, -24.0)]]},
			{"type": "report", "text": "Bring the black box to Brandt",
				"say": [["Brandt", "The engine didn't fail. The pulse pulled her drive's field inside out. It wasn't me."], ["Brandt", "Thank you. I needed to hear that."]]},
		],
	},
	{
		"id": "silk_anchors", "title": "Silk for the hoist", "act": 3,
		"summary": "Pinweaver silk is stronger than any cable the survey team had. It has to be cut from its anchors before it sets.",
		"requires": [{"type": "quest", "id": "job_spindle_chord"}],
		"giver": {"region": "loom_expanse", "pos": Vector3(-36.0, 0.0, -58.0), "label": "Read the survey team's note on pinweaver silk",
			"offer": [["HOB", "A note: pinweaver silk, fresh off its anchor, takes the weight of a hauler. It sets hard inside a minute once one strand's cut."],
				["Juno", "Reyes's hoist could use it. Four anchors, one minute."]]},
		"region": "loom_expanse", "scrap": 85,
		"stages": [
			{"type": "use", "text": "Cut pinweaver silk from four anchors in the Spindles before it sets (%d/%d)", "label": "Cut the silk anchor", "timer": 50.0,
				"slip": "The silk's set hard. Cut four fresh anchors",
				"points": [Vector3(23.0, 0.0, 26.0), Vector3(33.0, 0.0, 4.0), Vector3(23.0, 0.0, -10.0), Vector3(31.0, 0.0, -21.0)],
				"guards": [["pinweaver", Vector3(30.0, 0.5, 10.0)], ["pinweaver", Vector3(26.0, 0.5, -16.0)]]},
			{"type": "report", "text": "Log the silk at the survey camp for Reyes's runners",
				"say": [["HOB", "Logged and bundled. Reyes's runners will have it up the hoist by morning."]]},
		],
	},
]


static var _by_id := {}


static func get_job(id: String) -> Dictionary:
	if _by_id.is_empty():
		for j in JOBS:
			_by_id[j["id"]] = j
	return _by_id.get(id, {})


static func taken_flag(id: String) -> String:
	return "job_%s_taken" % id


static func stage_flag(id: String, i: int) -> String:
	return "job_%s_s%d" % [id, i]


static func point_flag(id: String, i: int, k: int) -> String:
	return "job_%s_s%d_%d" % [id, i, k]


## The stage's region (its own, or the job's; a report is wherever the giver is).
static func stage_region(job: Dictionary, s: Dictionary) -> String:
	if s["type"] == "report":
		return String(job["giver"]["region"])
	return String(s.get("region", job["region"]))


## The journal's version of every job: taken, then one step per stage.
static func quests() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in JOBS:
		var id: String = j["id"]
		var steps: Array = [{"text": "%s (%s)" % [j["giver"]["label"], RegionDB.get_region(String(j["giver"]["region"]))["name"]],
			"done": {"type": "flag", "id": taken_flag(id)}}]
		for i in (j["stages"] as Array).size():
			var s: Dictionary = j["stages"][i]
			steps.append({"text": String(s["text"]).replace(" (%d/%d)", ""), "done": {"type": "flag", "id": stage_flag(id, i)}})
		out.append({"id": "job_" + id, "title": j["title"], "act": j["act"], "kind": "side", "region": j["region"],
			"summary": j["summary"], "requires": j["requires"], "steps": steps, "rewards": {"scrap": j["scrap"]}})
	return out
