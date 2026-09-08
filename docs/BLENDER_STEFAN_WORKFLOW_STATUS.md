# Stefan workflow verification — 2026-09-07

Result: NOT YET EQUIVALENT. Direct Codex-to-Bridge authentication failed before scene execution.

- Supplied evidence: ASTRA_BLENDER_STEFAN_WORKFLOW.md and Stefan video screenshot around 4:50 (`https://www.youtube.com/watch?v=8MUk-tQTiwE`).
- Screenshot: Codex Astra xhigh → higgsfield.bl_execute → versioned bpy script in the open Blender → render file → image inspection.
- Local: Blender 5.1.2 and official Higgsfield add-on 1.5.50 enabled/authenticated. Vendor mcp.log confirms outbound WebSocket connected.
- Fixed missing Codex MCP registration: global server `higgsfield`, URL `https://bridge.higgsfield.ai/mcp`, timeout 180s, OAuth callback base `http://localhost:56444/callback`, listener 56444.
- Project default: C:/Oathwake/.codex/config.toml selects gpt-6-astra with xhigh. This does not certify the settings of an already active turn.
- OAuth consent completed, but `codex mcp login higgsfield` exited with `Authorization server issuer mismatch: expected https://bridge.higgsfield.ai, received https://clerk.higgsfield.ai`.
- No cube, shrine, checkpoint or rendered preview was created by the direct Bridge test. Never label it passed.

Next: use a provider/client-supported configuration with consistent OAuth issuer; retain issuer validation. Authenticate, reload the MCP server/tool catalog, inspect tools, then execute the cube and two-render visual refinement test in the open Blender. No headless substitute and no separate Supercomputer web agent as proof of this workflow.

Configuration documentation: https://learn.chatgpt.com/docs/extend/mcp and https://learn.chatgpt.com/docs/config-file/config-reference.
