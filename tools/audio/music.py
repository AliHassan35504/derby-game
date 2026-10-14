"""Procedural music: a driving rock/electronic track for the rounds, a
calmer synthwave track for menus, and the short stings.

Songs are rendered into a circular stereo buffer: notes that ring past the
end wrap round to the start, delays are circular and the reverb is a
circular convolution, so the track loops without a seam.
"""

import numpy as np

from dsp import (SR, TAU, bp, env_exp, filt, hp, lp, normalize_peak, peak, place,
	polyblep, room_ir, saw_from_phase, secs, soft_clip, square_from_phase)


def midi(m):
	return 440.0 * 2.0 ** ((m - 69) / 12.0)


# ----------------------------------------------------------------------------
# Drums


def kick(rng, punch=1.0, length_s=0.5, low=48.0, decay=0.2):
	n = secs(length_s)
	t = np.arange(n) / SR
	f = low + 120.0 * punch * np.exp(-t / 0.032)
	body = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / decay) * np.clip(t / 0.001, 0, 1)
	click = filt(rng.standard_normal(n) * env_exp(n, 0.003), lambda fr: hp(fr, 1800.0, 2) * lp(fr, 9000.0, 1))
	x = soft_clip(body * 1.3 + 0.35 * click / (np.max(np.abs(click)) + 1e-9), 1.6)
	return x * np.clip((length_s - t) / 0.03, 0, 1)


def snare(rng, length_s=0.45, tone=1.0):
	n = secs(length_s)
	t = np.arange(n) / SR
	body = (np.sin(TAU * 185.0 * t) + 0.6 * np.sin(TAU * 330.0 * t + 1.0)) * np.exp(-t / 0.07)
	wires = filt(rng.standard_normal(n), lambda f: bp(f, 4200.0, 0.5) + 0.5 * bp(f, 1800.0, 0.8)) * np.exp(-t / 0.15)
	wires /= np.max(np.abs(wires)) + 1e-9
	snap = filt(rng.standard_normal(n) * env_exp(n, 0.004), lambda f: hp(f, 1200.0, 2))
	snap /= np.max(np.abs(snap)) + 1e-9
	x = 0.7 * tone * body + 0.9 * wires + 0.5 * snap
	return soft_clip(x, 1.4) * np.clip((length_s - t) / 0.03, 0, 1)


def hat(rng, open_hat=False):
	n = secs(0.6 if open_hat else 0.12)
	t = np.arange(n) / SR
	metal = np.zeros(n)
	for f in (263.0, 400.0, 421.0, 474.0, 587.0, 845.0):
		metal += np.sign(np.sin(TAU * f * 2.1 * t + rng.uniform(0, TAU)))
	x = 0.6 * metal + 0.8 * rng.standard_normal(n)
	x = filt(x, lambda f: hp(f, 7000.0, 3) * lp(f, 15000.0, 1))
	x *= np.exp(-t / (0.16 if open_hat else 0.025)) * np.clip(t / 0.0005, 0, 1)
	return x / (np.max(np.abs(x)) + 1e-9)


def crash(rng, length_s=2.2):
	n = secs(length_s)
	t = np.arange(n) / SR
	metal = np.zeros(n)
	for _ in range(40):
		f = np.exp(rng.uniform(np.log(300), np.log(9000)))
		metal += np.sin(TAU * f * t + rng.uniform(0, TAU)) * np.exp(-t / rng.uniform(0.3, 1.4))
	x = 0.4 * metal / 6.0 + rng.standard_normal(n) * np.exp(-t / 0.7)
	x = filt(x, lambda f: hp(f, 2500.0, 2) * lp(f, 13000.0, 1))
	x *= np.clip(t / 0.002, 0, 1) * np.clip((length_s - t) / 0.2, 0, 1)
	return x / (np.max(np.abs(x)) + 1e-9)


