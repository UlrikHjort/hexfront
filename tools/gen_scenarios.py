#!/usr/bin/env python3
"""Generates the bundled Hexfront scenarios into ../data/scenarios.

Maps are painted procedurally (see mapgen.py) and then written in the plain
text .scn format, so the output files can also be edited by hand.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mapgen import Map

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'scenarios')


def write(name, header, m, territory, places, units, extra=()):
    """units: list of (side, type, col, row, options-string)"""
    s = list(header)
    s.append(f"map {m.w} {m.h}")
    s.append(m.dump())
    for side, a, b in territory:
        s.append(f"territory side={side} cols={a}-{b}")
    for c, r, ch, n, o, v in places:
        m.set(c, r, ch)
        s.append(f"place at={c},{r} name={n} owner={o}" + (" victory" if v else ""))
    # sanity: vehicles cannot stand in river/swamp/mountain, nothing in water
    vehicles = ("tank", "medtank", "lighttank", "heavytank", "armcar", "atgun", "fieldart",
                "heavyart", "flak")
    air = ("fighter", "divebomb", "medbomb", "scout", "biplane")
    for side, t, c, r, opt in units:
        g = m.get(c, r)
        if t in air:
            continue
        bad = g == 'w' or (t in vehicles and g in '~sM')
        if bad:
            raise SystemExit(f"{name}: {t} at {c},{r} stands on '{g}'")
    # places may change glyphs: re-dump map
    s[s.index(f"map {m.w} {m.h}") + 1] = m.dump()
    s.extend(extra)
    for side, t, c, r, opt in units:
        s.append(f"unit side={side} type={t} at={c},{r}" + (" " + opt if opt else ""))
    with open(os.path.join(OUT, name), 'w') as f:
        f.write("\n".join(s) + "\n")


def U(side, lst, opt=""):
    return [(side, t, c, r, opt) for t, c, r in lst]

# German core force used through the WW2 campaign: 16 ground + 4 air slots.
CORE_GROUND = ["medtank", "medtank", "lighttank", "lighttank", "heavytank", "armcar",
               "infantry", "infantry", "infantry", "infantry", "pioneers", "pioneers",
               "fieldart", "fieldart", "heavyart", "atgun"]
CORE_AIR = ["fighter", "fighter", "divebomb", "divebomb"]


def core(ground_pos, air_pos):
    assert len(ground_pos) == len(CORE_GROUND) and len(air_pos) == len(CORE_AIR)
    return ([(1, t, c, r, "core") for t, (c, r) in zip(CORE_GROUND, ground_pos)] +
            [(1, t, c, r, "core") for t, (c, r) in zip(CORE_AIR, air_pos)])

# =====================================================================
# Tutorial
# =====================================================================
m = Map(16, 10)
m.rect(5, 1, 6, 2, 'f'); m.set(5, 3, 'f')
m.rect(10, 6, 11, 7, 'f'); m.set(10, 5, 'f')
m.set(8, 6, 'h'); m.set(8, 7, 'h'); m.set(9, 7, 'h'); m.set(12, 1, 'h'); m.set(13, 1, 'h')
m.path([(7, 0), (7, 3), (6, 9)], '~')
m.path([(0, 5), (4, 5), (9, 4), (13, 6), (15, 6)], '=')
m.set(3, 8, 's'); m.set(4, 8, 's')
places = [(1, 5, 't', 'Camp_Alpha', 1, False), (1, 8, 'A', 'Alpha_Field', 1, False),
          (9, 4, 't', 'Millbrook', 2, True), (13, 6, 't', 'Eastwick', 2, True)]
hdr = [
 "title Boot Camp: Learning the Ropes",
 "category Tutorial",
 "description A small training battle. Pop-up hints explain the basics of hex",
 "description wargaming as you play: moving, scouting, attacking, artillery,",
 "description supply, prestige and air power. Take Millbrook and Eastwick.",
 "era ww2", "turns 14", "attacker 1", "first 1",
 "side 1 name=Blue_Force color=60,100,180 control=human prestige=150 income=20",
 "side 2 name=Red_Force color=170,60,50 control=ai prestige=0 income=0",
 "buy side=1 types=infantry,medtank,fieldart,armcar,atgun",
 "buy side=2 types=none",
 # ---- hints ----
 "hint turn=1 Welcome to Hexfront boot camp!",
 "more",
 "more The map is made of hexes. Each counter is a unit; the number on it is its",
 "more strength (10 = full). Blue counters are yours, red ones are the enemy.",
 "more",
 "more Your mission: capture the two villages with gold rings - Millbrook and",
 "more Eastwick - within 14 turns. Gold-ringed hexes are OBJECTIVES.",
 "more",
 "more Notice the grey haze: that is the FOG OF WAR. You only see what your units",
 "more can see. Start by clicking your ARMOURED CAR (the counter with a slash",
 "more and a small circle, at the front) to select it.",
 "hint event=select A unit is selected (yellow outline).",
 "more",
 "more The darkened hexes are out of reach this turn. Moving costs points per hex:",
 "more roads are cheap, forest, hills and rivers are expensive. The side panel",
 "more shows the unit's movement points, attack and defence values.",
 "more",
 "more Move the armoured car forward along the road by clicking a lit hex.",
 "more Recon units see further (3 hexes) and may split their move.",
 "hint event=move Good. Look how the fog lifts around your unit as it moves.",
 "more",
 "more Rules of movement:",
 "more  - A unit normally moves once per turn (recon may continue).",
 "more  - Entering a hex next to an enemy stops you: its ZONE OF CONTROL.",
 "more  - You cannot move through enemy units.",
 "more",
 "more Now move the rest of your force up, keeping infantry and tanks together.",
 "more Leave the artillery where it is for now. Press 'End turn' when done.",
 "hint event=contact Contact! A unit stopped because it bumped into an enemy zone of control.",
 "more Scouting with cheap recon units first avoids nasty surprises.",
 "hint event=ambush AMBUSH! An enemy unit was hidden in the fog and blocked your path.",
 "more Your unit stopped short and lost the rest of its move. Scout ahead!",
 "hint turn=2 ATTACKING",
 "more",
 "more Select a unit: enemies it can attack get a RED outline. Hover the mouse",
 "more over one to see the EXPECTED LOSSES on both sides before you commit.",
 "more",
 "more Combat tips:",
 "more  - Defenders in towns, forests and hills are much harder to hurt.",
 "more  - Units that sit still DIG IN (brown ticks on the counter).",
 "more    Every attack knocks one level of entrenchment off.",
 "more  - Tanks hate close terrain (towns, forest); infantry loves it.",
 "more  - Use ARTILLERY first: it fires from range 2-3 without return fire,",
 "more    kills and SUPPRESSES the target. But guns cannot fire after moving!",
 "more  - Then assault with infantry and tanks from several sides.",
 "hint event=attack The defender fires back at close range, so both sides take losses.",
 "more Check the combat log at the bottom right for details.",
 "hint event=kill Enemy unit destroyed! Destroying units and capturing towns earns PRESTIGE.",
 "hint event=loss You lost a unit. Weak units should pull back to reinforce rather than attack.",
 "hint turn=3 SUPPLY AND ENTRENCHMENT",
 "more",
 "more Units use ammunition when they fight, and vehicles burn fuel. A small",
 "more orange dot on a counter means it is running low.",
 "more",
 "more A unit that has not moved or fought this turn can press RESUPPLY",
 "more (only half if an enemy is adjacent). It can also press REINFORCE to",
 "more replace losses, paid for with prestige.",
 "hint turn=4 AIR POWER",
 "more",
 "more You have a DIVE BOMBER at Alpha Field. Aircraft fly over everything",
 "more and ignore zones of control. A bomber attacks the hex below it or next",
 "more to it, and the target is suppressed too.",
 "more",
 "more But aircraft burn fuel every turn they spend away from an airfield or",
 "more friendly town. If the tank runs dry they crash! Land, then Resupply.",
 "more Beware enemy flak and fighters, which shoot back.",
 "hint turn=5 PRESTIGE",
 "more",
 "more Prestige is your currency. Spend it on 'Buy unit': new units appear in",
 "more your own towns or airfields and can act from next turn. In a campaign,",
 "more surviving units and prestige carry over to the next battle.",
 "hint event=capture Captured! Owning a town gives you a flag on it and some prestige.",
 "more Objectives (gold rings) decide the battle: take them all to win.",
 "hint event=buy New unit deployed. It can move from your next turn.",
 "hint turn=7 GENERAL ADVICE",
 "more",
 "more  - Concentrate: three units attacking one enemy beat three duels.",
 "more  - Protect the flanks of your artillery; it is weak in close combat.",
 "more  - Keep a reserve, and pull battered units back to refit.",
 "more  - Watch the turn counter: an attack that is too slow fails too.",
 "hint turn=11 Only a few turns left! Push for the objectives now.",
]
units = U(1, [("armcar", 4, 4), ("infantry", 3, 5), ("infantry", 2, 4), ("infantry", 3, 3),
              ("medtank", 3, 6), ("fieldart", 1, 4), ("pioneers", 2, 6)])
units += U(1, [("divebomb", 1, 8)])
units += U(2, [("infantry", 9, 4)], "entrench=2")
units += U(2, [("atgun", 10, 6), ("infantry", 12, 3), ("fieldart", 14, 4), ("armcar", 8, 1)])
units += U(2, [("infantry", 13, 6)], "entrench=1")
write("tutorial.scn", hdr, m, [(1, 0, 4), (2, 5, 15)], places, units)

# =====================================================================
# WW2: Breakthrough at the Meuse (campaign stage 1)
# =====================================================================
m = Map(28, 16)
m.scatter(15, 0, 27, 15, 'f', 0.55, 1)
m.scatter(15, 0, 27, 15, 'h', 0.25, 2)
m.scatter(0, 0, 10, 15, 'f', 0.10, 3)
m.scatter(0, 0, 10, 15, 'h', 0.06, 4)
m.path([(12, 0), (12, 5), (11, 9), (12, 15)], '~')
m.scatter(13, 0, 14, 15, 'h', 0.35, 5)
m.path([(27, 8), (20, 9), (15, 9), (11, 9), (5, 10), (0, 11)], '=', keep='~')
m.path([(27, 3), (21, 4), (13, 3), (12, 3), (6, 4), (0, 4)], '=', keep='~')
m.path([(11, 9), (9, 5), (6, 4)], '=', keep='~')
m.path([(20, 9), (19, 13), (14, 14), (12, 13)], '=', keep='~')
m.path([(5, 10), (3, 14)], '=')
m.rect(0, 15, 4, 15, '.')
places = [(11, 9, 'C', 'Sedan', 2, True), (12, 3, 't', 'Dinant', 2, True), (12, 6, 't', 'Montherme', 2, False),
          (6, 4, 't', 'Charleville', 2, True), (3, 11, 'C', 'Rethel', 2, True), (12, 13, 't', 'Mouzon', 2, False),
          (24, 4, 't', 'Bastogne', 1, False), (23, 10, 't', 'Neufchateau', 1, False), (18, 9, 't', 'Bouillon', 2, False),
          (26, 1, 'A', 'Airfield', 1, False), (25, 14, 'A', 'Airfield', 1, False),
          (2, 7, 'A', 'Airfield', 2, False), (6, 13, 'A', 'Airfield', 2, False)]
hdr = ["title Breakthrough at the Meuse (1940)",
       "description Spring 1940. Armoured columns have pushed through the wooded hills",
       "description and stand before the river line. Force the crossings at Sedan and",
       "description Dinant, then drive west and take Charleville and Rethel before the",
       "description defenders can bring up their reserves. 14 turns.",
       "era ww2", "turns 14", "attacker 1", "first 1",
       "side 1 name=Wehrmacht color=96,104,88 control=human prestige=300 income=30",
       "side 2 name=French_Army color=70,110,170 control=ai prestige=150 income=20"]
units = core([(26, 8), (25, 3), (27, 7), (26, 4), (27, 9), (23, 8), (24, 7), (22, 5), (25, 10), (23, 3),
              (24, 9), (22, 4), (26, 6), (26, 10), (27, 5), (25, 9)],
             [(26, 1), (25, 14), (24, 4), (23, 10)])
fr = [("armcar", 18, 8), ("cavalry", 17, 4), ("infantry", 11, 8), ("bunker", 11, 10), ("infantry", 12, 4),
      ("bunker", 12, 2), ("infantry", 12, 7), ("infantry", 12, 12), ("atgun", 10, 9), ("fieldart", 9, 7),
      ("fieldart", 9, 3), ("infantry", 6, 5), ("heavytank", 4, 9), ("medtank", 5, 6), ("infantry", 3, 10),
      ("atgun", 7, 4), ("flak", 10, 10)]
for t, c, r in fr:
    units.append((2, t, c, r, "entrench=2" if t in ("infantry", "atgun") and c <= 12 else ""))
units += U(2, [("fighter", 2, 7), ("medbomb", 6, 13)])
write("ww2_meuse.scn", hdr, m, [(2, 0, 21), (1, 22, 27)], places, units)

# =====================================================================
# WW2: Dash to the Channel (campaign stage 2)
# =====================================================================
m = Map(30, 16)
m.scatter(0, 0, 29, 15, 'f', 0.10, 31)
m.scatter(0, 0, 29, 15, 'h', 0.07, 32)
for r in range(16):
    m.set(0, r, 'w')
    if r % 5 != 2: m.set(1, r, 'w')
m.path([(29, 11), (20, 10), (12, 12), (2, 11)], '~')
m.path([(29, 4), (16, 4), (11, 4), (3, 3)], '=', keep='~')
m.path([(28, 10), (18, 10), (7, 11)], '=', keep='')
m.path([(16, 4), (13, 7), (18, 10)], '=', keep='~')
m.path([(11, 4), (7, 11)], '=', keep='')
places = [(16, 4, 'C', 'Arras', 2, True), (18, 10, 'C', 'Amiens', 2, True), (7, 11, 't', 'Abbeville', 2, True),
          (3, 3, 'C', 'Boulogne', 2, True), (11, 4, 't', 'St_Pol', 2, False), (13, 7, 't', 'Doullens', 2, False),
          (25, 4, 't', 'Cambrai', 1, False), (24, 10, 't', 'Peronne', 1, False),
          (27, 7, 'A', 'Airfield', 1, False), (28, 2, 'A', 'Airfield', 1, False),
          (5, 6, 'A', 'Airfield', 2, False), (8, 1, 'A', 'Airfield', 2, False)]
hdr = ["title Dash to the Channel (1940)",
       "description The front is broken. Race west to the sea and cut the allied armies",
       "description in two: take Arras, Amiens, Abbeville and the port of Boulogne.",
       "description Expect an armoured counter-attack around Arras. 18 turns.",
       "era ww2", "turns 18", "attacker 1", "first 1",
       "side 1 name=Wehrmacht color=96,104,88 control=human prestige=100 income=30",
       "side 2 name=Allied_Forces color=150,110,60 control=ai prestige=100 income=15"]
units = core([(26, 6), (26, 8), (27, 5), (27, 9), (28, 7), (24, 7), (25, 5), (25, 9), (24, 3), (24, 11),
              (26, 4), (26, 10), (28, 5), (28, 9), (29, 7), (25, 7)],
             [(27, 7), (28, 2), (25, 4), (24, 10)])
units += U(2, [("heavytank", 15, 3), ("heavytank", 17, 5), ("infantry", 16, 4), ("infantry", 15, 5),
               ("atgun", 17, 3), ("fieldart", 13, 4), ("infantry", 18, 10), ("infantry", 19, 11),
               ("infantry", 12, 12), ("atgun", 17, 9), ("fieldart", 15, 10), ("medtank", 10, 8),
               ("infantry", 7, 11), ("infantry", 3, 3), ("flak", 5, 6), ("infantry", 11, 4),
               ("cavalry", 20, 6)])
units += U(2, [("fighter", 5, 6), ("fighter", 8, 1), ("medbomb", 3, 3)])
write("ww2_channel.scn", hdr, m, [(2, 0, 21), (1, 22, 29)], places, units)

# =====================================================================
# WW2: The Dunkirk Perimeter (campaign stage 3)
# =====================================================================
m = Map(24, 14)
m.rect(0, 0, 23, 0, 'w')
for c in range(24):
    if c % 3: m.set(c, 1, 'w')
m.scatter(0, 2, 23, 6, 's', 0.25, 41)           # polders
m.scatter(0, 7, 23, 13, 'f', 0.12, 42)
m.scatter(0, 7, 23, 13, 'h', 0.08, 43)
m.path([(0, 8), (8, 7), (14, 6), (23, 4)], '~')  # canal line
m.path([(5, 2), (6, 5), (9, 10), (10, 13)], '=', keep='~')
m.path([(5, 2), (13, 3), (21, 2)], '=')
m.path([(13, 3), (16, 9), (18, 13)], '=', keep='~')
places = [(5, 2, 'C', 'Dunkirk', 2, True), (6, 5, 't', 'Bergues', 2, True), (13, 3, 't', 'Furnes', 2, True),
          (10, 5, 't', 'Hondschoote', 2, False), (21, 2, 't', 'Nieuport', 2, True),
          (9, 11, 't', 'Cassel', 1, False), (17, 11, 't', 'Ypres', 1, False),
          (12, 12, 'A', 'Airfield', 1, False), (3, 3, 'A', 'Airfield', 2, False)]
hdr = ["title The Dunkirk Perimeter (1940)",
       "description The allied armies are trapped against the sea and are evacuating.",
       "description Break the canal line and take Dunkirk, Bergues, Furnes and Nieuport",
       "description before they slip away. The polders are boggy and the defenders",
       "description are dug in. 14 turns.",
       "era ww2", "turns 14", "attacker 1", "first 1",
       "side 1 name=Wehrmacht color=96,104,88 control=human prestige=150 income=30",
       "side 2 name=Allied_Forces color=150,110,60 control=ai prestige=80 income=15"]
units = core([(8, 10), (14, 10), (11, 11), (16, 10), (12, 10), (6, 10), (4, 10), (10, 9), (15, 9), (19, 8),
              (7, 9), (13, 9), (9, 12), (14, 12), (11, 13), (17, 10)],
             [(12, 12), (9, 11), (17, 11), (20, 12)])
de = [("infantry", 3, 7), ("infantry", 6, 6), ("infantry", 8, 6), ("infantry", 11, 5), ("infantry", 14, 5),
      ("infantry", 17, 4), ("infantry", 20, 3), ("atgun", 9, 5), ("atgun", 16, 5)]
for t, c, r in de:
    units.append((2, t, c, r, "entrench=2"))
units += U(2, [("fieldart", 6, 4), ("fieldart", 12, 3), ("heavyart", 5, 3), ("flak", 9, 4),
               ("medtank", 8, 3), ("infantry", 5, 2), ("infantry", 21, 2)])
units += U(2, [("fighter", 3, 3), ("fighter", 5, 2)])
write("ww2_dunkirk.scn", hdr, m, [(2, 0, 23)], places, units)

# =====================================================================
# WW1: The Big Push
# =====================================================================
m = Map(24, 14)
m.scatter(0, 0, 23, 13, 'f', 0.07, 11)
m.scatter(0, 0, 23, 13, 'h', 0.08, 12)
m.rect(7, 0, 10, 13, '.')
m.scatter(7, 0, 10, 13, 's', 0.35, 13)
m.path([(5, 0), (6, 6), (5, 13)], '#')
m.path([(11, 0), (12, 7), (11, 13)], '#')
m.path([(16, 0), (16, 13)], '#')
m.path([(0, 8), (4, 8)], '=')
m.path([(17, 6), (23, 6)], '=')
m.path([(0, 13), (3, 10)], '~')
places = [(12, 3, 't', 'Thiepval', 2, True), (11, 10, 't', 'Fricourt', 2, True), (13, 12, 't', 'Montauban', 2, True),
          (17, 6, 't', 'Pozieres', 2, True), (17, 10, 't', 'Contalmaison', 2, False), (22, 6, 'C', 'Bapaume', 2, False),
          (2, 8, 't', 'Albert', 1, False), (2, 3, 't', 'Hamel', 1, False),
          (0, 5, 'A', 'Airfield', 1, False), (22, 2, 'A', 'Airfield', 2, False)]
hdr = ["title The Big Push (1916)",
       "description Summer 1916. After a week of bombardment the infantry goes over the",
       "description top. Break the first trench system, seize the fortified villages and",
       "description open the road to Bapaume. Wire, machine guns and deep dugouts await. 18 turns.",
       "era ww1", "turns 18", "attacker 1", "first 1",
       "side 1 name=British_Army color=150,120,70 control=human prestige=300 income=50",
       "side 2 name=German_Army color=110,120,130 control=ai prestige=60 income=10"]
units = U(1, [("infantry", 5, 1), ("infantry", 6, 3), ("infantry", 6, 5), ("infantry", 6, 7), ("infantry", 6, 9),
              ("infantry", 5, 11), ("storm", 5, 6), ("storm", 6, 10), ("infantry", 4, 4), ("infantry", 4, 8),
              ("tank", 4, 6), ("tank", 4, 10), ("mg", 5, 2), ("fieldgun", 3, 2), ("fieldgun", 3, 6),
              ("fieldgun", 3, 10), ("howitzer", 1, 5), ("howitzer", 1, 9), ("cavalry", 1, 7),
              ("cavalry", 0, 11), ("storm", 4, 2)])
units += U(1, [("scout", 0, 5), ("biplane", 2, 8)])
for t, c, r in [("mg", 12, 2), ("infantry", 12, 5), ("mg", 12, 7), ("infantry", 11, 9), ("mg", 11, 11),
                ("infantry", 12, 1), ("mg", 12, 3), ("infantry", 11, 13), ("mg", 16, 4),
                ("infantry", 16, 7), ("infantry", 16, 11), ("fieldgun", 14, 4), ("fieldgun", 14, 9),
                ("howitzer", 19, 6), ("armcar", 21, 5), ("aagun", 18, 8)]:
    units.append((2, t, c, r, "entrench=3" if t in ("mg", "infantry") and c <= 16 else ""))
units += U(2, [("scout", 22, 2)])
write("ww1_bigpush.scn", hdr, m, [(1, 0, 8), (2, 9, 23)], places, units)

# =====================================================================
# Napoleonic: Austerlitz
# =====================================================================
m = Map(24, 16)
m.scatter(0, 0, 23, 15, 'f', 0.06, 21)
m.rect(11, 4, 16, 10, 'h')
m.scatter(10, 3, 17, 11, '.', 0.15, 22, only='h')
m.set(3, 2, 'h'); m.set(2, 2, 'h'); m.set(15, 5, 'h')
m.path([(8, 0), (9, 4), (8, 9), (8, 15)], '~')
m.rect(10, 14, 15, 15, 'w'); m.rect(11, 13, 13, 13, 'w')
m.scatter(9, 12, 16, 15, 's', 0.4, 23)
m.path([(0, 2), (10, 2), (16, 2), (23, 2)], '=', keep='~')
m.path([(0, 9), (8, 9), (13, 7), (22, 9)], '=', keep='~')
places = [(13, 7, 't', 'Pratzen', 2, True), (15, 5, 'h', 'Stare_Vinohrady', 2, True), (11, 2, 't', 'Blasowitz', 2, True),
          (8, 12, 't', 'Telnitz', 2, False), (8, 10, 't', 'Sokolnitz', 2, False), (22, 9, 't', 'Austerlitz', 2, True),
          (2, 9, 't', 'Turas', 1, False), (3, 2, 'h', 'Santon', 1, False)]
hdr = ["title Austerlitz (1805)",
       "description December 1805. The allied army has weakened its centre to strike at",
       "description your right along the Goldbach. Storm the Pratzen heights, split their",
       "description army and march on Austerlitz itself. 14 turns.",
       "era napoleonic", "turns 14", "attacker 1", "first 1",
       "side 1 name=Grande_Armee color=50,70,160 control=human prestige=250 income=25",
       "side 2 name=Allied_Army color=40,120,60 control=ai prestige=60 income=10"]
units = U(1, [("line", 6, 4), ("line", 6, 6), ("line", 7, 8), ("line", 7, 11), ("line", 6, 13), ("light", 5, 2),
              ("light", 7, 6), ("grenadier", 4, 7), ("guard", 2, 8), ("cuirass", 3, 4), ("cuirass", 4, 5),
              ("hussars", 5, 3), ("hussars", 6, 14), ("footart", 4, 3), ("footart", 5, 8), ("horseart", 3, 6),
              ("dragoons", 5, 11), ("line", 5, 9)], "core")
units += U(2, [("line", 9, 11), ("line", 9, 12), ("line", 9, 9), ("line", 10, 13), ("line", 13, 6),
               ("line", 12, 8), ("line", 14, 9), ("grenadier", 15, 6), ("guard", 18, 7), ("line", 11, 3),
               ("cossacks", 14, 2), ("cossacks", 9, 14), ("dragoons", 17, 3), ("cuirass", 18, 5),
               ("footart", 13, 4), ("footart", 10, 10), ("footart", 14, 8), ("line", 20, 8)])
write("nap_austerlitz.scn", hdr, m, [(1, 0, 7), (2, 8, 23)], places, units)


# =====================================================================
# Napoleonic: Ulm (campaign stage 1)
# =====================================================================
m = Map(26, 16)
m.scatter(0, 0, 25, 15, 'f', 0.10, 51)
m.scatter(0, 0, 25, 5, 'h', 0.22, 52)
m.path([(0, 9), (8, 8), (13, 7), (20, 8), (25, 7)], '~')      # Danube
m.path([(12, 15), (12, 8)], '~')                               # Iller
m.path([(13, 7), (7, 3), (0, 1)], '=', keep='~')
m.path([(13, 7), (19, 9), (25, 10)], '=', keep='~')
m.path([(13, 7), (11, 11), (10, 14)], '=', keep='~')
m.path([(17, 5), (21, 1), (25, 0)], '=', keep='~')
m.scatter(14, 11, 22, 15, 's', 0.15, 53)
places = [(13, 7, 'F', 'Ulm', 2, True), (17, 5, 't', 'Elchingen', 2, True), (5, 8, 't', 'Gunzburg', 2, True),
          (10, 14, 't', 'Memmingen', 2, True), (21, 1, 't', 'Nordlingen', 1, False), (4, 2, 't', 'Aalen', 1, False),
          (24, 10, 't', 'Augsburg', 1, False)]
hdr = ["title Ulm: The Encirclement (1805)",
       "description Autumn 1805. While the Austrian army waits at Ulm for an attack from",
       "description the west, your corps have swung around its flank to the north and",
       "description east. Close the ring: take Elchingen, Gunzburg and Memmingen and",
       "description force the fortress of Ulm before the Russians arrive. 14 turns.",
       "era napoleonic", "turns 14", "attacker 1", "first 1",
       "side 1 name=Grande_Armee color=50,70,160 control=human prestige=200 income=20",
       "side 2 name=Austrian_Army color=225,225,215 control=ai prestige=150 income=20"]
units = U(1, [("line", 5, 3), ("line", 8, 3), ("line", 11, 2), ("line", 14, 2), ("line", 18, 2), ("line", 22, 4),
              ("light", 9, 1), ("light", 23, 7), ("grenadier", 16, 1), ("cuirass", 12, 1), ("cuirass", 20, 2),
              ("hussars", 3, 4), ("hussars", 24, 9), ("dragoons", 22, 2), ("footart", 13, 2), ("footart", 17, 2),
              ("horseart", 21, 3), ("line", 6, 1)], "core")
units += U(2, [("line", 13, 7), ("line", 12, 6), ("line", 14, 6), ("grenadier", 13, 8), ("line", 17, 5),
               ("line", 16, 6), ("line", 5, 8), ("line", 6, 9), ("line", 10, 14), ("line", 9, 12),
               ("footart", 12, 7), ("footart", 15, 7), ("footart", 5, 9), ("hussars", 8, 6),
               ("dragoons", 11, 9), ("cuirass", 14, 9), ("line", 18, 6), ("grenadier", 6, 8),
               ("line", 11, 13)])
write("nap_ulm.scn", hdr, m, [(2, 0, 25), (1, 0, 0)], places, units)

# =====================================================================
# WW1: Operation Michael (campaign stage 1) - attack from the east
# =====================================================================
m = Map(26, 14)
m.scatter(0, 0, 25, 13, 'f', 0.08, 61)
m.scatter(0, 0, 25, 13, 'h', 0.07, 62)
m.rect(18, 0, 19, 13, '.')
m.scatter(18, 0, 19, 13, 's', 0.4, 63)
m.path([(17, 0), (16, 7), (17, 13)], '#')       # British forward zone
m.path([(12, 0), (12, 13)], '#')                # battle zone
m.path([(0, 11), (10, 9), (14, 11), (25, 12)], '~')   # Somme
m.path([(23, 7), (14, 6), (8, 4), (0, 5)], '=', keep='~')
m.path([(14, 6), (10, 9), (3, 8)], '=', keep='')
places = [(23, 7, 'C', 'St_Quentin', 1, False), (21, 2, 'A', 'Airfield', 1, False),
          (14, 11, 't', 'Ham', 2, True), (10, 9, 't', 'Peronne', 2, True), (8, 4, 'C', 'Bapaume', 2, True),
          (3, 8, 't', 'Albert', 2, True), (14, 6, 't', 'Epehy', 2, False), (2, 2, 'A', 'Airfield', 2, False)]
hdr = ["title Operation Michael (1918)",
       "description March 1918. Reinforced from the east, your armies strike the British",
       "description line in thick morning fog. New infiltration tactics let assault troops",
       "description bypass strongpoints: break through and take Ham, Peronne, Bapaume",
       "description and Albert. 16 turns.",
       "era ww1", "turns 16", "attacker 1", "first 1",
       "side 1 name=German_Army color=110,120,130 control=human prestige=250 income=40",
       "side 2 name=British_Army color=150,120,70 control=ai prestige=40 income=8"]
ger = [("storm", 20, 2), ("storm", 20, 5), ("storm", 20, 8), ("storm", 20, 11), ("infantry", 21, 3),
       ("infantry", 21, 6), ("infantry", 21, 9), ("infantry", 21, 12), ("infantry", 22, 5), ("infantry", 22, 9),
       ("mg", 22, 3), ("mg", 22, 11), ("fieldgun", 23, 4), ("fieldgun", 23, 9), ("fieldgun", 24, 6),
       ("howitzer", 25, 4), ("howitzer", 25, 9), ("cavalry", 24, 12)]
units = U(1, ger, "core")
units += U(1, [("scout", 21, 2), ("biplane", 23, 7)], "core")
for t, c, r in [("infantry", 17, 1), ("mg", 16, 4), ("infantry", 16, 7), ("mg", 16, 10), ("infantry", 17, 12),
                ("infantry", 12, 2), ("mg", 12, 6), ("infantry", 12, 10), ("infantry", 14, 6)]:
    units.append((2, t, c, r, "entrench=3"))
units += U(2, [("fieldgun", 14, 3), ("fieldgun", 14, 9), ("howitzer", 9, 6), ("tank", 7, 8), ("tank", 9, 3),
               ("cavalry", 5, 6), ("aagun", 10, 5), ("infantry", 3, 8)])
units += U(2, [("scout", 2, 2)])
write("ww1_michael.scn", hdr, m, [(2, 0, 19), (1, 20, 25)], places, units)

# =====================================================================
# WW1: Drive on the Marne (campaign stage 2) - attack north to south
# =====================================================================
m = Map(24, 16)
m.scatter(0, 0, 23, 15, 'f', 0.12, 71)
m.rect(0, 4, 23, 5, 'h')                          # Chemin des Dames ridge
m.scatter(0, 4, 23, 5, 'f', 0.2, 72, only='h')
m.path([(0, 5), (23, 5)], '#')
m.path([(0, 8), (8, 7), (16, 8), (23, 7)], '~')   # Aisne
m.path([(0, 11), (12, 10), (23, 11)], '~')        # Vesle
m.path([(0, 14), (10, 14), (23, 13)], '~')        # Marne
m.path([(12, 0), (10, 6), (4, 8), (8, 12)], '=', keep='~')
m.path([(10, 6), (14, 10), (20, 11)], '=', keep='~')
places = [(12, 0, 'C', 'Laon', 1, False), (18, 1, 'A', 'Airfield', 1, False),
          (4, 8, 'C', 'Soissons', 2, True), (14, 10, 't', 'Fismes', 2, True), (8, 12, 't', 'Chateau-Thierry', 2, True),
          (20, 11, 'C', 'Reims', 2, False), (2, 12, 't', 'Villers', 2, False), (16, 15, 'A', 'Airfield', 2, False)]
hdr = ["title Drive on the Marne (1918)",
       "description May 1918. A crushing bombardment opens the assault on the Chemin des",
       "description Dames ridge. Storm the heights, cross the Aisne and the Vesle and",
       "description reach the Marne at Chateau-Thierry. Take Soissons and Fismes on the",
       "description way. 18 turns.",
       "era ww1", "turns 18", "attacker 1", "first 1",
       "side 1 name=German_Army color=110,120,130 control=human prestige=150 income=40",
       "side 2 name=Allied_Army color=165,135,75 control=ai prestige=40 income=10"]
gpos = [(3, 2), (6, 2), (9, 2), (12, 2), (15, 2), (18, 2), (4, 1), (8, 1), (13, 1), (17, 1), (20, 2), (21, 1),
        (2, 1), (10, 0), (14, 0), (6, 0), (16, 0), (22, 2)]
units = [(1, t, c, r, "core") for (t, _, _), (c, r) in zip(ger, gpos)]
units += U(1, [("scout", 18, 1), ("biplane", 12, 0)], "core")
for t, c, r in [("infantry", 3, 5), ("mg", 7, 5), ("infantry", 11, 5), ("mg", 15, 5), ("infantry", 19, 5),
                ("infantry", 22, 5)]:
    units.append((2, t, c, r, "entrench=2"))
units += U(2, [("fieldgun", 9, 6), ("fieldgun", 17, 6), ("infantry", 4, 8), ("infantry", 14, 10),
               ("infantry", 8, 12), ("mg", 9, 12), ("tank", 12, 12), ("cavalry", 6, 11), ("howitzer", 16, 12),
               ("infantry", 20, 11), ("aagun", 13, 9)])
units += U(2, [("scout", 16, 15)])
write("ww1_marne.scn", hdr, m, [(2, 0, 23)], places, units)

# =====================================================================
# Campaign
# =====================================================================
camp = os.path.join(OUT, '..', 'campaigns')
os.makedirs(camp, exist_ok=True)
with open(os.path.join(camp, 'blitz_west.cmp'), 'w') as f:
    f.write("""title Blitz in the West (1940)
