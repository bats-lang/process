#include "share/atspre_staload.hats"
#use array as A
#use list as L
#use process as P

(* As nul-other-array, for exec_inherit_env_with: the NUL is set in one
   array and the path borrowed is another, so the cells differ. *)
fn exec_other {n:pos | n <= 1048576} (n: int n): int = let
  val (cells | a) = $A.barr_alloc(n)
  val (set | a) = $A.barr_set(a, n - 1, 0)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  prval nul = $P.NUL_mk(len_ok, nul_ok)
  val (_ | other) = $A.barr_alloc(n)
  val @(fz, cb) = $A.barr_freeze(other)
  val e = $P.exec_inherit_env_with(nul | cb, $L.list_vt_nil{$P.arg_entry}(), $L.list_vt_nil{$P.arg_entry}())
  val () = $A.cborrow_drop(fz, cb)
  val () = $A.barr_free($A.barr_thaw(fz))
  val () = $A.barr_free(a)
in e end

implement main0 () = let val _ = exec_other(8) in () end
