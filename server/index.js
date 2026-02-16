const express = require("express");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 3000;

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

app.use((req, res, next) => {
  console.log(req.method, req.url);
  next();
});

const GOVERNORATES = [
  "القاهرة",
  "الجيزة",
  "الإسكندرية",
  "القليوبية",
  "الشرقية",
  "الغربية",
  "المنوفية",
  "الدقهلية",
  "الفيوم",
  "البحيرة",
  "دمياط",
  "سوهاج",
  "أسيوط",
  "قنا",
  "الأقصر",
  "أسوان",
  "المنيا",
  "بني سويف",
  "بورسعيد",
  "السويس",
  "الإسماعيلية",
  "مطروح",
  "الوادي الجديد",
  "شمال سيناء",
  "جنوب سيناء",
  "كفر الشيخ",
];

function normalizeArabicSpaces(s) {
  return s.replace(/\s+/g, " ").trim();
}

function extractGovernorate(text) {
  const found = GOVERNORATES.find((g) => text.includes(g));
  return found || null;
}

function detectModel(text) {
  if (/(?:\b|^)(?:17|١٧)(?:\b|$)/.test(text)) return "17";
  if (/(?:\b|^)(?:16|١٦)(?:\b|$)/.test(text)) return "16";
  if (/(?:\b|^)(?:15|١٥)(?:\b|$)/.test(text)) return "15";
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
    "بنفسجي",
    "وردي",
    "اخضر",
    "أخضر",
  ];
  const found = colors.find((c) => text.includes(c));
  return found ? found.replace("أ", "ا") : null;
}

function detectCount(text) {
  const m = text.match(/(\d+)/);
  if (!m) return null;
  const n = Number.parseInt(m[1], 10);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function extractNameAfterKeywords(text, keywords) {
  for (const kw of keywords) {
    const idx = text.indexOf(kw);
    if (idx === -1) continue;
    let rest = text.slice(idx + kw.length);
    rest = rest.replace(/^(?:\s+|:|-|،)+/g, "");
    const gov = extractGovernorate(rest);
    if (gov) {
      rest = rest.replace(gov, "").trim();
    }
    if (rest.length > 0) return normalizeArabicSpaces(rest);
  }
  return "";
}

function parseCommand(textRaw) {
  const text = normalizeArabicSpaces((textRaw || "").toString());
  if (!text) {
    return { action: "unknown", message: "اكتب أمر أولًا" };
  }

  const lower = text.toLowerCase();

  if (
    lower.includes("check stock") ||
    lower.includes("stock") ||
    text.includes("المخزن") ||
    text.includes("الجرد") ||
    text.includes("رصيد")
  ) {
    return { action: "check_stock" };
  }

  if (
    text.includes("امسح") ||
    text.includes("احذف") ||
    text.includes("حذف")
  ) {
    const governorate = extractGovernorate(text);
    const name =
      extractNameAfterKeywords(text, ["اوردر", "أوردر", "طلب", "عميل"]) ||
      text.replace(/.*(?:امسح|احذف|حذف)/, "").trim();
    return {
      action: "delete_order",
      name: normalizeArabicSpaces(name),
      ...(governorate ? { governorate } : {}),
    };
  }

  if (
    text.includes("الغي") ||
    text.includes("إلغي") ||
    text.includes("الغي") ||
    text.includes("cancel")
  ) {
    const governorate = extractGovernorate(text);
    const name =
      extractNameAfterKeywords(text, ["اوردر", "أوردر", "طلب", "عميل"]) ||
      text.replace(/.*(?:الغي|إلغي|الغي|cancel)/i, "").trim();
    return {
      action: "cancel_order",
      name: normalizeArabicSpaces(name),
      ...(governorate ? { governorate } : {}),
    };
  }

  if (
    text.includes("زود") ||
    text.includes("ضيف") ||
    text.includes("اضف") ||
    text.includes("أضف") ||
    text.includes("توريد") ||
    lower.includes("add stock")
  ) {
    const model = detectModel(text);
    const color = detectColor(text);
    const count = detectCount(text) || 1;
    if (!model || !color) {
      return {
        action: "unknown",
        message: "حدد الموديل واللون. مثال: زود 3 ايفون 15 ازرق",
      };
    }
    return {
      action: "add_stock",
      model,
      color,
      count,
    };
  }

  return {
    action: "unknown",
    message: "الأمر غير واضح. جرب: امسح أوردر محمد / زود 2 ايفون 16 سلفر / اعرض المخزن",
  };
}

app.post("/ai/command", async (req, res) => {
  try {
    const text = (req.body?.text || "").toString();
    const action = parseCommand(text);
    return res.json(action);
  } catch (error) {
    return res.status(500).json({ action: "unknown", message: error.message || "Server error" });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI proxy running on http://localhost:${PORT}`);
});
