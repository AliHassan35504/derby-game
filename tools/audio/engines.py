"""Engine loops.

Each loop is one or more whole engine cycles of exhaust pulses. Every
cylinder firing is an impulse placed at its exact (fractional) time in the
frequency domain, shaped by a blowdown pulse, then sent down its bank's
exhaust (a tube resonance, a muffler and a tailpipe) - all circular, so the
loop is seamless. Cycle-to-cycle variation in pulse strength and timing makes
it sound alive; the cross-plane V8 firing order split over two banks gives
the lumpy burble.
"""

import numpy as np

from dsp import (SR, TAU, bp, comb_resp, filt, hp, impulse_train_spectrum, lp,
	normalize_rms, peak, secs, smooth_random)

# Firing order 1-8-4-3-6-5-7-2 at 90 degree intervals; odd cylinders on the
# left bank. Positions are fractions of a 720 degree cycle.
_V8_BANKS = [0, 1, 1, 0, 1, 0, 0, 1]

CHARACTERS = {
	# Cross-plane V8 with a lumpy cam: van, muscle, pickup.
	"v8": {
		"fire": [(i / 8.0, _V8_BANKS[i]) for i in range(8)],
		"cyl_var": 0.12, "cycle_var": 0.10, "jitter": 0.004, "idle_lump": 0.18,
		"pipes": [(2.6, -0.62), (2.95, -0.6)], "muffler": 900.0, "boom": (75.0, 1.6, 7.0),
		"shell": (420.0, 2.5, 3.0), "blowdown": 0.00045, "broad": 0.035, "rasp": 0.25,
		"rasp_band": (900.0, 0.8), "drive": 1.8, "intake": 0.08, "sub": 0.35,
		"rpms": (1100.0, 3000.0, 5600.0),
	},
	# Big-block V8 with a roots supercharger: monster truck.
	"monster": {
		"fire": [(i / 8.0, _V8_BANKS[i]) for i in range(8)],
		"cyl_var": 0.15, "cycle_var": 0.12, "jitter": 0.005, "idle_lump": 0.25,
		"pipes": [(3.3, -0.66), (3.55, -0.64)], "muffler": 650.0, "boom": (55.0, 1.5, 9.0),
		"shell": (300.0, 2.0, 4.0), "blowdown": 0.0006, "broad": 0.04, "rasp": 0.3,
		"rasp_band": (700.0, 0.7), "drive": 2.4, "intake": 0.12, "sub": 0.5,
		"whine": (88, 0.035), "rpms": (900.0, 2600.0, 4800.0),
	},
	# Smooth, high-revving inline six: sports car and sedan.
	"six": {
		"fire": [(i / 6.0, 0) for i in range(6)],
		"cyl_var": 0.05, "cycle_var": 0.05, "jitter": 0.002, "idle_lump": 0.05,
		"pipes": [(1.9, -0.55)], "muffler": 1800.0, "boom": (110.0, 1.8, 4.0),
		"shell": (700.0, 2.5, 4.0), "blowdown": 0.0003, "broad": 0.03, "rasp": 0.3,
		"rasp_band": (1600.0, 0.9), "drive": 1.6, "intake": 0.18, "sub": 0.15,
		"rpms": (1500.0, 4600.0, 8200.0),
	},
	# Turbo flat four with unequal headers (a burbly rally boxer).
	"four": {
		"fire": [(0.0, 0), (0.25 + 0.022, 1), (0.5 - 0.012, 0), (0.75 + 0.016, 1)],
		"cyl_var": 0.08, "cycle_var": 0.07, "jitter": 0.003, "idle_lump": 0.08,
		"pipes": [(1.6, -0.6), (1.75, -0.6)], "muffler": 1500.0, "boom": (95.0, 1.8, 5.0),
		"shell": (600.0, 2.0, 5.0), "blowdown": 0.00035, "broad": 0.035, "rasp": 0.55,
		"rasp_band": (1900.0, 0.8), "drive": 2.2, "intake": 0.12, "sub": 0.2,
		"turbo": (5600.0, 0.012), "rpms": (1500.0, 4400.0, 7600.0),
	},
}

# Which engine each car style uses, and a pitch scale on top of it.
STYLE_ENGINE = {
	"van": ("v8", 0.92), "muscle": ("v8", 1.0), "pickup": ("v8", 0.86),
	"monster": ("monster", 1.0), "sports": ("six", 1.0), "sedan": ("six", 0.82),
	"rally": ("four", 1.0),
}

# Loop lengths for the low, mid and high loops.
LOOP_SECONDS = (2.0, 1.6, 1.25)


