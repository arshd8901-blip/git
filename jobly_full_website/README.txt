JOBLY v3: first-job website for ages 16-18

START HERE: SETUP-GUIDE.txt   (then ADMIN-GUIDE.txt for running the site, GROWTH-GUIDE.txt for next steps)

WHAT'S NEW IN V3
- Real jobs from a database (Supabase) with a review-and-approve flow. Samples show only until a real job is approved.
- Accounts now sync availability, resume, application tracker and saved searches across devices (private per user).
- For employers page: post a job (pending until you approve it), private contact email, "My submissions" status.
- Verified / Not yet verified badges, "Verified employers only" filter, https-only apply links.
- Report this listing and Contact forms save to the database (write-only for the public).
- Saved searches, parents & guardians section, privacy/terms updated for accounts.
- Add to Home Screen (manifest + icon). Keys moved to config.js so updates never erase them.
- Database security rules (Row Level Security) tested: users can't approve their own jobs, read others' data, etc.

STILL NEEDS YOU (see GROWTH-GUIDE.txt): real employers and listings, a real email service (SMTP),
custom domain (optional), lawyer review of privacy/terms, and someone to review jobs and reports.
NOT BUILT YET: emailed job alerts and reminder emails (need a scheduled server function).
