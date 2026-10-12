"""Small DSP toolkit for the derby sound generator (numpy only).

Everything that has to loop seamlessly is built with circular operations:
noise is filtered in the frequency domain over the whole loop, periodic
events are placed with exact fractional delays in the frequency domain and
modulators have a whole number of cycles per loop. Pointwise operations
(gain, saturation) keep a periodic signal periodic, so the loop point is
just another sample.
"""

import numpy as np

SR = 44100
TAU = 2.0 * np.pi


def db(x):
	return 20.0 * np.log10(np.maximum(np.abs(x), 1e-12))


def undb(d):
	return 10.0 ** (np.asarray(d, dtype=np.float64) / 20.0)


def t_axis(n, sr=SR):
	return np.arange(n) / sr


def secs(s, sr=SR):
	return int(round(s * sr))


# ----------------------------------------------------------------------------
# Frequency responses (magnitudes, evaluated on an array of frequencies)


def lp(f, fc, order=2):
	return 1.0 / np.sqrt(1.0 + (np.abs(f) / fc) ** (2 * order))


def hp(f, fc, order=2):
	f = np.maximum(np.abs(f), 1e-6)
	return 1.0 / np.sqrt(1.0 + (fc / f) ** (2 * order))


def bp(f, fc, q):
	f = np.maximum(np.abs(f), 1e-6)
	return 1.0 / np.sqrt(1.0 + q * q * (f / fc - fc / f) ** 2)


def peak(f, fc, q, gain_db):
	"""A bell boost/cut: 1 + (g - 1) * bandpass."""
	return 1.0 + (undb(gain_db) - 1.0) * bp(f, fc, q)


def shelf_hi(f, fc, gain_db):
	g = undb(gain_db)
	return 1.0 + (g - 1.0) * hp(f, fc, 1)


def tilt(f, db_per_oct, ref=1000.0):
	f = np.maximum(np.abs(f), 10.0)
	return undb(db_per_oct * np.log2(f / ref))


# ----------------------------------------------------------------------------
# FFT filtering


def filt(x, resp, circular=False, pad=None):
	"""Filter x by a magnitude response function resp(freqs) (zero phase).

	circular=True treats x as one period of a loop. Otherwise x is padded
	so the filter's ringing doesn't wrap round.
	"""
	n = len(x)
	if not circular:
		pad = pad if pad is not None else min(n, SR)
		x = np.concatenate([x, np.zeros(pad)])
	spec = np.fft.rfft(x)
	freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
	spec *= resp(freqs)
	y = np.fft.irfft(spec, len(x))
	return y if circular else y[:n]


def filt_complex(x, cresp, circular=True):
	"""Filter with a complex response function cresp(freqs)."""
	n = len(x)
	if not circular:
		x = np.concatenate([x, np.zeros(min(n, SR))])
	spec = np.fft.rfft(x)
	freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
	spec *= cresp(freqs)
	y = np.fft.irfft(spec, len(x))
	return y if circular else y[:n]


def comb_resp(delay_s, feedback, damp_fc=None):
	"""Feedback comb (a tube): 1 / (1 - g e^{-jwD}), optional loss in the loop."""
	def r(f):
		g = feedback * (lp(f, damp_fc, 1) if damp_fc else 1.0)
		return 1.0 / (1.0 - g * np.exp(-1j * TAU * f * delay_s))
	return r


def convolve(x, ir, circular=False):
	if circular:
		n = len(x)
		irp = np.zeros(n)
		m = min(len(ir), n)
		irp[:m] = ir[:m]
		# Fold a longer IR round the loop.
		for k in range(n, len(ir), n):
			seg = ir[k:k + n]
			irp[:len(seg)] += seg
		return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(irp), n)
	n = len(x) + len(ir) - 1
	size = 1 << (n - 1).bit_length()
	y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
	return y[:n]


def stft_filter(x, resp_at, frame=2048, hop=512, circular=False):
	"""Time-varying zero-phase filter. resp_at(t_seconds, freqs) -> magnitudes.

	Weighted overlap-add with a sqrt-Hann window on both sides. With
	circular=True the frames that straddle the end wrap round to the start.
	"""
	n = len(x)
	win = np.sqrt(np.hanning(frame + 1)[:-1])
	if circular:
		ext = np.concatenate([x[-frame:], x, x[:frame]])
	else:
		ext = np.concatenate([np.zeros(frame), x, np.zeros(frame)])
	out = np.zeros(len(ext))
	norm = np.zeros(len(ext))
	freqs = np.fft.rfftfreq(frame, 1.0 / SR)
	for start in range(0, len(ext) - frame + 1, hop):
		seg = ext[start:start + frame] * win
		t = (start + frame / 2 - frame) / SR
		if circular:
			t = t % (n / SR)
		spec = np.fft.rfft(seg) * resp_at(t, freqs)
		out[start:start + frame] += np.fft.irfft(spec, frame) * win
		norm[start:start + frame] += win * win
	if circular:
		y = out[frame:frame + n].copy()
		w = norm[frame:frame + n].copy()
		y[-frame:] += out[:frame]
		w[-frame:] += norm[:frame]
		y[:frame] += out[frame + n:]
		w[:frame] += norm[frame + n:]
		return y / np.maximum(w, 1e-6)
	return (out / np.maximum(norm, 1e-6))[frame:frame + n]


