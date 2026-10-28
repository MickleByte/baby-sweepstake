import { health } from "./handlers/health";
import { createRouter } from "./router";

export const handler = createRouter({
  "GET /api/health": health,
});
