"""Sound effects: tyres, wind, impacts, glass, scraping, explosions, fire,
water, nitro, hop, horn and UI."""

import numpy as np

from dsp import (SR, TAU, bp, brown, convolve, env_ad, env_exp, fade, filt, hp, lp,
	modal, normalize_peak, normalize_rms, peak, pink, place, room_ir, secs,
	smooth_random, soft_clip, stft_filter, trim_tail, wet)


def _rng(seed):
	return np.random.default_rng(seed)


def _periodic_phase(freq, n):
	"""Integrate a frequency track into a phase (cycles) that ends on a whole
	cycle, so a loop built from it is seamless."""
	ph = np.cumsum(freq) / SR
	total = ph[-1]
	ph *= max(1, round(total)) / total
	return ph - ph[0]


def _noise_burst(n, rng, lo, hi, decay_s):
	x = rng.standard_normal(n) * env_exp(n, decay_s)
	return filt(x, lambda f: hp(f, lo, 2) * lp(f, hi, 2))


def _metal_modes(rng, count, f_lo, f_hi, decay_lo, decay_hi, bright=0.0):
	"""Inharmonic modes of a crumpled panel. Higher modes decay faster."""
	fs = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi), count))
	modes = []
	for f in fs:
		frac = np.log(f / f_lo) / np.log(f_hi / f_lo)
		d = np.exp(np.log(decay_hi) + (np.log(decay_lo) - np.log(decay_hi)) * frac) * rng.uniform(0.6, 1.4)
		a = rng.uniform(0.3, 1.0) * (f / 1000.0) ** (bright * 0.5) / np.sqrt(count)
		modes.append((f, a, d))
	return modes


def metal_ir(rng, length_s=1.2, count=70, f_lo=140.0, f_hi=8000.0, decay_lo=0.02, decay_hi=0.5):
	return modal(secs(length_s), _metal_modes(rng, count, f_lo, f_hi, decay_lo, decay_hi), rng)


def _grains(n, rng, count, t0, t1, shape_fn, density_decay=None, gain_decay=None):
	"""Scatter count grains between t0 and t1 seconds. shape_fn(rng) -> array."""
	out = np.zeros(n)
	for _ in range(count):
		if density_decay:
			t = t0 + rng.exponential(density_decay)
			if t > t1:
				continue
		else:
			t = rng.uniform(t0, t1)
		g = np.exp(-(t - t0) / gain_decay) if gain_decay else 1.0
		place(out, shape_fn(rng), secs(t), g * rng.uniform(0.3, 1.0))
	return out


# ----------------------------------------------------------------------------
# Tyres, wind, landing


def skid_loop(seed=1, length_s=2.4):
	rng = _rng(seed)
	n = secs(length_s)
	t = np.arange(n) / SR
	out = np.zeros(n)
	# Squeal: a few unstable tones that wander and flutter.
	for base, amt in ((930.0, 1.0), (1240.0, 0.55), (1710.0, 0.3)):
		wander = smooth_random(n, rng, 2.5) * 0.035 + smooth_random(n, rng, 14.0) * 0.012
		ph = _periodic_phase(base * (1.0 + wander), n)
		tone = np.sin(TAU * ph) + 0.35 * np.sin(TAU * 2 * ph + 0.7) + 0.12 * np.sin(TAU * 3 * ph)
		flutter = 0.55 + 0.45 * np.tanh(1.5 * smooth_random(n, rng, 9.0))
		out += amt * tone * flutter
	out = normalize_rms(out, 1.0)
	hiss = normalize_rms(filt(rng.standard_normal(n), lambda f: bp(f, 3200.0, 0.8), circular=True), 1.0)
	scrub = normalize_rms(filt(rng.standard_normal(n), lambda f: lp(f, 380.0, 2) * hp(f, 60.0, 1), circular=True), 1.0)
	hiss *= 0.7 + 0.3 * smooth_random(n, rng, 6.0)
	x = out + 0.35 * hiss + 0.3 * scrub
	x = soft_clip(normalize_rms(x, 0.35), 1.4)
	x = filt(x, lambda f: hp(f, 50.0, 2) * lp(f, 9000.0, 2), circular=True)
	return normalize_rms(x, 0.2)


