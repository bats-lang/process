#include "share/atspre_staload.hats"
#use array as A
#use process as P

(* An argument is an array of the capacity it needs: three bytes in an
   array of four, and none in an array of one *)
fn three (): $P.arg_entry = let
  val arr = $A.alloc<byte>(4)
in @(arr, 3) end

fn none (): $P.arg_entry = let
  val arr = $A.alloc<byte>(1)
in @(arr, 0) end

implement main0 () = let
  val @(a, _) = three()
  val () = $A.free<byte>(a)
  val @(b, _) = none()
  val () = $A.free<byte>(b)
in () end
