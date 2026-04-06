import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;

export function activate(context: vscode.ExtensionContext): void {
  const config = vscode.workspace.getConfiguration("zgraph");
  const lspEnabled = config.get<boolean>("lsp.enabled", true);

  if (!lspEnabled) {
    return;
  }

  const zgraphPath = config.get<string>("lsp.path", "zgraph");

  const serverOptions: ServerOptions = {
    command: zgraphPath,
    args: ["lsp"],
    transport: TransportKind.stdio,
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: "file", language: "zgraph" }],
  };

  client = new LanguageClient(
    "zgraph",
    "zgraph Language Server",
    serverOptions,
    clientOptions,
  );

  client.start().catch((err: Error) => {
    vscode.window.showErrorMessage(
      `zgraph LSP failed to start: ${err.message}. Check the "zgraph.lsp.path" setting.`,
    );
  });

  context.subscriptions.push({
    dispose: () => {
      if (client) {
        client.stop();
      }
    },
  });
}

export function deactivate(): Thenable<void> | undefined {
  if (client) {
    return client.stop();
  }
  return undefined;
}
