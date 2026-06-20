/* @refresh reload */
import "virtual:uno.css"
import './index.css'
import { render } from 'solid-js/web'
import { Router } from "@solidjs/router";
import { type RouteDefinition, Navigate } from "@solidjs/router"
import { lazy } from "solid-js";

// Dynamically inject webui.js script tag in development mode only
const injectWebUI = () => {
  if (import.meta.env.DEV) {
    const urlParams = new URLSearchParams(window.location.search);
    const queryPort = urlParams.get('webui_port');
    const webuiPort = queryPort || import.meta.env.VITE_WEBUI_PORT || '8000';
    const script = document.createElement('script');
    script.src = `http://localhost:${webuiPort}/webui.js`;
    script.async = false;
    document.head.appendChild(script);
  }
};

injectWebUI();

const routes: RouteDefinition[] = [
  {
    path: "/",
    component: () => <Navigate href="/default" />,
  },
  {
    path: "/:id",
    component: lazy(() => import("./App.tsx")),
  }
];

const root = document.getElementById('root')

render(() => <Router>{routes}</Router>, root!)
