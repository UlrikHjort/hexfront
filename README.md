# Hexfront

A turn-based operational hex wargame in the classic style,
written in Ada 2012 with GtkAda (GTK3). One era-neutral engine, with eras and
scenarios defined in plain text data files.

## Features

* Era-neutral engine; WW2, WW1 and Napoleonic eras defined in data files
* Fog of war with spotting ranges and ambushes
* Air units (fighters, bombers) in a separate air layer, flak and interception;
  aircraft must return to airfields or friendly towns to refuel
* Buying new units with prestige; resupply and reinforcement
* Campaigns: chained battles where surviving core units keep their experience
* Save / load, hot seat (with hand-over screen), watch computer vs computer
* Boot Camp tutorial scenario with pop-up hints that teach wargame basics
* Computer opponent that obeys the fog of war (remembers what it saw);
  can be switched to "sees everything" in the Game menu
* Animated movement and combat (muzzle flashes, explosions, loss numbers)
  with synthesised sound effects (played with paplay / pw-play / aplay)
* Campaigns: Blitz in the West (1940), The Road to Austerlitz (1805),
  Kaiserschlacht (1918)
* Scenario and campaign chooser with a map preview
* Encirclement: units with no escape hex are surrounded (defence -2, no
  supply). The AI withdraws battered units, concentrates its attacks,
  closes envelopments, picks a "main effort" objective and counter-attacks
  threats to its own objectives
* Campaign HQ between battles: re-equip veteran core units with better
  models of the same class, paid with prestige
* Built-in scenario editor (Game > Scenario editor): paint terrain, place
  units, towns and objectives, set up sides, save and play-test

## Build & run

    gprbuild -P hexfront.gpr
    ./bin/hexfront                                   # scenario chooser
    ./bin/hexfront data/scenarios/ww2_meuse.scn      # start directly
    ./bin/hexfront data/scenarios/ww1_bigpush.scn watch   # side1|side2|hotseat|watch

Tools:

    gprbuild -P selftest.gpr && ./bin/selftest [-v]  # AI vs AI on every scenario
    gprbuild -P render.gpr && ./bin/render_png <scn> out.png   # headless map render

## Layout

    src/engine/   era-neutral engine (no GUI dependencies)
      engine-hexes      odd-q hex geometry, distance, neighbours
      engine-terrain    terrain kinds, movement costs, defence bonuses
      engine-units      unit types (from data) and unit instances
      engine-game       game state, movement/ZOC, combat, supply, turns, victory
      engine-loader     .era and .scn parsers
      engine-ai         computer opponent (one unit per step)
    src/ui/       GtkAda front end (Cairo map renderer + main window)
      engine-campaign   campaign chains and core-unit carry-over
      engine-save       save/load (~/.hexfront/saves)
      engine-editing    editor operations and the .scn writer
    data/eras/        ww2.era, ww1.era, napoleonic.era
    data/scenarios/   *.scn
    data/campaigns/   *.cmp
    data/sounds/      *.wav sound effects
    tools/            gen_scenarios.py (+ mapgen.py) regenerates the bundled
                      scenarios: python3 tools/gen_scenarios.py
                      gen_sounds.py synthesises data/sounds

## Rules summary

* Move, then attack. Artillery cannot fire after moving. Recon can split moves.
* Entering a hex adjacent to an enemy (zone of control) stops movement.
* Combat: each strength point fires with a hit chance from attack minus defence
  (terrain, entrenchment, experience). The defender returns fire at range 1.
  Nearby `support` guns fire defensively. `bombard` fire suppresses.
* Units that stay still dig in. Resupply or Reinforce (costs prestige) instead
  of moving or attacking.
* The attacker must take every objective (gold ring) before the turn limit.

Era tweaks (`rule` line): `max_entrench`, `charge_bonus` (cavalry shock in the
open), `square_bonus` (infantry vs cavalry), `close_armor_penalty`.

## Data formats

Era file: `unit id=medtank name=Medium_Tank class=armor move=tracked target=hard
mp=6 range=1 soft=7 hard=8 def=8 ammo=8 fuel=50 cost=300 flags=support,bombard`
(underscores become spaces).

Scenario file: `title`, `description`, `era`, `turns`, `attacker`, `first`,
`side N name= color=r,g,b control=human|ai prestige= income=`, `map W H`
followed by H rows of terrain glyphs, `territory side= cols=A-B`,
`place at=c,r name= owner= [victory]`, `unit side= type= at=c,r [str= exp= entrench=] [core]`.
Optional: `category Tutorial`, `fog on|off`, `buy side=N types=a,b,c|none`,
`hint turn=N text...` or `hint event=select|move|contact|ambush|attack|kill|loss|capture|buy|resupply|reinforce text...`
with `more text...` continuation lines.

Campaign file (`data/campaigns/*.cmp`): `title`, `era`, `description`,
`player N`, `prestige N`, and `stage id= file= win=<id|victory> loss=<id|defeat>`.
Units marked `core` are the slots filled by the player's surviving units.

Terrain glyphs: `.` clear `=` road `f` forest `h` hills `M` mountain `~` river
`s` swamp `t` town `C` city `F` fortress `w` water `#` trench `A` airfield.
