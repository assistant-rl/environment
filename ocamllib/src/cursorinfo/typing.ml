(* Synthesis and Analysis *)

open Type

let rec get_common_type (t1 : Type.p_t) (t2 : Type.p_t) : Type.p_t option =
  if Type.consistent t1 t2
  then
    match (t1, t2) with
    | Type.Hole, t | t, Type.Hole -> Some t
    | Type.Int, Type.Int -> Some Type.Int
    | Type.Bool, Type.Bool -> Some Type.Bool
    | Type.Arrow (t1_l, t1_r), Type.Arrow (t2_l, t2_r) -> (
        let t1 = get_common_type t1_l t2_l in
        let t2 = get_common_type t1_r t2_r in
        match (t1, t2) with
        | Some t1, Some t2 -> Some (Type.Arrow (t1, t2))
        | _ -> None)
    | Type.Prod (t1_l, t1_r), Type.Prod (t2_l, t2_r) -> (
        let t1 = get_common_type t1_l t2_l in
        let t2 = get_common_type t1_r t2_r in
        match (t1, t2) with
        | Some t1, Some t2 -> Some (Type.Prod (t1, t2))
        | _ -> None)
    | Type.List t1, Type.List t2 -> (
        let t = get_common_type t1 t2 in
        match t with Some t -> Some (Type.List t) | _ -> None)
    | _ -> None
  else None

let rec pattern_type (p : Pattern.p_t) : Type.p_t =
    match p with
    | Const (Int _) -> Type.Int
    | Const (Bool _) -> Type.Bool
    | Const (Nil _) -> Type.List Type.Hole
    | Var _ -> Type.Hole
    | List (p1, p2) -> 
        let t1 = pattern_type p1 in
        let t2 = pattern_type p2 in
        begin match t2 with
        | Type.Hole -> Type.List t1
        | Type.List t2 -> 
            let t = get_common_type t1 t2 in
            begin match t with
            | Some t -> Type.List t
            | None -> raise (Failure "List pattern type error")
            end
        | _ -> raise (Failure "List pattern type error")
        end
    | Wild -> Type.Hole

(* Return Some t if t is the common type of the rules. Otherwise, return None *)
let pattern_common_type (rules : (Pattern.t * Expr.t) list) : Type.p_t option = 
    let pattern_common_type_aux (acc : Type.p_t option) (rule : Pattern.t * Expr.t) : Type.p_t option =
        match acc with
        | None -> None
        | Some t -> 
            let (p, _) = rule in
            get_common_type t (pattern_type (Pattern.strip p))
    in
    List.fold_left pattern_common_type_aux (Some Type.Hole) rules

let rec synthesis (context : Context.t) (e : Expr.t) : Type.p_t option =
  (*given an expression and its type-context, infer its type by looking
     at its children, if possible *)
    match e.node with
    (*match epxression based on type (and operation for unops and binops)*)
    | EVar x -> Context.lookup context x
    | EConst c -> 
        begin match c with
        | Int _ -> Some Int
        | Bool _ -> Some Bool
        | Nil -> Some (List Hole)
        end
    | EUnOp (OpNeg, arg) ->
        (* negation: if child is int, expr has same type *)
        if analysis context arg Int then Some Int else None
    | EBinOp (argl, (OpPlus | OpMinus | OpTimes | OpDiv), argr) ->
        (*arithmetic operations: if we see an int, return an int *)
        if analysis context argl Int && analysis context argr Int
        then Some Int
        else None
    | EBinOp (argl, (OpGt | OpGe | OpLt | OpLe | OpEq | OpNe), argr) ->
        (*comparasons: int-> bool*)
        if analysis context argl Int && analysis context argr Int
        then Some Bool
        else None
    | EBinOp (arrow, OpAp, arg) -> (
        match synthesis context arrow with
        | Some (Arrow (in_t, out_t)) ->
            if analysis context arg in_t then Some out_t else None
        | Some Hole -> if analysis context arg Hole then Some Hole else None
        | _ -> None)
    | EBinOp (hd, OpCons, tl) -> (
        match synthesis context tl with
        | Some (List list_t) ->
            if analysis context hd list_t then Some (List list_t) else None
        | Some Hole -> if analysis context hd Hole then Some (List Hole) else None
        | _ -> None)
    | EPair (l_pair, r_pair) -> (
        match (synthesis context l_pair, synthesis context r_pair) with
        | Some l_t, Some r_t -> Some (Prod (l_t, r_t))
        | _ -> None)
    | EIf (econd, ethen, eelse) ->
        if analysis context econd Bool
        then
        let tthen = synthesis context ethen in
        let telse = synthesis context eelse in
        match (tthen, telse) with
        | Some tthen, Some teelse -> get_common_type tthen teelse
        | _ -> None
        else None
    | ELet (varn, dec, body) -> (
        match synthesis context dec with
        | Some var_t -> synthesis (Context.extend context (varn, var_t)) body
        | _ -> None)
    | EFun (varn, vart, body) -> (
        let vart = Type.strip vart in
        match synthesis (Context.extend context (varn, vart)) body with
        | Some outtype -> Some (Arrow (vart, outtype))
        | _ -> None)
    | EFix (varn, vart, body) ->
        let vart = Type.strip vart in
        if analysis (Context.extend context (varn, vart)) body vart
        then Some vart
        else None
    | EHole -> Some Hole
    | EMatch (escrut, rules) -> 
        begin match synthesis context escrut with
        | Some tscrut -> 
            let t_rules = pattern_common_type rules in
            begin match t_rules with
            | Some t_rules -> 
                if Type.consistent tscrut t_rules 
                then 
                else None
            | None -> None
            end
        | None -> None
        end
    | EList ()

and analysis (context : Context.t) (e : Expr.t) (targ : Type.p_t) : bool =
  (* given an epxression and an expected type,
      return a bool representing whether that's correct*)
  match e.node with
  | EFun (varn, vart, expr) -> (
      let vart = Type.strip vart in
      match synthesis (Context.extend context (varn, vart)) expr with
      | Some etyp -> Type.consistent etyp targ
      | None -> false)
  | EFix (varn, vart, arg) ->
      let vart = Type.strip vart in
      Type.consistent vart targ && analysis context arg targ
  | EPair (lpair, rpair) -> (
      match targ with
      | Prod (l_t, r_t) ->
          analysis context lpair l_t && analysis context rpair r_t
      | Hole -> analysis context lpair Hole && analysis context rpair Hole
      | _ -> false)
  | EIf (argl, argc, argr) ->
      (* for if statements, first arg is expected to be a bool,
         and second and third are expected to match *)
      analysis context argl Bool && analysis context argc targ
      && analysis context argr targ
  | ELet (varn, def, body) -> (
      (* for variable definitions, add variable type to context*)
      match synthesis context def with
      | Some vart -> analysis (Context.extend context (varn, vart)) body targ
      | None -> false)
  | _ -> (
      match synthesis context e with
      | None -> false
      | Some expt -> Type.consistent expt targ)
(* this handles all the other cases*)
