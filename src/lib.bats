(* process -- safe process spawning with linear child handles *)
(* Linear child must be waited on. Pipes are linear fds from file package. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use result as R
#use file as F

(* ============================================================
   C runtime (the entire unsafe surface)
   ============================================================ *)

$UNSAFE begin
%{#
#include <unistd.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <string.h>

/* Spawn result struct passed back to ATS */
typedef struct {
  int pid;
  int stdin_parent_fd;   /* parent writes here (-1 if not piped) */
  int stdout_parent_fd;  /* parent reads here (-1 if not piped) */
  int stderr_parent_fd;  /* parent reads here (-1 if not piped) */
} _spawn_result_t;

/* Stream config: 0=pipe, 1=inherit(fd), 2=devnull */

static _spawn_result_t _proc_spawn(
  const char *path,
  const char *argv_buf, int argv_count,
  const char *envp_buf, int envp_count,
  int stdin_mode, int stdin_fd,
  int stdout_mode, int stdout_fd,
  int stderr_mode, int stderr_fd
) {
  _spawn_result_t res;
  res.pid = -1;
  res.stdin_parent_fd = -1;
  res.stdout_parent_fd = -1;
  res.stderr_parent_fd = -1;

  /* Set up pipes as needed */
  int stdin_pipe[2] = {-1, -1};
  int stdout_pipe[2] = {-1, -1};
  int stderr_pipe[2] = {-1, -1};

  if (stdin_mode == 0) {
    if (pipe(stdin_pipe) < 0) return res;
  }
  if (stdout_mode == 0) {
    if (pipe(stdout_pipe) < 0) {
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      return res;
    }
  }
  if (stderr_mode == 0) {
    if (pipe(stderr_pipe) < 0) {
      if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
      if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
      return res;
    }
  }

  /* Build argv array from null-separated buffer */
  const char *argv_ptrs[256];
  int ai = 0;
  const char *p = argv_buf;
  int i;
  for (i = 0; i < argv_count && ai < 255; i++) {
    argv_ptrs[ai++] = p;
    p += strlen(p) + 1;
  }
  argv_ptrs[ai] = (const char *)0;

  /* Build envp array from null-separated buffer */
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
    /* Fork failed */
    if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); close(stdin_pipe[1]); }
    if (stdout_pipe[0] >= 0) { close(stdout_pipe[0]); close(stdout_pipe[1]); }
    if (stderr_pipe[0] >= 0) { close(stderr_pipe[0]); close(stderr_pipe[1]); }
    return res;
  }

  if (pid == 0) {
    /* Child */

    /* stdin */
    if (stdin_mode == 0) {
      dup2(stdin_pipe[0], 0);
      close(stdin_pipe[0]); close(stdin_pipe[1]);
    } else if (stdin_mode == 1) {
      if (stdin_fd != 0) { dup2(stdin_fd, 0); close(stdin_fd); }
    } else {
      int devnull = open("/dev/null", O_RDONLY);
      if (devnull >= 0) { dup2(devnull, 0); close(devnull); }
    }

    /* stdout */
    if (stdout_mode == 0) {
      dup2(stdout_pipe[1], 1);
      close(stdout_pipe[0]); close(stdout_pipe[1]);
    } else if (stdout_mode == 1) {
      if (stdout_fd != 1) { dup2(stdout_fd, 1); close(stdout_fd); }
    } else {
      int devnull = open("/dev/null", O_WRONLY);
      if (devnull >= 0) { dup2(devnull, 1); close(devnull); }
    }

    /* stderr */
    if (stderr_mode == 0) {
      dup2(stderr_pipe[1], 2);
      close(stderr_pipe[0]); close(stderr_pipe[1]);
    } else if (stderr_mode == 1) {
      if (stderr_fd != 2) { dup2(stderr_fd, 2); close(stderr_fd); }
    } else {
      int devnull = open("/dev/null", O_WRONLY);
      if (devnull >= 0) { dup2(devnull, 2); close(devnull); }
    }

    execve(path, (char *const *)argv_ptrs, (char *const *)envp_ptrs);
    _exit(127); /* execve failed */
  }

  /* Parent: close child ends of pipes, keep parent ends */
  if (stdin_pipe[0] >= 0) { close(stdin_pipe[0]); res.stdin_parent_fd = stdin_pipe[1]; }
  if (stdout_pipe[1] >= 0) { close(stdout_pipe[1]); res.stdout_parent_fd = stdout_pipe[0]; }
  if (stderr_pipe[1] >= 0) { close(stderr_pipe[1]); res.stderr_parent_fd = stderr_pipe[0]; }

  /* Close inherited fds in parent too (they were consumed) */
  if (stdin_mode == 1) close(stdin_fd);
  if (stdout_mode == 1) close(stdout_fd);
  if (stderr_mode == 1) close(stderr_fd);

  res.pid = pid;
  return res;
}

