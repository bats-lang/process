#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* A NUL proof is for a zero byte: a cell set to 1 gives NTH(cs, 0, 1),
   which NUL_mk does not accept *)
implement main0 () = let
  val (cells | a) = $A.barr_of_arr($A.alloc<byte>(4))
  val (set | a) = $A.barr_set(a, 0, 1)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  prval nul = $P.NUL_mk(len_ok, nul_ok)
  val () = $A.barr_free(a)
in () end
