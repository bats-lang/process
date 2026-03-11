(* process -- safe process spawning with linear child handles *)
(* Linear child must be waited on. Pipes are linear fds from file package. *)
(* Type-indexed: pipe_new in config guarantees fd in result. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use list as L
#use result as R
#use str as S
#use file as F

(* ============================================================
   C runtime (the entire unsafe surface)
   ============================================================ *)

$UNSAFE begin
%{#
#ifndef _PROCESS_RUNTIME_DEFINED
#define _PROCESS_RUNTIME_DEFINED
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <string.h>

typedef struct {
  int pid;
  int stdin_parent_fd;
  int stdout_parent_fd;
  int stderr_parent_fd;
} _spawn_result_t;

/* Global to pass result back (avoids returning struct by value issues) */
static _spawn_result_t _spawn_res;

static int _proc_spawn(
  const char *path,
  const char *argv_buf, int argv_count,
  const char *envp_buf, int envp_count,
  int stdin_mode, int stdin_fd,
  int stdout_mode, int stdout_fd,
  int stderr_mode, int stderr_fd
) {
  _spawn_res.pid = -1;
  _spawn_res.stdin_parent_fd = -1;
  _spawn_res.stdout_parent_fd = -1;
  _spawn_res.stderr_parent_fd = -1;

  int stdin_pipe[2] = {-1, -1};
  int stdout_pipe[2] = {-1, -1};
  int stderr_pipe[2] = {-1, -1};

  if (stdin_mode == 0) {
    if (pipe(stdin_pipe) < 0) return -1;
  }
  if (stdout_mode == 0) {
    if (pipe(stdout_pipe) < 0) {
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      return -1;
    }
  }
  if (stderr_mode == 0) {
    if (pipe(stderr_pipe) < 0) {
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
      return -1;
    }
  }

  const char *argv_ptrs[256];
  int ai = 0;
  const char *p = argv_buf;
  int i;
  for (i = 0; i < argv_count && ai < 255; i++) {
    argv_ptrs[ai++] = p;
    p += strlen(p) + 1;
  }
  argv_ptrs[ai] = (const char *)0;

  const char *envp_ptrs[256];
  int ei = 0;
  p = envp_buf;
  for (i = 0; i < envp_count && ei < 255; i++) {
    envp_ptrs[ei++] = p;
    p += strlen(p) + 1;
  }
  envp_ptrs[ei] = (const char *)0;

  int pid = fork();
  if (pid < 0) {
    if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
    if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
    if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
    return -1;
  }

  if (pid == 0) {
    if (stdin_mode == 0) {
      dup2(stdin_pipe[0], 0); close(stdin_pipe[0]); close(stdin_pipe[1]);
    } else if (stdin_mode == 1) {
      if (stdin_fd != 0) { dup2(stdin_fd, 0); close(stdin_fd); }
    } else {
      int dn = open("/dev/null", O_RDONLY); if (dn >= 0) { dup2(dn, 0); close(dn); }
    }
    if (stdout_mode == 0) {
      dup2(stdout_pipe[1], 1); close(stdout_pipe[0]); close(stdout_pipe[1]);
    } else if (stdout_mode == 1) {
      if (stdout_fd != 1) { dup2(stdout_fd, 1); close(stdout_fd); }
    } else {
      int dn = open("/dev/null", O_WRONLY); if (dn >= 0) { dup2(dn, 1); close(dn); }
    }
    if (stderr_mode == 0) {
      dup2(stderr_pipe[1], 2); close(stderr_pipe[0]); close(stderr_pipe[1]);
    } else if (stderr_mode == 1) {
      if (stderr_fd != 2) { dup2(stderr_fd, 2); close(stderr_fd); }
    } else {
      int dn = open("/dev/null", O_WRONLY); if (dn >= 0) { dup2(dn, 2); close(dn); }
    }
    execve(path, (char *const *)argv_ptrs, (char *const *)envp_ptrs);
    _exit(127);
  }

  if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); _spawn_res.stdin_parent_fd = stdin_pipe[1]; }
  if (stdout_pipe[1] >= 0) { close(stdout_pipe[1]); _spawn_res.stdout_parent_fd = stdout_pipe[0]; }
  if (stderr_pipe[1] >= 0) { close(stderr_pipe[1]); _spawn_res.stderr_parent_fd = stderr_pipe[0]; }
  if (stdin_mode == 1) close(stdin_fd);
  if (stdout_mode == 1) close(stdout_fd);
  if (stderr_mode == 1) close(stderr_fd);
  _spawn_res.pid = pid;
  return pid;
}

static int _spawn_get_stdin_fd(void) { return _spawn_res.stdin_parent_fd; }
static int _spawn_get_stdout_fd(void) { return _spawn_res.stdout_parent_fd; }
static int _spawn_get_stderr_fd(void) { return _spawn_res.stderr_parent_fd; }

