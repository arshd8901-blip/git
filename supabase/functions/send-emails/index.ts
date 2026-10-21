// Jobly "send-emails" (Supabase Edge Function). One file: paste it into Dashboard -> Edge Functions -> Deploy a new function -> Via Editor.
// What it does: reads queued rows from the "outbox" table, sends each as an email, and marks it sent.
// Admin alerts (to YOU) work with a free Resend account and no domain.
// Emails to teens/employers are OFF until you set SEND_USER_EMAILS=true (needs a verified sending domain, see ADMIN-GUIDE.txt).
//
// Secrets to set (Dashboard -> Edge Functions -> Secrets):
//   MAIL_API_KEY      your Resend (or Brevo) API key
//   MAIL_FROM         e.g.  Jobly <onboarding@resend.dev>   (later: Jobly <hello@yourdomain.com>)
//   ADMIN_EMAIL       the address that should get admin alerts (with Resend's test sender this MUST be the email you signed up to Resend with)
//   SITE_URL          https://arshd8901-blip.github.io/jobly_full_website/
//   SEND_USER_EMAILS  "true" only once your sending domain is verified (default: off)
//   MAIL_PROVIDER     "resend" (default) or "brevo"

const MAX_PER_RUN = 25;
const MAX_ATTEMPTS = 5;
const STALE_MS = 3 * 24 * 3600 * 1000;

const esc = (s: unknown) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
const clip = (s: unknown, n = 80) => String(s ?? "").replace(/[\r\n]+/g, " ").slice(0, n);

// kind -> who gets it ("admin" or "user") and what it says
const TEMPLATES: Record<string, { to: "admin" | "user"; build: (d: any, site: string) => { subject: string; lines: string[]; link?: [string, string] } }> = {
  request_received: { to: "user", build: (d, site) => ({ subject: "An employer is interested in you on Jobly", lines: [
    `${clip(d.company)} sent you a hire interest request on Jobly.`, "Nothing is shared with them unless you accept. You can accept, decline or block them.", "To turn these emails off, uncheck the box on your My profile page."], link: ["Read the request", site + "#profile"] }) },
  request_accepted: { to: "user", build: (d, site) => ({ subject: "A teen accepted your request on Jobly", lines: [`${clip(d.name, 40)} accepted your hire interest request.`, "Sign in, open Find talent, and press “Show contact” on your sent request."], link: ["Open Find talent", site + "#talent"] }) },
  job_approved: { to: "user", build: (d, site) => ({ subject: "Your Jobly listing is live", lines: [`“${clip(d.title)}” was approved and is now visible to teens on Jobly.`], link: ["See the site", site + "#find-jobs"] }) },
  job_rejected: { to: "user", build: (d, site) => ({ subject: "About your Jobly listing", lines: [`We couldn't approve “${clip(d.title)}” as submitted.`, "If you'd like to fix and resubmit it, or you have questions, use the Contact page."], link: ["Contact us", site + "#contact"] }) },
  employer_verified: { to: "user", build: (d, site) => ({ subject: "You're approved to find talent on Jobly", lines: [`${clip(d.company)} is now approved. You can browse teens who chose to share a profile.`, "Please only contact teens about real jobs that follow child-labor laws."], link: ["Open Find talent", site + "#talent"] }) },
  employer_rejected: { to: "user", build: (d, site) => ({ subject: "About your Jobly access request", lines: [`We couldn't approve ${clip(d.company)} for talent search.`, "If you think that's a mistake, use the Contact page."], link: ["Contact us", site + "#contact"] }) },
  admin_new_job: { to: "admin", build: (_d, site) => ({ subject: "[Jobly] A job is waiting for review", lines: ["A new job was submitted and is pending."], link: ["Open the admin page", site + "#admin"] }) },
  admin_new_employer: { to: "admin", build: (_d, site) => ({ subject: "[Jobly] An employer asked for access", lines: ["A new employer asked to browse teen profiles."], link: ["Open the admin page", site + "#admin"] }) },
  admin_new_report: { to: "admin", build: (_d, site) => ({ subject: "[Jobly] A job listing was reported", lines: ["Someone reported a job listing."], link: ["Open the admin page", site + "#admin"] }) },
  admin_new_profile_report: { to: "admin", build: (_d, site) => ({ subject: "[Jobly] A profile was reported", lines: ["Someone reported a teen profile. Please review it soon."], link: ["Open the admin page", site + "#admin"] }) },
  admin_new_contact: { to: "admin", build: (_d, site) => ({ subject: "[Jobly] New contact message", lines: ["Someone sent a message through the Contact page."], link: ["Open the admin page", site + "#admin"] }) },
};

export function render(kind: string, data: any, site: string) {
  const t = TEMPLATES[kind]; if (!t) return null;
  const base = site.endsWith("/") ? site : site + "/";
  const b = t.build(data || {}, base);
  const foot = t.to === "user" ? "You're getting this because you have an account on Jobly." : "Jobly admin alert.";
  const text = [...b.lines, b.link ? `${b.link[0]}: ${b.link[1]}` : "", "", foot].filter((x, i, a) => x !== "" || a[i - 1] !== "").join("\n");
  const html = `<div style="font-family:Arial,Helvetica,sans-serif;max-width:520px;color:#16201a"><p style="font-weight:800;font-size:20px;margin:0 0 12px">Jobly<span style="color:#ff6b3d">.</span></p>${b.lines.map((l) => `<p style="margin:0 0 10px;line-height:1.5">${esc(l)}</p>`).join("")}${b.link ? `<p style="margin:16px 0"><a href="${esc(b.link[1])}" style="background:#ff6b3d;color:#1a0d07;font-weight:700;text-decoration:none;padding:10px 18px;border-radius:99px;display:inline-block">${esc(b.link[0])}</a></p>` : ""}<p style="color:#5a6a60;font-size:12px;margin-top:20px">${esc(foot)}</p></div>`;
  return { to: t.to, subject: b.subject, text, html };
}

