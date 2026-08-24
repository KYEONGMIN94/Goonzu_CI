# Goonzu CI

This repository is the reviewable automation layer for the Visual Studio .NET 2003 Goonzu build. It never owns production deployment or game-client control.

## Design

1. Checkout an exact `Goonzu_Build` branch and record its commit SHA.
2. Run preflight and classify the minimum build impact.
3. Rewrite every selected VC7 project output into the Jenkins workspace.
4. Refuse to build if an output, intermediate, linker, or PDB path still targets a known live directory.
5. Build only the selected target with `devenv.com`.
6. Archive logs, binaries, sizes, and SHA-256 hashes.
7. Stop. Publishing and runtime testing are separate human-approved workflows.

## Targets

| Target | Contents |
| --- | --- |
| `None` | Documentation and workflow-only changes |
| `Client` | `Release_Korea` client |
| `GameServer` | `ReleaseServer_Korea` world server |
| `ClientGameServer` | Client and world server |
| `ServerSuite` | Master, Agent, AccountDB, GameDB, Auth, and Front |
| `All` | Client, world server, and the six service processes |

Target definitions live in `config/build-targets.csv`; dependency output isolation lives in `config/build-dependencies.csv`.

## Required topology

- A modern or maintainable Jenkins controller manages job history and access.
- A dedicated, recoverable Windows build worker contains Visual Studio .NET 2003 and the legacy SDK/libraries.
- The runtime server VM is separate from the build worker whenever possible.
- Build artifacts are immutable and grouped by Jenkins build and source commit.

If the legacy Jenkins 2.60.1 installation must remain temporarily, use the Freestyle sequence in `docs/JENKINS_FREESTYLE.md`. The checked-in Pipeline is the migration target; it is not evidence that the current Jenkins has already been upgraded.

## Local preflight

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-Preflight.ps1 `
  -SourceRoot ..\Goonzu_Build `
  -BaseRevision origin/master `
  -OutputDirectory ..\Goonzu_Build_Output\preflight
```

The result includes:

- `impact.properties`: selected build target and commit SHA
- `changed-files.tsv`: reviewed change list and category
- `preflight.tsv`: pass/fail evidence

## Build worker requirements

- Label: `goonzu-windows`
- Git
- Windows PowerShell
- Visual Studio .NET 2003
- Legacy Microsoft SDK and all required third-party libraries
- A disposable Jenkins workspace with no live-runtime junctions

Run `scripts/Test-BuildEnvironment.ps1` before enabling the node.

## GitHub settings

Protect `master` in `Goonzu_Build`:

- Require a pull request before merging.
- Require the Goonzu isolated-build status.
- Require resolved review conversations.
- Block force pushes and branch deletion.
- Allow the repository owner to self-merge only after the same checks pass.

The required status context is `Goonzu isolated build`. A successful Jenkins build is not enough by itself: publish that context only from eight-row `All` build evidence with `scripts/Publish-GitHubBuildStatus.ps1 -Approved`. The script uses the caller's authenticated GitHub CLI and stores no token in this repository or Jenkins.

This local repository must be pushed to an approved `Goonzu_CI` remote before another developer or Jenkins can consume it. No credentials, runtime binaries, VM images, or release shares belong here.
