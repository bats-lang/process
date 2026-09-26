#include "share/atspre_staload.hats"
#use array as A
#use builder as B
#use list as L
#use process as P
#use result as R

(* spawn of a command found nowhere fails with ENOENT, and
   os_error_text gives its description, as Rust's io::Error shows it. *)
fn arg {sn:nat | sn <= 1024} (s: string sn): $P.arg_entry = let
  var b = $B.create()
  val () = $B.bput(b, s)
  val @(arr, len) = $B.to_arr(b)
in @(arr, len) end

fun print_bytes {l:agz}{n:pos}{f:nat} .<f>.
  (buf: !$A.arr(byte, l, n), i: [p:int] int p, k: int, n: int n, f: int f): void =
  if f <= 0 then () else if i >= k then ()
  else if i < 0 then () else if i >= n then ()
  else let
    val () = print_char(int2char0(byte2int0($A.get<byte>(buf, i))))
  in print_bytes(buf, i + 1, k, n, f - 1) end

implement main0 () = let
  var pb = $B.create()
  val () = $B.bput(pb, "no-such-command-for-bats-tests")
  val () = $B.put_char(pb, 0)
  val @(pa, _) = $B.to_arr(pb)
  val @(fp, bp) = $A.freeze<byte>(pa)
  val argv = $L.list_vt_cons(arg("x"), $L.list_vt_nil())
  val r = $P.spawn_inherit_env(bp, argv, $P.dev_null(), $P.dev_null(), $P.dev_null())
  val () = $A.drop<byte>(fp, bp)
  val () = $A.free<byte>($A.thaw<byte>(fp))
  val code = (case+ r of
    | ~$R.ok(sp) => let
        val+ ~$P.spawn_pipes_mk(c, i, o, e) = sp
        val () = $P.pipe_end_close(i)
        val () = $P.pipe_end_close(o)
        val () = $P.pipe_end_close(e)
        val () = $R.discard<int><int>($P.child_wait(c))
      in 0 end
    | ~$R.err(e) => e): int
  val buf = $A.alloc<byte>(256)
  val k = $P.os_error_text(code, buf, 256)
  val () = print_bytes(buf, 0, k, 256, 256)
  val () = println! (" (os error ", code, ")")
in $A.free<byte>(buf) end
