#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* The NUL of a path from path_of_string_proved is a zero at some byte k
   of the path's array, and the C string spawn reads ends at the first zero,
   which may come before k: the proof says only that byte k is zero. Two
   shapes that the other tests do not spawn: a path of one byte, "x", a
   name without '/' that no PATH entry holds, so spawn gives ENOENT (2),
   1002 (an empty path would be looked up as a directory, EACCES, 1013);
   and a path whose string holds a zero before its last byte, "/bin/sh"
   then a zero and "junk": the C string is "/bin/sh", so the child runs it
   and exits 4. A status is the child's exit code, or 1000 + spawn's errno. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn sh_c {sn:nat | sn <= 1024} (script: string sn): $L.listv($P.arg_entry) =
  $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_nil())))

fn status {sin,sout,serr:bool} (r: $R.result($P.spawn_pipes(sin, sout, serr), int)): int =
  case+ r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in case+ $P.child_wait(c) of | ~$R.ok(n) => n | ~$R.err(_) => ~1000 end
  | ~$R.err(e) => 1000 + e

(* the path made by path_of_string_proved of s, spawned with argv *)
fn run_path {sn:nat | sn < $B.BUILDER_CAP}
  (s: string sn, argv: $L.listv($P.arg_entry)): int = let
  val (nul | pa) = $P.path_of_string_proved(s)
  val @(fp, bp) = $A.barr_freeze(pa)
  val code = status($P.spawn_inherit_env_proved(nul | bp, argv, $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in code end

implement main0 () = let
  val one_byte = run_path("x", $L.list_vt_cons(arg("x"), $L.list_vt_nil()))
  val early = run_path("/bin/sh\000junk", sh_c("exit 4"))
in
  if one_byte = 1002 && early = 4 then println! ("nulpath: all cases pass")
  else let
    val () = println! ("FAIL nulpath: one_byte=", one_byte, " early=", early)
  in exit_void(1) end
end
