import type { WorldData } from '../world.ts'
import { escapeHtml } from '../world.ts'
import type { SelectedRoom } from '../picking.ts'

const DIR_ARROW: Record<string, string> = {
  N: '↑N', S: '↓S', E: '→E', W: '←W', U: '⬆U', D: '⬇D',
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

    el.innerHTML = `
      <div class="h-label">Room</div>
      <div class="h-name" style="color:${escapeHtml(region.color)}">#${sel.nodeId} &mdash; ${escapeHtml(region.name)}</div>
      <div class="h-coords">(${x}, ${y}, ${z})</div>
      <div class="h-exits">
        <div class="h-exits-title">Exits</div>
        ${exitsHtml}
      </div>
    `
    el.style.display = 'block'
  }

  return { onRoomSelected }
}