def tom(rng, freq):
	n = secs(0.5)
	t = np.arange(n) / SR
	f = freq * (1 + 0.5 * np.exp(-t / 0.03))
	x = np.sin(TAU * np.cumsum(f) / SR) * np.exp(-t / 0.2)
	x += 0.2 * filt(rng.standard_normal(n) * env_exp(n, 0.02), lambda fr: bp(fr, 2000.0, 0.7))
	return soft_clip(x, 1.3)


# ----------------------------------------------------------------------------
# Pitched instruments


def _saw(freq, n, phase0=0.0, sr=SR):
	ph = phase0 + freq * np.arange(n) / sr
	return saw_from_phase(ph, freq / sr)


def bass_note(freq, dur, rng, bright=1.0, grit=1.0):
	"""Picked synth bass: saw plus sub, with a decaying filter."""
	n = secs(dur + 0.08)
	t = np.arange(n) / SR
	ph = freq * t
	x = 0.0 * t
	cutoff = 180.0 + 2200.0 * bright * np.exp(-t / 0.09)
	# Additive saw with a time-varying low-pass on each harmonic.
	for k in range(1, 60):
		fk = freq * k
		if fk > 9000:
			break
		a = (1.0 / k) / np.sqrt(1.0 + (fk / cutoff) ** 4)
		x += a * np.sin(TAU * k * ph)
	x += 0.5 * np.sin(TAU * 0.5 * ph) if freq > 70 else 0.3 * np.sin(TAU * ph)
	env = np.clip(t / 0.003, 0, 1) * np.where(t < dur, 0.75 + 0.25 * np.exp(-t / 0.15), np.exp(-(t - dur) / 0.02) * (0.75 + 0.25 * np.exp(-dur / 0.15)))
	x = soft_clip(x * env * 1.2 * grit, 1.0 + grit)
	return x


def _decimate2(x):
	"""Halve the sample rate with an FFT brickwall."""
	n = len(x)
	spec = np.fft.rfft(x)
	keep = n // 4
	spec = spec[:keep + 1]
	spec[-int(keep * 0.08):] *= np.linspace(1, 0, int(keep * 0.08))
	return np.fft.irfft(spec, n // 2) * 0.5


def guitar_chord(root_hz, dur, rng, muted=False, voicing=(0, 7, 12), drive=9.0):
	"""A distorted power chord, rendered at twice the rate to keep the
	distortion's harmonics from aliasing, then through a speaker cabinet."""
	sr2 = SR * 2
	ring = 0.06 if muted else 0.25
	n = int((dur + ring) * sr2)
	n += n % 2
	t = np.arange(n) / sr2
	x = np.zeros(n)
	for semi in voicing:
		f = root_hz * 2.0 ** (semi / 12.0)
		for det in (-0.0035, 0.0035):
			fr = f * (1 + det + rng.uniform(-0.001, 0.001))
			ph = rng.uniform() + fr * t
			# Pick attack: slight sharp pitch at the start.
			ph += 0.004 * fr * 0.01 * np.exp(-t / 0.02)
			x += saw_from_phase(ph, fr / sr2)
	if muted:
		env = np.exp(-t / 0.07) * np.clip(t / 0.002, 0, 1)
	else:
		env = (0.6 + 0.4 * np.exp(-t / 0.3)) * np.exp(-t / 3.0) * np.clip(t / 0.003, 0, 1)
	env *= np.clip((dur + ring - t) / ring, 0, 1)
	x *= env
	# Pre-emphasis then a hard-ish clip.
	spec = np.fft.rfft(x)
	fr = np.fft.rfftfreq(n, 1.0 / sr2)
	spec *= hp(fr, 250.0 if muted else 180.0, 1) * lp(fr, 5000.0, 1)
	x = np.fft.irfft(spec, n)
	x = np.tanh(drive * x / (np.max(np.abs(x)) + 1e-9))
	x = _decimate2(x)
	# Cabinet: a 4x12 is dark above 5 kHz with a presence bump.
	x = filt(x, lambda f: hp(f, 85.0, 2) * lp(f, 4800.0, 4) * peak(f, 2100.0, 1.4, 4.0) * peak(f, 120.0, 1.0, 3.0 if muted else 0.0) * peak(f, 700.0, 1.0, -3.0), pad=secs(0.05))
	return x * np.max(env)


def lead_note(freq, dur, rng, kind="saw", glide_from=None, vibrato=0.006, bright=1.0):
	n = secs(dur + 0.25)
	t = np.arange(n) / SR
	f = np.full(n, freq)
	if glide_from:
		f = freq + (glide_from - freq) * np.exp(-t / 0.035)
	vib = vibrato * np.sin(TAU * 5.5 * t) * np.clip((t - 0.18) / 0.25, 0, 1)
	f = f * (1 + vib)
	ph = np.cumsum(f) / SR
	dt = f / SR
	if kind == "square":
		x = square_from_phase(ph, dt, 0.5) * 0.6 + saw_from_phase(ph * 1.003, dt) * 0.4
	else:
		x = saw_from_phase(ph, dt) * 0.5 + saw_from_phase(ph * 1.006 + 0.3, dt) * 0.5
	x += 0.3 * np.sin(TAU * ph * 0.5)
	gate = np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.06))
	env = np.clip(t / 0.008, 0, 1) * (0.8 + 0.2 * np.exp(-t / 0.2)) * gate
	x *= env
	# A fixed low-pass that opens a little at the attack.
	x = filt(x, lambda fr: lp(fr, 3200.0 * bright, 2) * hp(fr, 150.0, 1), pad=secs(0.05))
	return x


