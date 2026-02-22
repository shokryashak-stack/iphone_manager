const express = require("express");
const cors = require("cors");
const { GoogleGenerativeAI } = require("@google/generative-ai");
const crypto = require("crypto");

const app = express();
const PORT = process.env.PORT || 3000;
const AI_PROVIDER = String(process.env.AI_PROVIDER || "auto").toLowerCase();
const OPENROUTER_API_KEY = process.env.OPENROUTER_API_KEY || "";
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || "openai/gpt-4o-mini";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const OPENAI_BASE_URL = process.env.OPENAI_BASE_URL || "https://api.openai.com/v1";
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-4o-mini";

const GEMINI_MODELS = [
  "gemini-2.0-flash",
  "gemini-2.5-flash",
  "gemini-1.5-flash-latest",
  "gemini-1.5-flash-8b"
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
    endpoints: ["/health", "/ai/command", "/ai/parse_orders", "/ai/match_delivery", "/ai/resolve_unmatched_row"],
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

function normalizeSpaces(s) {
  return String(s || "").replace(/\s+/g, " ").trim();
}

function detectModel(text) {
  if (/(?:^|\s)(17|ط¸طŒط¸آ§)(?:\s|$)/.test(text)) return "17";
  if (/(?:^|\s)(16|ط¸طŒط¸آ¦)(?:\s|$)/.test(text)) return "16";
  if (/(?:^|\s)(15|ط¸طŒط¸آ¥)(?:\s|$)/.test(text)) return "15";
  return null;
}

function detectColor(text) {
  const colors = [
    "ط·آ³ط¸â€‍ط¸ظ¾ط·آ±",
    "ط¸ظ¾ط·آ¶ط¸ظ¹",
    "ط·آ§ط·آ³ط¸ث†ط·آ¯",
    "ط·آ£ط·آ³ط¸ث†ط·آ¯",
    "ط·آ§ط·آ²ط·آ±ط¸â€ڑ",
    "ط·آ£ط·آ²ط·آ±ط¸â€ڑ",
    "ط·آ¯ط¸â€،ط·آ¨ط¸ظ¹",
    "ط·آ°ط¸â€،ط·آ¨ط¸ظ¹",
    "ط·آ¨ط·آ±ط·ع¾ط¸â€ڑط·آ§ط¸â€‍ط¸ظ¹",
    "ط·ع¾ط¸ظ¹ط·ع¾ط·آ§ط¸â€ ط¸ظ¹ط¸ث†ط¸â€¦",
    "ط¸ئ’ط·آ­ط¸â€‍ط¸ظ¹",
    "ط·آ§ط·آ¨ط¸ظ¹ط·آ¶",
    "ط·آ£ط·آ¨ط¸ظ¹ط·آ¶",
  ];
  const found = colors.find((c) => text.includes(c));
  return found ? found.replace("ط·آ£", "ط·آ§") : null;
}

function detectCount(text) {
  const m = text.match(/(\d+)/);
  if (!m) return 1;
  const n = Number.parseInt(m[1], 10);
  return Number.isInteger(n) && n > 0 ? n : 1;
}

function parseRuleBased(textRaw) {
  const text = normalizeSpaces(textRaw);
  if (!text) return { action: "unknown", message: "ط·آ§ط¸ئ’ط·ع¾ط·آ¨ ط·آ£ط¸â€¦ط·آ± ط·آ£ط¸ث†ط¸â€‍ط¸â€¹ط·آ§" };

  const lower = text.toLowerCase();
  if (text.includes("ط·آ§ط¸â€‍ط¸â€¦ط·آ®ط·آ²ط¸â€ ") || text.includes("ط·آ§ط¸â€‍ط·آ¬ط·آ±ط·آ¯") || lower.includes("check stock")) {
    return { action: "check_stock" };
  }

  if (text.includes("ط·آ§ط¸â€¦ط·آ³ط·آ­") || text.includes("ط·آ§ط·آ­ط·آ°ط¸ظ¾") || text.includes("ط·آ­ط·آ°ط¸ظ¾") || text.includes("ط·آ´ط¸ظ¹ط¸â€‍")) {
    const name = normalizeSpaces(
      text
        .replace(/.*(ط·آ§ط¸ث†ط·آ±ط·آ¯ط·آ±|ط·آ£ط¸ث†ط·آ±ط·آ¯ط·آ±|ط·آ·ط¸â€‍ط·آ¨|ط·آ¹ط¸â€¦ط¸ظ¹ط¸â€‍)/, "")
        .replace(/.*(ط·آ§ط¸â€¦ط·آ³ط·آ­|ط·آ§ط·آ­ط·آ°ط¸ظ¾|ط·آ­ط·آ°ط¸ظ¾|ط·آ´ط¸ظ¹ط¸â€‍)/, "")
    );
    return { action: "delete_order", name };
  }

  if (text.includes("ط·آ§ط¸â€‍ط·ط›ط¸ظ¹") || text.includes("ط·آ¥ط¸â€‍ط·ط›ط¸ظ¹") || lower.includes("cancel")) {
    const name = normalizeSpaces(
      text
        .replace(/.*(ط·آ§ط¸ث†ط·آ±ط·آ¯ط·آ±|ط·آ£ط¸ث†ط·آ±ط·آ¯ط·آ±|ط·آ·ط¸â€‍ط·آ¨|ط·آ¹ط¸â€¦ط¸ظ¹ط¸â€‍)/, "")
        .replace(/.*(ط·آ§ط¸â€‍ط·ط›ط¸ظ¹|ط·آ¥ط¸â€‍ط·ط›ط¸ظ¹|cancel)/i, "")
    );
    return { action: "cancel_order", name };
  }

  if (
    text.includes("ط·آ²ط¸ث†ط·آ¯") ||
    text.includes("ط·آ¶ط¸ظ¹ط¸ظ¾") ||
    text.includes("ط·آ§ط·آ¶ط¸ظ¾") ||
    text.includes("ط·آ£ط·آ¶ط¸ظ¾") ||
    lower.includes("add stock")
  ) {
    const model = detectModel(text);
    const color = detectColor(text);
    if (!model || !color) {
      return { action: "unknown", message: "ط·آ­ط·آ¯ط·آ¯ ط·آ§ط¸â€‍ط¸â€¦ط¸ث†ط·آ¯ط¸ظ¹ط¸â€‍ ط¸ث†ط·آ§ط¸â€‍ط¸â€‍ط¸ث†ط¸â€ . ط¸â€¦ط·آ«ط·آ§ط¸â€‍: ط·آ²ط¸ث†ط·آ¯ 2 ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€  16 ط·آ³ط¸â€‍ط¸ظ¾ط·آ±" };
    }
    return { action: "add_stock", model, color, count: detectCount(text) };
  }

  return {
    action: "unknown",
    message: "ط·آ§ط¸â€‍ط·آ£ط¸â€¦ط·آ± ط·ط›ط¸ظ¹ط·آ± ط¸ث†ط·آ§ط·آ¶ط·آ­. ط¸â€¦ط·آ«ط·آ§ط¸â€‍: ط·آ§ط¸â€¦ط·آ³ط·آ­ ط·آ£ط¸ث†ط·آ±ط·آ¯ط·آ± ط¸â€¦ط·آ­ط¸â€¦ط·آ¯ ط·آ£ط¸ث† ط·آ²ط¸ث†ط·آ¯ 2 ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€  16 ط·آ³ط¸â€‍ط¸ظ¾ط·آ±",
  };
}

// ============== التعديل الجديد هنا ==============
let geminiAi = null;
let currentApiKey = null;

function getGeminiAi() {
  const activeKey = process.env.GEMINI_API_KEY || process.env.GOOGLE_API_KEY || "";
  if (!activeKey) return null;

  if (!geminiAi || currentApiKey !== activeKey) {
    geminiAi = new GoogleGenerativeAI(activeKey);
    currentApiKey = activeKey;
  }
  return geminiAi;
}
// ===============================================

function isModelNotFoundError(message) {
  const s = String(message || "").toLowerCase();
  return (
    s.includes("404") ||
    s.includes("not found") ||
    s.includes("is not supported")
  );
}

async function callOpenAICompatible({
  apiKey,
  baseUrl,
  model,
  promptText,
  referer,
  title,
}) {
  if (!apiKey) {
    throw new Error("OpenAI-compatible API key is missing");
  }

  const headers = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiKey}`,
  };
  if (referer) headers["HTTP-Referer"] = referer;
  if (title) headers["X-Title"] = title;

  const response = await fetch(`${baseUrl.replace(/\/+$/, "")}/chat/completions`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      model,
      temperature: 0,
      messages: [{ role: "user", content: promptText }],
    }),
  });

  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`OpenAI-compatible HTTP ${response.status}: ${raw}`);
  }

  let parsed = null;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {}

  const content = parsed?.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI-compatible response has no choices[0].message.content");
  }
  return String(content);
}

async function generateWithFallbackModels(promptText) {
  const providerErrors = [];

  const canUseOpenRouter = !!OPENROUTER_API_KEY;
  const canUseOpenAI = !!OPENAI_API_KEY;
  const canUseGemini = !!getGeminiAi();

  const tryOpenRouter = AI_PROVIDER === "openrouter" || (AI_PROVIDER === "auto" && canUseOpenRouter);
  if (tryOpenRouter) {
    try {
      return await callOpenAICompatible({
        apiKey: OPENROUTER_API_KEY,
        baseUrl: "https://openrouter.ai/api/v1",
        model: OPENROUTER_MODEL,
        promptText,
        referer: process.env.OPENROUTER_REFERER || "https://iphone-manager.onrender.com",
        title: process.env.OPENROUTER_TITLE || "iphone_manager_ai_proxy",
      });
    } catch (error) {
      providerErrors.push(`openrouter: ${error?.message || String(error)}`);
      if (AI_PROVIDER === "openrouter") throw error;
    }
  }

  const tryOpenAI = AI_PROVIDER === "openai" || (AI_PROVIDER === "auto" && !canUseOpenRouter && canUseOpenAI);
  if (tryOpenAI) {
    try {
      return await callOpenAICompatible({
        apiKey: OPENAI_API_KEY,
        baseUrl: OPENAI_BASE_URL,
        model: OPENAI_MODEL,
        promptText,
      });
    } catch (error) {
      providerErrors.push(`openai: ${error?.message || String(error)}`);
      if (AI_PROVIDER === "openai") throw error;
    }
  }

  const tryGemini = AI_PROVIDER === "gemini" || AI_PROVIDER === "auto";
  if (!tryGemini) {
    throw new Error(`AI provider '${AI_PROVIDER}' is invalid. Use auto|gemini|openrouter|openai`);
  }

  const ai = getGeminiAi();
  if (!ai) {
    if (providerErrors.length) {
      throw new Error(`No working AI provider. ${providerErrors.join(" | ")} | gemini: GEMINI_API_KEY missing`);
    }
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

  if (providerErrors.length) {
    throw new Error(`${providerErrors.join(" | ")} | gemini: ${lastError?.message || "No supported Gemini model found"}`);
  }
  throw lastError || new Error("No supported Gemini model found");
}

function normalizeAction(payload) {
  const action = payload?.action;
  if (!action) return { action: "unknown", message: "ط·آ§ط¸â€‍ط·آ§ط¸â€¦ط·آ± ط·ط›ط¸ظ¹ط·آ± ط¸ث†ط·آ§ط·آ¶ط·آ­" };

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

  return { action: "unknown", message: String(payload.message || "ط·آ§ط¸â€‍ط·آ§ط¸â€¦ط·آ± ط·ط›ط¸ظ¹ط·آ± ط¸ث†ط·آ§ط·آ¶ط·آ­").trim() };
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

function normalizeNewlines(s) {
  return String(s || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

function stripDiacritics(s) {
  return String(s || "").replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "");
}

function stripBidi(s) {
  return String(s || "").replace(/[\u200E\u200F\u202A-\u202E]/g, "");
}

function normalizeArabicDigits(s) {
  const map = {
    "ط¸آ ": "0",
    "ط¸طŒ": "1",
    "ط¸آ¢": "2",
    "ط¸آ£": "3",
    "ط¸آ¤": "4",
    "ط¸آ¥": "5",
    "ط¸آ¦": "6",
    "ط¸آ§": "7",
    "ط¸آ¨": "8",
    "ط¸آ©": "9",
  };
  return String(s || "").replace(/[ط¸آ -ط¸آ©]/g, (d) => map[d] || d);
}

function normalizePhone(phone) {
  const s = normalizeArabicDigits(String(phone || ""))
    .replace(/[^\d+]/g, "")
    .replace(/^(\+?20)/, "0");
  const m = s.match(/0?1[0-2,5]\d{8}/);
  if (!m) return "";
  const raw = m[0];
  return raw.startsWith("0") ? raw : `0${raw}`;
}

function detectModelDigitAny(text) {
  const t = normalizeArabicDigits(String(text || ""));
  if (/(?:^|\D)17(?:\D|$)/.test(t)) return "17";
  if (/(?:^|\D)16(?:\D|$)/.test(t)) return "16";
  if (/(?:^|\D)15(?:\D|$)/.test(t)) return "15";
  return "";
}

function normalizeModelNameAny(modelRaw) {
  const d = detectModelDigitAny(modelRaw);
  return d ? `${d} Pro Max` : "";
}

function extractNormalizedModels(textRaw, count) {
  const text = normalizeSpaces(normalizeNewlines(stripBidi(normalizeArabicDigits(stripDiacritics(String(textRaw || ""))))));
  const digits = [];
  const re = /(?:ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ |iphone)?\s*(15|16|17)\s*(?:pro|max|ط·آ¨ط·آ±ط¸ث†|ط¸â€¦ط·آ§ط¸ئ’ط·آ³)?/gi;
  let m;
  while ((m = re.exec(text)) !== null) {
    const d = m[1];
    if (d === "15" || d === "16" || d === "17") digits.push(d);
  }
  const out = digits.map((d) => `${d} Pro Max`);
  const safeCount = Number.isInteger(count) && count > 0 ? count : 1;
  if (!out.length) return [];
  const filled = out.slice(0, safeCount);
  while (filled.length < safeCount) filled.push(out[0]);
  return filled;
}

function normalizeColorNameAny(colorRaw) {
  const s = normalizeSpaces(stripDiacritics(String(colorRaw || ""))).toLowerCase();
  if (!s) return "";

  const has = (...tokens) => tokens.some((token) => token && s.includes(token));

  if (has("سلفر", "سيلفر", "فضي", "فضى", "ابيض", "أبيض", "silver", "white", "ط·آ³ط¸â€‍ط¸ظ¾ط·آ±", "ط¸ظ¾ط·آ¶ط¸ظ¹")) return "سلفر";
  if (has("اسود", "أسود", "black", "ط·آ§ط·آ³ط¸ث†ط·آ¯")) return "اسود";
  if (has("دهبي", "ذهبي", "gold", "golden", "ط·آ¯ط¸â€،ط·آ¨ط¸ظ¹")) return "دهبي";
  if (has("برتقالي", "برتقاني", "اورنج", "أورنج", "اورانج", "أورانج", "orange", "ط·آ¨ط·آ±ط·ع¾ط¸â€ڑط·آ§ط¸â€‍ط¸ظ¹")) return "برتقالي";
  if (has("كحلي", "كحلى", "navy", "dark blue", "ط¸ئ’ط·آ­ط¸â€‍ط¸ظ¹")) return "كحلي";
  if (has("تيتانيوم", "تيتاني", "natural", "natural titanium", "ط·ع¾ط¸ظ¹ط·ع¾ط·آ§ط¸â€ ط¸ظ¹ط¸ث†ط¸â€¦")) return "تيتانيوم";
  if (has("ازرق", "أزرق", "blue", "ط·آ§ط·آ²ط·آ±ط¸â€ڑ")) return "ازرق";

  return "";
}

const STOCK_COLORS_BY_MODEL = {
  "15 Pro Max": ["سلفر", "اسود", "ازرق"],
  "16 Pro Max": ["سلفر", "دهبي", "اسود"],
  "17 Pro Max": ["برتقالي", "سلفر", "اسود", "دهبي", "تيتانيوم", "كحلي", "ازرق"],
};

function normalizeColorForModel(modelKey, colorRaw) {
  const normalized = normalizeColorNameAny(colorRaw);
  if (!normalized) return "";
  const allowed = STOCK_COLORS_BY_MODEL[modelKey] || [];
  if (allowed.includes(normalized)) return normalized;
  if (normalized === "ازرق" && allowed.includes("كحلي")) return "كحلي";
  if (normalized === "كحلي" && allowed.includes("ازرق")) return "ازرق";
  return normalized;
}

function extractNormalizedColors(textRaw) {
  const text = normalizeNewlines(stripBidi(normalizeArabicDigits(stripDiacritics(String(textRaw || "")))));
  const colors = [];
  const push = (c) => {
    if (!c) return;
    if (!colors.includes(c)) colors.push(c);
  };

  const m = text.match(/(?:الوان|ألوان|اللون|لون)\s*[:\/]?\s*([^\n]+)/i);
  if (m && m[1]) {
    const seg = normalizeSpaces(m[1]);
    for (const part of seg.split(/[\u060C,|/]|(?:\s+و\s+)|(?:\s*&\s*)/).map((x) => x.trim()).filter(Boolean)) {
      push(normalizeColorNameAny(part));
    }
  }

  const lines = text.split("\n").map((l) => normalizeSpaces(l)).filter(Boolean);
  for (const line of lines) {
    const c = normalizeColorNameAny(line);
    if (c) push(c);
  }

  return colors;
}

function extractCount(textRaw) {
  const text = normalizeSpaces(normalizeNewlines(stripBidi(normalizeArabicDigits(stripDiacritics(String(textRaw || ""))))));
  const m = text.match(/(\d+)\s*ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ ط·آ§ط·ع¾|(\d+)\s*ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ |(\d+)\s*iphone/i);
  const n = m ? Number.parseInt(m[1] || m[2] || m[3] || "1", 10) : 1;
  return Number.isInteger(n) && n > 0 ? n : 1;
}

function tryParseJsonArray(textRaw) {
  if (!textRaw) return null;
  const text = String(textRaw)
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();
  try {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed) ? parsed : null;
  } catch (_) {
    const start = text.indexOf("[");
    const end = text.lastIndexOf("]");
    if (start === -1 || end === -1 || end <= start) return null;
    const candidate = text.slice(start, end + 1);
    try {
      const parsed = JSON.parse(candidate);
      return Array.isArray(parsed) ? parsed : null;
    } catch {
      return null;
    }
  }
}

function splitWhatsAppBlocks(rawText) {
  const text = normalizeNewlines(rawText);
  let parts = text
    .split(/(?=^\s*\[\d{1,2}\/\d{1,2},[^\]]+\]\s)/m)
    .map((p) => p.trim())
    .filter(Boolean);
  if (parts.length <= 1) {
    parts = text
      .split(/(?=^\s*(?:ط·آ§ط·آ³ط¸â€¦ ط·آ§ط¸â€‍ط·آ¹ط¸â€¦ط¸ظ¹ط¸â€‍|ط·آ§ط¸â€‍ط·آ§ط·آ³ط¸â€¦)\s*\/?)/m)
      .map((p) => p.trim())
      .filter(Boolean);
  }
  return parts.length ? parts : [text.trim()].filter(Boolean);
}

function pickLargestPrice(nums) {
  const candidates = nums.filter((n) => n >= 3000 && n <= 20000);
  if (!candidates.length) return 0;
  return Math.max(...candidates);
}

function parseWhatsAppBlockRuleBased(blockRaw) {
  const block = normalizeNewlines(blockRaw);
  const cleaned = block
    .replace(/^\s*\[[^\]]+\]\s*/m, "")
    .replace(/^\s*\+\d+\s+\d+\s+\d+:\s*/m, "")
    .trim();

  const text = stripBidi(stripDiacritics(cleaned));
  const textDigits = stripBidi(normalizeArabicDigits(text));
  const textNoPhones = textDigits.replace(/0?1[0-2,5]\d{8}/g, " ");
  const lines = textDigits
    .split("\n")
    .map((l) => normalizeSpaces(l))
    .filter(Boolean);

  const phones = Array.from(
    new Set((textDigits.match(/(?:\+?20)?\s*0?1[0-2,5]\d{8}/g) || []).map(normalizePhone).filter(Boolean))
  );
  const phone = phones[0] || "";

  let name = "";
  const nameLine = lines.find((l) => /ط·آ§ط·آ³ط¸â€¦ ط·آ§ط¸â€‍ط·آ¹ط¸â€¦ط¸ظ¹ط¸â€‍\s*\/|ط·آ§ط¸â€‍ط·آ§ط·آ³ط¸â€¦\s*/.test(l));
  if (nameLine) {
    name = normalizeSpaces(nameLine.replace(/.*(?:ط·آ§ط·آ³ط¸â€¦ ط·آ§ط¸â€‍ط·آ¹ط¸â€¦ط¸ظ¹ط¸â€‍|ط·آ§ط¸â€‍ط·آ§ط·آ³ط¸â€¦)\s*\/?/g, ""));
  } else if (lines.length) {
    name = normalizeSpaces(lines[0].replace(/^\s*[:\\-]+/, ""));
  }

  let governorate = "";
  const govLine = lines.find((l) => /ط·آ§ط¸â€‍ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط¸â€،\s*\/|ط·آ§ط¸â€‍ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط·آ©\s*\/|ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط¸â€،|ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط·آ©/.test(l));
  if (govLine) {
    governorate = normalizeSpaces(govLine.replace(/.*(?:ط·آ§ط¸â€‍ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط¸â€،|ط·آ§ط¸â€‍ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط·آ©|ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط¸â€،|ط¸â€¦ط·آ­ط·آ§ط¸ظ¾ط·آ¸ط·آ©)\s*\/?/g, ""));
  } else {
    const possibleGov = lines.find((l) => l.length <= 20 && !/ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ |iphone|pro|max|ط¸â€‍ط¸ث†ط¸â€ |ط·آ´ط·آ­ط¸â€ |ط·آ®ط·آµط¸â€¦|\d/.test(l));
    if (possibleGov) governorate = possibleGov;
  }

  let address = "";
  const addrIdx = lines.findIndex((l) => /ط·آ§ط¸â€‍ط·آ¹ط¸â€ ط¸ث†ط·آ§ط¸â€  ط·آ¨ط·آ§ط¸â€‍ط·ع¾ط¸ظ¾ط·آµط¸ظ¹ط¸â€‍\s*\/|ط·آ§ط¸â€‍ط·آ¹ط¸â€ ط¸ث†ط·آ§ط¸â€ \s*/.test(l));
  if (addrIdx !== -1) {
    address = normalizeSpaces(lines[addrIdx].replace(/.*(?:ط·آ§ط¸â€‍ط·آ¹ط¸â€ ط¸ث†ط·آ§ط¸â€  ط·آ¨ط·آ§ط¸â€‍ط·ع¾ط¸ظ¾ط·آµط¸ظ¹ط¸â€‍|ط·آ§ط¸â€‍ط·آ¹ط¸â€ ط¸ث†ط·آ§ط¸â€ )\s*\/?/g, ""));
    const tail = lines
      .slice(addrIdx + 1, addrIdx + 4)
      .filter((l) => !/^(?:0?1[0-2,5]\d{8})$/.test(l));
    if (tail.length) address = normalizeSpaces([address, ...tail].filter(Boolean).join(" "));
  } else {
    const arrowLines = lines.filter((l) => l.includes("ظ‹ع؛â€کث†") || l.includes("ط·آ¬ط¸ث†ط·آ§ط·آ±") || l.includes("ط·آ¨ط·آ¬ط¸ث†ط·آ§ط·آ±"));
    if (arrowLines.length) address = normalizeSpaces(arrowLines.join(" "));
  }

  function detectModelFromOrderText(tRaw) {
    const t = normalizeArabicDigits(String(tRaw || "")).toLowerCase();
    if (/(?:ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ |iphone)\s*17/.test(t) || /17\s*(?:pro|max|ط·آ¨ط·آ±ط¸ث†|ط¸â€¦ط·آ§ط¸ئ’ط·آ³)/.test(t)) return "17";
    if (/(?:ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ |iphone)\s*16/.test(t) || /16\s*(?:pro|max|ط·آ¨ط·آ±ط¸ث†|ط¸â€¦ط·آ§ط¸ئ’ط·آ³)/.test(t)) return "16";
    if (/(?:ط·آ§ط¸ظ¹ط¸ظ¾ط¸ث†ط¸â€ |iphone)\s*15/.test(t) || /15\s*(?:pro|max|ط·آ¨ط·آ±ط¸ث†|ط¸â€¦ط·آ§ط¸ئ’ط·آ³)/.test(t)) return "15";
    const d = detectModelDigitAny(t);
    return d || "";
  }

  const count = extractCount(textNoPhones);
  const models = extractNormalizedModels(textNoPhones, count);
  const modelDigit = detectModelFromOrderText(textNoPhones);
  const model = models[0] || (modelDigit ? `${modelDigit} Pro Max` : "");
  const colors = extractNormalizedColors(textDigits);
  const color = colors[0] || normalizeColorNameAny(textDigits);

  const nums = (textNoPhones.match(/\d{1,5}/g) || [])
    .map((x) => Number.parseInt(x, 10))
    .filter((n) => Number.isFinite(n));
  const discountMatch = textDigits.match(/ط·آ®ط·آµط¸â€¦\s*(\d{1,4})/);
  const discount = discountMatch ? Number.parseInt(discountMatch[1], 10) : 0;
  const shippingMatch = textDigits.match(/(\d{1,4})\s*(?:ط·آ´ط·آ­ط¸â€ |shipping)/i);
  const shipping = shippingMatch ? Number.parseInt(shippingMatch[1], 10) : 0;
  const price = pickLargestPrice(nums);
  const codTotal = Math.max(0, price - (Number.isFinite(discount) ? discount : 0) + (Number.isFinite(shipping) ? shipping : 0));

  const notesCandidates = lines.filter((l) => l.includes("ظ‹ع؛ع‘آ«") || l.includes("ط·آ§ط¸â€‍ط·آ§ط·آ³ط·ع¾ط¸â€‍ط·آ§ط¸â€¦") || l.includes("ط¸â€¦ط¸â€‍ط·آ­ط¸ث†ط·آ¸ط·آ©"));
  const notes = normalizeSpaces(notesCandidates.join(" "));

  return {
    name,
    governorate,
    phone,
    phones,
    address,
    model,
    color,
    count,
    ...(models.length ? { models } : {}),
    ...(colors.length ? { colors } : {}),
    price: price ? String(price) : "",
    discount: String(discount || 0),
    shipping: String(shipping || 0),
    cod_total: codTotal ? String(codTotal) : "",
    notes,
  };
}

function normalizeParsedOrder(obj) {
  const name = normalizeSpaces(obj?.name);
  const governorate = normalizeSpaces(obj?.governorate);
  const address = normalizeSpaces(obj?.address);
  const countN = Number.parseInt(normalizeArabicDigits(obj?.count), 10);
  const count = Number.isInteger(countN) && countN > 0 ? countN : 1;

  const modelsRaw = Array.isArray(obj?.models) ? obj.models : null;
  const models = modelsRaw ? modelsRaw.map(normalizeModelNameAny).filter(Boolean) : [];
  const finalModels = models.length ? models.slice(0, count) : [];
  while (finalModels.length && finalModels.length < count) finalModels.push(finalModels[0]);

  const model = normalizeModelNameAny(obj?.model) || (finalModels[0] || "");
  const colorsRaw = Array.isArray(obj?.colors) ? obj.colors : null;
  const colors = colorsRaw ? colorsRaw.map(normalizeColorNameAny).filter(Boolean) : [];
  const color = normalizeColorNameAny(obj?.color) || (colors[0] || "");
  const phone = normalizePhone(obj?.phone) || normalizePhone((obj?.phones && obj.phones[0]) || "");
  const phones = Array.from(
    new Set([phone, ...(Array.isArray(obj?.phones) ? obj.phones : [])].map(normalizePhone).filter(Boolean))
  );
  const finalColors = colors.length ? colors.slice(0, count) : [];

  const modelsForMap = finalModels.length ? finalModels : (model ? Array(count).fill(model) : []);
  let resolvedColors = [];
  for (let i = 0; i < count; i++) {
    const m = modelsForMap[i] || model;
    const cRaw = (i < finalColors.length && finalColors[i]) ? finalColors[i] : (color || "");
    const mapped = m ? normalizeColorForModel(m, cRaw) : normalizeColorNameAny(cRaw);
    resolvedColors.push(mapped || "");
  }
  const resolvedColor = (resolvedColors.find((x) => x) || (model ? normalizeColorForModel(model, color) : color) || "");
  if (resolvedColor) {
    resolvedColors = resolvedColors.map((x) => x || resolvedColor);
  }
  const shouldIncludeColors = count > 1 && resolvedColors.some((x) => x);

  const priceN = Number.parseInt(normalizeArabicDigits(obj?.price), 10);
  const discountN = Number.parseInt(normalizeArabicDigits(obj?.discount), 10);
  const shippingN = Number.parseInt(normalizeArabicDigits(obj?.shipping), 10);
  const price = Number.isFinite(priceN) ? priceN : 0;
  const discount = Number.isFinite(discountN) ? discountN : 0;
  const shipping = Number.isFinite(shippingN) ? shippingN : 0;
  const codTotal = Math.max(0, price - discount + shipping);

  const missing = [];
  if (!name) missing.push("name");
  if (!phone) missing.push("phone");
  if (!governorate) missing.push("governorate");
  if (!address) missing.push("address");
  if (!model) missing.push("model");
  if (!resolvedColor) missing.push("color");
  if (!price) missing.push("price");

  let confidence = 0;
  if (model) confidence += 0.28;
  if (resolvedColor) confidence += 0.22;
  if (phone) confidence += 0.18;
  if (name) confidence += 0.12;
  if (governorate) confidence += 0.08;
  if (address) confidence += 0.08;
  if (price) confidence += 0.04;
  confidence = Math.max(0, Math.min(1, Number(confidence.toFixed(2))));

  return {
    name,
    governorate,
    phone: phones[0] || "",
    ...(phones.length > 1 ? { phones } : {}),
    address,
    model,
    ...(finalModels.length ? { models: finalModels } : {}),
    color: resolvedColor || "",
    ...(shouldIncludeColors ? { colors: resolvedColors } : {}),
    count,
    price: price ? String(price) : "",
    discount: String(discount || 0),
    shipping: String(shipping || 0),
    cod_total: codTotal ? String(codTotal) : "",
    notes: normalizeSpaces(obj?.notes),
    confidence,
    missing_fields: missing,
    status: "shipped",
    created_at: new Date().toISOString(),
  };
}

function mergeParsedOrders(aiOrder, ruleOrder) {
  const ai = aiOrder || {};
  const rule = ruleOrder || {};

  const pickText = (...vals) => {
    for (const v of vals) {
      const s = normalizeSpaces(v);
      if (s) return s;
    }
    return "";
  };

  const pickArray = (...vals) => {
    for (const v of vals) {
      if (Array.isArray(v) && v.length) return v;
    }
    return [];
  };

  return {
    ...rule,
    ...ai,
    name: pickText(ai.name, rule.name),
    governorate: pickText(ai.governorate, rule.governorate),
    address: pickText(ai.address, rule.address),
    phone: pickText(ai.phone, rule.phone),
    phones: pickArray(ai.phones, rule.phones),
    model: pickText(ai.model, rule.model),
    models: pickArray(ai.models, rule.models),
    color: pickText(ai.color, rule.color),
    colors: pickArray(ai.colors, rule.colors),
    count: String(ai.count ?? rule.count ?? "1"),
    price: String(ai.price ?? rule.price ?? ""),
    shipping: String(ai.shipping ?? rule.shipping ?? "0"),
    discount: String(ai.discount ?? rule.discount ?? "0"),
    cod_total: String(ai.cod_total ?? rule.cod_total ?? ""),
    notes: pickText(ai.notes, rule.notes),
  };
}

app.post("/ai/command", async (req, res) => {
  try {
    const text = String(req.body?.text || "").trim();
    if (!text) {
      return res.status(400).json({ action: "unknown", message: "text is required" });
    }

    try {
      const raw = await generateWithFallbackModels(
        `${ROUTER_PROMPT}\n\nUser command: ${text}`
      );
      const parsed = tryParseJson(raw);
      if (!parsed) {
        return res.json(parseRuleBased(text));
      }
      return res.json(normalizeAction(parsed));
    } catch (aiError) {
      console.log("Gemini fallback to rule-based:", aiError?.message || aiError);
      return res.json(parseRuleBased(text));
    }
  } catch (error) {
    return res.status(500).json({
      action: "unknown",
      message: error?.message || "Server error",
    });
  }
});

const PARSE_CACHE_TTL_MS = 5 * 60 * 1000;
const parseOrdersCache = new Map(); // key -> { at:number, value:any }
function cacheKeyForText(text) {
  return crypto.createHash("sha256").update(String(text || "")).digest("hex");
}
function getCachedParse(text) {
  const key = cacheKeyForText(text);
  const entry = parseOrdersCache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.at > PARSE_CACHE_TTL_MS) {
    parseOrdersCache.delete(key);
    return null;
  }
  return entry.value;
}
function setCachedParse(text, value) {
  const key = cacheKeyForText(text);
  parseOrdersCache.set(key, { at: Date.now(), value });
}

app.post("/ai/parse_orders", async (req, res) => {
  try {
    const text = String(req.body?.text || "").trim();
    const strictAi = req.body?.strict_ai !== false;
    if (!text) {
      return res.status(400).json({ error: "text is required" });
    }

    const cached = getCachedParse(text);
    if (cached) return res.json(cached);
    const blocks = splitWhatsAppBlocks(text);
    const ruleParsedByBlock = blocks.map(parseWhatsAppBlockRuleBased);

    let aiFailureReason = "";
    try {
      const prompt = `
You extract iPhone order data from Egyptian Arabic WhatsApp messages.
Return ONLY valid JSON array. No markdown. No extra text.
Each output item is one order.
Preserve input order and include source_index (0-based) for every order.

Normalization:
- model in {"15 Pro Max","16 Pro Max","17 Pro Max"}
- color in {"سلفر","اسود","ازرق","دهبي","برتقالي","كحلي","تيتانيوم"}
- count integer >= 1
- phone Egyptian mobile 11 digits starts with 01
- cod_total = price - discount + shipping
- If multi-device: set models[] and colors[] (length <= count)

Synonyms:
- اورنج/اورانج/برتقاني => برتقالي
- فضي/سيلفر/ابيض => سلفر
- ازرق/كحلي same family (choose valid model color)

Governorate:
- Use governorate only (ط§ظ„ظ‚ط§ظ‡ط±ط©/ط§ظ„ط¬ظٹط²ط©/ط§ظ„ظ‚ظ„ظٹظˆط¨ظٹط©...) not district.

Output schema:
{ "source_index","name","governorate","address","phone","phones","model","models","color","colors","count","price","shipping","discount","cod_total","notes" }

Input blocks:
${JSON.stringify(blocks.map((b, i) => ({ source_index: i, text: b })))}
      `.trim();

      const raw = await generateWithFallbackModels(prompt);
      const arr = tryParseJsonArray(raw);
      if (arr && arr.length) {
        const normalized = arr
          .map((o, idx) => {
            const sourceIndexRaw = Number.parseInt(o?.source_index, 10);
            const sourceIndex = Number.isInteger(sourceIndexRaw) ? sourceIndexRaw : idx;
            const ruleOrder = sourceIndex >= 0 && sourceIndex < ruleParsedByBlock.length ? ruleParsedByBlock[sourceIndex] : null;
            return {
              source_index: sourceIndex,
              order: normalizeParsedOrder(mergeParsedOrders(o, ruleOrder)),
            };
          })
          .sort((a, b) => a.source_index - b.source_index)
          .map((x) => x.order)
          .filter((o) => o.name || o.phone || o.address);
        res.set("x-parse-mode", "ai");
        setCachedParse(text, normalized);
        return res.json(normalized);
      }
      aiFailureReason = "ai_empty_or_invalid_json";
    } catch (aiError) {
      aiFailureReason = aiError?.message || String(aiError || "ai_error");
      console.log("Gemini parse_orders error:", aiFailureReason);
    }

    const ruleParsed = ruleParsedByBlock
      .map(normalizeParsedOrder)
      .filter((o) => o.name || o.phone || o.address);

    if (strictAi) {
      return res.status(503).json({
        error: "AI_PARSE_UNAVAILABLE",
        message: "Gemini parse_orders failed; rule fallback disabled in strict mode",
        details: aiFailureReason,
        fallback_preview_count: ruleParsed.length,
      });
    }

    res.set("x-parse-mode", "rule");
    setCachedParse(text, ruleParsed);
    return res.json(ruleParsed);
  } catch (error) {
    return res.status(500).json({
      error: error?.message || "Server error",
    });
  }
});

app.post("/ai/match_delivery", async (req, res) => {
  try {
    const row = req.body?.row || {};
    const candidates = Array.isArray(req.body?.candidates) ? req.body.candidates : [];
    if (!candidates.length) {
      return res.json({ match_candidate_id: -1, confidence: 0, reason: "no_candidates" });
    }

    const compact = candidates.slice(0, 8).map((c) => ({
      candidate_id: Number(c?.candidate_id),
      name: normalizeSpaces(c?.name),
      governorate: normalizeSpaces(c?.governorate),
      phone: normalizePhone(c?.phone),
      phones: Array.isArray(c?.phones) ? c.phones.map(normalizePhone).filter(Boolean) : [],
      address: normalizeSpaces(c?.address),
      cod_total: String(c?.cod_total ?? ""),
      price: String(c?.price ?? ""),
      shipping: String(c?.shipping ?? ""),
      discount: String(c?.discount ?? ""),
      count: String(c?.count ?? "1"),
      created_at: String(c?.created_at ?? ""),
      status: String(c?.status ?? ""),
    }));

    const prompt = `
You match ONE delivery-sheet row to one of candidate orders.
Return ONLY JSON object, no markdown.

Output JSON:
{ "match_candidate_id": number, "confidence": number, "reason": string }

Rules:
- Choose match_candidate_id from provided candidate_id values only.
- If uncertain, return -1.
- confidence must be between 0 and 1.
- Prefer name+governorate+amount consistency.
- COD amount may differ due to fees/discounts by up to moderate tolerance.
- count can indicate multi-device orders (e.g. 2 devices).

Sheet row:
${JSON.stringify({
  receiver_name: normalizeSpaces(row?.receiver_name),
  destination: normalizeSpaces(row?.destination),
  cod_amount: String(row?.cod_amount ?? ""),
  cod_service_fee: String(row?.cod_service_fee ?? ""),
  shipping_fee: String(row?.shipping_fee ?? ""),
})}

Candidates:
${JSON.stringify(compact)}
    `.trim();

    const raw = await generateWithFallbackModels(prompt);
    const parsed = tryParseJson(raw) || {};
    const picked = Number(parsed?.match_candidate_id);
    const confidence = Number(parsed?.confidence);
    const validIds = new Set(compact.map((c) => c.candidate_id).filter((x) => Number.isInteger(x)));
    const safeId = Number.isInteger(picked) && validIds.has(picked) ? picked : -1;
    const safeConfidence = Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : 0;

    return res.json({
      match_candidate_id: safeId,
      confidence: Number(safeConfidence.toFixed(2)),
      reason: normalizeSpaces(parsed?.reason),
    });
  } catch (error) {
    return res.json({ match_candidate_id: -1, confidence: 0, reason: "fallback_no_match" });
  }
});

app.post("/ai/resolve_unmatched_row", async (req, res) => {
  try {
    const row = req.body?.row || {};
    const sheetName = normalizeSpaces(req.body?.sheetName || row?.receiver_name || "");
    const sheetGov = normalizeSpaces(req.body?.sheetGov || row?.destination || "");
    const sheetAmountRaw = req.body?.sheetAmount ?? row?.cod_amount ?? "";
    const sheetAmount = Number.parseFloat(String(sheetAmountRaw));

    const candidates = Array.isArray(req.body?.candidates) ? req.body.candidates : [];
    if (!candidates.length) {
      return res.json({ status: "manual" });
    }

    const compact = candidates.slice(0, 6).map((c) => ({
      name: normalizeSpaces(c?.name),
      governorate: normalizeSpaces(c?.governorate),
      phone: normalizePhone(c?.phone),
      address: normalizeSpaces(c?.address),
      last_model: normalizeModelNameAny(c?.last_model),
      last_color: normalizeColorNameAny(c?.last_color),
      models_summary: normalizeSpaces(c?.models_summary),
      colors_summary: normalizeSpaces(c?.colors_summary),
      score: String(c?.score ?? ""),
    }));

    const prompt = `
أنت مساعد ذكي لإدارة مطابقة شحنات إكسيل مع قاعدة بيانات العملاء.
بيانات الشحنة الحالية من الشيت:

الاسم: ${sheetName}

المحافظة: ${sheetGov}

مبلغ التحصيل (Cod Amount): ${Number.isFinite(sheetAmount) ? sheetAmount : String(sheetAmountRaw)}

قائمة العملاء المحتملين من قاعدة البيانات:
${JSON.stringify(compact, null, 2)}

المطلوب:

ابحث عن أقرب تطابق للاسم والمحافظة.

استخدم "مبلغ التحصيل" كدليل إضافي لتوقع الموديل (مثلاً: 5500 يعني 15 Pro Max، 6000 يعني 16 Pro Max، 6500 يعني 17 Pro Max، أو مضاعفاتهم).

إذا وجدت العميل المناسب وتأكدت منه، أرجع هذا الـ JSON فقط:
{"status": "matched", "model": "اسم الموديل المستنتج", "color": "لون العميل المفضل من الداتا"}

إذا لم تجد تطابق أو كان الاسم مختلفاً تماماً، أرجع:
{"status": "manual"}

أرجع JSON فقط بدون أي نصوص أخرى أنا علامات Markdown.
    `.trim();

    const raw = await generateWithFallbackModels(prompt);
    const cleaned = String(raw || "")
      .replace(/```json/gi, "")
      .replace(/```/g, "")
      .trim();

    const parsed = tryParseJson(cleaned) || tryParseJson(raw) || {};
    const statusRaw = String(parsed?.status || "").toLowerCase().trim();

    if (statusRaw !== "matched") {
      return res.json({ status: "manual" });
    }

    const model = normalizeModelNameAny(parsed?.model);
    const color = model
      ? normalizeColorForModel(model, parsed?.color)
      : normalizeColorNameAny(parsed?.color);
    const confidence = Number(parsed?.confidence);
    const safeConfidence = Number.isFinite(confidence) ? Math.max(0, Math.min(1, confidence)) : 0;

    if (!model || !color) {
      return res.json({ status: "manual" });
    }

    return res.json({
      status: "matched",
      model,
      color,
      confidence: Number(safeConfidence.toFixed(2)),
    });
  } catch (error) {
    return res.status(500).json({
      error: "resolve_unmatched_row_failed",
      message: error?.message || "Server error",
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI proxy running on http://localhost:${PORT}`);
});
