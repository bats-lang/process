#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* Every argument and environment entry reaches the child, however many:
   400 arguments and 300 added variables (spawn used to keep only the
   first 255 of each). *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

(* k copies of "a" in front of acc *)
fun args {k:nat} .<k>. (k: int k, acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if k <= 0 then acc else args(k - 1, $L.list_vt_cons(arg("a"), acc))

(* V<k-1>=x .. V0=x in front of acc *)
fun vars {k:nat} .<k>. (k: int k, acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if k <= 0 then acc
  else let
    var b = $B.create()
    val () = $B.bput(b, "V")
    val () = $B.put_int(b, k - 1)
    val () = $B.bput(b, "=x")
    val @(arr, len) = $B.to_arr(b)
  in vars(k - 1, $L.list_vt_cons(@(arr, len), acc)) end

fn exit_code {sin,sout,serr:bool} (r: $R.result($P.spawn_pipes(sin, sout, serr), int)): int =
  case+ r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in case+ $P.child_wait(c) of | ~$R.ok(n) => n | ~$R.err(_) => ~1 end
  | ~$R.err(_) => ~1

implement main0 () = let
  var pb = $B.create()
  val () = $B.bput(pb, "/bin/sh")
  val () = $B.put_char(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fp, bp) = $A.freeze<byte>(pa)
  (* sh -c SCRIPT sh a a ... : $# is the number of a's *)
  val argv = $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg("test $# -eq 400 && test \"$V0\" = x && test \"$V299\" = x"),
    $L.list_vt_cons(arg("sh"), args(400, $L.list_vt_nil())))))
  val rc = exit_code($P.spawn_inherit_env_with(bp, argv, vars(300, $L.list_vt_nil()),
    $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val () = $A.drop<byte>(fp, bp)
  val () = $A.free<byte>($A.thaw<byte>(fp))
in
  if rc = 0 then println! ("manyargs: all arguments and variables arrive")
  else let
    val () = println! ("FAIL manyargs: exit ", rc)
  in exit_void(1) end
end