def pluck(freq, rng, length_s=0.5, bright=1.0):
	n = secs(length_s)
	t = np.arange(n) / SR
	ph = freq * t
	cutoff = 300.0 + 4500.0 * bright * np.exp(-t / 0.06)
	x = np.zeros(n)
	for k in range(1, 40):
		fk = freq * k
		if fk > 12000:
			break
		x += ((1.0 / k) if k % 2 else 0.6 / k) / np.sqrt(1.0 + (fk / cutoff) ** 4) * np.sin(TAU * k * ph)
	return x * np.exp(-t / 0.18) * np.clip(t / 0.002, 0, 1) * np.clip((length_s - t) / 0.05, 0, 1)


def pad_chord(freqs, dur, rng, attack=0.5, release=0.8, cutoff=2200.0):
	"""Detuned saws per note, stereo."""
	n = secs(dur + release)
	t = np.arange(n) / SR
	out = np.zeros((2, n))
	for f in freqs:
		for v in range(5):
			det = (v - 2) * 0.004 + rng.uniform(-0.001, 0.001)
			fr = f * (1 + det)
			x = saw_from_phase(rng.uniform() + fr * t, fr / SR)
			pan = (v - 2) / 2.0 * 0.8
			out[0] += x * np.sqrt((1 - pan) / 2)
			out[1] += x * np.sqrt((1 + pan) / 2)
	env = np.clip(t / attack, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / (release / 3)))
	out *= env
	for c in range(2):
		out[c] = filt(out[c], lambda fr: lp(fr, cutoff, 2) * hp(fr, 120.0, 1), pad=secs(0.1))
	return out / (len(freqs) * 5)


def brass_stab(freqs, dur, rng):
	n = secs(dur + 0.3)
	t = np.arange(n) / SR
	x = np.zeros(n)
	cutoff = 500.0 + 3500.0 * (1 - np.exp(-t / 0.04)) * np.exp(-t / 0.6) + 700.0
	for f in freqs:
		for det in (-0.005, 0.0, 0.005):
			fr = f * (1 + det)
			ph = rng.uniform() + fr * t
			for k in range(1, 50):
				if fr * k > 10000:
					break
				x += (1.0 / k) / np.sqrt(1 + (fr * k / cutoff) ** 4) * np.sin(TAU * k * ph)
	env = np.clip(t / 0.02, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.08))
	return soft_clip(x * env / len(freqs) / 2.0, 1.5)


