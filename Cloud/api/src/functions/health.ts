// GET /api/v1/health -- liveness only; touches no storage, needs no auth (A.3 row 1).
import { app } from "@azure/functions";
import type { components } from "../dto.js";

type HealthResponse = components["schemas"]["HealthResponse"];

export const API_VERSION = "1";

app.http("health", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "v1/health",
  handler: () => {
    const body: HealthResponse = { ok: true, apiVersion: API_VERSION };
    return { status: 200, jsonBody: body };
  },
});
