#include "share/atspre_staload.hats"
#use process as P

(* an outcome is linear: one not matched is not consumed, so the answer
   of a wait cannot be dropped *)
implement main0 () = let
  val o = $P.child_wait_outcome($P.child_mk(2000000000))
in () end
