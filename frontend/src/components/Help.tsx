import { For, type Component } from "solid-js";

const SHORTCUTS: { keys: string; action: string }[] = [
  { keys: "Alt + N", action: "Nueva nota" },
  { keys: "Shift + Alt + N", action: "Nueva nota (otra ventana)" },
  { keys: "Alt + S", action: "Buscar notas" },
  { keys: "Alt + C", action: "Copiar contenido" },
  { keys: "Alt + X", action: "Copiar y eliminar nota" },
  { keys: "Alt + D", action: "Eliminar nota" },
  // { keys: "Alt + P", action: "Configuración" },
  { keys: "Alt + H", action: "Mostrar atajos" },
  { keys: "Alt + Q", action: "Cerrar ventana" },
];

const Help: Component = () => {
  return (
    <div class="flex flex-col items-center justify-center p-8 gap-6 flex-1">
      <h2 class="text-xl font-bold">Atajos de teclado</h2>
      <div class="flex flex-col gap-3 text-left">
        <For each={SHORTCUTS}>
          {({ keys, action }) => (
            <div class="flex gap-8">
              <code class="text-emerald-400 w-44 shrink-0">{keys}</code>
              <span>{action}</span>
            </div>
          )}
        </For>
      </div>
    </div>
  );
};

export default Help;