function parseFrom(from: string) { const m = from.match(/^\s*(.*?)\s*<([^>]+)>\s*$/); return m ? { name: m[1].replace(/^"|"$/g, ""), email: m[2] } : { name: "Jobly", email: from.trim() }; }

export function makeMailer(env: Record<string, string | undefined>, fetchFn: typeof fetch = fetch) {
  const provider = (env.MAIL_PROVIDER || "resend").toLowerCase(), key = env.MAIL_API_KEY, from = env.MAIL_FROM || "Jobly <onboarding@resend.dev>";
  return async (to: string, m: { subject: string; text: string; html: string }) => {
    if (!key) throw new Error("MAIL_API_KEY is not set");
    let res: Response;
    if (provider === "brevo") {
      const f = parseFrom(from);
      res = await fetchFn("https://api.brevo.com/v3/smtp/email", { method: "POST", headers: { "api-key": key, "content-type": "application/json", accept: "application/json" }, body: JSON.stringify({ sender: f, to: [{ email: to }], subject: m.subject, htmlContent: m.html, textContent: m.text }) });
    } else {
      res = await fetchFn("https://api.resend.com/emails", { method: "POST", headers: { Authorization: "Bearer " + key, "content-type": "application/json" }, body: JSON.stringify({ from, to: [to], subject: m.subject, html: m.html, text: m.text }) });
    }
    if (!res.ok) throw new Error(provider + " " + res.status + ": " + (await res.text()).slice(0, 200));
  };
}

// db = { pending(limit), finish(id, fields), emailOf(userId) }  (the real one is built in serve(); tests pass a fake)
export async function processOutbox(db: any, send: (to: string, m: any) => Promise<void>, env: Record<string, string | undefined>, now = Date.now()) {
  const site = env.SITE_URL || "https://example.com/", rows = await db.pending(MAX_PER_RUN), out = { sent: 0, skipped: 0, failed: 0 };
  for (const r of rows) {
    const stamp = new Date(now).toISOString();
    try {
      const msg = render(r.kind, r.data, site);
      if (!msg) { await db.finish(r.id, { sent_at: stamp, error: "skipped: unknown kind" }); out.skipped++; continue; }
      if (now - new Date(r.created_at).getTime() > STALE_MS) { await db.finish(r.id, { sent_at: stamp, error: "skipped: too old" }); out.skipped++; continue; }
      let to: string | null = null;
      if (msg.to === "admin") {
        to = env.ADMIN_EMAIL || null; if (!to) { await db.finish(r.id, { attempts: MAX_ATTEMPTS, error: "ADMIN_EMAIL is not set" }); out.failed++; continue; }
      } else {
        if (env.SEND_USER_EMAILS !== "true") { await db.finish(r.id, { sent_at: stamp, error: "skipped: user emails are off" }); out.skipped++; continue; }
        to = r.user_id ? await db.emailOf(r.user_id) : null; if (!to) { await db.finish(r.id, { sent_at: stamp, error: "skipped: no email on file" }); out.skipped++; continue; }
      }
      await send(to, msg); await db.finish(r.id, { sent_at: stamp, error: null }); out.sent++;
    } catch (e) {
      const attempts = (r.attempts || 0) + 1; out.failed++;
      await db.finish(r.id, { attempts, error: String((e as Error).message || e).slice(0, 300) });
    }
  }
  return out;
}

// ---- Supabase wiring (only runs inside Supabase, not in tests) ----
const D = (globalThis as any).Deno;
if (D && D.serve && !(globalThis as any).__JOBLY_TEST__) {
  D.serve(async () => {
    try {
      const { createClient } = await import("npm:@supabase/supabase-js@2");
      const keys = D.env.get("SUPABASE_SECRET_KEYS");
      const key = keys ? (JSON.parse(keys).default ?? Object.values(JSON.parse(keys))[0]) : D.env.get("SUPABASE_SERVICE_ROLE_KEY");
      const sb = createClient(D.env.get("SUPABASE_URL")!, key, { auth: { persistSession: false, autoRefreshToken: false } });
      const env = D.env.toObject();
      const db = {
        async pending(limit: number) { const { data, error } = await sb.from("outbox").select("*").is("sent_at", null).lt("attempts", MAX_ATTEMPTS).order("created_at").limit(limit); if (error) throw error; return data; },
        async finish(id: string, fields: any) { const { error } = await sb.from("outbox").update(fields).eq("id", id); if (error) throw error; },
        async emailOf(uid: string) { const { data } = await sb.auth.admin.getUserById(uid); return data?.user?.email ?? null; },
      };
      const result = await processOutbox(db, makeMailer(env), env);
      return new Response(JSON.stringify(result), { headers: { "content-type": "application/json" } });
    } catch (e) {
      return new Response(JSON.stringify({ error: String((e as Error).message || e) }), { status: 500, headers: { "content-type": "application/json" } });
    }
  });
}
