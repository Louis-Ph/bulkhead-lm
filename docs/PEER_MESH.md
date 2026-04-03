# Peer Mesh

AegisLM can treat another AegisLM instance as an upstream LLM endpoint.

The dedicated provider kind is `aegis_peer`. It uses the same OpenAI-compatible
surface as `openai_compat`, but it is explicit in config and participates in the
peer hop guard carried by AegisLM headers.

## When to use it

- machine `B` should consume a model route exposed by machine `A`
- you want one AegisLM to front another without writing a separate microservice
- you want bounded peer-to-peer forwarding instead of an unguarded OpenAI-style proxy chain

## Minimal route example on machine B

```json
{
  "routes": [
    {
      "public_model": "remote-claude",
      "backends": [
        {
          "provider_id": "peer-a",
          "provider_kind": "aegis_peer",
          "upstream_model": "claude-sonnet",
          "api_base": "https://machine-a.example.net:4100/v1",
          "api_key_env": "AEGIS_MACHINE_A_KEY"
        }
      ]
    }
  ]
}
```

`AEGIS_MACHINE_A_KEY` must contain a virtual key that machine `A` accepts.

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

- `x-aegislm-request-id`
- `x-aegislm-hop-count`

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
