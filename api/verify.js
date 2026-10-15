
module.exports = async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST, OPTIONS");
    return res.status(405).json({
      valid: false,
      message: "Method not allowed",
    });
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceKey) {
    return res.status(500).json({
      valid: false,
      message: "Server configuration missing",
    });
  }

  const key =
    typeof req.body?.key === "string"
      ? req.body.key.trim().toUpperCase()
      : "";

  const deviceId =
    typeof req.body?.deviceId === "string"
      ? req.body.deviceId.trim()
      : "";

  if (!key || key.length > 100) {
    return res.status(400).json({
      valid: false,
      message: "กรุณากรอก License Key ให้ถูกต้อง",
    });
  }

  if (
    !deviceId ||
    deviceId.length > 200 ||
    !/^[a-zA-Z0-9-]+$/.test(deviceId)
  ) {
    return res.status(400).json({
      valid: false,
      message: "Device ID ไม่ถูกต้อง",
    });
  }

  try {
    const forwarded = req.headers["x-forwarded-for"];
    const ip =
      typeof forwarded === "string"
        ? forwarded.split(",")[0].trim()
        : "unknown";

    const rpcResponse = await fetch(
      `${supabaseUrl}/rest/v1/rpc/verify_license_device`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          p_key: key,
          p_device_id: deviceId,
          p_ip: ip,
        }),
      }
    );

    if (!rpcResponse.ok) {
      console.error(
        "License RPC failed:",
        rpcResponse.status
      );

      return res.status(500).json({
        valid: false,
        message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้",
      });
    }

    const rawResult = await rpcResponse.json();
    const result = Array.isArray(rawResult)
      ? rawResult[0]
      : rawResult;

    if (!result || result.valid !== true) {
      return res.status(200).json({
        valid: false,
        message: result?.message || "คีย์ไม่ถูกต้อง",
      });
    }

    const fileName =
      typeof result.fileName === "string"
        ? result.fileName.trim()
        : "";

    const downloadUrl =
      typeof result.downloadUrl === "string"
        ? result.downloadUrl.trim()
        : "";

    if (!fileName || !downloadUrl) {
      console.error("License RPC missing file information", {
        fields: Object.keys(result),
        hasFileName: Boolean(fileName),
        hasDownloadUrl: Boolean(downloadUrl),
      });

      return res.status(500).json({
        valid: false,
        message: "ข้อมูลไฟล์ของ License ไม่ครบ",
      });
    }

    let parsedUrl;

    try {
      parsedUrl = new URL(downloadUrl);
    } catch {
      console.error("License RPC returned an invalid download URL");

      return res.status(500).json({
        valid: false,
        message: "URL ดาวน์โหลดจากฐานข้อมูลไม่ถูกต้อง",
      });
    }

    const allowedHosts = new Set([
      "utvmdjprzzteltajqwzk.supabase.co",
      "github.com",
    ]);

    if (
      parsedUrl.protocol !== "https:" ||
      !allowedHosts.has(parsedUrl.hostname) ||
      parsedUrl.username ||
      parsedUrl.password
    ) {
      console.error("Download URL failed validation", {
        protocol: parsedUrl.protocol,
        hostname: parsedUrl.hostname,
      });

      return res.status(500).json({
        valid: false,
        message: "URL ดาวน์โหลดไม่ตรงกับแหล่งไฟล์ที่อนุญาต",
      });
    }

    return res.status(200).json({
      valid: true,
      message: result.message || "ตรวจสอบคีย์สำเร็จ",
      fileName,
      downloadUrl,
      useNumber: result.useNumber,
    });
  } catch (error) {
    console.error(
      "License verification failed:",
      error instanceof Error ? error.message : "Unknown error"
    );

    return res.status(500).json({
      valid: false,
      message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้",
    });
  }
};
