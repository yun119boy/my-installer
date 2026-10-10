
export default async function handler(req, res) {
  res.setHeader("Cache-Control", "no-store");

  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
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

  const keyCode =
    typeof req.body?.key === "string"
      ? req.body.key.trim().toUpperCase()
      : "";

  if (!keyCode || keyCode.length > 100) {
    return res.status(400).json({
      valid: false,
      message: "กรุณากรอก License Key ให้ถูกต้อง"
    });
  }

  try {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/keys?key_code=eq.${encodeURIComponent(keyCode)}&select=id,key_code,status,file_id,first_ip,first_used_at,files(name,storage_url)`,
      {
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`
        }
      }
    );

    if (!response.ok) {
      throw new Error("Database query failed");
    }

    const rows = await response.json();
    const record = rows[0];

    if (!record || record.status !== "unused") {
      return res.status(200).json({
        valid: false,
        message: "คีย์ไม่ถูกต้องหรือถูกใช้งานแล้ว"
      });
    }

    if (!record.files) {
      return res.status(200).json({
        valid: false,
        message: "ไม่พบไฟล์ที่ผูกกับคีย์นี้"
      });
    }

    return res.status(200).json({
      valid: true,
      message: "ตรวจสอบคีย์สำเร็จ",
      fileName: record.files.name,
      downloadUrl: record.files.storage_url
    });
  } catch (error) {
    console.error("License verification failed");
    return res.status(500).json({
      valid: false,
      message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้"
    });
  }
}
