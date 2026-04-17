import type { WorldData } from '../world.ts'
import { escapeHtml } from '../world.ts'
import type { RegionMesh, ColoringMode } from '../render/rooms.ts'
import { applyColoring } from '../render/rooms.ts'
import { RAMPS, rampToCssGradient } from '../render/ramps.ts'

export function createLegend(
  world: WorldData,
  regionMeshes: RegionMesh[],
  initialMode: ColoringMode = { kind: 'region' },
): { getMode: () => ColoringMode } {
  const el = document.getElementById('legend')!

  let currentMode: ColoringMode = initialMode

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

  // Coloring section: region + one radio per exported field
  let html = '<h3>Coloring</h3>'
  html += `<label>
    <input type="radio" name="coloring" data-color="region" ${
      currentMode.kind === 'region' ? 'checked' : ''
    }>
    Regions
  </label>`
  for (const f of world.fields) {
    const checked = currentMode.kind === 'field' && currentMode.field === f.name
    html += `<label>
      <input type="radio" name="coloring" data-color="field" data-field="${escapeHtml(f.name)}" ${checked ? 'checked' : ''}>
      ${escapeHtml(f.name.charAt(0).toUpperCase() + f.name.slice(1))}
    </label>`
  }
  html += `<div id="legend-colorbar" style="display:none"></div>`

  html += '<div class="sep"></div><h3>Layers</h3>'
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

  // ── Color bar helper ──────────────────────────────────────────────────────

  const colorbar = el.querySelector<HTMLElement>('#legend-colorbar')!
  function renderColorbar(mode: ColoringMode) {
    if (mode.kind !== 'field') {
      colorbar.style.display = 'none'
      colorbar.innerHTML = ''
      return
    }
    const ramp = RAMPS[mode.field]
    if (!ramp) {
      colorbar.style.display = 'none'
      return
    }
    colorbar.style.display = 'block'
    colorbar.innerHTML = `
      <div style="height:10px;border-radius:2px;margin-top:4px;background:${rampToCssGradient(ramp)}"></div>
      <div style="display:flex;justify-content:space-between;font-size:10px;color:#888;margin-top:2px">
        <span>0.0</span><span>1.0</span>
      </div>
    `
  }
  renderColorbar(currentMode)

  // ── Wire coloring radios ──────────────────────────────────────────────────

  el.querySelectorAll<HTMLInputElement>('input[name="coloring"]').forEach(radio => {
    radio.addEventListener('change', () => {
      if (!radio.checked) return
      const kind = radio.dataset.color
      currentMode = kind === 'field'
        ? { kind: 'field', field: radio.dataset.field! }
        : { kind: 'region' }
      applyColoring(regionMeshes, currentMode)
      renderColorbar(currentMode)
    })
  })

  // ── Wire layer / region checkboxes ────────────────────────────────────────

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

  return { getMode: () => currentMode }
}
