// The sandbox container's security posture lives here as a pure builder, so the
// guarantees (never privileged, no-new-privileges, all caps dropped, non-root,
// no host binds beyond the session workspace — except operator-confirmed
// /folders mounts validated by mount-safety) are unit-tested and cannot silently
// regress. server.js composes the runtime values and calls these.

/**
 * The platform decides egress per run (admin setting + per-project override) and
 * sends the requested mode. Only "bridge" grants network; anything else — and any
 * unrecognized request (e.g. "host") — resolves to "none" (no network).
 */
export function resolveNetworkMode(requested) {
  return requested === "bridge" ? "bridge" : "none";
}

/**
 * Public resolvers for bridge sandboxes. Host Docker DNS often inherits the
 * Mac's Clash/Surge fake-ip resolver (198.18.0.0/15); the egress firewall then
 * DROPs those addresses and every fetch times out. Pinning real DNS avoids that.
 * Override with SANDBOX_DNS=1.1.1.1,8.8.8.8 (comma-separated).
 */
export function resolveSandboxDns(dnsEnv = process.env.SANDBOX_DNS) {
  const fromEnv = String(dnsEnv || "")
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
  return fromEnv.length ? fromEnv : ["223.5.5.5", "8.8.8.8"];
}

export function dnsEqual(a = [], b = []) {
  if (a.length !== b.length) return false;
  const sa = [...a].sort().join(",");
  const sb = [...b].sort().join(",");
  return sa === sb;
}

/**
 * Extract an IPv4 or IPv4:port allowlist entry from a proxy URL.
 * Hostnames are rejected — Docker's bridge gateway / LAN IP must be used so the
 * entrypoint can pin an iptables ACCEPT without DNS (which may be fake-ip).
 * Returns null when the value is empty or not a usable IPv4 proxy URL.
 */
export function proxyUrlToAllowEntry(raw) {
  const s = String(raw || "").trim();
  if (!s) return null;
  let url;
  try {
    url = new URL(s.includes("://") ? s : `http://${s}`);
  } catch {
    return null;
  }
  const host = url.hostname;
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return null;
  if (host.startsWith("169.254.")) return null;
  const port = url.port || (url.protocol === "https:" ? "443" : url.protocol === "http:" ? "80" : "");
  // socks / http proxies almost always need an explicit port in the URL; if the
  // parser left it empty, allow the whole host (operator supplied host-only).
  return port ? `${host}:${port}` : host;
}

/**
 * Resolve optional host-proxy settings for bridge sandboxes.
 * Controllers set SANDBOX_HTTP_PROXY / SANDBOX_HTTPS_PROXY / SANDBOX_ALL_PROXY
 * (and optional SANDBOX_EGRESS_ALLOW) so agents can reach foreign sites via a
 * host Clash/mihomo while the private-range DROP still blocks the rest of the LAN.
 */
export function resolveSandboxProxy(env = process.env) {
  const http = String(env.SANDBOX_HTTP_PROXY || "").trim();
  const https = String(env.SANDBOX_HTTPS_PROXY || (http ? http : "")).trim();
  const all = String(env.SANDBOX_ALL_PROXY || "").trim();
  const no = String(env.SANDBOX_NO_PROXY || "localhost,127.0.0.1").trim();
  const fromUrls = [http, https, all].map(proxyUrlToAllowEntry).filter(Boolean);
  const fromAllow = String(env.SANDBOX_EGRESS_ALLOW || "")
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean)
    .filter((e) => !e.startsWith("169.254."));
  const allow = [...new Set([...fromUrls, ...fromAllow])];
  const enabled = Boolean(http || https || all || allow.length);
  if (!enabled) {
    return { http: "", https: "", all: "", no: "", allow: [], fingerprint: "" };
  }
  // Proxy URLs must use an IPv4 host so the entrypoint can ACCEPT before DROP.
  if ((http || https || all) && fromUrls.length === 0 && allow.length === 0) {
    throw new Error(
      "SANDBOX_*_PROXY must use an IPv4 host (e.g. http://172.17.0.1:7890), not a hostname — " +
        "or set SANDBOX_EGRESS_ALLOW=x.x.x.x:port explicitly",
    );
  }
  const fingerprint = [http, https, all, no, allow.slice().sort().join(" ")].join("|");
  return { http, https, all, no, allow, fingerprint };
}

export function proxyEqual(a, b) {
  return (a || "") === (b || "");
}

/** Build the full dockerode createContainer config for a sandbox.
 *  `runtime` selects the OCI runtime (gVisor "runsc" by default in the secure
 *  profile; "runc" only for trusted/dev). `readonlyRootfs` makes the container's
 *  root filesystem immutable with a writable tmpfs at /tmp — strong hardening, but
 *  workflows that write into the image rootfs (e.g. `pip install` into system
 *  site-packages) must use /workspace or a venv; validate via the §9 workload matrix
 *  before assuming a given image tolerates it. */
