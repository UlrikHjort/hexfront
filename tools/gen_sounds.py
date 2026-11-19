#!/usr/bin/env python3
"""Synthesises Hexfront's sound effects into ../data/sounds/*.wav.

Everything is generated from noise and sine waves, so the sounds are
original and small. Re-run after tweaking.
"""
import math, os, random, struct, wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'sounds')
rnd = random.Random(1914)


def silence(sec):
    return [0.0] * int(sec * RATE)


def noise(sec, decay=8.0, lp=0.5, gain=1.0, attack=0.002):
    """Low-passed noise burst with exponential decay."""
    out, y = [], 0.0
    n = int(sec * RATE)
    for i in range(n):
        t = i / RATE
        y += lp * (rnd.uniform(-1, 1) - y)
        env = min(1.0, t / attack) * math.exp(-decay * t)
        out.append(y * env * gain)
    return out


def tone(freq, sec, decay=3.0, gain=0.5, vibrato=0.0, slide=0.0, shape='sine'):
    out, ph = [], 0.0
    n = int(sec * RATE)
    for i in range(n):
        t = i / RATE
        f = freq * (1 + vibrato * math.sin(2 * math.pi * 5 * t)) + slide * t
        ph += 2 * math.pi * f / RATE
        if shape == 'square':
            v = 1.0 if math.sin(ph) > 0 else -1.0
            v *= 0.4
        elif shape == 'brass':
            v = math.sin(ph) + 0.5 * math.sin(2 * ph) + 0.3 * math.sin(3 * ph)
            v *= 0.5
        else:
            v = math.sin(ph)
        env = min(1.0, t / 0.01) * math.exp(-decay * t)
        out.append(v * env * gain)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def at(track, start):
    return silence(start) + track


def seq(*parts):
    out = []
    for p in parts:
        out += p
    return out


def save(name, data, volume=0.8):
    peak = max(1e-6, max(abs(x) for x in data))
    data = [x / peak * volume for x in data]
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b''.join(struct.pack('<h', int(x * 32000)) for x in data))


# --- movement -------------------------------------------------------------
save('move_foot', seq(*[noise(0.12, 30, 0.15) + silence(0.13) for _ in range(4)]), 0.5)
save('move_horse', seq(*[noise(0.05, 50, 0.4) + silence(0.07) + noise(0.05, 50, 0.4) + silence(0.18)
                         for _ in range(3)]), 0.5)
rumble = noise(1.0, 1.2, 0.04, attack=0.15)
clank = seq(*[noise(0.03, 60, 0.9, 0.35) + silence(0.09) for _ in range(8)])
save('move_tracks', mix(rumble, clank), 0.55)
save('move_wheels', mix(noise(0.9, 1.5, 0.06, attack=0.1), tone(70, 0.9, 1.5, 0.3, slide=20)), 0.5)
save('move_air', mix(tone(110, 1.1, 1.0, 0.4, vibrato=0.04, slide=-30, shape='square'),
                     noise(1.1, 1.2, 0.2, 0.3, attack=0.2)), 0.45)
# --- weapons --------------------------------------------------------------
save('fire_rifle', seq(*[noise(0.09, 45, 0.7) + silence(rnd.uniform(0.02, 0.09)) for _ in range(6)]), 0.6)
save('fire_mg', seq(*[noise(0.04, 80, 0.8) + silence(0.035) for _ in range(14)]), 0.55)
save('fire_gun', mix(noise(0.6, 9, 0.5), tone(55, 0.6, 6, 0.8)), 0.8)
save('fire_artillery', mix(noise(1.2, 4, 0.12), tone(40, 1.2, 4, 1.0)), 0.9)
whistle = tone(1400, 0.7, 0.5, 0.25, slide=-1300)
save('fire_bomb', seq(whistle, mix(noise(1.0, 4, 0.15), tone(45, 1.0, 4, 1.0))), 0.9)
save('fire_musket', seq(*[noise(0.15, 20, 0.6) + silence(rnd.uniform(0.0, 0.06)) for _ in range(8)]), 0.6)
save('fire_cannon', mix(noise(0.9, 5, 0.25), tone(48, 0.9, 5, 0.9)), 0.85)
save('fire_air', seq(*[noise(0.03, 90, 0.9) + silence(0.025) for _ in range(18)]), 0.5)
# --- events ---------------------------------------------------------------
save('explosion', mix(noise(1.6, 2.5, 0.08), noise(0.4, 12, 0.6, 0.5), tone(35, 1.4, 3, 1.0)), 0.95)
notes = [392, 523, 659, 784]
save('capture', seq(tone(392, 0.18, 4, shape='brass'), tone(523, 0.18, 4, shape='brass'),
                    tone(659, 0.45, 3, shape='brass')), 0.6)
save('deploy', mix(noise(0.25, 15, 0.3), tone(220, 0.25, 10, 0.5)), 0.5)
save('victory', seq(*[tone(f, 0.16, 4, shape='brass') for f in notes],
                    tone(1046, 0.9, 1.5, shape='brass')), 0.65)
save('defeat', seq(*[tone(f, 0.35, 3, shape='brass') for f in (392, 349, 311)],
                   tone(262, 1.0, 1.5, shape='brass')), 0.6)
save('click', tone(1200, 0.05, 60, 0.4), 0.3)
# --- naval (appended so the earlier sounds stay unchanged) ---------------
save('move_ship', mix(tone(62, 1.4, 0.8, 0.5, vibrato=0.02), noise(1.4, 1.0, 0.03, 0.6, attack=0.3),
                     at(tone(150, 0.9, 1.2, 0.35, shape='brass'), 0.2)), 0.5)

save('fire_naval', seq(mix(noise(0.5, 6, 0.3), tone(38, 0.5, 5, 1.0)), silence(0.15),
                      mix(noise(1.4, 3, 0.08), tone(32, 1.4, 3, 1.0))), 0.95)

print('sounds written to', os.path.normpath(OUT))
