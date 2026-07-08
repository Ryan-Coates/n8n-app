# Copilot Architecture & Workflow Guide
### Agents • Skills • Instructions • Development Flows

---

## 1. Purpose
This document defines how GitHub Copilot is used within this repository to support:

- Workflow planning  
- Workflow implementation  
- Platform maintenance  
- Documentation  
- Testing  
- Schema validation  
- GitOps practices  

The goal is to create a consistent, predictable, and safe development environment where Copilot assists architects and developers without generating unstructured or inconsistent output.

This repository contains both:

- The n8n automation platform  
- All workflows, tests, schemas, and shared libraries  

Copilot must operate within these boundaries.

---

## 2. Development Roles

### Architect / Researcher
Responsible for:
- Planning new workflows  
- Designing changes to existing workflows  
- Producing specifications  
- Writing workflow READMEs  
- Defining inputs, outputs, schemas, and edge cases  
- Escalating model complexity when needed  

### Developer
Responsible for:
- Implementing workflow specifications  
- Creating workflow.json  
- Writing tests (unit, integration, snapshot)  
- Writing documentation  
- Updating schemas  
- Maintaining platform code (n8n, Docker, MCP tools, shared libs)  
- Ensuring CI/CD compatibility  

---

## 3. Development Flows

### Flow A — Workflow Creation
1. Architect designs workflow  
2. Architect produces specification + README  
3. Developer implements workflow  
4. Developer writes tests  
5. Developer validates schemas  
6. Developer updates documentation  
7. CI validates everything  
8. Deployment pipeline pushes to staging → production  

### Flow B — Platform Maintenance
1. Developer updates n8n stack  
2. Developer updates shared libraries  
3. Developer updates MCP tools  
4. Developer updates CI/CD  
5. Developer updates Copilot agents/skills  
6. Developer ensures platform stability  

---

## 4. Copilot Instructions (Suggested Repo‑Wide Rules)

### 4.1 Workflow Structure
Copilot must:
- Follow the workflow folder structure  
- Generate workflow.json, tests, schemas, and documentation together  
- Avoid creating workflows outside the `workflows/` directory  
- Use shared libraries instead of duplicating logic  

### 4.2 Documentation Standards
Copilot must generate README.md files containing:
- Overview  
- Purpose  
- Inputs  
- Outputs  
- Dependencies  
- LLM usage  
- Token budget  
- Testing instructions  
- Deployment notes  

### 4.3 Testing Requirements
Copilot must generate:
- Unit tests  
- Integration tests  
- Snapshot tests  
- Mocks  
- Schema validation tests  

### 4.4 Naming Conventions
Copilot must use:
- kebab-case for workflow folders  
- `<type>.test.js` for tests  
- `<name>.schema.json` for schemas  
- `config.yaml` for metadata  

### 4.5 Model Tiering
Copilot must:
- Use low-cost models for planning and simple tasks  
- Escalate only when complexity requires it  
- Avoid premium models during development unless explicitly needed  

### 4.6 GitOps Rules
Copilot must:
- Treat workflow.json as the source of truth  
- Avoid suggesting direct edits in n8n UI  
- Ensure all changes include tests + documentation  
- Ensure CI/CD compatibility  

### 4.7 Developer Experience
Copilot should:
- Suggest reusable patterns  
- Suggest schema-first workflow design  
- Suggest test-first workflow development  
- Suggest minimal, structured prompts  

Copilot should not:
- Suggest verbose prompts  
- Suggest unbounded LLM usage  
- Suggest premium models unnecessarily  

---

## 5. Agents

### 5.1 Orchestrator Agent
**Purpose:**  
Route user requests to the correct agent.

**Model:**  
Low-cost model.

**Behaviour:**  
- Handles simple tasks directly  
- Determines whether the request requires the Architect or Developer  
- Enforces repo-wide Copilot instructions  
- No skills (routing only)

**Routing Logic:**  
- Planning/design/documentation → Architect  
- Implementation/testing/platform changes → Developer  
- Trivial tasks → handled directly  

---

### 5.2 Architect Agent
**Purpose:**  
Plan workflows and produce specifications.

**Model:**  
Starts with low-cost model, escalates when needed.

**Skills:**  
- `design-workflow`  
- `create-spec`  
- `write-readme`  

**Behaviour:**  
- Produces workflow plans  
- Defines inputs, outputs, schemas  
- Writes documentation  
- Designs changes to existing workflows  
- Hands off to Developer Agent  

---

### 5.3 Developer Agent
**Purpose:**  
Implement workflows and maintain the platform.