# ----------------------------------------------------------------------------
# Noise and modulators


def noise(n, rng):
	return rng.standard_normal(n)


def pink(n, rng, circular=True):
	x = rng.standard_normal(n)
	return normalize_rms(filt(x, lambda f: 1.0 / np.sqrt(np.maximum(f, 20.0)), circular=circular), 1.0)


def brown(n, rng, circular=True):
	x = rng.standard_normal(n)
	return normalize_rms(filt(x, lambda f: 1.0 / np.maximum(f, 15.0), circular=circular), 1.0)


def smooth_random(n, rng, rate_hz, circular=True):
	"""A slowly wandering random signal (unit RMS) with energy below rate_hz.

	With circular=True it is periodic over n samples.
	"""
	x = rng.standard_normal(n)
	y = filt(x, lambda f: lp(f, rate_hz, 4), circular=circular)
	return normalize_rms(y, 1.0)


def periodic_lfo(n, cycles, phase=0.0):
	"""A sine with a whole number of cycles over n samples."""
	return np.sin(TAU * (cycles * np.arange(n) / n + phase))


# ----------------------------------------------------------------------------
# Envelopes and shaping


def env_exp(n, decay_s, sr=SR):
	return np.exp(-np.arange(n) / (decay_s * sr))


def env_ad(n, attack_s, decay_s, sr=SR):
	t = np.arange(n) / sr
	a = np.clip(t / max(attack_s, 1e-5), 0.0, 1.0)
	return a * np.exp(-np.maximum(t - attack_s, 0.0) / decay_s)


def env_adsr(n, a, d, s, r, gate_s, sr=SR):
	t = np.arange(n) / sr
	e = np.where(t < a, t / max(a, 1e-5), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-5)))
	at_gate = np.interp(gate_s, t, e) if n > 0 else 0.0
	rel = at_gate * np.exp(-(t - gate_s) / max(r, 1e-5))
	return np.where(t < gate_s, e, rel)


def fade(x, fin=0.002, fout=0.01):
	x = x.copy()
	a = secs(fin)
	b = secs(fout)
	if a > 0:
		x[:a] *= np.linspace(0, 1, a)
	if b > 0:
		x[-b:] *= np.linspace(1, 0, b) ** 2
	return x


def soft_clip(x, drive=1.0):
	return np.tanh(drive * x) / np.tanh(drive)


def asym_clip(x, drive=2.0, bias=0.2):
	y = np.tanh(drive * (x + bias)) - np.tanh(drive * bias)
	return y / np.max(np.abs(y) + 1e-12) * np.max(np.abs(x))


def normalize_peak(x, peak_db=-1.0):
	p = np.max(np.abs(x))
	return x * (undb(peak_db) / p) if p > 0 else x


def normalize_rms(x, target=1.0):
	r = np.sqrt(np.mean(x * x))
	return x * (target / r) if r > 0 else x


def rms_db(x):
	return db(np.sqrt(np.mean(x * x)))


def short_term_max_rms_db(x, win_s=0.4):
	w = secs(win_s)
	if len(x) <= w:
		return rms_db(x)
	c = np.concatenate([[0.0], np.cumsum(x * x)])
	ms = (c[w:] - c[:-w]) / w
	return db(np.sqrt(np.max(ms)))


def remove_dc(x, circular=False):
	return filt(x, lambda f: hp(f, 25.0, 2), circular=circular)


def trim_tail(x, thresh_db=-70.0, fout=0.05):
	"""Cut trailing silence and fade the end."""
	a = np.abs(x)
	lim = undb(thresh_db) * np.max(a)
	idx = np.nonzero(a > lim)[0]
	end = min(len(x), (idx[-1] if len(idx) else len(x)) + secs(0.02))
	return fade(x[:end], 0.0, fout)


# ----------------------------------------------------------------------------
# Oscillators


def polyblep(t, dt):
	"""PolyBLEP residual for phase t in [0,1) and phase step dt."""
	y = np.zeros_like(t)
	m = t < dt
	tt = t[m] / dt[m] if np.ndim(dt) else t[m] / dt
	y[m] = tt + tt - tt * tt - 1.0
	m2 = t > 1.0 - dt
	tt = (t[m2] - 1.0) / (dt[m2] if np.ndim(dt) else dt)
	y[m2] = tt * tt + tt + tt + 1.0
	return y