def wind_loop(seed=2, length_s=6.0):
	"""Stereo rushing air with slow gusts."""
	rng = _rng(seed)
	n = secs(length_s)
	gust = 0.65 + 0.35 * np.tanh(smooth_random(n, rng, 0.5))
	chans = []
	for c in range(2):
		x = np.zeros(n)
		for fc, q, amt, rate in ((180.0, 0.6, 1.0, 0.7), (520.0, 1.2, 0.7, 1.1), (1300.0, 1.5, 0.45, 1.7), (3200.0, 1.2, 0.18, 2.3)):
			band = filt(rng.standard_normal(n), lambda f: bp(f, fc, q), circular=True)
			mod = 0.6 + 0.4 * np.tanh(1.2 * smooth_random(n, rng, rate))
			x += amt * normalize_rms(band, 1.0) * mod
		buffet = normalize_rms(filt(rng.standard_normal(n), lambda f: bp(f, 70.0, 1.0), circular=True), 1.0)
		x += 0.5 * buffet * (0.5 + 0.5 * np.tanh(smooth_random(n, rng, 4.0)))
		chans.append(x * gust)
	x = np.stack(chans)
	return x / np.sqrt(np.mean(x * x)) * 0.2


def land(seed):
	"""Landing on the road: suspension slam, a body clunk and gravel spray."""
	rng = _rng(seed)
	n = secs(0.9)
	t = np.arange(n) / SR
	thump = np.sin(TAU * np.cumsum(55.0 + 45.0 * np.exp(-t / 0.03)) / SR) * env_ad(n, 0.002, 0.12)
	clunk = modal(n, [(170.0 * rng.uniform(0.9, 1.1), 0.5, 0.07), (390.0, 0.35, 0.05), (920.0, 0.2, 0.03), (2300.0, 0.08, 0.02)], rng)
	clunk *= env_ad(n, 0.001, 0.2)
	body = _noise_burst(n, rng, 80.0, 900.0, 0.05)

	def grit(r):
		m = secs(r.uniform(0.001, 0.005))
		g = r.standard_normal(m) * env_exp(m, m / SR / 3)
		fc = r.uniform(1500, 6500)
		return filt(g, lambda f: bp(f, fc, 1.5), pad=256)

	gravel = _grains(n, rng, 260, 0.0, 0.7, grit, density_decay=0.14)
	gravel = filt(gravel, lambda f: hp(f, 900.0, 2))
	x = 1.0 * normalize_peak(thump, 0) + 0.45 * normalize_peak(clunk, 0) + 0.3 * normalize_peak(body, 0) + 0.35 * normalize_peak(gravel, 0)
	return trim_tail(soft_clip(x * 0.8, 1.5))


# ----------------------------------------------------------------------------
# Impacts


def bump(seed):
	"""A light knock between cars: hollow panel thud with a little ring."""
	rng = _rng(seed)
	n = secs(0.5)
	t = np.arange(n) / SR
	f0 = rng.uniform(75, 105)
	thud = np.sin(TAU * np.cumsum(f0 * (1 + 0.6 * np.exp(-t / 0.015))) / SR) * env_ad(n, 0.001, 0.07)
	knock = _noise_burst(n, rng, 150.0, 1400.0, 0.025)
	panel = modal(n, _metal_modes(rng, 18, 250.0, 4500.0, 0.015, 0.12), rng) * env_ad(n, 0.0005, 0.15)
	x = normalize_peak(thud, 0) + 0.6 * normalize_peak(knock, 0) + 0.3 * normalize_peak(panel, 0)
	x = soft_clip(x * 0.9, 1.3)
	return trim_tail(x, -60)


