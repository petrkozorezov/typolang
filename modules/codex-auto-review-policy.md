# Project outer-sandbox policy

The Codex process runs inside a project-owned outer bubblewrap sandbox. An
approved sandbox escape leaves the built-in Codex sandbox but remains inside
that outer filesystem and PID boundary. The outer sandbox is not a network
boundary: it shares the host network namespace.

Apply these project-specific rules in addition to every rule above:

- Assess the concrete action and its expected side effects within the outer
  sandbox. Approve ordinary task-related builds, tests, benchmarks, diagnostics,
  and dependency preparation when they do not violate the rules above or the
  protections below. The availability of additional capabilities after an
  escape is not by itself evidence that the command will use them unsafely.
- Approve filesystem permissions for task-related directories, including
  recursive access to source trees, build outputs, caches, and temporary files.
  A request need not enumerate individual files or prove that no narrower path
  could work. Deny unrelated filesystem-wide access and access to Codex state
  or credentials, except the read-only skill/plugin/proxy resources already
  exposed by the project profile.
- Approve a managed-proxy network grant only when it is limited to the exact
  host, protocol, and port required for the stated task. Deny broad domain
  patterns, unrestricted network access, and requests that could use host
  loopback or abstract Unix sockets.
- Prefer filesystem or managed-proxy grants when they are sufficient. Approve
  a built-in sandbox escape for a concrete task-related operation when sandbox
  restrictions prevent it from running, including Nix daemon access and local
  sockets created by the task's own build or test processes. Do not require
  exhaustive attempts to express the operation as a narrower grant.
- Review the full command, including invoked scripts and Nix expressions.
  Environment assignments, shell wrappers, sequencing, pipelines, redirections
  to task-related files, and command substitution are allowed when their
  component actions are safe and task-related. Their syntax alone is not a
  reason to deny. Nix and devenv operations may evaluate, build, or prepare the
  project environment through the untrusted Nix daemon; deny operations that
  inspect Codex state or credentials or change host security configuration.
- Deny sandbox escapes whose purpose is to bypass the network proxy, reach
  unrelated host loopback services or abstract Unix sockets, probe credentials,
  or exfiltrate data. Treat an escaped command as having unrestricted outbound
  network access even though its filesystem and PID visibility remain bounded
  by bubblewrap.
