#!/usr/bin/env python3
"""Synthesises every sound and both music tracks for Derby Game from
scratch and writes them into assets/audio/.

    python3 tools/audio/make_sounds.py            # everything
    python3 tools/audio/make_sounds.py --no-music # skip the slow music render
    python3 tools/audio/make_sounds.py --check DIR  # also write spectrograms
    python3 tools/audio/make_sounds.py --only pickups  # just one group

Nothing is sampled: engines, impacts, weather, UI and music are all built
from oscillators, noise, filters, modal resonators and synthetic rooms
(numpy only). Seamless loops are written as WAV, which Godot compresses to
QOA on import with a forward loop over the whole file. One-shots and music
are Ogg Vorbis (encoded with ffmpeg's libvorbis); the music .import files
turn looping on.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import analyze  # noqa: E402
import engines  # noqa: E402
import songs  # noqa: E402
import sounds as sx  # noqa: E402
from dsp import SR, db, rms_db, short_term_max_rms_db, undb  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")

# Exact rpm of each engine loop (low, mid, high). scripts/audio/car_audio.gd
# has the same table; the loop lengths are chosen so these come out exact.
ENGINE_RPMS = {
	"v8": (1080.0, 3000.0, 5568.0),
	"monster": (900.0, 2625.0, 4800.0),
	"six": (1500.0, 4575.0, 8160.0),
	"four": (1500.0, 4425.0, 7584.0),
}
LEVEL_NAMES = ("low", "mid", "high")


def limit(x, ceiling_db=-1.0, knee=0.75):
	"""Pointwise soft limiter (keeps loops periodic)."""
	c = undb(ceiling_db)
	k = knee * c
	a = np.abs(x)
	over = a > k
	y = x.copy()
	y[over] = np.sign(x[over]) * (k + (c - k) * np.tanh((a[over] - k) / (c - k)))
	return y


def level(x, loop, target_db, ceiling_db=-1.0):
	"""Loops: set RMS. One-shots: set the loudest 400 ms. Then make sure the
	peak stays under the ceiling."""
	mono = x.mean(axis=0) if x.ndim > 1 else x
	cur = rms_db(mono) if loop else short_term_max_rms_db(mono)
	x = x * undb(target_db - cur)
	if np.max(np.abs(x)) > undb(ceiling_db) * 0.75:
		x = limit(x, ceiling_db)
	return x


def write_wav(path, x):
	x = np.atleast_2d(x)
	pcm = np.clip(np.round(x.T * 32767.0), -32768, 32767).astype("<i2")
	with wave.open(path, "wb") as w:
		w.setnchannels(x.shape[0])
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(pcm.tobytes())


def write_ogg(path, x, quality):
	with tempfile.TemporaryDirectory() as tmp:
		src = os.path.join(tmp, "in.wav")
		write_wav(src, x)
		subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-c:a", "libvorbis",
			"-q:a", str(quality), path], check=True)


def write_import(path, kind, loop):
	"""Write the Godot .import settings next to an audio file. An existing
	file keeps its [remap] and [deps] sections (uid and import paths) and
	only gets its [params] replaced, so regenerating leaves a clean diff."""
	if kind == "wav":
		params = [
			"force/8_bit=false", "force/mono=false", "force/max_rate=false", "force/max_rate_hz=44100",
			"edit/trim=false", "edit/normalize=false",
			"edit/loop_mode=%d" % (2 if loop else 1), "edit/loop_begin=0", "edit/loop_end=-1",
			"compress/mode=2",
		]
		head = ["[remap]", "", 'importer="wav"', 'type="AudioStreamWAV"', ""]
	else:
		params = ["loop=%s" % ("true" if loop else "false"), "loop_offset=0", "bpm=0", "beat_count=0", "bar_beats=4"]
		head = ["[remap]", "", 'importer="oggvorbisstr"', 'type="AudioStreamOggVorbis"', ""]
	imp = path + ".import"
	if os.path.exists(imp):
		text = open(imp).read()
		if "[params]" in text:
			head = text[:text.index("[params]")].rstrip("\n").split("\n") + [""]
	with open(imp, "w") as f:
		f.write("\n".join(head + ["[params]", ""] + params) + "\n")


class Writer:
	def __init__(self, check_dir):
		self.rows = []
		self.check_dir = check_dir
		self.previews = {}

	def save(self, rel, x, loop, target_db, group=None, quality=5):
		path = os.path.join(OUT, rel)
		os.makedirs(os.path.dirname(path), exist_ok=True)
		x = level(x, loop, target_db, -1.0 if rel.endswith(".wav") else -1.5)
		if rel.endswith(".wav"):
			write_wav(path, x)
			write_import(path, "wav", loop)
		else:
			write_ogg(path, x, quality)
			write_import(path, "ogg", loop)
		mono = x.mean(axis=0) if x.ndim > 1 else x
		row = {
			"file": rel, "seconds": x.shape[-1] / SR, "bytes": os.path.getsize(path),
			"peak": db(np.max(np.abs(x))), "level": rms_db(mono) if loop else short_term_max_rms_db(mono),
			"seam": analyze.seam_click(x) if loop else None, "channels": 1 if x.ndim == 1 else x.shape[0],
		}
		self.rows.append(row)
		print("  %-34s %5.2fs %7.1f KB  peak %5.1f dBFS  %s %5.1f dB%s" % (
			rel, row["seconds"], row["bytes"] / 1024, row["peak"], "rms" if loop else "st ", row["level"],
			"  seam %.2f" % row["seam"] if loop else ""), flush=True)
		if self.check_dir and group:
			self.previews.setdefault(group, []).append((rel, np.tile(x, 2) if loop and x.shape[-1] < SR * 8 else x))
		return x

	def report(self):
		total = sum(r["bytes"] for r in self.rows)
		bad = [r for r in self.rows if r["peak"] > -0.99 or (r["seam"] is not None and r["seam"] > 2.0)]
		print("%d files, %.2f MB on disk" % (len(self.rows), total / 1048576))
		# QOA is 3.2 bits per sample per channel.
		est = sum(r["bytes"] if not r["file"].endswith(".wav") else r["seconds"] * SR * r["channels"] * 3.2 / 8 for r in self.rows)
		print("about %.2f MB once Godot has compressed the WAV loops to QOA" % (est / 1048576))
		for r in bad:
			print("WARNING: %s peak %.2f dBFS seam %s" % (r["file"], r["peak"], r["seam"]))
		if self.check_dir:
			os.makedirs(self.check_dir, exist_ok=True)
			for group, items in self.previews.items():
				analyze.save_spectrograms(os.path.join(self.check_dir, group + ".png"), items, width=600, height=100)
			print("spectrograms in", self.check_dir)
		return not bad


def build_engines(w):
	print("engines")
	for name, rpms in ENGINE_RPMS.items():
		for which in range(3):
			x, rpm = engines.engine_loop(name, which)
			assert abs(rpm - rpms[which]) < 0.01, (name, which, rpm)
			w.save("engine/%s_%s.wav" % (name, LEVEL_NAMES[which]), x, True, -16.0, "engines")


def build_sfx(w):
	print("loops")
	w.save("sfx/skid_loop.wav", sx.skid_loop(), True, -18.0, "loops")
	w.save("sfx/scrape_loop.wav", sx.scrape_loop(), True, -18.0, "loops")
	w.save("sfx/wind_loop.wav", sx.wind_loop(), True, -20.0, "loops")
	w.save("sfx/fire_loop.wav", sx.fire_loop(), True, -19.0, "loops")
	w.save("sfx/nitro_loop.wav", sx.nitro_loop(), True, -18.0, "loops")
	print("impacts")
	for i in range(3):
		w.save("sfx/bump_%d.ogg" % (i + 1), sx.bump(100 + i), False, -15.0, "impacts")
	for i, size in enumerate((1.0, 1.25, 0.85)):
		w.save("sfx/crunch_%d.ogg" % (i + 1), sx.crunch(200 + i, size), False, -10.0, "impacts")
	w.save("sfx/glass.ogg", sx.glass(), False, -14.0, "impacts")
	for i in range(2):
		w.save("sfx/land_%d.ogg" % (i + 1), sx.land(300 + i), False, -14.0, "impacts")
	print("events")
	w.save("sfx/explosion.ogg", sx.explosion(), False, -9.0, "events")
	w.save("sfx/splash.ogg", sx.splash(), False, -11.0, "events")
	w.save("sfx/fall_whoosh.ogg", sx.fall_whoosh(), False, -14.0, "events")
	w.save("sfx/nitro_burst.ogg", sx.nitro_burst(), False, -13.0, "events")
	w.save("sfx/hop.ogg", sx.hop(), False, -13.0, "events")
	w.save("sfx/horn.ogg", sx.horn(), False, -14.0, "events")
	build_pickups(w)
	print("ui")
	w.save("ui/click.ogg", sx.ui_click(), False, -18.0, "ui")
	w.save("ui/hover.ogg", sx.ui_hover(), False, -22.0, "ui")
	w.save("ui/beep.ogg", sx.beep(880.0), False, -15.0, "ui")
	w.save("ui/go.ogg", sx.go_horn(), False, -11.0, "ui")
	w.save("ui/sting_win.ogg", songs.sting_win(), False, -12.0, "ui")
	w.save("ui/sting_lose.ogg", songs.sting_lose(), False, -13.0, "ui")
	w.save("ui/sting_elimination.ogg", songs.sting_elimination(), False, -15.0, "ui")
	w.save("ui/sting_player_out.ogg", songs.sting_player_out(), False, -12.0, "ui")


def build_pickups(w):
	print("pickups and cash")
	w.save("sfx/pickup.ogg", sx.pickup_chime(), False, -13.0, "pickups", quality=3)
	w.save("sfx/shockwave.ogg", sx.shockwave(), False, -10.0, "pickups", quality=3)
	w.save("ui/cash.ogg", sx.cash_jingle(), False, -15.0, "pickups", quality=3)


def build_music(w):
	print("music (takes a minute)")
	w.save("music/round.ogg", songs.round_track(), True, -16.0, "music", quality=1)
	w.save("music/menu.ogg", songs.menu_track(), True, -17.0, "music", quality=1)


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--no-music", action="store_true")
	ap.add_argument("--check", metavar="DIR", help="write spectrogram PNGs here")
	ap.add_argument("--only", choices=["engines", "sfx", "pickups", "music"], help="build just this group")
	args = ap.parse_args()
	if not shutil.which("ffmpeg"):
		sys.exit("ffmpeg (with libvorbis) is needed to write the .ogg files")
	w = Writer(args.check)
	if args.only:
		{"engines": build_engines, "sfx": build_sfx, "pickups": build_pickups, "music": build_music}[args.only](w)
		sys.exit(0 if w.report() else 1)
	build_engines(w)
	build_sfx(w)
	if not args.no_music:
		build_music(w)
	ok = w.report()
	sys.exit(0 if ok else 1)


if __name__ == "__main__":
	main()
