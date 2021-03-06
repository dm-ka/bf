(* changelog.ml *)

open Deptree
open Printf
open Component

let vr_of_rev s =
  try
    let pos = String.index s '-' in
    let len = String.length s in
    String.sub s 0 pos,
    int_of_string (String.sub s (succ pos) (len - pos - 1))
  with _ -> raise (Invalid_argument s)

let diff ?(changelog=false) specdir rev_a rev_b =
  let tree_a = Clonetree.tree_of_specdir ~log:false ~vr:(Some (vr_of_rev rev_a)) specdir in
  let tree_b = Clonetree.tree_of_specdir ~log:false ~vr:(Some (vr_of_rev rev_b)) specdir in
  Check.pack_component ();
  let depends_a =
    List.map (fun (p,v,r,s) -> p,(v,r))
      (list_of_deptree ~add_parent:true tree_a) in
  let depends_b =
    List.map (fun (p,v,r,s) -> p,(v,r))
      (list_of_deptree ~add_parent:true tree_b) in

  print_endline "\nCHANGELOG:\n";

  List.iter
    (fun (pkgname_b,(ver_b,rev_b)) ->
     (try
	let (ver_a,rev_a) =
	  List.assoc pkgname_b depends_a in
	let pkgname = Specdir.pkgname pkgname_b in
	let tag_a = sprintf "%s/%s-%d" pkgname ver_a rev_a in
	let tag_b = sprintf "%s/%s-%d" pkgname ver_b rev_b in
	if tag_a <> tag_b then
	  printf "# %s %s %d -> %s %d\n%!" pkgname_b ver_a rev_a ver_b rev_b;
	if changelog then
	  begin
	    let composite =
	      Filename.concat pkgname_b "composite" in
	    if tag_a <> tag_b then
	      List.iter (List.iter (printf "%s\n%!"))
		(List.map (Component.changelog tag_a tag_b)
		  (List.filter (fun c -> c.name <> (Params.get_param "pack") && c.pkg = None && (not c.nopack))
		    (Composite.components composite)))
	  end
      with Not_found ->
	printf "+ %s %s %d\n%!" pkgname_b ver_b rev_b))
    depends_b;
      
  List.iter
    (fun (pkgname_a,(ver_a,rev_a)) ->
      if not (List.mem_assoc pkgname_a depends_b) then
	printf "- %s %s %d\n%!" pkgname_a ver_a rev_a)
    depends_a

let non_first_build rev_a rev_b =
  not (snd (vr_of_rev rev_a) = 0)

let make specdir rev_a rev_b =

  Params.update_for_specdir specdir;

  if non_first_build rev_a rev_b then
    try
      diff ~changelog:true specdir rev_a rev_b
    with exn ->
      Logger.log_message (sprintf "=> changelog-failed by %s\n" (Printexc.to_string exn))
