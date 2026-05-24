import http from "node:http";
import fs from "node:fs";
import path from "node:path";

function loadDotEnv(filePath = ".env") {
  const fullPath = path.resolve(process.cwd(), filePath);

  if (!fs.existsSync(fullPath)) {
    return;
  }

  const lines = fs.readFileSync(fullPath, "utf8").split(/\r?\n/);

  for (const line of lines) {
    const trimmed = line.trim();

    if (!trimmed || trimmed.startsWith("#")) {
      continue;
    }

    const equalsIndex = trimmed.indexOf("=");

    if (equalsIndex === -1) {
      continue;
    }

    const key = trimmed.slice(0, equalsIndex).trim();
    let value = trimmed.slice(equalsIndex + 1).trim();

    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }

    if (!process.env[key]) {
      process.env[key] = value;
    }
  }
}

loadDotEnv();

const port = Number(process.env.PORT ?? 8787);
const host = process.env.HOST ?? "0.0.0.0";
const openAIKey = process.env.OPENAI_API_KEY;
const openAIModel = process.env.OPENAI_MODEL ?? "gpt-5-mini";
const proxyToken = process.env.FITCHECK_PROXY_TOKEN ?? "";
const maxBodyBytes = 512_000;

const responseSchema = {
  type: "object",
  additionalProperties: false,
  required: ["itemIDs", "rationale", "cautions"],
  properties: {
    itemIDs: {
      type: "array",
      items: { type: "string" },
      minItems: 3,
      maxItems: 8
    },
    rationale: {
      type: "string"
    },
    cautions: {
      type: "array",
      items: { type: "string" },
      maxItems: 5
    }
  }
};

const instructions = `
You are FitCheck's private outfit reviewer. Review outfits for a single user's real closet.
Use practical, modern menswear judgment: color harmony, silhouette, material, weather, occasion,
activity, user style preferences, outfit rotation, and prior negative feedback.

Rules:
- Only return item IDs that were provided in the closet payload.
- Prefer the candidate outfit if it is solid; suggest swaps only when the candidate has a clear issue.
- Never invent clothing items, duplicate a closet item, or recommend a quantity.
- Keep the rationale concise and specific.
- Put risks or caveats in cautions, not the rationale.
`;

const server = http.createServer(async (request, response) => {
  setCommonHeaders(response);

  if (request.method === "OPTIONS") {
    response.writeHead(204);
    response.end();
    return;
  }

  if (request.method === "GET" && request.url === "/health") {
    sendJSON(response, 200, { ok: true, model: openAIModel });
    return;
  }

  if (request.method !== "POST" || request.url !== "/outfit-recommendation") {
    sendJSON(response, 404, { error: "Not found" });
    return;
  }

  if (proxyToken && request.headers["x-fitcheck-token"] !== proxyToken) {
    sendJSON(response, 401, { error: "Invalid proxy token" });
    return;
  }

  if (!openAIKey) {
    sendJSON(response, 500, { error: "OPENAI_API_KEY is not configured" });
    return;
  }

  try {
    const body = await readJSONBody(request);
    const review = await reviewOutfit(body);
    sendJSON(response, 200, review);
  } catch (error) {
    sendJSON(response, error.statusCode ?? 500, {
      error: error.message ?? "AI review failed"
    });
  }
});

server.listen(port, host, () => {
  console.log(`FitCheck AI proxy listening on http://${host}:${port}`);
});

