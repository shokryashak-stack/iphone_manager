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
    endpoints: ["/health", "/ai/command", "/ai/parse_orders"],
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
  if (/(?:^|\s)(17|١٧)(?:\s|$)/.test(text)) return "17";
  if (/(?:^|\s)(16|١٦)(?:\s|$)/.test(text)) return "16";
  if (/(?:^|\s)(15|١٥)(?:\s|$)/.test(text)) return "15";
  return null;
}

function detectColor(text) {
  const colors = [
    "سلفر",
    "فضي",
    "اسود",
    "أسود",
    "ازرق",
    "أزرق",
    "دهبي",
    "ذهبي",
    "برتقالي",
    "تيتانيوم",
    "كحلي",
    "ابيض",
    "أبيض",
  ];
  const found = colors.find((c) => text.includes(c));
  return found ? found.replace("أ", "ا") : null;
}

function detectCount(text) {
  const m = text.match(/(\d+)/);
  if (!m) return 1;
  const n = Number.parseInt(m[1], 10);
  return Number.isInteger(n) && n > 0 ? n : 1;
}

function parseRuleBased(textRaw) {
  const text = normalizeSpaces(textRaw);
  if (!text) return { action: "unknown", message: "اكتب أمر أولًا" };

  const lower = text.toLowerCase();
  if (text.includes("المخزن") || text.includes("الجرد") || lower.includes("check stock")) {
    return { action: "check_stock" };
  }

  if (text.includes("امسح") || text.includes("احذف") || text.includes("حذف") || text.includes("شيل")) {
    const name = normalizeSpaces(
      text
        .replace(/.*(اوردر|أوردر|طلب|عميل)/, "")
        .replace(/.*(امسح|احذف|حذف|شيل)/, "")
    );
    return { action: "delete_order", name };
  }

  if (text.includes("الغي") || text.includes("إلغي") || lower.includes("cancel")) {
    const name = normalizeSpaces(
      text
        .replace(/.*(اوردر|أوردر|طلب|عميل)/, "")
        .replace(/.*(الغي|إلغي|cancel)/i, "")
    );
    return { action: "cancel_order", name };
  }

  if (
    text.includes("زود") ||
    text.includes("ضيف") ||
    text.includes("اضف") ||
    text.includes("أضف") ||
    lower.includes("add stock")
  ) {
    const model = detectModel(text);
    const color = detectColor(text);
    if (!model || !color) {
      return { action: "unknown", message: "حدد الموديل واللون. مثال: زود 2 ايفون 16 سلفر" };
    }
    return { action: "add_stock", model, color, count: detectCount(text) };
  }

  return {
    action: "unknown",
    message: "الأمر غير واضح. مثال: امسح أوردر محمد أو زود 2 ايفون 16 سلفر",
  };
}

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

