import fs from "node:fs";

export async function computeSpec(tab, spec) {
  const pageFn = (spec) => {
    const vis = (el) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      return r.width > 2 && r.height > 2 && s.visibility !== "hidden" && s.display !== "none" && s.opacity !== "0";
    };
    const round = (r) => ({ x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height) });
    const scopeOf = (m) => (m.withinSel ? [...document.querySelectorAll(m.withinSel)][m.withinIndex || 0] : document);
    const byText = (m) => {
      const scope = scopeOf(m);
      if (!scope) return null;
      const list = [...scope.querySelectorAll(m.tag || "*")].filter((el) => {
        if (!vis(el)) return false;
        const t = (el.innerText || el.textContent || "").replace(/\s+/g, " ").trim();
        if (m.contains) return t.includes(m.contains);
        return t === m.text;
      });
      list.sort((a, b) => {
        const ra = a.getBoundingClientRect(), rb = b.getBoundingClientRect();
        return ra.width * ra.height - rb.width * rb.height || ra.y - rb.y || ra.x - rb.x;
      });
      return list[m.index || 0] || null;
    };
    const bySel = (m) => {
      const scope = scopeOf(m);
      if (!scope) return null;
      const list = [...scope.querySelectorAll(m.sel)].filter(vis);
      return list[m.index || 0] || null;
    };
    const rects = [];
    const missing = [];
    for (const m of spec.marks || []) {
      if (m.rect) { rects.push({ ...m, ...m.rect }); continue; }
      let el = m.sel ? bySel(m) : byText(m);
      if (el && m.closest) el = el.closest(m.closest) || el;
      if (!el) { missing.push(m.sel || m.text); continue; }
      rects.push({ ...m, ...round(el.getBoundingClientRect()) });
    }
    let clip;
    if (spec.clipRect) {
      clip = { ...spec.clipRect };
    } else if (spec.clipSel) {
      const el = document.querySelector(spec.clipSel);
      if (!el) return { missing: missing.concat(spec.clipSel), clip: null, marks: [] };
      const r = el.getBoundingClientRect();
      const pad = spec.pad ?? 28;
      clip = { x: Math.round(r.x) - pad, y: Math.round(r.y) - pad, width: Math.round(r.width) + pad * 2, height: Math.round(r.height) + pad * 2 };
    } else {
      const pad = spec.pad ?? 28;
      const xs = rects.map((r) => r.x), ys = rects.map((r) => r.y);
      const xe = rects.map((r) => r.x + r.w), ye = rects.map((r) => r.y + r.h);
      clip = { x: Math.min(...xs) - pad, y: Math.min(...ys) - pad, width: Math.max(...xe) - Math.min(...xs) + pad * 2, height: Math.max(...ye) - Math.min(...ys) + pad * 2 };
    }
    clip.x = Math.max(0, Math.round(clip.x));
    clip.y = Math.max(0, Math.round(clip.y));
    clip.width = Math.min(Math.round(clip.width), window.innerWidth - clip.x);
    clip.height = Math.min(Math.round(clip.height), window.innerHeight - clip.y);
    return { clip, marks: rects.map((r) => ({ n: r.n ?? null, box: Boolean(r.box), pos: r.pos ?? "tl", x: r.x, y: r.y, w: r.w, h: r.h })), missing };
  };
  return await tab.playwright.evaluate(pageFn, spec);
}

async function renderShot(tab, pngBase64, clip, marks) {
  return await tab.playwright.evaluate(async ({ png, clip, marks }) => {
    const img = new Image();
    img.src = "data:image/png;base64," + png;
    await img.decode();
    const scale = img.naturalWidth / window.innerWidth;
    const c = document.createElement("canvas");
    c.width = clip.width;
    c.height = clip.height;
    const ctx = c.getContext("2d");
    ctx.drawImage(img, clip.x * scale, clip.y * scale, clip.width * scale, clip.height * scale, 0, 0, clip.width, clip.height);
    for (const m of marks) {
      const x = m.x - clip.x;
      const y = m.y - clip.y;
      let cx = x - 12;
      let cy = y - 12;
      if (m.box) {
        ctx.strokeStyle = "#e11d48";
        ctx.lineWidth = 2;
        ctx.strokeRect(x - 4.5, y - 4.5, m.w + 9, m.h + 9);
        cx = x - 16;
        cy = y - 16;
      }
      if (m.pos === "bl") { cx = x - 12; cy = y + m.h + 12; }
      if (m.pos === "tr") { cx = x + m.w + 12; cy = y - 12; }
      if (m.pos === "br") { cx = x + m.w - 12; cy = y + m.h + 12; }
      if (m.n === null) continue;
      ctx.beginPath();
      ctx.arc(cx, cy, 10, 0, Math.PI * 2);
      ctx.fillStyle = "#ffffff";
      ctx.fill();
      ctx.lineWidth = 4;
      ctx.strokeStyle = "#ffffff";
      ctx.stroke();
      ctx.lineWidth = 2;
      ctx.strokeStyle = "#e11d48";
      ctx.stroke();
      ctx.fillStyle = "#e11d48";
      ctx.font = "700 13px system-ui, sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(String(m.n), cx, cy + 0.5);
    }
    return c.toDataURL("image/png");
  }, { png: pngBase64, clip, marks });
}

export async function capture(tab, spec, dirs, emitFn) {
  const computed = await computeSpec(tab, spec);
  if (!computed.clip) {
    return { id: spec.id, ok: false, missing: computed.missing };
  }
  const shot = await tab.screenshot();
  const b64 = Buffer.from(shot).toString("base64");
  const rawUrl = await renderShot(tab, b64, computed.clip, []);
  const annUrl = await renderShot(tab, b64, computed.clip, computed.marks);
  fs.writeFileSync(`${dirs.raw}\\${spec.id}.png`, Buffer.from(rawUrl.split(",")[1], "base64"));
  fs.writeFileSync(`${dirs.annotated}\\${spec.id}.png`, Buffer.from(annUrl.split(",")[1], "base64"));
  if (dirs.images) fs.writeFileSync(`${dirs.images}\\${spec.id}.png`, Buffer.from(annUrl.split(",")[1], "base64"));
  if (emitFn) await emitFn(Buffer.from(annUrl.split(",")[1], "base64"));
  return { id: spec.id, ok: computed.missing.length === 0, missing: computed.missing, clip: computed.clip, marks: computed.marks };
}