def crunch(seed, size=1.0):
	"""A heavy metal crunch: boom, crumpling panels, then debris."""
	rng = _rng(seed)
	n = secs(1.8)
	t = np.arange(n) / SR
	boom = np.sin(TAU * np.cumsum(48.0 + 70.0 * np.exp(-t / 0.04)) / SR) * env_ad(n, 0.002, 0.22)
	boom += 0.6 * _noise_burst(n, rng, 40.0, 350.0, 0.12)
	# Crumple: a burst of creases, each a little noise click, rung through
	# the panel's modes.
	creases = np.zeros(n)
	span = rng.uniform(0.18, 0.35) * size
	for _ in range(int(40 * size)):
		at = rng.exponential(span * 0.35)
		if at > span * 1.6:
			continue
		m = secs(rng.uniform(0.0005, 0.004))
		click = rng.standard_normal(m) * np.hanning(m)
		place(creases, click, secs(at), np.exp(-at / span) * rng.uniform(0.3, 1.0))
	ir = metal_ir(rng, 1.2, 80, 130.0, 9000.0, 0.015, 0.45)
	crumple = convolve(creases, ir)[:n]
	tear = _noise_burst(n, rng, 1200.0, 7000.0, 0.06 * size) * (1 + 0.5 * smooth_random(n, rng, 40.0, circular=False))
	# Debris: small parts bouncing off.
	def part(r):
		m = secs(0.25)
		return modal(m, _metal_modes(r, 6, 600.0, 6000.0, 0.01, 0.08), r)
	debris = _grains(n, rng, int(14 * size), 0.12, 1.3, part, density_decay=0.35, gain_decay=0.6)
	x = (1.0 * normalize_peak(boom, 0) + 0.9 * normalize_peak(crumple, 0) + 0.3 * normalize_peak(tear, 0) + 0.25 * normalize_peak(debris, 0))
	x = soft_clip(x * 1.1, 2.0)
	ir_room = room_ir(0.8, 0.25, rng, bright=5000.0)
	x = wet(x, ir_room, 0.18)
	return trim_tail(filt(x, lambda f: hp(f, 35.0, 2)), -62, 0.1)


def glass(seed=11):
	rng = _rng(seed)
	n = secs(1.6)
	crack = _noise_burst(n, rng, 2500.0, 14000.0, 0.006)
	crack += modal(n, [(rng.uniform(2500, 4500), 0.4, 0.01), (rng.uniform(5000, 8000), 0.3, 0.008)], rng) * env_exp(n, 0.05)

	def shard(r):
		m = secs(0.08)
		f = r.uniform(2200, 11000)
		modes = [(f * k * r.uniform(0.97, 1.03), 1.0 / k, r.uniform(0.006, 0.04)) for k in (1, 2.31, 3.7)]
		return modal(m, modes, r)

	shards = _grains(n, rng, 220, 0.0, 1.4, shard, density_decay=0.25, gain_decay=0.5)
	# A second wave: pieces landing on the road.
	shards += 0.6 * _grains(n, rng, 90, 0.28, 1.4, shard, density_decay=0.3, gain_decay=0.5)
	hiss = _noise_burst(n, rng, 3500.0, 12000.0, 0.18)
	x = 1.0 * normalize_peak(crack, 0) + 0.8 * normalize_peak(shards, 0) + 0.3 * normalize_peak(hiss, 0)
	return trim_tail(x, -60, 0.1)


def scrape_loop(seed=12, length_s=2.0):
	"""Grinding metal on metal: stick-slip noise rung through panel modes,
	with a screech riding on top."""
	rng = _rng(seed)
	n = secs(length_s)
	exc = rng.standard_normal(n)
	stick = np.clip(0.5 + 0.8 * smooth_random(n, rng, 35.0), 0.05, None)
	judder = 0.7 + 0.3 * np.sin(TAU * np.round(23.0 * length_s) * np.arange(n) / n)
	exc *= stick * judder
	ir = metal_ir(rng, 0.6, 60, 200.0, 8000.0, 0.01, 0.12)
	grind = convolve(exc, ir, circular=True)
	grind = filt(grind, lambda f: hp(f, 120.0, 2) * peak(f, 2500.0, 1.0, 4.0), circular=True)
	wander = smooth_random(n, rng, 3.0) * 0.05
	ph = _periodic_phase(1850.0 * (1 + wander), n)
	screech = (np.sin(TAU * ph) + 0.3 * np.sin(TAU * 2.0 * ph)) * np.clip(smooth_random(n, rng, 2.0), 0, None)
	rumble = normalize_rms(filt(rng.standard_normal(n), lambda f: bp(f, 110.0, 0.8), circular=True), 1.0) * stick
	x = normalize_rms(grind, 1.0) + 0.25 * normalize_rms(screech, 1.0) + 0.5 * rumble
	x = soft_clip(normalize_rms(x, 0.3), 1.6)
	return normalize_rms(x, 0.2)


# ----------------------------------------------------------------------------
# Fire, explosion, water, falling


