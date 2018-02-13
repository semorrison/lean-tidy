import data.list
import data.hash_map
import .edit_distance

open lean
open lean.parser

-- universes t u v w

-- TODO mathlib
def list.flatten {β} : list (list β) → list β
| [] := []
| (h :: t) := h ++ (list.flatten t)

-- TODO mathlib
def option.to_list {α} : option α → list α 
| none := []
| (some a) := [a]

def min_with_position : list ℕ → option (ℕ × ℕ)
| [] := none
| (h :: t) := let min := t.foldl min h in
              let p := (h :: t).index_of min in
              some (min, p)

def min_with_position_2 : list (list ℕ) → option (ℕ × ℕ × ℕ)
| l := match min_with_position l.flatten with
       | none := none
       | (some (min, _)) := let n := l.find_index (λ r, min ∈ r) in
                            match l.nth n with
                            | none := none -- impossible
                            | (some r) := some (min, n, r.index_of min)
                            end
       end

-- TODO PR'd to mathlib as https://github.com/leanprover/mathlib/pull/51
@[simp] lemma append_eq_nil {β} (p q : list β) : (p ++ q) = [] ↔ p = [] ∧ q = [] :=
begin
split,
show (p ++ q) = [] → p = [] ∧ q = [],
{
  intro h,
  split,
  apply list.eq_nil_of_prefix_nil, rw ← h, simp, 
  apply list.eq_nil_of_suffix_nil, rw ← h, simp,
},
show p = [] ∧ q = [] → p ++ q = [],
{
  intros h,
  rw [h.left, h.right],
  refl,
}
end

-- TODO PR'd to mathlib as https://github.com/leanprover/mathlib/pull/51
@[simp] lemma update_nth_eq_nil {β} (l : list β) (n : ℕ) (a : β) : l.update_nth n a = [] ↔ l = [] :=
begin
split,
show list.update_nth l n a = list.nil → l = list.nil, 
{
  induction l,
  case list.nil {
    intros,
    assumption
  },
  case list.cons {
    induction n,
    all_goals { contradiction }
  }
},
-- show l = list.nil → list.update_nth l n a = list.nil,
{
  intros, simp *, refl
}
end


/-
A `partial_graph` represents a partial traversal of a graph, along with a tentative shortest path tree.
Each vertex of the graph is labelled by an `β`.
We also record along with each vertex its parent (this may be revised later, as more of the graph is traversed)
as an index into the prefix-immutable list of traversed vertices.
Along with the parent we record some 'descent_data' of some arbitrary type `γ`,
which we think of as recording how the vertex was generated from its parent (which also may be revised).
At each vertex we record the (current) depth to the root. We use this to decide whether to update parentage data when
the vertex is rediscovered.
-/

structure vertex_data (α : Type) (β : Type) (γ : Type) :=
(compare_on : α)
(data : β)
(descent_data : γ)

structure untraversed_vertex_data (α : Type) (β : Type) (γ : Type) :=
(data : vertex_data α β γ)
(parent : ℕ)
(depth : ℕ)

structure traversed_vertex_data (α : Type) (β : Type) (γ : Type) extends untraversed_vertex_data α β γ :=
(traversed_neighbours : list ℕ)   -- these are indices into traversed_vertices
(untraversed_neighbours : list ℕ) -- these are indices into untraversed_vertices, which does change!

structure partial_graph (α : Type) (β : Type) (γ : Type) :=
(traversed_vertices : list (traversed_vertex_data α β γ))    -- we only ever append to this list, so indices are stable 
(untraversed_vertices : list (untraversed_vertex_data α β γ))
(nonempty : traversed_vertices ≠ [])

attribute [simp] partial_graph.nonempty

structure partial_graph_pair (α : Type) (β : Type) (γ : Type) :=
(graph_1 : partial_graph α β γ)
(graph_2 : partial_graph α β γ)
(connected : bool)
(exhausted : bool)
(tt_distances : list (list ℕ))
(tu_distances : list (list ℕ))
(ut_distances : list (list ℕ))
(uu_distances : list (list ℕ))  -- pairwise distances between untraversed vertices on each graph

variable {α : Type}
variable {β : Type}
variable {γ : Type}

