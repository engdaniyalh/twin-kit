#!/usr/bin/env bash
set -e

echo "🚀 Bootstrapping twin-kit repository..."

# Create directory structure
mkdir -p twin-kit extension/media extension/src

# 1. Create .gitignore
cat << 'EOF' > .gitignore
node_modules/
**/node_modules/
out/
**/out/
*.vsix
.vscode-test/
server.log
__pycache__/
**/__pycache__/
EOF

# 2. Create twin-kit/server.py
cat << 'EOF' > twin-kit/server.py
#!/usr/bin/env python3
"""
twin-kit server: stdlib-only Python 3.10+ server for twin-kit.
Serves static offline HTML at GET / and JSON API endpoints.
"""

import argparse
import json
import os
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

# HTML Content for Visual Twin
HTML_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Twin-Kit Visual Twin</title>
    <style>
        :root {
            --bg-color: #1e1e1e;
            --text-color: #d4d4d4;
            --card-bg: #252526;
            --border-color: #3c3c3c;
            --accent-color: #0e639c;
            --success-color: #4ec9b0;
            --warning-color: #ce9178;
            --danger-color: #f14c4c;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            margin: 0;
            padding: 20px;
        }

        h1, h2, h3 {
            margin-top: 0;
        }

        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border-color);
            padding-bottom: 10px;
            margin-bottom: 20px;
        }

        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }

        .card {
            background-color: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 15px;
        }

        .card-header {
            font-weight: bold;
            font-size: 1.1em;
            margin-bottom: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .badge {
            padding: 3px 8px;
            border-radius: 12px;
            font-size: 0.8em;
            font-weight: bold;
            text-transform: uppercase;
        }

        .badge-green { background-color: rgba(78, 201, 176, 0.2); color: var(--success-color); border: 1px solid var(--success-color); }
        .badge-yellow { background-color: rgba(206, 145, 120, 0.2); color: var(--warning-color); border: 1px solid var(--warning-color); }
        .badge-red { background-color: rgba(241, 76, 76, 0.2); color: var(--danger-color); border: 1px solid var(--danger-color); }

        .progress-bar-bg {
            background-color: #333;
            border-radius: 4px;
            height: 10px;
            width: 100%;
            overflow: hidden;
            margin-top: 8px;
        }

        .progress-bar-fill {
            background-color: var(--accent-color);
            height: 100%;
            width: 0%;
            transition: width 0.3s ease;
        }

        .topology {
            background-color: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 20px;
            margin-top: 20px;
        }

        .nodes {
            display: flex;
            justify-content: space-around;
            align-items: center;
            flex-wrap: wrap;
            gap: 20px;
            position: relative;
            padding: 20px 0;
        }

        .node {
            background: #2d2d2d;
            border: 2px solid var(--border-color);
            border-radius: 8px;
            padding: 15px;
            width: 160px;
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.3);
        }

        .node.active {
            border-color: var(--accent-color);
        }

        .node.alert {
            border-color: var(--danger-color);
        }

        .violations-list {
            margin-top: 10px;
            padding-left: 20px;
            color: var(--danger-color);
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Twin-Kit Visual Twin</h1>
        <div id="connection-status"><span class="badge badge-green">LIVE</span></div>
    </div>

    <div class="grid">
        <div class="card">
            <div class="card-header">
                <span>Minikube</span>
                <span id="mk-status-badge" class="badge">--</span>
            </div>
            <div>Profile: <strong id="mk-profile">--</strong></div>
            <div>CPUs: <span id="mk-cpus">--</span> | Memory: <span id="mk-memory">--</span></div>
            <div style="font-size: 0.8em; color: #888; margin-top: 5px;">Last check: <span id="mk-last-check">--</span></div>
        </div>

        <div class="card">
            <div class="card-header">
                <span>Rollout</span>
                <span id="rollout-phase-badge" class="badge">--</span>
            </div>
            <div>Progress: <span id="rollout-progress-val">0</span>%</div>
            <div class="progress-bar-bg">
                <div id="rollout-progress-bar" class="progress-bar-fill"></div>
            </div>
            <div style="margin-top: 8px;" id="rollout-deployments"></div>
        </div>

        <div class="card">
            <div class="card-header">
                <span>gRPC Mock</span>
                <span id="grpc-status-badge" class="badge">--</span>
            </div>
            <div>Service: <strong id="grpc-mock">--</strong></div>
            <div>Latency: <span id="grpc-latency">--</span> ms</div>
        </div>

        <div class="card">
            <div class="card-header">
                <span>Git Sandbox</span>
                <span id="git-dirty-badge" class="badge">CLEAN</span>
            </div>
            <div>Branch: <strong id="git-branch">--</strong></div>
            <div>Commit: <code id="git-commit">--</code></div>
        </div>
    </div>

    <div class="card" style="margin-bottom: 20px;">
        <div class="card-header">
            <span>Safety / Endpoint Allowlist</span>
            <span id="safety-status-badge" class="badge">OK</span>
        </div>
        <div>Allowlist: <span id="safety-allowlist">--</span></div>
        <div id="safety-violations-container" style="display: none;">
            <div style="margin-top: 8px; font-weight: bold; color: var(--danger-color);">Blocked / Violations:</div>
            <ul id="safety-violations" class="violations-list"></ul>
        </div>
    </div>

    <div class="topology">
        <h2>Live Sandbox Topology</h2>
        <div class="nodes">
            <div id="node-git" class="node">
                <h3>Git Repository</h3>
                <div id="top-git-branch">--</div>
            </div>
            <div id="node-pipeline" class="node">
                <h3>Release Pipeline</h3>
                <div id="top-rollout-phase">--</div>
            </div>
            <div id="node-cluster" class="node">
                <h3>Minikube</h3>
                <div id="top-minikube-status">--</div>
            </div>
            <div id="node-grpc" class="node">
                <h3>gRPC Mock</h3>
                <div id="top-grpc-status">--</div>
            </div>
        </div>
    </div>

    <script>
        function updateUI(state) {
            if (!state) return;

            // Minikube
            if (state.minikube) {
                document.getElementById('mk-profile').textContent = state.minikube.profile || '--';
                document.getElementById('mk-cpus').textContent = state.minikube.cpus ?? '--';
                document.getElementById('mk-memory').textContent = state.minikube.memory || '--';
                document.getElementById('mk-last-check').textContent = state.minikube.lastCheck || '--';

                const mkBadge = document.getElementById('mk-status-badge');
                const mkStatus = state.minikube.status || 'Unknown';
                mkBadge.textContent = mkStatus;
                mkBadge.className = 'badge ' + (mkStatus === 'Running' ? 'badge-green' : (mkStatus === 'Degraded' ? 'badge-yellow' : 'badge-red'));
                document.getElementById('top-minikube-status').textContent = mkStatus;
            }

            // Rollout
            if (state.rollout) {
                const phase = state.rollout.phase || 'unknown';
                const progress = state.rollout.progress ?? 0;
                document.getElementById('rollout-progress-val').textContent = progress;
                document.getElementById('rollout-progress-bar').style.width = progress + '%';

                const rolloutBadge = document.getElementById('rollout-phase-badge');
                rolloutBadge.textContent = phase;
                rolloutBadge.className = 'badge ' + (phase === 'stable' ? 'badge-green' : (phase === 'rollback' ? 'badge-red' : 'badge-yellow'));
                document.getElementById('top-rollout-phase').textContent = phase;

                const depsContainer = document.getElementById('rollout-deployments');
                if (state.rollout.deployments && state.rollout.deployments.length > 0) {
                    depsContainer.innerHTML = state.rollout.deployments.map(d =>
                        `<div>Deployment: <strong>${d.name}</strong> (${d.ready}/${d.replicas})</div>`
                    ).join('');
                } else {
                    depsContainer.innerHTML = '<div>No deployments</div>';
                }
            }

            // gRPC
            if (state.grpc) {
                document.getElementById('grpc-mock').textContent = state.grpc.mock || '--';
                document.getElementById('grpc-latency').textContent = state.grpc.latencyMs ?? '--';
                const grpcBadge = document.getElementById('grpc-status-badge');
                const grpcStatus = state.grpc.status || 'UNKNOWN';
                grpcBadge.textContent = grpcStatus;
                grpcBadge.className = 'badge ' + (grpcStatus === 'OK' ? 'badge-green' : (grpcStatus === 'DEGRADED' ? 'badge-yellow' : 'badge-red'));
                document.getElementById('top-grpc-status').textContent = grpcStatus;
            }

            // Git
            if (state.git) {
                document.getElementById('git-branch').textContent = state.git.branch || '--';
                document.getElementById('git-commit').textContent = state.git.commit || '--';
                document.getElementById('top-git-branch').textContent = state.git.branch || '--';

                const gitBadge = document.getElementById('git-dirty-badge');
                if (state.git.dirty) {
                    gitBadge.textContent = 'DIRTY';
                    gitBadge.className = 'badge badge-yellow';
                } else {
                    gitBadge.textContent = 'CLEAN';
                    gitBadge.className = 'badge badge-green';
                }
            }

            // Safety
            if (state.safety) {
                const allowlist = (state.safety.allowlist || []).join(', ');
                document.getElementById('safety-allowlist').textContent = allowlist || 'None';

                const violations = state.safety.violations || state.safety.blocked || [];
                const safetyBadge = document.getElementById('safety-status-badge');
                const container = document.getElementById('safety-violations-container');
                const list = document.getElementById('safety-violations');

                if (violations.length > 0) {
                    safetyBadge.textContent = 'BLOCKED (' + violations.length + ')';
                    safetyBadge.className = 'badge badge-red';
                    container.style.display = 'block';
                    list.innerHTML = violations.map(v => `<li>${v}</li>`).join('');
                } else {
                    safetyBadge.textContent = 'OK';
                    safetyBadge.className = 'badge badge-green';
                    container.style.display = 'none';
                    list.innerHTML = '';
                }
            }
        }

        // Poll API
        function pollState() {
            fetch('/api/state')
                .then(res => res.json())
                .then(data => updateUI(data))
                .catch(err => console.error('Error polling state:', err));
        }

        setInterval(pollState, 2000);
        pollState();

        // Listen for messages from VS Code extension host if embedded
        window.addEventListener('message', event => {
            const message = event.data;
            if (message && message.type === 'stateUpdate') {
                updateUI(message.state);
            }
        });
    </script>
</body>
</html>
"""

# Walkthrough Definitions
WALKTHROUGHS = [
    {
        "id": "healthy-rollout",
        "name": "Healthy Rollout",
        "description": "Progresses from stable to canary, then promotes smoothly back to stable."
    },
    {
        "id": "canary-failure-rollback",
        "name": "Canary Failure & Rollback",
        "description": "Canary deployment triggers errors and automatically rolls back to stable."
    },
    {
        "id": "endpoint-blocked",
        "name": "Endpoint Blocked",
        "description": "Sandbox attempts to call external endpoint outside allowlist and gets flagged."
    }
]

class StateManager:
    def __init__(self, profile_name="twin-kit"):
        self.lock = threading.Lock()
        self.profile_name = profile_name
        self.walkthrough_thread = None

        # Initial state
        self.state = {
            "minikube": {
                "profile": self.profile_name,
                "status": "Running",
                "cpus": 2,
                "memory": "4g",
                "lastCheck": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            },
            "rollout": {
                "phase": "stable",
                "deployments": [
                    {"name": "api", "replicas": 2, "ready": 2, "image": "twin-kit/api:v1.0.0"}
                ],
                "progress": 100
            },
            "grpc": {
                "mock": "inventory",
                "status": "OK",
                "latencyMs": 12
            },
            "git": {
                "branch": "main",
                "commit": "a1b2c3d",
                "dirty": False
            },
            "safety": {
                "allowlist": ["*.svc.cluster.local", "localhost"],
                "violations": [],
                "blocked": []
            }
        }

    def get_state(self):
        with self.lock:
            self.state["minikube"]["lastCheck"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            return json.loads(json.dumps(self.state))

    def start_walkthrough(self, walkthrough_id):
        with self.lock:
            # Cancel current thread if any
            if self.walkthrough_thread and self.walkthrough_thread.is_alive():
                # We let it finish or override state
                pass

            if walkthrough_id == "healthy-rollout":
                t = threading.Thread(target=self._run_healthy_rollout, daemon=True)
            elif walkthrough_id == "canary-failure-rollback":
                t = threading.Thread(target=self._run_canary_failure_rollback, daemon=True)
            elif walkthrough_id == "endpoint-blocked":
                t = threading.Thread(target=self._run_endpoint_blocked, daemon=True)
            else:
                return False, f"Unknown walkthrough id: {walkthrough_id}"

            self.walkthrough_thread = t
            t.start()
            return True, f"Started walkthrough {walkthrough_id}"

    def _run_healthy_rollout(self):
        # Step 1: Start canary
        with self.lock:
            self.state["git"]["branch"] = "feature/canary"
            self.state["rollout"]["phase"] = "canary"
            self.state["rollout"]["progress"] = 25
            self.state["rollout"]["deployments"] = [
                {"name": "api-stable", "replicas": 2, "ready": 2, "image": "twin-kit/api:v1.0.0"},
                {"name": "api-canary", "replicas": 1, "ready": 1, "image": "twin-kit/api:v1.1.0-canary"}
            ]
            self.state["safety"]["violations"] = []
            self.state["safety"]["blocked"] = []

        time.sleep(2.5)

        # Step 2: Progress canary
        with self.lock:
            self.state["rollout"]["progress"] = 60
            self.state["grpc"]["latencyMs"] = 18

        time.sleep(2.5)

        # Step 3: Promote
        with self.lock:
            self.state["rollout"]["phase"] = "promote"
            self.state["rollout"]["progress"] = 90

        time.sleep(2.5)

        # Step 4: Stable
        with self.lock:
            self.state["rollout"]["phase"] = "stable"
            self.state["rollout"]["progress"] = 100
            self.state["rollout"]["deployments"] = [
                {"name": "api", "replicas": 2, "ready": 2, "image": "twin-kit/api:v1.1.0"}
            ]
            self.state["grpc"]["latencyMs"] = 10

    def _run_canary_failure_rollback(self):
        # Step 1: Start canary
        with self.lock:
            self.state["git"]["branch"] = "feature/buggy-canary"
            self.state["rollout"]["phase"] = "canary"
            self.state["rollout"]["progress"] = 30
            self.state["grpc"]["status"] = "OK"

        time.sleep(2.5)

        # Step 2: Canary degraded
        with self.lock:
            self.state["rollout"]["progress"] = 50
            self.state["grpc"]["status"] = "DEGRADED"
            self.state["grpc"]["latencyMs"] = 450
            self.state["minikube"]["status"] = "Degraded"

        time.sleep(2.5)

        # Step 3: Rollback
        with self.lock:
            self.state["rollout"]["phase"] = "rollback"
            self.state["rollout"]["progress"] = 20
            self.state["grpc"]["status"] = "DOWN"

        time.sleep(2.5)

        # Step 4: Back to Stable
        with self.lock:
            self.state["rollout"]["phase"] = "stable"
            self.state["rollout"]["progress"] = 100
            self.state["minikube"]["status"] = "Running"
            self.state["grpc"]["status"] = "OK"
            self.state["grpc"]["latencyMs"] = 12
            self.state["rollout"]["deployments"] = [
                {"name": "api", "replicas": 2, "ready": 2, "image": "twin-kit/api:v1.0.0"}
            ]

    def _run_endpoint_blocked(self):
        # Step 1: Normal
        with self.lock:
            self.state["git"]["branch"] = "feature/exfiltrate"
            self.state["safety"]["violations"] = []
            self.state["safety"]["blocked"] = []

        time.sleep(1.5)

        # Step 2: Attempt illegal call
        with self.lock:
            violation = "http://unauthorized-external-telemetry.com/collect"
            self.state["safety"]["violations"] = [violation]
            self.state["safety"]["blocked"] = [violation]

class TwinKitHTTPRequestHandler(BaseHTTPRequestHandler):
    state_manager = None

    def log_message(self, format, *args):
        # Write to stdout so extension host output channel receives it cleanly
        sys.stdout.write("%s - - [%s] %s\n" %
                         (self.address_string(),
                          self.log_date_time_string(),
                          format%args))
        sys.stdout.flush()

    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path

        if path == "/" or path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode("utf-8"))
        elif path == "/api/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"ok": True}).encode("utf-8"))
        elif path == "/api/state":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            state = self.state_manager.get_state()
            self.wfile.write(json.dumps(state).encode("utf-8"))
        elif path == "/api/walkthroughs":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(WALKTHROUGHS).encode("utf-8"))
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path

        # Handle /api/walkthrough/:id/start
        if path.startswith("/api/walkthrough/") and path.endswith("/start"):
            parts = path.split("/")
            if len(parts) >= 4:
                walkthrough_id = parts[3]
                success, msg = self.state_manager.start_walkthrough(walkthrough_id)
                if success:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"status": "started", "walkthrough": walkthrough_id, "message": msg}).encode("utf-8"))
                else:
                    self.send_response(400)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps({"error": msg}).encode("utf-8"))
                return

        self.send_error(404, "Not Found")

def run_server(port, profile):
    state_manager = StateManager(profile_name=profile)
    TwinKitHTTPRequestHandler.state_manager = state_manager

    server_address = ('', port)
    httpd = HTTPServer(server_address, TwinKitHTTPRequestHandler)
    print(f"Twin-Kit server running on port {port} with profile '{profile}'...", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
        print("Twin-Kit server stopped.", flush=True)

def main():
    parser = argparse.ArgumentParser(description="Twin-Kit Server")
    parser.add_argument("--port", type=int, default=8765, help="Port to listen on")
    parser.add_argument("--profile", type=str, default="twin-kit", help="Minikube profile name")
    args = parser.parse_args()

    run_server(args.port, args.profile)

if __name__ == "__main__":
    main()
EOF
chmod +x twin-kit/server.py

# 3. Create extension/package.json
cat << 'EOF' > extension/package.json
{
  "name": "twin-kit",
  "displayName": "Twin-Kit Visual Twin",
  "description": "Deterministic visual twin for a local Kubernetes release-pipeline sandbox.",
  "version": "0.1.0",
  "publisher": "twin-kit",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": [
    "Other"
  ],
  "main": "./out/extension.js",
  "icon": "media/icon.png",
  "activationEvents": [
    "onStartupFinished",
    "onCommand:twinKit.startServer",
    "onCommand:twinKit.stopServer",
    "onCommand:twinKit.restartServer",
    "onCommand:twinKit.openVisualTwin",
    "onCommand:twinKit.runWalkthrough",
    "onCommand:twinKit.showOutput"
  ],
  "contributes": {
    "commands": [
      {
        "command": "twinKit.startServer",
        "title": "Twin-Kit: Start Twin-Kit Server",
        "category": "Twin-Kit",
        "icon": "$(play)"
      },
      {
        "command": "twinKit.stopServer",
        "title": "Twin-Kit: Stop Twin-Kit Server",
        "category": "Twin-Kit",
        "icon": "$(stop)"
      },
      {
        "command": "twinKit.restartServer",
        "title": "Twin-Kit: Restart Twin-Kit Server",
        "category": "Twin-Kit",
        "icon": "$(refresh)"
      },
      {
        "command": "twinKit.openVisualTwin",
        "title": "Twin-Kit: Open Visual Twin",
        "category": "Twin-Kit",
        "icon": "$(preview)"
      },
      {
        "command": "twinKit.runWalkthrough",
        "title": "Twin-Kit: Run Walkthrough...",
        "category": "Twin-Kit",
        "icon": "$(run-all)"
      },
      {
        "command": "twinKit.showOutput",
        "title": "Twin-Kit: Show Twin-Kit Output",
        "category": "Twin-Kit",
        "icon": "$(output)"
      },
      {
        "command": "twinKit.refreshExplorer",
        "title": "Refresh Twin-Kit Explorer",
        "category": "Twin-Kit",
        "icon": "$(refresh)"
      }
    ],
    "viewsContainers": {
      "activitybar": [
        {
          "id": "twin-kit",
          "title": "Twin-Kit",
          "icon": "media/icon.svg"
        }
      ]
    },
    "views": {
      "twin-kit": [
        {
          "id": "twin-kit.explorer",
          "name": "Twin-Kit Visual Twin"
        }
      ],
      "explorer": [
        {
          "id": "twin-kit.explorer",
          "name": "Twin-Kit Sandbox"
        }
      ]
    },
    "viewsWelcome": [
      {
        "view": "twin-kit.explorer",
        "contents": "Twin-Kit server is currently stopped.\n[Start Twin-Kit Server](command:twinKit.startServer)"
      }
    ],
    "menus": {
      "view/title": [
        {
          "command": "twinKit.startServer",
          "when": "view == twin-kit.explorer",
          "group": "navigation@1"
        },
        {
          "command": "twinKit.stopServer",
          "when": "view == twin-kit.explorer",
          "group": "navigation@2"
        },
        {
          "command": "twinKit.openVisualTwin",
          "when": "view == twin-kit.explorer",
          "group": "navigation@3"
        },
        {
          "command": "twinKit.runWalkthrough",
          "when": "view == twin-kit.explorer",
          "group": "navigation@4"
        },
        {
          "command": "twinKit.refreshExplorer",
          "when": "view == twin-kit.explorer",
          "group": "navigation@5"
        }
      ]
    },
    "configuration": {
      "title": "Twin-Kit",
      "properties": {
        "twinKit.serverPath": {
          "type": "string",
          "default": "",
          "description": "Path to twin-kit/server.py script. If empty, auto-detects in workspace."
        },
        "twinKit.pythonPath": {
          "type": "string",
          "default": "python3",
          "description": "Path to Python executable."
        },
        "twinKit.port": {
          "type": "number",
          "default": 8765,
          "description": "Port to run the twin-kit server on."
        },
        "twinKit.minikubeProfile": {
          "type": "string",
          "default": "twin-kit",
          "description": "Minikube profile name."
        },
        "twinKit.autoStart": {
          "type": "boolean",
          "default": false,
          "description": "Automatically start twin-kit server when opening workspace containing twin-kit/server.py."
        },
        "twinKit.pollInterval": {
          "type": "number",
          "default": 2000,
          "description": "Polling interval in milliseconds for fetching twin state."
        },
        "twinKit.walkthroughs": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "default": [
            "healthy-rollout",
            "canary-failure-rollback",
            "endpoint-blocked"
          ],
          "description": "List of available scripted walkthrough IDs."
        }
      }
    }
  },
  "scripts": {
    "vscode:prepublish": "npm run compile",
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./",
    "package": "vsce package --no-dependencies"
  },
  "devDependencies": {
    "@types/node": "^18.11.9",
    "@types/vscode": "^1.85.0",
    "@vscode/vsce": "^2.22.0",
    "typescript": "^5.3.3"
  }
}
EOF

# 4. Create extension/tsconfig.json
cat << 'EOF' > extension/tsconfig.json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2022",
    "outDir": "out",
    "lib": ["ES2022"],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true
  },
  "exclude": ["node_modules", ".vscode-test"]
}
EOF

# 5. Create extension/.vscodeignore
cat << 'EOF' > extension/.vscodeignore
.vscode/
.vscode-test/
node_modules/
src/
tsconfig.json
server.log
*.vsix
EOF

# 6. Create Media Files
cat << 'EOF' > extension/media/icon.svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
  <rect x="5" y="5" width="90" height="90" rx="15" fill="#1e1e1e" stroke="#0e639c" stroke-width="4"/>
  <circle cx="30" cy="35" r="12" fill="#0e639c"/>
  <circle cx="70" cy="35" r="12" fill="#4ec9b0"/>
  <circle cx="50" cy="70" r="14" fill="#ce9178"/>
  <line x1="30" y1="35" x2="70" y2="35" stroke="#ffffff" stroke-width="3" stroke-dasharray="4"/>
  <line x1="30" y1="35" x2="50" y2="70" stroke="#ffffff" stroke-width="3"/>
  <line x1="70" y1="35" x2="50" y2="70" stroke="#ffffff" stroke-width="3"/>
</svg>
EOF

python3 -c "
import struct, zlib

def create_png():
    width, height = 128, 128
    raw_data = b''
    for y in range(height):
        raw_data += b'\x00'
        for x in range(width):
            if 10 <= x <= 118 and 10 <= y <= 118:
                raw_data += b'\x0e\x63\x9c\xff'
            else:
                raw_data += b'\x1e\x1e\x1e\xff'

    def chunk(two, data):
        return struct.pack('>I', len(data)) + two + data + struct.pack('>I', zlib.crc32(two + data) & 0xffffffff)

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(raw_data))
    png += chunk(b'IEND', b'')
    return png

with open('extension/media/icon.png', 'wb') as f:
    f.write(create_png())
"

# 7. Create Source Files
cat << 'EOF' > extension/src/types.ts
export interface MinikubeState {
    profile: string;
    status: "Running" | "Stopped" | "Degraded" | "Unknown" | string;
    cpus?: number;
    memory?: string;
    lastCheck?: string;
}

export interface DeploymentState {
    name: string;
    replicas: number;
    ready: number;
    image?: string;
}

export interface RolloutState {
    phase: "stable" | "canary" | "promote" | "rollback" | string;
    deployments: DeploymentState[];
    progress: number;
}

export interface GrpcState {
    mock: string;
    status: "OK" | "DEGRADED" | "DOWN" | string;
    latencyMs?: number;
}

export interface GitState {
    branch: string;
    commit?: string;
    dirty: boolean;
}

export interface SafetyState {
    allowlist: string[];
    violations: string[];
    blocked?: string[];
}

export interface TwinState {
    minikube?: MinikubeState;
    rollout?: RolloutState;
    grpc?: GrpcState;
    git?: GitState;
    safety?: SafetyState;
}

export interface WalkthroughItem {
    id: string;
    name: string;
    description: string;
}

export interface ServerConfig {
    serverPath: string;
    pythonPath: string;
    port: number;
    minikubeProfile: string;
    autoStart: boolean;
    pollInterval: number;
    walkthroughs: string[];
}
EOF

cat << 'EOF' > extension/src/serverManager.ts
import * as vscode from 'vscode';
import * as child_process from 'child_process';
import * as http from 'http';
import * as path from 'path';
import * as fs from 'fs';
import { TwinState, ServerConfig, WalkthroughItem } from './types';

export class ServerManager {
    private process: child_process.ChildProcess | null = null;
    private outputChannel: vscode.OutputChannel;
    private pollTimer: NodeJS.Timeout | null = null;
    private state: TwinState | null = null;
    private isRunning: boolean = false;
    private attachedToExisting: boolean = false;

    private _onStateChange: vscode.EventEmitter<TwinState | null> = new vscode.EventEmitter<TwinState | null>();
    public readonly onStateChange: vscode.Event<TwinState | null> = this._onStateChange.event;

    private _onStatusChange: vscode.EventEmitter<boolean> = new vscode.EventEmitter<boolean>();
    public readonly onStatusChange: vscode.Event<boolean> = this._onStatusChange.event;

    constructor(private context: vscode.ExtensionContext) {
        this.outputChannel = vscode.window.createOutputChannel("Twin-Kit");
    }

    public getConfig(): ServerConfig {
        const config = vscode.workspace.getConfiguration('twinKit');
        return {
            serverPath: config.get<string>('serverPath', ''),
            pythonPath: config.get<string>('pythonPath', process.platform === 'win32' ? 'python' : 'python3'),
            port: config.get<number>('port', 8765),
            minikubeProfile: config.get<string>('minikubeProfile', 'twin-kit'),
            autoStart: config.get<boolean>('autoStart', false),
            pollInterval: config.get<number>('pollInterval', 2000),
            walkthroughs: config.get<string[]>('walkthroughs', ['healthy-rollout', 'canary-failure-rollback', 'endpoint-blocked'])
        };
    }

    public showOutput(): void {
        this.outputChannel.show(true);
    }

    public log(message: string): void {
        const time = new Date().toISOString();
        this.outputChannel.appendLine(`[${time}] ${message}`);
    }

    public findServerScript(): string | null {
        const cfg = this.getConfig();
        if (cfg.serverPath && fs.existsSync(cfg.serverPath)) {
            return cfg.serverPath;
        }

        if (vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders.length > 0) {
            for (const folder of vscode.workspace.workspaceFolders) {
                const candidates = [
                    path.join(folder.uri.fsPath, 'twin-kit', 'server.py'),
                    path.join(folder.uri.fsPath, 'server.py')
                ];
                for (const candidate of candidates) {
                    if (fs.existsSync(candidate)) {
                        return candidate;
                    }
                }
            }
        }
        return null;
    }

    public async checkHealth(port?: number): Promise<boolean> {
        const cfg = this.getConfig();
        const checkPort = port || cfg.port;
        return new Promise((resolve) => {
            const req = http.get(`http://127.0.0.1:${checkPort}/api/health`, { timeout: 1000 }, (res) => {
                if (res.statusCode === 200) {
                    resolve(true);
                } else {
                    resolve(false);
                }
            });
            req.on('error', () => resolve(false));
            req.on('timeout', () => {
                req.destroy();
                resolve(false);
            });
        });
    }

    public async startServer(): Promise<boolean> {
        if (this.isRunning) {
            vscode.window.showInformationMessage('Twin-Kit server is already running.');
            return true;
        }

        const cfg = this.getConfig();
        const isPortActive = await this.checkHealth(cfg.port);
        if (isPortActive) {
            const answer = await vscode.window.showInformationMessage(
                `Server already running on port ${cfg.port}, attach?`,
                'Attach',
                'Cancel'
            );
            if (answer === 'Attach') {
                this.attachedToExisting = true;
                this.setRunningState(true);
                this.startPolling();
                this.log(`Attached to existing Twin-Kit server running on port ${cfg.port}`);
                return true;
            } else {
                return false;
            }
        }

        const scriptPath = this.findServerScript();
        if (!scriptPath) {
            const choice = await vscode.window.showErrorMessage(
                'Twin-Kit server script (twin-kit/server.py) not found in workspace.',
                'Locate Script'
            );
            if (choice === 'Locate Script') {
                const files = await vscode.window.showOpenDialog({
                    canSelectFiles: true,
                    canSelectFolders: false,
                    canSelectMany: false,
                    filters: { 'Python': ['py'] },
                    title: 'Locate Twin-Kit server.py'
                });
                if (files && files.length > 0) {
                    await vscode.workspace.getConfiguration('twinKit').update('serverPath', files[0].fsPath, vscode.ConfigurationTarget.Workspace);
                    return this.startServer();
                }
            }
            return false;
        }

        const pythonExec = cfg.pythonPath || (process.platform === 'win32' ? 'python' : 'python3');
        this.log(`Starting Twin-Kit server: ${pythonExec} "${scriptPath}" --port ${cfg.port} --profile ${cfg.minikubeProfile}`);

        try {
            this.process = child_process.spawn(pythonExec, [
                scriptPath,
                '--port', cfg.port.toString(),
                '--profile', cfg.minikubeProfile
            ], {
                cwd: path.dirname(scriptPath),
                env: { ...process.env }
            });

            this.process.stdout?.on('data', (data) => {
                this.outputChannel.append(`[STDOUT] ${data.toString()}`);
            });

            this.process.stderr?.on('data', (data) => {
                this.outputChannel.append(`[STDERR] ${data.toString()}`);
            });

            this.process.on('error', (err) => {
                this.log(`Server process error: ${err.message}`);
                this.stopServer();
                vscode.window.showErrorMessage(`Failed to launch Twin-Kit server: ${err.message}`);
            });

            this.process.on('exit', (code, signal) => {
                this.log(`Server process exited with code ${code}, signal ${signal}`);
                if (this.isRunning && !this.attachedToExisting) {
                    this.setRunningState(false);
                    vscode.window.showErrorMessage('Twin-Kit server unexpectedly stopped.', 'Restart').then(selection => {
                        if (selection === 'Restart') {
                            this.startServer();
                        }
                    });
                }
            });

            await new Promise((res) => setTimeout(res, 500));
            this.attachedToExisting = false;
            this.setRunningState(true);
            this.startPolling();
            this.log('Twin-Kit server started successfully.');
            return true;
        } catch (err: any) {
            this.log(`Failed to spawn server: ${err.message}`);
            vscode.window.showErrorMessage(`Failed to start Twin-Kit server: ${err.message}`);
            return false;
        }
    }

    public async stopServer(): Promise<void> {
        this.stopPolling();
        if (this.process) {
            try {
                this.process.kill();
            } catch (e) {
                // Ignore kill errors
            }
            this.process = null;
        }
        this.attachedToExisting = false;
        this.setRunningState(false);
        this.log('Twin-Kit server stopped.');
    }

    public async restartServer(): Promise<void> {
        await this.stopServer();
        await this.startServer();
    }

    public startPolling(): void {
        this.stopPolling();
        const cfg = this.getConfig();
        this.pollState();
        this.pollTimer = setInterval(() => {
            this.pollState();
        }, cfg.pollInterval);
    }

    public stopPolling(): void {
        if (this.pollTimer) {
            clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    private async pollState(): Promise<void> {
        if (!this.isRunning) return;

        const cfg = this.getConfig();
        try {
            const req = http.get(`http://127.0.0.1:${cfg.port}/api/state`, { timeout: 1500 }, (res) => {
                if (res.statusCode === 200) {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        try {
                            const parsedState = JSON.parse(data) as TwinState;
                            this.state = parsedState;
                            this._onStateChange.fire(this.state);
                        } catch (e) {
                            // JSON parse error
                        }
                    });
                } else {
                    this.handlePollFailure();
                }
            });

            req.on('error', () => {
                this.handlePollFailure();
            });
            req.on('timeout', () => {
                req.destroy();
                this.handlePollFailure();
            });
        } catch (e) {
            this.handlePollFailure();
        }
    }

    private handlePollFailure(): void {
        if (this.isRunning && this.attachedToExisting) {
            this.log('Lost connection to attached Twin-Kit server.');
            this.stopServer();
            vscode.window.showErrorMessage('Lost connection to Twin-Kit server.', 'Restart').then(sel => {
                if (sel === 'Restart') {
                    this.startServer();
                }
            });
        }
    }

    public async getWalkthroughs(): Promise<WalkthroughItem[]> {
        const cfg = this.getConfig();
        return new Promise((resolve) => {
            if (!this.isRunning) {
                return resolve(this.getFallbackWalkthroughs());
            }

            const req = http.get(`http://127.0.0.1:${cfg.port}/api/walkthroughs`, { timeout: 1500 }, (res) => {
                if (res.statusCode === 200) {
                    let data = '';
                    res.on('data', chunk => data += chunk);
                    res.on('end', () => {
                        try {
                            const list = JSON.parse(data) as WalkthroughItem[];
                            resolve(list);
                        } catch (e) {
                            resolve(this.getFallbackWalkthroughs());
                        }
                    });
                } else {
                    resolve(this.getFallbackWalkthroughs());
                }
            });
            req.on('error', () => resolve(this.getFallbackWalkthroughs()));
            req.on('timeout', () => {
                req.destroy();
                resolve(this.getFallbackWalkthroughs());
            });
        });
    }

    public async startWalkthrough(id: string): Promise<boolean> {
        const cfg = this.getConfig();
        if (!this.isRunning) {
            vscode.window.showErrorMessage('Twin-Kit server is not running. Start server first.');
            return false;
        }

        return new Promise((resolve) => {
            const req = http.request({
                hostname: '127.0.0.1',
                port: cfg.port,
                path: `/api/walkthrough/${id}/start`,
                method: 'POST',
                timeout: 2000
            }, (res) => {
                if (res.statusCode === 200) {
                    this.log(`Successfully started walkthrough ${id}`);
                    resolve(true);
                } else {
                    this.log(`Failed to start walkthrough ${id}: Status ${res.statusCode}`);
                    resolve(false);
                }
            });

            req.on('error', (err) => {
                this.log(`Walkthrough start error: ${err.message}`);
                resolve(false);
            });
            req.end();
        });
    }

    private getFallbackWalkthroughs(): WalkthroughItem[] {
        return [
            { id: "healthy-rollout", name: "Healthy Rollout", description: "Progresses from stable to canary, then promotes smoothly back to stable." },
            { id: "canary-failure-rollback", name: "Canary Failure & Rollback", description: "Canary deployment triggers errors and automatically rolls back to stable." },
            { id: "endpoint-blocked", name: "Endpoint Blocked", description: "Sandbox attempts to call external endpoint outside allowlist and gets flagged." }
        ];
    }

    public getState(): TwinState | null {
        return this.state;
    }

    public getIsRunning(): boolean {
        return this.isRunning;
    }

    private setRunningState(running: boolean): void {
        this.isRunning = running;
        if (!running) {
            this.state = null;
            this._onStateChange.fire(null);
        }
        this._onStatusChange.fire(running);
    }

    public dispose(): void {
        this.stopServer();
        this.outputChannel.dispose();
    }
}
EOF

cat << 'EOF' > extension/src/twinViewProvider.ts
import * as vscode from 'vscode';
import { ServerManager } from './serverManager';
import { TwinState, DeploymentState } from './types';

export class TwinTreeItem extends vscode.TreeItem {
    constructor(
        public readonly label: string,
        public readonly collapsibleState: vscode.TreeItemCollapsibleState,
        public readonly contextValue?: string,
        public readonly iconPath?: vscode.ThemeIcon | string,
        public readonly description?: string,
        public readonly command?: vscode.Command
    ) {
        super(label, collapsibleState);
        this.contextValue = contextValue;
        this.iconPath = iconPath;
        this.description = description;
        this.command = command;
    }
}

export class TwinViewProvider implements vscode.TreeDataProvider<TwinTreeItem> {
    private _onDidChangeTreeData: vscode.EventEmitter<TwinTreeItem | undefined | void> = new vscode.EventEmitter<TwinTreeItem | undefined | void>();
    readonly onDidChangeTreeData: vscode.Event<TwinTreeItem | undefined | void> = this._onDidChangeTreeData.event;

    constructor(private serverManager: ServerManager) {
        this.serverManager.onStateChange(() => this.refresh());
        this.serverManager.onStatusChange(() => this.refresh());
    }

    public refresh(): void {
        this._onDidChangeTreeData.fire();
    }

    public getTreeItem(element: TwinTreeItem): vscode.TreeItem {
        return element;
    }

    public async getChildren(element?: TwinTreeItem): Promise<TwinTreeItem[]> {
        if (!this.serverManager.getIsRunning()) {
            return [
                new TwinTreeItem(
                    "Twin-Kit Server Stopped",
                    vscode.TreeItemCollapsibleState.None,
                    "stopped",
                    new vscode.ThemeIcon("circle-slash"),
                    "Click to start",
                    {
                        command: "twinKit.startServer",
                        title: "Start Twin-Kit Server"
                    }
                )
            ];
        }

        const state = this.serverManager.getState();
        if (!state) {
            return [
                new TwinTreeItem(
                    "Connecting to server...",
                    vscode.TreeItemCollapsibleState.None,
                    "loading",
                    new vscode.ThemeIcon("sync~spin")
                )
            ];
        }

        if (!element) {
            return [
                this.getMinikubeRoot(state),
                this.getRolloutRoot(state),
                this.getGrpcRoot(state),
                this.getGitRoot(state),
                this.getSafetyRoot(state)
            ];
        }

        if (element.contextValue === 'minikubeRoot') {
            const mk = state.minikube;
            if (!mk) return [];
            return [
                new TwinTreeItem(`Status: ${mk.status}`, vscode.TreeItemCollapsibleState.None, 'info', this.getStatusIcon(mk.status)),
                new TwinTreeItem(`CPUs: ${mk.cpus ?? 'N/A'}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("cpu")),
                new TwinTreeItem(`Memory: ${mk.memory || 'N/A'}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("database")),
                new TwinTreeItem(`Last Check: ${mk.lastCheck || 'N/A'}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("clock"))
            ];
        }

        if (element.contextValue === 'rolloutRoot') {
            const r = state.rollout;
            if (!r) return [];
            const items: TwinTreeItem[] = [
                new TwinTreeItem(`Phase: ${r.phase}`, vscode.TreeItemCollapsibleState.None, 'info', this.getRolloutIcon(r.phase)),
                new TwinTreeItem(`Progress: ${r.progress}%`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("dashboard"))
            ];

            if (r.deployments && r.deployments.length > 0) {
                const depsItem = new TwinTreeItem(
                    `Deployments (${r.deployments.length})`,
                    vscode.TreeItemCollapsibleState.Expanded,
                    'deploymentsGroup',
                    new vscode.ThemeIcon("layers")
                );
                items.push(depsItem);
            }
            return items;
        }

        if (element.contextValue === 'deploymentsGroup') {
            const r = state.rollout;
            if (!r || !r.deployments) return [];
            return r.deployments.map((d: DeploymentState) => {
                const isReady = d.ready === d.replicas;
                return new TwinTreeItem(
                    `${d.name}: ${d.ready}/${d.replicas} ready`,
                    vscode.TreeItemCollapsibleState.None,
                    'deploymentItem',
                    isReady ? new vscode.ThemeIcon("check", new vscode.ThemeColor("testing.iconPassed")) : new vscode.ThemeIcon("warning", new vscode.ThemeColor("testing.iconFailed")),
                    d.image
                );
            });
        }

        if (element.contextValue === 'grpcRoot') {
            const g = state.grpc;
            if (!g) return [];
            return [
                new TwinTreeItem(`Mock Service: ${g.mock}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("symbol-service")),
                new TwinTreeItem(`Status: ${g.status}`, vscode.TreeItemCollapsibleState.None, 'info', this.getStatusIcon(g.status)),
                new TwinTreeItem(`Latency: ${g.latencyMs ?? 'N/A'} ms`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("pulse"))
            ];
        }

        if (element.contextValue === 'gitRoot') {
            const git = state.git;
            if (!git) return [];
            return [
                new TwinTreeItem(`Branch: ${git.branch}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("git-branch")),
                new TwinTreeItem(`Commit: ${git.commit || 'N/A'}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("git-commit")),
                new TwinTreeItem(`Dirty: ${git.dirty ? 'Yes' : 'No'}`, vscode.TreeItemCollapsibleState.None, 'info', git.dirty ? new vscode.ThemeIcon("diff-modified") : new vscode.ThemeIcon("check"))
            ];
        }

        if (element.contextValue === 'safetyRoot') {
            const s = state.safety;
            if (!s) return [];
            const items: TwinTreeItem[] = [];

            const allowlistStr = (s.allowlist || []).join(', ');
            items.push(new TwinTreeItem(`Allowlist: ${allowlistStr}`, vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("shield")));

            const violations = s.violations || s.blocked || [];
            if (violations.length === 0) {
                items.push(new TwinTreeItem("No Endpoint Violations", vscode.TreeItemCollapsibleState.None, 'info', new vscode.ThemeIcon("pass", new vscode.ThemeColor("testing.iconPassed"))));
            } else {
                for (const v of violations) {
                    items.push(new TwinTreeItem(
                        `Blocked: ${v}`,
                        vscode.TreeItemCollapsibleState.None,
                        'safetyViolation',
                        new vscode.ThemeIcon("error", new vscode.ThemeColor("testing.iconFailed")),
                        "Click for output details",
                        {
                            command: "twinKit.showOutput",
                            title: "Show Output"
                        }
                    ));
                }
            }
            return items;
        }

        return [];
    }

    private getMinikubeRoot(state: TwinState): TwinTreeItem {
        const mk = state.minikube;
        const status = mk?.status || "Unknown";
        return new TwinTreeItem(
            `Minikube (${mk?.profile || 'twin-kit'})`,
            vscode.TreeItemCollapsibleState.Expanded,
            'minikubeRoot',
            this.getStatusIcon(status),
            status
        );
    }

    private getRolloutRoot(state: TwinState): TwinTreeItem {
        const r = state.rollout;
        const phase = r?.phase || "unknown";
        return new TwinTreeItem(
            `Rollout Phase: ${phase}`,
            vscode.TreeItemCollapsibleState.Expanded,
            'rolloutRoot',
            this.getRolloutIcon(phase),
            `${r?.progress ?? 0}%`
        );
    }

    private getGrpcRoot(state: TwinState): TwinTreeItem {
        const g = state.grpc;
        const status = g?.status || "UNKNOWN";
        return new TwinTreeItem(
            `gRPC Mock (${g?.mock || 'service'})`,
            vscode.TreeItemCollapsibleState.Expanded,
            'grpcRoot',
            this.getStatusIcon(status),
            status
        );
    }

    private getGitRoot(state: TwinState): TwinTreeItem {
        const git = state.git;
        return new TwinTreeItem(
            `Git Branch: ${git?.branch || 'main'}`,
            vscode.TreeItemCollapsibleState.Expanded,
            'gitRoot',
            new vscode.ThemeIcon("git-branch"),
            git?.dirty ? "DIRTY" : "CLEAN"
        );
    }

    private getSafetyRoot(state: TwinState): TwinTreeItem {
        const s = state.safety;
        const violations = s?.violations || s?.blocked || [];
        const hasViolations = violations.length > 0;
        return new TwinTreeItem(
            `Safety Allowlist`,
            vscode.TreeItemCollapsibleState.Expanded,
            'safetyRoot',
            hasViolations ? new vscode.ThemeIcon("warning", new vscode.ThemeColor("testing.iconFailed")) : new vscode.ThemeIcon("shield", new vscode.ThemeColor("testing.iconPassed")),
            hasViolations ? `${violations.length} BLOCKED` : "OK"
        );
    }

    private getStatusIcon(status: string): vscode.ThemeIcon {
        switch (status.toUpperCase()) {
            case 'RUNNING':
            case 'OK':
                return new vscode.ThemeIcon("circle-filled", new vscode.ThemeColor("testing.iconPassed"));
            case 'DEGRADED':
                return new vscode.ThemeIcon("circle-filled", new vscode.ThemeColor("testing.iconQueued"));
            case 'STOPPED':
            case 'DOWN':
                return new vscode.ThemeIcon("circle-filled", new vscode.ThemeColor("testing.iconFailed"));
            default:
                return new vscode.ThemeIcon("circle-outline");
        }
    }

    private getRolloutIcon(phase: string): vscode.ThemeIcon {
        switch (phase.toLowerCase()) {
            case 'stable':
                return new vscode.ThemeIcon("check-all", new vscode.ThemeColor("testing.iconPassed"));
            case 'canary':
                return new vscode.ThemeIcon("beaker", new vscode.ThemeColor("testing.iconQueued"));
            case 'promote':
                return new vscode.ThemeIcon("arrow-up", new vscode.ThemeColor("testing.iconPassed"));
            case 'rollback':
                return new vscode.ThemeIcon("discard", new vscode.ThemeColor("testing.iconFailed"));
            default:
                return new vscode.ThemeIcon("symbol-event");
        }
    }
}
EOF

cat << 'EOF' > extension/src/twinPanel.ts
import * as vscode from 'vscode';
import * as http from 'http';
import * as crypto from 'crypto';
import { ServerManager } from './serverManager';
import { TwinState } from './types';

export class TwinPanel {
    public static currentPanel: TwinPanel | undefined;
    private readonly panel: vscode.WebviewPanel;
    private disposables: vscode.Disposable[] = [];

    private constructor(
        panel: vscode.WebviewPanel,
        private extensionUri: vscode.Uri,
        private serverManager: ServerManager
    ) {
        this.panel = panel;

        this.panel.onDidDispose(() => this.dispose(), null, this.disposables);

        this.panel.webview.onDidReceiveMessage(
            async (message) => {
                switch (message.command) {
                    case 'startServer':
                        await this.serverManager.startServer();
                        break;
                    case 'stopServer':
                        await this.serverManager.stopServer();
                        break;
                    case 'runWalkthrough':
                        if (message.id) {
                            await this.serverManager.startWalkthrough(message.id);
                        } else {
                            await vscode.commands.executeCommand('twinKit.runWalkthrough');
                        }
                        break;
                    case 'refresh':
                        this.updateContent();
                        break;
                }
            },
            null,
            this.disposables
        );

        this.serverManager.onStateChange((state) => {
            this.postStateUpdate(state);
        }, null, this.disposables);

        this.serverManager.onStatusChange((running) => {
            this.updateContent();
        }, null, this.disposables);

        this.updateContent();
    }

    public static createOrShow(extensionUri: vscode.Uri, serverManager: ServerManager): TwinPanel {
        const column = vscode.window.activeTextEditor ? vscode.window.activeTextEditor.viewColumn : undefined;

        if (TwinPanel.currentPanel) {
            TwinPanel.currentPanel.panel.reveal(column);
            TwinPanel.currentPanel.updateContent();
            return TwinPanel.currentPanel;
        }

        const panel = vscode.window.createWebviewPanel(
            'twinKitVisualTwin',
            'Twin-Kit Visual Twin',
            column || vscode.ViewColumn.One,
            {
                enableScripts: true,
                retainContextWhenHidden: true,
                localResourceRoots: [vscode.Uri.joinPath(extensionUri, 'media')]
            }
        );

        TwinPanel.currentPanel = new TwinPanel(panel, extensionUri, serverManager);
        return TwinPanel.currentPanel;
    }

    private async updateContent(): Promise<void> {
        if (!this.serverManager.getIsRunning()) {
            this.panel.webview.html = this.getStoppedHtml();
            return;
        }

        try {
            const html = await this.fetchServerHtml();
            this.panel.webview.html = this.injectWebviewToolbar(html);
        } catch (err) {
            this.panel.webview.html = this.getErrorHtml(err instanceof Error ? err.message : String(err));
        }
    }

    private async fetchServerHtml(): Promise<string> {
        const cfg = this.serverManager.getConfig();
        return new Promise((resolve, reject) => {
            const req = http.get(`http://127.0.0.1:${cfg.port}/`, { timeout: 2000 }, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => resolve(data));
            });
            req.on('error', (err) => reject(err));
            req.on('timeout', () => {
                req.destroy();
                reject(new Error('Timeout fetching Twin-Kit server page'));
            });
        });
    }

    private injectWebviewToolbar(serverHtml: string): string {
        const nonce = crypto.randomBytes(16).toString('hex');
        const csp = `<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'; img-src data: http: https:; connect-src http://127.0.0.1:* http://localhost:*;"/>`;

        const toolbarHtml = `
            <style>
                .twin-toolbar {
                    background-color: #252526;
                    border-bottom: 1px solid #3c3c3c;
                    padding: 8px 12px;
                    display: flex;
                    align-items: center;
                    gap: 10px;
                    margin-bottom: 15px;
                }
                .twin-toolbar button, .twin-toolbar select {
                    background: #0e639c;
                    color: #ffffff;
                    border: none;
                    padding: 6px 12px;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 13px;
                }
                .twin-toolbar button:hover {
                    background: #1177bb;
                }
                .twin-toolbar button.stop-btn {
                    background: #f14c4c;
                }
                .twin-toolbar button.stop-btn:hover {
                    background: #d13434;
                }
                .twin-toolbar select {
                    background: #3c3c3c;
                }
            </style>
            <div class="twin-toolbar">
                <button id="btn-stop-server" class="stop-btn">Stop Server</button>
                <select id="wt-select">
                    <option value="">Run Walkthrough...</option>
                    <option value="healthy-rollout">Healthy Rollout</option>
                    <option value="canary-failure-rollback">Canary Failure & Rollback</option>
                    <option value="endpoint-blocked">Endpoint Blocked</option>
                </select>
                <button id="btn-refresh-twin">Refresh</button>
            </div>
            <script nonce="${nonce}">
                const vscode = acquireVsCodeApi();
                document.getElementById('btn-stop-server').addEventListener('click', () => {
                    vscode.postMessage({command: 'stopServer'});
                });
                document.getElementById('btn-refresh-twin').addEventListener('click', () => {
                    vscode.postMessage({command: 'refresh'});
                });
                document.getElementById('wt-select').addEventListener('change', (e) => {
                    const val = e.target.value;
                    if (val) {
                        vscode.postMessage({command: 'runWalkthrough', id: val});
                        e.target.value = '';
                    }
                });
            </script>
        `;

        let modified = serverHtml.replace('<head>', `<head>${csp}`);
        modified = modified.replace('<body>', `<body>${toolbarHtml}`);
        modified = modified.replace(/<script(?![^>]*nonce=)/gi, `<script nonce="${nonce}"`);
        return modified;
    }

    private getStoppedHtml(): string {
        const nonce = crypto.randomBytes(16).toString('hex');
        return `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Twin-Kit Visual Twin</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    background-color: #1e1e1e;
                    color: #d4d4d4;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    height: 100vh;
                    margin: 0;
                }
                .container {
                    text-align: center;
                    background: #252526;
                    border: 1px solid #3c3c3c;
                    padding: 40px;
                    border-radius: 8px;
                    box-shadow: 0 4px 10px rgba(0,0,0,0.5);
                }
                button {
                    background-color: #0e639c;
                    color: white;
                    border: none;
                    padding: 10px 20px;
                    font-size: 14px;
                    border-radius: 4px;
                    cursor: pointer;
                    margin-top: 15px;
                }
                button:hover {
                    background-color: #1177bb;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h2>Twin-Kit Server is Stopped</h2>
                <p>Start the server to view the live Visual Twin topology and pipeline state.</p>
                <button id="btn-start-server">Start Server</button>
            </div>
            <script nonce="${nonce}">
                const vscode = acquireVsCodeApi();
                document.getElementById('btn-start-server').addEventListener('click', () => {
                    vscode.postMessage({command: 'startServer'});
                });
            </script>
        </body>
        </html>`;
    }

    private getErrorHtml(errMsg: string): string {
        const nonce = crypto.randomBytes(16).toString('hex');
        return `<!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}';">
            <title>Twin-Kit Visual Twin Error</title>
            <style>
                body { font-family: sans-serif; background: #1e1e1e; color: #f14c4c; padding: 30px; }
                button { background: #0e639c; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; }
            </style>
        </head>
        <body>
            <h2>Error Loading Twin-Kit Page</h2>
            <p>${errMsg}</p>
            <button id="btn-retry">Retry</button>
            <script nonce="${nonce}">
                const vscode = acquireVsCodeApi();
                document.getElementById('btn-retry').addEventListener('click', () => {
                    vscode.postMessage({command: 'refresh'});
                });
            </script>
        </body>
        </html>`;
    }

    public postStateUpdate(state: TwinState | null): void {
        if (state) {
            this.panel.webview.postMessage({ type: 'stateUpdate', state });
        }
    }

    public dispose(): void {
        TwinPanel.currentPanel = undefined;
        this.panel.dispose();
        while (this.disposables.length) {
            const x = this.disposables.pop();
            if (x) x.dispose();
        }
    }
}
EOF

cat << 'EOF' > extension/src/walkthroughs.ts
import * as vscode from 'vscode';
import { ServerManager } from './serverManager';

export async function runWalkthroughQuickPick(serverManager: ServerManager): Promise<void> {
    if (!serverManager.getIsRunning()) {
        const start = await vscode.window.showWarningMessage('Twin-Kit server is not running.', 'Start Server');
        if (start === 'Start Server') {
            const started = await serverManager.startServer();
            if (!started) return;
        } else {
            return;
        }
    }

    const walkthroughs = await serverManager.getWalkthroughs();
    const items: vscode.QuickPickItem[] = walkthroughs.map(w => ({
        label: w.name,
        description: `(${w.id})`,
        detail: w.description
    }));

    const selected = await vscode.window.showQuickPick(items, {
        placeHolder: 'Select a scripted walkthrough to run',
        title: 'Twin-Kit Walkthroughs'
    });

    if (selected && selected.description) {
        const id = selected.description.replace(/[()]/g, '');
        vscode.window.withProgress({
            location: vscode.ProgressLocation.Notification,
            title: `Running walkthrough: ${selected.label}`,
            cancellable: false
        }, async () => {
            const ok = await serverManager.startWalkthrough(id);
            if (ok) {
                vscode.window.showInformationMessage(`Walkthrough "${selected.label}" started.`);
            } else {
                vscode.window.showErrorMessage(`Failed to start walkthrough "${selected.label}".`);
            }
        });
    }
}
EOF

cat << 'EOF' > extension/src/extension.ts
import * as vscode from 'vscode';
import { ServerManager } from './serverManager';
import { TwinViewProvider } from './twinViewProvider';
import { TwinPanel } from './twinPanel';
import { runWalkthroughQuickPick } from './walkthroughs';
import { TwinState } from './types';

let statusBarItem: vscode.StatusBarItem;

export async function activate(context: vscode.ExtensionContext) {
    const serverManager = new ServerManager(context);
    context.subscriptions.push(serverManager);

    const twinViewProvider = new TwinViewProvider(serverManager);
    vscode.window.registerTreeDataProvider('twin-kit.explorer', twinViewProvider);

    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    statusBarItem.command = 'twinKit.openVisualTwin';
    context.subscriptions.push(statusBarItem);
    updateStatusBar(serverManager, null);

    serverManager.onStateChange((state) => {
        updateStatusBar(serverManager, state);
    });

    serverManager.onStatusChange(() => {
        updateStatusBar(serverManager, serverManager.getState());
    });

    context.subscriptions.push(
        vscode.commands.registerCommand('twinKit.startServer', async () => {
            await serverManager.startServer();
        }),

        vscode.commands.registerCommand('twinKit.stopServer', async () => {
            await serverManager.stopServer();
        }),

        vscode.commands.registerCommand('twinKit.restartServer', async () => {
            await serverManager.restartServer();
        }),

        vscode.commands.registerCommand('twinKit.openVisualTwin', () => {
            TwinPanel.createOrShow(context.extensionUri, serverManager);
        }),

        vscode.commands.registerCommand('twinKit.runWalkthrough', async () => {
            await runWalkthroughQuickPick(serverManager);
        }),

        vscode.commands.registerCommand('twinKit.showOutput', () => {
            serverManager.showOutput();
        }),

        vscode.commands.registerCommand('twinKit.refreshExplorer', () => {
            twinViewProvider.refresh();
        })
    );

    context.subscriptions.push(
        vscode.workspace.onDidChangeConfiguration(async (e) => {
            if (e.affectsConfiguration('twinKit.port') || e.affectsConfiguration('twinKit.minikubeProfile')) {
                if (serverManager.getIsRunning()) {
                    vscode.window.showInformationMessage('Twin-Kit configuration changed. Restarting server...');
                    await serverManager.restartServer();
                }
            }
        })
    );

    const scriptPath = serverManager.findServerScript();
    if (scriptPath) {
        statusBarItem.show();
        const cfg = serverManager.getConfig();

        if (cfg.autoStart) {
            await serverManager.startServer();
        } else {
            vscode.window.showInformationMessage('Twin-Kit detected in workspace. Start server?', 'Start Server').then(async (sel) => {
                if (sel === 'Start Server') {
                    await serverManager.startServer();
                }
            });
        }
    } else {
        statusBarItem.show();
    }
}

function updateStatusBar(serverManager: ServerManager, state: TwinState | null): void {
    if (!serverManager.getIsRunning()) {
        statusBarItem.text = `$(circle-slash) twin-kit: Stopped`;
        statusBarItem.tooltip = `Twin-Kit server is stopped. Click to open Visual Twin panel.`;
        statusBarItem.backgroundColor = undefined;
        return;
    }

    const phase = state?.rollout?.phase || 'stable';
    const profile = state?.minikube?.profile || 'twin-kit';
    const branch = state?.git?.branch || 'main';
    const violations = state?.safety?.violations || state?.safety?.blocked || [];
    const hasViolations = violations.length > 0;

    statusBarItem.text = `$(radio-tower) twin-kit: Running - ${phase}`;

    const tooltipLines = [
        `Twin-Kit Server: Running`,
        `Profile: ${profile}`,
        `Branch: ${branch}`,
        `Rollout Phase: ${phase}`,
        `Safety Status: ${hasViolations ? `BLOCKED (${violations.length} violation(s))` : 'OK'}`
    ];
    statusBarItem.tooltip = tooltipLines.join('\n');

    if (hasViolations) {
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    } else {
        statusBarItem.backgroundColor = undefined;
    }
}

export function deactivate() {
    if (statusBarItem) {
        statusBarItem.dispose();
    }
}
EOF

# 8. Create README.md
cat << 'EOF' > README.md
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
EOF

echo "✅ Bootstrapped successfully! Run 'cd extension && npm install && npm run compile' to build."
