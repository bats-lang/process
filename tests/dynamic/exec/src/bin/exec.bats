#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use env as E
#use file as F
#use list as L
#use process as P
#use result as R

(* exec_inherit_env_with (process#90) replaces the process that calls it.
   This binary runs in two roles. With no argument it is the parent: it
   spawns itself with one argument, the case, and says what the child did.
   With an argument it is the child of that case and calls exec.

   replaced: the program exec runs has the very pid the parent spawned
   (a fork would give another), so a signal sent to that pid reaches it.
   env: the parent's variable is kept, one the parent set is replaced, one
   is added. stdin: the program reads what the parent wrote to the pipe
   that is its stdin, and its stdout is the parent's pipe.
   missing, directory, toobig: exec returns the errno (ENOENT 2, EACCES 13,
   E2BIG 7) and the process is still there to exit with it. Those three run
   under valgrind, so the C's failure path is checked for leaks. *)

fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fn sh_c {sn:nat | sn <= 1024} (script: string sn): $L.listv($P.arg_entry) =
  $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_nil())))

fn no_extra (): $L.listv($P.arg_entry) = $L.list_vt_nil()

(* exec of cmd; only an errno comes back *)
fn exec_of {sn:nat | sn <= 1024}
  (cmd: string sn, argv: $L.listv($P.arg_entry), extra: $L.listv($P.arg_entry)): int = let
  val (nul | pa) = $P.path_of_string_proved(cmd)
  val @(fp, bp) = $A.barr_freeze(pa)
  val e = $P.exec_inherit_env_with(nul | bp, argv, extra)
  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in e end

(* an argument of 300000 bytes: two of them do not fit ARG_TOTAL_MAX *)
fn big_arg (): $P.arg_entry = let
  val a = $A.alloc<byte>(300000)
in @(a, 300000) end

(* the child of a case *)
fn child (mode: int): int =
  if mode = char2int0('p') then
    exec_of("sh", sh_c("echo $$"), no_extra())
  else if mode = char2int0('e') then
    exec_of("sh", sh_c("echo \"$KEEP $REPL $ADDED\""),
      $L.list_vt_cons(arg("REPL=new"), $L.list_vt_cons(arg("ADDED=add"), $L.list_vt_nil())))
  else if mode = char2int0('i') then
    exec_of("sh", sh_c("read x; echo \"got $x\""), no_extra())
  else if mode = char2int0('x') then
    exec_of("no-such-command-for-bats-tests", sh_c("true"), no_extra())
  else if mode = char2int0('a') then
    exec_of("/", sh_c("true"), no_extra())
  else
    exec_of("sh",
      $L.list_vt_cons(arg("sh"), $L.list_vt_cons(big_arg(), $L.list_vt_cons(big_arg(), $L.list_vt_nil()))),
      no_extra())

fun first_nul {l:agz}{n:pos}{i:nat | i <= n} .<n - i>.
  (buf: !$A.arr(byte, l, n), i: int i, n: int n): [k:nat | k <= n] int k =
  if i >= n then n
  else if byte2int0($A.get<byte>(buf, i)) = 0 then i
  else first_nul(buf, i + 1, n)

fn outcome_of (o: $P.child_outcome): int =
  case+ o of
  | ~$P.child_exited(n) => n
  | ~$P.child_signaled(s) => 1000 + s
  | ~$P.child_wait_failed(_) => ~1
  | ~$P.child_wait_unexpected(_) => ~2

(* the number the output starts with, or ~1 *)
fun number_of {l:agz}{n:pos}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (buf: !$A.arr(byte, l, n), i: int i, m: int m, acc: int): int =
  if i >= m then (if i > 0 then acc else ~1)
  else let val c = byte2int0($A.get<byte>(buf, i)) in
    if c >= 48 && c <= 57 then number_of(buf, i + 1, m, acc * 10 + (c - 48))
    else (if i > 0 then acc else ~1)
  end

fun show {l:agz}{n:pos}{m:nat | m <= n}{i:nat | i <= m} .<m - i>.
  (buf: !$A.arr(byte, l, n), i: int i, m: int m): void =
  if i >= m then ()
  else let
    val c = byte2int0($A.get<byte>(buf, i))
    val () = (if c != 10 then print_char(int2char0(c)) else ())
  in show(buf, i + 1, m) end

(* "hello\n" *)
fn hello (): [l:agz] $A.arr(byte, l, 6) = let
  val a = $A.alloc<byte>(6)
  val () = $A.set<byte>(a, 0, int2byte0(104))
  val () = $A.set<byte>(a, 1, int2byte0(101))
  val () = $A.set<byte>(a, 2, int2byte0(108))
  val () = $A.set<byte>(a, 3, int2byte0(108))
  val () = $A.set<byte>(a, 4, int2byte0(111))
  val () = $A.set<byte>(a, 5, int2byte0(10))
