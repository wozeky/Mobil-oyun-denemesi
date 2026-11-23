#!/usr/bin/env python3
"""Son Hat - Pure-stdlib Pixel Art PNG & Procedural WAV Asset Generator."""
import math
import os
import random
import struct
import wave
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPRITES = os.path.join(ROOT, "assets", "sprites")
AUDIO = os.path.join(ROOT, "assets", "audio")
os.makedirs(SPRITES, exist_ok=True)
os.makedirs(AUDIO, exist_ok=True)


def write_png(path, w, h, pixels):
    """Write RGBA bytearray (len == w*h*4) as a valid PNG."""
    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", crc)

    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    ihdr = struct.pack("!IIBBBBB", w, h, 8, 6, 0, 0, 0)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.buf = bytearray(w * h * 4)

    def px(self, x, y, rgba):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            self.buf[i:i + 4] = bytes(rgba)

    def rect(self, x, y, w, h, rgba):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.px(xx, yy, rgba)

    def save(self, path):
        write_png(path, self.w, self.h, self.buf)


# Workshop train palette
PETROL = (28, 56, 54, 255)
PETROL_DARK = (16, 34, 35, 255)
TILE_YEL = (196, 184, 134, 255)
TILE_LINE = (128, 118, 84, 255)
STEEL = (47, 55, 61, 255)
STEEL_HI = (86, 98, 108, 255)
BRASS = (204, 158, 62, 255)
GLOW_GRN = (91, 227, 152, 255)
WARM_WHT = (255, 242, 214, 255)
BRAKE_RED = (230, 57, 70, 255)
CAPE = (30, 42, 48, 255)
CAPE_HI = (56, 76, 84, 255)
SKIN = (222, 198, 174, 255)
GUARD = (44, 38, 42, 255)
SHIELD = (118, 132, 142, 255)


def make_icon():
    c = Canvas(64, 64)
    c.rect(0, 0, 64, 64, PETROL_DARK)
    c.rect(4, 4, 56, 56, PETROL)
    c.rect(10, 10, 44, 28, (14, 22, 28, 255))
    c.rect(14, 18, 36, 4, WARM_WHT)
    c.rect(20, 24, 22, 2, GLOW_GRN)
    c.rect(24, 34, 12, 22, CAPE)
    c.rect(34, 38, 4, 4, WARM_WHT)
    for i in range(36):
        c.rect(12 + i, 50 - int(i * 0.7), 3, 3, BRAKE_RED)
    c.save(os.path.join(ROOT, "icon.png"))


def make_tiles():
    c = Canvas(128, 64)
    c.rect(0, 0, 32, 32, PETROL)
    c.rect(0, 0, 32, 2, PETROL_DARK)
    c.rect(0, 30, 32, 2, PETROL_DARK)
    c.rect(15, 0, 2, 32, PETROL_DARK)
    c.rect(32, 0, 32, 32, TILE_YEL)
    for y in range(0, 32, 8):
        c.rect(32, y, 32, 1, TILE_LINE)
    for x in range(32, 64, 8):
        c.rect(x, 0, 1, 32, TILE_LINE)
    c.rect(64, 0, 32, 32, STEEL)
    c.rect(64, 0, 32, 3, STEEL_HI)
    for x in range(66, 94, 6):
        c.rect(x, 8, 3, 2, PETROL_DARK)
        c.rect(x + 2, 18, 3, 2, PETROL_DARK)
    c.rect(96, 0, 32, 32, STEEL)
    c.rect(101, 4, 22, 14, (132, 158, 156, 200))
    c.rect(120, 20, 5, 3, BRASS)
    c.rect(0, 32, 32, 32, PETROL_DARK)
    c.rect(4, 38, 24, 16, STEEL)
    c.rect(7, 42, 18, 3, GLOW_GRN)
    c.rect(7, 47, 12, 3, GLOW_GRN)
    c.save(os.path.join(SPRITES, "tiles_train.png"))


