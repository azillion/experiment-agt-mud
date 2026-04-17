import * as THREE from 'three'
import type { WorldData, WorldNode } from './world.ts'
import { sortedExits } from './world.ts'
import type { RegionMesh } from './render/rooms.ts'
import { worldToThree } from './render/rooms.ts'

export interface SelectedRoom {
  nodeId: number
  node: WorldNode
  exits: { dir: string; toId: number }[]
}

export type SelectHandler = (sel: SelectedRoom | null) => void

export function setupPicking(
  world: WorldData,
  camera: THREE.Camera,
  regionMeshes: RegionMesh[],
  scene: THREE.Scene,
  onSelect: SelectHandler,
): {
  onPointerDown: (e: PointerEvent) => void
  onPointerUp: (e: PointerEvent) => void
} {
  const raycaster = new THREE.Raycaster()
  const pointer = new THREE.Vector2()

  // Yellow exit-highlight lines drawn on top (depthTest off so they're always visible)
  const selGeo = new THREE.BufferGeometry()
  selGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(0), 3))
  const selMat = new THREE.LineBasicMaterial({
    color: 0xffee44,
    depthTest: false,
    transparent: true,
    opacity: 0.9,
  })
  const selLines = new THREE.LineSegments(selGeo, selMat)
  selLines.name = 'selection-exits'
  selLines.renderOrder = 999
  scene.add(selLines)

  // ── Helpers ──────────────────────────────────────────────────────────────

  function updateSelectionHighlight(node: WorldNode) {
    const neighbors = world.exitsByNode.get(node.id) ?? []
    const pos: number[] = []
    const from = worldToThree(node)
    for (const toId of neighbors) {
      const toNode = world.nodeById.get(toId)
      if (!toNode) continue
      const to = worldToThree(toNode)
      pos.push(from.x, from.y, from.z, to.x, to.y, to.z)
    }
    const buf = new Float32Array(pos)
    selGeo.setAttribute('position', new THREE.BufferAttribute(buf, 3))
    selGeo.computeBoundingBox()
  }

  function clearSelection() {
    selGeo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(0), 3))
    onSelect(null)
  }

  // ── Pointer handling (distinguish click vs drag) ──────────────────────────

  let downX = 0
  let downY = 0

  function onPointerDown(e: PointerEvent) {
    downX = e.clientX
    downY = e.clientY
  }

  function onPointerUp(e: PointerEvent) {
    // Ignore drags (camera orbit)
    if (Math.hypot(e.clientX - downX, e.clientY - downY) > 5) return

    pointer.x = (e.clientX / window.innerWidth) * 2 - 1
    pointer.y = -(e.clientY / window.innerHeight) * 2 + 1
    raycaster.setFromCamera(pointer, camera)

    // Only raycast against visible region meshes
    const targets = regionMeshes.filter(rm => rm.mesh.visible).map(rm => rm.mesh)
    const hits = raycaster.intersectObjects(targets, false)

    if (hits.length === 0) {
      clearSelection()
      return
    }

    const hit = hits[0]
    const mesh = hit.object as THREE.InstancedMesh
    const nodeIds: number[] = mesh.userData.nodeIds
    const nodeId = nodeIds[hit.instanceId!]
    const node = world.nodeById.get(nodeId)
    if (!node) return

    updateSelectionHighlight(node)
    onSelect({ nodeId, node, exits: sortedExits(nodeId, world) })
  }

  return { onPointerDown, onPointerUp }
}
