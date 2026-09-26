#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* A command name without '/' is looked up on PATH: "sh" runs /bin/sh
   (or wherever PATH finds it), and a name found nowhere makes the
   child exit 127. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn status {sn:nat | sn <= 1024} (cmd: string sn): int = let
  var pb = $B.create()
  val () = $B.bput(pb, cmd)
  val () = $B.put_char(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fp, bp) = $A.freeze<byte>(pa)
  val argv = $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg("exit 4"), $L.list_vt_nil())))
  val r = $P.spawn_inherit_env(bp, argv, $P.dev_null(), $P.dev_null(), $P.dev_null())
  val () = $A.drop<byte>(fp, bp)
  val () = $A.free<byte>($A.thaw<byte>(fp))
in
  case+ r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in case+ $P.child_wait(c) of | ~$R.ok(n) => n | ~$R.err(_) => ~1 end
  | ~$R.err(_) => ~1
end

implement main0 () = let
  val found = status("sh")
  val missing = status("no-such-command-for-bats-tests")
in
  if found = 4 && missing = 127 then println! ("search: all cases pass")
  else let
    val () = println! ("FAIL search: found=", found, " missing=", missing)
  in exit_void(1) end
end
