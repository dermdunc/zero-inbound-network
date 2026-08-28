# Risks: Zero-Inbound Network

## Risk Register

Machine-readable risk state lives in `.hekton/risk-register.yaml`. Keep this
Markdown file as the human-readable explanation of material risks and mitigations.

| ID | Date | Risk | Impact | Likelihood | Mitigation | Status |
|---|---|---|---|---|---|---|
| RISK-0001 | 2026-08-28 | Initial governance baseline needs first human/agent review | Medium | Medium | Run governance preflight and end-session review during the first material session | Open |
| RISK-0002 | 2026-08-28 | Single-control security model (zero-inbound SG only, no NAT/private-subnet second layer) means a Cloudflare Access misconfiguration or tunnel-token leak has no compensating network-layer control | High | Low | Documented explicitly in `docs/well-architected.md` as a deliberate tradeoff, with the dual-control alternative named for when this pattern is the wrong fit. Tunnel token stored as SSM SecureString, read only by the task's execution role. | Open — accepted tradeoff, not a defect |
| RISK-0003 | 2026-08-28 | No Terraform remote-state backend configured in this reference repo | Medium | Certain (by design) | `docs/well-architected.md` "State" section requires configuring locked remote state before any real apply; this repo intentionally ships with none to stay a pure reference. Anyone adapting this repo must add one first. | Open — by design, disclosed |
| RISK-0004 | 2026-08-28 | `enable_ecs_exec` (interactive shell into a running container) is a real blast-radius increase if left on | Low | Low | Defaults to `false`; module comment states explicitly this exists so "need a shell" never becomes a reason to open an ingress rule instead | Mitigated (safe default) |