def partial_graph.current_vertex (g : partial_graph α β γ) := g.traversed_vertices.length
def partial_graph.current_vertex_data (g : partial_graph α β γ) := g.traversed_vertices.last g.nonempty

-- We have to use meta here because the recursion can't be justified without much more care.
meta def partial_graph.traversed_vertex_ancestry (g : partial_graph α β γ) : ℕ → list γ 
| 0 := []
| n := match g.traversed_vertices.nth n with
       | none := []
       | (some v) := v.data.descent_data :: (partial_graph.traversed_vertex_ancestry v.parent)
       end
meta def partial_graph.untraversed_vertex_ancestry (g : partial_graph α β γ) : ℕ → list γ 
| n := match g.untraversed_vertices.nth n with
       | none := []
       | (some v) := v.data.descent_data :: (partial_graph.traversed_vertex_ancestry g v.parent)
       end

meta def partial_graph_pair.min_distance (p : partial_graph_pair α β γ) : option (ℕ × option (list γ × list γ)) :=
let tu_min_distance := min_with_position_2 p.tu_distances in
let ut_min_distance := min_with_position_2 p.ut_distances in
let uu_min_distance := min_with_position_2 p.uu_distances in
match tu_min_distance, ut_min_distance, uu_min_distance with
| none, none, none                                     := none
| (some (0, x_tu, y_tu)), _ ,_                         := some (0, some (p.graph_1.traversed_vertex_ancestry   x_tu, p.graph_2.untraversed_vertex_ancestry y_tu))
| _, (some (0, x_ut, y_ut)) ,_                         := some (0, some (p.graph_1.untraversed_vertex_ancestry x_ut, p.graph_2.traversed_vertex_ancestry   y_ut))
| _, _, (some (0, x_uu, y_uu))                         := some (0, some (p.graph_1.untraversed_vertex_ancestry x_uu, p.graph_2.untraversed_vertex_ancestry y_uu))
| (some (d, _, _)), none, none                         := some (d, none)
| none, (some (d, _, _)), none                         := some (d, none)
| none, none, (some (d, _, _))                         := some (d, none)
| (some (d, _, _)), (some (e, _, _)), none             := some (min d e, none)
| (some (d, _, _)), none, (some (e, _, _))             := some (min d e, none)
| none, (some (d, _, _)), (some (e, _, _))             := some (min d e, none)
| (some (d, _, _)), (some (e, _, _)), (some (f, _, _)) := some (min (min d e) f, none)
end

-- we're only ever adding vertices which are neighbours of the last traversed vertex
def add_new_untraversed_vertex (g : partial_graph α β γ) (data : vertex_data α β γ) := {
  untraversed_vertices := g.untraversed_vertices ++ [⟨ data, g.traversed_vertices.length - 1, g.current_vertex_data.depth + 1⟩]
  ..g
}




def update_traversed_vertex (g : partial_graph α β γ) (just_traversed : ℕ) (previously_traversed : ℕ) (descent_data : γ) :=
match g.traversed_vertices.nth previously_traversed with
| none := g
| (some d) := let new_traversed_neighbours := d.traversed_neighbours ++ [g.current_vertex] in
              let new_untraversed_neighbours := d.untraversed_neighbours.erase just_traversed in
              if d.depth > g.current_vertex_data.depth + 1 then
                {
                  traversed_vertices := g.traversed_vertices.update_nth previously_traversed {
                                                                            data := { descent_data := descent_data, .. d.data },
                                                                            traversed_neighbours := new_traversed_neighbours,
                                                                            untraversed_neighbours := new_untraversed_neighbours,
                                                                            parent := g.current_vertex, 
                                                                            depth := g.current_vertex_data.depth + 1
                                                                          },
                  nonempty := by simp,
                .. g }
              else 
                {
                  traversed_vertices := g.traversed_vertices.update_nth previously_traversed {
                                                                            traversed_neighbours := new_traversed_neighbours,
                                                                            untraversed_neighbours := new_untraversed_neighbours,
                                                                          .. d},
                  nonempty := by simp,
                .. g }
end

def update_untraversed_vertex (g : partial_graph α β γ) (n : ℕ) :=
match g.untraversed_vertices.nth n with
| none := g
| (some d) := if d.depth > g.current_vertex_data.depth + 1 then
                { untraversed_vertices := g.untraversed_vertices.update_nth n { parent := g.current_vertex, depth := g.current_vertex_data.depth + 1, .. d}, .. g }
              else 
                g
