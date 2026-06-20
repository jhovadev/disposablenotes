// src/lib/webui.bridge.ts

export type DataTypes = string | number | boolean | Uint8Array;

export interface WebUi {
  call(fn: string, ...args: DataTypes[]): Promise<DataTypes>;
  isConnected(): boolean; // Añadimos la firma del método nativo
}

declare global {
  interface Window {
    webui?: WebUi;
  }
}

export const waitForWebUI = (timeout = 2000): Promise<boolean> => {
  return new Promise((resolve) => {
    const start = Date.now();

    const check = () => {
      // CRÍTICO: Ahora esperamos a que isConnected() sea true
      if (
        window.webui &&
        typeof window.webui.isConnected === 'function' &&
        window.webui.isConnected()
      ) {
        resolve(true);
        return;
      }

      if (Date.now() - start > timeout) {
        console.warn("[WebUI] Timeout esperando la inicialización nativa.");
        resolve(false);
        return;
      }

      setTimeout(check, 50);
    };

    check();
  });
};

