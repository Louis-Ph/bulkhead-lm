# SSH Remote Usage

This repository can be used remotely over SSH without running the HTTP gateway
as a separate microservice. The intended split is:

- human operator: `scripts/remote_starter.sh`
- programmatic caller: `scripts/remote_worker.sh`

That same worker wrapper is also the transport used by `provider_kind = "aegis_ssh_peer"`
when one AegisLM instance targets another directly over SSH.

Both wrappers assume the repository already exists on the remote machine.
Neither wrapper creates an `opam` switch or installs dependencies. They only:

1. resolve the repository root from the wrapper path,
2. load an `opam` environment when `opam` is available,
3. prefer an existing compiled client binary,
4. fall back to `dune exec` when necessary.

There is also a separate bootstrap path for a machine that does not yet have
AegisLM locally: `scripts/remote_install.sh`.

## Bootstrap a Clean Client Machine

If machine `A` already has AegisLM and machine `B` has only `ssh`, `tar`, and a
POSIX shell, `B` can install a local snapshot of AegisLM directly from `A`.

Recommended one-liner on the clean client machine:

```bash
ssh user@remote \
  '/opt/aegis-lm/scripts/remote_install.sh --emit-installer --origin user@remote' \
  | sh
```

By default, the emitted installer:

1. opens a second SSH fetch back to the same remote host,
2. downloads a filtered tarball of the remote repository,
3. installs it into `~/opt/aegis-lm`,
4. makes `run.sh`, `start-macos-client.command`, and shell wrappers executable.

Then start the local copy:

```bash
cd ~/opt/aegis-lm
./run.sh
```

Choose another local target directory:

```bash
ssh user@remote \
  '/opt/aegis-lm/scripts/remote_install.sh --emit-installer --origin user@remote' \
  | sh -s -- --target "$HOME/apps/aegis-lm"
```

Start immediately after install:

```bash
ssh user@remote \
  '/opt/aegis-lm/scripts/remote_install.sh --emit-installer --origin user@remote' \
  | sh -s -- --start
```

Advanced notes:

- the local installer also accepts `AEGISLM_INSTALL_SSH_BIN` and `AEGISLM_INSTALL_SSH_ARGS`
  if the callback SSH command needs a non-default binary, port, or identity file
- `AEGISLM_INSTALL_ARCHIVE_CMD` can override the archive fetch path entirely for custom transports
- the archive is intentionally filtered and excludes `.git`, `_build`, `_opam`, and `var`
- this is a bootstrap snapshot, not a `git clone`

## Human Remote Session

Use a pseudo-terminal:

```bash
ssh -t user@remote '/opt/aegis-lm/scripts/remote_starter.sh'
```

With an explicit config file:

```bash
ssh -t user@remote \
  '/opt/aegis-lm/scripts/remote_starter.sh --config /etc/aegislm/gateway.json'
```

If the remote machine uses a specific `opam` switch:

```bash
ssh -t user@remote \
  '/opt/aegis-lm/scripts/remote_starter.sh --switch 5.2.1-ocamlformat0262'
```

Notes:

- `ssh -t` is required so the starter gets a TTY.
- provider API keys must exist on the remote machine, not only on the local one.
- if the remote environment is normally loaded by a login shell, use `zsh -lc` or
  `bash -lc` in the SSH command that launches the wrapper.

Example:

```bash
ssh -t user@remote \
  'zsh -lc "/opt/aegis-lm/scripts/remote_starter.sh --config /etc/aegislm/gateway.json"'
```

## Programmatic Worker Over SSH

Use `ssh -T` and keep stdout reserved for JSONL:

```bash
ssh -T user@remote \
  '/opt/aegis-lm/scripts/remote_worker.sh --config /etc/aegislm/gateway.json --jobs 4'
```

Then write one JSON request per line to stdin and read one JSON response per line
from stdout.

Example request line:

```json
{"id":"job-1","kind":"chat","request":{"model":"claude-sonnet","messages":[{"role":"user","content":"Reply with OK."}]}}
```

Wrapper options:

- `--config FILE`
- `--jobs N`
- `--authorization VALUE`
- `--api-key TOKEN`
- `--switch NAME`

Example with an explicit client token:

```bash
ssh -T user@remote \
  '/opt/aegis-lm/scripts/remote_worker.sh --config /etc/aegislm/gateway.json --api-key sk-aegis-prod'
```

## Operational Advice

- Prefer `scripts/remote_starter.sh` for humans and `scripts/remote_worker.sh` for programs.
- Use `scripts/remote_install.sh` when the local client machine does not yet have AegisLM at all.
- Do not use the interactive starter for machine-to-machine traffic.
- Avoid banners or shell startup output on stdout when using the worker, otherwise JSONL consumers will break.
- If the remote repository is already built, the wrappers prefer the compiled client binary before trying `dune exec`.
- If you want a stable host-level command, install a symlink such as:

```bash
ln -sf /opt/aegis-lm/scripts/remote_worker.sh ~/bin/aegislm-worker
ln -sf /opt/aegis-lm/scripts/remote_starter.sh ~/bin/aegislm-starter
```

Then the SSH entrypoints become:

```bash
ssh -t user@remote aegislm-starter
ssh -T user@remote aegislm-worker
```
