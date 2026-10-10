
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
      message: "Method not allowed"
    });
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !serviceKey) {
    return res.status(500).json({
      valid: false,
      message: "Server configuration missing"
    });
  }

  const key =
    typeof req.body?.key === "string"
      ? req.body.key.trim().toUpperCase()
      : "";

  if (!key || key.length > 100) {
    return res.status(400).json({
      valid: false,
      message: "กรุณากรอก License Key ให้ถูกต้อง"
    });
  }


const deviceId =
  typeof req.body?.deviceId === "string"
    ? req.body.deviceId.trim()
    : "";

console.log("Device ID received:", JSON.stringify(deviceId));
  

if (!deviceId) {
  console.log("Device ID validation failed: missing or not a string");
  return res.status(400).json({
    valid: false,
    message: "ไม่พบ Device ID"
  });
}

if (deviceId.length > 200) {
  console.log("Device ID validation failed: too long", deviceId.length);
  return res.status(400).json({
    valid: false,
    message: "Device ID ยาวเกินกำหนด"
  });
}

if (!/^[a-zA-Z0-9-]+$/.test(deviceId)) {
  console.log("Device ID validation failed: invalid characters");
  return res.status(400).json({
    valid: false,
    message: "รูปแบบ Device ID ไม่ถูกต้อง"
  });
}


  
  try {
    const forwarded = req.headers["x-forwarded-for"];
    const ip = typeof forwarded === "string"
      ? forwarded.split(",")[0].trim()
      : "unknown";

    const response = await fetch(  
`${supabaseUrl}/rest/v1/rpc/verify_license_device`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`
        },    
body: JSON.stringify({
  p_key: key,
  p_device_id: deviceId,
  p_ip: ip,
})

      }
    );

    if (!response.ok) {
      console.error("License redemption request failed:", response.status);
      return res.status(500).json({
        valid: false,
        message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้"
      });
    }

    const result = await response.json();
    return res.status(200).json(result);
  } catch (error) {
    console.error("License verification failed:", error.message);
    return res.status(500).json({
      valid: false,
      message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้"
    });
  }
};
