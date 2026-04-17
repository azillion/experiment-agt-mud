import type { WorldData } from '../world.ts'
import { escapeHtml } from '../world.ts'
import type { SelectedRoom } from '../picking.ts'
import { RAMPS, sampleRamp } from '../render/ramps.ts'
import * as THREE from 'three'

const DIR_ARROW: Record<string, string> = {
  N: '↑N', S: '↓S', E: '→E', W: '←W', U: '⬆U', D: '⬇D',
}

const tmpColor = new THREE.Color()

function swatchHex(fieldName: string, value: number): string {
  const ramp = RAMPS[fieldName]
  if (!ramp) return '#666'
  sampleRamp(ramp, value, tmpColor)
  return '#' + tmpColor.getHexString()
}

export function createHud(world: WorldData): {
  onRoomSelected: (sel: SelectedRoom | null) => void
} {
  const el = document.getElementById('hud')!

  function onRoomSelected(sel: SelectedRoom | null) {
    if (!sel) {
      el.style.display = 'none'
      return
    }

    const region = world.regions[sel.node.region]
    const { x, y, z } = sel.node

    const exitsHtml = sel.exits.length === 0
      ? '<em style="color:#666">None (trapped!)</em>'
      : sel.exits
          .map(e => `<span class="exit-chip">${DIR_ARROW[e.dir] ?? escapeHtml(e.dir)} → ${e.toId}</span>`)
          .join('')

    const fieldsHtml = world.fields.length === 0 ? '' : `
      <div class="h-exits" style="margin-top:10px">
        <div class="h-exits-title">Fields</div>
        ${world.fields.map(f => {
          const v = f.values[sel.nodeId] ?? 0
          const swatch = swatchHex(f.name, v)
          return `<div style="display:flex;align-items:center;gap:6px;margin-top:2px;font-size:12px">
            <span style="width:10px;height:10px;border-radius:2px;background:${swatch};border:1px solid #333"></span>
            <span style="color:#999">${escapeHtml(f.name)}:</span>
            <span style="color:#ddd;font-variant-numeric:tabular-nums">${v.toFixed(3)}</span>
          </div>`
        }).join('')}
      </div>
    `

    el.innerHTML = `
      <div class="h-label">Room</div>
      <div class="h-name" style="color:${escapeHtml(region.color)}">#${sel.nodeId} &mdash; ${escapeHtml(region.name)}</div>
      <div class="h-coords">(${x}, ${y}, ${z})</div>
      <div class="h-exits">
        <div class="h-exits-title">Exits</div>
        ${exitsHtml}
      </div>
      ${fieldsHtml}
    `
    el.style.display = 'block'
  }

  return { onRoomSelected }
}