# ----------------------------------------------------------------------------
# Mixing helpers


class Song:
	def __init__(self, bpm, bars, beats_per_bar=4, loop=True):
		self.loop = loop
		self.bpm = bpm
		self.beat = 60.0 / bpm
		self.bar = self.beat * beats_per_bar
		self.bars = bars
		self.n = int(round(self.bar * bars * SR))
		self.buses = {}

	def bus(self, name):
		if name not in self.buses:
			self.buses[name] = np.zeros((2, self.n))
		return self.buses[name]

	def step_time(self, bar, step, steps_per_bar=16):
		return (bar + step / steps_per_bar) * self.bar

	def add(self, bus, sig, at_s, gain=1.0, pan=0.0):
		b = self.bus(bus)
		start = int(round(at_s * SR))
		if sig.ndim == 1:
			lg = np.sqrt((1 - pan) / 2) * np.sqrt(2)
			rg = np.sqrt((1 + pan) / 2) * np.sqrt(2)
			place(b[0], sig, start, gain * lg, wrap=self.loop)
			place(b[1], sig, start, gain * rg, wrap=self.loop)
		else:
			place(b[0], sig[0], start, gain, wrap=self.loop)
			place(b[1], sig[1], start, gain, wrap=self.loop)


def circ_delay(x, delay_s, feedback, taps=6, pingpong=True, damp=4000.0):
	"""Circular feedback delay on a stereo buffer (wet only), computed in the
	frequency domain. Ping-pong sends odd repeats to the other side."""
	n = x.shape[1]
	freqs = np.fft.rfftfreq(n, 1.0 / SR)
	d = delay_s
	loss = feedback * lp(freqs, damp, 1)
	same = np.zeros(len(freqs), dtype=np.complex128)
	cross = np.zeros(len(freqs), dtype=np.complex128)
	for i in range(1, taps + 1):
		h = loss ** i * np.exp(-1j * TAU * freqs * d * i)
		if pingpong and i % 2 == 1:
			cross += h
		else:
			same += h
	sl = np.fft.rfft(x[0])
	sr = np.fft.rfft(x[1])
	return np.stack([np.fft.irfft(sl * same + sr * cross, n), np.fft.irfft(sr * same + sl * cross, n)])


def circ_reverb(x, rng, decay_s=1.6, length_s=3.0, bright=6000.0):
	ir = room_ir(length_s, decay_s, rng, bright=bright, predelay_s=0.02, early=12, stereo=True)
	n = x.shape[1]
	out = np.zeros_like(x)
	src = x.mean(axis=0)
	spec = np.fft.rfft(src)
	for c in range(2):
		irp = np.zeros(n)
		irp[:len(ir[c])] = ir[c][:n]
		out[c] = np.fft.irfft(spec * np.fft.rfft(irp), n)
	return out


def duck_envelope(n, times_s, depth=0.5, release_s=0.18):
	"""Circular sidechain gain from kick times."""
	g = np.zeros(n)
	m = secs(release_s * 4)
	shape = 1.0 - np.exp(-np.arange(m) / (release_s * SR))
	shape = 1.0 - shape  # 1 at the hit, decaying to 0
	for t in times_s:
		place(g, shape, int(round(t * SR)), 1.0, wrap=True)
	g = np.clip(g, 0, 1)
	return 1.0 - depth * g


def master(mix, peak_db=-1.5, drive=1.3):
	"""Glue: gentle saturation-style limiting and a peak normalise."""
	mix = np.stack([filt(c, lambda f: hp(f, 28.0, 2), circular=True) for c in mix])
	p = np.max(np.abs(mix))
	mix = mix / p
	mix = np.tanh(drive * mix) / np.tanh(drive)
	return normalize_peak(mix, peak_db)


