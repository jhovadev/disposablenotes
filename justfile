default:
    @just --list

# Compilar frontend
build-frontend:
    bun --cwd=frontend/ run build

build-app:
    zig build -Doptimize=ReleaseSmall

# Modo producción (webview nativa)
run: build-frontend
    zig build run

# Modo desarrollo (browser + vite dev server - inicia automáticamente bun dev)
dev file="~/.disposablenotes/notes.json" format="json":
    zig build run -Ddev=true -- "{{file}}" --format "{{format}}"

# Limpiar
clean:
    rm -rf ./dist/
