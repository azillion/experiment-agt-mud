(** Scalar-field diffusion over an undirected graph.

    Conceptually this is the iteration t' = alpha * P * t where
    P = D^-1 * A (random-walk transition matrix), but implemented
    by iterating directly over the adjacency list so cost is O(E)
    per step regardless of graph sparsity. *)

type mode =
  | Pulse      (** t' = alpha * avg(neighbors t).  Sources fade over time. *)
  | Anchored   (** t' = (1-alpha) * seed + alpha * avg(neighbors t).
                  PageRank-style: sources remain lit, smooth gradient. *)
  | Dirichlet  (** Seeded nodes are pinned to their initial value each step;
                  others diffuse freely.  Crisp boundary conditions. *)

type field_spec = {
  name : string;
  seeds : (int * float) list;  (** (node_id, initial value) pairs *)
  mode : mode;
  alpha : float;               (** mixing factor; unused when mode = Dirichlet *)
  iterations : int;
}

(** Run the diffusion to completion.

    Returns [(normalized_values, raw_min, raw_max)] where
    [normalized_values] is an array of length [Graph.vertex_count g]
    rescaled to the interval [0, 1].  If the raw field is constant
    the normalized array is all zeros. *)
val diffuse :
  Graph.t -> field_spec -> float array * float * float
