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
   and exits 4; and a path at the old bound, 524288 bytes (bats-lang/process#63
   row 3), made on the array path the proved spawns take (no string: a
   barr_alloc, a NUL at byte 524287, every other byte set to 'a' after a
   slash, the NUL's NTH kept through each set by setc_nth_other), so the C
   string is 524287 bytes and the kernel refuses it as too long, 1000 + 36
   (ENAMETOOLONG on Linux), not E2BIG for the path. Mutants (each applied and
   restored): the NUL at byte 524287 moved to byte 0 (bound_path(524288, 0)):
   the C string is empty, old_bound=1013 (EACCES), not 1036; path_of_string_proved writing its NUL at
   byte 0: one_byte and early are 1013. A status is the child's exit code, or
   1000 + spawn's errno. *)
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

(* 'a' for every byte but the first, a slash: an absolute name, so no PATH search *)
fn byte_at (i: int): [v:int | 0 <= v; v < 256] int v = if i = 0 then 47 else 97

(* every byte but byte k set, byte k's zero kept: the NUL's proof follows *)
fun fill {l:agz}{n:pos}{k:nat | k < n}{cs:$A.cells}{i:nat | i <= n} .<n - i>.
  (nul: $A.NTH(cs, k, 0), len: $A.CLEN(cs, n) | a: $A.barr(l, n, cs), i: int i, n: int n, k: int k)
  : [cs2:$A.cells] ($A.NTH(cs2, k, 0), $A.CLEN(cs2, n) | $A.barr(l, n, cs2)) =
  if i >= n then (nul, len | a)
  else if i = k then fill(nul, len | a, i + 1, n, k)
  else let
    val (set | a2) = $A.barr_set(a, i, byte_at(i))
  in fill($A.setc_nth_other(set, nul), $A.setc_len(set, len) | a2, i + 1, n, k) end

(* a path of n bytes with its only zero at byte k, spawned *)
fn bound_path {n:pos | n <= 1048576}{k:nat | k < n} (n: int n, k: int k): int = let
  val (cells | a) = $A.barr_alloc(n)
  val (set | a) = $A.barr_set(a, k, 0)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  val (nul_kept, len_kept | a) = fill(nul_ok, len_ok | a, 0, n, k)
  prval nul = $P.NUL_mk(len_kept, nul_kept)
  val @(fz, cb) = $A.barr_freeze(a)
  val code = status($P.spawn_inherit_env_proved(nul | cb, $L.list_vt_cons(arg("x"), $L.list_vt_nil()),
    $P.dev_null(), $P.dev_null(), $P.dev_null()))
  val () = $A.cborrow_drop(fz, cb)
  val () = $A.barr_free($A.barr_thaw(fz))
in code end

implement main0 () = let
  val one_byte = run_path("x", $L.list_vt_cons(arg("x"), $L.list_vt_nil()))
  val early = run_path("/bin/sh\000junk", sh_c("exit 4"))
  val old_bound = bound_path(524288, 524287)
in
  if one_byte = 1002 && early = 4 && old_bound = 1036 then println! ("nulpath: all cases pass")
  else let
    val () = println! ("FAIL nulpath: one_byte=", one_byte, " early=", early, " old_bound=", old_bound)
  in exit_void(1) end
end
