type state = {
  pos      : Lexing.position;
  tokens   : Outline.token list;
  outlines : Outline.t;
  chunks   : Chunk.t;
  types    : Typer.t;
}

let initial_state = {
  pos      = Lexing.({pos_fname = ""; pos_lnum = 1; pos_bol = 0; pos_cnum = 0});
  tokens   = [];
  outlines = History.empty;
  chunks   = History.empty;
  types    = History.empty;
}

type handler = Protocol.io -> state -> Json.json list -> state * Json.json
type t = { name : string ; handler : handler ; doc : string }
let invalid_arguments () = failwith "invalid arguments"

let commands : (string,t) Hashtbl.t = Hashtbl.create 11
let register cmd = Hashtbl.add commands cmd.name cmd

let command_tell = {
  name = "tell";

  doc = String.concat "\n" [
    "Use ['tell','struct','...ocaml impl...'] to send source code from editor to merlin.";
    "The command answers the boolean 'true' if parsing ended, 'false' if it needs more input.";
    "In this case, the only allowed command is ['tell','struct','next source content'].";
    "To interrupt the parser, run ['tell','struct',''] (meaning eof) or ['tell','struct',null].";
  ];

  handler = begin fun (i,o) state -> function
  | [`String "struct" ; `String source] ->
      Env.reset_missing_cmis ();
      ignore (Error_report.reset_warnings ());
      let goteof = ref false in
      let lexbuf = Misc.lex_strings source
        begin fun () ->
          goteof := true;
          o (Protocol.return (`Bool false));
          try begin match Stream.next i with
            | `List [`String "tell" ; `String "struct" ; `String source] -> source
            | `List [`String "tell" ; `String "struct" ; `Null ] -> ""
              (* FIXME: parser catch this Failure. It should not *)
            | _ -> invalid_arguments ()
          end with
            Stream.Failure -> invalid_arguments ()
        end
      in
      let rec loop state =
        let bufpos = ref state.pos in
        let outlines, chunks, types = 
          (History.cutoff state.outlines), 
          (History.cutoff state.chunks), 
          (History.cutoff state.types)
        in
        let tokens, outlines =
          Outline.parse ~bufpos ~goteof
            (History.of_list state.tokens) outlines lexbuf
        in
        let chunks = Chunk.sync outlines chunks in
        let types = Typer.sync chunks types in
        let tokens = History.nexts tokens in
        let pos = !bufpos in
        let w = Error_report.reset_warnings () in
        let outlines = History.modify (fun outline -> Outline.({ outline with exns = w @ outline.exns })) outlines in
        let state' = { tokens ; outlines ; chunks ; types ; pos } in
        if !goteof || state.tokens = state'.tokens
        then state'
        else loop state'
      in
      let state = loop state in
      state, `Bool true
  | _ -> invalid_arguments ()
  end;
}

exception Found of Types.signature_item

let command_type = {
  name = "type";

  doc = String.concat "\n" [
    "Returns the type of an expression as a string.";
    "['type','expression','... ml expression'] tries to type expression in global env.";
    "['type','at',{'line':l,'col':c}] returns the type of the expression at given position(BUGGY)";
  ];

  handler = begin fun _ state -> function
  | [`String "expression"; `String expr] ->
      let lexbuf = Lexing.from_string expr in
      let env = Typer.env state.types in
      let expression = Chunk_parser.top_expr Lexer.token lexbuf in
      let (str, sg, _) =
        Typemod.type_toplevel_phrase env
          Parsetree.([{ pstr_desc = Pstr_eval expression ; pstr_loc = Location.curr lexbuf }])
      in
      (*let sg' = Typemod.simplify_signature sg in*)
      let open Typedtree in
      begin match str.str_items with
        | [ { str_desc = Tstr_eval exp }] ->
            let ppf, to_string = Misc.ppf_to_string () in
            Printtyp.type_scheme ppf exp.exp_type;
            state, `String (to_string ())
        | _ -> failwith "unhandled expression"
      end

  | [`String "at" ; jpos] ->
    let ln, cl = Protocol.pos_of_json jpos in
    let trees = Typer.trees state.types in
    begin try
      List.iter
      begin fun (tstr,tsg) ->
        List.iter
        begin fun sg ->
          match Browse.signature_loc sg with
            | Some loc when Browse.compare_loc (ln,cl) loc < 0 ->
                raise Not_found
            | Some loc when Browse.compare_loc (ln,cl) loc = 0 ->
                raise (Found sg)
            | _ -> ()
          end tsg
        end trees;
        raise Not_found
      with Found sg -> 
        let ppf, to_string = Misc.ppf_to_string () in
        Printtyp.signature ppf [sg];
        state, `String (to_string ())
    end

  | _ -> invalid_arguments ()
  end;
}

let rec mod_smallerthan n m =
  if n < 0 then None
  else
  let open Types in
  match m with
  | Mty_ident _ -> Some 1
  | Mty_signature s ->
      begin match Misc.length_lessthan n s with
        | None -> None
        | Some n' ->
            List.fold_left
            begin fun acc item ->
              match acc, item with
                | None, _ -> None
                | Some n', _ when n' > n -> None
                | Some n1, Sig_modtype (_,Modtype_manifest m)
                | Some n1, Sig_module (_,m,_) ->
                    (match mod_smallerthan (n - n1) m with
                       | Some n2 -> Some (n1 + n2)
                       | None -> None)
                | Some n', _ -> Some (succ n')
            end (Some 0) s
      end
  | Mty_functor (_,m1,m2) ->
      begin
        match mod_smallerthan n m1 with
        | None -> None
        | Some n1 ->
        match mod_smallerthan (n - n1) m2 with
        | None -> None
        | Some n2 -> Some (n1 + n2)
      end

let complete_in_env env prefix = 
  let fmt ~exact name path ty =
    let ident = Ident.create (Path.last path) in
    let ppf, to_string = Misc.ppf_to_string () in
    let kind =
      match ty with
      | `Value v -> Printtyp.value_description ident ppf v; "value"
      | `Cons c  -> 
          Format.pp_print_string ppf name;
          Format.pp_print_string ppf " : ";
          Printtyp.type_expr ppf Types.({ level = 0 ; id = 0 ; desc = Tarrow ("",{ level = 0; id = 0; desc = Ttuple c.cstr_args}, c.cstr_res,Cok)});
          "constructor"
      | `Mod m   -> 
          (if exact then
             match mod_smallerthan 200 m with
               | None -> ()
               | Some _ -> Printtyp.modtype ppf m
          ); "module"
      | `Typ t ->
          Printtyp.type_declaration ident ppf t; "type"
    in
    let desc, info = match kind with "module" -> "", to_string () | _ -> to_string (), "" in
    `Assoc ["name", `String name ; "kind", `String kind ; "desc", `String desc ; "info", `String info]
  in
  let find ?path prefix compl =
    let valid = Misc.has_prefix prefix in
    (* Hack to prevent extensions namespace to leak *)
    let valid name = name <> "_" && valid name in
    let compl = [] in
    let compl = Env.fold_values
      (fun name path v compl ->
         if valid name then (fmt ~exact:(name = prefix) name path (`Value v)) :: compl else compl)
      path env compl
    in
    let compl = Env.fold_constructors
      (fun name path v compl ->
         if valid name then (fmt ~exact:(name = prefix) name path (`Cons v)) :: compl else compl)
      path env compl
    in
    let compl = Env.fold_types
      (fun name path v compl ->
         if valid name then (fmt ~exact:(name = prefix)  name path (`Typ v)) :: compl else compl)
      path env compl
    in
    let compl = Env.fold_modules
      (fun name path v compl ->
         if valid name then (fmt ~exact:(name = prefix)  name path (`Mod v)) :: compl else compl)
      path env compl
    in
    compl
  in
  try
    match Longident.parse prefix with
      | Longident.Ldot (path,prefix) -> find ~path prefix []
      | Longident.Lident prefix -> find prefix []
      | _ -> find prefix []
  with Not_found -> []

let command_complete = {
  name = "complete";

  doc = String.concat "\n" [
    "['complete','prefix','...identifier path...'] or";
    "['complete','prefix','...identifier path...', 'at', {'line':l,'col':c}]";
    "returns possible completions in global environement or in environment";
    "surrounding given position for given prefix/path (path of the form: Module.ident)";
  ];

  handler =
  begin fun _ state -> function
  | [`String "prefix" ; `String prefix] ->
    begin
      let env = Typer.env state.types in
      let compl = complete_in_env env prefix in
      state, `List (List.rev compl)
    end 
  | [`String "prefix" ; `String prefix ; `String "at" ; pos ] ->
    begin
      failwith "TODO"
    end 
  | _ -> invalid_arguments ()
  end;
}

let command_seek = {
  name = "seek";

  doc = "TODO";

  handler =
  begin fun _ state -> function
  | [`String "position"] ->
      state, Protocol.pos_to_json state.pos

  | [`String "position" ; jpos] ->
      let l, c = Protocol.pos_of_json jpos in
      let outlines = Outline.seek_line (l,c) state.outlines in
      let outlines = match History.backward outlines with
        | Some ({ Outline.kind = Outline_utils.Partial_definitions _ }, o) -> o
        | _ -> outlines
      in
      let outlines, chunks = History.Sync.rewind fst outlines state.chunks in
      let chunks, types = History.Sync.rewind fst chunks state.types in
      let pos =
        match Outline.last_position outlines with
          | Some p -> p
          | None -> initial_state.pos
      in
      { tokens = [] ; outlines ; chunks ; types ; pos },
      Protocol.pos_to_json pos

  | [`String "end_of_definition"] ->
      failwith "TODO"

  | [`String "end"] ->
      let outlines = History.seek (fun _ -> 1) state.outlines in
      let chunks = History.Sync.right fst outlines state.chunks in
      let types  = History.Sync.right fst chunks state.types in
      let pos =
        match Outline.last_position outlines with
          | Some p -> p
          | None -> initial_state.pos
      in
      { tokens = [] ; outlines ; chunks ; types ; pos },
      Protocol.pos_to_json pos

  | [`String "maximize_scope"] ->
      let rec find_end_of_module (depth,outlines) =
        if depth = 0 then (0,outlines)
        else
        match History.forward outlines with
          | None -> (depth,outlines)
          | Some ({ Outline.kind = Outline_utils.Leave_module },outlines') ->
              find_end_of_module (pred depth, outlines')
          | Some ({ Outline.kind = Outline_utils.Enter_module },outlines') ->
              find_end_of_module (succ depth, outlines')
          | Some (_,outlines') -> find_end_of_module (depth,outlines')
      in
      let rec loop outlines =
        match History.forward outlines with
          | None -> outlines
          | Some ({ Outline.kind = Outline_utils.Leave_module },_) ->
              outlines
          | Some ({ Outline.kind = Outline_utils.Enter_module },outlines') ->
              (match find_end_of_module (1,outlines') with
                | (0,outlines'') -> outlines''
                | _ -> outlines)
          | Some (_,outlines') -> loop outlines'
      in 
      let outlines = loop state.outlines in
      let chunks = History.Sync.right fst outlines state.chunks in
      let types  = History.Sync.right fst chunks state.types in
      let pos =
        match Outline.last_position outlines with
          | Some p -> p
          | None -> initial_state.pos
      in
      { tokens = [] ; outlines ; chunks ; types ; pos },
      Protocol.pos_to_json pos
  | _ -> invalid_arguments ()
  end;
}

let command_reset = {
  name = "reset";
  
  doc = "TODO";
  
  handler =
  begin fun _ state -> function
  | [] -> initial_state,
          Protocol.pos_to_json initial_state.pos
  | _ -> invalid_arguments ()
  end
}

let command_refresh = {
  name = "refresh";

  doc = "TODO";

  handler =
  begin fun _ state -> function
  | [] -> 
      Env.reset_cache ();
      let types = Typer.sync state.chunks History.empty in
      { state with types }, `Bool true
  | _ -> invalid_arguments ()
  end;
}

let command_cd = {
  name = "cd";
  doc = "TODO";
  
  handler = 
  begin fun _ state -> function
  | [`String s] ->
      Sys.chdir s;
      state, `Bool true
  | _ -> invalid_arguments ()
  end;
}

let command_errors = {
  name = "errors";
  doc = "TODO";
  
  handler =
  begin fun _ state -> function
  | [] ->
      let exns = Outline.exns state.outlines @ Typer.exns state.types in
      state, `List (Error_report.to_jsons (List.rev exns))
  | _ -> invalid_arguments ()
  end;
}

let command_dump = {
  name = "dump";
  doc = "TODO";

  handler =
  begin let pr_item_desc items =
    (List.map (fun (s,i) -> `List [`String s;`Int i]) (Chunk.dump_chunk items))
  in
  fun _ state -> function
  | [`String "env"] ->
      let sg = Browse.Env.signature_of_env (Typer.env state.types) in
      let aux item =
        let ppf, to_string = Misc.ppf_to_string () in
        Printtyp.signature ppf [item];
        let content = to_string () in
        let ppf, to_string = Misc.ppf_to_string () in
        match Browse.signature_loc item with
          | Some loc ->
              Location.print_loc ppf loc;
              let loc = to_string () in
              `List [`String loc ; `String content]
          | None -> `String content
      in
      state, `List (List.map aux sg)
  | [`String "sig"] ->
      let trees = Typer.trees state.types in
      let sg = List.flatten (List.map snd trees) in
      let aux item =
        let ppf, to_string = Misc.ppf_to_string () in
        Printtyp.signature ppf [item];
        let content = to_string () in
        let ppf, to_string = Misc.ppf_to_string () in
        match Browse.signature_loc item with
          | Some loc ->
              Location.print_loc ppf loc;
              let loc = to_string () in
              `List [`String loc ; `String content]
          | None -> `String content
      in
      state, `List (List.map aux sg)
  | [`String "chunks"] ->
      state, `List (pr_item_desc state.chunks)
  (*| [`String "types" ; `String "chunks"] ->
      state, `List (List.rev_map (fun item -> `List (pr_item_desc item))
                                 (Typer.chunks state.types))*)
  | _ -> invalid_arguments ()
  end;
}

let command_help = {
  name = "help";
  doc = "List known commands with synopsis and small description";

  handler =
  begin fun _ state -> function
  | [] -> 
      let helps = Hashtbl.fold (fun name { doc } cmds -> (name, `String doc) :: cmds) commands [] in
      state, `Assoc helps
  | _ -> invalid_arguments ()
  end;
}

let _ = List.iter register [
  command_tell; command_seek; command_reset; command_refresh;
  command_cd; command_type; command_complete;
  command_errors; command_dump; command_help
]