def make_player():
    c = Canvas(192, 32)
    for f in range(6):
        ox = f * 32
        if f in (0, 1, 2):
            bob = 1 if f == 1 else 0
            c.rect(ox + 12, 6 + bob, 6, 6, SKIN)
            c.rect(ox + 10, 5 + bob, 10, 3, CAPE)
            c.rect(ox + 8, 12 + bob, 12, 11, CAPE)
            c.rect(ox + 7, 13 + bob, 3, 9, CAPE_HI)
            c.rect(ox + 18, 12 + bob, 3, 3, WARM_WHT)
            c.rect(ox + 10, 21 + bob, 4, 3, BRASS)
            lx = 11 + (2 if f == 1 else (-2 if f == 2 else 0))
            rx = 16 - (2 if f == 1 else (-2 if f == 2 else 0))
            c.rect(ox + lx, 23, 3, 8, PETROL_DARK)
            c.rect(ox + rx, 23, 3, 8, PETROL_DARK)
        elif f == 3:
            c.rect(ox + 9, 15, 14, 12, CAPE)
            c.rect(ox + 11, 17, 10, 6, CAPE_HI)
            c.rect(ox + 18, 16, 3, 3, WARM_WHT)
            c.rect(ox + 10, 22, 4, 2, BRASS)
        elif f == 4:
            c.rect(ox + 10, 6, 6, 6, SKIN)
            c.rect(ox + 8, 12, 10, 12, CAPE)
            c.rect(ox + 16, 12, 3, 3, WARM_WHT)
            c.rect(ox + 9, 24, 4, 6, PETROL_DARK)
        else:
            c.rect(ox + 14, 7, 6, 6, SKIN)
            c.rect(ox + 9, 13, 13, 10, CAPE)
            c.rect(ox + 20, 12, 3, 3, WARM_WHT)
            c.rect(ox + 22, 14, 9, 2, WARM_WHT)
            c.rect(ox + 11, 23, 3, 8, PETROL_DARK)
            c.rect(ox + 18, 23, 3, 8, PETROL_DARK)
    c.save(os.path.join(SPRITES, "player_sheet.png"))


def make_enemies():
    c = Canvas(160, 32)
    configs = [
        (GUARD, BRAKE_RED, False, False),
        (GUARD, STEEL_HI, False, False),
        ((58, 36, 36, 255), BRASS, False, False),
        (GUARD, SHIELD, True, False),
        ((24, 20, 26, 255), BRAKE_RED, False, True),
    ]
    for i, (body, accent, has_shield, is_boss) in enumerate(configs):
        ox = i * 32
        c.rect(ox + 12, 6, 6, 6, SKIN)
        c.rect(ox + 11, 4, 8, 3, accent if is_boss else body)
        c.rect(ox + 10, 12, 11, 12, body)
        c.rect(ox + 12, 14, 7, 3, accent)
        c.rect(ox + 11, 24, 3, 7, PETROL_DARK)
        c.rect(ox + 17, 24, 3, 7, PETROL_DARK)
        if has_shield:
            c.rect(ox + 21, 9, 4, 19, SHIELD)
            c.rect(ox + 22, 11, 2, 15, WARM_WHT)
        if is_boss:
            c.rect(ox + 7, 11, 4, 15, BRAKE_RED)
            c.rect(ox + 21, 14, 9, 2, WARM_WHT)
    c.save(os.path.join(SPRITES, "enemies_sheet.png"))


def make_props():
    c = Canvas(128, 32)
    c.rect(6, 12, 4, 12, GLOW_GRN)
    c.rect(7, 8, 2, 4, WARM_WHT)
    c.rect(20, 14, 9, 3, WARM_WHT)
    c.rect(17, 14, 3, 3, BRASS)
    c.rect(36, 11, 6, 12, STEEL_HI)
    c.rect(37, 13, 4, 3, GLOW_GRN)
    c.rect(50, 7, 12, 18, BRAKE_RED)
    c.rect(50, 12, 12, 3, WARM_WHT)
    c.rect(68, 10, 10, 6, STEEL_HI)
    c.rect(76, 12, 3, 3, BRAKE_RED)
    c.rect(86, 6, 12, 18, STEEL)
    c.rect(88, 9, 8, 6, GLOW_GRN)
    c.rect(89, 17, 6, 4, BRASS)
    c.save(os.path.join(SPRITES, "props_sheet.png"))


