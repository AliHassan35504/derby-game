"""Checks for the generated sounds: levels, loop seams, spectra, and
spectrogram PNGs (written with zlib, no plotting library needed)."""

import struct
import zlib

import numpy as np

from dsp import SR, db


def write_png(path, rgb):
	"""rgb: (h, w, 3) uint8 array."""
	h, w, _ = rgb.shape
	raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

	def chunk(tag, data):
		c = struct.pack(">I", len(data)) + tag + data
		return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

	png = b"\x89PNG\r\n\x1a\n"
	png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
	png += chunk(b"IDAT", zlib.compress(raw, 9))
	png += chunk(b"IEND", b"")
	with open(path, "wb") as f:
		f.write(png)


def _colormap(v):
	"""v in [0,1] -> rgb (a simple dark-blue/red/yellow/white ramp)."""
	stops = np.array([
		[0.0, 0, 0, 0], [0.25, 20, 10, 90], [0.5, 170, 20, 80],
		[0.75, 250, 150, 20], [1.0, 255, 255, 230]])
	out = np.zeros(v.shape + (3,))
	for c in range(3):
		out[..., c] = np.interp(v, stops[:, 0], stops[:, c + 1])
	return out.astype(np.uint8)


def spectrogram(x, frame=2048, hop=256, fmax=12000.0, height=256, width=None, log_freq=True):
	if x.ndim > 1:
		x = x.mean(axis=0)
	n = max(1, (len(x) - frame) // hop + 1)
	win = np.hanning(frame)
	frames = np.stack([x[i * hop:i * hop + frame] * win for i in range(n)]) if len(x) >= frame else (np.pad(x, (0, frame - len(x))) * win)[None]
	mag = np.abs(np.fft.rfft(frames, axis=1)).T
	freqs = np.fft.rfftfreq(frame, 1.0 / SR)
	if log_freq:
		rows = np.geomspace(30.0, fmax, height)
	else:
		rows = np.linspace(0, fmax, height)
	idx = np.clip(np.searchsorted(freqs, rows), 0, len(freqs) - 1)
	img = db(mag[idx] + 1e-9)
	img = img - img.max()
	img = np.clip((img + 90.0) / 90.0, 0, 1)[::-1]
	if width and img.shape[1] > width:
		cols = np.linspace(0, img.shape[1] - 1, width).astype(int)
		img = img[:, cols]
	return img


def save_spectrograms(path, items, width=600, height=160):
	"""items: list of (label, signal). Stacks one spectrogram per row,
	with a waveform envelope strip under each."""
	rows = []
	for _label, x in items:
		img = spectrogram(x, height=height, width=width)
		rgb = _colormap(img)
		if rgb.shape[1] < width:
			rgb = np.concatenate([rgb, np.zeros((height, width - rgb.shape[1], 3), np.uint8)], axis=1)
		mono = x.mean(axis=0) if x.ndim > 1 else x
		strip = np.zeros((40, width, 3), np.uint8)
		cols = np.array_split(np.abs(mono), width)
		for i, c in enumerate(cols):
			if len(c):
				h = int(min(1.0, c.max()) * 38)
				strip[39 - h:40, i] = (80, 200, 255)
		rows += [rgb, strip, np.full((4, width, 3), 255, np.uint8)]
	write_png(path, np.concatenate(rows, axis=0))


def seam_click(x):
	"""How big the jump across the loop point is compared with the
	signal's normal sample-to-sample movement (second difference).
	About 1 or less means no click."""
	if x.ndim > 1:
		return max(seam_click(c) for c in x)
	d2 = np.abs(np.diff(x, 2))
	ext = np.concatenate([x[-3:], x[:3]])
	seam = np.max(np.abs(np.diff(ext, 2)))
	return seam / (np.percentile(d2, 99.5) + 1e-12)


def band_energies(x, edges=(20, 80, 250, 800, 2500, 6000, 12000, 20000)):
	if x.ndim > 1:
		x = x.mean(axis=0)
	spec = np.abs(np.fft.rfft(x)) ** 2
	freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
	total = spec.sum() + 1e-12
	out = []
	for a, b in zip(edges[:-1], edges[1:]):
		out.append(10 * np.log10(spec[(freqs >= a) & (freqs < b)].sum() / total + 1e-12))
	return out
