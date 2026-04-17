import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import type { WorldData } from './world.ts'
import { loadWorld } from './world.ts'
import { createRoomMeshes } from './render/rooms.ts'
import { createEdgeMeshes } from './render/edges.ts'
import { setupPicking } from './picking.ts'
import { createLegend } from './ui/legend.ts'
import { createHud } from './ui/hud.ts'

// ── Overlay helpers ───────────────────────────────────────────────────────────

function showOverlay(msg?: string) {
  const ov = document.getElementById('overlay')!
  ov.classList.remove('hidden')
  if (msg) document.getElementById('overlay-error')!.textContent = msg
}

function hideOverlay() {
  document.getElementById('overlay')!.classList.add('hidden')
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  // ── Renderer ──────────────────────────────────────────────────────────────
  const renderer = new THREE.WebGLRenderer({ antialias: true })
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
  renderer.setSize(window.innerWidth, window.innerHeight)
  document.body.appendChild(renderer.domElement)

  // ── Scene ──────────────────────────────────────────────────────────────────
  const scene = new THREE.Scene()
  scene.background = new THREE.Color(0x12121e)
  // Mild exponential fog so far-away dungeons fade instead of hard-clipping
  scene.fog = new THREE.FogExp2(0x12121e, 0.0025)

  // ── Camera ────────────────────────────────────────────────────────────────
  // Start above the Capital centre (world 15,15,0 → three 15,0,-15), looking
  // slightly down-north so all z-layers are visible on first load.
  const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 600)
  camera.position.set(15, 55, 85)

  // ── Controls ──────────────────────────────────────────────────────────────
  const controls = new OrbitControls(camera, renderer.domElement)
  controls.target.set(15, -8, -15)
  controls.enableDamping = true
  controls.dampingFactor = 0.08
  controls.minDistance = 2
  controls.maxDistance = 400
  controls.update()

  // ── Lights ────────────────────────────────────────────────────────────────
  // Hemisphere: warm sky, cool ground — gives depth to the lit cubes
  scene.add(new THREE.HemisphereLight(0xfff4e0, 0x223355, 1.4))
  const sun = new THREE.DirectionalLight(0xffeedd, 0.7)
  sun.position.set(50, 80, 40)
  scene.add(sun)

  // ── Load world ────────────────────────────────────────────────────────────
  showOverlay()
  let world: WorldData
  try {
    world = await loadWorld()
  } catch (err) {
    showOverlay(String(err))
    return
  }
  hideOverlay()

  // ── Geometry ──────────────────────────────────────────────────────────────
  const regionMeshes = createRoomMeshes(world, scene)
  createEdgeMeshes(world, scene)

  // ── UI ────────────────────────────────────────────────────────────────────
  const { onRoomSelected } = createHud(world)
  createLegend(world, regionMeshes)

  // ── Picking ───────────────────────────────────────────────────────────────
  const { onPointerDown, onPointerUp } = setupPicking(
    world, camera, regionMeshes, scene, onRoomSelected,
  )
  renderer.domElement.addEventListener('pointerdown', onPointerDown)
  renderer.domElement.addEventListener('pointerup', onPointerUp)

  // ── Resize ────────────────────────────────────────────────────────────────
  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight
    camera.updateProjectionMatrix()
    renderer.setSize(window.innerWidth, window.innerHeight)
  })

  // ── Animation loop ────────────────────────────────────────────────────────
  renderer.setAnimationLoop(() => {
    controls.update()
    renderer.render(scene, camera)
  })
}

main().catch(err => {
  console.error(err)
  showOverlay(String(err))
})
