# Symphony Agents

Symphony orchestrates **Coding Agents** to autonomously execute project work. This document defines what an agent is in the Symphony ecosystem, how they operate, and the patterns they follow.

## What is a Symphony Agent?

In Symphony, an **Agent** is a stateful, tool-augmented session powered by a Large Language Model (LLM) like Codex or Gemini. Unlike simple one-off LLM completions, Symphony agents:

1. **Operate in Isolated Workspaces**: Each agent runs inside a dedicated directory (workspace) created specifically for the issue it is solving.
2. **Use Specialized Skills**: Agents have access to repository-local skills (located in `.codex/skills/`) that allow them to perform complex operations like committing code, interacting with Linear, and landing Pull Requests.
3. **Follow Multi-Turn Workflows**: Agents can run for multiple back-to-back turns (up to `agent.max_turns`) to solve complex problems iteratively.
4. **Adhere to In-Repo Policy**: The agent's instructions, posture, and constraints are defined in the repository's `WORKFLOW.md` file.

## Agent Lifecycle

1. **Discovery**: The Symphony Orchestrator polls the issue tracker (e.g., Linear) for candidate issues.
2. **Workspace Preparation**: Symphony creates a sanitized workspace directory and runs lifecycle hooks (e.g., `git clone`).
3. **Session Launch**: Symphony launches a coding agent in "app-server" mode inside the workspace.
4. **Execution**: The agent follows a **Research → Strategy → Execution** lifecycle.
5. **Handoff**: Once the work is complete, the agent transitions the issue to a handoff state (e.g., `Human Review` or `Done`).

## Agent Personas

While most agents act as **Workers** (implementing features or fixing bugs), Symphony supports different personas through workflow prompts and skill-specific instructions:

- **Worker**: The primary agent that reproduces issues, implements fixes, and adds tests.
- **Reviewer**: Specialized personas used during the `land` skill to provide multi-perspective code reviews before a PR is merged.

## Core Patterns

### The Codex Workpad

Agents use a persistent comment on the issue tracker called the **Codex Workpad** as their primary state tracking mechanism. The workpad includes:
- **Environment Stamp**: The host, directory, and commit SHA where the agent is running.
- **Plan**: A hierarchical checklist of tasks.
- **Acceptance Criteria**: Concrete goals that must be met for the task to be considered complete.
- **Validation**: Evidence of testing and verification.
- **Notes**: A log of progress and decisions.

### Research → Strategy → Execution

Agents are instructed to spend significant effort upfront on research and planning before modifying code.
1. **Research**: Systematically map the codebase and validate assumptions.
2. **Strategy**: Formulate a grounded plan and share it in the workpad.
3. **Execution**: Iterate through the plan, validating each sub-task.

## Skills and Tools

Agents extend their capabilities through:
- **Repository Skills**: Located in `.codex/skills/`, these provide high-level abstractions for common tasks (e.g., `land`, `commit`).
- **Dynamic Tools**: Symphony injects tools like `linear_graphql` directly into the agent session, allowing for secure and efficient interaction with external services.
