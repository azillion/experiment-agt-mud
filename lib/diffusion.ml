type mode = Pulse | Anchored | Dirichlet

type field_spec = {
  name : string;
  seeds : (int * float) list;
  mode : mode;
  alpha : float;
  iterations : int;
}

(* Precompute neighbor arrays once so the hot loop dereferences [int array]
   instead of walking [int list] cons-cells 80 * n times. *)
let build_adj_arrays g =
  let n = Graph.vertex_count g in
  Array.init n (fun i -> Array.of_list (Graph.neighbors g i))

let diffuse g spec =
  let n = Graph.vertex_count g in
  let adj = build_adj_arrays g in

  (* Seed vector: zero everywhere except at explicit sources. *)
  let t0 = Array.make n 0.0 in
  List.iter (fun (id, v) -> t0.(id) <- v) spec.seeds;

  (* For Dirichlet we need O(1) membership tests to restore pinned values. *)
  let is_seed =
    match spec.mode with
    | Dirichlet ->
      let h = Hashtbl.create (List.length spec.seeds) in
      List.iter (fun (id, _) -> Hashtbl.replace h id ()) spec.seeds;
      (fun i -> Hashtbl.mem h i)
    | Pulse | Anchored -> (fun _ -> false)
  in

  let t = Array.copy t0 in
  let t' = Array.make n 0.0 in

  for _ = 1 to spec.iterations do
    (* Compute neighbor averages into t'. For the common (Anchored/Pulse)
       case we fold neighbors manually to avoid allocating the float array
       that [average_of (Array.map ...)] would produce. *)
    for i = 0 to n - 1 do
      let nbrs = adj.(i) in
      let len = Array.length nbrs in
      let avg =
        if len = 0 then 0.0
        else begin
          let sum = ref 0.0 in
          for k = 0 to len - 1 do sum := !sum +. t.(nbrs.(k)) done;
          !sum /. float_of_int len
        end
      in
      t'.(i) <-
        (match spec.mode with
         | Pulse     -> spec.alpha *. avg
         | Anchored  -> (1.0 -. spec.alpha) *. t0.(i) +. spec.alpha *. avg
         | Dirichlet -> if is_seed i then t0.(i) else avg)
    done;
    (* Swap into t for next iteration. Array.blit is O(n) but avoids
       accidentally holding onto stale references. *)
    Array.blit t' 0 t 0 n
  done;

  (* Min-max normalize to [0,1]. *)
  let lo = ref infinity and hi = ref neg_infinity in
  for i = 0 to n - 1 do
    if t.(i) < !lo then lo := t.(i);
    if t.(i) > !hi then hi := t.(i)
  done;
  let raw_min = !lo and raw_max = !hi in
  let span = raw_max -. raw_min in
  let out =
    if span <= 0.0 then Array.make n 0.0
    else Array.init n (fun i -> (t.(i) -. raw_min) /. span)
  in
  (out, raw_min, raw_max)
