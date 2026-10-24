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
                <button onclick="vscode.postMessage({command: 'stopServer'})">Stop Server</button>
                <select id="wt-select" onchange="if(this.value) { vscode.postMessage({command: 'runWalkthrough', id: this.value}); this.value=''; }">
                    <option value="">Run Walkthrough...</option>
                    <option value="healthy-rollout">Healthy Rollout</option>
                    <option value="canary-failure-rollback">Canary Failure & Rollback</option>
                    <option value="endpoint-blocked">Endpoint Blocked</option>
                </select>
                <button onclick="vscode.postMessage({command: 'refresh'})">Refresh</button>
            </div>
            <script nonce="${nonce}">
                const vscode = acquireVsCodeApi();
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
                <button onclick="vscode.postMessage({command: 'startServer'})">Start Server</button>
            </div>
            <script nonce="${nonce}">
                const vscode = acquireVsCodeApi();
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
            <button onclick="vscode.postMessage({command: 'refresh'})">Retry</button>
            <script nonce="${nonce}">
                const vscode = acquireVsCodeApi();
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