era ww2
description Lead a panzer corps through three battles of the 1940 campaign: the
description Meuse crossings, the dash to the Channel and the Dunkirk perimeter.
description Surviving core units keep their experience; prestige carries over.
player 1
prestige 0
stage id=meuse   file=ww2_meuse.scn   win=channel loss=defeat
stage id=channel file=ww2_channel.scn win=dunkirk loss=defeat
stage id=dunkirk file=ww2_dunkirk.scn win=victory loss=defeat
""")
with open(os.path.join(camp, 'road_to_austerlitz.cmp'), 'w') as f:
    f.write("""title The Road to Austerlitz (1805)
era napoleonic
description Lead the Grande Armee from the Rhine to Moravia: first trap the
description Austrian army at Ulm, then face the Austro-Russian host at Austerlitz.
description Your veterans carry their experience from one battle to the next.
player 1
prestige 0
stage id=ulm        file=nap_ulm.scn        win=austerlitz loss=austerlitz
stage id=austerlitz file=nap_austerlitz.scn win=victory    loss=defeat
""")
with open(os.path.join(camp, 'kaiserschlacht.cmp'), 'w') as f:
    f.write("""title Kaiserschlacht (1918)
era ww1
description The last gamble of the Great War. Lead the German spring offensives:
description smash through the British line in Operation Michael, then storm the
description Chemin des Dames and drive for the Marne.
player 1
prestige 0
stage id=michael file=ww1_michael.scn win=marne   loss=defeat
stage id=marne   file=ww1_marne.scn   win=victory loss=defeat
""")
print("scenarios written to", os.path.normpath(OUT))
