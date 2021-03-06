(*
 * Event Structure Compiler
 * Copyright (c) 2017 Simon Cooksey, Scott Owens
 *
 * This portion of the software is derived from Scott Owens' sample compiler.
 *
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


(**
 * Compiles Jeffrey style programs into event-structures
 *)

open RelateEventStructure

exception CompileException of string

let print_tokens = ref false;;
let alloy_path = ref ".";;
let format = ref None;;
let infile_ref = ref None;;
let outfile_ref = ref None;;
let max_value = ref 1;;
let long_names = ref false;;
let use_stdin = ref false;;
let use_stdout = ref false;;
let output_format : string option ref = ref None;;
let options = Arg.align ([
  ("--print-tokens", Arg.Set print_tokens, " print the tokens as they are tokenised.");
  ("-f", Arg.String (fun f -> format := Some(f)), " choose output format by giving a file extension e.g. `-f dot', will be inferred from filenames if not given.");
  ("--alloy-path", Arg.Set_string alloy_path, " set the path that the alloy model exists at.");
  ("--values", Arg.Set_int max_value, " set the max value (V) such that the modeled V are in {0..V}");
  ("-V", Arg.Set_int max_value, " set the max value (V) such that the modeled V are in {0..V}");
  ("--long-names", Arg.Set long_names, " use long event names in output e.g. `c_Rx1_r2'.");
  ("--use-stdin", Arg.Set use_stdin, " read the input from standard in rather than a file");
  ("--use-stdout", Arg.Set use_stdout, "  write the output to stdout rather than to a file");
]);;

let usage_msg = "compile.byte [options] infile [outfile]"

let _ =
  Arg.parse options
    (fun s ->
       match !infile_ref, !use_stdin with
       | None, false ->
         infile_ref := Some s
       | _, _ -> (match !outfile_ref with
         | None -> outfile_ref := Some s
         | Some s'' -> (Printf.eprintf "Error: specified 2 output files %s and %s" s'' s; exit 1)
         )
    )
    usage_msg

let filename =
 match !infile_ref, !use_stdin with
  | None, false -> (Arg.usage options usage_msg; exit 1)
  | Some filename, false -> filename
  | _, true -> "stdin";;

let input = match !infile_ref, !use_stdin with
  | None, false -> (Arg.usage options usage_msg; exit 1)
  | Some filename, false -> Std.input_file filename
  | _, true -> Std.input_all stdin
in
let tokens = Tokeniser.tokenise input 0 1 in

let format_tok (a, _) =
  let fmt = (format_of_string "'%s' ") in
  Printf.printf fmt (Tokeniser.show_token a);
  true
in

let _ = if !print_tokens then
  List.for_all format_tok tokens
  else
    true
in

let rec range x =
  match x with
  | x when x > 0 -> x :: (range (x - 1))
  | x -> [x]
in

let parsed_program = Parser.parse_program tokens in
let max_value = ref (match (Parser.getVals ()) with
    0  -> !max_value
  | n -> n
) in

let translated_program, var_map = TranslateLocations.translate_statements_vm parsed_program in
let es = EventStructure.read_ast ~values:(range !max_value) translated_program in

let es, consts = Constraints.extract_constraints es in
let evs, labs, rels = RelateEventStructure.read_es (EventStructure.Comp (EventStructure.Init, es)) [] [] ([],[]) in

(* It's much nicer if we sort the events and labels *)
let labs = List.sort (fun (L ((E a), _)) (L ((E b), _)) ->
  compare a b
) labs in

let evs = List.sort (fun (E a) (E b) ->
  compare a b
) evs in

let output_fmt =
  match !outfile_ref with
  | Some fn ->
    let oc = open_out fn in
    Format.make_formatter (Pervasives.output oc) (fun () -> Pervasives.flush oc)
  | None -> Format.std_formatter
in

let rec n_cartesian_product l =
  match l with
  | [] -> [[]]
  | h :: t ->
      let rest = n_cartesian_product t in
      List.concat
        (List.map (fun i -> List.map (fun r -> i :: r) rest) h)
in

let consts = Constraints.compile_constraints consts var_map in
let (exp, forb) = Constraints.find_satisfying labs consts ([], []) in
let expected_labels = n_cartesian_product exp in
let forbidden_labels = n_cartesian_product forb in
let test_name = Filename.remove_extension (Filename.basename filename) in

let rec find_label e labs lbs =
  match labs with
  | (L (_, ev) as lab)::labs when
    EventStructure.equal_ev_s e ev -> (lbs@labs, lab)
  | l::labs -> find_label e labs (l::lbs)
  | []-> raise (CompileException "Internal compiler error, labels appear incomplete.")
in

let pc = EventStructure.get_pc () in
let rec build_pc labels pc =
  match pc with
  | (l, r)::pcs ->
    let labels, L(E l, _) = find_label l labels [] in
    let labels, L(E r, _) = find_label r labels [] in
    (E l, E r) :: build_pc labels pcs
  | [] -> []
in
let pc = build_pc labs pc in

let handle_extension extension =
  begin match extension with
  | ".thy" ->
    OutputIsabelle.print_isabelle output_fmt (!long_names) var_map test_name evs labs rels pc (expected_labels, forbidden_labels)
  | ".als" ->
    OutputAlloy.print_alloy output_fmt var_map (!alloy_path) evs labs rels (exp @ forb)
  | ".dot" ->
    OutputGraphviz.print_graphviz output_fmt (!long_names) var_map test_name evs labs rels pc []
  | ".tikz" | ".tex" ->
    OutputTikz.print_tikz output_fmt (!long_names) var_map test_name evs labs rels pc []
  | ".es" ->
    OutputRaduSim.print_sim output_fmt (!long_names) var_map test_name evs labs rels pc (expected_labels, forbidden_labels)
  | s ->
    Printf.eprintf "Unknown output type: `%s'.\n" s
  end
in
match !outfile_ref, !format with
| _, Some extension -> handle_extension ("." ^ extension)
| Some out_filename, _ -> handle_extension (Filename.extension out_filename)
| None, None -> Printf.eprintf "-f required when output is to standard output.\n"
;;