def explosion(seed=21):
	rng = _rng(seed)
	n = secs(5.0)
	t = np.arange(n) / SR
	crack = _noise_burst(n, rng, 200.0, 12000.0, 0.012)
	body = brown(n, rng, circular=False) * env_ad(n, 0.004, 0.5)
	body += 0.5 * pink(n, rng, circular=False) * env_ad(n, 0.002, 0.25)
	body = stft_filter(body, lambda tt, f: lp(f, 300.0 + 5000.0 * np.exp(-tt / 0.25), 2))
	sub = np.sin(TAU * np.cumsum(30.0 + 40.0 * np.exp(-t / 0.15)) / SR) * env_ad(n, 0.003, 0.7)
	rumble = brown(n, rng, circular=False) * env_ad(n, 0.25, 1.4)
	rumble = filt(rumble, lambda f: lp(f, 220.0, 2))

	def chunk(r):
		m = secs(0.5)
		return modal(m, _metal_modes(r, 10, 300.0, 5000.0, 0.02, 0.2), r)

	debris = _grains(n, rng, 30, 0.25, 3.0, chunk, density_decay=0.8, gain_decay=1.2)
	roar = filt(rng.standard_normal(n), lambda f: bp(f, 700.0, 0.6)) * env_ad(n, 0.15, 1.2)
	x = (0.7 * normalize_peak(crack, 0) + 1.0 * normalize_peak(body, 0) + 0.9 * normalize_peak(sub, 0)
		+ 0.45 * normalize_peak(rumble, 0) + 0.2 * normalize_peak(debris, 0) + 0.25 * normalize_peak(roar, 0))
	x = fade(soft_clip(x, 2.5), 0.0, 1.5)
	ir = room_ir(3.0, 0.9, rng, bright=3500.0, predelay_s=0.03)
	x = wet(x, ir, 0.35)
	return trim_tail(filt(x, lambda f: hp(f, 25.0, 2)), -60, 0.3)


def fire_loop(seed=22, length_s=4.0):
	rng = _rng(seed)
	n = secs(length_s)
	flicker = 0.6 + 0.4 * np.tanh(1.5 * smooth_random(n, rng, 4.0))
	roar = normalize_rms(filt(rng.standard_normal(n), lambda f: lp(f, 450.0, 2) * hp(f, 40.0, 1), circular=True), 1.0) * flicker
	breath = normalize_rms(filt(rng.standard_normal(n), lambda f: bp(f, 1100.0, 0.7), circular=True), 1.0)
	breath *= 0.5 + 0.5 * np.tanh(smooth_random(n, rng, 2.0))
	crackle = np.zeros(n)
	for _ in range(int(32 * length_s)):
		m = secs(rng.uniform(0.0008, 0.004))
		c = rng.standard_normal(m) * env_exp(m, m / SR / 4)
		fc = rng.uniform(1800, 7000)
		place(crackle, filt(c, lambda f: bp(f, fc, 1.2), pad=512), rng.integers(0, n), rng.uniform(0.2, 1.0) ** 2, wrap=True)
	for _ in range(int(3 * length_s)):
		m = secs(0.03)
		pop = modal(m, [(rng.uniform(300, 900), 1.0, 0.006), (rng.uniform(1500, 3000), 0.4, 0.004)], rng)
		place(crackle, pop, rng.integers(0, n), rng.uniform(0.5, 1.2), wrap=True)
	crackle = np.tanh(2.0 * crackle / (np.max(np.abs(crackle)) + 1e-9)) * 0.5
	x = normalize_rms(roar, 1.0) + 0.35 * breath + 1.2 * normalize_rms(crackle, 1.0)
	return normalize_rms(x, 0.2)


