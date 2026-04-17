open Agt_mud_lib

(* =========================================================================
   1. Compass Direction Engine
   ========================================================================= *)

type dir = North | South | East | West | Up | Down

let string_of_dir = function
  | North -> "N" | South -> "S" | East -> "E"
  | West -> "W" | Up -> "U" | Down -> "D"

let opposite = function
  | North -> South | South -> North
  | East -> West | West -> East
  | Up -> Down | Down -> Up

let dir_rank = function
  | North -> 0 | South -> 1 | East -> 2
  | West -> 3 | Up -> 4 | Down -> 5

(* =========================================================================
   2. Spatial Registry (Euclidean anchoring)
   ========================================================================= *)

type coords = { x : int; y : int; z : int }

let positions : (int, coords) Hashtbl.t = Hashtbl.create 16384
let occupied : (int * int * int, int) Hashtbl.t = Hashtbl.create 16384

let set_pos id x y z =
  Hashtbl.replace positions id { x; y; z };
  Hashtbl.replace occupied (x, y, z) id

let get_pos id =
  try Hashtbl.find positions id
  with Not_found ->
    failwith (Printf.sprintf "Node %d has no spatial coordinates!" id)

let is_occupied x y z = Hashtbl.mem occupied (x, y, z)

let get_spatial_dir u v : dir =
  let p1 = get_pos u in
  let p2 = get_pos v in
  match p2.x - p1.x, p2.y - p1.y, p2.z - p1.z with
  |  0,  1,  0 -> North
  |  0, -1,  0 -> South
  |  1,  0,  0 -> East
  | -1,  0,  0 -> West
  |  0,  0,  1 -> Up
  |  0,  0, -1 -> Down
  | dx, dy, dz ->
      failwith
        (Printf.sprintf
           "Invalid suture between %d and %d! delta=(%d, %d, %d)."
           u v dx dy dz)

let exits : (int, (dir * int) list) Hashtbl.t = Hashtbl.create 16384

let record_exit u d v =
  let cur = try Hashtbl.find exits u with Not_found -> [] in
  Hashtbl.replace exits u ((d, v) :: cur)

let add_spatial_edge g u v =
  let d = get_spatial_dir u v in
  Graph.add_edge g u v;
  record_exit u d v;
  record_exit v (opposite d) u

(* =========================================================================
   3. Spatial Generators
   ========================================================================= *)

let build_city g offset start_x start_y z_level width height =
  for row = 0 to height - 1 do
    for col = 0 to width - 1 do
      let id = offset + (row * width) + col in
      set_pos id (start_x + col) (start_y + row) z_level
    done
  done;
  for row = 0 to height - 1 do
    for col = 0 to width - 1 do
      let id = offset + (row * width) + col in
      if col < width - 1 then add_spatial_edge g id (id + 1);
      if row < height - 1 then add_spatial_edge g id (id + width)
    done
  done;
  offset + (width * height)

let shuffle_array a =
  for i = Array.length a - 1 downto 1 do
    let j = Random.int (i + 1) in
    let t = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- t
  done

let fresh_dirs () =
  let a = [| (1, 0); (-1, 0); (0, 1); (0, -1) |] in
  shuffle_array a;
  a