async function reviewOutfit(requestBody) {
  const closet = Array.isArray(requestBody.closet) ? requestBody.closet : [];
  if (closet.length === 0) {
    throw httpError(400, "closet is required");
  }

  const knownIDs = new Set(closet.map((item) => item.id).filter(Boolean));
  const candidateItemIDs = Array.isArray(requestBody.candidateItemIDs)
    ? requestBody.candidateItemIDs.filter((id) => knownIDs.has(id))
    : [];

  const promptPayload = {
    weatherSummary: requestBody.weatherSummary ?? "",
    occasion: requestBody.occasion ?? "",
    activity: requestBody.activity ?? "",
    styleDescription: requestBody.styleDescription ?? "",
    selectedItemID: requestBody.selectedItemID ?? null,
    candidateItemIDs,
    localScore: requestBody.localScore ?? null,
    localNotes: Array.isArray(requestBody.localNotes) ? requestBody.localNotes : [],
    recentFeedback: Array.isArray(requestBody.recentFeedback) ? requestBody.recentFeedback : [],
    closet: closet.map((item) => ({
      id: item.id,
      name: item.name,
      category: item.category,
      color: item.color,
      pattern: item.pattern,
      formalityLevel: item.formalityLevel,
      weatherSuitability: item.weatherSuitability,
      occasionSuitability: item.occasionSuitability,
      activitySuitability: item.activitySuitability,
      notes: item.notes
    }))
  };

  const openAIResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openAIKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: openAIModel,
      instructions,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: JSON.stringify(promptPayload)
            }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "fitcheck_outfit_review",
          strict: true,
          schema: responseSchema
        }
      },
      max_output_tokens: 2000,
      store: false
    })
  });


  const data = await openAIResponse.json().catch(() => ({}));
  if (!openAIResponse.ok) {
    throw httpError(openAIResponse.status, data.error?.message ?? "OpenAI request failed");
  }

  const outputText = extractOpenAIText(data);

  if (!outputText) {
    console.error("OpenAI response without extractable text:", JSON.stringify(data, null, 2));

    if (data.status === "incomplete") {
      throw new Error(`OpenAI response incomplete: ${data.incomplete_details?.reason ?? "unknown reason"}`);
    }

    const refusal = extractOpenAIRefusal(data);
    if (refusal) {
      throw new Error(`OpenAI refused the request: ${refusal}`);
    }

    throw new Error("OpenAI response did not include output text");
  }

  const parsed = JSON.parse(outputText);
  const itemIDs = Array.isArray(parsed.itemIDs)
    ? parsed.itemIDs.filter((id) => knownIDs.has(id))
    : [];

  return {
    itemIDs: itemIDs.length > 0 ? itemIDs : candidateItemIDs,
    rationale: String(parsed.rationale ?? "AI review completed."),
    cautions: Array.isArray(parsed.cautions) ? parsed.cautions.map(String).slice(0, 5) : []
  };
}

function extractOpenAIText(data) {
  if (typeof data.output_text === "string" && data.output_text.trim()) {
    return data.output_text.trim();
  }

  const textParts = [];

  for (const output of data.output ?? []) {
    for (const content of output.content ?? []) {
      if (typeof content.text === "string") {
        textParts.push(content.text);
      }

      if (typeof content.value === "string") {
        textParts.push(content.value);
      }
    }
  }

  for (const choice of data.choices ?? []) {
    const choiceText = choice?.message?.content ?? choice?.text;
    if (typeof choiceText === "string") {
      textParts.push(choiceText);
    }
  }

  return textParts.join("\n").trim();
}

function extractOpenAIRefusal(data) {
  for (const output of data.output ?? []) {
    for (const content of output.content ?? []) {
      if (typeof content.refusal === "string" && content.refusal.trim()) {
        return content.refusal.trim();
      }
    }
  }

  return "";
}

function readJSONBody(request) {
  return new Promise((resolve, reject) => {
    let body = "";

    request.on("data", (chunk) => {
      body += chunk;
      if (Buffer.byteLength(body) > maxBodyBytes) {
        reject(httpError(413, "Request body is too large"));
        request.destroy();
      }
    });

    request.on("end", () => {
      try {
        resolve(JSON.parse(body || "{}"));
      } catch {
        reject(httpError(400, "Request body must be valid JSON"));
      }
    });

    request.on("error", reject);
  });
}

function setCommonHeaders(response) {
  response.setHeader("Access-Control-Allow-Origin", "*");
  response.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  response.setHeader("Access-Control-Allow-Headers", "Content-Type,X-FitCheck-Token");
}

function sendJSON(response, statusCode, payload) {
  response.writeHead(statusCode, { "Content-Type": "application/json" });
  response.end(JSON.stringify(payload));
}

function httpError(statusCode, message) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}