**Model:**  
Mid-tier model.

**Skills:**  
- `create-workflow`  
- `generate-tests`  
- `validate-schema`  
- `update-platform`  

**Behaviour:**  
- Implements workflow.json  
- Writes tests  
- Writes documentation  
- Updates schemas  
- Maintains n8n stack + shared libs  
- Ensures CI/CD compatibility  

---

## 6. Skills

### Architect Skills
- `design-workflow`  
- `create-spec`  
- `write-readme`  

### Developer Skills
- `create-workflow`  
- `generate-tests`  
- `validate-schema`  
- `update-platform`  

Skills are intentionally minimal to keep the system simple and predictable.

---

## 7. Interaction Model

### Example Flow
User:  
> “Create a new workflow for CRM lead routing.”

Orchestrator Agent:  
- Determines this is a workflow design request  
- Routes to Architect Agent  

Architect Agent:  
- Designs workflow  
- Produces spec + README  
- Hands off to Developer Agent  

Developer Agent:  
- Implements workflow.json  
- Writes tests  
- Writes documentation  
- Validates schemas  

---

## 8. Future Extensions
- Multi-tenant workflow planning  
- Model tiering enforcement  
- LLM snapshot testing integration  
- MCP tool integration rules  
- Deployment agent for GitOps pipelines  

---

## copilot prompt


You are setting up a structured Copilot agent system for this repository. 
Use the existing codebase, folder structure, workflows, tests, and documentation to understand how the repo is organised. 
Your job is to create and maintain a consistent Copilot architecture with the following components:

============================================================
## 1. Repo-Wide Copilot Instructions
============================================================
Create a file named `COPILOT_INSTRUCTIONS.md` in the repo root.

The instructions must:
- enforce the workflow folder structure
- enforce documentation standards (README.md with required sections)
- enforce testing standards (unit, integration, snapshot)
- enforce schema usage (input/output schemas)
- enforce naming conventions (kebab-case folders, schema.json, config.yaml)
- enforce GitOps rules (workflow.json is the source of truth)
- enforce CI/CD compatibility
- enforce model tiering (low-cost for planning, escalate only when needed)
- ensure developers write tests + documentation for every change
- ensure architects produce specifications before implementation
- ensure Copilot uses shared libraries instead of duplicating logic
- ensure Copilot validates structure against the existing codebase

============================================================
## 2. Agents
============================================================
Create two agents in `.github/agents/`:

### Orchestrator Agent
File: `.github/agents/orchestrator.agent.md`
Purpose:
- Use a low-cost model
- Handle simple tasks directly
- Route requests to Architect or Developer
- Enforce repo-wide instructions
- Determine whether a request is:
  - workflow planning / documentation → Architect
  - workflow implementation / testing / platform maintenance → Developer
- No skills

### Architect Agent
File: `.github/agents/architect.agent.md`
Purpose:
- Start with low-cost model, escalate when needed
- Plan workflows and features
- Produce specifications
- Write workflow READMEs
- Define inputs, outputs, schemas, edge cases
Skills:
- design-workflow
- create-spec
- write-readme

### Developer Agent
File: `.github/agents/developer.agent.md`
Purpose:
- Implement workflow specifications
- Create workflow.json
- Write tests (unit, integration, snapshot)
- Write documentation
- Update schemas
- Maintain platform code (n8n, Docker, MCP tools, shared libs)
Skills:
- create-workflow
- generate-tests
- validate-schema
- update-platform

============================================================
## 3. Skills
============================================================
Create skill files in `.github/skills/`:

Architect Skills:
- design-workflow.skill.md
- create-spec.skill.md
- write-readme.skill.md

Developer Skills:
- create-workflow.skill.md
- generate-tests.skill.md
- validate-schema.skill.md
- update-platform.skill.md

Each skill file must:
- describe the skill purpose
- define expected inputs/outputs
- follow repo-wide Copilot instructions
- reference the existing codebase for structure validation

============================================================
## 4. Behaviour Requirements
============================================================
Copilot must:
- inspect the existing repo structure before generating anything
- verify that new workflows follow the established folder structure
- verify tests and documentation exist for every workflow
- verify schemas are present and valid
- verify shared libraries are used instead of duplication
- verify CI/CD compatibility
- maintain consistency with existing code and patterns

============================================================
## 5. Output
============================================================
Generate:
- COPILOT_INSTRUCTIONS.md
- all agent files
- all skill files

Do not modify existing workflows or platform code unless asked.
Ensure all generated files follow the repo’s conventions and structure.
