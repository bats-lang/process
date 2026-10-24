#include "share/atspre_staload.hats"
#use array as A
#use list as L
#use process as P
#use result as R

fn finish {sin,sout,serr:bool}
  (r: $R.result($P.spawn_pipes(sin, sout, serr), int)): void =
  case+ r of
  | ~$R.ok(sp) => let
      val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
      val () = $P.pipe_end_close(i)
      val () = $P.pipe_end_close(o)
      val () = $P.pipe_end_close(e)
    in case+ $P.child_wait(c) of
       | ~$R.ok(_) => ()
       | ~$R.err(_) => ()
    end
  | ~$R.err(_) => ()

(* As nul-other-array, for spawn_inherit_env_with_proved. *)
fn spawn_other {n:pos | n <= 1048576} (n: int n): void = let
  val (cells | a) = $A.barr_alloc(n)
  val (set | a) = $A.barr_set(a, n - 1, 0)
  prval len_ok = $A.setc_len(set, cells)
  prval nul_ok = $A.setc_nth_same(set)
  prval nul = $P.NUL_mk(len_ok, nul_ok)
  val (_ | other) = $A.barr_alloc(n)
  val @(fz, cb) = $A.barr_freeze(other)
  val r = $P.spawn_inherit_env_with_proved(nul | cb, $L.list_vt_nil{$P.arg_entry}(), $L.list_vt_nil{$P.arg_entry}(),
    $P.dev_null(), $P.dev_null(), $P.dev_null())
  val () = finish(r)
  val () = $A.cborrow_drop(fz, cb)
  val () = $A.barr_free($A.barr_thaw(fz))
  val () = $A.barr_free(a)
in () end

implement main0 () = spawn_other(8)
