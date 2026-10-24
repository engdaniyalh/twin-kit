# twin-kit

`twin-kit` is a deterministic visual twin for a local Kubernetes release-pipeline sandbox.

It wraps a stdlib-only Python server (`twin-kit/server.py`) that polls real cluster state — minikube profile health, rollout phases, a gRPC mock service, the checked out Git branch, and an endpoint allowlist safety check — and serves a single offline HTML page rendering it as a live topology.

This VS Code extension brings `twin-kit` directly into VS Code with zero runtime dependencies.

---

## Features

- **Lifecycle Management**: Start, stop, restart, attach to, or auto-detect the `twin-kit` Python server process right from VS Code.
- **Visual Twin Webview**: Interactive panel rendering live topology and state updates via strict CSP and postMessage bridge.
- **Sidebar Explorer View**: Tree view (`twin-kit.explorer`) displaying live status across Minikube, Rollout Phase, gRPC Mock, Git Sandbox, and Safety Allowlist.
- **Status Bar Integration**: Visual status indicator displaying current rollout phase and warning in red when endpoint safety violations occur.
- **Scripted Walkthroughs**: Trigger deterministic scenario walkthroughs (`healthy-rollout`, `canary-failure-rollback`, `endpoint-blocked`) via QuickPick or toolbar buttons.
- **Output Channel**: Streamed stdout and stderr logging in "Twin-Kit" Output Channel.

---

## Workspace Structure

```
.
├── bootstrap.sh            # Repository bootstrap script
├── twin-kit/
│   └── server.py           # Stdlib-only Python 3.10+ server
└── extension/
    ├── package.json        # Extension manifest
    ├── tsconfig.json       # TypeScript configuration
    ├── media/
    │   ├── icon.png        # Extension icon
    │   └── icon.svg        # View container icon
    └── src/
        ├── extension.ts    # Extension entry point
        ├── serverManager.ts# Server process lifecycle and polling
        ├── twinViewProvider.ts # Sidebar Explorer TreeDataProvider
        ├── twinPanel.ts    # Webview Visual Twin panel
        ├── walkthroughs.ts # Scripted walkthrough QuickPick launcher
        └── types.ts        # TypeScript state interfaces
```

---

## Settings Configuration

The extension contributes settings under the `twinKit` namespace:

| Setting | Type | Default | Description |
|---|---|---|---|
| `twinKit.serverPath` | `string` | `""` | Path to `server.py`. Auto-detected if empty. |
| `twinKit.pythonPath` | `string` | `"python3"` | Executable command/path for Python. |
| `twinKit.port` | `number` | `8765` | Server port. |
| `twinKit.minikubeProfile` | `string` | `"twin-kit"` | Minikube profile name. |
| `twinKit.autoStart` | `boolean` | `false` | Automatically start server when opening workspace with `server.py`. |
| `twinKit.pollInterval` | `number` | `2000` | Polling interval in milliseconds for state updates. |
| `twinKit.walkthroughs` | `array` | `["healthy-rollout", ...]` | Available scripted walkthrough IDs. |

---

## Command Palette Commands

- `Twin-Kit: Start Twin-Kit Server`
- `Twin-Kit: Stop Twin-Kit Server`
- `Twin-Kit: Restart Twin-Kit Server`
- `Twin-Kit: Open Visual Twin`
- `Twin-Kit: Run Walkthrough...`
- `Twin-Kit: Show Twin-Kit Output`

---

## Extension Development Host Testing Checklist

1. **Compilation & Packaging**:
   - Run `cd extension && npm install && npm run compile` -> Must succeed without errors.
   - Run `cd extension && npm run package` -> Must produce `twin-kit-0.1.0.vsix`.

2. **Workspace Auto-Detection**:
   - Open a VS Code workspace containing `twin-kit/server.py`.
   - Verify prompt: *"Twin-Kit detected in workspace. Start server?"* appears on activation.

3. **Server Start & Logging**:
   - Execute command `Twin-Kit: Start Twin-Kit Server`.
   - Status bar changes to `$(radio-tower) twin-kit: Running - stable`.
   - Command `Twin-Kit: Show Twin-Kit Output` displays startup logs in "Twin-Kit" Output Channel.

4. **Visual Twin Webview**:
   - Execute command `Twin-Kit: Open Visual Twin`.
   - Verify panel titled "Twin-Kit Visual Twin" opens with live topology and status metrics.
   - Test toolbar "Stop Server", "Run Walkthrough", and "Refresh" buttons.

5. **Sidebar Explorer**:
   - Expand `Twin-Kit Visual Twin` view in Explorer sidebar.
   - Confirm all 5 sections display accurate state: Minikube Profile, Rollout Phase, gRPC Mock, Git Branch, Safety Allowlist.

6. **Scripted Walkthroughs**:
   - Execute command `Twin-Kit: Run Walkthrough...` and select `canary-failure-rollback`.
   - Observe rollout phase transition from `canary` -> `degraded` -> `rollback` -> `stable` deterministically in sidebar and Webview.
   - Run walkthrough `endpoint-blocked`.
   - Verify safety section flags violation `http://unauthorized-external-telemetry.com/collect`.
   - Status bar turns red due to safety violation. Clicking violation item opens Output Channel.

7. **Server Cleanup**:
   - Execute command `Twin-Kit: Stop Twin-Kit Server`.
   - Status bar resets to `$(circle-slash) twin-kit: Stopped`.
   - Webview displays stopped empty state with "Start Server" action button.
