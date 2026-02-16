const express = require("express");
const cors = require("cors");
const { GoogleGenerativeAI } = require("@google/generative-ai");

const app = express();
const PORT = process.env.PORT || 3000;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || "";
const GEMINI_MODELS = [
  "gemini-2.0-flash",
  "gemini-1.5-flash-latest",
  "gemini-1.5-flash-8b",
  "gemini-1.5-pro-latest",
];

app.use(
  cors({
    origin: true,
    methods: ["GET", "POST", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization"],
  })
);
app.use(express.json());

app.get("/health", (req, res) => {
  res.json({ ok: true });
});

app.get("/", (req, res) => {
  res.json({
    ok: true,
    service: "iphone_manager_ai_proxy",
    endpoints: ["/health", "/ai/command"],
  });
});

app.use((req, res, next) => {
  console.log(req.method, req.url);
  next();
});

const ROUTER_PROMPT = `
You are an Arabic command router for an iPhone inventory app.
Return ONLY ONE JSON object and nothing else.
Allowed actions:
- delete_order {action,name,governorate}
- cancel_order {action,name,governorate}
- add_stock {action,model,color,count}
- check_stock {action}
- unknown {action,message}

Output rules:
- Valid JSON only.
- No markdown.
- action must be one of: delete_order,cancel_order,add_stock,check_stock,unknown.
- model must be "15" or "16" or "17" when action is add_stock.
- count must be integer >= 1 when action is add_stock.
- For unknown, message must be short Arabic text.
`.trim();

let geminiAi = null;
function getGeminiAi() {
  if (!GEMINI_API_KEY) return null;
  if (!geminiAi) {
    geminiAi = new GoogleGenerativeAI(GEMINI_API_KEY);
  }
  return geminiAi;
}

function isModelNotFoundError(message) {
  const s = String(message || "").toLowerCase();
  return (
    s.includes("404") ||
    s.includes("not found") ||
    s.includes("is not supported")
  );
}

async function generateWithFallbackModels(promptText) {
  const ai = getGeminiAi();
  if (!ai) {
    throw new Error("GEMINI_API_KEY is missing");
  }

  let lastError = null;
  for (const modelName of GEMINI_MODELS) {
    try {
      const model = ai.getGenerativeModel({ model: modelName });
      const result = await model.generateContent({
        contents: [
          {
            role: "user",
            parts: [{ text: promptText }],
          },
        ],
        generationConfig: {
          temperature: 0,
        },
      });
      return result?.response?.text?.() || "";
    } catch (error) {
      lastError = error;
      if (!isModelNotFoundError(error?.message)) {
        throw error;
      }
    }
  }

  throw lastError || new Error("No supported Gemini model found");
}

function normalizeAction(payload) {
  const action = payload?.action;
  if (!action) return { action: "unknown", message: "الامر غير واضح" };

  if (action === "delete_order" || action === "cancel_order") {
    return {
      action,
      name: String(payload.name || "").trim(),
      ...(payload.governorate ? { governorate: String(payload.governorate).trim() } : {}),
    };
  }

  if (action === "add_stock") {
    const model = String(payload.model || "");
    const count = Number.parseInt(payload.count, 10);
    return {
      action: "add_stock",
      model: model === "15" || model === "16" || model === "17" ? model : "15",
      color: String(payload.color || "").trim(),
      count: Number.isInteger(count) && count > 0 ? count : 1,
    };
  }

  if (action === "check_stock") {
    return { action: "check_stock" };
  }

  return { action: "unknown", message: String(payload.message || "الامر غير واضح").trim() };
}

function tryParseJson(text) {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
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
}

app.post("/ai/command", async (req, res) => {
  try {
    const text = String(req.body?.text || "").trim();
    if (!text) {
      return res.status(400).json({ action: "unknown", message: "text is required" });
    }

    const raw = await generateWithFallbackModels(
      `${ROUTER_PROMPT}\n\nUser command: ${text}`
    );
    const parsed = tryParseJson(raw);
    if (!parsed) {
      return res.json({ action: "unknown", message: "رد غير صالح من Gemini" });
    }

    return res.json(normalizeAction(parsed));
  } catch (error) {
    return res.status(500).json({
      action: "unknown",
      message: error?.message || "Server error",
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI proxy running on http://localhost:${PORT}`);
});
