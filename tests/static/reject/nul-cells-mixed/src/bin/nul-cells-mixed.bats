#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* A NUL proof joins the length and the zero byte of the SAME cells: the
   length of one array with the zero of another is not a NUL_AT *)
fn mixed {n:pos | n <= 1048576} (n: int n): void = let
  val (cells | a) = $A.barr_alloc(n)
  val (other_cells | b) = $A.barr_alloc(n)
  val (set_a | a) = $A.barr_set(a, n - 1, 0)
  val (set_b | b) = $A.barr_set(b, n - 1, 0)
  prval len_ok = $A.setc_len(set_a, cells)
  prval nul_ok = $A.setc_nth_same(set_b)
  prval nul = $P.NUL_mk(len_ok, nul_ok)
  val () = $A.barr_free(a)
  val () = $A.barr_free(b)
in () end

implement main0 () = mixed(8)
