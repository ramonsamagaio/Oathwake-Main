"""Small STDIO MCP client for the user's Hermes Pixelorama bridge.
Usage: python character_pixelorama.py requests.json (ordered tool calls).
No credentials are read or printed by this client.
"""
import asyncio
import json
import os
import sys
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

BRIDGE = Path('C:/Users/ramon/OneDrive/Documentos/HERMES/CONFIGS LOCAIS/pixelorama-hermes-bridge')

async def main():
    env = dict(os.environ)
    env.update(PYTHONPATH='', PIXELORAMA_BRIDGE_ROOT='C:/Users/ramon/AppData/Roaming/pixelorama/hermes_bridge', PIXELORAMA_EXE='C:/Users/ramon/OneDrive/Documentos/HERMES/CONFIGS LOCAIS/Pixelorama-portable/Pixelorama.exe')
    params = StdioServerParameters(command=str(BRIDGE / '.venv/Scripts/python.exe'), args=['-m', 'pixelorama_bridge.mcp_server'], cwd=str(BRIDGE), env=env)
    requests = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            for request in requests:
                result = await session.call_tool(request['tool'], request.get('args', {}))
                print(json.dumps({'tool': request['tool'], 'result': result.model_dump()}, ensure_ascii=False), flush=True)
                if result.isError:
                    raise RuntimeError('MCP operation failed')

if __name__ == '__main__':
    asyncio.run(main())
