# Model allocation (Grok pointer)

**Plane A owner:** `~/.claude/rules/model-allocation.md`  
**ADRs:** `.jv` `docs/decisions/2026-07-23-work-classes-design-build-verify-deploy.md`
and `docs/decisions/2026-08-15-model-capability-classes.md` (GAP-483, accepted)

## Adapter summary

Work classes: **Design → Build → Verify → Deploy**.

Capability classes (not vendor names): **local · mechanical · frontier · reasoning**.

- **local**: custom on-box AI. Every model-to-UI setup on your silicon.
- **mechanical**: implementer of an existing spec or plan.
- **frontier**: moving capability ceiling (including future ASI/AGI).
- **reasoning**: think, search, pattern-match, synthesize, with context, as one loop.

Grok latest maps to **frontier**. Groq hosted maps to **mechanical**.
Fable-class maps to **reasoning**. Product default is **local**.

Hosted walks: hosted-byok plus mechanical, frontier, or reasoning.
Groq or Grok is enough. On-box cannot prove hosted.

Crown-jewel **Verify** is never the same session that **Build** authored.
Owner disposition is never model-allocated.

Do not re-author the full ladder here. Edit the Claude-compat owner file + ADRs.
