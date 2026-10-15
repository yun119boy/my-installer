
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

    // 1. ตรวจสอบ License ผ่าน RPC เดิม
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
        "License RPC failed:",
        verifyResponse.status
      );

      return res.status(500).json({
        valid: false,
        message: "ไม่สามารถตรวจสอบคีย์ได้ในขณะนี้",
      });
    }

    const rpcResult = await verifyResponse.json();
    const license = Array.isArray(rpcResult)
      ? rpcResult[0]
      : rpcResult;

    if (!license || license.valid !== true) {
      return res.status(200).json({
        valid: false,
        message: license?.message || "คีย์ไม่ถูกต้อง",
      });
    }

    // 2. ตรวจสอบว่า RPC ส่ง file_id กลับมาหรือไม่
    const fileId =
      license.file_id ??
      license.fileId ??
      license.file?.id ??
      null;

    if (fileId === null || fileId === undefined) {
      console.error("RPC response fields:", Object.keys(license));

      return res.status(500).json({
        valid: false,
        message:
          "RPC ตรวจคีย์ผ่าน แต่ไม่พบ file_id กรุณาตรวจสอบข้อมูล License",
      });
    }

    // 3. ค้นหาข้อมูลไฟล์ในตาราง files
    const fileQuery = new URL(
      `${supabaseUrl}/rest/v1/files`
    );

    fileQuery.searchParams.set("select", "id,name,storage_path");
    fileQuery.searchParams.set("id", `eq.${fileId}`);
    fileQuery.searchParams.set("limit", "1");

    const fileResponse = await fetch(fileQuery.toString(), {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    });

    if (!fileResponse.ok) {
      console.error(
        "File lookup failed:",
        fileResponse.status
      );

      return res.status(500).json({
        valid: false,
        message: "ค้นหาข้อมูลไฟล์ไม่สำเร็จ",
      });
    }

    const files = await fileResponse.json();
    const file = files[0];

    if (
      !file ||
      typeof file.name !== "string" ||
      typeof file.storage_path !== "string" ||
      !file.storage_path.trim()
    ) {
      console.error("File record missing required fields");

      return res.status(500).json({
        valid: false,
        message: "ไม่พบชื่อไฟล์หรือ Storage Path ในฐานข้อมูล",
      });
    }

    // 4. สร้าง Signed URL จาก Storage
    const storagePath = file.storage_path
      .split("/")
      .map(encodeURIComponent)
      .join("/");

    const signedResponse = await fetch(
      `${supabaseUrl}/storage/v1/object/sign/installer-files/${storagePath}`,
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
      signedData.signedURL || signedData.signedUrl;

    if (typeof signedUrl !== "string" || !signedUrl) {
      console.error("Signed URL missing from Storage response");

      return res.status(500).json({
        valid: false,
        message: "เซิร์ฟเวอร์ไม่ได้รับ URL ดาวน์โหลด",
      });
    }

    const downloadUrl = new URL(
      signedUrl,
      supabaseUrl
    ).toString();

    return res.status(200).json({
      valid: true,
      downloadUrl,
      fileName: file.name,
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
