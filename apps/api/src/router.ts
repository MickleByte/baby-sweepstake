import type {
  APIGatewayProxyEventV2,
  APIGatewayProxyStructuredResultV2,
} from "aws-lambda";

export interface ApiRequest {
  method: string;
  path: string;
}

export interface ApiResponse {
  status: number;
  body: unknown;
}

/** A route handler: a plain function from request to response, free of Lambda types. */
export type RouteHandler = (request: ApiRequest) => Promise<ApiResponse>;

/** Routes keyed by `"<METHOD> <path>"`, e.g. `"GET /api/health"`. */
export type Routes = Record<string, RouteHandler>;

export function createRouter(routes: Routes) {
  return async (
    event: APIGatewayProxyEventV2,
  ): Promise<APIGatewayProxyStructuredResultV2> => {
    const request: ApiRequest = {
      method: event.requestContext.http.method,
      path: event.rawPath,
    };
    const route = routes[`${request.method} ${request.path}`];
    const response: ApiResponse = route
      ? await route(request)
      : { status: 404, body: { error: "Not found" } };

    return {
      statusCode: response.status,
      headers: { "content-type": "application/json" },
      body: JSON.stringify(response.body),
    };
  };
}
