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
