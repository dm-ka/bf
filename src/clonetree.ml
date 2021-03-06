open Deptree
open Platform
open Spectype
open Logger
open Printf
open Pkgpath
open Output

type clone_val = string * Component.version * Component.revision * spec

type extdep = string
type pkg_clone_tree =
    (Pkgpath.t * extdep list) deptree

type clone_tree =
    clone_val deptree

let debug =
  try
    ignore(Sys.getenv "DEBUG");
    true
  with Not_found -> false

let string_of_clone_val (specdir, ver, rev, spec) =
  "SPECINFO: " ^ specdir ^ " " ^ ver ^ "-" ^ (string_of_int rev) ^ "\n"
  ^ "SPEC:\n"
  ^ (string_of_spec spec)
	      
let string_of_clone_tree ?(limit_depth=None) (tree:clone_tree) =
  let space depth = String.make (2*depth) ' ' in
  let rec print_tree depth = function
    | Dep_val (clone_val, deptree) ->
       string_of_string_list [
	   ((space depth) ^ (string_of_clone_val clone_val));
	   (let next_depth = succ depth in
	    match limit_depth with
	    | Some limit -> if next_depth = limit then
			      ""
			    else (print_tree (1+ depth) deptree)
	    | None -> (print_tree (1+ depth) deptree))
	 ]
    | Dep_list trees ->
       string_of_string_list
	 (List.map (print_tree depth) trees)
  in
  print_tree 0 tree
     
let new_only (e, _) =
  with_platform
    (fun os platform ->
      let pkg =
	sprintf "%s-%s-%d.%s.%s.%s"
	  e.pkg_name e.pkg_version e.pkg_revision
	  (string_of_platform platform)
	  (System.arch ())
	  e.pkg_extension
      in
      if Sys.file_exists pkg then
	begin
	  log_message (sprintf "\tpackage %s/%s already exists" (Sys.getcwd ()) pkg);
	  false
	end
      else true)

let with_overwrite ow l =
  if ow then l else List.filter new_only l

let optint_of_string s =
  try
    Some (int_of_string s)
  with Failure(int_of_string) ->
    None

let compare_pkg_versions ver1 ver2 =
  let rex = Str.regexp ".-" in
  Version.compare 
    ~retype:optint_of_string
    (Str.split rex ver1)
    (Str.split rex ver2)

let tree_of_package ?userhost ?(log=true) pkg_path : pkg_clone_tree =
  let pre_table = Hashtbl.create 32 in
  
  let rec scan pkg_path =
    if debug then
      log_message (sprintf "scanning %s" pkg_path);
    let e = make_pkg_record ~userhost pkg_path in
    let deps = Pkgdeps.extract ~userhost pkg_path in
    Hashtbl.add pre_table e.pkg_name (e,deps);
    
    List.iter
      (fun (pkg_name,ver_opt,rev_opt,operand_opt) ->
        (match ver_opt, rev_opt with
	  | Some ver, Some rev ->
	      if Hashtbl.mem pre_table pkg_name then
		begin
		  let (e,_) = Hashtbl.find pre_table pkg_name in
		  if ver <> e.pkg_version || rev <> e.pkg_revision then
		    begin
		      if log then
			log_message (sprintf "Already registered: pkg(%s) ver(%s)/rev(%d) and next found: ver(%s)/rev(%d) not equivalent."
			  pkg_name e.pkg_version e.pkg_revision ver rev);
		      raise (Cannot_resolve_dependes pkg_path)
		    end
		end;
	      let new_path =
		sprintf "%s/%s-%s-%d.%s.%s.%s" e.pkg_dir pkg_name ver rev (string_of_platform e.pkg_platform) e.pkg_arch e.pkg_extension in
	      if not (Hashtbl.mem pre_table pkg_name) then
		scan new_path
	  | _ ->
	      ()))
      deps
  in
  scan pkg_path;

  let table = Hashtbl.create 32 in
  let warning depth s =
    if log then
      log_message (sprintf "%s warning: %s already scanned" (String.make depth ' ') s) in
  let resolve depth s =
    if log then
      log_message (sprintf "%s resolve %s" (String.make depth ' ') s) in

  let extract_version pkg_name ver_opt =
    match ver_opt with
      | Some v -> Some v
      | None ->
	  try
	    let (e,_) =
	      Hashtbl.find pre_table pkg_name in
	    Some e.pkg_version
	  with Not_found -> None
  in
  
  let extract_revision pkg_name rev_opt =
    match rev_opt with
      | Some r -> Some r
      | None ->
	  try
	    let (e,_) =
	      Hashtbl.find pre_table pkg_name in
	    Some e.pkg_revision
	  with Not_found -> None in

  let split_deps e deps =
	List.fold_left
	  (fun (paths,extdeps) (pkg_name,ver_opt,rev_opt,operand_opt) ->
	    match extract_version pkg_name ver_opt with
	      | None -> 
		  paths, pkg_name::extdeps
	      | Some ver ->
		  begin
		    match extract_revision pkg_name rev_opt with
		      | None ->
			  let op =
			    match operand_opt with
			      | None -> " = "
			      | Some op -> " " ^ op ^ " " in
			  let extdep =
			    sprintf "%s%s%s" pkg_name op ver in
			  (paths, (extdep::extdeps))
		      | Some rev ->
			  (((sprintf "%s/%s-%s-%d.%s.%s.%s" e.pkg_dir
			    pkg_name ver rev
			    (string_of_platform e.pkg_platform)
			    e.pkg_arch e.pkg_extension)::paths), extdeps)
		  end)
	  ([],[]) deps in
  
  let rec make depth pkg_path =        
    if Hashtbl.mem table pkg_path then
      begin
	warning depth pkg_path;
	let (e,deps) = 
	  Hashtbl.find pre_table (Pkgpath.name pkg_path) in
	Dep_val ((e,(snd (split_deps e deps))), Dep_list [])
      end
    else
      let pkg_name = Pkgpath.name pkg_path in
      let (e,deps) = Hashtbl.find pre_table pkg_name in
      
      Hashtbl.add table pkg_path true;
      
      let (depend_paths,ext_deps) = split_deps e deps in

      resolve depth pkg_path;
      Dep_val
	((e,ext_deps), Dep_list
	  (List.fold_left
	    (fun acc path ->
	      (try
		acc @ [make (succ depth) path]
	      with
		| Not_found
		| Exit -> acc)) [] depend_paths))
  in

  make 0 pkg_path

