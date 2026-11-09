class_name Story
extends RefCounted
## The story as data: who says what, and when. Voice lines play as subtitles (see voice.gd).
## Logs are found in salvage crates ("crate:N", by the site's crate index) or with the component
## ("component"), and are read from the log reader (L) or the inventory.

const JUNO := "Juno"
const HOB := "HOB"
const REYES := "Reyes"

## The opening, aboard a Kestrel that still works (the approach) and then the wreck.
const APPROACH_WAKE: Array = [
	[HOB, "Proximity chime, Juno. Low priority. We're coming up on HD-4471 b."],
	[HOB, "You're three minutes early. I'm recording that for posterity."],
]
const APPROACH_NUDGE: Array = [
	[HOB, "The copilot's seat is free, if you'd like to watch me park."],
]
const APPROACH_CUP: Array = [[JUNO, "Got you. Not today, cup."]]
const APPROACH_CONTRACT: Array = [
	[JUNO, "Strip one relay station, Kettle basin, salvage rights paid in full. Nobody's been down there in years."],
	[JUNO, "Easy money. That's what worries me."],
]
const APPROACH_RELAY: Array = [
	[JUNO, "Relay looks intact. That's a good day's work, if it stays that way."],
]
const APPROACH_KEEPSAKE: Array = [
	[JUNO, "Mira carved this fish the week she quit the yards. Said every ship needs something that can't break."],
	[HOB, "It is a fish, Juno. It has broken twice. I glued it."],
]
const APPROACH_SEATED: Array = [
	[JUNO, "Not much of a welcome mat."],
	[HOB, "Kestrel has a name. The mat is optional."],
	[HOB, "There's a wreck beacon on the surface, if you want something to look at while I work."],
]
const APPROACH_TRACE: Array = [
	[JUNO, "That beacon's moving against the wind."],
	[HOB, "It's weather. Probably. I'm logging it as weather."],
]
const APPROACH_DRIFT: Array = [
	[JUNO, "HOB, you're pulling us down."],
	[HOB, "I am not."],
]
const APPROACH_FALL: Array = [
	[HOB, "Juno, something is moving the direction of down."],
]

## The wreck, and the walk to the relay (see Opening).
const WAKE: Array = [
	[JUNO, "...HOB? That's not funny."],
	[JUNO, "Suit's punctured. One problem. Fix one problem."],
]
const GET_UP: Array = [[JUNO, "There's a med-seal in the aux bay kit. Amber light. Go."]]
const SEALED: Array = [[JUNO, "Breathe in. Seal. Breathe out."], [JUNO, "Okay. Okay. Side door."]]
const HOB_DARK: Array = [[JUNO, "HOB? ...Nothing. Not even the boot chime."]]
const HATCH_JAMMED: Array = [[JUNO, "Jammed solid. The hull's twisted round it. Later."]]
const THRESHOLD: Array = [[JUNO, "Fresh air. Sort of. Let's see what we hit."]]
const SCANS := {
	"scan_fracture": [[JUNO, "Keel's cracked through the starboard plating. She's not flying on that."]],
	"scan_pod": [[JUNO, "Our cargo pod, torn off on the way in. Empty. Of course it's empty."]],
	"scan_scar": [[JUNO, "That crater was here before us."], [JUNO, "Whatever brought us down, it has practice."]],
}
const FIND_POWER: Array = [
	[JUNO, "Kestrel needs power before she needs anything else. The relay's across the basin."],
	[JUNO, "Someone left reflector beads on a trail. I'll take it."],
]
const SPOOL: Array = [[JUNO, "Fibre, wound tight. And the rock: those aren't scratches. They're lines. Something dragged a wire through stone."]]
const POD_OPEN: Array = [[JUNO, "A survey pod's field kit. Receiver, a cell, one bent rail. You don't have to be pretty. You have to work."]]
const ASSEMBLE_1: Array = [[JUNO, "If I find the idiot who packed a receiver without a stock..."]]
const ASSEMBLE_2: Array = [[JUNO, "There. A salvage rifle, more or less. Test it on something that won't mind."]]
const TEST_SHOT: Array = [[JUNO, "Pulls a little left. I'll live with it."]]
const CARCASS: Array = [[JUNO, "A salvage drone. Orange coolant all over it, and bite marks."], [JUNO, "Those teeth would go straight through the suit."]]
const WATCHER: Array = [[JUNO, "...You saw me."], [JUNO, "Easy. I'm not here for you."]]
const WATCHER_GONE: Array = [[JUNO, "Gone. Something lives on this path. The relay's just ahead."]]
const YARD_SURGE: Array = [[JUNO, "Fence cable snapped, and there's one cornered in the yard. Easy..."]]
const YARD_WARNING: Array = [[JUNO, "I said easy!"]]
const YARD_AFTER: Array = [[JUNO, "Sorry. You gave me no room."], [JUNO, "It's got a battery contact in its teeth. The relay's breaker will want that."]]
const CELL_TAKEN: Array = [[JUNO, "There you are."], [JUNO, "Hang on, HOB. I found you a heartbeat."]]

