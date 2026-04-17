import * as THREE from 'three'

/**
 * Per-field color ramps, expressed as ordered stops in RGB space.
 * Values are interpolated linearly between adjacent stops.
 *
 * Keeping ramps in plain JS (not shader uniforms) lets us apply them
 * via InstancedMesh.setColorAt once per switch — no render-loop cost.
 */

type RampStop = { t: number; r: number; g: number; b: number }

const hexStop = (t: number, hex: number): RampStop => ({
  t,
  r: ((hex >> 16) & 0xff) / 255,
  g: ((hex >> 8) & 0xff) / 255,
  b: (hex & 0xff) / 255,
})

export type Ramp = RampStop[]

// Heat: near-black → deep red → orange → yellow → near-white
export const HEAT_RAMP: Ramp = [
  hexStop(0.0, 0x0a0a1a),
  hexStop(0.25, 0x2e0000),
  hexStop(0.5, 0x8a1a00),
  hexStop(0.75, 0xff5a1a),
  hexStop(0.9, 0xffd060),
  hexStop(1.0, 0xffffea),
]

// Light: midnight blue → pale blue → off-white
export const LIGHT_RAMP: Ramp = [
  hexStop(0.0, 0x060914),
  hexStop(0.4, 0x1a2a5e),
  hexStop(0.75, 0xa8bfff),
  hexStop(1.0, 0xfffff0),
]

export const RAMPS: Record<string, Ramp> = {
  heat: HEAT_RAMP,
  light: LIGHT_RAMP,
}

/** Sample a ramp at t ∈ [0,1], writing the result into [out] and returning it.
 *  Mutating a preallocated Color avoids per-call allocations in hot loops. */
export function sampleRamp(ramp: Ramp, t: number, out: THREE.Color): THREE.Color {
  // Clamp defensively; NaN values collapse to the bottom of the ramp.
  if (!(t > 0)) return out.setRGB(ramp[0].r, ramp[0].g, ramp[0].b)
  if (t >= 1) {
    const last = ramp[ramp.length - 1]
    return out.setRGB(last.r, last.g, last.b)
  }
  // Linear scan is fine — ramps have 4–6 stops.
  for (let i = 1; i < ramp.length; i++) {
    const b = ramp[i]
    if (t <= b.t) {
      const a = ramp[i - 1]
      const u = (t - a.t) / (b.t - a.t)
      return out.setRGB(
        a.r + (b.r - a.r) * u,
        a.g + (b.g - a.g) * u,
        a.b + (b.b - a.b) * u,
      )
    }
  }
  const last = ramp[ramp.length - 1]
  return out.setRGB(last.r, last.g, last.b)
}

/** Generate a CSS linear-gradient string for the legend's color bar. */
export function rampToCssGradient(ramp: Ramp): string {
  const stops = ramp.map(s => {
    const r = Math.round(s.r * 255)
    const g = Math.round(s.g * 255)
    const b = Math.round(s.b * 255)
    return `rgb(${r},${g},${b}) ${(s.t * 100).toFixed(0)}%`
  })
  return `linear-gradient(to right, ${stops.join(', ')})`
}
