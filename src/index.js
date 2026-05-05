const express = require("express");
const app = express();
const PORT = process.env.PORT || 8080;
const SERVICE_VERSION = process.env.IMAGE_TAG || "unknown";
const ENV = process.env.APP_ENV || "development";

app.get("/", (req, res) => {
  res.json({
    service: "my-service",
    status: "running",
    environment: ENV,
    version: SERVICE_VERSION,
    timestamp: new Date().toISOString(),
  });
});

app.get("/health/live", (req, res) => {
  res.status(200).json({ status: "alive" });
});

app.get("/health/ready", (req, res) => {
  res.status(200).json({ status: "ready" });
});

app.listen(PORT, () => {
  console.log(`[my-service] Running on port ${PORT}`);
  console.log(`[my-service] ENV=${ENV} | VERSION=${SERVICE_VERSION}`);
});