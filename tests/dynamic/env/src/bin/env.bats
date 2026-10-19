#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* spawn_inherit_env gives the child this process's environment;
   spawn with an empty envp list gives it none; spawn_inherit_env_with
   adds and replaces variables in it. The harness runs this
   with HOME set, and sh exits 0 only when HOME is set in its
   environment. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn sh_c {sn:nat | sn <= 1024} (script: string sn): $L.listv($P.arg_entry) =
  $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_nil())))

fn argv (): $L.listv($P.arg_entry) = sh_c("test -n \"$HOME\"")

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
  val (nul | pa) = $P.path_of_string_proved("/bin/sh")
  val @(fp, bp) = $A.barr_freeze(pa)
  val inherited = exit_code($P.spawn_inherit_env_proved(nul | bp, argv(), $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val empty = exit_code($P.spawn_proved(nul | bp, argv(), $L.list_vt_nil{$P.arg_entry}(), $P.dev_null(), $P.dev_null(), $P.dev_null()))
  (* extra entries replace HOME and add BATS_EXTRA; PATH is kept *)
  val extra = $L.list_vt_cons(arg("HOME=/replaced"), $L.list_vt_cons(arg("BATS_EXTRA=yes"), $L.list_vt_nil()))
  val with_extra = exit_code($P.spawn_inherit_env_with_proved(nul | bp,
    sh_c("test \"$HOME\" = /replaced && test \"$BATS_EXTRA\" = yes && test -n \"$PATH\""),
    extra, $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in
  if inherited = 0 && empty = 1 && with_extra = 0 then println! ("env: all cases pass")
  else let
    val () = println! ("FAIL env: inherited=", inherited, " empty=", empty, " with_extra=", with_extra)
  in exit_void(1) end
end
