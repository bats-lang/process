#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* The deprecated waits kept by process#52: child_wait and child_try_wait
   are called as before, with their original types. A later edit that
   drops or changes one fails here. A child that exits n gives ok(n) and
   some(n); one ended by a signal gives err(-1) and none, which is what
   child_wait_outcome (waitoutcome) tells apart. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn launch {sn:nat | sn <= 1024} (script: string sn): $R.result($P.spawn_pipes(true, false, false), int) = let
  val (nul | pa) = $P.path_of_string_proved("/bin/sh")
  val @(fp, bp) = $A.barr_freeze(pa)
  val argv = $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_nil())))
  val r = $P.spawn_proved(nul | bp, argv, $L.list_vt_nil{$P.arg_entry}(),
    $P.pipe_new(), $P.dev_null(), $P.dev_null())
  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in r end

(* ~3 when the shell could not be started *)
fn waited {sn:nat | sn <= 1024} (script: string sn): int =
  case+ launch(script) of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in
      case+ $P.child_wait(c) of
      | ~$R.ok(n) => n
      | ~$R.err(e) => 1000 + e
    end
  | ~$R.err(_) => ~3

(* child_try_wait: ~1 while running, ~2 never ended, else its status or 1000 + err *)
fun spin {n:nat} .<n>. (c: !$P.child, n: int n): int =
  if n = 0 then ~2
  else
    case+ $P.child_try_wait(c) of
    | ~$R.some(s) => s
    | ~$R.none() => spin(c, n - 1)

fn polled (): @(int, int) =
  case+ launch("read x; exit 3") of
  | ~$R.ok(sp) => let
  val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
  val running = (case+ $P.child_try_wait(c) of
    | ~$R.some(s) => s | ~$R.none() => ~1): int
  val () = $P.pipe_end_close(i)
  val () = $P.pipe_end_close(o)
  val () = $P.pipe_end_close(e)
  val ended = spin(c, 5000000)
  val _ = (case+ $P.child_wait(c) of | ~$R.ok(n) => n | ~$R.err(e) => e): int
in @(running, ended) end
  | ~$R.err(_) => @(~3, ~3)

implement main0 () = let
  val exited = waited("exit 7")
  val signaled = waited("kill -9 $$")
  val failed = (case+ $P.child_wait($P.child_mk(2000000000)) of
    | ~$R.ok(n) => n | ~$R.err(e) => 1000 + e): int
  val @(running, ended) = polled()
  (* a signal is err(-1), the same as a failed wait: 999 *)
in
  if exited = 7 && signaled = 999 && failed = 999 && running = ~1 && ended = 3
  then println! ("oldwait: all cases pass")
  else let
    val () = println! ("FAIL oldwait: exited=", exited, " signaled=", signaled,
      " failed=", failed, " running=", running, " ended=", ended)
  in exit_void(1) end
end
