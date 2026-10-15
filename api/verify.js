
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

    // ตรวจสอบ License และ Device ID ผ่าน RPC เดิม
    const verifyResponse = await fetch(
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

    if (!verifyResponse.ok) {
      console.error(
        "License verification RPC failed:",
        verifyResponse.status
      );

      return res.status(500).json({
        valid: false,
        message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้",
      });
    }

    const result = await verifyResponse.json();

    // รองรับ RPC ที่คืนค่าเป็น Object หรือ Array ที่มี Object เดียว
    const license = Array.isArray(result) ? result[0] : result;

    if (!license || license.valid !== true) {
      return res.status(200).json({
        valid: false,
        message: license?.message || "คีย์ไม่ถูกต้อง",
      });
    }

    // ต้องให้ RPC คืน filePath ซึ่งเป็น path จริงภายใน bucket
    const filePath =
      typeof license.filePath === "string"
        ? license.filePath.trim()
        : "";

    const fileName =
      typeof license.fileName === "string"
        ? license.fileName.trim()
        : "";

    if (!filePath || !fileName) {
      console.error(
        "License RPC response is missing filePath or fileName"
      );

      return res.status(500).json({
        valid: false,
        message: "ข้อมูลไฟล์ของ License ไม่ครบ",
      });
    }

    // สร้าง Signed URL อายุ 5 นาทีจาก Supabase Storage
    const signedResponse = await fetch(
      `${supabaseUrl}/storage/v1/object/sign/installer-files/${filePath
        .split("/")
        .map(encodeURIComponent)
        .join("/")}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          expiresIn: 300,
        }),
      }
    );

    if (!signedResponse.ok) {
      console.error(
        "Signed URL creation failed:",
        signedResponse.status
      );

      return res.status(500).json({
        valid: false,
        message: "สร้าง URL ดาวน์โหลดไม่สำเร็จ",
      });
    }

    const signedData = await signedResponse.json();

    const signedUrl =
      typeof signedData.signedURL === "string"
        ? signedData.signedURL
        : typeof signedData.signedUrl === "string"
          ? signedData.signedUrl
          : "";

    if (!signedUrl) {
      console.error("Supabase did not return a signed URL");

      return res.status(500).json({
        valid: false,
        message: "เซิร์ฟเวอร์ไม่ได้รับ URL ดาวน์โหลด",
      });
    }

    // Supabase อาจส่ง signedURL เป็น path ที่ขึ้นต้นด้วย /
    const downloadUrl = new URL(signedUrl, supabaseUrl).toString();

    return res.status(200).json({
      valid: true,
      downloadUrl,
      fileName,
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
