# Guided connection preview 0.7

Implemented: a single Connect entry point; Advanced-only relay configuration; baked-in production relay option; browser handoff with prefilled code; native QR rendering; fallback code; signed-in account and server-resolved device review before explicit claim; bounded browser polling; authenticated WebSocket readiness before connected state; server-side enrollment cancellation including a redeem/cancel race; persistent offline cancellation warning.

Validation: 40 Python relay/contract/protocol tests, 8 Swift native tests, and Node onboarding behavior checks passed. The Node test uses a simulated browser/auth service and does not establish real hosted Auth0 completion. Real native QR scanning and signed-in pairing against a deployed relay remain unverified.

Release limitations: no production relay origin/Auth0 deployment, verified Muse connector authorization, or Developer ID notarization. The installed build is a local preview and explicitly explains unavailable online setup. OS action blockers from 0.6 remain unchanged.
