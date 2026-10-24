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

    // Register Sidebar TreeDataProvider
    const twinViewProvider = new TwinViewProvider(serverManager);
    vscode.window.registerTreeDataProvider('twin-kit.explorer', twinViewProvider);

    // Status Bar Item
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    statusBarItem.command = 'twinKit.openVisualTwin';
    context.subscriptions.push(statusBarItem);
    updateStatusBar(serverManager, null);

    // Subscribe to state and status changes for status bar
    serverManager.onStateChange((state) => {
        updateStatusBar(serverManager, state);
    });

    serverManager.onStatusChange(() => {
        updateStatusBar(serverManager, serverManager.getState());
    });

    // Register Commands
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

    // Configuration change listener
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

    // Detect server script in workspace on activation
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
