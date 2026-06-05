# Copyright (c) Microsoft. All rights reserved.

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from agent_framework import Agent, FileSkill, FileSkillScript, SkillsProvider
from agent_framework.foundry import FoundryChatClient
from agent_framework_foundry_hosting import ResponsesHostServer
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()


def run_local_skill_script(
    skill: FileSkill,
    script: FileSkillScript,
    args: list[str] | None = None,
) -> str:
    """Run a file-based skill script as a local Python subprocess.

    The LLM passes positional CLI arguments as a JSON array of strings
    (per ``FileSkillScript.parameters_schema``).
    """
    script_path = Path(script.full_path)
    if not script_path.is_file():
        return f"Error: Script file not found: {script_path}"

    cmd: list[str] = [sys.executable, str(script_path)]
    if isinstance(args, list):
        for item in args:
            if not isinstance(item, str):
                raise TypeError(
                    "File-based skill scripts only accept string CLI arguments "
                    f"but received a {type(item).__name__}."
                )
        cmd.extend(args)
    elif args is not None:
        raise TypeError(
            f"Expected a list of CLI arguments but received {type(args).__name__}."
        )

    try:
        completed = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=120,
            cwd=str(script_path.parent),
        )
    except subprocess.TimeoutExpired:
        return f"Error: Script '{script.name}' timed out after 120 seconds."
    except OSError as exc:
        return f"Error: Failed to execute script '{script.name}': {exc}"

    output = completed.stdout
    if completed.stderr:
        output += f"\nStderr:\n{completed.stderr}"
    if completed.returncode != 0:
        output += f"\nScript exited with code {completed.returncode}"
    return output.strip() or "(no output)"


def main():
    client = FoundryChatClient(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        credential=DefaultAzureCredential(),
    )

    skills_provider = SkillsProvider.from_paths(
        skill_paths=Path(__file__).parent / "skills",
        script_runner=run_local_skill_script,
    )

    agent = Agent(
        client=client,
        instructions=(
            "You are a helpful travel planning assistant. When a user asks for a PDF "
            "travel guide, city guide, itinerary, or trip-planning document, use the "
            "travel-guide skill. After creating a guide, tell the user where the PDF "
            "was saved and summarize what it contains."
        ),
        context_providers=[skills_provider],
        # History will be managed by the hosting infrastructure, thus there
        # is no need to store history by the service. Learn more at:
        # https://developers.openai.com/api/reference/resources/responses/methods/create
        default_options={"store": False},
    )

    server = ResponsesHostServer(agent)
    server.run()


if __name__ == "__main__":
    main()