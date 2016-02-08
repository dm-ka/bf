open Printf

let fix_arch = function
  | "i686" -> "i386"
  | "i586" -> "i386"
  | "x86_64" -> "amd64"
  | s -> s

let fullname pkgname version revision arch =
  sprintf "%s_%s-%s_%s.deb" pkgname version revision arch