end

def add_traversed_neighbour_to_current_vertex (g : partial_graph α β γ) (n : ℕ) :=
match g.traversed_vertices.nth n with
| none := g
| (some d) := {
  traversed_vertices := g.traversed_vertices.update_nth g.current_vertex { traversed_neighbours := d.traversed_neighbours ++ [n], ..d },
  nonempty := by simp,
  .. g
}
end

def add_untraversed_neighbour_to_current_vertex (g : partial_graph α β γ) (n : ℕ) :=
match g.traversed_vertices.nth n with
| none := g
| (some d) := {
  traversed_vertices := g.traversed_vertices.update_nth g.current_vertex { untraversed_neighbours := d.untraversed_neighbours ++ [n], ..d },
  nonempty := by simp,
  .. g
}
end

def mark_vertex_traversed_1 (n : ℕ) (k : ℕ) (v : traversed_vertex_data α β γ) : traversed_vertex_data α β γ :=
{
traversed_neighbours   := if n ∈ v.untraversed_neighbours then v.traversed_neighbours ++ [k] else v.traversed_neighbours,
untraversed_neighbours := (v.untraversed_neighbours.remove_all [n]).map(λ m, if m > n then m-1 else m),
..v
}


def mark_vertex_traversed_2 (n : ℕ) (g : partial_graph α β γ) : partial_graph α β γ :=
match g.untraversed_vertices.nth n with
| none := g
| (some d) := {
                traversed_vertices := g.traversed_vertices.map (mark_vertex_traversed_1 n g.traversed_vertices.length) ++ [{ traversed_neighbours := [], untraversed_neighbours := [], .. d}],
                untraversed_vertices := g.untraversed_vertices.remove_nth n,
                nonempty := by simp,
              }
end

/- We've just marked a vertex as traversed, and need to add edges. -/
def process_neighbour [decidable_eq α] (just_traversed : ℕ) (g : partial_graph α β γ) (vertex : vertex_data α β γ) : partial_graph α β γ:=
match (g.traversed_vertices.map(λ d : traversed_vertex_data α β γ, d.data.compare_on)).indexes_of (vertex.compare_on) with
| (n :: _) := -- `a` has already been traversed
              add_traversed_neighbour_to_current_vertex (update_traversed_vertex g just_traversed n vertex.descent_data) n
| [] := -- `a` has not already been traversed
        match (g.untraversed_vertices.map(λ d : untraversed_vertex_data α β γ, d.data.compare_on)).indexes_of (vertex.compare_on) with
        | (n :: _) := -- `a` has already been listed as untraversed
                      add_untraversed_neighbour_to_current_vertex (update_untraversed_vertex g n) n
        | [] := -- we've never seen `a` before!
                add_untraversed_neighbour_to_current_vertex (add_new_untraversed_vertex g vertex) g.untraversed_vertices.length
        end
end

variable {m : Type → Type}

