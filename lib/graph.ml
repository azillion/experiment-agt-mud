type t = {
  n : int;
  edges : (int * int) list ref;
}

let create n = { n; edges = ref [] }

let add_edge g i j =
  g.edges := (i, j) :: !(g.edges)

let adjacency_matrix g =
  let m = Owl.Mat.zeros g.n g.n in
  List.iter (fun (i, j) ->
    Owl.Mat.set m i j 1.0;
    Owl.Mat.set m j i 1.0
  ) !(g.edges);
  m

let vertex_count g = g.n
let edge_count g = List.length !(g.edges)

let export_to_dot
    g
    ?(graph_name = "G")
    ?(node_attr = fun _ -> "")
    ?(edge_attr = fun _ _ -> "")
    filename =
  let oc = open_out filename in
  Printf.fprintf oc "graph %s {\n" graph_name;
  Printf.fprintf oc "  node [style=filled, fontname=\"Helvetica\"];\n";

  (* Emit nodes with attributes *)
  for i = 0 to g.n - 1 do
    let attrs = node_attr i in
    if attrs <> "" then
      Printf.fprintf oc "  %d [%s];\n" i attrs
    else
      Printf.fprintf oc "  %d;\n" i
  done;

  (* Emit each undirected edge exactly once *)
  let seen = Hashtbl.create (List.length !(g.edges)) in
  List.iter (fun (i, j) ->
    let a, b = if i <= j then i, j else j, i in
    if not (Hashtbl.mem seen (a, b)) then begin
      Hashtbl.add seen (a, b) ();
      let attrs = edge_attr a b in
      if attrs <> "" then
        Printf.fprintf oc "  %d -- %d [%s];\n" a b attrs
      else
        Printf.fprintf oc "  %d -- %d;\n" a b
    end
  ) !(g.edges);

  Printf.fprintf oc "}\n";
  close_out oc
