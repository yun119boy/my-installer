```js
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
  const allowedHost = "utvmdjprzzteltajqwzk.supabase.co";
  const maxFolderFiles = 1000;
  const signingConcurrency = 10;

  if (!supabaseUrl || !serviceKey) {
    console.error("[verify] Missing server configuration");
    return res.status(500).json({
      valid: false,
      message: "Server configuration missing",
    });
  }

  try {
    const baseUrl = new URL(supabaseUrl);

    if (
      baseUrl.protocol !== "https:" ||
      baseUrl.hostname !== allowedHost ||
      baseUrl.username ||
      baseUrl.password ||
      baseUrl.port
    ) {
      return res.status(500).json({
        valid: false,
        message: "Invalid Supabase configuration",
      });
    }
  } catch {
    return res.status(500).json({
      valid: false,
      message: "Invalid Supabase URL",
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

  function isSafeRelativePath(value) {
    if (
      typeof value !== "string" ||
      value.length === 0 ||
      value.length > 240 ||
      value.startsWith("/") ||
      value.startsWith("\\") ||
      /^[a-zA-Z]:/.test(value) ||
      value.includes("\\") ||
      /[\u0000-\u001f\u007f]/.test(value)
    ) {
      return false;
    }

    const parts = value.split("/");

    return parts.every((part) => {
      if (
        !part ||
        part === "." ||
        part === ".." ||
        part.length > 100 ||
        !/^[a-zA-Z0-9._-]+$/.test(part) ||
        /[. ]$/.test(part)
      ) {
        return false;
      }

      const stem = part.split(".")[0].toUpperCase();

      return !/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/.test(stem);
    });
  }

  function normalizeStoragePath(value) {
    if (typeof value !== "string" || !value.trim()) {
      throw new Error("Missing storage path");
    }

    let path = value.trim();

    if (/^https?:\/\//i.test(path)) {
      let url;

      try {
        url = new URL(path);
      } catch {
        throw new Error("Invalid storage URL");
      }

      if (
        url.protocol !== "https:" ||
        url.hostname !== allowedHost ||
        url.username ||
        url.password ||
        url.port
      ) {
        throw new Error("Storage URL is not allowed");
      }

      const prefixes = [
        `/storage/v1/object/public/${bucket}/`,
        `/storage/v1/object/authenticated/${bucket}/`,
        `/storage/v1/object/sign/${bucket}/`,
      ];

      const prefix = prefixes.find((item) =>
        url.pathname.startsWith(item)
      );

      if (!prefix) {
        throw new Error("Invalid Storage URL path");
      }

      if (
        prefix === prefixes[2] &&
        !url.searchParams.has("token")
      ) {
        throw new Error("Missing signed URL token");
      }

      path = url.pathname.slice(prefix.length);
    }

    try {
      path = decodeURIComponent(path);
    } catch {
      throw new Error("Invalid path encoding");
    }

    path = path.replace(/^\/+/, "");

    if (path.startsWith(`${bucket}/`)) {
      path = path.slice(bucket.length + 1);
    }

    const segments = path.split("/");

    if (
      !path ||
      path.length > 1000 ||
      segments.some(
        (segment) =>
          !segment ||
          segment === "." ||
          segment === ".." ||
          segment.includes("\\") ||
          /[\u0000-\u001f\u007f]/.test(segment)
      )
    ) {
      throw new Error("Invalid Storage path");
    }

    return { path, segments };
  }

  function normalizeSignedUrl(value) {
    if (typeof value !== "string" || !value.trim()) {
      throw new Error("Supabase returned an empty signed URL");
    }

    const raw = value.trim();
    let signedUrl;

    try {
      if (/^https:\/\//i.test(raw)) {
        signedUrl = new URL(raw);
      } else {
        const relative = raw.replace(/^\/+/, "");

        if (relative.startsWith("storage/v1/")) {
          signedUrl = new URL(relative, `${supabaseUrl}/`);
        } else if (relative.startsWith("object/sign/")) {
          signedUrl = new URL(
            `storage/v1/${relative}`,
            `${supabaseUrl}/`
          );
        } else {
          throw new Error("Unexpected signed URL path format");
        }
      }
    } catch {
      throw new Error("Unable to parse generated signed URL");
    }

    const pathPrefix = `/storage/v1/object/sign/${bucket}/`;

    const valid =
      signedUrl.protocol === "https:" &&
      signedUrl.hostname === allowedHost &&
      !signedUrl.username &&
      !signedUrl.password &&
      !signedUrl.port &&
      signedUrl.pathname.startsWith(pathPrefix) &&
      signedUrl.searchParams.has("token");

    if (!valid) {
      throw new Error("Invalid generated signed URL");
    }

    return signedUrl.toString();
  }

  async function createSignedUrl(storagePath) {
    const normalized = normalizeStoragePath(storagePath);
    const candidates = [normalized.path];

    if (normalized.path.startsWith(`${bucket}/`)) {
      candidates.push(
        normalized.path.slice(bucket.length + 1)
      );
    }

    const uniqueCandidates = [...new Set(candidates)];
    let lastStatus = 0;
    let lastDetails = "";

    for (const candidate of uniqueCandidates) {
      const encodedPath = candidate
        .split("/")
        .map((segment) => encodeURIComponent(segment))
        .join("/");

      const response = await fetch(
        `${supabaseUrl}/storage/v1/object/sign/${bucket}/${encodedPath}`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: serviceKey,
            Authorization: `Bearer ${serviceKey}`,
          },
          body: JSON.stringify({ expiresIn: 86400 }),
        }
      );

      if (!response.ok) {
        lastStatus = response.status;
        lastDetails = (await response.text()).slice(0, 300);

        console.error("[verify] Signed URL attempt failed:", {
          status: lastStatus,
          details: lastDetails,
        });

        continue;
      }

      const data = await response.json();

      if (
        typeof data.signedURL !== "string" ||
        !data.signedURL
      ) {
        lastStatus = response.status;
        lastDetails = "Supabase did not return signedURL";
        continue;
      }

      return normalizeSignedUrl(data.signedURL);
    }

    throw new Error(
      `Unable to sign Storage object; status=${lastStatus}; details=${lastDetails}`
    );
  }

  async function mapWithConcurrency(items, concurrency, worker) {
    const results = new Array(items.length);
    let nextIndex = 0;

    async function runWorker() {
      while (true) {
        const index = nextIndex++;

        if (index >= items.length) return;

        results[index] = await worker(items[index], index);
      }
    }

    const workerCount = Math.min(concurrency, items.length);

    await Promise.all(
      Array.from({ length: workerCount }, () => runWorker())
    );

    return results;
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
        "[verify] License RPC failed:",
        rpcResponse.status,
        (await rpcResponse.text()).slice(0, 300)
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

    if (result.type === "file" || !result.type) {
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

      let parsedUrl;

      try {
        parsedUrl = new URL(downloadUrl);
      } catch {
        parsedUrl = null;
      }

      if (
        parsedUrl &&
        parsedUrl.protocol === "https:" &&
        parsedUrl.hostname === "github.com" &&
        !parsedUrl.username &&
        !parsedUrl.password &&
        !parsedUrl.port &&
        /^\/yun119boy\/my-installer\/releases\/download\/[^/]+\/[^/]+$/.test(
          parsedUrl.pathname
        )
      ) {
        return res.status(200).json({
          valid: true,
          type: "file",
          message: result.message || "ตรวจสอบคีย์สำเร็จ",
          fileName,
          downloadUrl: parsedUrl.toString(),
          useNumber: result.useNumber,
        });
      }

      const signedUrl = await createSignedUrl(downloadUrl);

      return res.status(200).json({
        valid: true,
        type: "file",
        message: result.message || "ตรวจสอบคีย์สำเร็จ",
        fileName,
        downloadUrl: signedUrl,
        useNumber: result.useNumber,
      });
    }

    if (result.type === "folder") {
      const folderId = result.folderId;

      const folderName =
        typeof result.folderName === "string"
          ? result.folderName.trim()
          : "";

      if (
        typeof folderId !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          folderId
        ) ||
        !folderName
      ) {
        return res.status(500).json({
          valid: false,
          message: "ข้อมูลโฟลเดอร์ของ License ไม่ถูกต้อง",
        });
      }

      const queryUrl = new URL(
        `${supabaseUrl}/rest/v1/folder_files`
      );

      queryUrl.searchParams.set("folder_id", `eq.${folderId}`);
      queryUrl.searchParams.set("select", "name,storage_path");
      queryUrl.searchParams.set("order", "name.asc");
      queryUrl.searchParams.set(
        "limit",
        String(maxFolderFiles + 1)
      );

      const filesResponse = await fetch(queryUrl.toString(), {
        method: "GET",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
      });

      if (!filesResponse.ok) {
        console.error(
          "[verify] Folder file query failed:",
          filesResponse.status,
          (await filesResponse.text()).slice(0, 300)
        );

        return res.status(500).json({
          valid: false,
          message: "ไม่สามารถอ่านรายการไฟล์ในโฟลเดอร์ได้",
        });
      }

      const folderFiles = await filesResponse.json();

      if (
        !Array.isArray(folderFiles) ||
        folderFiles.length === 0
      ) {
        return res.status(404).json({
          valid: false,
          message: "ไม่พบไฟล์ในโฟลเดอร์นี้",
        });
      }

      if (folderFiles.length > maxFolderFiles) {
        return res.status(413).json({
          valid: false,
          message: "โฟลเดอร์มีไฟล์เกินจำนวนที่อนุญาต (สูงสุด 1,000 ไฟล์)",
        });
      }

      const seenNames = new Set();

      for (let i = 0; i < folderFiles.length; i++) {
        const file = folderFiles[i];

        const validName = isSafeRelativePath(file?.name);
        const validStoragePath =
          typeof file?.storage_path === "string" &&
          file.storage_path.trim().length > 0;

        if (!validName || !validStoragePath) {
          console.error("[verify] Invalid folder file record:", {
            index: i,
            recordIsObject:
              file !== null &&
              typeof file === "object" &&
              !Array.isArray(file),
            name: file?.name,
            nameLength:
              typeof file?.name === "string"
                ? file.name.length
                : null,
            nameHex:
              typeof file?.name === "string"
                ? Buffer.from(file.name, "utf8").toString("hex")
                : null,
            nameType: typeof file?.name,
            validName,
            storagePath: file?.storage_path,
            storagePathType: typeof file?.storage_path,
            validStoragePath,
          });

          throw new Error("Invalid folder file record");
        }

        const normalizedName = file.name.toLowerCase();

        if (seenNames.has(normalizedName)) {
          console.error("[verify] Duplicate folder file path:", {
            index: i,
            name: file.name,
            nameLength: file.name.length,
            nameHex: Buffer.from(file.name, "utf8").toString("hex"),
          });

          throw new Error("Duplicate folder file path");
        }

        seenNames.add(normalizedName);
      }

      const files = await mapWithConcurrency(
        folderFiles,
        signingConcurrency,
        async (file) => {
          const downloadUrl = await createSignedUrl(
            file.storage_path
          );

          return {
            name: file.name,
            downloadUrl,
          };
        }
      );

      return res.status(200).json({
        valid: true,
        type: "folder",
        message: result.message || "ตรวจสอบคีย์สำเร็จ",
        folderId,
        folderName,
        files,
        fileCount: files.length,
        useNumber: result.useNumber,
      });
    }

    console.error("[verify] Unsupported license type");

    return res.status(500).json({
      valid: false,
      message: "ประเภท License ไม่ถูกต้อง",
    });
  } catch (error) {
    console.error(
      "[verify] License verification failed:",
      error instanceof Error
        ? error.message
        : "Unknown error"
    );

    return res.status(500).json({
      valid: false,
      message: "ไม่สามารถตรวจสอบคีย์หรือสร้างลิงก์ดาวน์โหลดได้",
    });
  }
};
```