def splash(seed=31):
	rng = _rng(seed)
	n = secs(2.6)
	t = np.arange(n) / SR
	slap = _noise_burst(n, rng, 300.0, 3500.0, 0.02)
	thud = np.sin(TAU * np.cumsum(60.0 + 50.0 * np.exp(-t / 0.05)) / SR) * env_ad(n, 0.002, 0.15)
	wash = rng.standard_normal(n) * env_ad(n, 0.02, 0.45)
	wash = stft_filter(wash, lambda tt, f: lp(f, 1200.0 + 5000.0 * np.exp(-tt / 0.3), 2) * hp(f, 150.0, 1))

	def bubble(r):
		m = secs(0.12)
		tt = np.arange(m) / SR
		f0 = r.uniform(350, 1600)
		d = r.uniform(0.015, 0.06)
		f = f0 * (1 + 0.4 * tt / d)
		return np.sin(TAU * np.cumsum(f) / SR) * np.exp(-tt / d) * np.clip(tt / 0.002, 0, 1)

	bubbles = _grains(n, rng, 70, 0.08, 1.8, bubble, density_decay=0.4, gain_decay=0.7)
	gloop_t = np.clip(t - 0.22, 0, None)
	gloop = np.sin(TAU * np.cumsum(110.0 + 300.0 * np.clip(gloop_t / 0.12, 0, 1)) / SR) * (t > 0.22) * np.exp(-gloop_t / 0.06)

	def drop(r):
		m = secs(0.01)
		g = r.standard_normal(m) * env_exp(m, 0.002)
		return filt(g, lambda f: hp(f, 2500.0, 2), pad=256)

	spray = _grains(n, rng, 400, 0.35, 2.2, drop, density_decay=0.55)
	x = (0.8 * normalize_peak(slap, 0) + 0.8 * normalize_peak(thud, 0) + 1.0 * normalize_peak(wash, 0)
		+ 0.35 * normalize_peak(bubbles, 0) + 0.45 * normalize_peak(gloop, 0) + 0.25 * normalize_peak(spray, 0))
	return trim_tail(soft_clip(x, 1.3), -60, 0.2)


def fall_whoosh(seed=32):
	"""A long rush of air as a car drops away, rising then fading."""
	rng = _rng(seed)
	n = secs(3.2)
	t = np.arange(n) / SR
	x = pink(n, rng, circular=False)
	shape = np.clip(t / 1.4, 0, 1) ** 1.5 * np.exp(-np.clip(t - 1.8, 0, None) / 0.6)
	x = stft_filter(x, lambda tt, f: bp(f, 250.0 + 1200.0 * min(tt / 1.8, 1.0) ** 1.3, 0.9 + 0.8 * min(tt / 1.8, 1.0)))
	low = filt(rng.standard_normal(n), lambda f: bp(f, 90.0, 1.0)) * np.clip(t / 1.0, 0, 1) * np.exp(-np.clip(t - 2.0, 0, None) / 0.5)
	x = normalize_peak(x * shape, 0) + 0.4 * normalize_peak(low * (0.7 + 0.3 * smooth_random(n, rng, 5.0, circular=False)), 0)
	return fade(x, 0.05, 0.3)


# ----------------------------------------------------------------------------
# Nitro, hop, horn


def nitro_loop(seed=41, length_s=2.0):
	rng = _rng(seed)
	n = secs(length_s)
	jet = normalize_rms(filt(rng.standard_normal(n), lambda f: lp(f, 2800.0, 2) * hp(f, 180.0, 1) * peak(f, 1100.0, 1.2, 6.0), circular=True), 1.0)
	flutter = 0.8 + 0.2 * np.sin(TAU * round(31 * length_s) * np.arange(n) / n) * (0.6 + 0.4 * smooth_random(n, rng, 3.0))
	rumble = normalize_rms(filt(rng.standard_normal(n), lambda f: bp(f, 85.0, 1.0), circular=True), 1.0)
	hiss = normalize_rms(filt(rng.standard_normal(n), lambda f: hp(f, 5000.0, 2), circular=True), 1.0)
	x = jet * flutter + 0.6 * rumble * flutter + 0.25 * hiss
	x = soft_clip(normalize_rms(x, 0.3), 1.5)
	return normalize_rms(x, 0.2)


def nitro_burst(seed=42):
	rng = _rng(seed)
	n = secs(1.2)
	t = np.arange(n) / SR
	pop = np.sin(TAU * np.cumsum(70.0 + 120.0 * np.exp(-t / 0.02)) / SR) * env_ad(n, 0.002, 0.09)
	pop += 0.5 * _noise_burst(n, rng, 100.0, 4000.0, 0.03)
	rush = rng.standard_normal(n) * env_ad(n, 0.06, 0.45)
	rush = stft_filter(rush, lambda tt, f: bp(f, 400.0 + 2600.0 * min(tt / 0.35, 1.0), 1.2) + 0.3 * hp(f, 4000.0, 2))
	x = normalize_peak(pop, 0) + 0.8 * normalize_peak(rush, 0)
	return trim_tail(soft_clip(x, 1.6), -60, 0.15)