def saw_from_phase(phase, dt):
	p = phase % 1.0
	return 2.0 * p - 1.0 - polyblep(p, dt)


def square_from_phase(phase, dt, duty=0.5):
	p = phase % 1.0
	y = np.where(p < duty, 1.0, -1.0)
	y = y + polyblep(p, dt) - polyblep((p + 1.0 - duty) % 1.0, dt)
	return y


def phase_from_freq(freq, sr=SR, phase0=0.0):
	freq = np.asarray(freq, dtype=np.float64)
	return phase0 + np.cumsum(freq) / sr - freq[0] / sr


def additive(phase, n_harm, amp_fn, f0):
	"""Sum of harmonics k=1..n of a phase track (in cycles).

	amp_fn(k, freq_k) returns the amplitude (scalar or per-sample array).
	Harmonics above Nyquist are skipped.
	"""
	out = np.zeros_like(phase)
	for k in range(1, n_harm + 1):
		fk = f0 * k
		if fk >= SR * 0.47:
			break
		out += amp_fn(k, fk) * np.sin(TAU * k * phase)
	return out


def modal(n, modes, rng=None, sr=SR):
	"""Sum of decaying sinusoids. modes: iterable of (freq, amp, decay_s[, phase])."""
	t = np.arange(n) / sr
	out = np.zeros(n)
	for m in modes:
		f, a, d = m[0], m[1], m[2]
		ph = m[3] if len(m) > 3 else (rng.uniform(0, TAU) if rng is not None else 0.0)
		if f >= sr * 0.48:
			continue
		out += a * np.exp(-t / d) * np.sin(TAU * f * t + ph)
	return out


# ----------------------------------------------------------------------------
# Event placement


def place(buf, sound, start, gain=1.0, wrap=False):
	"""Add sound into buf at sample index start (wrapping round if wrap)."""
	start = int(start)
	n = len(buf)
	m = len(sound)
	if wrap:
		start %= n
		end = start + m
		if end <= n:
			buf[start:end] += gain * sound
		else:
			first = n - start
			buf[start:] += gain * sound[:first]
			rest = sound[first:]
			while len(rest) > 0:
				k = min(len(rest), n)
				buf[:k] += gain * rest[:k]
				rest = rest[k:]
		return
	if start >= n or start + m <= 0:
		return
	a = max(start, 0)
	b = min(start + m, n)
	buf[a:b] += gain * sound[a - start:b - start]


def impulse_train_spectrum(times, amps, n, sr=SR):
	"""Spectrum (rfft bins) of impulses at fractional times (s), circular over n."""
	freqs = np.fft.rfftfreq(n, 1.0 / sr)
	spec = np.zeros(len(freqs), dtype=np.complex128)
	times = np.asarray(times)
	amps = np.asarray(amps)
	chunk = 64
	for i in range(0, len(times), chunk):
		tt = times[i:i + chunk][:, None]
		aa = amps[i:i + chunk][:, None]
		spec += np.sum(aa * np.exp(-1j * TAU * freqs[None, :] * tt), axis=0)
	return spec, freqs


# ----------------------------------------------------------------------------
# Rooms


def room_ir(length_s, decay_s, rng, bright=6000.0, predelay_s=0.008, early=8, stereo=False):
	"""A synthetic room impulse response: early reflections plus a noise tail
	that gets darker as it decays."""
	n = secs(length_s)
	chans = []
	for c in range(2 if stereo else 1):
		x = rng.standard_normal(n)
		t = np.arange(n) / SR
		lo = filt(x, lambda f: lp(f, 900.0, 2))
		hi = x - lo
		tail = lo * np.exp(-t / decay_s) + hi * np.exp(-t / (decay_s * 0.45))
		tail = filt(tail, lambda f: lp(f, bright, 1))
		tail *= np.clip(t / 0.03, 0, 1)
		ir = np.zeros(n)
		pd = secs(predelay_s)
		ir[pd:] += tail[:n - pd] * 0.5
		for _ in range(early):
			d = secs(rng.uniform(0.004, 0.045)) + pd
			if d < n:
				ir[d] += rng.uniform(0.2, 0.6) * rng.choice([-1, 1])
		chans.append(ir / np.sqrt(np.sum(ir * ir)))
	return np.stack(chans) if stereo else chans[0]


def wet(x, ir, mix):
	y = convolve(x, ir)
	out = np.concatenate([x, np.zeros(len(y) - len(x))])
	return out + mix * y * (np.sqrt(np.mean(x * x)) / max(np.sqrt(np.mean(y[:len(x)] ** 2)), 1e-9))