function normalizeNewlines(s) {
  return String(s || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

function stripDiacritics(s) {
  return String(s || "").replace(/[\u064B-\u065F\u0670\u06D6-\u06ED]/g, "");
}

function normalizeArabicDigits(s) {
  const map = {
    "٠": "0",
    "١": "1",
    "٢": "2",
    "٣": "3",
    "٤": "4",
    "٥": "5",
    "٦": "6",
    "٧": "7",
    "٨": "8",
    "٩": "9",
  };
  return String(s || "").replace(/[٠-٩]/g, (d) => map[d] || d);
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

function normalizeColorNameAny(colorRaw) {
  const s = normalizeSpaces(stripDiacritics(String(colorRaw || ""))).toLowerCase();
  if (!s) return "";
  if (s.includes("سلفر") || s.includes("فضي") || s.includes("فضه") || s.includes("silver") || s.includes("ابيض") || s.includes("أبيض") || s.includes("white")) return "سلفر";
  if (s.includes("اسود") || s.includes("أسود") || s.includes("بلاك") || s.includes("black")) return "اسود";
  if (s.includes("ازرق") || s.includes("أزرق") || s.includes("blue")) return "ازرق";
  if (s.includes("دهبي") || s.includes("ذهبي") || s.includes("جولد") || s.includes("gold")) return "دهبي";
  if (s.includes("برتقالي") || s.includes("اورنج") || s.includes("اورانج") || s.includes("أورنج") || s.includes("orange")) return "برتقالي";
  if (s.includes("كحلي") || s.includes("navy")) return "كحلي";
  if (s.includes("تيتانيوم") || s.includes("طبيعي") || s.includes("ناتشورال") || s.includes("natural")) return "تيتانيوم";
  return "";
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
  const parts = text
    .split(/(?=^\s*\[\d{1,2}\/\d{1,2},[^\]]+\]\s)/m)
    .map((p) => p.trim())
    .filter(Boolean);
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

  const text = stripDiacritics(cleaned);
  const textDigits = normalizeArabicDigits(text);
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
  const nameLine = lines.find((l) => /اسم العميل\s*\/|الاسم\s*/.test(l));
  if (nameLine) {
    name = normalizeSpaces(nameLine.replace(/.*(?:اسم العميل|الاسم)\s*\/?/g, ""));
  } else if (lines.length) {
    name = normalizeSpaces(lines[0].replace(/^\s*[:\\-]+/, ""));
  }

  let governorate = "";
  const govLine = lines.find((l) => /المحافظه\s*\/|المحافظة\s*\/|محافظه|محافظة/.test(l));
  if (govLine) {
    governorate = normalizeSpaces(govLine.replace(/.*(?:المحافظه|المحافظة|محافظه|محافظة)\s*\/?/g, ""));
  } else {
    const possibleGov = lines.find((l) => l.length <= 20 && !/ايفون|iphone|pro|max|لون|شحن|خصم|\d/.test(l));
    if (possibleGov) governorate = possibleGov;
  }

  let address = "";
  const addrIdx = lines.findIndex((l) => /العنوان بالتفصيل\s*\/|العنوان\s*/.test(l));
  if (addrIdx !== -1) {
    address = normalizeSpaces(lines[addrIdx].replace(/.*(?:العنوان بالتفصيل|العنوان)\s*\/?/g, ""));
    const tail = lines
      .slice(addrIdx + 1, addrIdx + 4)
      .filter((l) => !/^(?:0?1[0-2,5]\d{8})$/.test(l));
    if (tail.length) address = normalizeSpaces([address, ...tail].filter(Boolean).join(" "));
  } else {
    const arrowLines = lines.filter((l) => l.includes("👈") || l.includes("جوار") || l.includes("بجوار"));
    if (arrowLines.length) address = normalizeSpaces(arrowLines.join(" "));
  }

  function detectModelFromOrderText(tRaw) {
    const t = normalizeArabicDigits(String(tRaw || "")).toLowerCase();
    if (/(?:ايفون|iphone)\s*17/.test(t) || /17\s*(?:pro|max|برو|ماكس)/.test(t)) return "17";
    if (/(?:ايفون|iphone)\s*16/.test(t) || /16\s*(?:pro|max|برو|ماكس)/.test(t)) return "16";
    if (/(?:ايفون|iphone)\s*15/.test(t) || /15\s*(?:pro|max|برو|ماكس)/.test(t)) return "15";
    const d = detectModelDigitAny(t);
    return d || "";
  }

  const modelDigit = detectModelFromOrderText(textNoPhones);
  const model = modelDigit ? `${modelDigit} Pro Max` : "";
  const color = normalizeColorNameAny(textDigits);

  const nums = (textNoPhones.match(/\d{1,5}/g) || [])
    .map((x) => Number.parseInt(x, 10))
    .filter((n) => Number.isFinite(n));
  const discountMatch = textDigits.match(/خصم\s*(\d{1,4})/);
  const discount = discountMatch ? Number.parseInt(discountMatch[1], 10) : 0;
  const shippingMatch = textDigits.match(/(\d{1,4})\s*(?:شحن|shipping)/i);
  const shipping = shippingMatch ? Number.parseInt(shippingMatch[1], 10) : 0;
  const price = pickLargestPrice(nums);
  const codTotal = Math.max(0, price - (Number.isFinite(discount) ? discount : 0) + (Number.isFinite(shipping) ? shipping : 0));

  const notesCandidates = lines.filter((l) => l.includes("🚫") || l.includes("الاستلام") || l.includes("ملحوظة"));
  const notes = normalizeSpaces(notesCandidates.join(" "));

  return {
    name,
    governorate,
    phone,
    phones,
    address,
    model,
    color,
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
  const model = normalizeModelNameAny(obj?.model);
  const color = normalizeColorNameAny(obj?.color);
  const phone = normalizePhone(obj?.phone) || normalizePhone((obj?.phones && obj.phones[0]) || "");
  const phones = Array.from(
    new Set([phone, ...(Array.isArray(obj?.phones) ? obj.phones : [])].map(normalizePhone).filter(Boolean))
  );

  const priceN = Number.parseInt(normalizeArabicDigits(obj?.price), 10);
  const discountN = Number.parseInt(normalizeArabicDigits(obj?.discount), 10);
  const shippingN = Number.parseInt(normalizeArabicDigits(obj?.shipping), 10);
  const price = Number.isFinite(priceN) ? priceN : 0;
  const discount = Number.isFinite(discountN) ? discountN : 0;
  const shipping = Number.isFinite(shippingN) ? shippingN : 0;
  const codTotal = Math.max(0, price - discount + shipping);

  return {
    name,
    governorate,
    phone: phones[0] || "",
    ...(phones.length > 1 ? { phones } : {}),
    address,
    model,
    color,
    price: price ? String(price) : "",
    discount: String(discount || 0),
    shipping: String(shipping || 0),
    cod_total: codTotal ? String(codTotal) : "",
    notes: normalizeSpaces(obj?.notes),
    status: "shipped",
    created_at: new Date().toISOString(),
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

app.post("/ai/parse_orders", async (req, res) => {
  try {
    const text = String(req.body?.text || "").trim();
    if (!text) {
      return res.status(400).json({ error: "text is required" });
    }

    // If we have Gemini configured, let it do extraction; otherwise fallback to rule-based parsing.
    try {
      const prompt = `
You extract iPhone order data from Egyptian Arabic WhatsApp messages.
Return ONLY valid JSON Array, no markdown, no explanations.
Each array item is ONE order.

Normalization rules (very important):
- model MUST be exactly one of: "15 Pro Max", "16 Pro Max", "17 Pro Max"
- color MUST be exactly one of: "سلفر","اسود","ازرق","دهبي","برتقالي","كحلي","تيتانيوم"
- price, shipping, discount are integers as strings (no currency symbols)
- phone should be an Egyptian mobile number (11 digits starting with 01) without spaces or +20
- If there are multiple phones, return "phones" as array of normalized phones, and set "phone" as the first.
- cod_total = price - discount + shipping

Fields to output per order:
{ "name","governorate","address","phone","phones","model","color","price","shipping","discount","cod_total","notes" }

Input WhatsApp text:
${text}
      `.trim();

      const raw = await generateWithFallbackModels(prompt);
      const arr = tryParseJsonArray(raw);
      if (arr && arr.length) {
        const normalized = arr.map(normalizeParsedOrder).filter((o) => o.name || o.phone || o.address);
        return res.json(normalized);
      }
    } catch (aiError) {
      console.log("Gemini parse_orders fallback to rule-based:", aiError?.message || aiError);
    }

    const blocks = splitWhatsAppBlocks(text);
    const ruleParsed = blocks
      .map(parseWhatsAppBlockRuleBased)
      .map(normalizeParsedOrder)
      .filter((o) => o.name || o.phone || o.address);

    return res.json(ruleParsed);
  } catch (error) {
    return res.status(500).json({
      error: error?.message || "Server error",
    });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI proxy running on http://localhost:${PORT}`);
});
