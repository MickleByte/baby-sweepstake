import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { describe, expect, it } from "vitest";
import { handler } from "./index";

function httpEvent(method: string, path: string): APIGatewayProxyEventV2 {
  return {
    version: "2.0",
    routeKey: "$default",
    rawPath: path,
    rawQueryString: "",
    headers: {},
    isBase64Encoded: false,
    requestContext: {
      http: { method, path, protocol: "HTTP/1.1", sourceIp: "", userAgent: "" },
    },
  } as APIGatewayProxyEventV2;
}

describe("GET /api/health", () => {
  it("reports that the API is ok", async () => {
    const response = await handler(httpEvent("GET", "/api/health"));

    expect(response).toMatchObject({
      statusCode: 200,
      headers: { "content-type": "application/json" },
    });
    expect(JSON.parse(response.body ?? "")).toEqual({ status: "ok" });
  });
});

describe("unknown routes", () => {
  it("respond with 404", async () => {
    const response = await handler(httpEvent("POST", "/api/health"));

    expect(response.statusCode).toBe(404);
  });
});