def write_wav(path, samples, rate=22050):
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(rate)
        data = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            data.extend(struct.pack("<h", int(v * 32767)))
        wf.writeframes(bytes(data))


def synth_sfx():
    sr = 22050
    rng = random.Random(42)

    dur = 0.14
    n = int(sr * dur)
    lp = 0.0
    out = []
    for i in range(n):
        t = i / n
        env = math.sin(math.pi * t) ** 1.3
        noise = rng.uniform(-1, 1)
        alpha = 0.08 + 0.16 * (1.0 - t)
        lp += alpha * (noise - lp)
        out.append(lp * env * 0.65)
    write_wav(os.path.join(AUDIO, "sfx_whiff.wav"), out, sr)

    dur = 0.18
    n = int(sr * dur)
    out = []
    for i in range(n):
        t = i / sr
        env = math.exp(-t * 24.0)
        sub = math.sin(2 * math.pi * (140 - 90 * min(1, t * 8)) * t) * math.exp(-t * 18)
        crisp = rng.uniform(-1, 1) * math.exp(-t * 48)
        out.append((sub * 0.75 + crisp * 0.55) * (0.4 + 0.6 * env))
    write_wav(os.path.join(AUDIO, "sfx_hit.wav"), out, sr)

    dur = 0.20
    n = int(sr * dur)
    out = []
    for i in range(n):
        t = i / sr
        env = math.exp(-t * 20.0)
        body = (math.sin(2 * math.pi * 195 * t) * 0.6 + math.sin(2 * math.pi * 318 * t) * 0.35)
        knock = rng.uniform(-1, 1) * math.exp(-t * 95) * 0.4
        out.append((body + knock) * env * 0.85)
    write_wav(os.path.join(AUDIO, "sfx_block.wav"), out, sr)

    dur = 0.30
    n = int(sr * dur)
    out = []
    for i in range(n):
        t = i / sr
        env = math.exp(-t * 11.0)
        ring = (
            math.sin(2 * math.pi * 1420 * t) * 0.45 +
            math.sin(2 * math.pi * 2310 * t) * 0.35 +
            math.sin(2 * math.pi * 3180 * t) * 0.20
        )
        out.append(ring * env * 0.8)
    write_wav(os.path.join(AUDIO, "sfx_clash.wav"), out, sr)

    dur = 0.22
    n = int(sr * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / sr
        freq = 1100.0 + 2600.0 * (1.0 - math.exp(-t * 14.0))
        phase += 2 * math.pi * freq / sr
        env = math.exp(-t * 15.0)
        out.append((math.sin(phase) * 0.65 + math.sin(phase * 1.97) * 0.25) * env)
    write_wav(os.path.join(AUDIO, "sfx_deflect.wav"), out, sr)

    dur = 0.16
    n = int(sr * dur)
    out = [((rng.uniform(-1, 1) * 0.85 + math.sin(2 * math.pi * 110 * (i / sr)) * 0.5) * math.exp(-(i / sr) * 28)) for i in range(n)]
    write_wav(os.path.join(AUDIO, "sfx_shot.wav"), out, sr)

    dur = 0.24
    n = int(sr * dur)
    out = [((math.sin(2 * math.pi * 82 * (i / sr)) * 0.7 + rng.uniform(-1, 1) * 0.45) * math.exp(-(i / sr) * 16)) for i in range(n)]
    write_wav(os.path.join(AUDIO, "sfx_door.wav"), out, sr)

    dur = 0.12
    n = int(sr * dur)
    out = [(math.sin(2 * math.pi * (680 if i < n // 2 else 1020) * (i / sr)) * math.exp(-(i / sr) * 22) * 0.6) for i in range(n)]
    write_wav(os.path.join(AUDIO, "sfx_pickup.wav"), out, sr)

    dur = 0.26
    n = int(sr * dur)
    out = []
    for i in range(n):
        t = i / sr
        c1 = math.exp(-((t - 0.03) ** 2) / 0.00018) * (0.7 * rng.uniform(-1, 1) + 0.4 * math.sin(2 * math.pi * 1650 * t))
        c2 = math.exp(-((t - 0.15) ** 2) / 0.00018) * (0.7 * rng.uniform(-1, 1) + 0.4 * math.sin(2 * math.pi * 1380 * t))
        out.append((c1 + c2) * 0.75)
    write_wav(os.path.join(AUDIO, "sfx_radio.wav"), out, sr)

    dur = 0.09
    n = int(sr * dur)
    out = [(math.sin(2 * math.pi * 130 * (i / sr)) * 0.45 + rng.uniform(-1, 1) * 0.35) * math.exp(-(i / sr) * 42) for i in range(n)]
    write_wav(os.path.join(AUDIO, "sfx_footstep.wav"), out, sr)

    dur = 0.55
    n = int(sr * dur)
    lp = 0.0
    out = []
    for i in range(n):
        t = i / sr
        lp += 0.12 * (rng.uniform(-1, 1) - lp)
        boom = math.sin(2 * math.pi * (65 - 30 * min(1, t * 2)) * t) * 0.7
        out.append((boom + lp * 0.9) * math.exp(-t * 5.2))
    write_wav(os.path.join(AUDIO, "sfx_explode.wav"), out, sr)


def synth_music():
    sr = 22050
    dur = 3.2
    n = int(sr * dur)
    rng = random.Random(99)

    rail_hits = [0.0, 0.19, 0.80, 0.99, 1.60, 1.79, 2.40, 2.59]
    bass_notes = [(0.0, 55.0), (0.8, 55.0), (1.6, 61.74), (2.4, 51.91)]

    rail_bass = [0.0] * n
    for i in range(n):
        t = i / sr
        s = 0.0
        for h in rail_hits:
            dt = t - h
            if 0.0 <= dt < 0.09:
                s += (rng.uniform(-1, 1) * 0.25 + math.sin(2 * math.pi * 92 * dt) * 0.35) * math.exp(-dt * 42)
        freq = 55.0
        for bt, bf in bass_notes:
            if t >= bt:
                freq = bf
        beat_env = 0.45 + 0.55 * math.exp(-((t % 0.8) * 5.0))
        s += (math.sin(2 * math.pi * freq * t) * 0.32 + math.sin(4 * math.pi * freq * t) * 0.10) * beat_env
        rail_bass[i] = s * 0.85
    write_wav(os.path.join(AUDIO, "mus_rail_bass.wav"), rail_bass, sr)

    metal_hits = [0.38, 0.58, 1.18, 1.38, 1.98, 2.18, 2.78, 2.98]
    metal = [0.0] * n
    for i in range(n):
        t = i / sr
        s = 0.0
        for h in metal_hits:
            dt = t - h
            if 0.0 <= dt < 0.08:
                s += (math.sin(2 * math.pi * 1180 * dt) * 0.35 + math.sin(2 * math.pi * 1790 * dt) * 0.25 + rng.uniform(-1, 1) * 0.15) * math.exp(-dt * 45)
        metal[i] = s * 0.75
    write_wav(os.path.join(AUDIO, "mus_metal_perc.wav"), metal, sr)

    loco_hits = [k * 0.20 for k in range(16)]
    loco = [0.0] * n
    for i in range(n):
        t = i / sr
        s = 0.0
        for idx, h in enumerate(loco_hits):
            dt = t - h
            if 0.0 <= dt < 0.07:
                f = 220.0 if idx % 4 == 0 else 146.83
                s += math.sin(2 * math.pi * f * dt) * math.exp(-dt * 36) * 0.32
        loco[i] = s * 0.8
    write_wav(os.path.join(AUDIO, "mus_loco_pulse.wav"), loco, sr)


if __name__ == "__main__":
    make_icon()
    make_tiles()
    make_player()
    make_enemies()
    make_props()
    synth_sfx()
    synth_music()
    print("Generated all Son Hat pixel-art PNGs and WAV audio assets.")
