import { defineConfig, loadEnv } from 'vite'
import UnoCSS from "unocss/vite"
import solid from 'vite-plugin-solid'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, '../', '');
  const webuiPort = env.VITE_WEBUI_PORT || '8000';

  return {
    plugins: [UnoCSS(), solid()],
    base: "./",
    envDir: "../",
    server: {
      proxy: {
        '/webui.js': {
          target: `http://localhost:${webuiPort}`,
          changeOrigin: true,
        },
        '/_webui_ws_connect': {
          target: `ws://localhost:${webuiPort}`,
          ws: true,
          changeOrigin: true,
        },
      }
    }
  };
})