export function buildSandboxConfig({
  image,
  sessionId,
  userId,
  wsHostPath,
  sharedHostPath,
  networkMode = "none",
  memoryBytes,
  nanoCpus,
  // gVisor's host-side runtime threads count toward Docker's pids cgroup. A
  // limit of 100 leaves too little headroom for normal image/document renderers
  // (ImageMagick, Chromium, LibreOffice) and can surface as misleading ENOMEM
  // errors from unrelated helpers such as tail/xargs. 256 still contains fork
  // bombs while leaving a useful workload budget across runc and runsc.
  pidsLimit = 256,
  nofileLimit = 65536,
  // Max bytes any single file may reach (RLIMIT_FSIZE). 0 = no cap. This is the
  // kernel-enforced, synchronous backstop the poll-based workspace quota lacks:
  // `fallocate -l 100G` / `dd` / `truncate` past the cap fail with EFBIG mid-write,
  // instead of slipping through as one command and only blocking the NEXT exec.
  fsizeBytes = 0,
  runtime,
  readonlyRootfs = true,
  // tmpfs sizes (MB). NOTE: tmpfs pages are charged against the container's
  // memory cgroup, so tmpMb + mcpTmpMb come OUT of memoryBytes — raising them
  // without raising Memory makes the container OOM sooner. Keep the sum well
  // under the memory budget. Tunable via SANDBOX_TMP_MB / SANDBOX_MCP_TMP_MB.
  tmpMb = 64,
  mcpTmpMb = 256,
  // Operator-confirmed host folders, bind-mounted at /folders/<name>. Each entry
  // is {hostPath, name, ro}; hostPath has already passed mount-safety validation
  // in server.js. Deliberately OUTSIDE /workspace so the quota/prune/delete_path
  // machinery never touches the operator's files. Empty by default (zero-config).
  mounts = [],
  // Public DNS for bridge mode (see resolveSandboxDns). Ignored when network is off.
  dns = [],
  // Host proxy for bridge sandboxes (mihomo/Clash). See resolveSandboxProxy.
  proxy = null,
  // Optional host path bind-mounted over /entrypoint.sh so operators can ship an
  // updated egress firewall without rebuilding the multi-GB sandbox image.
  entrypointHostPath = "",
}) {
  const proxyCfg = proxy && networkMode === "bridge" ? proxy : null;
  const proxyEnv = [];
  if (proxyCfg) {
    if (proxyCfg.allow?.length) proxyEnv.push(`SANDBOX_EGRESS_ALLOW=${proxyCfg.allow.join(" ")}`);
    if (proxyCfg.http) {
      proxyEnv.push(`HTTP_PROXY=${proxyCfg.http}`, `http_proxy=${proxyCfg.http}`);
    }
    if (proxyCfg.https) {
      proxyEnv.push(`HTTPS_PROXY=${proxyCfg.https}`, `https_proxy=${proxyCfg.https}`);
    }
    if (proxyCfg.all) {
      proxyEnv.push(`ALL_PROXY=${proxyCfg.all}`, `all_proxy=${proxyCfg.all}`);
    }
    if (proxyCfg.no) {
      proxyEnv.push(`NO_PROXY=${proxyCfg.no}`, `no_proxy=${proxyCfg.no}`);
    }
  }
  return {
    Image: image,
    name: `sandbox-${sessionId}`,
    // When egress is on (bridge), tell the entrypoint to install the egress
    // firewall that blocks private/internal ranges (see sandbox-entrypoint.sh).
    // No ambient DISPLAY: there's no persistent Xvfb to point at. GUI tools
    // (LibreOffice, wkhtmltopdf) render under a throwaway X server via the
    // `xvfb-run` shims in the image, which set their own DISPLAY per command.
    Env: [
      "PYTHONUNBUFFERED=1",
      "LANG=C.UTF-8",
      // XTABLES_LOCKFILE: iptables-legacy defaults its lock to /run/xtables.lock,
      // but the rootfs is read-only and /run isn't a writable mount — so the lock
      // open fails and the fail-closed egress firewall kills the container. Point
      // it at the writable /tmp tmpfs. (Only meaningful alongside the firewall.)
      ...(networkMode === "bridge" ? ["SANDBOX_EGRESS_FILTER=1", "XTABLES_LOCKFILE=/tmp/xtables.lock"] : []),
      ...proxyEnv,
    ],
    HostConfig: {
      Memory: memoryBytes,
      // Pin total memory+swap to Memory so a process can't spill past the RAM cap
      // into swap and dodge the OOM limit (Docker otherwise defaults swap to 2×).
      MemorySwap: memoryBytes,
      NanoCpus: nanoCpus,
      PidsLimit: pidsLimit,
      // Cap open file descriptors. The image default (~1M) lets a malicious
      // process open hundreds of thousands of FDs and destabilize the container's
      // own processes (the runner, on-demand render servers) and starve sibling
      // sandboxes on the host.
      Ulimits: [
        { Name: "nofile", Soft: nofileLimit, Hard: nofileLimit },
        // Single-file size cap — the only synchronous defense against a one-shot
        // `fallocate -l 100G`. Omitted when 0 so it's off unless the controller sets it.
        ...(fsizeBytes > 0 ? [{ Name: "fsize", Soft: fsizeBytes, Hard: fsizeBytes }] : []),
      ],
      // OCI runtime: gVisor ("runsc") in the secure profile. Omitted when unset so
      // the daemon default applies (dev/bare runs). Fail-closed availability is
      // enforced at boot by runtime-check.js, not here.
      ...(runtime ? { Runtime: runtime } : {}),
      // Immutable rootfs + a small writable /tmp. The agent's writable surface is
      // the bind-mounted /workspace (+ /shared); everything else is read-only.
      ReadonlyRootfs: readonlyRootfs,
      // NOTE: /tmp is size-capped, but the bind-mounted /workspace is NOT — Docker
      // bind mounts can't carry a size limit. A sandbox can fill the shared host's
      // disk via /workspace; the controller's MAX_WORKSPACE_MB only bounds uploads
      // routed through it. Enforce disk at the host (XFS project quota on DATA_ROOT
      // or a per-session sized volume); the controller logs `workspace.over_quota`.
      // /tmp stays noexec (can't drop+run a binary there). /opt/mcp is a separate
      // exec-allowed tmpfs for stdio MCP servers that self-install (npx/uvx need to
      // execute the fetched binary). It's ephemeral (dies with the session) and
      // outside the agent's /workspace, so it never pollutes the user's files.
      Tmpfs: {
        "/tmp": `rw,nosuid,nodev,noexec,size=${tmpMb}m`,
        // `exec` is REQUIRED and explicit — Docker adds noexec to tmpfs by default,
        // which would stop npx/uvx-installed server binaries from running here.
        "/opt/mcp": `rw,nosuid,nodev,exec,size=${mcpTmpMb}m,mode=1777`,
      },
      // Hard, non-negotiable isolation. Privileged is set explicitly so the
      // test pins it and a future edit can't omit it into a truthy default.
      Privileged: false,
      SecurityOpt: ["no-new-privileges"],
      CapDrop: ["ALL"],
      // Minimal caps for the boot sequence only: CHOWN lets the (root) entrypoint
      // fix ownership of the bind-mounted /workspace + /shared, and SETUID/SETGID
      // let it setpriv-drop to the unprivileged sandbox user. When egress is on the
      // entrypoint installs the iptables firewall before the drop, which needs
      // NET_ADMIN (write rules) *and* NET_RAW — under gVisor, with CapDrop ALL, the
      // iptables `filter` table can't initialize without NET_RAW ("Table does not
      // exist"), so the firewall fails closed and the container dies on startup.
      // (NET_RAW is honored only when runsc itself runs with --net-raw=true; see
      // scripts/install-gvisor.sh.) After the setpriv-drop, and for every agent
      // command (exec runs as uid 1000 with no caps), these buy nothing.
      CapAdd: ["CHOWN", "SETUID", "SETGID", ...(networkMode === "bridge" ? ["NET_ADMIN", "NET_RAW"] : [])],
      NetworkMode: networkMode,
      // Bypass host fake-ip DNS (Clash etc.) so public hosts resolve to real IPs
      // the egress filter will actually allow.
      ...(networkMode === "bridge" && dns.length ? { Dns: dns } : {}),
      Binds: [
        `${wsHostPath}:/workspace`,
        `${sharedHostPath}:/shared`,
        // Optional override of the image entrypoint (updated egress allowlist /
        // proxy pinholes) without rebuilding the sandbox image.
        ...(entrypointHostPath ? [`${entrypointHostPath}:/entrypoint.sh:ro`] : []),
      ],
      // Host folders use Mounts (not Binds): Mounts fails on a missing source
      // instead of silently creating a root-owned dir, and carries explicit
      // ReadOnly + Propagation. rprivate stops mount events propagating either way.
      ...(mounts.length ? { Mounts: mounts.map((m) => ({
        Type: "bind", Source: m.hostPath, Target: `/folders/${m.name}`,
        ReadOnly: m.ro !== false, BindOptions: { Propagation: "rprivate" },
      })) } : {}),
      Init: true,
    },
    // Intentionally NO `User` pin. The container must start as the image default
    // (root) so the entrypoint can chown the host-created bind mounts before the
    // agent touches them — that repair is what makes /workspace reliably writable
    // regardless of how the host created the mount source. The entrypoint then
    // immediately drops to uid 1000, and execInSandbox pins every command to
    // 1000:1000, so no agent code ever runs as root.
    WorkingDir: "/workspace",
    Tty: false,
    Labels: {
      "capka.session": sessionId,
      "capka.user": userId,
      "capka.network": networkMode,
      ...(proxyCfg?.fingerprint ? { "capka.proxy": proxyCfg.fingerprint } : {}),
    },
  };
}
