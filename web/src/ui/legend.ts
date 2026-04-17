import type { WorldData } from '../world.ts'
import { escapeHtml } from '../world.ts'
import type { RegionMesh } from '../render/rooms.ts'

export function createLegend(world: WorldData, regionMeshes: RegionMesh[]): void {
  const el = document.getElementById('legend')!

  // mesh.visible toggles the entire region InstancedMesh
  const meshByRegion = new Map(regionMeshes.map(rm => [rm.regionId, rm.mesh]))

  // Build z-layer → [regionId] mapping (each region sits on exactly one layer)
  const layerToRegionIds = new Map<number, number[]>()
  for (const [regionId, z] of world.regionZLayer) {
    if (!layerToRegionIds.has(z)) layerToRegionIds.set(z, [])
    layerToRegionIds.get(z)!.push(regionId)
  }
  // Surface (z=0) first, then descending into dungeons
  const sortedLayers = [...layerToRegionIds.keys()].sort((a, b) => b - a)

  // ── Build HTML ────────────────────────────────────────────────────────────

  const layerLabel = (z: number) => z === 0 ? 'Surface' : `z = ${z}`

  let html = '<h3>Layers</h3>'
  for (const z of sortedLayers) {
    html += `<label>
      <input type="checkbox" data-layer="${z}" checked>
      ${layerLabel(z)}
    </label>`
  }

  html += '<div class="sep"></div><h3>Regions</h3>'
  for (const r of world.regions) {
    html += `<label>
      <input type="checkbox" data-region="${r.id}" checked>
      <span class="swatch" style="background:${escapeHtml(r.color)}"></span>
      ${escapeHtml(r.name)}
    </label>`
  }

  el.innerHTML = html

  // ── Wire checkboxes ───────────────────────────────────────────────────────

  function setRegionVisible(regionId: number, visible: boolean) {
    const mesh = meshByRegion.get(regionId)
    if (mesh) mesh.visible = visible
    const cb = el.querySelector<HTMLInputElement>(`input[data-region="${regionId}"]`)
    if (cb) cb.checked = visible
  }

  el.querySelectorAll<HTMLInputElement>('input[data-region]').forEach(cb => {
    cb.addEventListener('change', () => {
      setRegionVisible(parseInt(cb.dataset.region!), cb.checked)
    })
  })

  el.querySelectorAll<HTMLInputElement>('input[data-layer]').forEach(cb => {
    cb.addEventListener('change', () => {
      const z = parseInt(cb.dataset.layer!)
      for (const id of layerToRegionIds.get(z) ?? []) {
        setRegionVisible(id, cb.checked)
      }
    })
  })
}
