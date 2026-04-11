# User Connector Roadmap

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

- implemented: LINE, Viber
- deferred: TikTok Direct Messages, WeChat
- `LINE` fits the current webhook and reply-token model directly, so it extends the existing architecture without adding a new runtime class
- `Viber` also fits the webhook plus send-message pattern, with one auth token reused for webhook verification and outbound delivery
- `TikTok Direct Messages` remains strategically relevant, but the business messaging surface is still operationally heavier and less open than the connectors already shipped here
- `WeChat` matters for reach, but it usually adds more regional, operational, and protocol complexity than the rest of this wave

## Wave 3

Goal: add specialized, regional, or lower-fit channels after the mainstream chat
surface is broad enough.

- Discord
- Snapchat
- KakaoTalk
- Zalo
- QQ

Implementation notes:

- audited and deferred: Discord, Snapchat, KakaoTalk, Zalo, QQ
- `Discord` is technically accessible, but its gateway and interaction model diverges from the simpler direct webhook reply architecture used by the mainstream chat connectors here
- `Snapchat` is globally large, but the business messaging surface is less aligned with the current direct webhook connector model
- `KakaoTalk`, `Zalo`, and `QQ` are regionally important, but they currently impose higher regional or partner-distribution friction than the channels already implemented

## Architecture guardrails

- keep each connector under `src/connectors/` with one wrapper per platform
- factor repeated protocol logic into shared modules before adding the second copy
- keep all user connectors on the standard BulkheadLM virtual-key auth path
- scope conversation memory by the smallest stable external conversation identity
- add focused config and webhook tests for every new connector before enabling it in examples
