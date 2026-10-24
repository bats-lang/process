#include "share/atspre_staload.hats"
#use process as P

(* an outcome that leaves a constructor out of its match (the unexpected
   status) is not a complete match *)
fn describe (o: $P.child_outcome): int =
  case+ o of
  | ~$P.child_exited(n) => n
  | ~$P.child_signaled(n) => 128 + n
  | ~$P.child_wait_failed(e) => ~e

implement main0 () = let
  val n = describe($P.child_wait_outcome($P.child_mk(2000000000)))
in
  if n = 0 then () else ()
end