## Small finds on the walks between sites (WalkFinds).
const FIND_RAIN_CUP: Array = [[JUNO, "Rainwater, clean as a lab sample. No: there's fibre in it, fine as hair."], [JUNO, "And it conducts. Wired it into the scanner. Huh. Better range."]]
const FIND_RAIN_CUP_AGAIN: Array = [[JUNO, "Fibre in the rain. It conducts. Worth something to the fabricator, anyway."]]
const FIND_TOWING_MARKS: Array = [[JUNO, "Something dragged a crate in here and never came back for it. Its loss."]]
const FIND_BEACON: Array = [[JUNO, "Back to the sky, old thing."], [JUNO, "It's pinging. And it's got a bearing on the canyon east: marked."]]
const FIND_GLASS_WIND: Array = [[JUNO, "Low, high, middle. The wind told me the combination. Spare rifle parts inside."]]
const FIND_BOLT_TAKEN: Array = [[JUNO, "Kestrel's stamp. Bolt fourteen-C. She's shedding."]]
const FIND_BOLT_RETURNED: Array = [[HOB, "Bolt fourteen-C. I'd been wondering where you'd gone."], [JUNO, "You talk to the bolts?"], [HOB, "Only the ones that come back."]]
const FIND_HELMET: Array = [[JUNO, "Someone's suit recorder. They were humming."], [JUNO, "The same three clicks. Before they crashed, or after?"]]
const FIND_BOOT: Array = [[JUNO, "One boot. Inside: a ration, never opened, and coordinates in pencil. The greenhouse."], [JUNO, "Whoever left this wanted the next one to find their way. Thanks."]]
const FIND_ORCHARD: Array = [[JUNO, "Seed pods that keep a charge. Slow feet, no flash. I'll take one."]]
const FIND_SIGNAL_FLAG: Array = [[JUNO, "A fibre flag knotting itself, and not a breath of wind. It's pulling west."], [JUNO, "The lace across that gap in the wall just went slack. A way round the Weave."]]
const FIND_POCKET_WEATHER: Array = [[JUNO, "Rain from nowhere, and it falls in threes. Same beat as the Loom pulse."], [JUNO, "Spore fibre in the puddle, too. Into the pouch."]]

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
## The relay's console, once the generator is back: Ilse's last traffic points up the slope.
const RELAY_CONSOLE_LINES := [
	[JUNO, "Station log. Last outbound traffic: 'Post Seven, hold your carrier, I'm still listening.'"],
	[JUNO, "Post Seven's up the south-east slope. Somebody kept a listening post running out here."],
]
## Coming up on Voss's greenhouses in the Shatterlands, and hailing the gate.
const GREENHOUSE_ARRIVE := [
	[JUNO, "Glasshouses. Lit. Somebody's growing things out here."],
	[HOB, "Palisade's new. Whoever's inside expects company, and not the friendly kind."],
]
const GREENHOUSE_HAIL := [
	[JUNO, "Greenhouses, this is Juno Vale, off the Kestrel. I've got Lieutenant Reyes's recorder."],
	[REYES, "Then you've got my last words, Vale. Lucky for both of us they weren't."],
	[REYES, "Stay where the lamp can see you. Eleven of us in here, and we've buried enough strangers."],
]
## Reyes's price for the gate: the nest under the Marigold's tail.
const GREENHOUSE_ASK := [
	[REYES, "You want in, earn it. There's a nest under that hauler's tail, by the lamp. It took Pell and Dorrie on a water run."],
	[REYES, "Clear it and come back to the gate."],
]
## Hailed with the nest already gone.
const GREENHOUSE_HAIL_CLEARED := [
	[REYES, "And that was you at the hauler. We heard it from here. Hold on, I'm opening up."],
]
const NEST_CLEARED := [
	[HOB, "That's the last of the nest. Reyes will have heard it from the gate."],
]
const GREENHOUSE_OPEN := [
	[REYES, "All right, Vale. Come in. Wipe your boots, the spores get into everything."],
]
## Inside the gate, the first time.
const REYES_TALK := [
	[REYES, "Ferro-9 came down for the Long Patience's people and we ended up needing rescuing ourselves. Same as everyone here."],
	[REYES, "Voss built this place sixty years ago. Her caps keep the pulse off us, mostly."],
	[JUNO, "Mostly?"],
	[REYES, "Some nights it gets through. Then we sit very still and wait for morning."],
	[REYES, "You've got a ship with a frame. We've got hands and a greenhouse full of salvage. Let's talk about getting both of us off this rock."],
	[REYES, "Start with Ferro-9. Brandt put her down in the Gillwood, north through the rim. Her canopy held, and so did her gear."],
	[REYES, "I'll have the north barricade pulled back. Whatever's moved into her since is yours to argue with."],
]
## Some of Reyes's eleven, a word each when Juno stops by (Claude's draft names and lines).
const SURVIVORS := {
	"Okafor": [["Okafor", "Okafor, Ferro-9's medic. If you're going to bleed, bleed over here, not on the beans."]],
	"Brandt": [["Brandt", "Brandt. I flew Ferro-9 in. Not my best landing. Not yours either, I hear."]],
	"Haddad": [["Haddad", "I watch the caps. When the violet goes dark all at once, the pulse is coming. Get inside."]],
	"Teo": [["Teo", "Voss's seed stock, sixty years in a locker, and it still comes up. Mind the squash."]],
}
const REYES_AGAIN := [
	[REYES, "Look around, Vale. Middle house is ours to eat from. Mind the beds."],
]
## The Gillwood: Ferro-9's crash site, north through the rim from the greenhouses.
const GILLWOOD_ARRIVE := [
	[HOB, "Spore count's climbing. Those gills are lit up like a runway."],
	[JUNO, "Somebody's runway. Past the stems there: slate hull, amber trim. That's Ferro-9."],
]
const FERRO_FOUND := [
	[JUNO, "She broke her back coming down, but the nose is whole. That canopy's the size of ours."],
	[HOB, "Kestrel's frame takes a Ferro-pattern canopy with an adapter ring. I can print the ring."],
]
const FERRO_CANOPY := [
	[JUNO, "Canopy's off. Seals look good."],
	[HOB, "Leave it on the skids. Reyes says her people can sled it back through the canyon."],
]
## The canopy rescue (milestone B1): the nose hangs in the trees, the canopy on a tilted spar.
const FERRO_CLIMB := [
	[HOB, "Careful. Your weight just shifted the nose. The canopy assembly's creeping down the spar."],
	[HOB, "Three emergency stay-lines on her: lock them before it goes over the edge."],
]
const FERRO_SLIPPED := [
	[JUNO, "It's going... and it's caught. On the lip of the spar. Lines are all sprung."],
	[HOB, "The spring brakes have pulled it back up. Again, Vale. Quicker."],
]
const FERRO_LINES_SET := [
	[JUNO, "Three lines on. It's not going anywhere now."],
	[HOB, "Ferro-9's winch is on the console under the nose. It'll lower the canopy onto the receiver pad."],
]
const FERRO_WINCH_START := [
	[HOB, "Winch is running. The power coupler's exposed, and it's singing. Things in these trees like that."],
]
const FERRO_SHORTED := [
	[JUNO, "Something hit the coupler. Winch has stopped."],
	[HOB, "Those chimes on the frame: Brandt hung them for a reason. Ring one and the veilwings scatter."],
]
const FERRO_WINCH_DONE := [
	[JUNO, "Canopy's on the pad. Seals look good."],
	[HOB, "Reyes's runners are sledding it home through the canyon. It'll be waiting at the install bay."],
]
const FERRO_GEAR := [
	[JUNO, "Gear strut's free. Bent at the knee, but the actuator's sound."],
	[HOB, "Kestrel's starboard leg will take it. That's the canopy and the gear, Vale."],
]
## The gear escort (milestone B2): the strut, Ferro-9's hauler drone, and Reyes's hoist.
const GEAR_CUT := [
	[JUNO, "Strut's free. Bent at the knee, but the actuator's sound. And heavy."],
	[HOB, "Ferro-9 had a hauler drone. It's under the aft section, half dead but it'll hover."],
]
const GEAR_MOUNTED := [
	[HOB, "It follows its beacon from node to node. Light the route nodes ahead of it and it'll keep moving."],
	[HOB, "Reyes has a salvage hoist east of here. Two ways there: pick one at the fork."],
]
const GEAR_LOW := [
	[JUNO, "Root tunnel. Nothing hunts down there."],
	[HOB, "Nothing but the weather. If a squall comes, that channel floods."],
]
const GEAR_HIGH := [
	[JUNO, "Over the ridge. Quicker."],
	[HOB, "Spore pods up there. If one bursts on the drone it'll jam. Pop them before it gets close."],
]
const GEAR_SQUALL := [
	[JUNO, "Here comes the rain. The tunnel's filling."],
	[HOB, "The drone's holding till the water drops. It won't drown, it's sulking."],
]
const GEAR_SQUALL_PASSED := [[HOB, "Water's down. It's moving again."]]
const GEAR_JAMMED := [
	[HOB, "Spores in the lift fans. It's jammed, not dead. There's scrap all over this wood: patch it."],
]
const GEAR_BROOD := [
	[JUNO, "A brood in the hoist clearing. The drone won't go in with them there."],
	[HOB, "There's a spore pod at the edge of it. Burst that and they'll scatter."],
]
const GEAR_HOISTED := [
	[JUNO, "Strut's on the hook. Reyes's runners can have it."],
	[HOB, "They'll sled it to Kestrel. That's the canopy and the gear, Vale."],
]
## The wing chase (milestone B3): Marigold's wing-tip section and the tether robot that took it.
const WING_GONE := [
	[JUNO, "Straps cut, drag marks. Somebody's had the wing-tip section."],
	[HOB, "Something. A salvage tether robot: there's its beacon, east, in the crags. It runs a circuit."],
	[HOB, "It bolts if you come at it head-on, and it crawls over cables. Or give it something better to eat."],
]
const WING_DECOY := [[HOB, "Decoy relay's live. Next time it rattles past, it'll stop to feed."]]
const WING_DRIFTERS := [
	[JUNO, "All that racket's brought drifters down off the wall."],
	[HOB, "It's got a siren. Hit it and they'll go after the robot instead of you."],
]
const WING_CAUGHT := [
	[JUNO, "Got it. Sorry, little one, I need this more."],
	[HOB, "Reyes's runners are on it. Marigold's tip, Kestrel's wing. Mismatched, but it'll fly."],
]
const WING_TAKEN := [
	[JUNO, "It's too busy feeding to notice. Panel's off."],
	[HOB, "Reyes's runners are on it. Marigold's tip, Kestrel's wing. Mismatched, but it'll fly."],
]
## The Loom Expanse's first pocket (milestone C), west through the Shatterlands' rim.
const LOOM_ARRIVE := [
	[HOB, "There's no pulse in the rock here. It's in the fibre. Everything you're looking at is one structure, Juno."],
	[JUNO, "Ridges like ship's cable, and they're breathing. Keep me off anything soft."],
]
const LOOM_CROWN := [
	[JUNO, "There. North, through the gap. Arches the height of a tower, and light down the middle."],
	[HOB, "Every pulse I've logged since the crash runs back to that. The survey teams called it the Tuning Crown."],
]
const LOOM_SHORTCUT := [
	[JUNO, "Knot's cut. The whole tunnel just sighed."],
	[HOB, "The far end's gone slack. That's your way back to the mouth."],
]
const WEAVE_GRIPS := [
	[JUNO, "Survey kit. Overboots with soft woven soles. The tag says 'for the weave'."],
	[HOB, "Soft soles don't carry through the fibre. The divers won't hear you run, and those trip-threads should slide off."],
]
const DIVER_SEEN := [
	[HOB, "Something's moving under the weave. That bulge. It hunts by footfall, not by sight."],
	[JUNO, "And stone doesn't carry. Slabs, then, and no running."],
]
const PINWEAVER_SEEN := [
	[JUNO, "Legs like a surveyor's calipers. It's stringing lines between the pillars."],
	[HOB, "Pale thread at shin height: crouch through it or shoot it. The amber valve on its back only opens while it anchors."],
]
const SINGER_SEEN := [
	[HOB, "The tall one is a resonator. When it plants its feet and draws breath, get rock between you and it."],
	[JUNO, "Or put a round through the membrane in its throat while it's breathing in."],
]
const LOOM_OPEN := [
	[HOB, "Juno, the fibres across the Shatterlands' west cleft just went slack. Whatever was holding that door has let go."],
]
## The landing gear's reward: the utility drone (UtilityDrone) on its cradle in the cargo bay.
const DRONE_READY := [
	[HOB, "With the ramp down the cargo bay has power again. There's a utility drone in the cradle by the ramp. Launch it and it'll ride with you: it fetches what you leave lying about, and it carries a med-seal for when you're in trouble."],
]
## The wing's reward: the field beacon (FieldBeacon).
const BEACON_READY := [
	[HOB, "The wing-tip had a survey beacon in its housing. It's on your scanner now. Plant it with B anywhere outside, and if you go down, I'll bring you up beside it."],
]
## Teo's favour (the dark house): the east glasshouse went dark in the last pulse.
const TEO_ASK := [
	["Teo", "You're the pilot? Good, you can wire. The east house went dark in the last pulse. Its cell cooked."],
	["Teo", "Voss kept spare lamp cells up on the high shelf, west side, out of the scuttlers' reach. There's a spitter up there now."],
	[JUNO, "And you'd like me to go and get one."],
	["Teo", "I'd like the beans to live. You'd like to eat. Same thing."],
]
const TEO_WAITING := [
	["Teo", "High shelf, up the steps on the west side. Oxide box, Voss's mark on the lid."],
]
const CELL_FOUND := [
	[HOB, "Voss-pattern lamp cell. Eighty percent charge after sixty years. She built things to last."],
]
const TEO_THANKS := [
	["Teo", "Oh, that's a good cell. Hold the lid... there."],
	["Teo", "Look at that. Tell Okafor the east house is back."],
	["Teo", "Here, we pulled these off Ferro-9 and nobody in here can use them."],
]
## Waking Ilse's listening post on the south-east slope.
const POST_LINES := [
	[HOB, "That's one of Ilse Marrow's listening posts. Still logging, after all this time."],
	[JUNO, "There's something under the basin, HOB. Way down. It answers every pulse."],
	[HOB, "Noted. I'd rather not go and say hello just yet."],
]
## Pulling the flight recorder from Reyes's drop pod.
const POD_LINES := [
	[HOB, "Got it all. Juno, Reyes's people are alive. Eleven of them, past the north-east canyon."],
	[JUNO, "The one that's full of rockfall."],
	[HOB, "That one. One thing at a time. Ship first, then rescues."],
]
## Taking the dormant core from the survey depot.
const DEPOT_LINES := [
	[HOB, "A WREN-series core. Older than me, and very tired. I'll keep it safe in my spare bay."],
	[JUNO, "Is there really a song on it?"],
	[HOB, "There is. I'll play it for you when we're off this rock. Not before; I'm superstitious."],
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
	# Discoveries ("discovery", the discovery's id): places off the repair routes.
	{
		"id": "post_1", "site": "discovery", "source": "listening_post",
		"title": "Listening post three", "author": "Ilse Marrow",
		"text": "Third post up and listening. The lattice doesn't stop at the basin floor. Under every pulse there's an echo that comes back late, from somewhere a long way down, as if the Kettle sits on a hollow. All three posts hear it. Pell says I should stop putting microphones on a planet that pulls ships out of the sky. Pell is probably right. I've left this one running in case anyone else wants to listen.",
	},
	{
		"id": "pod_1", "site": "discovery", "source": "drop_pod",
		"title": "Supply drop, six of six", "author": "Lt. Sana Reyes",
		"text": "Last drop, and the pod's going down hard. If you've pulled this recorder, you've met the welcoming committee. We're not at the Long Patience any more. Marrow found Voss's old greenhouses on the far side of the north-east canyon, under the big fungus, and they're holding. Eleven of us. The canyon came down behind us in the last quake. If you have a way through it, we have a way off this rock. Reyes out.",
	},
	{
		"id": "depot_1", "site": "discovery", "source": "survey_depot",
		"title": "Depot core, last state", "author": "WREN, survey ship mind",
		"text": "Crew of four went north to the spire on day nineteen. Crew of four did not come back. I have kept the lamps on the emergency circuit for six hundred and two days so the door would be easy to find. I am shutting down to save what is left. If you are a ship mind, take my core: the pulse timings for nineteen days are in it, and so is a song the geologist liked. If you are not a ship mind, please find one. I would like the song to be heard.",
	},
	# Shatterlands logs ("shatterlands", a place in that region).
	{
		"id": "voss_1", "site": "shatterlands", "source": "marigold_locker",
		"title": "Marigold, dorsal locker", "author": "Hester Voss, hauler Marigold",
		"text": "Last glass run, and the Marigold's done flying. Doesn't matter. The houses are up, under the big cap, and the big cap is the point: the pulse comes through the rock and the caps drink it. Under there the instruments stop twitching and the seedlings stop dying. Two charges in here for whoever needs them more than a dead hauler does. Plant something.",
	},
	# Gillwood logs ("gillwood", a place in that region).
	{
		"id": "ferro_1", "site": "gillwood", "source": "ferro_cockpit",
		"title": "Ferro-9, flight recorder", "author": "Pilot Brandt, Ferro-9",
		"text": "Ferro-9, descent. Locked on the Long Patience beacon. At four hundred metres the pulse hit and every board went dark, same as the old reports said. I put her into the softest thing I could see, which was a forest of mushrooms. Seven aboard, seven walking. The canopy held. The jettison locker blew clear on the way down, somewhere west in the trees; there's kit in it if anyone comes back for her. Reyes says we walk south toward the light. Recorder off.",
	},
	# The Loom Expanse ("loom_expanse").
	{
		"id": "loom_survey", "site": "loom_expanse", "source": "survey_marker",
		"title": "Tension memory", "author": "Resonance survey marker",
		"text": "A severed Loom fibre does not go slack. Under a microscope it curls into smaller rings and holds a pattern of bends made before it was cut. The rings seem to anticipate the next pulse, as though strain could remember its own future. A field scanner calls it an error. The researchers called it a material with history. After the third experiment, the test table began vibrating without power. The team buried the samples in basalt, sealed the results and left the table behind.",
	},
	# Drift caches out on the open basin ("basin", "cache:N"): cargo from every ship the Loom pulled down.
	{
		"id": "basin_1", "site": "basin", "source": "cache:0",
		"title": "Cargo tag, seed stock", "author": "Long Patience, hold 4",
		"text": "Pod 4-17. Seed stock, cold-sealed: barley, beans, two hundred apple pips for the colony orchard. Do not open below four degrees. Do not open in vacuum. Whoever finds this, sixty years late: the barley still grows if you keep it out of the pools.",
	},
	{
		"id": "basin_2", "site": "basin", "source": "cache:2",
		"title": "Supply drop, three of six", "author": "Lt. Sana Reyes",
		"text": "Dropping supplies on the walk to the graveyard in case anyone is left behind. Masks, stims, a box of charges. The scuttlers dig in under anything warm, so prise the lid from the side and be ready to run. If you're reading this, we're at the Long Patience. Come and find us.",
	},
	{
		"id": "basin_3", "site": "basin", "source": "cache:5",
		"title": "Field notes, the pools", "author": "Pell Adair, survey",
		"text": "Something long lives in the deep pools, with eyes on stalks like a frog's. It waits with only the eyes above the water and it never chases far from home. Shoot it in the water and it barely notices. Get it up on the rock, aim for the eyes, and it remembers it has somewhere else to be.",
	},
	{
		"id": "basin_4", "site": "basin", "source": "cache:7",
		"title": "Weather, again", "author": "Dace Okoro",
		"text": "The squalls come over the rim every few hours. In the rain the packs go half blind, so that's when we move the haul trucks. The scuttlers' backs light up when they're hunting, and that glowing ridge is soft. Tell the new hires: shoot the glow, not the shell.",
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
