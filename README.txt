JOBLY v5: first-job website for ages 16-18

START HERE: SETUP-GUIDE.txt   (then ADMIN-GUIDE.txt for running the site, GROWTH-GUIDE.txt for next steps)
ALREADY RUNNING v3 or v4? Read "UPDATING" in SETUP-GUIDE.txt (3 steps, about 5 minutes).

WHAT'S NEW IN V5: TEEN PROFILES AND TALENT SEARCH (optional for teens)
- Teens can make a profile: a name they type (first name + last initial is safest), city, short bio, interests, and
  an optional shared resume. Their "picture" is their initials (Jackson D. = JD). No photos, school, address, phone or email.
- Private by default. Only EMPLOYERS YOU VERIFY can browse profiles (Find talent page). You verify them in Supabase.
- Employers can't message teens directly. They send a short "hire interest" request; the teen accepts, declines or blocks.
  The teen's email is shared only after they accept.
- Safety built into the database: phone numbers/emails/links are rejected in bios, resumes and requests; employers can't
  edit anything; blocked employers see nothing; a daily request limit; report buttons; you can hide any profile.
- Privacy text, parent section and FAQ updated to match. HAVE A LAWYER REVIEW THIS BEFORE PROMOTING IT: profiles of minors are sensitive.

WHAT WAS NEW IN V4
Look and feel
- Bolder design with a coral accent, company-initial avatars on every job, category tiles, a "how it works" strip.
- Dark mode (follows the phone/computer setting, with a toggle in the header).
- Phone bottom tab bar, loading skeletons, friendlier empty states, toasts instead of pop-up alerts.
New for teens
- "Find my match": a 5-question quiz that ranks jobs for you and explains why.
- First-job checklist (some steps tick themselves), interview practice with tips and a 60-second timer.
- Browse by interest, a schematic map view of jobs, and "Share" links that open the exact job.
- FAQ for teens, parents and employers. About page and contact email (set in config.js).
Site basics
- Share preview image (og-image.png), proper app icons, a friendly 404 page.
- Home-page numbers appear ONLY when they are real (enough live jobs). No made-up stats or reviews.

STILL NEEDS YOU (see GROWTH-GUIDE.txt): real employers and listings, a real email service (SMTP),
custom domain (optional), lawyer review of privacy/terms, and someone to review jobs and reports.
NOT BUILT YET: an admin page (you still approve jobs in the Supabase Table Editor) and emailed alerts/reminders.
NOTES: the map is a simple schematic, not a street map. Illustrations/initials are used instead of photos
so no one's picture or logo is used without permission.
