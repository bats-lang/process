#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* child_wait_outcome and child_try_wait_outcome (process#52) on real
   children: exit 0, exit n, ended by SIGKILL (9), SIGTERM (15) and SIGSEGV
   (11), whose number is reported as a signal and not as a failed wait; a
   wait that fails (a pid that is no child of this process: ECHILD, 10); a
   child still running. An outcome is written as one number: the exit
   status n as n, a signal n as 1000 + n, a failed wait's errno e as
   2000 + e, an unexpected raw status s as 3000 + s. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn code (o: $P.child_outcome): int =
  case+ o of
  | ~$P.child_exited(n) => n
  | ~$P.child_signaled(n) => 1000 + n
  | ~$P.child_wait_failed(e) => 2000 + e
  | ~$P.child_wait_unexpected(s) => 3000 + s

fn poll_code (p: $P.child_poll): int =
  case+ p of
  | ~$P.child_running() => ~1
  | ~$P.child_ended(o) => code(o)

(* /bin/sh -c script, with a pipe for its stdin *)
fn launch {sn:nat | sn <= 1024} (script: string sn): $P.spawn_pipes(true, false, false) = let
  val (nul | pa) = $P.path_of_string_proved("/bin/sh")
  val @(fp, bp) = $A.barr_freeze(pa)
  val argv = $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_nil())))
  val r = $P.spawn_proved(nul | bp, argv, $L.list_vt_nil{$P.arg_entry}(),
    $P.pipe_new(), $P.dev_null(), $P.dev_null())
  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in
  case+ r of
  | ~$R.ok(sp) => sp
  | ~$R.err(_) => exit(1)
end

fn waited {sn:nat | sn <= 1024} (script: string sn): int = let
  val+ ~$P.spawn_pipes_mk(c, i, o, e) = launch(script)
  val () = $P.pipe_end_close(i)
  val () = $P.pipe_end_close(o)
  val () = $P.pipe_end_close(e)
in code($P.child_wait_outcome(c)) end

(* polls until the child has ended, at most n times; -2 if it never did *)
fun spin {n:nat} .<n>. (c: !$P.child, n: int n): int =
  if n = 0 then ~2
  else let
    val r = poll_code($P.child_try_wait_outcome(c))
  in if r = ~1 then spin(c, n - 1) else r end

fn polled {sn:nat | sn <= 1024} (script: string sn): @(int, int) = let
  val+ ~$P.spawn_pipes_mk(c, i, o, e) = launch(script)
  (* the child waits for its stdin to end: it is running *)
  val running = poll_code($P.child_try_wait_outcome(c))
  val () = $P.pipe_end_close(i)
  val () = $P.pipe_end_close(o)
  val () = $P.pipe_end_close(e)
  val ended = spin(c, 5000000)
  (* the poll reaped it: this wait is of a child that is gone *)
  val _ = $P.child_wait_outcome(c)
in @(running, ended) end

implement main0 () = let
  val exit0 = waited("exit 0")
  val exit7 = waited("exit 7")
  val exit255 = waited("exit 255")
  val killed = waited("kill -9 $$")
  val termed = waited("kill -15 $$")
  val segv = waited("kill -11 $$")
  val failed = code($P.child_wait_outcome($P.child_mk(2000000000)))
  val @(running, p_exit) = polled("read x; exit 3")
  val @(running2, p_kill) = polled("read x; kill -9 $$")
  val stranger = $P.child_mk(2000000000)
  val p_failed = poll_code($P.child_try_wait_outcome(stranger))
  val _ = $P.child_wait_outcome(stranger)
  val ok = exit0 = 0 && exit7 = 7 && exit255 = 255 && killed = 1009
    && termed = 1015 && segv = 1011 && failed = 2010
    && p_failed = 2010 && running = ~1 && p_exit = 3 && running2 = ~1 && p_kill = 1009
in
  if ok then println! ("waitoutcome: all cases pass")
  else let
    val () = println! ("FAIL waitoutcome: exit0=", exit0, " exit7=", exit7,
      " exit255=", exit255, " killed=", killed, " termed=", termed,
      " segv=", segv, " failed=", failed, " running=", running,
      " p_exit=", p_exit, " running2=", running2, " p_kill=", p_kill, " p_failed=", p_failed)
  in exit_void(1) end
end
