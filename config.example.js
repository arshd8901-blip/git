// JOBLY SETTINGS (example). Copy the lines you want into your own config.js.
// Your real config.js already has your Supabase values. Do NOT replace it with this file.
window.JOBLY_CONFIG = {
  // Required for accounts and real jobs. Public values only. NEVER paste a secret or service_role key here.
  supabaseUrl: "YOUR_SUPABASE_PROJECT_URL",
  supabaseKey: "YOUR_SUPABASE_PUBLISHABLE_OR_ANON_KEY",

  // Optional extras (delete any line you don't want):
  contactEmail: "",          // shows "Prefer email?" on Contact and in the footer, e.g. "hello@yourdomain.com"
  aboutName: "",             // shows "Jobly is run by ..." on the About page, e.g. "Arsh D."
  aboutStory: [],            // a few short paragraphs, e.g. ["I started Jobly because ...", "..."]
  showStatsAfter: 5          // the home page only shows real numbers once this many live jobs exist
};
