type t

val create : int -> t
val add_edge : t -> int -> int -> unit
val adjacency_matrix : t -> Owl.Mat.mat
val vertex_count : t -> int
val edge_count : t -> int

val export_to_dot :
  t ->
  ?graph_name:string ->
  ?node_attr:(int -> string) ->
  ?edge_attr:(int -> int -> string) ->
  string ->
  unit

val export_to_json :
  t ->
  ?regions_json:string ->
  ?node_json:(int -> string) ->
  ?edge_kind:(int -> int -> string) ->
  string ->
  unit