in a end

(* Runs this binary as the child of the case (under valgrind when
   valgrind is true), feeds feed to its stdin, and prints label, then the
   verdict by kind: 0 the exit status, 1 whether the program has the pid
   spawned, 2 the first line it wrote. *)
fn run {sn:nat | sn <= 1024}{cn:nat | cn <= 1024}
  (label: string, mode: string sn, cmd: string cn, valgrind: bool, extra: $L.listv($P.arg_entry),
   feed: bool, kind: int): void = let
  val () = print_string(label)
  val () = print_string(": ")
  val (nul | pa) = $P.path_of_string_proved(cmd)
  val @(fp, bp) = $A.barr_freeze(pa)
  val argv = (if valgrind then
    $L.list_vt_cons(arg("valgrind"), $L.list_vt_cons(arg("-q"),
    $L.list_vt_cons(arg("--leak-check=full"),
    $L.list_vt_cons(arg("--errors-for-leak-kinds=definite,indirect"),
    $L.list_vt_cons(arg("--error-exitcode=99"),
    $L.list_vt_cons(arg("./dist/debug/exec"), $L.list_vt_cons(arg(mode), $L.list_vt_nil())))))))
    else $L.list_vt_cons(arg("exec"), $L.list_vt_cons(arg(mode), $L.list_vt_nil()))): $L.listv($P.arg_entry)
  val r = $P.spawn_inherit_env_with_proved(nul | bp, argv, extra, $P.pipe_new(), $P.pipe_new(), $P.inherit())
  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in
  case+ r of
  | ~$R.err(e) => println! ("spawn failed ", e)
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val+ ~$P.pipe_none() = e
      val+ ~$P.pipe_fd(fi) = i
      val () = (if feed then let
          val a = hello()
          val @(fz, bv) = $A.freeze<byte>(a)
          val () = (case+ $F.file_write(fi, bv, 6) of | ~$R.ok(_) => () | ~$R.err(_) => ())
          val () = $A.drop<byte>(fz, bv)
          val () = $A.free<byte>($A.thaw<byte>(fz))
        in end else ())
      val () = $R.discard<int><$F.io_error>($F.file_close(fi))
      val pid = $P.child_pid(c)
      val status = outcome_of($P.child_wait_outcome(c))
      val+ ~$P.pipe_fd(fo) = o
      val out: [lo:agz] $A.arr(byte, lo, 256) = $A.alloc<byte>(256)
      val got = (case+ $F.file_read(fo, out, 256) of
        | ~$R.ok(k) => k
        | ~$R.err(_) => 0): [k:nat | k <= 256] int k
      val () = $R.discard<int><$F.io_error>($F.file_close(fo))
      val () = (if kind = 0 then println! ("exit ", status)
        else if kind = 1 then
          (if number_of(out, 0, got, 0) = pid then println! ("same pid") else println! ("other pid"))
        else let val () = show(out, 0, got) in println! () end)
      val () = $A.free<byte>(out)
    in end
end

implement main0 () = let
  val buf: [lb:agz] $A.arr(byte, lb, 4096) = $A.alloc<byte>(4096)
  val got = $E.args_read(buf, 4096)
in
  case+ got of
  | ~$R.none() => let
      val () = $A.free<byte>(buf)
    in exit_void(1) end
  | ~$R.some(n) => let
      val nul = first_nul(buf, 0, 4096)
      val mode = (if nul + 1 < n then byte2int0($A.get<byte>(buf, nul + 1)) else 0): int
      val () = $A.free<byte>(buf)
    in
      if mode > 0 then let
          (* a child: exec returned, so it failed; its errno is the status *)
          val e = child(mode)
        in exit_void(e) end
      else let
          val () = run("replaced", "p", "./dist/debug/exec", false, no_extra(), false, 1)
          val () = run("env", "e", "./dist/debug/exec", false,
            $L.list_vt_cons(arg("KEEP=kept"), $L.list_vt_cons(arg("REPL=old"), $L.list_vt_nil())), false, 2)
          val () = run("stdin", "i", "./dist/debug/exec", false, no_extra(), true, 2)
          val () = run("missing", "x", "valgrind", true, no_extra(), false, 0)
          val () = run("directory", "a", "valgrind", true, no_extra(), false, 0)
          val () = run("toobig", "b", "valgrind", true, no_extra(), false, 0)
        in println! ("exec: all cases pass") end
    end
end