(* Spatial maze on a single z-plane.
   Phase 1: deterministic Manhattan corridor through every anchor.
   Phase 2: iterative randomized DFS to fill the remaining budget.
   The iterative form is essential at 1000+ cells; the recursive form
   would blow OCaml's ~40 000-frame stack on long winding corridors. *)
exception Budget_exhausted

let build_spatial_maze g offset start_x start_y z_level size ?(anchors = []) () =
  let next_id = ref offset in
  let placed_ids = ref [] in
  let alloc x y =
    let id = !next_id in
    incr next_id;
    set_pos id x y z_level;
    placed_ids := id :: !placed_ids;
    id
  in
  let budget_ok () = !next_id < offset + size in

  (* Phase 1: anchored corridor *)
  let start_id = alloc start_x start_y in
  let cur_id = ref start_id in
  let cur_x = ref start_x in
  let cur_y = ref start_y in

  let advance step axis =
    if !next_id >= offset + size then raise Budget_exhausted;
    (match axis with
     | `X -> cur_x := !cur_x + step
     | `Y -> cur_y := !cur_y + step);
    match
      try Some (Hashtbl.find occupied (!cur_x, !cur_y, z_level))
      with Not_found -> None
    with
    | Some id -> cur_id := id
    | None ->
        let parent = !cur_id in
        let id = alloc !cur_x !cur_y in
        add_spatial_edge g parent id;
        cur_id := id
  in
  (try
     List.iter
       (fun (ax, ay) ->
         while !cur_x <> ax do
           advance (if ax > !cur_x then 1 else -1) `X
         done;
         while !cur_y <> ay do
           advance (if ay > !cur_y then 1 else -1) `Y
         done)
       anchors
   with Budget_exhausted ->
     failwith
       (Printf.sprintf
          "Maze at offset %d: budget %d too small for %d anchor(s)."
          offset size (List.length anchors)));

  (* Phase 2: iterative randomized DFS. Each stack frame carries the
     remaining untried directions for that cell. *)
  let stack = Stack.create () in
  (* Seed DFS from every already-placed cell. In practice only the first
     one actually matters; others skip because budget_ok fails. *)
  List.iter
    (fun id ->
      let p = get_pos id in
      Stack.push (id, p.x, p.y, ref (fresh_dirs ()), ref 0) stack)
    !placed_ids;

  while (not (Stack.is_empty stack)) && budget_ok () do
    let (parent, px, py, dirs, idx) = Stack.top stack in
    if !idx >= Array.length !dirs then
      let _ = Stack.pop stack in ()
    else begin
      let (dx, dy) = !dirs.(!idx) in
      incr idx;
      let nx = px + dx and ny = py + dy in
      if (not (is_occupied nx ny z_level)) && budget_ok () then begin
        let id = alloc nx ny in
        add_spatial_edge g parent id;
        Stack.push (id, nx, ny, ref (fresh_dirs ()), ref 0) stack
      end
    end
  done;

  if !next_id < offset + size then
    failwith
      (Printf.sprintf
         "Maze at offset %d boxed in after %d/%d cells."
         offset (!next_id - offset) size);
  !next_id

(* =========================================================================
   4. Macro-Graph: the Huge Layered World
   ========================================================================= *)

type region = {
  name : string;
  offset : int;
  size : int;
  color : string;
  tag : string;
}

(* 7 regions * 4 z-layers, ~10 000 rooms *)
let capital_w = 30
let capital_h = 30
let capital_size = capital_w * capital_h          (* 900   z=0  *)
let woods_size   = 2000                            (* 2000  z=0  *)
let swamp_size   = 2000                            (* 2000  z=0  *)
let mountain_sz  = 1500                            (* 1500  z=0  *)
let dungeon_u_sz = 1500                            (* 1500  z=-1 *)
let dungeon_l_sz = 1500                            (* 1500  z=-2 *)
let abyss_size   = 1000                            (* 1000  z=-3 *)

let cap_off   = 0
let wood_off  = cap_off   + capital_size
let swamp_off = wood_off  + woods_size
let mtn_off   = swamp_off + swamp_size
let d1_off    = mtn_off   + mountain_sz
let d2_off    = d1_off    + dungeon_u_sz
let abyss_off = d2_off    + dungeon_l_sz
let total_nodes = abyss_off + abyss_size

let regions = [|
  { name = "Capital";       offset = cap_off;   size = capital_size; color = "#add8e6"; tag = "City"  };
  { name = "Dark Woods";    offset = wood_off;  size = woods_size;   color = "#6abf69"; tag = "Wood"  };
  { name = "Fetid Swamp";   offset = swamp_off; size = swamp_size;   color = "#b8a26b"; tag = "Swmp"  };
  { name = "Grey Mountain"; offset = mtn_off;   size = mountain_sz;  color = "#c0c0c0"; tag = "Mtn"   };
  { name = "Upper Dungeon"; offset = d1_off;    size = dungeon_u_sz; color = "#f08080"; tag = "Dgn1"  };
  { name = "Lower Dungeon"; offset = d2_off;    size = dungeon_l_sz; color = "#c74a4a"; tag = "Dgn2"  };
  { name = "The Abyss";     offset = abyss_off; size = abyss_size;   color = "#5a3f8f"; tag = "Abys"  };
|]

let region_of_id id =
  let rec loop i =
    if i >= Array.length regions then
      failwith (Printf.sprintf "Node %d belongs to no region" id)
    else
      let r = regions.(i) in
      if id >= r.offset && id < r.offset + r.size then i else loop (i + 1)
  in
  loop 0

let sutures : (int * int) list ref = ref []
let macro_sutures : (int * int) list ref = ref []

let apply_suture g u v =
  add_spatial_edge g u v;
  sutures := (u, v) :: !sutures;
  let ra = region_of_id u and rb = region_of_id v in
  if ra <> rb then
    macro_sutures := (min ra rb, max ra rb) :: !macro_sutures

(* Flip to [true] to sever a deep suture and watch the hierarchical
   check localize the failure. *)
let skip_abyss_shaft = false

let build_world () =
  Random.init 42;
  let g = Graph.create total_nodes in

  (* --- Micro-graphs --- *)

  (* Capital: 30x30 grid anchored at origin *)
  let _ = build_city g cap_off 0 0 0 capital_w capital_h in

  (* Dark Woods: starts 1 cell east of capital edge, needs to touch east
     edge of capital for the suture. *)
  let _ = build_spatial_maze g wood_off 30 15 0 woods_size () in

  (* Fetid Swamp: south of capital *)
  let _ = build_spatial_maze g swamp_off 15 (-1) 0 swamp_size () in

  (* Grey Mountain: west of capital *)
  let _ = build_spatial_maze g mtn_off (-1) 15 0 mountain_sz () in

  (* Upper Dungeon: directly below capital centre, anchored so it reaches
     (17, 17, -1), giving the Lower Dungeon a staircase target. *)
  let _ = build_spatial_maze g d1_off 15 15 (-1) dungeon_u_sz
            ~anchors:[ (17, 17) ] () in

  (* Lower Dungeon: anchored so it reaches (19, 19, -2), feeding the
     Abyss shaft. *)
  let _ = build_spatial_maze g d2_off 17 17 (-2) dungeon_l_sz
            ~anchors:[ (19, 19) ] () in

  (* The Abyss: deepest layer *)
  let _ = build_spatial_maze g abyss_off 19 19 (-3) abyss_size () in

  (* --- Macro-sutures --- *)

  (* Capital east gate (29, 15, 0) id = 15*30+29 = 479 <-> woods start (30, 15, 0) *)
  apply_suture g 479 wood_off;

  (* Capital south gate (15, 0, 0) id = 15 <-> swamp start (15, -1, 0) *)
  apply_suture g 15 swamp_off;

  (* Capital west gate (0, 15, 0) id = 450 <-> mountain start (-1, 15, 0) *)
  apply_suture g 450 mtn_off;

  (* Capital centre (15, 15, 0) id = 15*30+15 = 465 <-> upper dungeon start (15,15,-1) *)
  apply_suture g 465 d1_off;

  (* Upper dungeon stair at (17, 17, -1) <-> lower dungeon start (17, 17, -2) *)
  let d1_stair =
    try Hashtbl.find occupied (17, 17, -1)
    with Not_found -> failwith "Upper Dungeon anchor (17,17,-1) missing."
  in
  apply_suture g d1_stair d2_off;

  (* Lower dungeon shaft at (19, 19, -2) <-> abyss start (19, 19, -3) *)
  if not skip_abyss_shaft then begin
    let d2_shaft =
      try Hashtbl.find occupied (19, 19, -2)
      with Not_found -> failwith "Lower Dungeon anchor (19,19,-2) missing."
    in
    apply_suture g d2_shaft abyss_off
  end;

  g

(* =========================================================================
   5. Visualization
   ========================================================================= *)

let screen_pos p =
  let scale = 1.0 in
  let layer_offset = 80.0 in
  let sx = float_of_int p.x *. scale +. (float_of_int (-p.z)) *. layer_offset in
  let sy = float_of_int p.y *. scale in
  (sx, sy)

let node_attr i =
  let p = get_pos i in
  let sx, sy = screen_pos p in
  let r = regions.(region_of_id i) in
  Printf.sprintf
    "fillcolor=\"%s\", label=\"\", shape=point, width=0.15, pos=\"%.2f,%.2f!\", \
     tooltip=\"%s %d (%d,%d,%d)\""
    r.color sx sy r.tag i p.x p.y p.z

let pair_eq (a, b) (x, y) = (a = x && b = y) || (a = y && b = x)

let edge_attr i j =
  let is_suture = List.exists (pair_eq (i, j)) !sutures in
  if is_suture then
    let p_i = get_pos i and p_j = get_pos j in
    if p_i.z <> p_j.z then "color=\"darkorange\", penwidth=3.0, style=\"dashed\""
    else "color=\"purple\", penwidth=3.0"
  else "color=\"#888888\", penwidth=0.3"

let edge_kind u v =
  if List.exists (pair_eq (u, v)) !sutures then
    let pu = get_pos u and pv = get_pos v in
    if pu.z <> pv.z then "shaft" else "suture"
  else "grid"

(* =========================================================================
   6. AI Payload Generator
   ========================================================================= *)

let print_ai_payload room_id biome =
  let p = get_pos room_id in
  let exits_list = try Hashtbl.find exits room_id with Not_found -> [] in
  let exits_json =
    exits_list
    |> List.sort (fun (a, _) (b, _) -> compare (dir_rank a) (dir_rank b))
    |> List.map (fun (d, v) -> Printf.sprintf "\"%s\": %d" (string_of_dir d) v)
    |> String.concat ", "
  in
  Printf.printf "{ \"room_id\": %d, \"coords\": (%d,%d,%d), \"biome\": \"%s\", \"exits\": { %s } }\n"
    room_id p.x p.y p.z biome exits_json

(* =========================================================================
   7. Verification: BFS (cheap, exact) + AGT eigvals (expensive, bonus)
   ========================================================================= *)

let time_it f =
  let t0 = Unix.gettimeofday () in
  let v = f () in
  (v, Unix.gettimeofday () -. t0)

(* Count connected components among [node_ids], traversing only edges
   whose BOTH endpoints are in the set. O(n + E_local). *)
let components_in_set node_ids =
  let membership = Hashtbl.create (List.length node_ids) in
  List.iter (fun n -> Hashtbl.replace membership n ()) node_ids;
  let visited = Hashtbl.create (List.length node_ids) in
  let c = ref 0 in
  List.iter (fun start ->
    if not (Hashtbl.mem visited start) then begin
      incr c;
      let q = Queue.create () in
      Queue.add start q;
      Hashtbl.replace visited start ();
      while not (Queue.is_empty q) do
        let u = Queue.pop q in
        let neigh = try Hashtbl.find exits u with Not_found -> [] in
        List.iter (fun (_, v) ->
          if Hashtbl.mem membership v && not (Hashtbl.mem visited v) then begin
            Hashtbl.replace visited v ();
            Queue.add v q
          end
        ) neigh
      done
    end
  ) node_ids;
  !c

let region_ids r =
  let rec loop i acc =
    if i < r.offset then acc
    else loop (i - 1) (i :: acc)
  in
  loop (r.offset + r.size - 1) []

let all_ids () =
  let n = total_nodes in
  let rec loop i acc = if i < 0 then acc else loop (i - 1) (i :: acc) in
  loop (n - 1) []

(* Fiedler value of a small dense adjacency matrix. Only called for
   matrices we know are cheap (regions <= threshold, macro graph). *)
let fiedler_of_adj adj =
  let n = Owl.Mat.row_num adj in
  if n < 2 then 0.0
  else
    let d = Owl.Mat.zeros n n in
    for i = 0 to n - 1 do
      let deg = Owl.Mat.sum' (Owl.Mat.row adj i) in
      Owl.Mat.set d i i deg
    done;
    let l = Owl.Mat.sub d adj in
    let vals = Owl.Linalg.D.eigvals l in
    let arr = Owl.Dense.Matrix.Z.to_array vals in
    let flat = Array.map (fun c -> c.Complex.re) arr in
    Array.sort compare flat;
    flat.(1)

let sub_adjacency full lo hi =
  let n = hi - lo in
  let m = Owl.Mat.zeros n n in
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      Owl.Mat.set m i j (Owl.Mat.get full (lo + i) (lo + j))
    done
  done;
  m

let eig_cutoff = 1000  (* run eigvals only on regions at most this big *)
let monolithic_cutoff = 2000  (* skip monolithic AGT above this *)

let verify_bfs_global g =
  Printf.printf "\n--- Global BFS Connectivity (O(n + E)) ---\n";
  Printf.printf "Nodes: %d   Edges: %d\n"
    (Graph.vertex_count g) (Graph.edge_count g);
  let (c, dt) = time_it (fun () -> components_in_set (all_ids ())) in
  Printf.printf "    (bfs sweep:   %.4f s)\n" dt;
  Printf.printf "Connected components: %d   %s\n"
    c (if c = 1 then "[PASS]" else "[FAIL] world is fragmented")

let verify_hierarchical g =
  Printf.printf "\n--- Hierarchical Verification ---\n";
  let overall = ref true in

  (* Per-region BFS + (optional) eigvals *)
  Array.iter (fun r ->
    let ids = region_ids r in
    let (c, dt_bfs) = time_it (fun () -> components_in_set ids) in
    let bfs_ok = c = 1 in
    if not bfs_ok then overall := false;
    if r.size <= eig_cutoff then begin
      let adj = Graph.adjacency_matrix g in
      let sub = sub_adjacency adj r.offset (r.offset + r.size) in
      let (f, dt_eig) = time_it (fun () -> fiedler_of_adj sub) in
      (* Threshold 1e-9 distinguishes LAPACK noise on a disconnected
         graph (~1e-13) from legitimate tiny Fiedler values of long
         chain-like mazes (π^2/n^2 ~ 1e-5 for n=1000). *)
      let eig_ok = f > 1e-9 in
      if not eig_ok then overall := false;
      Printf.printf "  %-15s n=%4d  bfs=%d (%.4fs)  lambda_2=%.6f (%.2fs)  %s\n"
        r.name r.size c dt_bfs f dt_eig
        (if bfs_ok && eig_ok then "[PASS]" else "[FAIL]")
    end else
      Printf.printf "  %-15s n=%4d  bfs=%d (%.4fs)  lambda_2=(skipped, region>%d)  %s\n"
        r.name r.size c dt_bfs eig_cutoff
        (if bfs_ok then "[PASS]" else "[FAIL]")
  ) regions;

  (* Macro-graph eigvals (tiny, always cheap) *)
  let r = Array.length regions in
  let macro = Owl.Mat.zeros r r in
  List.iter (fun (a, b) ->
    Owl.Mat.set macro a b 1.0;
    Owl.Mat.set macro b a 1.0
  ) !macro_sutures;
  let (f_macro, dt_macro) = time_it (fun () -> fiedler_of_adj macro) in
  let macro_ok = f_macro > 1e-9 in
  if not macro_ok then overall := false;
  Printf.printf "  %-15s R=%d sutures=%d  lambda_2=%.6f (%.4fs)  %s\n"
    "macro-graph" r (List.length !macro_sutures) f_macro dt_macro
    (if macro_ok then "[PASS]" else "[FAIL] <<< region(s) isolated");

  Printf.printf "\nHierarchical verdict: %s\n"
    (if !overall
     then "[PASS] every region connected AND macro-graph connected"
     else "[FAIL] fragmentation detected")

let verify_monolithic g =
  Printf.printf "\n--- Monolithic AGT (O(n^3)) ---\n";
  let n = Graph.vertex_count g in
  if n > monolithic_cutoff then
    Printf.printf
      "Skipped: n=%d exceeds cutoff of %d. Dense eigvals on this size would \
       allocate %dMB and take minutes. This is *exactly* the scaling wall \
       the hierarchical verifier exists to route around.\n"
      n monolithic_cutoff (n * n * 8 / 1024 / 1024)
  else begin
    let adj = Graph.adjacency_matrix g in
    let (f, dt) = time_it (fun () -> fiedler_of_adj adj) in
    Printf.printf "    (full Laplacian eig:   %.4f s)\n" dt;
    Printf.printf "lambda_2 (global Fiedler): %.9f  %s\n"
      f (if f > 1e-9 then "[PASS]" else "[FAIL]")
  end

(* =========================================================================
   8. CLI Game Engine
   ========================================================================= *)

let parse_command raw =
  match String.trim (String.lowercase_ascii raw) with
  | "n" | "north" -> `Move North
  | "s" | "south" -> `Move South
  | "e" | "east"  -> `Move East
  | "w" | "west"  -> `Move West
  | "u" | "up"    -> `Move Up
  | "d" | "down"  -> `Move Down
  | "q" | "quit" | "exit" -> `Quit
  | "" -> `Noop
  | _ -> `Unknown

let rec game_loop current_node =
  let pos = get_pos current_node in
  let region = regions.(region_of_id current_node) in
  let available =
    try Hashtbl.find exits current_node with Not_found -> []
  in

  Printf.printf "\n==================================================\n";
  Printf.printf "ROOM %d [%s]  (%d, %d, %d)\n"
    current_node region.name pos.x pos.y pos.z;
  Printf.printf "--------------------------------------------------\n";
  Printf.printf " [LLM description will go here.]\n\n";

  Printf.printf "Obvious Exits: ";
  if available = [] then Printf.printf "None (You are trapped!)\n"
  else begin
    let sorted =
      List.sort (fun (a, _) (b, _) -> compare (dir_rank a) (dir_rank b)) available
    in
    List.iter
      (fun (d, dest) -> Printf.printf "[%s -> %d] " (string_of_dir d) dest)
      sorted;
    Printf.printf "\n"
  end;
  Printf.printf "==================================================\n";
  Printf.printf "\n> %!";

  match (try Some (read_line ()) with End_of_file -> None) with
  | None -> Printf.printf "\n(EOF) Terminating connection.\n"
  | Some raw ->
      match parse_command raw with
      | `Quit -> Printf.printf "\nThanks for playing!\n"
      | `Noop -> game_loop current_node
      | `Unknown ->
          Printf.printf "\nI don't understand that command.\n";
          game_loop current_node
      | `Move d ->
          (match List.find_opt (fun (dir, _) -> dir = d) available with
           | Some (_, next_node) ->
               Printf.printf "\n>> You walk %s...\n" (string_of_dir d);
               game_loop next_node
           | None ->
               Printf.printf "\n>> You bump into a wall. No exit %s.\n"
                 (string_of_dir d);
               game_loop current_node)

(* =========================================================================
   Entry point
   ========================================================================= *)

let () =
  Printf.printf "Building HUGE Spatially-Embedded World...\n";
  Printf.printf "Target: %d rooms across %d regions on 4 Z-layers.\n"
    total_nodes (Array.length regions);
  let (g, dt) = time_it build_world in
  Printf.printf "Generated in %.3f s.\n\n" dt;

  Printf.printf "--- Region Summary ---\n";
  Array.iter (fun r ->
    Printf.printf "  %-15s  %5d rooms  ids [%d..%d]\n"
      r.name r.size r.offset (r.offset + r.size - 1)) regions;

  Printf.printf "\n--- AI Prompt Payloads (landmark rooms) ---\n";
  print_ai_payload 465 "Capital (Centre)";
  print_ai_payload 479 "Capital (East Gate)";
  print_ai_payload 15  "Capital (South Gate)";
  print_ai_payload 450 "Capital (West Gate)";
  print_ai_payload wood_off  "Dark Woods (Entrance)";
  print_ai_payload swamp_off "Fetid Swamp (Entrance)";
  print_ai_payload mtn_off   "Grey Mountain (Entrance)";
  print_ai_payload d1_off    "Upper Dungeon (Entrance)";
  print_ai_payload d2_off    "Lower Dungeon (Entrance)";
  print_ai_payload abyss_off "The Abyss (Entrance)";

  verify_bfs_global g;
  verify_hierarchical g;
  verify_monolithic g;

  Printf.printf "\nExporting map (this may take a moment at %d nodes)...\n"
    total_nodes;
  let (_, dt_dot) = time_it (fun () ->
    Graph.export_to_dot g
      ~graph_name:"World"
      ~node_attr
      ~edge_attr
      "world_map.dot") in
  Printf.printf "Wrote world_map.dot in %.3f s.\n" dt_dot;
  Printf.printf "(neato rendering of 10k+ nodes is slow; consider 'sfdp -Tpng' instead.)\n";

  (* ---------------------------------------------------------------------
     Diffusion fields: heat rises from the Abyss, light shines from z=0.

     Heat uses Dirichlet with *both* boundaries specified:
       - hot sources (Abyss + a couple Lower Dungeon lava vents)
       - cold clamp (every surface room pinned at 0)
     This turns it into a well-posed harmonic-interpolation problem, so
     the gradient spans the full depth of the world instead of collapsing
     to a tiny hot zone near the sole source.
     --------------------------------------------------------------------- *)
  Printf.printf "\n--- Diffusing scalar fields ---\n";
  let surface_seeds ?(v = 1.0) () =
    let acc = ref [] in
    for id = 0 to total_nodes - 1 do
      if (get_pos id).z = 0 then acc := (id, v) :: !acc
    done;
    !acc
  in
  let heat_seeds =
    (* Hot sources distributed through the Abyss (fully hot volume) and
       scattered as lava channels through the Lower Dungeon.  Seeding every
       N-th room keeps the dense mazes from interpolating down to zero
       between sparse sources. *)
    let hot = ref [] in
    (* Abyss: 1 seed every 60 rooms at ~0.95, plus the entrance at 1.0. *)
    hot := (abyss_off, 1.0) :: !hot;
    let i = ref (abyss_off + 60) in
    while !i < abyss_off + abyss_size do
      hot := (!i, 0.95) :: !hot; i := !i + 60
    done;
    (* Lower Dungeon: 1 lava vent every 150 rooms at 0.55..0.70. *)
    let j = ref d2_off in
    let intensity = ref 0.70 in
    while !j < d2_off + dungeon_l_sz do
      hot := (!j, !intensity) :: !hot;
      j := !j + 150;
      (* Slightly randomize vent strength so the gradient isn't uniformly warm. *)
      intensity := 0.55 +. (0.15 *. float_of_int ((!j / 150) mod 2))
    done;
    (* Cold clamp: every surface room held at 0 to pull the gradient upward. *)
    !hot @ surface_seeds ~v:0.0 ()
  in
  let field_specs : Diffusion.field_spec list = [
    { name = "heat";
      seeds = heat_seeds;
      mode = Diffusion.Dirichlet;
      alpha = 0.98;           (* unused for Dirichlet; kept for consistency *)
      iterations = 100 };
    { name = "light";
      seeds = surface_seeds ~v:1.0 ();
      mode = Diffusion.Dirichlet;
      alpha = 0.0;            (* unused for Dirichlet *)
      iterations = 60 };
  ] in
  let field_results =
    List.map (fun (spec : Diffusion.field_spec) ->
      let (values, raw_min, raw_max), dt =
        time_it (fun () -> Diffusion.diffuse g spec) in
      Printf.printf "  %-8s iters=%d mode=%s  raw=[%.4f, %.4f]  %.3f s\n"
        spec.name spec.iterations
        (match spec.mode with
         | Diffusion.Pulse -> "pulse"
         | Diffusion.Anchored -> "anchored"
         | Diffusion.Dirichlet -> "dirichlet")
        raw_min raw_max dt;
      (spec.name, values)
    ) field_specs
  in

  let regions_json =
    let buf = Buffer.create 512 in
    Buffer.add_char buf '[';
    Array.iteri (fun i r ->
      if i > 0 then Buffer.add_char buf ',';
      Printf.bprintf buf
        {|{"id":%d,"name":"%s","color":"%s","tag":"%s"}|}
        i r.name r.color r.tag
    ) regions;
    Buffer.add_char buf ']';
    Buffer.contents buf
  in
  let node_json i =
    let p = get_pos i in
    Printf.sprintf {|"id":%d,"x":%d,"y":%d,"z":%d,"region":%d|}
      i p.x p.y p.z (region_of_id i)
  in
  let fields_json =
    let buf = Buffer.create (List.length field_results * total_nodes * 8) in
    Buffer.add_char buf '[';
    List.iteri (fun fi (name, values) ->
      if fi > 0 then Buffer.add_char buf ',';
      Buffer.add_string buf {|{"name":"|};
      Buffer.add_string buf name;
      Buffer.add_string buf {|","values":[|};
      Array.iteri (fun i v ->
        if i > 0 then Buffer.add_char buf ',';
        (* 4 significant figures keeps JSON compact without losing
           visible precision in the ramp (256 colors max). *)
        Printf.bprintf buf "%.4f" v
      ) values;
      Buffer.add_string buf "]}"
    ) field_results;
    Buffer.add_char buf ']';
    Buffer.contents buf
  in
  Printf.printf "\nExporting world JSON for web viewer...\n";
  let (_, dt_json) = time_it (fun () ->
    Graph.export_to_json g
      ~regions_json
      ~node_json
      ~edge_kind
      ~fields_json
      "web/public/world.json") in
  Printf.printf "Wrote web/public/world.json in %.3f s.\n" dt_json;

  Printf.printf "\nBooting interface... You materialize at (0,0,0), NW corner of the Capital.\n";
  game_loop 0