def traverse [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (n : ℕ) (g : partial_graph α β γ) : m (partial_graph α β γ) :=
match g.untraversed_vertices.nth n with
| none := pure g
| (some d) := let g' := mark_vertex_traversed_2 n g in
              do ns ← neighbours d.data.data,
                 pure (ns.foldl (process_neighbour n) g')
end              


   


def pair_traverse_left [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (distance : α → α → ℕ) (x : ℕ) (p : partial_graph_pair α β γ) : m (partial_graph_pair α β γ) :=
do new_graph_1 ← traverse neighbours x p.graph_1,
  let new_tt_distances := p.tt_distances ++ (p.ut_distances.nth x).to_list,
  let new_tu_distances := p.tu_distances ++ (p.uu_distances.nth x).to_list,
  let offset := p.graph_1.untraversed_vertices.length - 1,
  let new_ut_distances := p.ut_distances.remove_nth x ++                            
                          ((new_graph_1.untraversed_vertices.drop offset).map $ λ v_i,
                            p.graph_2.traversed_vertices.map $ λ v_j,
                              distance v_i.data.compare_on v_j.data.compare_on),
  let new_uu_distances := p.uu_distances.remove_nth x ++                            
                          ((new_graph_1.untraversed_vertices.drop offset).map $ λ v_i,
                            p.graph_2.untraversed_vertices.map $ λ v_j,
                              distance v_i.data.compare_on v_j.data.compare_on),
  let connected := if ∃ r ∈ new_ut_distances, 0 ∈ r ∨ ∃ r ∈ new_uu_distances, 0 ∈ r then tt else ff,
  let exhausted := if new_graph_1.untraversed_vertices.length = 0 ∧ p.graph_2.untraversed_vertices.length = 0 then tt else ff,
  pure ⟨ new_graph_1, p.graph_2, connected, exhausted, new_tt_distances, new_tu_distances, new_ut_distances, new_uu_distances ⟩


def pair_traverse_right [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (distance : α → α → ℕ) (y : ℕ) (p : partial_graph_pair α β γ) : m (partial_graph_pair α β γ) :=
do new_graph_2 ← traverse neighbours y p.graph_2,
  let new_tt_distances := (p.tt_distances.zip p.tu_distances).map $ λ q, q.1 ++ (q.2.nth y).to_list,
  let new_ut_distances := (p.ut_distances.zip p.uu_distances).map $ λ q, q.1 ++ (q.2.nth y).to_list,
  let offset := p.graph_2.untraversed_vertices.length - 1,
  let new_tu_distances := (p.tu_distances.zip p.graph_1.traversed_vertices).map   $ λ q, (q.1.remove_nth y) ++ ((new_graph_2.untraversed_vertices.drop offset).map $ λ v, distance q.2.data.compare_on v.data.compare_on),
  let new_uu_distances := (p.uu_distances.zip p.graph_1.untraversed_vertices).map $ λ q, (q.1.remove_nth y) ++ ((new_graph_2.untraversed_vertices.drop offset).map $ λ v, distance q.2.data.compare_on v.data.compare_on),
  let connected := if ∃ r ∈ new_tu_distances, 0 ∈ r ∨ ∃ r ∈ new_uu_distances, 0 ∈ r then tt else ff,
  let exhausted := if p.graph_1.untraversed_vertices.length = 0 ∧ new_graph_2.untraversed_vertices.length = 0 then tt else ff,
  pure ⟨ p.graph_1, new_graph_2, connected, exhausted, new_tt_distances, new_tu_distances, new_ut_distances, new_uu_distances ⟩

def pair_traverse [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (distance : α → α → ℕ) (p : partial_graph_pair α β γ) : m (partial_graph_pair α β γ) :=
if p.connected ∨ p.exhausted then pure p else
match min_with_position_2 p.uu_distances, min_with_position_2 p.tu_distances, min_with_position_2 p.ut_distances with
| none, none, none := /- we're done! -/ pure p
| (some (0, _, _)), _, _ := /- we're done -/ pure p
| _, (some (0, _, _)), _ := /- we're done -/ pure p
| _, _, (some (0, _, _)) := /- we're done -/ pure p
| none, (some _), (some _) := /- impossible -/ pure p
| (some _), none, _ := /- impossible -/ pure p
| (some _), _, none := /- impossible -/ pure p
| none, none, (some (min_ut, x_ut, y_ut)) := do pair_traverse_left neighbours  distance x_ut p
| none, (some (min_tu, x_tu, y_tu)), none := do pair_traverse_right neighbours distance y_tu p
| (some (min_uu, x_uu, y_uu)), (some (min_tu, x_tu, y_tu)), (some (min_ut, x_ut, y_ut)) := if min_uu ≤ min_ut ∧ min_uu ≤ min_tu then
                                                                                            if p.graph_1.untraversed_vertices.length ≤ p.graph_2.untraversed_vertices.length then
                                                                                              do pair_traverse_left neighbours distance x_uu p
                                                                                            else
                                                                                              do pair_traverse_right neighbours distance y_uu p
                                                                                          else
                                                                                            if min_ut ≤ min_tu then
                                                                                              do pair_traverse_left neighbours distance x_ut p
                                                                                            else                                         
                                                                                              do pair_traverse_right neighbours distance y_tu p
end


def partial_graph.root [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (vertex : vertex_data α β γ) : m (partial_graph α β γ) := 
do
 ns ← neighbours vertex.data,
 let ns := ns.filter (λ p, p.compare_on ≠ vertex.compare_on),
  pure {
    traversed_vertices := [{ data := vertex, parent := 0, depth := 0, traversed_neighbours := [], untraversed_neighbours := list.range ns.length}],
    untraversed_vertices := ns.map(λ n, { data := n, parent := 0, depth := 1 }),
    nonempty := by simp
  }

-- FIXME these spin their wheels if n is large.
def breadth_first_search_monadic [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (vertex : vertex_data α β γ) : ℕ → m (partial_graph α β γ)
| 0 := partial_graph.root neighbours vertex
| (n+1) := do previous ← breadth_first_search_monadic n,
              traverse neighbours 0 previous


def depth_first_search_monadic [decidable_eq α] [monad m] (neighbours : β → m (list (vertex_data α β γ))) (vertex : vertex_data α β γ) : ℕ → m (partial_graph α β γ)
| 0 := partial_graph.root neighbours vertex
| (n+1) := do previous ← depth_first_search_monadic n,
              traverse neighbours (previous.untraversed_vertices.length - 1) previous

meta def graph_pair_search_monadic_core [decidable_eq α] 
  (neighbours : β → tactic (list (vertex_data α β γ))) 
  (distance : α → α → ℕ) (limit : ℕ) : ℕ → (partial_graph_pair α β γ) → tactic (partial_graph_pair α β γ)
| 0     p := pure p /- out of time -/
| (n+1) p := do if p.connected ∨ p.exhausted then
                  do tactic.trace format!"search steps : {limit - n}",
                     pure p
                else
                  do next ← pair_traverse neighbours distance p,
                     graph_pair_search_monadic_core n next

meta def graph_pair_search_monadic [decidable_eq α]
  (neighbours : β → tactic (list (vertex_data α β γ))) 
  (distance : α → α → ℕ) 
  (vertex_1 : vertex_data α β γ) 
  (vertex_2 : vertex_data α β γ) (n : ℕ) : tactic (partial_graph_pair α β γ) :=
do 
  graph_1 ← partial_graph.root neighbours vertex_1,
  graph_2 ← partial_graph.root neighbours vertex_2,
  let tt_distances := graph_1.traversed_vertices.map   $ λ v, graph_2.traversed_vertices.map   $ λ w, distance v.data.compare_on w.data.compare_on in
  let tu_distances := graph_1.traversed_vertices.map   $ λ v, graph_2.untraversed_vertices.map $ λ w, distance v.data.compare_on w.data.compare_on in
  let ut_distances := graph_1.untraversed_vertices.map $ λ v, graph_2.traversed_vertices.map   $ λ w, distance v.data.compare_on w.data.compare_on in
  let uu_distances := graph_1.untraversed_vertices.map $ λ v, graph_2.untraversed_vertices.map $ λ w, distance v.data.compare_on w.data.compare_on in
  let connected := if ∃ r ∈ ut_distances, 0 ∈ r ∨ ∃ r ∈ tu_distances, 0 ∈ r ∨ ∃ r ∈ uu_distances, 0 ∈ r then tt else ff in
  let exhausted := if graph_1.untraversed_vertices.length = 0 ∧ graph_2.untraversed_vertices.length = 0 then tt else ff in
    do graph_pair_search_monadic_core neighbours distance n n ⟨ graph_1, graph_2, connected, exhausted, tt_distances, tu_distances, ut_distances, uu_distances ⟩

instance id_monad : monad id := 
begin
refine {
  bind := λ _ _ a f, f a,
  map := λ _ _ f, f,
  pure := λ _ a, a,
  ..
},
intros, refl, intros, refl, intros, refl
end

def breadth_first_search [decidable_eq β] (neighbours : β → list β) (a : β) : ℕ → partial_graph β β ℕ := @breadth_first_search_monadic β β ℕ id _ _ (λ x, (neighbours x).enum.map(λ p, ⟨ p.2, p.2, p.1 ⟩)) ⟨ a, a, 0 ⟩
def depth_first_search [decidable_eq β] (neighbours : β → list β) (a : β) : ℕ → partial_graph β β ℕ := @depth_first_search_monadic β β ℕ id _ _ (λ x, (neighbours x).enum.map(λ p, ⟨ p.2, p.2, p.1 ⟩)) ⟨ a, a, 0 ⟩

#eval (breadth_first_search (λ p : ℕ × ℕ, [(p.1+1,p.2),(p.1,p.2+1)]) (0,0) 15).traversed_vertices.map(λ v : traversed_vertex_data (ℕ × ℕ) (ℕ × ℕ) ℕ, v.data.data)
#eval (breadth_first_search (λ p : ℕ × ℕ, [(p.1+1,p.2),(p.1,p.2+1)]) (0,0) 15).untraversed_vertices.map(λ v : untraversed_vertex_data (ℕ × ℕ) (ℕ × ℕ) ℕ, v.data.data)

#eval (depth_first_search (λ p : ℕ × ℕ, [(p.1+1,p.2),(p.1,p.2+1)]) (0,0) 15).traversed_vertices.map(λ v : traversed_vertex_data (ℕ × ℕ) (ℕ × ℕ) ℕ, v.data.data)

-- knights' moves
def knights := (λ p : ℤ × ℤ, [(p.1+2,p.2+1),(p.1+2,p.2-1),(p.1-2,p.2+1),(p.1-2,p.2-1),(p.1+1,p.2+2),(p.1+1,p.2-2),(p.1-1,p.2+2),(p.1-1,p.2-2)])
#eval (breadth_first_search knights (0,0) 20).traversed_vertices.map(λ v : traversed_vertex_data (ℤ × ℤ) (ℤ × ℤ) ℕ, (v.data.data, v.data.descent_data))
#eval (depth_first_search knights (0,0) 20).traversed_vertices.map(λ v : traversed_vertex_data (ℤ × ℤ) (ℤ × ℤ) ℕ, (v.data.data, v.data.descent_data))

namespace tactic

namespace interactive
open interactive interactive.types expr


private meta def list_while' {β} (f : ℕ → tactic β) (P : ℕ → β → bool) : ℕ → β → bool → list β → tactic (list β)
| _ _ ff t := pure t
| n a tt t := (do g ← f (n+1), list_while' (n+1) g (P (n+1) g) (a :: t)) <|> pure (a :: t)

meta def list_while {β} (f : ℕ → tactic β) (P : ℕ → β → bool) : tactic (list β) :=
(do 
  g ← f 0,
  r ← (list_while' f P 0 g (P 0 g) []),
  pure r.reverse) <|> pure []
 
meta def simp_as_rewrite (source : expr) : tactic (list (vertex_data string expr (ℕ × ℕ × expr))) :=
(do (s, u) ← tactic.mk_simp_set ff [] [],
   (target, proof) ← tactic.simplify s [] source {},
   pp ← pp target,
   let pp := pp.to_string,
   pure [ { vertex_data . compare_on := pp, data := target, descent_data := (0, 0, proof) } ]) <|> pure []

meta def rewrite_without_new_mvars (h : expr) (e : expr) (cfg : rewrite_cfg := {}) : tactic (expr × expr × list expr) :=
do n_before ← num_goals,
   (new_t, prf, metas) ← rewrite_core h e cfg,
   try_apply_opt_auto_param cfg.to_apply_cfg metas,
   n_after ← num_goals,
   guard (n_before = n_after),
   return (new_t, prf, metas)

meta def all_rewrites (rs: list (expr × bool)) (source : expr) : tactic (list (vertex_data string expr (ℕ × ℕ × expr))) :=
do table ← rs.enum.mmap $ λ e,
   (do results ← (list_while (λ n, do v ← rewrite_without_new_mvars e.2.1 source {symm := e.2.2, occs := occurrences.pos [n+1]}, pure (n, v)) (λ n x, tt /- do we need to discard any? or just wait until rewrite fails? -/)),
      results.mmap (λ result, do
        let (n, target, proof, mvars) := result,
        -- trace ((e, n), target),
        pp ← pp target,
        let pp := pp.to_string,
        pure { vertex_data . compare_on := pp, data := target, descent_data := (e.1 + 1, n, proof) })),
   by_simp ← simp_as_rewrite source,
   pure (by_simp ++ table.flatten) 

-- meta def rewrite_search_core (rs : list expr) (n : ℕ) (start : expr) := 
-- do pp ← pp start,
--    let pp := pp.to_string,
--    @depth_first_search_monadic _ _ _ tactic _ _ (all_rewrites rs) ⟨ pp, start, (0, 0, start /- this should be refl or something... -/) ⟩ n

-- meta def rewrite_search (rs: parse rw_rules) (n : ℕ) (e : tactic expr := target): tactic unit :=
-- do rs ← rs.rules.mmap $ λ r, to_expr' r.rule,
--    t ← e,
--    result ← rewrite_search_core rs n t,
--    trace (result.traversed_vertices.map (λ v : traversed_vertex_data _ _ _, v.data.compare_on)),
--   --  trace (result.untraversed_vertices.map (λ v : untraversed_vertex_data _ _ _, v.data.compare_on)),
--    skip

meta def rewrite_search_core (rs : list (expr × bool)) (n : ℕ) (e1 e2 : expr) := 
do pp1 ← pp e1,
   let pp1 := pp1.to_string,
   pp2 ← pp e2,
   let pp2 := pp2.to_string,
   e1refl ← mk_eq_refl e1,
   e2refl ← mk_eq_refl e2,
   graph_pair_search_monadic (all_rewrites rs) string_edit_distance ⟨ pp1, e1, (0, 0, e1refl) ⟩ ⟨ pp2, e2, (0, 0, e2refl) ⟩ n



meta def rewrite_search_aux (rs: list (expr × bool)) (n : ℕ := 1000) : tactic unit :=
do t ← target,
   (lhs, rhs) ← match t with
     | `(%%lhs = %%rhs) := pure (lhs, rhs)
     | _ := fail "goal is not an equality"
     end,
   result ← rewrite_search_core rs n lhs rhs,
   trace (result.graph_1.traversed_vertices.map (λ v : traversed_vertex_data _ _ _, v.data.compare_on)),
  --  trace (result.graph_1.untraversed_vertices.map (λ v : untraversed_vertex_data _ _ _, v.data.compare_on)),
   trace (result.graph_2.traversed_vertices.map (λ v : traversed_vertex_data _ _ _, v.data.compare_on)),
  --  trace (result.graph_2.untraversed_vertices.map (λ v : untraversed_vertex_data _ _ _, v.data.compare_on)),
  --  trace result.tt_distances,
  --  trace result.tu_distances,
  --  trace result.ut_distances,
  --  trace result.uu_distances,
   match result.min_distance with
   | none := fail "exhausted rewrites without reaching equality"
   | (some (0, some (l₁, l₂))) := do let eq₁ := l₁.map(λ p, p.2.2),
                                     let eq₂ := l₂.map(λ p, p.2.2),
                                    --  trace eq₁,
                                    --  trace eq₂,
                                     eq₂_symm ← eq₂.mmap mk_eq_symm,
                                     refl ← mk_eq_refl lhs,
                                     eq ← (eq₁.reverse ++ eq₂_symm).mfoldl mk_eq_trans refl,
                                    --  trace eq,
                                     tactic.exact eq
   | (some (d, none)) := fail "ran out of time without reaching equality"
   | (some (d, _)) := fail "unreachable code"
   end

meta def rewrite_search (rs: parse rw_rules) (n : ℕ := 1000) : tactic unit :=
do rs ← rs.rules.mmap (λ r, do e ← to_expr' r.rule, pure (e, r.symm)),
   rewrite_search_aux rs n

meta def rewrite_search_using (a : name) (n : ℕ := 1000) : tactic unit :=
do names ← attribute.get_instances a,
   trace names,
   exprs ← names.mmap $ mk_const,
   let pairs := exprs.map (λ e, (e, ff)) ++ exprs.map (λ e, (e, tt)),
   rewrite_search_aux pairs n

end interactive
end tactic


open tactic.interactive

@[ematch] private lemma foo : [0] = [1] := sorry
@[ematch] private lemma bar1 : [1] = [2] := sorry
@[ematch] private lemma bar2 : [3] = [2] := sorry
@[ematch] private lemma bar3 : [3] = [4] := sorry

private lemma turkle : [[0],[0]] = [[4],[4]] :=
begin
rewrite_search [foo, bar1, ← bar2, bar2, ← bar3],
end

private lemma turkle' : [[0],[0]] = [[4],[4]] :=
begin
rewrite_search_using `ematch,
end

@[ematch] private lemma foo' (n : ℕ) : [n, n] = [n+1, n+1] := sorry

private lemma turkle'' : [0,0] = [1,1] :=
begin
rewrite_search_using `ematch,
end
 