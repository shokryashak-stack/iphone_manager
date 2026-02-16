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

const toolSchema = {
  type: "function",
  name: "route_action",
  description: "Route Arabic inventory/order command to one strict action object.",
  parameters: {
    type: "object",
    additionalProperties: false,
    properties: {
      action: {
        type: "string",
        enum: ["delete_order", "cancel_order", "add_stock", "check_stock", "unknown"],
      },
      name: { type: "string" },
      governorate: { type: "string" },
      model: { type: "string", enum: ["15", "16", "17"] },
      color: { type: "string" },
      count: { type: "integer", minimum: 1 },
      message: { type: "string" },
    },
    required: ["action"],
  },
};

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
            content:
              "You are an inventory/order assistant. Always call the function and do not output free text.",
          },
          { role: "user", content: text },
        ],
        tools: [toolSchema],
        tool_choice: { type: "function", name: "route_action" },
      }),
    });

    if (!response.ok) {
      const errText = await response.text();
      return res.status(502).json({ action: "unknown", message: `OpenAI error: ${errText}` });
    }

    const data = await response.json();
    const functionCall = (data.output || []).find(
      (item) => item.type === "function_call" && item.name === "route_action"
    );

    if (!functionCall?.arguments) {
      return res.json({ action: "unknown", message: "No function call arguments returned" });
    }

    let parsed;
    try {
      parsed = JSON.parse(functionCall.arguments);
    } catch {
      return res.json({ action: "unknown", message: "Invalid function arguments JSON" });
    }

    return res.json(normalizeAction(parsed));
  } catch (error) {
    return res.status(500).json({ action: "unknown", message: error.message || "Server error" });
  }
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`AI proxy running on http://localhost:${PORT}`);
});
