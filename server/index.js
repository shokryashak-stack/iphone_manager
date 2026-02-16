const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;

app.use(
  cors({
    origin: true,
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
  })
);
app.use(express.json());
app.get('/health', (req, res) => {
  res.json({ ok: true });
});
app.use((req, res, next) => {
  console.log(req.method, req.url);
  next();
});

const ACTION_PROMPT = `
You are an Arabic inventory/order command router.
Return ONLY valid JSON object with these fields:
{
  "action": "delete_order|cancel_order|add_stock|check_stock|unknown",
  "name": string|null,
  "governorate": string|null,
  "model": "15"|"16"|"17"|null,
  "color": string|null,
  "count": number|null,
  "message": string|null
}
Rules:
- delete_order/cancel_order: fill name (and governorate if present), other fields null.
- add_stock: fill model,color,count, others null.
- check_stock: action only, all others null.
- If unclear: action=unknown and message in Arabic.
- No markdown, no explanation, JSON only.
`.trim();

function normalizeAction(payload) {
  const action = payload?.action;
  if (!action) return { action: "unknown", message: "No action returned" };

  switch (action) {
    case "delete_order":
    case "cancel_order":
      return {
        action,
        name: payload.name || "",
        ...(payload.governorate ? { governorate: payload.governorate } : {}),
      };
    case "add_stock":
      return {
        action,
        model: payload.model || "15",
        color: payload.color || "",
        count: Number.isInteger(payload.count) ? payload.count : 1,
      };
    case "check_stock":
      return { action: "check_stock" };
    default:
      return { action: "unknown", message: payload.message || "Unknown command" };
  }
}

app.post("/ai/command", async (req, res) => {
  try {
    if (!OPENAI_API_KEY) {
      return res.status(500).json({ action: "unknown", message: "OPENAI_API_KEY is missing" });
    }

    const text = (req.body?.text || "").toString().trim();
    if (!text) {
      return res.status(400).json({ action: "unknown", message: "text is required" });
    }

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: "gpt-4.1-mini",
        input: [
          {
            role: "system",
            content: ACTION_PROMPT,
          },
          { role: "user", content: text },
        ],
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      return res.status(502).json({ action: "unknown", message: `OpenAI error: ${errText}` });
    }

    const data = await response.json();
    const outputText = extractOutputText(data);
    if (!outputText) {
      return res.json({ action: "unknown", message: "No model output text returned" });
    }

    let parsed;
    try {
      parsed = JSON.parse(outputText);
    } catch {
      const recovered = tryExtractJsonObject(outputText);
      if (!recovered) {
        return res.json({ action: "unknown", message: "Invalid JSON from model" });
      }
      parsed = recovered;
    }

    return res.json(normalizeAction(parsed));
  } catch (error) {
    return res.status(500).json({ action: "unknown", message: error.message || "Server error" });
  }
});

function extractOutputText(data) {
  if (typeof data?.output_text === "string" && data.output_text.trim()) {
    return data.output_text.trim();
  }

  const chunks = [];
  for (const item of data?.output || []) {
    for (const c of item?.content || []) {
      if (c?.type === "output_text" && typeof c?.text === "string") {
        chunks.push(c.text);
      }
    }
  }
  const joined = chunks.join("\n").trim();
  return joined || null;
}

function tryExtractJsonObject(text) {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;
  const candidate = text.slice(start, end + 1);
  try {
    return JSON.parse(candidate);
  } catch {
    return null;
  }
}

app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI proxy running on http://localhost:${PORT}`);
});
