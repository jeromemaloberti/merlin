(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id: misc.mli 12511 2012-05-30 13:29:48Z lefessan $ *)

(* Miscellaneous useful types and functions *)

val fatal_error: string -> 'a
exception Fatal_error

val try_finally : (unit -> 'a) -> (unit -> unit) -> 'a;;

val map_end: ('a -> 'b) -> 'a list -> 'b list -> 'b list
        (* [map_end f l t] is [map f l @ t], just more efficient. *)
val map_left_right: ('a -> 'b) -> 'a list -> 'b list
        (* Like [List.map], with guaranteed left-to-right evaluation order *)
val for_all2: ('a -> 'b -> bool) -> 'a list -> 'b list -> bool
        (* Same as [List.for_all] but for a binary predicate.
           In addition, this [for_all2] never fails: given two lists
           with different lengths, it returns false. *)
val replicate_list: 'a -> int -> 'a list
        (* [replicate_list elem n] is the list with [n] elements
           all identical to [elem]. *)
val list_remove: 'a -> 'a list -> 'a list
        (* [list_remove x l] returns a copy of [l] with the first
           element equal to [x] removed. *)
val split_last: 'a list -> 'a list * 'a
        (* Return the last element and the other elements of the given list. *)
val samelist: ('a -> 'a -> bool) -> 'a list -> 'a list -> bool
        (* Like [List.for_all2] but returns [false] if the two
           lists have different length. *)

val may: ('a -> unit) -> 'a option -> unit
val may_map: ('a -> 'b) -> 'a option -> 'b option

val find_in_path: string list -> string -> string
        (* Search a file in a list of directories. *)
val find_in_path_uncap: string list -> string -> string
        (* Same, but search also for uncapitalized name, i.e.
           if name is Foo.ml, allow /path/Foo.ml and /path/foo.ml
           to match. *)
val canonicalize_filename : ?cwd:string -> string -> string
        (* Ensure that path is absolute (wrt to cwd), follow ".." and "." *)

val remove_file: string -> unit
        (* Delete the given file if it exists. Never raise an error. *)
val expand_directory: string -> string -> string
        (* [expand_directory alt file] eventually expands a [+] at the
           beginning of file into [alt] (an alternate root directory) *)

val create_hashtable: int -> ('a * 'b) list -> ('a, 'b) Hashtbl.t
        (* Create a hashtable of the given size and fills it with the
           given bindings. *)

val copy_file: in_channel -> out_channel -> unit
        (* [copy_file ic oc] reads the contents of file [ic] and copies
           them to [oc]. It stops when encountering EOF on [ic]. *)
val copy_file_chunk: in_channel -> out_channel -> int -> unit
        (* [copy_file_chunk ic oc n] reads [n] bytes from [ic] and copies
           them to [oc]. It raises [End_of_file] when encountering
           EOF on [ic]. *)
val string_of_file: in_channel -> string
        (* [string_of_file ic] reads the contents of file [ic] and copies
           them to a string. It stops when encountering EOF on [ic]. *)
val input_bytes : in_channel -> int -> string;;
        (* [input_bytes ic n] reads [n] bytes from [ic] and returns them
           in a new string.  It raises [End_of_file] if EOF is encountered
           before all the bytes are read. *)

val log2: int -> int
        (* [log2 n] returns [s] such that [n = 1 lsl s]
           if [n] is a power of 2*)
val align: int -> int -> int
        (* [align n a] rounds [n] upwards to a multiple of [a]
           (a power of 2). *)
val no_overflow_add: int -> int -> bool
        (* [no_overflow_add n1 n2] returns [true] if the computation of
           [n1 + n2] does not overflow. *)
val no_overflow_sub: int -> int -> bool
        (* [no_overflow_add n1 n2] returns [true] if the computation of
           [n1 - n2] does not overflow. *)
val no_overflow_lsl: int -> bool
        (* [no_overflow_add n] returns [true] if the computation of
           [n lsl 1] does not overflow. *)

val chop_extension_if_any: string -> string
        (* Like Filename.chop_extension but returns the initial file
           name if it has no extension *)

val chop_extensions: string -> string
        (* Return the given file name without its extensions. The extensions
           is the longest suffix starting with a period and not including
           a directory separator, [.xyz.uvw] for instance.

           Return the given name if it does not contain an extension. *)

val search_substring: string -> string -> int -> int
        (* [search_substring pat str start] returns the position of the first
           occurrence of string [pat] in string [str].  Search starts
           at offset [start] in [str].  Raise [Not_found] if [pat]
           does not occur. *)

val rev_split_words: string -> string list
        (* [rev_split_words s] splits [s] in blank-separated words, and return
           the list of words in reverse order. *)

val rev_string_split: on:char -> string -> string list
        (* [rev_string_split ~on s] splits [s] on [on], and return the list of
           words in reverse order. *)

val get_ref: 'a list ref -> 'a list
        (* [get_ref lr] returns the content of the list reference [lr] and reset
           its content to the empty list. *)


val fst3: 'a * 'b * 'c -> 'a
val snd3: 'a * 'b * 'c -> 'b
val thd3: 'a * 'b * 'c -> 'c

val fst4: 'a * 'b * 'c * 'd -> 'a
val snd4: 'a * 'b * 'c * 'd -> 'b
val thd4: 'a * 'b * 'c * 'd -> 'c
val fth4: 'a * 'b * 'c * 'd -> 'd

        (* [ppf_to_string ()] gives a fresh formatter and a function to easily
         * gets its content as a string *)
val ppf_to_string : ?width:int -> unit -> Format.formatter * (unit -> string)

        (* [lex_strings s f] makes a lexing buffer from the string [s]
         * (like a Lexer.from_string) and call [f] to refill the buffer *)
val lex_strings : ?position:Lexing.position -> string -> (unit -> string) -> Lexing.lexbuf

val lex_move : Lexing.lexbuf -> Lexing.position -> unit

        (* [length_lessthan n l] returns
         *   Some (List.length l) if List.length l <= n
         *   None otherwise *)
val length_lessthan : int -> 'a list -> int option

        (* [has_prefix p s] returns true iff p is a prefix of s *)
val has_prefix : string -> string -> bool

        (* [modules_in_path ~ext path] lists ocaml modules corresponding to
         * filenames with extension [ext] in given [path]es.
         * For instance, if there is file "a.ml","a.mli","b.ml" in ".":
         * - modules_in_path ~ext:".ml" ["."] returns ["A";"B"],
         * - modules_in_path ~ext:".mli" ["."] returns ["A"] *)
val modules_in_path : ext:string -> string list -> string list

        (* Remove duplicates from list *)
val list_filter_dup : 'a list -> 'a list

        (* Map and filter at the same time *)
val list_filter_map : ('a -> 'b option) -> 'a list -> 'b list

        (* Concat and map at the same time *)
val list_concat_map : ('a -> 'b list) -> 'a list -> 'b list

        (* Drop items from the beginning of the list until a predicate is no
         * longer satisfied *)
val list_drop_while : ('a -> bool) -> 'a list -> 'a list

        (* Usual either/sum type *)
type ('a,'b) sum = Inl of 'a | Inr of 'b
type 'a or_exn = (exn, 'a) sum 

val sum : ('a -> 'c) -> ('b -> 'c) -> ('a,'b) sum -> 'c
val sum_join : ('a,('a,'c) sum) sum -> ('a,'c) sum
val try_sum : (unit -> 'a) -> (exn,'a) sum

        (* Simple list zipper with a position *)
module Zipper : sig
  type 'a t = private Zipper of 'a list * int * 'a list
  val shift : int -> 'a t -> 'a t
  val of_list : 'a list -> 'a t
  val insert : 'a -> 'a t -> 'a t
  val seek : int -> 'a t -> 'a t
  val change_tail : 'a list -> 'a t -> 'a t
end
type 'a zipper = 'a Zipper.t = private Zipper of 'a list * int * 'a list

        (* Join for catch pattern (writer and error monad) *)
val catch_join : 'a list * ('a, 'a list * ('a, 'b) sum) sum -> 'a list * ('a, 'b) sum

        (* Manipulating Lexing.position *)
val make_pos : int * int -> Lexing.position
val split_pos : Lexing.position -> int * int
val compare_pos : Lexing.position -> Lexing.position -> int


        (* Drop characters from beginning of string *)
val string_drop : int -> string -> string

        (* Dynamic binding pattern *)
type 'a fluid
val fluid : 'a -> 'a fluid
val fluid'let : 'a fluid -> 'a -> (unit -> 'b) -> 'b 
val (~!) : 'a fluid -> 'a

val (~:) : 'a -> 'a Lazy.t

module Sync : sig
  type 'a t
  val none : unit -> 'a t
  val make : 'a -> 'a t
  val same : 'a -> 'a t -> bool
end
