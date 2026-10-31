class_name Story
extends RefCounted
## The story as data: who says what, and when. Voice lines play as subtitles (see voice.gd).
## Logs are found in salvage crates ("crate:N", by the site's crate index) or with the component
## ("component"), and are read from the log reader (L) or the inventory.

const JUNO := "Juno"
const HOB := "HOB"

## New game: Juno, alone, Kestrel dark.
const OPENING: Array = [
	[JUNO, "Kestrel? ...Nothing. Every board's red and the ship mind's dark."],
	[JUNO, "Drive cut out on the way down. Everything cut out. Like something reached up and took hold."],
	[JUNO, "Fine. The relay station I came to strip is on the south-west ridge. If anything out here has a charged cell, it does."],
]

## Said when a repair is installed. aux_power's is HOB coming back.
const INSTALLED: Dictionary = {
	"aux_power": [
		[HOB, "...HOB online. Systems check. Ah. We appear to be lying in a swamp, face down."],
		[JUNO, "Good to hear you, HOB."],
		[HOB, "Juno, I've watched you park. This is still a new low. Fabricator's warm, but it'll cook itself on anything heavy. There's a coolant hauler in the hot springs to the north-east."],
	],
	"cooling": [
		[HOB, "Coolant's flowing. I had forgotten what it's like not to be on fire."],
		[HOB, "Next, the canopy. There's a survey skiff perched on the spires to the west. Don't fall off anything. I can't fetch you."],
	],
	"canopy": [
		[HOB, "Cockpit sealed and the scanner's back. I can see crates and wildlife now, and they can see us. The heat of a working ship draws them."],
		[HOB, "The mining crawler in the quarry, due south. Strut packs. I would like to stop leaning."],
	],
	"landing_gear": [
		[HOB, "Gear down and locked. Level at last. The aft ramp's free, and the armoury locker with it."],
		[HOB, "The port wing next. A rescue dropship went into the moss field to the east. Mind the spores. I'd rather you didn't come back furry."],
	],
	"wing": [
		[HOB, "Wing's whole and the point-defence turret answers. I've named it Gerald. Gerald shoots things."],
		[HOB, "The port engine needs a drive coil. There's a freighter graveyard to the north. One of them, the Long Patience, has been down sixty years."],
	],
	"engine": [
		[HOB, "Port engine turns over. Listen to her. Bleed power's on the fabricator's top tier."],
		[HOB, "Last piece. Ilse Marrow left a nav core at the Loom spire, far to the west. Juno, everything that pulled us down comes from there. Go carefully."],
	],
	"navigation": [
		[HOB, "Nav core seated. Oh. Oh, that's clever. It isn't a map, it's a metronome."],
		[HOB, "The Loom pulses on a beat, and between beats there's a gap. Ninety seconds of engine spool and we can thread it. When you're ready, the pilot's seat."],
	],
}

## Said when a ship siege starts, by siege index; the finale has its own lines.
const SIEGE: Array = [
	[[HOB, "Contacts on the rim. A lot of them. They want the heat, and the heat is me."]],
	[[HOB, "They're back, with friends. Something big's leading them in."]],
	[[HOB, "Here they come again. Gerald and I would appreciate some help."]],
]
const SIEGE_HELD := [HOB, "They're scattering. Thank you. I'd have been very brave about it, of course."]
const SIEGE_LOST := [HOB, "Hull's breached. They've torn open the stores. They'll come back once they've eaten."]

const FINALE_START: Array = [
	[HOB, "Engine spool started. Ninety seconds. Every animal in the basin is going to feel this."],
	[JUNO, "Then we keep them off you. Let's go."],
]
const FINALE_HALF := [HOB, "Halfway. The Loom's beat is steady. Hold them off."]
const FINALE_LATE := [HOB, "Ten seconds left on the spool. Start heading for the cockpit."]
const FINALE_READY := [HOB, "Spool's full! Get to the pilot's seat. Now, Juno!"]
const FINALE_FAILED := [HOB, "Hull breach, spool's dumped. I'm sorry. We'll have to start it again."]
const LAUNCH: Array = [
	[HOB, "Waiting on the beat... three... two..."],
	[JUNO, "Go."],
]