# ----------------------------------------------------------------------------
# Composition helpers

MINOR = [0, 2, 3, 5, 7, 8, 10]


def scale_notes(root_midi, scale, lo, hi):
	notes = []
	for octave in range(-2, 6):
		for s in scale:
			m = root_midi + 12 * octave + s
			if lo <= m <= hi:
				notes.append(m)
	return sorted(notes)


def chord_tones(root_midi, quality):
	third = 3 if quality == "m" else 4
	return [root_midi % 12, (root_midi + third) % 12, (root_midi + 7) % 12]


def make_melody(rng, chords, rhythm_a, rhythm_b, key_root, scale, lo, hi, start=None):
	"""chords: list of (root_midi, quality) per bar. Rhythms: lists of
	(step, length_steps) per bar. Strong steps land on chord tones, weak
	ones move by step. Returns list of (bar, step, length, midi)."""
	pool = scale_notes(key_root, scale, lo, hi)
	cur = start if start is not None else pool[len(pool) // 2]
	notes = []
	for bar, (root, quality) in enumerate(chords):
		rhythm = rhythm_a if bar % 2 == 0 else rhythm_b
		tones = chord_tones(root, quality)
		for i, (step, length) in enumerate(rhythm):
			strong = step % 4 == 0
			if strong:
				cands = [m for m in pool if m % 12 in tones]
				cands.sort(key=lambda m: abs(m - cur) + rng.uniform(0, 2.5))
				cur = cands[0]
			else:
				idx = pool.index(min(pool, key=lambda m: abs(m - cur)))
				move = rng.choice([-2, -1, -1, 1, 1, 2])
				idx = int(np.clip(idx + move, 0, len(pool) - 1))
				cur = pool[idx]
			notes.append((bar, step, length, cur))
	return notes


def make_phrase_melody(rng, chords, rhythm_a, rhythm_b, key_root, scale, lo, hi, start):
	"""A melody built from one two-bar motif, restated over each pair of
	chords: the contour (in scale steps) is kept, strong beats snap to the
	chord, and the last phrase resolves to a long chord tone. Returns
	(bar, step, length, midi) like make_melody."""
	pool = scale_notes(key_root, scale, lo, hi)

	def degree(m):
		return pool.index(min(pool, key=lambda p: abs(p - m)))

	# The motif: scale-step offsets from the phrase's first note.
	contour = []
	pos = 0
	for bar_rhythm in (rhythm_a, rhythm_b):
		for i, _ in enumerate(bar_rhythm):
			contour.append(pos)
			pos += int(rng.choice([-2, -1, -1, 1, 1, 2, 3]))
			pos = int(np.clip(pos, -4, 5))
	# Phrase starting points walk up, then home.
	anchors = [0, 2, 1, 0]
	notes = []
	base = degree(start)
	for phrase in range(0, len(chords), 2):
		p = phrase // 2
		k = 0
		for half, bar_rhythm in enumerate((rhythm_a, rhythm_b)):
			bar = phrase + half
			if bar >= len(chords):
				break
			root, quality = chords[bar]
			tones = chord_tones(root, quality)
			for i, (step, length) in enumerate(bar_rhythm):
				d = int(np.clip(base + anchors[p % 4] + contour[k], 0, len(pool) - 1))
				m = pool[d]
				if step % 8 == 0:
					cands = [pool[j] for j in range(max(0, d - 2), min(len(pool), d + 3)) if pool[j] % 12 in tones]
					if cands:
						m = min(cands, key=lambda c: abs(c - pool[d]))
				last_note = bar == len(chords) - 1 and i == len(bar_rhythm) - 1
				if last_note:
					cands = [x for x in pool if x % 12 == root % 12]
					m = min(cands, key=lambda c: abs(c - m))
				notes.append((bar, step, length, m))
				k += 1
	return notes
