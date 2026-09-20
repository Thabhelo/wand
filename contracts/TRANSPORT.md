# Cloudflare device transport

The WebSocket upgrade at /v1/ws/device includes X-Wand-Device-ID with the enrollment UUID. This public identifier selects the per-device Durable Object; it grants no access. The first message remains the v1 hello. Its token hash must belong to this exact device; mismatch/revocation closes 4003. Authentication and incoming messages are serialized so a heartbeat immediately following hello is safe. Credentials never appear in URLs.

JSON envelopes, action schemas, ready, heartbeat, expiry and reconnect rules are unchanged. The updated Mac agent sends the header. Python ignores it. Other agents using the Cloudflare endpoint must send it too.
