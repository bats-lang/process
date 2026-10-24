#include "share/atspre_staload.hats"
#use process as P

(* child_wait_outcome's answer is matched on every constructor: an exit,
   a signal, a failed wait and an unexpected status, each with its number;
   child_try_wait_outcome adds a child still running *)
fn describe (o: $P.child_outcome): int =
  case+ o of
  | ~$P.child_exited(n) => n
  | ~$P.child_signaled(n) => 128 + n
  | ~$P.child_wait_failed(e) => ~e
  | ~$P.child_wait_unexpected(s) => ~s

fn describe_poll (p: $P.child_poll): int =
  case+ p of
  | ~$P.child_running() => ~1
  | ~$P.child_ended(o) => describe(o)

implement main0 () = let
  val c = $P.child_mk(2000000000)
  val polled = describe_poll($P.child_try_wait_outcome(c))
  val waited = describe($P.child_wait_outcome(c))
in
  if polled = waited then () else ()
end
