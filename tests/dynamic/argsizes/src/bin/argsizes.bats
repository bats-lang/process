#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* An argument or variable is an array of the capacity it needs
   (arg_entry carries its own capacity and the length within it). Every
   way to make one reaches the child whole, and the total spawn accepts
   is still the entries and their NULs <= 524287 bytes: a list of that
   size runs, one byte more is E2BIG (7). *)

(* An entry from a builder's own array (into_arr: 64 bytes for a short
   text, doubled as the text grows) *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.into_arr(b)
in @(arr, len) end

(* An entry whose array is the old fixed size (a builder's to_arr) *)
fn arg_old {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

(* One byte, 'a', in an array of exactly one byte *)
fn arg_exact (): $P.arg_entry = let
  val arr = $A.alloc<byte>(1)
  val () = $A.write_byte(arr, 0, 97)
in @(arr, 1) end

(* No bytes, in an array of exactly one byte *)
fn arg_empty (): $P.arg_entry = let
  val arr = $A.alloc<byte>(1)
in @(arr, 0) end

(* k bytes of 'a' into b *)
fun put_as {n,k:nat | n + k <= $B.BUILDER_CAP} .<k>.
  (b: !$B.builder(n) >> $B.builder(n + k), k: int k): void =
  if k <= 0 then () else let val () = $B.put_char(b, 97) in put_as(b, k - 1) end

(* k 'a's, in the array the builder grew to *)
fn as_of {k:nat | k <= $B.BUILDER_CAP} (k: int k): $P.arg_entry = let
  var b = $B.create()
  val () = put_as(b, k)
  val @(arr, len) = $B.into_arr(b)
in @(arr, len) end

(* k 'a's, in an array of the old fixed size *)
fn as_old {k:nat | k <= $B.BUILDER_CAP} (k: int k): $P.arg_entry = let
  var b = $B.create()
  val () = put_as(b, k)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

(* NAME=, then k 'a's: a variable whose value is k bytes *)
fn var_of {sn:nat | sn <= 8}{k:nat | sn + k <= $B.BUILDER_CAP}
  (name: string sn, k: int k): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, name)
  val () = put_as(b, k)
  val @(arr, len) = $B.into_arr(b)
in @(arr, len) end

(* count entries of size 'a's in front of acc *)
fun repeat {c:nat}{s:nat | s <= $B.BUILDER_CAP} .<c>.
  (c: int c, s: int s, acc: $L.listv($P.arg_entry)): $L.listv($P.arg_entry) =
  if c <= 0 then acc else repeat(c - 1, s, $L.list_vt_cons(as_of(s), acc))

(* sh -c SCRIPT sh, then rest *)
fn sh_c {sn:nat | sn <= 1024} (script: string sn, rest: $L.listv($P.arg_entry))
  : $L.listv($P.arg_entry) =
  $L.list_vt_cons(arg("sh"), $L.list_vt_cons(arg("-c"),
    $L.list_vt_cons(arg(script), $L.list_vt_cons(arg("sh"), rest))))

(* The exit code of the child, or ~errno when it did not start *)
fn outcome {sin,sout,serr:bool} (r: $R.result($P.spawn_pipes(sin, sout, serr), int)): int =
  case+ r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in case+ $P.child_wait(c) of | ~$R.ok(n) => n | ~$R.err(_) => ~1000 end
  | ~$R.err(e) => ~e

fn run {lp:agz}{np:pos}{cs:$A.cells}{k:nat | k < np}
  (nul: $P.NUL_AT(cs, np, k) | bp: !$A.cborrow(lp, np, cs), argv: $L.listv($P.arg_entry)): int =
  outcome($P.spawn_inherit_env(nul | bp, argv, $P.dev_null(), $P.dev_null(), $P.dev_null()))

fn run_with {lp:agz}{np:pos}{cs:$A.cells}{k:nat | k < np}
  (nul: $P.NUL_AT(cs, np, k) | bp: !$A.cborrow(lp, np, cs), argv: $L.listv($P.arg_entry),
  extra: $L.listv($P.arg_entry)): int =
  outcome($P.spawn_inherit_env_with(nul | bp, argv, extra, $P.dev_null(), $P.dev_null(), $P.dev_null()))

fn run_envp {lp:agz}{np:pos}{cs:$A.cells}{k:nat | k < np}
  (nul: $P.NUL_AT(cs, np, k) | bp: !$A.cborrow(lp, np, cs), argv: $L.listv($P.arg_entry),
  envp: $L.listv($P.arg_entry)): int =
  outcome($P.spawn(nul | bp, argv, envp, $P.dev_null(), $P.dev_null(), $P.dev_null()))

implement main0 () = let
  val (nul | pa) = $P.path_of_string("/bin/sh")
  val @(fp, bp) = $A.barr_freeze(pa)

  (* an empty argument, a one-byte array, arrays of other capacities,
     in one list: sh -c SCRIPT sh a bc def "" *)
  val mixed = run(nul | bp,sh_c("test $# -eq 4 && test \"$1$2$3\" = abcdef && test -z \"$4\"",
    $L.list_vt_cons(arg_exact(), $L.list_vt_cons(arg("bc"),
    $L.list_vt_cons(arg_old("def"), $L.list_vt_cons(arg_empty(), $L.list_vt_nil()))))))

  (* the entries and NULs of the list: "sh", "-c", the script (13 bytes),
     "sh" are 3 + 3 + 14 + 3 = 23; five arguments of 100000 bytes are 5 *
     100001 = 500005; the sixth is m bytes and its NUL. 23 + 500005 + m +
     1 = 524287 for m = 24258 *)
  val at_limit = run(nul | bp,sh_c("test $# -eq 6", $L.list_vt_cons(as_of(24258), repeat(5, 100000, $L.list_vt_nil()))))
  val over_limit = run(nul | bp,sh_c("test $# -eq 6", $L.list_vt_cons(as_of(24259), repeat(5, 100000, $L.list_vt_nil()))))
  (* the same arguments in arrays of the old size *)
  val at_limit_old = run(nul | bp,sh_c("test $# -eq 6", $L.list_vt_cons(as_old(24258), $L.list_vt_cons(as_old(100000),
    $L.list_vt_cons(as_old(100000), $L.list_vt_cons(as_old(100000), $L.list_vt_cons(as_old(100000),
    $L.list_vt_cons(as_old(100000), $L.list_vt_nil()))))))))

  (* one argument of 524288 bytes, the most an entry's array holds: refused *)
  val whole = run(nul | bp,sh_c("true", $L.list_vt_cons(as_of(524288), $L.list_vt_nil())))
  val whole_old = run(nul | bp,sh_c("true", $L.list_vt_cons(as_old(524288), $L.list_vt_nil())))

  (* the environment entries: spawn_inherit_env_with adds them, spawn
     gives the child exactly them; the same limit *)
  val v_at = run_with(nul | bp,sh_c("test ${#V3} -eq 131067 && test ${#V0} -eq 131068", $L.list_vt_nil()),
    $L.list_vt_cons(var_of("V0=", 131068), $L.list_vt_cons(var_of("V1=", 131068),
    $L.list_vt_cons(var_of("V2=", 131068), $L.list_vt_cons(var_of("V3=", 131067), $L.list_vt_nil())))))
  val v_over = run_with(nul | bp,sh_c("true", $L.list_vt_nil()),
    $L.list_vt_cons(var_of("V0=", 131068), $L.list_vt_cons(var_of("V1=", 131068),
    $L.list_vt_cons(var_of("V2=", 131068), $L.list_vt_cons(var_of("V3=", 131068), $L.list_vt_nil())))))
  val e_at = run_envp(nul | bp,sh_c("test ${#V3} -eq 131067 && test ${#V0} -eq 131068", $L.list_vt_nil()),
    $L.list_vt_cons(var_of("V0=", 131068), $L.list_vt_cons(var_of("V1=", 131068),
    $L.list_vt_cons(var_of("V2=", 131068), $L.list_vt_cons(var_of("V3=", 131067), $L.list_vt_nil())))))
  val e_over = run_envp(nul | bp,sh_c("true", $L.list_vt_nil()),
    $L.list_vt_cons(var_of("V0=", 131068), $L.list_vt_cons(var_of("V1=", 131068),
    $L.list_vt_cons(var_of("V2=", 131068), $L.list_vt_cons(var_of("V3=", 131068), $L.list_vt_nil())))))
  (* a single variable of 524288 bytes *)
  val e_whole = run_envp(nul | bp,sh_c("true", $L.list_vt_nil()),
    $L.list_vt_cons(as_of(524288), $L.list_vt_nil()))
  (* variables of arrays of every capacity, empty list and empty value *)
  val e_empty = run_envp(nul | bp,sh_c("test -z \"$V\" && test \"$W\" = a", $L.list_vt_nil()),
    $L.list_vt_cons(arg("V="), $L.list_vt_cons(arg("W=a"), $L.list_vt_nil())))

  val () = $A.cborrow_drop(fp, bp)
  val () = $A.barr_free($A.barr_thaw(fp))
in
  if mixed <> 0 then let
    val () = println! ("FAIL argsizes: mixed capacities gave ", mixed)
  in exit_void(1) end
  else if at_limit <> 0 then let
    val () = println! ("FAIL argsizes: 524287 bytes of arguments gave ", at_limit)
  in exit_void(1) end
  else if over_limit <> ~7 then let
    val () = println! ("FAIL argsizes: 524288 bytes of arguments gave ", over_limit, ", not E2BIG")
  in exit_void(1) end
  else if at_limit_old <> 0 then let
    val () = println! ("FAIL argsizes: 524287 bytes of arguments in old arrays gave ", at_limit_old)
  in exit_void(1) end
  else if whole <> ~7 || whole_old <> ~7 then let
    val () = println! ("FAIL argsizes: an argument of 524288 bytes gave ", whole, " and ", whole_old, ", not E2BIG")
  in exit_void(1) end
  else if v_at <> 0 then let
    val () = println! ("FAIL argsizes: 524287 bytes of added variables gave ", v_at)
  in exit_void(1) end
  else if v_over <> ~7 then let
    val () = println! ("FAIL argsizes: 524288 bytes of added variables gave ", v_over, ", not E2BIG")
  in exit_void(1) end
  else if e_at <> 0 then let
    val () = println! ("FAIL argsizes: 524287 bytes of variables gave ", e_at)
  in exit_void(1) end
  else if e_over <> ~7 || e_whole <> ~7 then let
    val () = println! ("FAIL argsizes: 524288 bytes of variables gave ", e_over, " and ", e_whole, ", not E2BIG")
  in exit_void(1) end
  else if e_empty <> 0 then let
    val () = println! ("FAIL argsizes: an empty variable gave ", e_empty)
  in exit_void(1) end
  else println! ("argsizes: entries of every capacity arrive, the 524287-byte total holds")
end
