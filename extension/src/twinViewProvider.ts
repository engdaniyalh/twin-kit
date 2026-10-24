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
            // Root elements: 5 sections
            return [
                this.getMinikubeRoot(state),
                this.getRolloutRoot(state),
                this.getGrpcRoot(state),
                this.getGitRoot(state),
                this.getSafetyRoot(state)
            ];
        }

        // Child elements based on parent contextValue
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