def hop(seed=43):
	"""Hydraulics fire: a hiss of air, a deep thunk and a spring twang."""
	rng = _rng(seed)
	n = secs(0.9)
	t = np.arange(n) / SR
	thunk = np.sin(TAU * np.cumsum(50.0 + 90.0 * np.exp(-t / 0.025)) / SR) * env_ad(n, 0.001, 0.12)
	clank = modal(n, [(130.0, 0.6, 0.12), (270.0, 0.5, 0.09), (545.0, 0.3, 0.06), (1340.0, 0.15, 0.03)], rng) * env_ad(n, 0.001, 0.3)
	hiss = _noise_burst(n, rng, 2500.0, 11000.0, 0.12) * np.clip(t / 0.01, 0, 1)
	spring = np.sin(TAU * np.cumsum(180.0 * (1 + 0.3 * np.exp(-t / 0.1))) / SR) * env_ad(n, 0.005, 0.18)
	x = normalize_peak(thunk, 0) + 0.5 * normalize_peak(clank, 0) + 0.45 * normalize_peak(hiss, 0) + 0.18 * normalize_peak(spring, 0)
	return trim_tail(soft_clip(x * 0.9, 1.4), -60, 0.1)


def horn(seed=44, length_s=0.75):
	"""A twin-tone electric car horn."""
	rng = _rng(seed)
	n = secs(length_s)
	t = np.arange(n) / SR
	x = np.zeros(n)
	for f in (415.0, 523.0):
		ph = f * t + 0.002 * smooth_random(n, rng, 6.0, circular=False)
		# A buzzy diaphragm: narrow pulses.
		x += np.tanh(4.0 * np.sin(TAU * ph)) + 0.5 * np.sin(TAU * 2 * ph)
	x = filt(x, lambda f: peak(f, 2200.0, 2.0, 9.0) * peak(f, 900.0, 1.5, 4.0) * hp(f, 300.0, 2) * lp(f, 6000.0, 2))
	env = np.clip(t / 0.015, 0, 1) * np.clip((length_s - t) / 0.06, 0, 1)
	x = soft_clip(normalize_peak(x, 0) * 1.2, 1.5) * env
	return fade(x, 0.002, 0.01)


# ----------------------------------------------------------------------------
# Pickups and stunt cash


def _bell(n, freq, decay_s, rng, bright=1.0):
	"""A small struck bell: slightly inharmonic partials, upper ones dying fast."""
	modes = [(freq * r, a * bright ** i, decay_s * d) for i, (r, a, d) in enumerate(
		((1.0, 1.0, 1.0), (2.01, 0.45, 0.55), (3.03, 0.22, 0.35), (4.27, 0.12, 0.2), (5.41, 0.06, 0.12)))]
	return modal(n, modes, rng) * env_ad(n, 0.0015, 10.0)


def pickup_chime(seed=61):
	"""Collecting a pickup: a quick rising three-note bell arpeggio over an
	upward shimmer of noise."""
	rng = _rng(seed)
	n = secs(1.3)
	x = np.zeros(n)
	for i, f in enumerate((659.3, 987.8, 1318.5)):
		place(x, _bell(n, f, 0.35 - 0.06 * i, rng), secs(0.055 * i), 1.0 - 0.15 * i)
	sweep = filt(rng.standard_normal(n), lambda f: bp(f, 6500.0, 1.5)) * env_ad(n, 0.12, 0.1)
	x = fade(normalize_peak(x, 0) + 0.18 * normalize_peak(sweep, 0), 0.0, 0.3)
	x = wet(x, room_ir(0.5, 0.25, rng, bright=9000.0), 0.18)
	return trim_tail(fade(soft_clip(normalize_peak(x, 0) * 0.95, 1.2), 0.0005, 0.05), -60, 0.08)


def cash_jingle(seed=62):
	"""Stunt cash: a till's ka-ching, a mechanical clack then a bright ring
	with a few coins jangling."""
	rng = _rng(seed)
	n = secs(1.0)
	clack = _noise_burst(n, rng, 900.0, 7000.0, 0.006) + 0.6 * modal(n, [(410.0, 1.0, 0.015), (1180.0, 0.6, 0.01)], rng)
	ring = np.zeros(n)
	place(ring, _bell(n, 2093.0, 0.32, rng, 0.8) + 0.8 * _bell(n, 2637.0, 0.28, rng, 0.8), secs(0.045))
	coins = _grains(n, rng, 7, 0.06, 0.3,
		lambda r: modal(secs(0.08), [(r.uniform(4500.0, 7500.0), 1.0, 0.012), (r.uniform(8000.0, 11000.0), 0.5, 0.008)], r))
	x = 0.55 * normalize_peak(clack, 0) + normalize_peak(ring, 0) + 0.25 * normalize_peak(coins, 0)
	x = filt(x, lambda f: hp(f, 250.0, 2))
	return trim_tail(fade(soft_clip(normalize_peak(x, 0) * 0.95, 1.3), 0.0005, 0.3), -60, 0.08)


