import Foundation

struct MockCategory: Identifiable {
    let id: String
    let name: String
    let emails: [Email]
}

enum MockData {
    static let categories: [MockCategory] = [
        MockCategory(
            id: "interview",
            name: "Interview",
            emails: [
                Email(
                    sender: "Taylor Brooks",
                    senderEmail: "taylor.brooks@northstar.com",
                    subject: "Interview panel — final loop on Wednesday",
                    preview: "Final loop scheduled — confirm your slot for Wednesday afternoon.",
                    receivedAt: "9:12 AM",
                    destinationAccount: "work@gmail.com",
                    isUnread: true,
                    summarizedBody: "Taylor confirmed your final interview loop is set for Wednesday 2–5pm with four panelists. Bring a laptop; the system design round needs a shared editor.",
                    attachments: [EmailAttachment(name: "panel-schedule.md", mimeType: "text/markdown")]
                ),
                Email(
                    sender: "Jordan Kim",
                    senderEmail: "jordan.kim@orbitlabs.io",
                    subject: "Onsite scheduling options",
                    preview: "Sharing a few time slots for your onsite — let me know what works.",
                    receivedAt: "8:46 AM",
                    destinationAccount: "work@gmail.com",
                    isUnread: true,
                    summarizedBody: "Jordan offered three onsite slots next week (Mon/Wed/Thu). They need a confirmation by EOD Friday so they can book the panel."
                ),
                Email(
                    sender: "Priya Shah",
                    senderEmail: "priya@talentcue.com",
                    subject: "Recruiter intro call",
                    preview: "Confirming our intro call tomorrow to walk through the role and team.",
                    receivedAt: "Yesterday",
                    destinationAccount: "work@gmail.com",
                    summarizedBody: "Priya confirmed tomorrow's 30-min intro call. Agenda: role overview, team structure, comp band, and Q&A."
                ),
                Email(
                    sender: "Avery Lee",
                    senderEmail: "avery.lee@flux.ai",
                    subject: "Take-home assignment",
                    preview: "Here are the instructions and the rubric for the take-home exercise.",
                    receivedAt: "Mon",
                    destinationAccount: "work@gmail.com",
                    summarizedBody: "Take-home is due in 5 days. The rubric weights correctness 50%, design 30%, tests 20%. Submit a single zip file via the portal.",
                    attachments: [
                        EmailAttachment(name: "take-home-instructions.md", mimeType: "text/markdown"),
                        EmailAttachment(name: "rubric.md", mimeType: "text/markdown")
                    ]
                )
            ]
        ),
        MockCategory(
            id: "work",
            name: "Work",
            emails: [
                Email(
                    sender: "Avery Lee",
                    senderEmail: "avery@inkpath.co",
                    subject: "Q2 planning notes",
                    preview: "Sharing the draft agenda and owners before tomorrow's planning session.",
                    receivedAt: "2h ago",
                    destinationAccount: "work@gmail.com",
                    isUnread: true,
                    summarizedBody: "Q2 planning agenda is attached. Each owner should pre-fill their section by tomorrow 9am so the meeting can focus on cross-team dependencies.",
                    attachments: [EmailAttachment(name: "q2-agenda.docx", mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document")]
                ),
                Email(
                    sender: "Priya Shah",
                    senderEmail: "priya.shah@inkpath.co",
                    subject: "Design review follow-up",
                    preview: "I added comments to the thread and called out the blockers for launch.",
                    receivedAt: "4h ago",
                    destinationAccount: "work@gmail.com",
                    isUnread: true,
                    summarizedBody: "Priya flagged two launch blockers: empty-state copy and the dark-mode contrast on the primary CTA. Both need a fix before Friday's review."
                ),
                Email(
                    sender: "Jordan Kim",
                    senderEmail: "jordan@inkpath.co",
                    subject: "Client status update",
                    preview: "The client approved the updated scope and wants the timeline by Friday.",
                    receivedAt: "Yesterday",
                    destinationAccount: "work@gmail.com",
                    summarizedBody: "Client approved the revised scope. They want a fresh timeline doc by Friday with milestones, owners, and a risk column."
                )
            ]
        ),
        MockCategory(
            id: "finance",
            name: "Finance",
            emails: [
                Email(
                    sender: "Northstar Bank",
                    senderEmail: "no-reply@northstarbank.com",
                    subject: "Statement available",
                    preview: "Your monthly account statement is ready to view in online banking.",
                    receivedAt: "1h ago",
                    destinationAccount: "finance@gmail.com",
                    isUnread: true,
                    summarizedBody: "March statement is ready. Closing balance increased 4.2% MoM. No unusual activity flagged.",
                    attachments: [EmailAttachment(name: "statement-mar-2026.txt", mimeType: "text/plain")]
                ),
                Email(
                    sender: "Card Services",
                    senderEmail: "alerts@cardservices.com",
                    subject: "Large purchase alert",
                    preview: "A recent transaction exceeded your notification threshold.",
                    receivedAt: "Tue",
                    destinationAccount: "finance@gmail.com",
                    isUnread: true,
                    summarizedBody: "A $1,240 charge at Apple Store posted yesterday. If you don't recognize it, reply STOP to lock the card immediately."
                ),
                Email(
                    sender: "Acme Payroll",
                    senderEmail: "payroll@acme.com",
                    subject: "Paystub posted",
                    preview: "Your latest paystub has been posted to the employee portal.",
                    receivedAt: "Yesterday",
                    destinationAccount: "finance@gmail.com",
                    summarizedBody: "April 15 paystub is posted. Net pay matches last cycle. Tax withholdings adjusted slightly after your W-4 update."
                )
            ]
        ),
        MockCategory(
            id: "newsletters",
            name: "Newsletters",
            emails: [
                Email(
                    sender: "Product Weekly",
                    senderEmail: "hello@productweekly.io",
                    subject: "Five launches worth watching",
                    preview: "A compact roundup of product updates, funding news, and launch notes.",
                    receivedAt: "2h ago",
                    destinationAccount: "personal@gmail.com",
                    summarizedBody: "Top picks this week: Linear's spreadsheet view, Vercel's edge config GA, and Replit's mobile editor. Three funding rounds, all in agentic tooling."
                ),
                Email(
                    sender: "Design Digest",
                    senderEmail: "team@designdigest.co",
                    subject: "Patterns for cleaner settings",
                    preview: "This week focuses on dense forms, disclosure patterns, and account flows.",
                    receivedAt: "4h ago",
                    destinationAccount: "personal@gmail.com",
                    isUnread: true,
                    summarizedBody: "Three patterns covered: progressive disclosure for advanced options, grouped toggles with shared explanations, and inline validation that doesn't shout."
                )
            ]
        )
    ]
}
