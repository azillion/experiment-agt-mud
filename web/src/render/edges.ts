import * as THREE from 'three'
import type { WorldData, EdgeKind } from '../world.ts'
import { Z_SCALE } from './rooms.ts'

const EDGE_COLORS: Record<EdgeKind, number> = {
  grid:   0x666688,  // muted grey-blue  (mirrors graphviz #888888 at slightly cooler tone)
  suture: 0xa020f0,  // purple           (cross-region same layer)
  shaft:  0xff8c00,  // orange           (cross-layer vertical shaft)
}

export function createEdgeMeshes(
  world: WorldData,
  scene: THREE.Scene,
): Map<EdgeKind, THREE.LineSegments> {
  const positions: Record<EdgeKind, number[]> = { grid: [], suture: [], shaft: [] }

  // Inline worldToThree to avoid 2 * edges Vector3 allocations (~22k here).
  for (const edge of world.edges) {
    const u = world.nodeById.get(edge.u)
    const v = world.nodeById.get(edge.v)
    if (!u || !v) continue
    const arr = positions[edge.kind]
    arr.push(
      u.x, u.z * Z_SCALE, -u.y,
      v.x, v.z * Z_SCALE, -v.y,
    )
  }

  const result = new Map<EdgeKind, THREE.LineSegments>()

  for (const kind of ['grid', 'suture', 'shaft'] as EdgeKind[]) {
    const pos = new Float32Array(positions[kind])
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.BufferAttribute(pos, 3))
    const mat = new THREE.LineBasicMaterial({ color: EDGE_COLORS[kind] })
    const lines = new THREE.LineSegments(geo, mat)
    lines.name = `edges-${kind}`
    scene.add(lines)
    result.set(kind, lines)
  }

  return result
}
