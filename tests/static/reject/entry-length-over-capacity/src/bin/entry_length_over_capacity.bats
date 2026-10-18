#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* Five bytes do not fit an array of four *)
fn five_in_four (): $P.arg_entry = let
  val arr = $A.alloc<byte>(4)
in @(arr, 5) end

implement main0 () = ()
