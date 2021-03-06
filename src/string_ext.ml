module String = struct
    include String

    let empty s =
      Str.string_match (Str.regexp "^[ \t]*$") s 0

    let not_empty s =
      not (empty s)

    let chop_suffix str suff =
      if Filename.check_suffix str suff then
	Filename.chop_suffix str suff
      else str

    let unprintable_to_underline str =
      Str.global_replace (Str.regexp "[-]") "_" str

    let have_prefix prefix s =
      let len = String.length s in
      let plen = String.length prefix in
      len >= plen && prefix = String.sub s 0 plen
			 
  end
