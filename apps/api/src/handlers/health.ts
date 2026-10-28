import type { RouteHandler } from "../router";

export const health: RouteHandler = async () => ({
  status: 200,
  body: { status: "ok" },
});
