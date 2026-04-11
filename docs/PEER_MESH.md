# Peer Mesh

BulkheadLM can treat another BulkheadLM instance as an upstream LLM endpoint. This is where the project stops looking like a simple gateway and becomes a horizontal AI mesh: peer-to-peer, multi-machine, and explicitly routed instead of loosely chained.

There are two explicit peer transports:

- `bulkhead_peer`: HTTP OpenAI-compatible peering
- `bulkhead_ssh_peer`: SSH transport over the existing JSONL worker protocol

Both participate in the same peer hop guard carried by BulkheadLM headers.

## When to use it

- machine `B` should consume a model route exposed by machine `A`
- you want one BulkheadLM to front another without writing a separate microservice
- you want bounded peer-to-peer forwarding instead of an unguarded OpenAI-style proxy chain

If machine `B` does not have BulkheadLM installed yet, machine `A` can also serve a
local bootstrap installer over SSH via `scripts/remote_install.sh`. The bootstrap
flow is documented in [SSH_REMOTE.md](SSH_REMOTE.md).

## Minimal route example on machine B

### HTTP peer

```json
{
  "routes": [
    {
      "public_model": "remote-claude",
      "backends": [
        {
          "provider_id": "peer-a",
          "provider_kind": "bulkhead_peer",
          "upstream_model": "claude-sonnet",
          "api_base": "https://machine-a.example.net:4100/v1",
          "api_key_env": "BULKHEAD_MACHINE_A_KEY"
        }
      ]
    }
  ]
}
```

`BULKHEAD_MACHINE_A_KEY` must contain a virtual key that machine `A` accepts.

### SSH peer

```json
{
  "routes": [
    {
      "public_model": "remote-claude-ssh",
      "backends": [
        {
          "provider_id": "peer-a-ssh",
          "provider_kind": "bulkhead_ssh_peer",
          "upstream_model": "claude-sonnet",
          "api_key_env": "BULKHEAD_MACHINE_A_KEY",
          "ssh_transport": {
            "destination": "ops@machine-a.example.net",
            "host": "machine-a.example.net",
            "remote_worker_command": "/opt/bulkhead-lm/scripts/remote_worker.sh",
            "remote_config_path": "/etc/bulkhead-lm/gateway.json",
            "remote_jobs": 1,
            "options": ["-i", "/Users/me/.ssh/bulkhead_lm_mesh"]
          }
        }
      ]
    }
  ]
}
```

For `bulkhead_ssh_peer`, `api_key_env` is still the remote virtual key, but it is
passed to the remote worker wrapper as `--api-key` rather than as an HTTP header.

Then callers can use machine `B` as usual:

```bash
curl -s http://machine-b.example.net:4100/v1/chat/completions \
  -H "Authorization: Bearer sk-b-client" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "remote-claude",
    "messages": [
      { "role": "user", "content": "Reply with OK." }
    ]
  }'
```

## Hop guard

Peer calls carry:

- `x-bulkhead-lm-request-id`
- `x-bulkhead-lm-hop-count`

By default, the security policy enables this peer mesh guard and sets:

- `max_hops = 1`

That default allows:

- client -> machine `B` -> machine `A`

and blocks deeper chains such as:

- client -> `B` -> `A` -> `C`
- client -> `A` -> `B` -> `A`

If you intentionally want a longer chain, raise `mesh.max_hops` in the security
policy on the receiving machines.

## Private network note

The default egress policy blocks private and loopback destinations. If peers
communicate over private RFC1918 or ULA addresses, the receiving config must
explicitly relax that policy, for example by setting `egress.deny_private_ranges`
to `false`.

This is intentionally not automatic. Peer routing is explicit, but private-range
egress is still a deployment security decision.

## SSH transport note

`bulkhead_ssh_peer` opens one `ssh -T` session per upstream request in the current
implementation. That keeps the first transport simple and isolated, but it is
not yet a pooled SSH connection manager.
