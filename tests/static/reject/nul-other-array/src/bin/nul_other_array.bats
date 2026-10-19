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

(* The NUL of one path does not serve another: the proof names the cells
   of the path made by path_of_string, and this array holds other cells *)
implement main0 () = let
  val (nul | pa) = $P.path_of_string("/bin/sh")
  val (_ | other) = $A.barr_of_arr($A.alloc<byte>(8))
  val @(fz, cb) = $A.barr_freeze(other)
  val r = $P.spawn_inherit_env(nul | cb, $L.list_vt_nil{$P.arg_entry}(),
    $P.dev_null(), $P.dev_null(), $P.dev_null())
  val () = finish(r)
  val () = $A.cborrow_drop(fz, cb)
  val () = $A.barr_free($A.barr_thaw(fz))
  val () = $A.barr_free(pa)
in () end
