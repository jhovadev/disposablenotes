// hooks/createShortcut.ts
import { onCleanup, onMount } from "solid-js";

type ShortcutOptions = {
  ctrl?: boolean;
  meta?: boolean; // Para la tecla Command en Mac
  alt?: boolean;
  shift?: boolean;
};

export function createShortcut(
  key: string,
  callback: (e: KeyboardEvent) => void,
  options: ShortcutOptions = {}
) {
  const handleKeyDown = (event: KeyboardEvent) => {
    // Comprobar si la tecla coincide (ignorando mayúsculas/minúsculas)
    if (event.key.toLowerCase() !== key.toLowerCase()) return;

    // Verificar modificadores (Ctrl, Cmd, Alt, Shift)
    const ctrlMatch = options.ctrl ? (event.ctrlKey || event.metaKey) : !event.ctrlKey && !event.metaKey;
    const altMatch = options.alt ? event.altKey : !event.altKey;
    const shiftMatch = options.shift ? event.shiftKey : !event.shiftKey;

    if (ctrlMatch && altMatch && shiftMatch) {
      event.preventDefault(); // Evitamos la acción nativa del navegador si es necesario
      callback(event);
    }
  };

  onMount(() => {
    window.addEventListener("keydown", handleKeyDown);
  });

  onCleanup(() => {
    window.removeEventListener("keydown", handleKeyDown);
  });
}