static int _proc_wait(int pid) {
  int status;
  if (waitpid(pid, &status, 0) < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
}

static int _proc_try_wait(int pid) {
  int status;
  int r = waitpid(pid, &status, WNOHANG);
  if (r == 0) return -2; /* still running */
  if (r < 0) return -1;
  if (WIFEXITED(status)) return WEXITSTATUS(status);
  return -1;
}

/* Accessors for spawn result struct */
static int _spawn_res_pid(void *p) { return ((_spawn_result_t *)p)->pid; }
static int _spawn_res_stdin(void *p) { return ((_spawn_result_t *)p)->stdin_parent_fd; }
static int _spawn_res_stdout(void *p) { return ((_spawn_result_t *)p)->stdout_parent_fd; }
static int _spawn_res_stderr(void *p) { return ((_spawn_result_t *)p)->stderr_parent_fd; }
%}
end

(* ============================================================
   Types
   ============================================================ *)

(* Linear child process handle — must wait exactly once *)
#pub datavtype child =
  | child_mk of (int)

(* Stream configuration for stdin/stdout/stderr *)
#pub datavtype stream_config =
  | pipe_new of ()
  | inherit_fd of ($F.fd)
  | dev_null of ()

(* Spawn result: child + optional pipe fds *)
#pub datavtype spawn_pipes =
  | spawn_pipes_mk of (
      child,
      $R.option($F.fd),   (* stdin pipe: parent writes to child *)
      $R.option($F.fd),   (* stdout pipe: parent reads from child *)
      $R.option($F.fd)    (* stderr pipe: parent reads from child *)
    )

(* ============================================================
   Public API
   ============================================================ *)

(* Spawn a child process.
   path: null-terminated executable path
   argv: null-separated argument strings
   argv_count: number of arguments
   envp: null-separated environment strings (KEY=VALUE)
   envp_count: number of env entries
   stdin/stdout/stderr_cfg: what to connect each stream to (consumed) *)
#pub fn spawn
  {lp:agz}{np:pos | np < 1048576}
  {la:agz}{na:pos}
  {le:agz}{ne:pos}
  (path: !$A.borrow(byte, lp, np), path_len: int np,
   argv: !$A.borrow(byte, la, na), argv_count: int,
   envp: !$A.borrow(byte, le, ne), envp_count: int,
   stdin_cfg: stream_config,
   stdout_cfg: stream_config,
   stderr_cfg: stream_config)
  : $R.result(spawn_pipes)

(* Wait for child to exit. Consumes child. Returns exit code. *)
#pub fn child_wait(c: child): $R.result(int)

(* Non-blocking wait. Returns some(exit_code) if exited, none if still running. *)
#pub fn child_try_wait(c: !child): $R.option(int)

(* Get child pid *)
#pub fn child_pid(c: !child): int

(* ============================================================
   Implementations
   ============================================================ *)

fn _cfg_mode(cfg: !stream_config): int =
  case+ cfg of
  | pipe_new() => 0
  | inherit_fd(_) => 1
  | dev_null() => 2

