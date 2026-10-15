
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

  const supabaseUrl = process.env.SUPABASE_URL?.replace(/\/+$/, "");
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const bucket = "installer-files";

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

    // 1. ตรวจสอบ License ผ่าน Supabase RPC
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
      console.error("License RPC failed:", rpcResponse.status);

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
      return res.status(500).json({
        valid: false,
        message: "ข้อมูลไฟล์ของ License ไม่ครบ",
      });
    }

    // 2. อนุญาตเฉพาะ GitHub Release URL ที่กำหนดไว้
    let parsedUrl;

    try {
      parsedUrl = new URL(downloadUrl);
    } catch {
      parsedUrl = null;
    }

    if (parsedUrl) {
      const isAllowedGitHub =
        parsedUrl.protocol === "https:" &&
        parsedUrl.hostname === "github.com" &&
        parsedUrl.username === "" &&
        parsedUrl.password === "" &&
        parsedUrl.port === "" &&
        parsedUrl.pathname.startsWith(
          "/yun119boy/my-installer/releases/download/"
        );

      if (isAllowedGitHub) {
        return res.status(200).json({
          valid: true,
          message: result.message || "ตรวจสอบคีย์สำเร็จ",
          fileName,
          downloadUrl: parsedUrl.toString(),
          useNumber: result.useNumber,
        });
      }

      // URL เต็มที่ไม่ใช่แหล่งที่อนุญาต ห้ามนำไปใช้
      if (
        parsedUrl.protocol !== "https:" ||
        parsedUrl.hostname !== "utvmdjprzzteltajqwzk.supabase.co" ||
        parsedUrl.username ||
        parsedUrl.password ||
        parsedUrl.port
      ) {
        return res.status(500).json({
          valid: false,
          message: "URL ดาวน์โหลดไม่ตรงกับแหล่งไฟล์ที่อนุญาต",
        });
      }
    }

    // 3. แปลง storage_url ให้เป็น Path ภายใน Bucket
    const prefix = `/storage/v1/object/`;

    let objectPath = downloadUrl;

    if (parsedUrl) {
      const path = parsedUrl.pathname;

      const publicPrefix = `${prefix}public/${bucket}/`;
      const signPrefix = `${prefix}sign/${bucket}/`;
      const authenticatedPrefix = `${prefix}authenticated/${bucket}/`;

      if (path.startsWith(publicPrefix)) {
        objectPath = path.slice(publicPrefix.length);
      } else if (path.startsWith(signPrefix)) {
        // Signed URL เดิมใช้ได้ต่อเมื่อมี token
        const token = parsedUrl.searchParams.get("token");

        if (!token) {
          return res.status(500).json({
            valid: false,
            message: "Signed URL ไม่มี token",
          });
        }

        return res.status(200).json({
          valid: true,
          message: result.message || "ตรวจสอบคีย์สำเร็จ",
          fileName,
          downloadUrl: parsedUrl.toString(),
          useNumber: result.useNumber,
        });
      } else if (path.startsWith(authenticatedPrefix)) {
        objectPath = path.slice(authenticatedPrefix.length);
      } else {
        return res.status(500).json({
          valid: false,
          message: "Path ของไฟล์ไม่ถูกต้อง",
        });
      }
    }

    // รองรับ Path ที่มีหรือไม่มีชื่อ Bucket นำหน้า
    objectPath = objectPath.replace(/^\/+/, "");

    if (objectPath.startsWith(`${bucket}/`)) {
      objectPath = objectPath.slice(bucket.length + 1);
    }

    let decodedPath;

    try {
      decodedPath = decodeURIComponent(objectPath);
    } catch {
      return res.status(400).json({
        valid: false,
        message: "รูปแบบ Path ของไฟล์ไม่ถูกต้อง",
      });
    }

    const segments = decodedPath.split("/");

    if (
      !decodedPath ||
      decodedPath.length > 1000 ||
      segments.some(
        (segment) =>
          !segment ||
          segment === "." ||
          segment === ".." ||
          segment.includes("\\")
      )
    ) {
      return res.status(400).json({
        valid: false,
        message: "Path ของไฟล์ไม่ถูกต้อง",
      });
    }

    // 4. ขอ Signed URL จาก Supabase Storage อายุ 5 นาที
    const encodedPath = decodedPath
      .split("/")
      .map((segment) => encodeURIComponent(segment))
      .join("/");

    const signResponse = await fetch(
      `${supabaseUrl}/storage/v1/object/sign/${bucket}/${encodedPath}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          expiresIn: 86400,
        }),
      }
    );

    if (!signResponse.ok) {
      const errorText = await signResponse.text();

      console.error(
        "Supabase signed URL creation failed:",
        signResponse.status,
        errorText.slice(0, 500)
      );

      return res.status(500).json({
        valid: false,
        message: "ไม่สามารถสร้างลิงก์ดาวน์โหลดได้ กรุณาตรวจสอบไฟล์ใน Storage",
      });
    }

    const signedResult = await signResponse.json();

    if (typeof signedResult.signedURL !== "string") {
      return res.status(500).json({
        valid: false,
        message: "Supabase ไม่ได้ส่ง Signed URL กลับมา",
      });
    }

    // Supabase อาจส่ง Path กลับมาแทน URL เต็ม
    const signedURL = signedResult.signedURL.startsWith("http")
      ? new URL(signedResult.signedURL)
      : new URL(
          signedResult.signedURL.replace(/^\/+/, ""),
          `${supabaseUrl}/storage/v1/`
        );

    // 5. ตรวจสอบ URL ที่สร้างก่อนส่งให้ปลั๊กอิน
    if (
      signedURL.protocol !== "https:" ||
      signedURL.hostname !== "utvmdjprzzteltajqwzk.supabase.co" ||
      signedURL.username ||
      signedURL.password ||
      signedURL.port ||
      !signedURL.pathname.startsWith(
        `/storage/v1/object/sign/${bucket}/`
      ) ||
      !signedURL.searchParams.has("token")
    ) {
      console.error("Generated signed URL failed validation");

      return res.status(500).json({
        valid: false,
        message: "Signed URL ที่สร้างไม่ถูกต้อง",
      });
    }

    return res.status(200).json({
      valid: true,
      message: result.message || "ตรวจสอบคีย์สำเร็จ",
      fileName,
      downloadUrl: signedURL.toString(),
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
