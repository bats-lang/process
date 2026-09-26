#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* spawn_inherit_env gives the child this process's environment;
   spawn with an empty envp list gives it none. The harness runs this
   with HOME set, and sh exits 0 only when HOME is set in its
   environment. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn argv (): $L.listv($P.arg_entry) =
  $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg("test -n \"$HOME\""), $L.list_vt_nil())))

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
  val inherited = exit_code($P.spawn_inherit_env(bp, argv(), $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val empty = exit_code($P.spawn(bp, argv(), $L.list_vt_nil{$P.arg_entry}(), $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val () = $A.drop<byte>(fp, bp)
  val () = $A.free<byte>($A.thaw<byte>(fp))
in
  if inherited = 0 && empty = 1 then println! ("env: all cases pass")
  else let
    val () = println! ("FAIL env: inherited=", inherited, " empty=", empty)
  in exit_void(1) end
end
