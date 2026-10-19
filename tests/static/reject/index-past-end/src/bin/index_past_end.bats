#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* A NUL at a byte past the array's end: cell 5 of a 3-byte array is not
   a cell of it, so barr_set's i < n is unsolved and no NUL proof exists *)
implement main0 () = let
  val (cells | a) = $A.barr_of_arr($A.alloc<byte>(3))
  val (set | a) = $A.barr_set(a, 5, 0)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  prval nul = $P.NUL_mk(len_ok, nul_ok)
  val () = $A.barr_free(a)
in () end
