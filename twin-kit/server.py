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