static int _proc_wait(int pid) {
  int status;
  if (waitpid(pid, &status, 0) < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
}

static int _proc_try_wait(int pid) {
  int status;
  int r = waitpid(pid, &status, WNOHANG);
  if (r == 0) return -2;
  if (r < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
}
#endif
%}
end

(* ============================================================
   Types
   ============================================================ *)

#pub datavtype child =
  | child_mk of (int)

(* Type-level conditional: pipe_fd iff b=true *)
#pub datavtype pipe_end(b:bool) =
  | pipe_fd(true) of ($F.fd)
  | pipe_none(false) of ()

(* Stream config indexed by bool — pipe_new proves b=true *)
#pub datavtype stream_config(b:bool) =
  | pipe_new(true) of ()
  | inherit_fd(false) of ($F.fd)
  | dev_null(false) of ()

(* Spawn result indexed by which streams are piped *)
#pub datavtype spawn_pipes(sin:bool, sout:bool, serr:bool) =
  | spawn_pipes_mk(sin, sout, serr) of (
      child,
      pipe_end(sin),
      pipe_end(sout),
      pipe_end(serr)
    )

(* ============================================================
   Public API
   ============================================================ *)


#pub fn child_wait(c: child): $R.result(int, int)

#pub fn child_try_wait(c: !child): $R.option(int)

#pub fn child_pid(c: !child): int

#pub fn pipe_end_close {b:bool} (p: pipe_end(b)): void

(* ============================================================
   Internal helpers
   ============================================================ *)

(* Build pipe_end from config and raw fd.
   The config pattern match IS the proof that b matches reality. *)
fn _build_pipe_end {b:bool}
  (cfg_mode: int, rawfd: int, cfg: !stream_config(b)): pipe_end(b) =
  case+ cfg of
  | pipe_new() => pipe_fd($F.fd_mk(rawfd))
  | inherit_fd(_) => pipe_none()
  | dev_null() => pipe_none()

fn _cfg_mode {b:bool} (cfg: !stream_config(b)): int =
  case+ cfg of
  | pipe_new() => 0
  | inherit_fd(_) => 1
  | dev_null() => 2

fn _cfg_fd {b:bool} (cfg: !stream_config(b)): int =
  case+ cfg of
  | pipe_new() => ~1
  | inherit_fd(f) => let
      val+ @$F.fd_mk(rawfd) = f
      val r = rawfd
      prval () = fold@(f)
    in r end
  | dev_null() => ~1

fn _consume_cfg {b:bool} (cfg: stream_config(b)): void =
  case+ cfg of
  | ~pipe_new() => ()
  | ~inherit_fd(f) => let val+ ~$F.fd_mk(_) = f in end
  | ~dev_null() => ()

(* ============================================================
   Implementations
   ============================================================ *)

fn spawn
  {lp:agz}{np:pos | np < 1048576}
  {la:agz}{na:pos}
  {le:agz}{ne:pos}
  {sin:bool}{sout:bool}{serr:bool}
  (path: !$A.borrow(byte, lp, np), path_len: int np,
   argv: !$A.borrow(byte, la, na), argv_count: int,
   envp: !$A.borrow(byte, le, ne), envp_count: int,
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int) = let
  val sin_mode = _cfg_mode(stdin_cfg)
  val sin_fd = _cfg_fd(stdin_cfg)
  val sout_mode = _cfg_mode(stdout_cfg)
  val sout_fd = _cfg_fd(stdout_cfg)
  val serr_mode = _cfg_mode(stderr_cfg)
  val serr_fd = _cfg_fd(stderr_cfg)
  val cpath = $A.alloc<byte>(path_len + 1)
  val () = $A.write_borrow(cpath, 0, path, path_len)
  val () = $A.write_byte(cpath, path_len, 0)
  val pid = $UNSAFE begin $extfcall(int, "_proc_spawn",
    $UNSAFE.castvwtp1{ptr}(cpath),
    $UNSAFE.castvwtp1{ptr}(argv), argv_count,
    $UNSAFE.castvwtp1{ptr}(envp), envp_count,
    sin_mode, sin_fd, sout_mode, sout_fd, serr_mode, serr_fd) end
  val () = $A.free<byte>(cpath)
in
  if pid >= 0 then let
    val stdin_pfd = $UNSAFE begin $extfcall(int, "_spawn_get_stdin_fd") end
    val stdout_pfd = $UNSAFE begin $extfcall(int, "_spawn_get_stdout_fd") end
    val stderr_pfd = $UNSAFE begin $extfcall(int, "_spawn_get_stderr_fd") end
    (* Pattern match on configs to build correctly-typed pipe_ends *)
    val sin_end = _build_pipe_end(sin_mode, stdin_pfd, stdin_cfg)
    val sout_end = _build_pipe_end(sout_mode, stdout_pfd, stdout_cfg)
    val serr_end = _build_pipe_end(serr_mode, stderr_pfd, stderr_cfg)
    (* Consume the configs — C already handled the fds *)
    val () = _consume_cfg(stdin_cfg)
    val () = _consume_cfg(stdout_cfg)
    val () = _consume_cfg(stderr_cfg)
  in
    $R.ok(spawn_pipes_mk(child_mk(pid), sin_end, sout_end, serr_end))
  end
  else let
    val () = _consume_cfg(stdin_cfg)
    val () = _consume_cfg(stdout_cfg)
    val () = _consume_cfg(stderr_cfg)
  in $R.err(~1) end
end

implement child_wait(c) = let
  val+ ~child_mk(pid) = c
  val status = $UNSAFE begin $extfcall(int, "_proc_wait", pid) end
in
  if status >= 0 then $R.ok(status)
  else $R.err(status)
end

implement child_try_wait(c) = let
  val+ @child_mk(pid) = c
  val status = $UNSAFE begin $extfcall(int, "_proc_try_wait", pid) end
  prval () = fold@(c)
in
  if status >= 0 then $R.some(status)
  else $R.none()
end

implement child_pid(c) = let
  val+ @child_mk(pid) = c
  val p = pid
  prval () = fold@(c)
in p end

implement pipe_end_close {b} (p) =
  case+ p of
  | ~pipe_fd(f) => $R.discard<int><int>($F.file_close(f))
  | ~pipe_none() => ()

(* ============================================================
   List-based spawn API
   ============================================================ *)

fn _bput_v(b: !$B.builder_v >> $B.builder_v, c: int): void = let
  val n = $B.length(b)
in
  if n < 524288 - 1 then $B.put_char(b, c)
  else ()
end

fn _bput_str_v(b: !$B.builder_v >> $B.builder_v, s0: string): void = let
  val s = g1ofg0_string(s0)
  val slen = g1u2i(string1_length(s))
  fun loop {sn:nat}{i:nat | i <= sn}{fuel:nat} .<fuel>.
    (b: !$B.builder_v >> $B.builder_v,
     s: string sn, slen: int sn, i: int i, fuel: int fuel): void =
    if fuel <= 0 then ()
    else if i >= slen then ()
    else let
      val c = char2int0(string_get_at(s, i))
      val () = _bput_v(b, c)
    in loop(b, s, slen, i + 1, fuel - 1) end
in loop(b, s, slen, 0, slen) end

fn _build_argv(args: $L.list(string)): @($B.builder_v, int) = let
  fun loop {n:nat} .<n>.
    (xs: $L.list_t(string, n), b: !$B.builder_v >> $B.builder_v,
     count: int): int =
    case+ xs of
    | $L.list_nil() => count
    | $L.list_cons(s, tl) => let
        val () = _bput_str_v(b, s)
        val () = _bput_v(b, 0)
      in loop(tl, b, count + 1) end
  var b = $B.create()
  val argc = loop(args, b, 0)
in @(b, argc) end


#pub fn spawn_args
  {sin:bool}{sout:bool}{serr:bool}
  (path: string,
   args: $L.list(string),
   envp: $L.list(string),
   stdin_cfg: stream_config(sin),
   stdout_cfg: stream_config(sout),
   stderr_cfg: stream_config(serr))
  : $R.result(spawn_pipes(sin, sout, serr), int)

implement spawn_args {sin}{sout}{serr}
  (path, args, envp, stdin_cfg, stdout_cfg, stderr_cfg) = let
  val path1 = g1ofg0_string(path)
  val path_len = g1u2i(string1_length(path1))
in
  if path_len >= 524287 then let
    val () = _consume_cfg(stdin_cfg)
    val () = _consume_cfg(stdout_cfg)
    val () = _consume_cfg(stderr_cfg)
  in $R.err(~1) end
  else let
  val path_arr = $A.alloc<byte>(524288)
  val () = $S.fill_exact(path_arr, path1, 524288, path_len, 0, path_len)
  val () = $A.set<byte>(path_arr, path_len, int2byte0(0))
  val @(fz_p, bv_p) = $A.freeze<byte>(path_arr)
  val @(argv_b, argc) = _build_argv(args)
  val @(argv_arr, _) = $B.to_arr(argv_b)
  val @(fz_a, bv_a) = $A.freeze<byte>(argv_arr)
  val @(envp_b, envp_c) = _build_argv(envp)
  val @(envp_arr, _) = $B.to_arr(envp_b)
  val @(fz_e, bv_e) = $A.freeze<byte>(envp_arr)
  val r = spawn(bv_p, 524288, bv_a, argc, bv_e, envp_c,
    stdin_cfg, stdout_cfg, stderr_cfg)
  val () = $A.drop<byte>(fz_a, bv_a)
  val () = $A.free<byte>($A.thaw<byte>(fz_a))
  val () = $A.drop<byte>(fz_e, bv_e)
  val () = $A.free<byte>($A.thaw<byte>(fz_e))
  val () = $A.drop<byte>(fz_p, bv_p)
  val () = $A.free<byte>($A.thaw<byte>(fz_p))
in r end end

