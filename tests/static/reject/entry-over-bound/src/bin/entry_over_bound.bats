#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* An entry's array holds at most ARG_ENTRY_MAX (524288) bytes *)
fn too_big (): $P.arg_entry = let
  val arr = $A.alloc<byte>(524289)
in @(arr, 0) end

implement main0 () = ()
