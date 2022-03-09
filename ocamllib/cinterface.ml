open Bigarray
open Astlib
open Astutil
open Ast
open Int32

(* Get nodes array from C *)
external get_nodes: unit -> (int32, int32_elt, c_layout) Array1.t = "pass_nodes" 

(* Pass nodes array to C *)
external pass_nodes: (int32, int32_elt, c_layout) Array1.t -> unit = "get_nodes"

(* Get edges array from C *)
external get_edges: unit -> (int32, int32_elt, c_layout) Array2.t = "pass_edges"

(* Pass edges array to C *)
external pass_edges: (int32, int32_elt, c_layout) Array2.t -> unit = "get_edges"

(* Get unit tests from C *)
external get_unit_tests: unit -> (int32, int32_elt, c_layout) Array2.t = "pass_unit_tests"

(* Pass unit tests to C *)
external pass_unit_tests: (int32, int32_elt, c_layout) Array2.t -> unit = "get_unit_tests"

(* Convert nodes from Bigarray to OCaml list *)
let array1_to_list (arr : (int32, int32_elt, c_layout) Array1.t) : int list =
  let rec array1_to_list_aux (arr: (int32, int32_elt, c_layout) Array1.t) (len : int) : int list = 
    if len > 0 then
       array1_to_list_aux arr (len - 1) @ [to_int (arr.{len - 1})]
    else
      []
  in
  array1_to_list_aux arr (Array1.dim arr)

(* Convert OCaml nodes list to Bigarray *)
let list_to_array1 (l : int list) : (int32, int32_elt, c_layout) Array1.t = 
  let nodes = Array1.create Int32 c_layout (List.length l) in
  let rec list_to_array1_aux (l : int list) (arr : (int32, int32_elt, c_layout) Array1.t) (count : int) : unit = 
    match l with
      | [] -> ()
      | hd :: tl ->
        let _ = arr.{count} <- (of_int hd) in 
        list_to_array1_aux tl arr (count + 1)
  in
  let _ = list_to_array1_aux l nodes 0 in
  nodes

(* Convert edges from Bigarray to OCaml list *)
let edge_to_list (arr : (int32, int32_elt, c_layout) Array2.t) : (int * int * int) list = 
  let rec edge_to_list_aux (arr: (int32, int32_elt, c_layout) Array2.t) (len : int) : (int * int * int) list = 
    if len > 0 then
      (to_int arr.{len - 1, 0}, to_int arr.{len - 1, 1}, to_int arr.{len - 1, 2}) :: edge_to_list_aux arr (len - 1)
    else
      []
  in
  edge_to_list_aux arr (Array2.dim1 arr)

(* Convert OCaml edges list to Bigarray *)
let list_to_edge (l : (int * int * int) list) : (int32, int32_elt, c_layout) Array2.t = 
  let edges = Array2.create Int32 c_layout (List.length l) 3 in
  let rec list_to_edge_aux (l : (int * int * int) list) (arr : (int32, int32_elt, c_layout) Array2.t) (count : int) : unit = 
    match l with
      | [] -> ()
      | (start, stop, index) :: tl -> 
        let _ = arr.{count, 0} <- (of_int start) in
        let _ = arr.{count, 1} <- (of_int stop) in
        let _ = arr.{count, 2} <- (of_int index) in
        list_to_edge_aux tl arr (count + 1)
  in
  let _ = list_to_edge_aux l edges 0 in
  edges

(* Convert unit tests from Bigarray to OCaml list *)
let tests_to_list (arr : (int32, int32_elt, c_layout) Array2.t) : (int * int) list = 
  let rec tests_to_list_aux (arr: (int32, int32_elt, c_layout) Array2.t) (len : int) : (int * int) list = 
    if len > 0 then
      (to_int arr.{len - 1, 0}, to_int arr.{len - 1, 1}) :: tests_to_list_aux arr (len - 1)
    else
      []
  in
  tests_to_list_aux arr (Array2.dim1 arr)

(* Convert OCaml unit tests to Bigarray *)
let list_to_tests (l : (int * int) list) : (int32, int32_elt, c_layout) Array2.t = 
  let tests = Array2.create Int32 c_layout (List.length l) 2 in
  let rec list_to_edge_aux (l : (int * int) list) (arr : (int32, int32_elt, c_layout) Array2.t) (count : int) : unit = 
    match l with
      | [] -> ()
      | (input, output) :: tl -> 
        let _ = arr.{count, 0} <- (of_int input) in
        let _ = arr.{count, 1} <- (of_int output) in
        list_to_edge_aux tl arr (count + 1)
  in
  let _ = list_to_edge_aux l tests 0 in
  tests

(* change_ast function that will be called by C *)
let change_ast_c (root : int) (action : int) : int =
  let nodes = array1_to_list (get_nodes ()) in
  let edges = edge_to_list (get_edges ()) in
  let e = c_to_expr nodes edges root in
  let action = Action.tag_to_action action in
  let ((nodes, edges), root) = expr_to_c (change_ast e action) in (* TODO : implement a function with type int -> Action.t *)
  pass_nodes (list_to_array1 nodes);
  pass_edges (list_to_edge edges);
  root


(* run_unittests function that will be called by C *)
let run_unit_tests_c (root : int) : bool =
  let tests = tests_to_list (get_unit_tests ()) in
  let nodes = array1_to_list (get_nodes ()) in
  let edges = edge_to_list (get_edges ()) in
  let e = c_to_expr nodes edges root in
  run_unit_tests tests e

(* load_assignment function that will be called by C *)
let load_tests_c (assignment : int) : unit =
  let unit_tests = load_tests "data" assignment in
  pass_unit_tests (list_to_tests unit_tests)

(* load_assignment function that will be called by C *)
let load_starter_code_c (assignment : int) (index : int) : int =
  let e = load_starter_code "data" assignment index in
  let ((nodes, edges), root) = expr_to_c e in
  let _ = pass_nodes (list_to_array1 nodes) in
  let _ = pass_edges (list_to_edge edges) in
  root

(* For debugging use *)
let print_stuff (x : unit) : string =
  let nodes = array1_to_list (get_nodes ()) in
  List.fold_right (fun hd acc -> string_of_int hd ^ " " ^ acc) nodes ""

let _ = Callback.register "run_unit_tests" run_unit_tests_c
let _ = Callback.register "change_ast" change_ast_c
let _ = Callback.register "load_tests" load_tests_c
let _ = Callback.register "load_starter_code" load_starter_code_c
let _ = Callback.register "print_stuff" print_stuff