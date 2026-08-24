# Developer onboarding

## 1. Clone the repositories

Use sibling directories so the documented commands stay stable:

```text
Goonzu/
  Goonzu_Build/
  Goonzu_CI/
  Goonzu_Build_Output/   generated, not versioned
```

Clone `https://github.com/KYEONGMIN94/Goonzu_Build.git` and the approved `Goonzu_CI` remote. Do not use a runtime client folder, distribution tree, Jenkins workspace, or VM live directory as a source checkout.

## 2. Trust and open the source project

Open `Goonzu_Build` as the task workspace for ordinary code work and mark the checkout trusted only after reviewing `.codex/config.toml`, `AGENTS.md`, and any project hooks or rules.

Start a new Codex task after trusting the project. The repository requests GPT-5.6 Terra with `low` reasoning for new tasks. An already-open task or an explicit composer/CLI choice keeps its current selection; the repository cannot automatically switch models in the middle of a task.

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ..\Goonzu_CI\scripts\Test-DeveloperEnvironment.ps1 `
  -SourceRoot .
```

## 3. Development machine versus build worker

The development machine needs Git, PowerShell, an editor, and approved reference/runtime artifacts. Visual Studio .NET 2003 is not required for every contributor workstation.

Compatibility compilation happens on the dedicated build worker. Preserve that worker as a recoverable VM image with:

- Visual Studio .NET 2003 / VC7.1;
- the legacy Microsoft SDK;
- third-party include and library dependencies;
- Git and Windows PowerShell;
- no live game-runtime role;
- no stored source changes outside a Jenkins workspace.

Do not modernize the compiler as part of routine feature work. Toolchain migration requires its own compatibility project and regression baseline.

## 4. Runtime assets

The source repository does not contain the complete client runtime, server data, databases, or VM image. Obtain an approved versioned runtime snapshot through the project's artifact storage and verify its manifest before testing.

Until artifact storage is formalized, record at minimum:

- snapshot or package version;
- source commit SHA;
- Client and Server executable SHA-256 values;
- runtime data manifest SHA-256;
- database backup/snapshot identifier;

## Dedicated legacy build worker

The current baseline worker is a separate VMware VM named `Goonzu_Build`. It uses a disk cloned from the named runtime baseline snapshot but has its own UUID, MAC address, hostname, and static address. Before connecting its NIC, run `scripts/Configure-BuildWorker.ps1` while isolated and restart the worker. The checked-in default is `GOONZU-BUILD` / `192.168.1.112`; change it only after confirming the address is unused.

Install the isolated Jenkins job with `scripts/Install-JenkinsFreestyle.ps1` before the first connected boot. All inherited Jenkins jobs must remain disabled on this worker.
- patch manifest version.

Never commit multi-gigabyte runtime or distribution trees to `Goonzu_Build`.

## 5. First contribution

1. Update local `master` without local modifications.
2. Create a focused `feature/*`, `fix/*`, or `chore/*` branch.
3. Run preflight before requesting a build.
4. Push and open a pull request.
5. Merge only the exact commit that passed the selected isolated build.
6. Let the user perform any required server startup and in-game acceptance.
