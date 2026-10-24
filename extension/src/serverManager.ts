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
            pythonPath: config.get<string>('pythonPath', 'python3'),
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

        const pythonExec = cfg.pythonPath || 'python3';
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

            // Wait brief moment for startup
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
        this.pollState(); // immediate initial poll
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
            // Attached server died
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
