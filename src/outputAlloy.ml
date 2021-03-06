(*
 * Event Structure Compiler
 * Copyright (c) 2017 Simon Cooksey
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *)

open RelateEventStructure
open TranslateLocations
open EventStructure
open OutputHelpers


exception AlloyOutputException of string

let rec show_event labs var_map (E id) =
  match labs with
  | L (E eid, Read (Val v, Loc src, Loc dst)) :: _ when id = eid ->
    let src_loc = find_loc var_map src in
    let dst_loc = find_loc var_map dst in
    Format.sprintf "%s_R%s%d_%s" (pick_char id) src_loc v dst_loc
  | L (E eid, Write (Val v, Loc dst)) :: _ when id == eid ->
    let dst_loc = find_loc var_map dst in
    Format.sprintf "%s_W%s%d" (pick_char id) dst_loc v
  | L (E eid, Init) :: _ when id == eid ->
    pick_char id
  | _ :: xs -> show_event xs var_map (E id)
  | [] ->
    raise (AlloyOutputException "Event found with no matching label. Labels are incomplete.")

let show_label var_map label =
  match label with
  | L (event, Read (Val v, Loc src, Loc dst)) ->
    let src_loc = find_loc var_map src in
    let dst_loc = find_loc var_map dst in
    Format.sprintf "%s in MemoryEventStructure.R /* %s = R%s%d */" (show_event [label] var_map event) dst_loc src_loc v
  | L (event, Write (Val v, Loc dst)) ->
      let dst_loc = find_loc var_map dst in
      Format.sprintf "%s in MemoryEventStructure.W /* W%s%d */" (show_event [label] var_map event) dst_loc v
  | L (event, Init) -> String.concat "" [show_event [label] var_map event; " in MemoryEventStructure.I"]
  | _ -> ""

let show_relation labs var_map (left, right) =
  String.concat "->" [show_event labs var_map left; show_event labs var_map right]

let rec ev_with f v labs =
  match labs with
  | x::xs when (f v x) -> x
  | _::xs -> ev_with f v xs
  | [] -> raise (AlloyOutputException "invarient violated in alloy output")

let rec print_unrelated fmt f prop var_map vals labs =
  match vals with
  | p::xs ->
    let h = ev_with f p labs in
    let a = List.filter (fun x ->
      let L(_, y) = x in
      not (f p x) &&  not (is_init y)
    ) labs in
    let _ = List.map (fun x ->
      Format.fprintf fmt "    and %s->%s not in MemoryEventStructure.%s\n"
        (show_event labs var_map (strip_label h))
        (show_event labs var_map (strip_label x))
        prop
    ) a in
    print_unrelated fmt f prop var_map xs labs
  | _ -> ()

(* Don't look too hard, eh? *)
let print_alloy fmt var_map alloy_path events labels rels req =
  Format.fprintf fmt "module event_structures/examples\n";
  Format.fprintf fmt "open %s/event_structures/event_structure\n" alloy_path;
  Format.fprintf fmt "open %s/event_structures/configuration\n\n" alloy_path;
  Format.fprintf fmt "pred output { \n";
  Format.fprintf fmt "     some disj %s : E | \n    " (String.concat ", " (List.map (show_event labels var_map) events));

  Format.fprintf fmt "    %s" (String.concat "\n    and " (List.map (show_label var_map) labels));

  let order, conflict = rels in
  Format.fprintf fmt "\n\n   and MemoryEventStructure.O = ^(%s" (String.concat " + " (List.map (show_relation labels var_map) order));
  Format.fprintf fmt ") + \n    (iden :> (%s))\n\n" (String.concat " + " (List.map (show_event labels var_map) events));
  Format.fprintf fmt "    and let ord = MemoryEventStructure.O | \n";
  Format.fprintf fmt "    MemoryEventStructure.C =\n";

  Format.fprintf fmt "        symmClosure[%s" (String.concat " + "
  (List.map (fun (l, r) ->
    Format.sprintf "(%s.ord->%s.ord)" (show_event labels var_map l) (show_event labels var_map r)
  ) conflict));

  Format.fprintf fmt "]\n";

  let locations = find_locations labels in
  let sloc = List.map (fun l ->
    List.map strip_label (List.filter (same_location l) labels)
  ) locations in

  let slocr = List.map (fun x ->
    List.flatten (List.map (fun p ->
        List.map (fun q ->
          (p, q)
        ) x
      ) x
    )
  ) sloc in

  let values = find_values labels in
  let sval = List.map (fun l ->
    List.map strip_label (List.filter (same_value l) labels)
  ) values in

  let svalr = List.map (fun x ->
    List.flatten (List.map (fun p ->
        List.map (fun q ->
          (p, q)
        ) x
      ) x
    )
  ) sval in

  let _ = List.map (fun (l,r) ->
    Format.fprintf fmt "    and %s->%s in MemoryEventStructure.loc\n" (show_event labels var_map l) (show_event labels var_map r)
  ) (List.flatten slocr) in

  print_unrelated fmt (same_location) "loc" var_map locations labels;

  let _ = List.map (fun (l,r) ->
    Format.fprintf fmt "    and %s->%s in MemoryEventStructure.val\n" (show_event labels var_map l) (show_event labels var_map r)
  ) (List.flatten svalr) in

  print_unrelated fmt (same_value) "val" var_map values labels;


  let z = ev_with (same_value) 0 labels in
  Format.fprintf fmt "    and %s in MemoryEventStructure.zero\n" (show_event labels var_map (strip_label z));

  Format.fprintf fmt "    and some MaxConfig\n";
  Format.fprintf fmt "    and (";
  let rec print_constraints fmt cs =
    match cs with
    | [] -> []
    | c::cs ->
      let r = List.map strip_label c in
      Format.asprintf "((%s) in MaxConfig.c_ev)" (
          String.concat "+" (List.map (show_event labels var_map) r)
      ) :: print_constraints fmt cs
  in

  Format.fprintf fmt "%s" ((String.concat "\n    or ") (print_constraints fmt req));
  Format.fprintf fmt ")\n\n";

  Format.fprintf fmt "}\n";

  Format.fprintf fmt "\n\nrun output for %d but 1 MaxConfig\n" (List.length events);
  ()
