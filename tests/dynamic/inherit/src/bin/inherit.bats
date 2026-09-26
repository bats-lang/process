#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* Runs /bin/sh -c <script> with the given stdout config and waits;
   the exit code, or ~1 if it could not be run. With inherit() the
   child writes to this process's stdout, which the harness compares
   with `expected`; with dev_null() its output must not appear. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn sh {sout:bool}{sn:nat | sn <= 1024} (script: string sn, out: $P.stream_config(sout)): int = let
  var pb = $B.create()
  val () = $B.bput(pb, "/bin/sh")
  val () = $B.put_char(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fp, bp) = $A.freeze<byte>(pa)
  val argv = $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_nil())))
  val r = $P.spawn(bp, argv, $L.list_vt_nil{$P.arg_entry}(), $P.dev_null(), out, $P.inherit())
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
  val a = sh("echo from the child", $P.inherit())
  val b = sh("echo hidden", $P.dev_null())
  val c = sh("exit 5", $P.inherit())
in
  if a = 0 && b = 0 && c = 5 then println! ("inherit: all cases pass")
  else let
    val () = println! ("FAIL inherit: ", a, " ", b, " ", c)
  in exit_void(1) end
end
