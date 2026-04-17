import * as THREE from 'three'
import type { WorldData, WorldNode } from '../world.ts'
import { RAMPS, sampleRamp } from './ramps.ts'

// Z exaggeration: world z ∈ {0,-1,-2,-3} → THREE.js y ∈ {0,-8,-16,-24}
export const Z_SCALE = 8

/** Map world coordinates to Three.js scene position.
 *  world X → THREE.x  (East)
 *  world Z → THREE.y  (up; surface=0, dungeons below)
 *  world Y → THREE.z  (negated so +y/"North" points away from viewer)
 */
export function worldToThree(n: WorldNode): THREE.Vector3 {
  return new THREE.Vector3(n.x, n.z * Z_SCALE, -n.y)
}

export type ColoringMode = { kind: 'region' } | { kind: 'field'; field: string }

export interface RegionMesh {
  mesh: THREE.InstancedMesh
  regionId: number
  /** nodeIds[instanceId] === room id — used by the raycaster */
  nodeIds: number[]
  /** Re-color every instance in this region based on the requested mode. */
  setColoring: (mode: ColoringMode) => void
}

const BOX = new THREE.BoxGeometry(0.55, 0.55, 0.55)

export function createRoomMeshes(world: WorldData, scene: THREE.Scene): RegionMesh[] {
  // Single O(n) pass to group nodes by region instead of R * O(n) filters.
  const nodesByRegion = new Map<number, WorldNode[]>()
  for (const n of world.nodes) {
    let bucket = nodesByRegion.get(n.region)
    if (!bucket) {
      bucket = []
      nodesByRegion.set(n.region, bucket)
    }
    bucket.push(n)
  }

  const dummy = new THREE.Object3D()
  const tmpColor = new THREE.Color()
  const result: RegionMesh[] = []

  for (const region of world.regions) {
    const regionNodes = nodesByRegion.get(region.id)
    if (!regionNodes || regionNodes.length === 0) continue

    // Base color white; InstancedMesh.instanceColor (populated by setColorAt)
    // is automatically multiplied in by Three.js when present — no vertexColors
    // flag needed (that's for per-vertex color attributes on the geometry,
    // which a shared BoxGeometry doesn't carry).
    const mat = new THREE.MeshLambertMaterial({ color: 0xffffff })
    const mesh = new THREE.InstancedMesh(BOX, mat, regionNodes.length)
    mesh.name = `region-${region.id}`

    const nodeIds = regionNodes.map(n => n.id)
    mesh.userData.regionId = region.id
    mesh.userData.nodeIds = nodeIds

    regionNodes.forEach((node, i) => {
      dummy.position.copy(worldToThree(node))
      dummy.updateMatrix()
      mesh.setMatrixAt(i, dummy.matrix)
    })
    mesh.instanceMatrix.needsUpdate = true

    // Seed instance colors with region color. Allocating the instanceColor
    // buffer here (not lazily on first setColorAt) avoids a one-frame flash.
    const regionColor = new THREE.Color(region.color)
    for (let i = 0; i < regionNodes.length; i++) {
      mesh.setColorAt(i, regionColor)
    }
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true

    const setColoring = (mode: ColoringMode) => {
      if (mode.kind === 'region') {
        for (let i = 0; i < regionNodes.length; i++) {
          mesh.setColorAt(i, regionColor)
        }
      } else {
        const values = world.fieldByName.get(mode.field)
        const ramp = RAMPS[mode.field]
        if (!values || !ramp) {
          // Unknown field → fall back to region color rather than crashing
          for (let i = 0; i < regionNodes.length; i++) {
            mesh.setColorAt(i, regionColor)
          }
        } else {
          for (let i = 0; i < regionNodes.length; i++) {
            const v = values[regionNodes[i].id]
            sampleRamp(ramp, v, tmpColor)
            mesh.setColorAt(i, tmpColor)
          }
        }
      }
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true
    }

    scene.add(mesh)
    result.push({ mesh, regionId: region.id, nodeIds, setColoring })
  }

  return result
}

/** Apply a coloring mode across every region mesh in one call. */
export function applyColoring(regionMeshes: RegionMesh[], mode: ColoringMode): void {
  for (const rm of regionMeshes) rm.setColoring(mode)
}
