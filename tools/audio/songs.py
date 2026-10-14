"""The two music tracks and the stings, composed from patterns with a seeded
random melody writer so they come out the same every run."""

import numpy as np

import music as mu
from dsp import SR, filt, hp, lp, normalize_peak, peak, room_ir, secs, trim_tail

E, F, G, A, B, C, D = 40, 41, 43, 45, 35, 36, 38

# The last render's stems (for checking the balance).
STEMS = {}


def _active_rms_db(x, win_s=0.5):
	"""RMS over the parts of a stem that are playing (within 25 dB of its
	loudest half second), so a lead that only plays half the song isn't
	judged by its silences."""
	m = x.mean(axis=0) if x.ndim > 1 else x
	w = secs(win_s)
	frames = m[:len(m) // w * w].reshape(-1, w)
	levels = np.sqrt(np.mean(frames ** 2, axis=1)) + 1e-12
	active = levels[levels > levels.max() * 10 ** (-25 / 20)]
	return 20 * np.log10(np.sqrt(np.mean(active ** 2)))


def _balance(stems, targets_db):
	"""Scale each stem so its active RMS sits at its target relative level."""
	mix = 0.0
	for name, x in stems.items():
		gain = 10 ** ((targets_db[name] - 20.0 - _active_rms_db(x)) / 20)
		mix = mix + x * gain
	return mix


def _pattern(s):
	"""'x' = full hit, 'o' = soft hit, anything else = nothing."""
	return [(i, 1.0 if ch == "x" else 0.55) for i, ch in enumerate(s) if ch in "xo"]


def _riff(s):
	"""Guitar riff: 'O' open chord (held through '-'), 'M' palm mute."""
	events = []
	i = 0
	while i < len(s):
		ch = s[i]
		if ch in "OM":
			j = i + 1
			while ch == "O" and j < len(s) and s[j] == "-":
				j += 1
			events.append((i, (j - i) if ch == "O" else 1, ch == "M"))
		i += 1
	return events


# ----------------------------------------------------------------------------
# In-round track: 140 bpm, E minor, guitars, synth lead and arps.


def round_track(seed=7):
	rng = np.random.default_rng(seed)
	s = mu.Song(140, 52)
	q = {E: "m", C: "M", D: "M", G: "M", B: "M"}
	sections = (
		[("intro", [E, E, E, E])]
		+ [("verse", [E, E, C, D, E, E, G, D])]
		+ [("verse_lead", [E, E, C, D, E, E, G, D])]
		+ [("chorus", [C, D, E, E, C, D, B, B])]
		+ [("break", [C, C, D, D])]
		+ [("verse_lead", [E, E, C, D, E, E, G, D])]
		+ [("chorus", [C, D, E, E, C, D, B, B])]
		+ [("outro", [E, E, C, D])]
	)
	bars = []
	for name, chords in sections:
		for i, ch in enumerate(chords):
			bars.append((name, ch, i, len(chords)))

	kicks = [mu.kick(rng, 1.0) for _ in range(3)]
	snares = [mu.snare(rng) for _ in range(3)]
	hats = [mu.hat(rng) for _ in range(4)]
	ohat = mu.hat(rng, True)
	crash = mu.crash(rng)
	toms = [mu.tom(rng, f) for f in (190.0, 140.0, 100.0)]

	verse_mel = mu.make_phrase_melody(rng, [(c + 24, q[c]) for c in [E, E, C, D, E, E, G, D]],
		[(0, 3), (3, 3), (6, 2), (8, 4), (12, 2), (14, 2)], [(0, 2), (2, 2), (4, 4), (8, 6), (14, 2)],
		64, mu.MINOR, 62, 76, start=71)
	chorus_mel = mu.make_phrase_melody(rng, [(c + 36 if c < 40 else c + 24, q[c]) for c in [C, D, E, E, C, D, B, B]],
		[(0, 4), (4, 2), (6, 2), (8, 6), (14, 2)], [(0, 6), (6, 2), (8, 8)],
		64, mu.MINOR, 67, 81, start=76)

	drum_pats = {
		"intro": ("x.......x.......", "................", "x.o.x.o.x.o.x.o."),
		"verse": ("x.....x.x.x.....", "....x.......x...", "x.o.x.o.x.o.x.o."),
		"verse_lead": ("x.....x.x.x.....", "....x.......x...", "x.o.x.o.x.o.x.o."),
		"chorus": ("x.x...x.x.x...x.", "....x.......x..o", "x...x...x...x..."),
		"break": ("x.........x.....", "........x.......", "x...o...x...o..."),
		"outro": ("x.....x.x.x.....", "....x.......x...", "x.o.x.o.x.o.x.o."),
	}
	riffs = {
		"intro": "M.M.M.M.M.M.MMMM",
		"verse": "O--MM.M.O--M.MMM",
		"verse_lead": "O--MM.M.O--M.MMM",
		"chorus": "O-------O-----MM",
		"break": "M.......M.......",
		"outro": "O--MM.M.O--M.MMM",
	}
	step = s.bar / 16.0
	lead_i = {"verse_lead": 0, "chorus": 0}
	section_bar = 0
	prev_name = None
	for bar, (name, root, i, count) in enumerate(bars):
		if name != prev_name:
			section_bar = 0
			prev_name = name
		kp, sp, hp_ = drum_pats[name]
		last = i == count - 1
		# Drums.
		for st, v in _pattern(kp):
			s.add("drums", kicks[rng.integers(3)], s.step_time(bar, st), 1.0 * v)
		if last and name in ("intro", "break", "outro"):
			# A fill into the next section.
			sp = sp[:8] + ("o.x.xoxo" if name != "outro" else "........")
			for st, v in _pattern(sp):
				s.add("drums", snares[rng.integers(3)], s.step_time(bar, st), 0.75 * v * (0.6 + 0.05 * st))
			if name == "outro":
				for k, st in enumerate((8, 10, 12, 13, 14, 15)):
					s.add("drums", toms[min(k // 2, 2)], s.step_time(bar, st), 0.8, pan=0.5 - 0.2 * k)
		else:
			for st, v in _pattern(sp):
				s.add("drums", snares[rng.integers(3)], s.step_time(bar, st), 0.8 * v)
		for st, v in _pattern(hp_):
			if name == "chorus":
				s.add("drums", ohat, s.step_time(bar, st + 2), 0.18, pan=0.3)
			s.add("drums", hats[rng.integers(4)], s.step_time(bar, st), 0.22 * v, pan=0.3)
		if name == "chorus" and i % 4 == 0 or (name in ("verse", "verse_lead") and i == 0):
			s.add("drums", crash, s.step_time(bar, 0), 0.4, pan=-0.4)

		# Guitars (double-tracked hard left and right).
		if name != "intro" or i >= 2:
			for st, length, muted in _riff(riffs[name]):
				dur = length * step * (0.9 if muted else 0.97)
				for side in (-0.85, 0.85):
					g = mu.guitar_chord(mu.midi(root), dur, rng, muted=muted)
					s.add("guitar", g, s.step_time(bar, st) + rng.uniform(0, 0.006), 0.32 if muted else 0.36, pan=side)

		# Bass.
		bpat = {"chorus": "x.x.x.x.x.x.x.x.", "break": "x.......x......."}.get(name, "x.x.x.xox.x.x.xo")
		for st, v in _pattern(bpat):
			octave = 12 if (v < 1.0 and name not in ("intro",)) else 0
			length = 7.6 if name == "break" else 1.8
			s.add("bass", mu.bass_note(mu.midi(root + octave), length * step, rng, bright=0.8 if v == 1.0 else 0.6), s.step_time(bar, st), 0.5)

		# Synth arp: chord tones in sixteenths.
		if name in ("verse", "verse_lead", "chorus", "break"):
			tones = [root + 24, root + 24 + (3 if q[root] == "m" else 4), root + 31, root + 36]
			order = [0, 1, 2, 3, 2, 1, 2, 3]
			bright = 0.5 + 0.5 * (i / max(count - 1, 1)) if name == "break" else 0.6
			gain = 0.16 if name == "break" else 0.09
			for st in range(16):
				m = tones[order[st % 8]]
				s.add("arp", mu.pluck(mu.midi(m), rng, 0.3, bright), s.step_time(bar, st), gain, pan=-0.5 if st % 2 else 0.5)

		# Lead.
		if name in ("verse_lead", "chorus"):
			mel = verse_mel if name == "verse_lead" else chorus_mel
			prev = None
			for (mb, st, length, m) in mel:
				if mb != i:
					continue
				note = mu.lead_note(mu.midi(m), length * step * 0.92, rng, glide_from=mu.midi(prev) if prev and abs(prev - m) <= 3 else None)
				s.add("lead", note, s.step_time(bar, st), 0.28)
				prev = m
		section_bar += 1

	drums = s.bus("drums")
	guitar = s.bus("guitar")
	bass = s.bus("bass")
	arp = s.bus("arp")
	lead = s.bus("lead")
	bass = np.stack([filt(c, lambda f: lp(f, 3000.0, 2) * hp(f, 35.0, 2), circular=True) for c in bass])
	guitar = np.stack([filt(c, lambda f: hp(f, 90.0, 2) * peak(f, 300.0, 1.0, -2.0), circular=True) for c in guitar])
	lead_fx = mu.circ_delay(lead, s.beat * 0.75, 0.35, taps=5, damp=3000.0)
	arp_fx = mu.circ_delay(arp, s.beat * 0.5, 0.3, taps=4, damp=2500.0)
	verb_in = 0.35 * drums + 0.5 * lead + 0.6 * arp + 0.1 * guitar
	verb = mu.circ_reverb(verb_in, rng, decay_s=1.2, length_s=2.5, bright=5000.0)
	stems = {"drums": drums, "guitar": guitar, "bass": bass, "arp": arp + 0.4 * arp_fx, "lead": lead + 0.35 * lead_fx, "verb": verb}
	mix = _balance(stems, {"drums": 0.0, "guitar": -1.0, "bass": -4.5, "arp": -11.0, "lead": -4.0, "verb": -13.0})
	STEMS["round"] = stems
	return mu.master(mix, -1.5, 1.2)


# ----------------------------------------------------------------------------
# Menu track: 96 bpm, A minor synthwave.


def menu_track(seed=11):
	rng = np.random.default_rng(seed)
	Am, Fm, Cm, Gm, Dm, Em = (45, "m"), (41, "M"), (48, "M"), (43, "M"), (50, "m"), (40, "M")
	sections = [
		("intro", [Am, Fm, Cm, Gm]),
		("a", [Am, Fm, Cm, Gm, Am, Fm, Cm, Gm]),
		("b", [Fm, Gm, Am, Am, Fm, Gm, Cm, Em]),
		("c", [Dm, Am, Fm, Gm, Dm, Am, Fm, Em]),
		("a2", [Am, Fm, Cm, Gm, Am, Fm, Cm, Gm]),
		("outro", [Am, Fm, Cm, Gm]),
	]
	bars = []
	for name, chords in sections:
		for i, ch in enumerate(chords):
			bars.append((name, ch, i, len(chords)))
	s = mu.Song(96, len(bars))
	step = s.bar / 16.0

	kick = mu.kick(rng, 0.7, 0.6, 44.0, 0.3)
	snares = [mu.snare(rng, 0.6, 0.6) for _ in range(2)]
	hats = [mu.hat(rng) for _ in range(3)]
	crash = mu.crash(rng, 3.0)

	lead_b = mu.make_phrase_melody(rng, [(r + 24, qq) for r, qq in sections[2][1]],
		[(0, 6), (6, 2), (8, 8)], [(0, 4), (4, 4), (8, 4), (12, 4)], 57, mu.MINOR, 69, 81, start=76)
	lead_c = mu.make_phrase_melody(rng, [(r + 24, qq) for r, qq in sections[3][1]],
		[(0, 8), (8, 4), (12, 4)], [(0, 12), (12, 4)], 57, mu.MINOR, 64, 79, start=72)
	lead_a2 = mu.make_phrase_melody(rng, [(r + 24, qq) for r, qq in sections[4][1]],
		[(0, 3), (3, 3), (6, 2), (8, 6), (14, 2)], [(0, 6), (6, 2), (8, 8)], 57, mu.MINOR, 69, 84, start=76)

	kick_times = []
	for bar, (name, (root, qual), i, count) in enumerate(bars):
		third = 3 if qual == "m" else 4
		pitch_classes = [root % 12, (root + third) % 12, (root + 7) % 12]
		voicing = sorted(m for m in range(55, 70) if m % 12 in pitch_classes)[:3]
		drums_on = name in ("a", "b", "a2")
		# Pad.
		s.add("pad", mu.pad_chord([mu.midi(m) for m in voicing] + [mu.midi(root)], s.bar * 0.98, rng,
			attack=0.6 if name in ("intro", "c") else 0.25, release=1.2, cutoff=1600.0 if name == "intro" else 2400.0), s.step_time(bar, 0), 0.9)
		# Arp.
		if name != "c" or i >= 4:
			tones = [voicing[0] + 12, voicing[1] + 12, voicing[2] + 12, voicing[0] + 24]
			order = [0, 1, 2, 3, 2, 1, 0, 1]
			bright = 0.35 + 0.4 * (bar % 8) / 7.0
			for st in range(16):
				s.add("arp", mu.pluck(mu.midi(tones[order[st % 8]]), rng, 0.35, bright), s.step_time(bar, st), 0.11, pan=-0.4 if st % 2 else 0.4)
		# Bass.
		if name != "intro" or i >= 2:
			bpat = "x.x.x.x.x.x.x.x." if drums_on else "x.......x......."
			for st, v in _pattern(bpat):
				s.add("bass", mu.bass_note(mu.midi(root - 12 if root >= 45 else root), step * (1.7 if drums_on else 7.5), rng, bright=0.45, grit=0.4), s.step_time(bar, st), 0.55)
		# Drums.
		if drums_on:
			for st in (0, 8):
				s.add("drums", kick, s.step_time(bar, st), 0.9)
				kick_times.append(s.step_time(bar, st))
			if i % 2 == 1:
				s.add("drums", kick, s.step_time(bar, 14), 0.5)
				kick_times.append(s.step_time(bar, 14))
			for st in (4, 12):
				s.add("drums", snares[rng.integers(2)], s.step_time(bar, st), 0.55)
			for st in range(0, 16, 2):
				s.add("drums", hats[rng.integers(3)], s.step_time(bar, st + 1), 0.12, pan=0.25)
			if i == 0:
				s.add("drums", crash, s.step_time(bar, 0), 0.25, pan=-0.3)
		elif name == "c":
			for st in range(0, 16, 2):
				s.add("drums", hats[rng.integers(3)], s.step_time(bar, st + 1), 0.08, pan=0.25)
		# Lead.
		mel = {"b": lead_b, "c": lead_c, "a2": lead_a2}.get(name)
		if mel:
			for (mb, st, length, m) in mel:
				if mb == i:
					s.add("lead", mu.lead_note(mu.midi(m), length * step * 0.95, rng, kind="square", vibrato=0.008, bright=0.7), s.step_time(bar, st), 0.2)

	n = s.n
	duck = mu.duck_envelope(n, kick_times, depth=0.45, release_s=0.16)
	pad = s.bus("pad") * duck
	arp = s.bus("arp")
	lead = s.bus("lead")
	drums = s.bus("drums")
	bass = s.bus("bass") * (0.6 + 0.4 * duck)
	bass = np.stack([filt(c, lambda f: lp(f, 1800.0, 2) * hp(f, 35.0, 2), circular=True) for c in bass])
	arp_fx = mu.circ_delay(arp, s.beat * 0.75, 0.45, taps=6, damp=2200.0)
	lead_fx = mu.circ_delay(lead, s.beat * 0.75, 0.4, taps=6, damp=2500.0)
	verb = mu.circ_reverb(0.5 * pad + 0.8 * arp + 0.8 * lead + 0.4 * drums, rng, decay_s=2.4, length_s=5.0, bright=4500.0)
	stems = {"pad": pad, "arp": arp + 0.5 * arp_fx, "lead": lead + 0.4 * lead_fx, "drums": drums, "bass": bass, "verb": verb}
	mix = _balance(stems, {"pad": -2.0, "arp": -6.0, "lead": -3.5, "drums": 0.0, "bass": -3.0, "verb": -9.0})
	STEMS["menu"] = stems
	return mu.master(mix, -1.5, 1.2)


# ----------------------------------------------------------------------------
# Stings (stereo one-shots)


def _finish_sting(s, rng, verb_amt=0.3, decay=1.4):
	mix = sum(s.buses.values())
	verb = np.zeros_like(mix)
	ir = room_ir(decay * 2.0, decay, rng, bright=5000.0, predelay_s=0.02, stereo=True)
	src = mix.mean(axis=0)
	for c in range(2):
		y = np.convolve(src, ir[c])[:mix.shape[1]] if len(src) < 20000 else _fftconv(src, ir[c])[:mix.shape[1]]
		verb[c] = y
	out = mix + verb_amt * verb / (np.max(np.abs(verb)) + 1e-9) * np.max(np.abs(mix))
	out = normalize_peak(np.tanh(1.2 * out / np.max(np.abs(out))), -1.0)
	end = out.shape[1]
	energy = np.max(np.abs(out), axis=0)
	idx = np.nonzero(energy > 10 ** (-60 / 20))[0]
	end = min(end, idx[-1] + secs(0.02))
	out = out[:, :end]
	f = secs(0.1)
	out[:, -f:] *= np.linspace(1, 0, f) ** 2
	return out


def _fftconv(a, b):
	n = len(a) + len(b) - 1
	size = 1 << (n - 1).bit_length()
	return np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)[:n]


def sting_win(seed=3):
	rng = np.random.default_rng(seed)
	s = mu.Song(140, 3, loop=False)
	hits = [(0.0, C, 0.2), (0.43, D, 0.2), (0.86, E, 2.2)]
	for at, root, dur in hits:
		for side in (-0.8, 0.8):
			s.add("gtr", mu.guitar_chord(mu.midi(root), dur, rng), at, 0.4, pan=side)
		major = [root + 24, root + 28, root + 31, root + 36]
		s.add("brass", mu.brass_stab([mu.midi(m) for m in major], dur, rng), at, 0.5)
		s.add("drums", mu.kick(rng), at, 1.0)
		s.add("drums", mu.snare(rng), at, 0.6)
	s.add("drums", mu.crash(rng, 2.5), 0.86, 0.6)
	# A rising fanfare on top.
	for k, m in enumerate((64, 68, 71, 76)):
		s.add("lead", mu.lead_note(mu.midi(m + 12), 0.12 if k < 3 else 1.6, rng, vibrato=0.01), 0.86 + 0.11 * k, 0.25)
	for k, st in enumerate((0, 1, 2, 3)):
		s.add("drums", mu.snare(rng), 0.43 + 0.43 / 4 * st, 0.35 + 0.1 * k)
	return _finish_sting(s, rng, 0.35)


def sting_lose(seed=4):
	rng = np.random.default_rng(seed)
	s = mu.Song(100, 2, loop=False)
	for k, m in enumerate((55, 54, 53)):
		s.add("brass", mu.brass_stab([mu.midi(m), mu.midi(m - 12)], 0.32, rng), 0.42 * k, 0.6)
	last = mu.lead_note(mu.midi(52), 1.4, rng, vibrato=0.02, bright=0.5)
	s.add("brass", mu.brass_stab([mu.midi(52), mu.midi(40)], 1.4, rng), 1.26, 0.6)
	s.add("lead", last, 1.26, 0.25)
	s.add("drums", mu.kick(rng, 0.6), 1.26, 0.7)
	s.add("drums", mu.tom(rng, 90.0), 1.26, 0.5)
	return _finish_sting(s, rng, 0.35)


def _zap(rng, start_hz, end_hz, dur):
	n = secs(dur)
	t = np.arange(n) / SR
	f = end_hz + (start_hz - end_hz) * np.exp(-t / (dur * 0.35))
	ph = np.cumsum(f) / SR
	x = mu.saw_from_phase(ph, f / SR) * 0.6 + mu.square_from_phase(ph * 0.5, f / SR / 2) * 0.4
	x = filt(x, lambda fr: lp(fr, 4000.0, 2) * hp(fr, 80.0, 1))
	return x * np.exp(-t / (dur * 0.5)) * np.clip(t / 0.003, 0, 1)


def sting_elimination(seed=5):
	"""Short cue when another car is knocked out."""
	rng = np.random.default_rng(seed)
	s = mu.Song(120, 2, loop=False)
	s.add("hit", mu.tom(rng, 110.0), 0.0, 0.8)
	s.add("hit", mu.kick(rng, 0.8), 0.0, 0.6)
	s.add("zap", _zap(rng, 1400.0, 180.0, 0.45), 0.0, 0.45)
	s.add("zap", _zap(rng, 1900.0, 260.0, 0.35), 0.06, 0.25, pan=0.4)
	return _finish_sting(s, rng, 0.3, 0.9)


def sting_player_out(seed=6):
	"""Heavier cue when the player is knocked out."""
	rng = np.random.default_rng(seed)
	s = mu.Song(120, 2, loop=False)
	for side in (-0.8, 0.8):
		s.add("gtr", mu.guitar_chord(mu.midi(E), 1.6, rng), 0.0, 0.45, pan=side)
	s.add("hit", mu.kick(rng, 1.2, 0.8, 38.0), 0.0, 1.0)
	s.add("hit", mu.crash(rng, 2.0), 0.0, 0.35)
	s.add("zap", _zap(rng, 900.0, 60.0, 1.2), 0.05, 0.45)
	for k, m in enumerate((59, 58, 57, 52)):
		s.add("lead", mu.lead_note(mu.midi(m), 0.25 if k < 3 else 0.9, rng, bright=0.6), 0.25 + 0.25 * k, 0.22)
	return _finish_sting(s, rng, 0.35, 1.2)