let tree_of_specdir ?(newload=false) ?(log=true) ?packdir ~vr specdir : clone_tree =
  let table = Hashtbl.create 32 in
  let pkgdir =
    match packdir with
      | Some p -> p
      | None ->
	  Filename.dirname (Filename.dirname specdir) in
  let warning depth specdir ver rev iver irev =
    if log then
      log_message (sprintf "%s warning: %s %s %d already scanned, ignore %s %d" (String.make depth ' ') specdir ver rev iver irev) in
  let replace depth specdir ver rev iver irev =
    if log then
      log_message (sprintf "%s warning: %s %s %d already scanned, replaced %s %d" (String.make depth ' ') specdir ver rev iver irev) in
  let resolve depth specdir ver rev =
    if log then
      log_message (sprintf "%s resolve %s %s %d" (String.make depth ' ') specdir ver rev) in
  let checkout_pack key =
    System.with_dir pkgdir
      (Git.git_checkout ~low:true ~key) in

  let (ver,rev) =
    match vr with
	Some x -> x | None -> Release.get specdir in
  
  let rec make depth (specdir,ver,rev,mode) =
    if Hashtbl.mem table specdir then
      begin
	let (ver',rev',_) =
	  Hashtbl.find table specdir in	
	if mode then
	  begin	    
	    checkout_pack 
	      (Tag.mk ((Specdir.pkgname specdir), ver, rev));
	    let spec =
	      if newload
	      then
		let pkgname = Specdir.pkgname specdir in
		Spectype.newload pkgname ver
	      else
		Spectype.load
		  ~version:ver
		  ~revision:(string_of_int rev) specdir in
	    Hashtbl.replace table specdir (ver,rev,spec);
	    replace depth specdir ver' rev' ver rev;
	  end
	else
	  warning depth specdir ver' rev' ver rev;
	Dep_val (specdir, Dep_list [])
      end
    else
      begin
	checkout_pack 
	  (Tag.mk ((Specdir.pkgname specdir), ver, rev));

	if Sys.file_exists specdir then
	  let spec =
	    if newload
	    then
	      let pkgname = Specdir.pkgname specdir in
	      let (version,_) = Specdir.ver_rev_of_release (Specdir.release_by_specdir specdir) in
	      Spectype.newload pkgname version
	    else
	      Spectype.load
		~version:ver
		~revision:(string_of_int rev) specdir in
	  
	  Hashtbl.add table specdir (ver,rev,spec);
	  
	  let depfile = 
	    Filename.concat specdir "depends" in
	  if Sys.file_exists depfile then
	    let depends =
	      List.fold_left (fun acc (pkg,vr_opt,_) ->
		try
		  if Params.home_made_package pkg then
		    begin
		      let new_specdir =
			Specdir.of_pkg ~default_branch:(Some (Specdir.branch specdir)) pkgdir pkg in
		      let (ver,rev) =
			Release.get new_specdir in
		      acc @ [new_specdir,ver,rev,(Version.have_revision (Version.parse_vr_opt vr_opt))] (* add specdir for post-processing *)
		    end
		  else acc
		with _ -> acc)
		[]
		((*if newload
		 then Spectype.depload_v2_new depfile
		 else*) Spectype.depload ~ignore_last:false depfile)
	    in
	    resolve depth specdir ver rev;
	    Dep_val (specdir, Dep_list
	      (List.fold_left
		(fun acc (specdir,ver,rev,mode) ->
		  (try acc @ [make (succ depth) (specdir,ver,rev,mode)] with Exit -> acc)) [] depends))
	  else
	    begin
	      resolve depth specdir ver rev;
	      Dep_val (specdir, Dep_list [])
	    end
	else raise Exit
      end
  in

  let tree =
    try
      make 0 (specdir,ver,rev,true)
    with Exit -> checkout_pack "master";
      raise (Tree_error (sprintf "not found specdir (%s) for pack state: %s/%s-%d\n%!" specdir (Specdir.pkgname specdir) ver rev))
  in

  checkout_pack "master";
  
  (map_deptree (fun specdir -> 
    let (ver,rev,spec) =
      try
	Hashtbl.find table specdir 
      with Not_found -> assert false
    in (specdir,ver,rev,spec)) 
    tree)
