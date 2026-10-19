#include "share/atspre_staload.hats"
#use array as A
#use list as L
#use process as P
#use result as R

(* The NUL of one path does not serve another: the proof names the cells
   of the path made by path_of_string, and this array holds other cells *)
implement main0 () = let
  val (nul | pa) = $P.path_of_string("/bin/sh")
  val (other_cells | other) = $A.barr_of_arr($A.alloc<byte>(8))
  val @(fz, cb) = $A.barr_freeze(other)
  val r = $P.spawn_inherit_env(nul | cb, $L.list_vt_nil{$P.arg_entry}(),
    $P.dev_null(), $P.dev_null(), $P.dev_null())
  val () = $A.cborrow_drop(fz, cb)
  val () = $A.barr_free($A.barr_thaw(fz))
  val () = $A.barr_free(pa)
in () end