fn _cfg_fd(cfg: !stream_config): int =
  case+ cfg of
  | pipe_new() => ~1
  | inherit_fd(f) => let
      val+ @$F.fd_mk(rawfd) = f
      val r = rawfd
      prval () = fold@(f)
    in r end
  | dev_null() => ~1

(* Consume the configs — inherit_fd's fd is consumed by C side *)
fn _consume_configs(
  sin: stream_config, sout: stream_config, serr: stream_config
): void = let
  val () = case+ sin of
    | ~pipe_new() => ()
    | ~inherit_fd(f) => let val+ ~$F.fd_mk(_) = f in end
    | ~dev_null() => ()
  val () = case+ sout of
    | ~pipe_new() => ()
    | ~inherit_fd(f) => let val+ ~$F.fd_mk(_) = f in end
    | ~dev_null() => ()
  val () = case+ serr of
    | ~pipe_new() => ()
    | ~inherit_fd(f) => let val+ ~$F.fd_mk(_) = f in end
    | ~dev_null() => ()
in end

fn _make_pipe_fd(rawfd: int): $R.option($F.fd) =
  if rawfd >= 0 then $R.some($F.fd_mk(rawfd))
  else $R.none()

implement spawn {lp}{np}{la}{na}{le}{ne}
  (path, path_len, argv, argv_count, envp, envp_count,
   stdin_cfg, stdout_cfg, stderr_cfg) = let
  val sin_mode = _cfg_mode(stdin_cfg)
  val sin_fd = _cfg_fd(stdin_cfg)
  val sout_mode = _cfg_mode(stdout_cfg)
  val sout_fd = _cfg_fd(stdout_cfg)
  val serr_mode = _cfg_mode(stderr_cfg)
  val serr_fd = _cfg_fd(stderr_cfg)
  (* Need null-terminated path *)
  val cpath = $A.alloc<byte>(path_len + 1)
  val () = $A.write_borrow(cpath, 0, path, path_len)
  val () = $A.write_byte(cpath, path_len, 0)
  (* Call C spawn *)
  val res_ptr = $extfcall(ptr, "_proc_spawn",
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(cpath) end,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(argv) end, argv_count,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(envp) end, envp_count,
    sin_mode, sin_fd,
    sout_mode, sout_fd,
    serr_mode, serr_fd)
  val () = $A.free<byte>(cpath)
  val pid = $extfcall(int, "_spawn_res_pid", res_ptr)
  val stdin_pfd = $extfcall(int, "_spawn_res_stdin", res_ptr)
  val stdout_pfd = $extfcall(int, "_spawn_res_stdout", res_ptr)
  val stderr_pfd = $extfcall(int, "_spawn_res_stderr", res_ptr)
  (* Consume configs — C already handled the fds *)
  val () = _consume_configs(stdin_cfg, stdout_cfg, stderr_cfg)
in
  if pid >= 0 then
    $R.ok(spawn_pipes_mk(
      child_mk(pid),
      _make_pipe_fd(stdin_pfd),
      _make_pipe_fd(stdout_pfd),
      _make_pipe_fd(stderr_pfd)))
  else $R.err(~1)
end

implement child_wait(c) = let
  val+ ~child_mk(pid) = c
  val status = $extfcall(int, "_proc_wait", pid)
in
  if status >= 0 then $R.ok(status)
  else $R.err(status)
end

implement child_try_wait(c) = let
  val+ @child_mk(pid) = c
  val status = $extfcall(int, "_proc_try_wait", pid)
  prval () = fold@(c)
in
  if status >= 0 then $R.some(status)
  else if $AR.eq_int_int(status, ~2) then $R.none() (* still running *)
  else $R.none() (* error — treat as still running *)
end

implement child_pid(c) = let
  val+ @child_mk(pid) = c
  val p = pid
  prval () = fold@(c)
in p end
