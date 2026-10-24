#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* The constructor of NUL_AT needs k < n: byte 4 of 4 bytes is past the end,
   even when its static arguments are given by hand *)
implement main0 () = let
  val (cells | a) = $A.barr_alloc(4)
  val (set | a) = $A.barr_set(a, 3, 0)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  prval nul = $P.NUL_mk{..}{4}{4}(len_ok, nul_ok)
  val () = $A.barr_free(a)
in () end
