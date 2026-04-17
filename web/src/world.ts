// ── Types ────────────────────────────────────────────────────────────────────

export interface Region {
  id: number
  name: string
  color: string
  tag: string
}

export interface WorldNode {
  id: number
  x: number
  y: number
  z: number
  region: number
}

export type EdgeKind = 'grid' | 'suture' | 'shaft'

export interface WorldEdge {
  u: number
  v: number
  kind: EdgeKind
}

export interface RawWorld {
  regions: Region[]
  nodes: WorldNode[]
  edges: WorldEdge[]
}

export interface WorldData extends RawWorld {
  /** O(1) node lookup by id */
  nodeById: Map<number, WorldNode>
  /** Undirected adjacency list: nodeId → neighbor ids */
  exitsByNode: Map<number, number[]>
  /** regionId → z-layer value (all nodes of a region share the same z) */
  regionZLayer: Map<number, number>
}

// ── Loader ───────────────────────────────────────────────────────────────────

export async function loadWorld(): Promise<WorldData> {
  const res = await fetch('/world.json')
  if (!res.ok) throw new Error(`HTTP ${res.status} — run 'make export-web' first`)
  const raw: RawWorld = await res.json()

  const nodeById = new Map<number, WorldNode>()
  for (const n of raw.nodes) nodeById.set(n.id, n)

  const exitsByNode = new Map<number, number[]>()
  for (const e of raw.edges) {
    if (!exitsByNode.has(e.u)) exitsByNode.set(e.u, [])
    if (!exitsByNode.has(e.v)) exitsByNode.set(e.v, [])
    exitsByNode.get(e.u)!.push(e.v)
    exitsByNode.get(e.v)!.push(e.u)
  }

  // Each region lives entirely on one z-layer; find it from the first node seen
  const regionZLayer = new Map<number, number>()
  for (const n of raw.nodes) {
    if (!regionZLayer.has(n.region)) {
      regionZLayer.set(n.region, n.z)
      if (regionZLayer.size === raw.regions.length) break
    }
  }

  return { ...raw, nodeById, exitsByNode, regionZLayer }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

const DIR_RANK: Record<string, number> = { N: 0, S: 1, E: 2, W: 3, U: 4, D: 5 }

export function getDirection(from: WorldNode, to: WorldNode): string {
  const dx = to.x - from.x
  const dy = to.y - from.y
  const dz = to.z - from.z
  if (dx === 0 && dy === 1 && dz === 0) return 'N'
  if (dx === 0 && dy === -1 && dz === 0) return 'S'
  if (dx === 1 && dy === 0 && dz === 0) return 'E'
  if (dx === -1 && dy === 0 && dz === 0) return 'W'
  if (dx === 0 && dy === 0 && dz === 1) return 'U'
  if (dx === 0 && dy === 0 && dz === -1) return 'D'
  return '?'
}

export function sortedExits(
  nodeId: number,
  world: WorldData,
): { dir: string; toId: number }[] {
  const neighbors = world.exitsByNode.get(nodeId) ?? []
  const from = world.nodeById.get(nodeId)!
  return neighbors
    .map(toId => ({ dir: getDirection(from, world.nodeById.get(toId)!), toId }))
    .sort((a, b) => (DIR_RANK[a.dir] ?? 9) - (DIR_RANK[b.dir] ?? 9))
}

/** Minimal HTML-escape for safe interpolation of untrusted strings into innerHTML. */
export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}