## [title, text] lines of the ending card, after the launch cinematic.
const ENDING: Array = [
	"Kestrel climbs through the steam as the Loom's pulse spreads beneath her, and misses.",
	"In orbit, Juno drops a warning buoy over the Kettle: the beat, the gap, and the names of everyone in the logs.",
	"Then the relay band crackles. A looping message, sent from somewhere above the planet. The voice is Ilse Marrow's.",
]

## Compass convention for every line: -Z is north, +X is east.

## Every log, in campaign order. site = the repair id whose site holds it.
const LOGS: Array[Dictionary] = [
	# Relay station: Ilse Marrow, relay technician.
	{
		"id": "relay_1", "site": "aux_power", "source": "crate:0",
		"title": "Relay HD-4471, day 1", "author": "Ilse Marrow, relay technician",
		"text": "Posted to the relay on HD-4471 b. The haulers call it the Kettle, and now I know why: the whole basin steams like a pot on the boil. My job is to listen to the outer lanes and pass the traffic on. Two years of that, then home. The station is warm, the coffee is terrible, and the moss glows in the dark. Teal. I like it.",
	},
	{
		"id": "relay_2", "site": "aux_power", "source": "crate:2",
		"title": "Relay HD-4471, day 40", "author": "Ilse Marrow",
		"text": "Third ship down this season. Every one reports the same: drive dies over the basin, no fault, no warning. And every time, the station seismograph jumps a second earlier. Something under the wetlands pulses, and the moss brightens with it. The little six-legged grazers wake up when a wreck comes down. They gather round the warm hulls like cattle round a stove.",
	},
	{
		"id": "relay_3", "site": "aux_power", "source": "component",
		"title": "Relay HD-4471, day 112", "author": "Ilse Marrow",
		"text": "It isn't random. The pulses keep time, like a shuttle across a loom, and that's what I'm calling it: the Loom. There's a lattice under the whole basin, and it all runs back to the spire in the west. If I can build a core that keeps the same beat, a pilot could fly in the gaps. I'm going out there to tune it. I've left this cell charged for whoever comes down next. You're welcome.",
	},
	# Hauler Brightwater: Captain Teodor Gant.
	{
		"id": "hauler_1", "site": "cooling", "source": "crate:0",
		"title": "Brightwater, captain's log", "author": "Captain Teodor Gant",
		"text": "Coolant run for the relay, two hundred tonnes and a crew of four. The drive cut out over the basin like somebody pulled the plug. I put her down in the hot springs, which is the softest place on this rock. Nobody hurt. Marrow at the relay says she's seen this before. She sounds more interested than sorry.",
	},
	{
		"id": "hauler_2", "site": "cooling", "source": "crate:1",
		"title": "Brightwater, night four", "author": "Captain Teodor Gant",
		"text": "They come at night, for the reactor heat. Grazers, Marrow calls them. Scuttlers, my crew calls them, and worse. They don't want us; they want the warm. They lie on the hull plates and hum. When the heat drops they wander off. I've started running the reactor low on purpose. Cold and quiet is how you survive the Kettle.",
	},
	{
		"id": "hauler_3", "site": "cooling", "source": "component",
		"title": "Brightwater, last entry", "author": "Captain Teodor Gant",
		"text": "We're walking to the relay. Brightwater won't fly again, and I won't pretend otherwise. Whoever reads this: the spare manifold is good. Take it, take anything. Better her parts fly than rot in a spring. Tell my sister in Vasa Port that I was right about the coolant contract and she was right about everything else.",
	},
	# Survey skiff Lark: Pell Adair.
	{
		"id": "skiff_1", "site": "canopy", "source": "crate:0",
		"title": "Lark, survey flight", "author": "Pell Adair, survey pilot",
		"text": "Contract from the relay: fly Ilse Marrow's sensor rigs up to the spire tops and seed the basin with them. She tells me the pulse is on a timer and she's going to read it like sheet music. I fly, I don't read. Two drops done. The view from up here is something. Teal veins under all that black rock, like the planet has a nervous system.",
	},
	{
		"id": "skiff_2", "site": "canopy", "source": "crate:1",
		"title": "Lark, perched", "author": "Pell Adair",
		"text": "Pulse caught me on the third drop. Drive dead, and I put the Lark down on top of a spire because the alternative was the ground. She's balanced like a cup on a fence post. The grazers can't climb this high, which is the good news. The bad news is that I can't climb down without the ropes I left at the relay.",
	},
	{
		"id": "skiff_3", "site": "canopy", "source": "component",
		"title": "Lark, the map", "author": "Pell Adair",
		"text": "Ilse's rigs finished the map before the Lark's power gave out. The lattice runs under the whole basin, a web, and it all knots up at the spire in the west. She's right. I've made some ropes from cargo straps and I'm heading for the quarry. The miners have a crawler and a working radio. Leaving the glazing panel, it's the only part of the Lark not cracked.",
	},
	# Mining crawler: foreman Dace Okoro.
	{
		"id": "quarry_1", "site": "landing_gear", "source": "crate:0",
		"title": "Crawler shift report", "author": "Dace Okoro, foreman",
		"text": "Cutting basalt for the company. Found glassy teal strands running through the rock, thin as wire and hard as diamond. Company assayers went quiet when they saw the samples, and then very loud. New orders: dig deeper and bring up as much thread as we can. Hazard pay doubled. That should have told me something.",
	},
	{
		"id": "quarry_2", "site": "landing_gear", "source": "crate:2",
		"title": "Crawler shift report, week three", "author": "Dace Okoro",
		"text": "Every metre down, more wildlife. The scuttlers came first, then the spitters, and now rams: big armoured things that charge the crawler like it's a rival. Pell Adair walked in yesterday off the spires with rope burns and a map of the thread. It's not a vein, he says. It's one thing, and it's alive, or close enough.",
	},
	{
		"id": "quarry_3", "site": "landing_gear", "source": "component",
		"title": "Crawler, evacuation", "author": "Dace Okoro",
		"text": "We cut a strand. The whole basin lit up, every pool at once, and the rams came over the rim in a herd. They broke the crawler's legs. Nobody died, which is a miracle I'll take. Marrow got a rescue call out on the relay, and a dropship, the Ferro-9, is coming for us. Leaving the spare strut pack in the bay. Don't cut the thread.",
	},
	# Dropship Ferro-9: Lieutenant Sana Reyes.
	{
		"id": "moss_1", "site": "wing", "source": "crate:0",
		"title": "Ferro-9, mission brief", "author": "Lt. Sana Reyes, rescue lead",
		"text": "Search and rescue for the relay tech and the quarry crew, nine souls. Approach plan: low and fast, under whatever is downing ships. Command believes it's an orbital fault. Command is not flying this.",
	},
	{
		"id": "moss_2", "site": "wing", "source": "crate:1",
		"title": "Ferro-9, on the ground", "author": "Lt. Sana Reyes",
		"text": "Down in the moss field. Low and fast didn't help: the pulse doesn't care how high you are. Two injured. The moss throws spores when you step near the bright pods, and the spores burn. We've got masks for six and there are nine of us. Marrow made it here on foot and she won't stop talking about gaps.",
	},
	{
		"id": "moss_3", "site": "wing", "source": "component",
		"title": "Ferro-9, change of plan", "author": "Lt. Sana Reyes",
		"text": "Marrow's maths says the gap between pulses is ninety seconds wide for a ship that's already spooled. Nobody here has a working drive. There's a freighter in the graveyard, the Long Patience, sixty years down, with a coil Marrow swears still holds charge. We're taking everyone there. It's shelter, at least. The wing panel's good if anyone needs it. I hope someone does.",
	},
	# Freighter Long Patience: Captain Mirela Voss, sixty years ago; Ilse, recently.
	{
		"id": "freighter_1", "site": "engine", "source": "crate:0",
		"title": "Long Patience, automated log", "author": "Ship's recorder",
		"text": "Unscheduled descent. Drive offline. Cause: unknown. Crew: eleven. Cargo: agricultural machinery, seed stock, irrigation pumps. Distress beacon active. Distress beacon active. Distress beacon active. Distress beacon depleted.",
	},
	{
		"id": "freighter_2", "site": "engine", "source": "crate:1",
		"title": "Long Patience, year three", "author": "Captain Mirela Voss",
		"text": "Three launch attempts. Every time, the moment the drive spools, the ground answers, and we fall again. We have stopped trying. We have seed stock and pumps, and the springs are warm. The grazers leave the greenhouses alone if we keep them cool. It is not the life we planned. It's a life.",
	},
	{
		"id": "freighter_3", "site": "engine", "source": "crate:3",
		"title": "Long Patience, today", "author": "Ilse Marrow",
		"text": "Reyes's people are safe in the old greenhouses. Voss's crew left them in good order, sixty years ago. The drive coil is intact, as I said it would be. All we need is a ship with a working frame, and nobody here has one. So I'm going to the spire to finish the core. If it works and I don't come back, it'll be in the cradle at the top. Whoever has a ship: take it, and come back for these people.",
	},
	{
		"id": "freighter_4", "site": "engine", "source": "component",
		"title": "Long Patience, year forty", "author": "Captain Mirela Voss",
		"text": "I am old now, and most of us are buried by the greenhouses. Every spring we still charge the drive coil from the hot pools, the way you'd wind a clock nobody reads. Someone will come down who can fly. The coil is for them. Tell them the Long Patience waited as long as she could.",
	},
	# The Loom spire: Ilse Marrow.
	{
		"id": "loom_1", "site": "navigation", "source": "crate:0",
		"title": "The spire", "author": "Ilse Marrow",
		"text": "The beat is clean up here. Pulse, gap, pulse, gap. The core is tuned to it now, and it hums when I hold it. The moss on the spire is brighter than anywhere in the basin. I think this is where the Loom breathes.",
	},
	{
		"id": "loom_2", "site": "navigation", "source": "crate:1",
		"title": "The guardian", "author": "Ilse Marrow",
		"text": "Something lives at the foot of the spire. Larger than the rams, plated, and it glows in time with the pulse. It knocked me flat with a ring of light and didn't follow me. It doesn't hunt; it guards. Whatever the Loom is, it has a keeper. I'm calling it the Warden, and I'm keeping out of its way.",
	},
	{
		"id": "loom_3", "site": "navigation", "source": "component",
		"title": "The cradle", "author": "Ilse Marrow",
		"text": "The core goes in a ship's nav bay. Any ship mind will understand it. Wait for the beat and fly in the gap. I'm not coming down from the spire the way I came up. When the pulse goes through the top, there's a moment where the Loom reaches all the way to orbit. I think I can ride it. If you're reading this and I was wrong, tell Reyes I'm sorry. If I was right, look up.",
	},
]

## The message waiting in orbit.
const ORBIT_LOG := {
	"id": "orbit", "site": "", "source": "ending",
	"title": "Relay band, orbital", "author": "Ilse Marrow",
	"text": "...if you're hearing this, you made it through the gap. So did I, after a fashion. It's very quiet up here and the view is extraordinary. Tell them at the graveyard to wait for the beat. I'll keep time. Ilse Marrow, relay HD-4471, signing off.",
}


static func get_log(id: String) -> Dictionary:
	if id == ORBIT_LOG["id"]:
		return ORBIT_LOG
	for l in LOGS:
		if l["id"] == id:
			return l
	return {}


## The log at a site's source ("crate:2", "component"), or "" if none.
static func log_at(site: String, source: String) -> String:
	for l in LOGS:
		if l["site"] == site and l["source"] == source:
			return l["id"]
	return ""


static func logs_at(site: String) -> Array:
	return LOGS.filter(func(l): return l["site"] == site)
