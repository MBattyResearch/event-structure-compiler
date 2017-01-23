(*
 * Event Structure Compiler
 * Copyright (c) 2016 Simon Cooksey, Scott Owens
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


let print_tokens = ref false;;
let filename_ref = ref None;;

let options = Arg.align ([
  ("--print-tokens", Arg.Set print_tokens, " print the tokens as they are tokenised.")
]);;

let usage_msg = "compile.byte MP.jef"

let _ =
  Arg.parse options
    (fun s ->
       match !filename_ref with
       | None ->
         filename_ref := Some s
       | Some s' ->
         (Format.printf "Error: given multiple files to process: %s and %s\n"
            s' s;
          exit 1))
    usage_msg

let filename =
 match !filename_ref with
  | None ->
    (print_string usage_msg;
     exit 1)
  | Some filename ->
    filename;;

let input = Std.input_file filename in
let tokens = Tokeniser.tokenise input 0 0 in

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

let parsed_program = Parser.parse_program tokens in
let translated_program = TranslateLocations.translate_statements parsed_program in
let _ = EventStructure.read_ast 0 EventStructure.RegMap.empty translated_program in

();;
(* let tokens = Tokeniser.tokenise  *)
