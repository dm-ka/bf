open Ocs_types
open Printf
open Logger

exception Load_error of string

let std_load file =
  try
    let composite = ref None in
    Env.prepare ();
    Scheme.eval_file file;
    Scheme.eval_code (fun v -> composite := Some v) "(composite)";
    match !composite with
      | None -> log_error "composite handler is not called"
      | Some v ->
	  (Scheme.map Component.component_of_sval v)
  with exn ->
    raise (Load_error (sprintf "%s: %s\n%!" file (Printexc.to_string exn)))

let short_load file =
  let ch = open_in file in
  let port =
    Ocs_port.input_port ch in
  let rec load acc =
      match Ocs_read.read_from_port port with
	| Seof -> 
	    Ocs_port.close port;
	    List.map Component.component_of_sval (List.rev acc)
	| value ->
	    load (value::acc)
  in
  try
    load []
  with exn ->
    raise (Load_error (sprintf "%s: %s\n%!" file (Printexc.to_string exn)))

let ignore_pack c =
  c.Component.name <> Params.get_param "pack"

let load ?(short_composite=false) file =
  if Sys.file_exists file then
    let components =
      if short_composite then
	short_load file
      else
	begin
	  let loc = Filename.dirname file in
	  let ver = Filename.concat loc "version" in
	  let ch = open_in ver in
	  let res =
	    match input_line ch with
	      | "3.0" ->
		  (* printf "SHORTLOAD\n%!"; *)
		  short_load file
	      | _ ->
		  (* printf "STDLOAD\n%!"; *)
		  std_load file in
	  close_in ch;
	  res
	end in
    List.filter
      ignore_pack components
  else []
      
let write ?(version=3) file components =
  let ch = open_out file in
  let out = output_string ch in
  let first = ref true in
  let write c =
    if not !first then
      out "\n  ";
    out "(";
    out c.Component.name;    
    (match c.Component.label with
      | Component.Current -> ()
      | Component.Branch s ->
	  out " (branch \"";
	  out s;
	  out "\")";
      | Component.Tag s ->
	  out " (tag \"";
	  out s;
	  out "\")");
    (match c.Component.pkg with
      | None -> ()
      | Some s ->
	  out " (package \"";
	  out s;
	  out "\")");
    if c.Component.nopack then
	  out " (nopack)";
    (match c.Component.rules with
      | None -> ()
      | Some s ->
	  out " (rules \"";
	  out s;
	  out "\")");
    out ")";
    first := false;
  in
  if version = 2 then
    out "(define (composite)\n'(";
  List.iter write components;
  if version = 2 then
    out "))\n";
  close_out ch

let components ?(short_composite=false) ?(replace_composite=None) composite =
  let replace =
    match replace_composite with
      | None -> []
      | Some x -> load x in
  List.map
    (fun c ->
      match List.filter 
	(fun r -> 
	  r.Component.name  = c.Component.name &&
	  r.Component.rules = c.Component.rules)
	replace with
	  | r::_ ->
	      printf "replace %s.%s.%s -> %s.%s.%s\n%!"
		c.Component.name (Component.string_of_label c.Component.label) (Component.string_of_rules c.Component.rules)
		r.Component.name (Component.string_of_label r.Component.label) (Component.string_of_rules r.Component.rules);
	      r
	  | [] -> c)
    (load ~short_composite composite)

let prepare ?tag composite =
  log_message ("=> prepare-composite " ^ composite);
  Components.prepare (Components.with_tag tag (components composite))

let update ?tag composite =
  log_message ("=> update-composite " ^ composite);
  Components.update (Components.with_tag tag (components composite))

let forward ?tag composite =
  log_message ("=> forward-composite " ^ composite);
  Components.forward (Components.with_tag tag (components composite))
  
let build ?tag composite =
  log_message ("=> build-composite " ^ composite);
  Components.build (Components.with_tag tag (components composite))

let rebuild ?tag composite =
  log_message ("=> rebuild-composite " ^ composite);
  Components.rebuild (Components.with_tag tag (components composite))

let install ?tag composite =
  log_message ("=> install-composite " ^ composite);
  Components.install (Components.with_tag tag (components composite))

let reinstall ?tag composite =
  log_message ("=> reinstall-composite " ^ composite);
  Components.reinstall (Components.with_tag tag (components composite))

let status ?tag composite =
  log_message ("=> status-composite " ^ composite);
  Components.status (Components.with_tag tag (components composite))

let tag composite tag =
  log_message ("=> tag-composite " ^ composite ^ " " ^ tag);
  Components.make_tag tag 
    (Components.only_local
      (components composite))

let review composite since =
  log_message ("=> review-composite " ^ composite ^ " " ^ since);
  Components.make_review since (components composite)

let diff composite tag_a tag_b =
  log_message ("=> diff-composite " ^ composite ^ " " ^ tag_a ^ ":" ^ tag_b);
  Components.make_diff tag_a tag_b 
    (Components.only_local (components composite))

let changelog ?(interactive=false) ?(compact=false) composite tag_a tag_b =
  log_message ("=> changelog-composite " ^ composite ^ " " ^ tag_a ^ ":" ^ tag_b);
  let branch =
    Some (Filename.basename (Filename.dirname composite)) in  
  Components.make_changelog ~interactive ~compact ~branch tag_a tag_b
    (Components.only_local (components composite))