def engine_loop(name, which, seed=0):
	"""which: 0 = low, 1 = mid, 2 = high. Returns (signal, actual_rpm)."""
	ch = CHARACTERS[name]
	rng = np.random.default_rng(seed * 1000 + which * 17 + sum(map(ord, name)))
	target = ch["rpms"][which]
	n = secs(LOOP_SECONDS[which])
	length = n / SR
	cycles = max(1, int(round(target / 120.0 * length)))
	period = length / cycles
	rpm = 120.0 / period
	# 0 at idle, 1 near the redline.
	load = (which) / 2.0
	lump = ch["idle_lump"] * (1.0 - load) ** 2

	banks = sorted(set(b for _, b in ch["fire"]))
	cyl_amp = 1.0 + ch["cyl_var"] * rng.uniform(-1, 1, len(ch["fire"]))
	times = {b: [] for b in banks}
	amps = {b: [] for b in banks}
	all_times = []
	all_amps = []
	for c in range(cycles):
		cycle_gain = float(np.clip(1.0 + (ch["cycle_var"] + lump) * rng.standard_normal(), 0.72, 1.3))
		for i, (offset, bank) in enumerate(ch["fire"]):
			jit = rng.standard_normal() * (ch["jitter"] + lump * 0.03) * period
			t = ((c + offset) * period + jit) % length
			a = max(0.15, cyl_amp[i] * cycle_gain * (1.0 + 0.06 * rng.standard_normal()))
			times[bank].append(t)
			amps[bank].append(a)
			all_times.append(t)
			all_amps.append(a)

	freqs = np.fft.rfftfreq(n, 1.0 / SR)
	w = TAU * freqs
	# Blowdown: a sharp pressure front plus the broad gas pulse.
	tb = ch["blowdown"]
	tw = ch["broad"] * period
	sharp = 1.0 / (1.0 + 1j * w * tb) ** 2
	broad = 1.0 / (1.0 + 1j * w * tw) ** 2
	pulse = 0.55 * sharp + 1.0 * broad * (tw / tb) ** 0.0

	out_spec = np.zeros(len(freqs), dtype=np.complex128)
	for bank in banks:
		train, _ = impulse_train_spectrum(times[bank], amps[bank], n)
		length_m, fb = ch["pipes"][bank % len(ch["pipes"])]
		pipe = comb_resp(2.0 * length_m / 520.0, fb, damp_fc=2500.0)(freqs)
		out_spec += train * pulse * pipe
	muffler = lp(freqs, ch["muffler"], 1) * (0.35 + 0.65 * lp(freqs, ch["muffler"] * 2.5, 2))
	boom_f, boom_q, boom_db = ch["boom"]
	shell_f, shell_q, shell_db = ch["shell"]
	body = peak(freqs, boom_f, boom_q, boom_db) * peak(freqs, shell_f, shell_q, shell_db)
	# High rpm opens the exhaust up: brighter.
	bright = 1.0 + load * 1.5 * hp(freqs, 1500.0, 1)
	out_spec *= muffler * body * bright * hp(freqs, 28.0, 2)
	exhaust = np.fft.irfft(out_spec, n)
	exhaust = normalize_rms(exhaust, 1.0)

	# Flow/combustion noise, gated by the pulses.
	train_all, _ = impulse_train_spectrum(all_times, all_amps, n)
	gate = np.fft.irfft(train_all / (1.0 + 1j * w * (0.06 * period)) ** 2, n)
	gate = np.maximum(gate, 0.0)
	gate /= gate.max() + 1e-12
	rf, rq = ch["rasp_band"]
	hiss = filt(rng.standard_normal(n), lambda f: bp(f, rf * (1 + 0.4 * load), rq) * lp(f, 7000.0, 2), circular=True)
	rasp = normalize_rms(hiss * (0.25 + gate), 1.0)

	# Intake roar: low noise that swells with load.
	intake = normalize_rms(filt(rng.standard_normal(n), lambda f: bp(f, 250.0 + 300.0 * load, 0.7), circular=True) * (0.6 + gate), 1.0)

	# Sub: the firing fundamental itself (the "chest" thump).
	fire_hz = cycles * len(ch["fire"]) / length
	sub = np.zeros(n)
	tt = np.arange(n) / SR
	for k, a in ((1, 1.0), (2, 0.35)):
		f = fire_hz * k / 2.0
		cyc = int(round(f * length))
		sub += a * np.sin(TAU * cyc * tt / length)
	sub = normalize_rms(sub * (0.6 + 0.4 * gate), 1.0)

	x = exhaust + ch["rasp"] * (0.7 + 0.6 * load) * rasp + ch["intake"] * (0.5 + load) * intake + ch["sub"] * (1.0 - 0.6 * load) * sub

	if "whine" in ch:
		harm, amt = ch["whine"]
		f0 = harm * cycles / length
		wobble = smooth_random(n, rng, 3.0) * 0.002
		ph = np.cumsum(np.full(n, f0) * (1 + wobble)) / SR
		# Make the phase end on a whole cycle so the loop stays seamless.
		ph *= round(ph[-1] + f0 / SR) / (ph[-1] + f0 / SR)
		whine = np.sin(TAU * ph) + 0.4 * np.sin(TAU * 2 * ph) + 0.15 * np.sin(TAU * 3 * ph)
		x += amt * (0.4 + load) * np.sqrt(np.mean(x * x)) * whine / 0.75

	if "turbo" in ch and which > 0:
		f, amt = ch["turbo"]
		f = f * (0.8 + 0.2 * load)
		cyc = round(f * length)
		whistle = np.sin(TAU * cyc * tt / length) * (1 + 0.2 * smooth_random(n, rng, 4.0))
		spool = filt(rng.standard_normal(n), lambda fr: bp(fr, cyc / length, 12.0), circular=True)
		x += amt * load * np.sqrt(np.mean(x * x)) * (whistle + normalize_rms(spool, 0.7)) * 3.0

	# Grit: soft saturation (pointwise, so the loop stays periodic).
	x = normalize_rms(x, 0.28)
	x = np.tanh(ch["drive"] * (1 + 0.4 * load) * x) / ch["drive"]
	x = filt(x, lambda f: hp(f, 30.0, 2) * lp(f, 11000.0, 2), circular=True)
	return normalize_rms(x, 0.2), rpm