def shockwave(seed=63):
	"""The shockwave pickup going off: a deep sub boom, a crack, and a wide
	rushing whoosh that sweeps down as the ring spreads."""
	rng = _rng(seed)
	n = secs(1.5)
	t = np.arange(n) / SR
	boom = np.sin(TAU * np.cumsum(32.0 + 85.0 * np.exp(-t / 0.06)) / SR) * env_ad(n, 0.003, 0.35)
	crack = _noise_burst(n, rng, 600.0, 9000.0, 0.025)
	rush = rng.standard_normal(n) * env_ad(n, 0.02, 0.4)
	rush = stft_filter(rush, lambda tt, f: bp(f, 3200.0 * np.exp(-tt / 0.3) + 180.0, 1.0), frame=1024, hop=256)
	zap = np.sin(TAU * np.cumsum(900.0 * np.exp(-t / 0.12) + 120.0) / SR) * env_ad(n, 0.001, 0.15)
	x = normalize_peak(boom, 0) + 0.45 * normalize_peak(crack, 0) + 0.6 * normalize_peak(rush, 0) + 0.18 * normalize_peak(zap, 0)
	x = soft_clip(normalize_peak(x, 0) * 1.3, 1.8)
	return trim_tail(fade(x, 0.0005, 0.08), -60, 0.12)


# ----------------------------------------------------------------------------
# UI


def ui_click(seed=51):
	rng = _rng(seed)
	n = secs(0.09)
	t = np.arange(n) / SR
	tick = _noise_burst(n, rng, 1500.0, 9000.0, 0.002)
	tone = np.sin(TAU * 1250.0 * t) * env_ad(n, 0.0005, 0.018) + 0.5 * np.sin(TAU * 620.0 * t) * env_ad(n, 0.001, 0.03)
	return fade(normalize_peak(0.6 * normalize_peak(tick, 0) + tone, 0), 0.0005, 0.01)


def ui_hover(seed=52):
	rng = _rng(seed)
	n = secs(0.06)
	t = np.arange(n) / SR
	tone = np.sin(TAU * 2100.0 * t) * env_ad(n, 0.001, 0.012) + 0.3 * _noise_burst(n, rng, 3000.0, 10000.0, 0.002)
	return fade(normalize_peak(tone, 0), 0.0005, 0.01)


def beep(freq=880.0, length_s=0.32):
	n = secs(length_s)
	t = np.arange(n) / SR
	x = np.sin(TAU * freq * t) + 0.3 * np.sin(TAU * 2 * freq * t) + 0.12 * np.sin(TAU * 3 * freq * t)
	env = np.clip(t / 0.004, 0, 1) * np.where(t < 0.18, 1.0, np.exp(-(t - 0.18) / 0.03))
	return fade(normalize_peak(x * env, 0), 0.0, 0.01)


def go_horn(seed=53):
	"""A stadium air horn chord, with a high start beep on top."""
	rng = _rng(seed)
	n = secs(1.5)
	t = np.arange(n) / SR
	x = np.zeros(n)
	for f in (233.1, 293.7, 349.2):
		for det in (-0.004, 0.0, 0.005):
			ph = f * (1 + det) * t + 0.15 * rng.uniform()
			x += np.tanh(3.0 * np.sin(TAU * ph)) * 0.5 + 0.5 * (2 * (ph % 1.0) - 1)
	x = filt(x, lambda f: peak(f, 1200.0, 1.2, 8.0) * peak(f, 2800.0, 2.0, 5.0) * hp(f, 160.0, 2) * lp(f, 6500.0, 2))
	env = np.clip(t / 0.03, 0, 1) * np.where(t < 1.0, 1.0, np.exp(-(t - 1.0) / 0.12))
	x = soft_clip(normalize_peak(x, 0) * 1.3, 2.0) * env
	start = beep(1760.0, 0.4)
	place(x, 0.6 * start, 0)
	return fade(normalize_peak(x, 0), 0.0, 0.05)
