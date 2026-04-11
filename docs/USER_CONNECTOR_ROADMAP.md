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

- `LINE` fits the current webhook and reply-token model well and is the most straightforward next step
- `TikTok Direct Messages` is strategically relevant but still operationally heavier because the business messaging surface is newer
- `Viber` is structurally close to the current connectors but lower priority by global reach
- `WeChat` matters for reach but usually carries the highest operational and regional complexity in this wave

## Wave 3

Goal: add specialized, regional, or lower-fit channels after the mainstream chat
surface is broad enough.

- Discord
- Snapchat
- KakaoTalk
- Zalo
- QQ

Implementation notes:

- `Discord` is technically accessible, but its community/server dynamics differ from direct consumer messaging
- `Snapchat` is globally large, but the business messaging surface is less aligned with the current direct webhook connector model
- `KakaoTalk`, `Zalo`, and `QQ` are regionally important and should be staged after broader global channels are covered

## Architecture guardrails

- keep each connector under `src/connectors/` with one wrapper per platform
- factor repeated protocol logic into shared modules before adding the second copy
- keep all user connectors on the standard BulkheadLM virtual-key auth path
- scope conversation memory by the smallest stable external conversation identity
- add focused config and webhook tests for every new connector before enabling it in examples
