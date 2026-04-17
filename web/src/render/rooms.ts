import * as THREE from 'three'
import type { WorldData, WorldNode } from '../world.ts'

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

export interface RegionMesh {
  mesh: THREE.InstancedMesh
  regionId: number
  /** nodeIds[instanceId] === room id — used by the raycaster */
  nodeIds: number[]
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
  const result: RegionMesh[] = []

  for (const region of world.regions) {
    const regionNodes = nodesByRegion.get(region.id)
    if (!regionNodes || regionNodes.length === 0) continue

    const mat = new THREE.MeshLambertMaterial({ color: new THREE.Color(region.color) })
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

    scene.add(mesh)
    result.push({ mesh, regionId: region.id, nodeIds })
  }

  return result
}
