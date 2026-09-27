#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* An argument list that does not fit the 524288 bytes spawn builds it
   in is refused with E2BIG (7), not run cut short; one that fits runs
   whole. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

(* k bytes of 'a' into b *)
fun put_as {n,k:nat | n + k <= $B.BUILDER_CAP} .<k>.
  (b: !$B.builder(n) >> $B.builder(n + k), k: int k): void =
  if k <= 0 then () else let val () = $B.put_char(b, 97) in put_as(b, k - 1) end

(* An argument of 100000 a's (each under Linux's 131072-byte limit for
   one argument) *)
fn big (): $P.arg_entry = let
  var b = $B.create()
  val () = put_as(b, 100000)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

(* k big arguments in front of acc *)
fun bigs {k:nat} .<k>. (k: int k, acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if k <= 0 then acc else bigs(k - 1, $L.list_vt_cons(big(), acc))

(* The exit code of the child, or ~errno when it did not start *)
fn outcome {sin,sout,serr:bool} (r: $R.result($P.spawn_pipes(sin, sout, serr), int)): int =
  case+ r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in case+ $P.child_wait(c) of | ~$R.ok(n) => n | ~$R.err(_) => ~1000 end
  | ~$R.err(e) => ~e

(* sh -c SCRIPT sh followed by k big arguments *)
fn run_sh {lp:agz}{k:nat} (bp: !$A.borrow(byte, lp, 524288), k: int k): int = let
  val argv = $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg("test ${#1} -eq 100000"),
    $L.list_vt_cons(arg("sh"), bigs(k, $L.list_vt_nil())))))
in outcome($P.spawn_inherit_env(bp, argv, $P.dev_null(), $P.dev_null(), $P.dev_null())) end

implement main0 () = let
  var pb = $B.create()
  val () = $B.bput(pb, "/bin/sh")
  val () = $B.put_char(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fp, bp) = $A.freeze<byte>(pa)
  val fits = run_sh(bp, 4)
  val over = run_sh(bp, 6)
  val () = $A.drop<byte>(fp, bp)
  val () = $A.free<byte>($A.thaw<byte>(fp))
in
  if fits <> 0 then let
    val () = println! ("FAIL bigargs: 4 x 100000 bytes gave ", fits)
  in exit_void(1) end
  else if over <> ~7 then let
    val () = println! ("FAIL bigargs: 6 x 100000 bytes gave ", over, ", not E2BIG")
  in exit_void(1) end
  else println! ("bigargs: a list that fits runs, one that does not is E2BIG")
end
