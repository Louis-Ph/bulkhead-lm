# User Connector Roadmap

The point of this roadmap is simple: advanced AI infrastructure should feel immediate to normal people. BulkheadLM already acts as a secure AI router and hyper-connector under the hood, and this rollout is how that power reaches mainstream chat surfaces with the least adaptation cost.

This roadmap keeps connector growth explicit, hierarchical, and grounded in
two constraints:

- reach: prioritize the channels that reduce adaptation cost for the largest audience
- operability: prefer channels with stable webhook and send APIs before channels that require beta programs, heavier review, or more custom runtime behavior

## Wave 1

Goal: maximize worldwide reach with mature chat APIs and low user adaptation.

- WhatsApp Cloud API
- Telegram Bot API
- Facebook Messenger
- Instagram Direct

Status:

- implemented: WhatsApp Cloud API, Telegram Bot API, Facebook Messenger, Instagram Direct

## Wave 2

Goal: cover high-value regional or growth channels that still fit the same
request-response webhook architecture.

- LINE
- TikTok Direct Messages
- Viber
- WeChat

Implementation notes:

- implemented: LINE, Viber, WeChat Service Account
- deferred: TikTok Direct Messages
- `LINE` fits the current webhook and reply-token model directly, so it extends the existing architecture without adding a new runtime class
- `Viber` also fits the webhook plus send-message pattern, with one auth token reused for webhook verification and outbound delivery
- `WeChat Service Account` now covers plaintext mode plus the official compatibility and security modes through passive XML replies wrapped in the encrypted `Encrypt / MsgSignature / TimeStamp / Nonce` envelope
- `TikTok Direct Messages` remains strategically relevant and explicitly prioritized, but the public business messaging surface still does not expose a clean enough webhook-plus-reply contract here to ship without guesswork
- Asia-first expansion now favors deeper `WeChat` operability before adding another region-specific connector with weaker public protocol evidence

## Wave 3

Goal: add specialized, regional, or lower-fit channels after the mainstream chat
surface is broad enough.

- Discord
- Snapchat
- KakaoTalk
- Zalo
- QQ

Implementation notes:

- implemented: Discord Interactions
- deferred: Snapchat, KakaoTalk, Zalo, QQ
- `Discord Interactions` fit after introducing a dedicated signed-webhook plus deferred-response class instead of forcing Discord into the simpler synchronous webhook-reply pattern used by most chat connectors here
- `Discord` still is not treated as a general gateway-bot message connector here; arbitrary message-content listeners would require a separate gateway runtime class
- `Snapchat` is globally large, but the business messaging surface is less aligned with the current direct webhook connector model
- `KakaoTalk` is regionally important, but the current official surface is stronger for channel add, chat launch, and relationship status than for a general inbound assistant conversation webhook
- `QQ` is regionally important and now looks more likely through the QQ bot ecosystem than through a classic messenger webhook surface, which makes it a distinct connector class rather than a drop-in copy of WhatsApp or Telegram
- `Zalo` remains strategically relevant, but its public developer portal is still less directly extractable here than the connectors already implemented

## Architecture guardrails

- keep each connector under `src/connectors/` with one wrapper per platform
- keep rollout order and runtime class explicit in a central connector registry instead of encoding it in nested route conditionals
- factor repeated protocol logic into shared modules before adding the second copy
- keep all user connectors on the standard BulkheadLM virtual-key auth path
- require every enabled connector to own a unique `webhook_path`, and reject ambiguous configs during load
- scope conversation memory by the smallest stable external conversation identity
- add focused config and webhook tests for every new connector before enabling it in examples
