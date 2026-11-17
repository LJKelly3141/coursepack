---
name: uwrf-syllabus
description: Use when creating, revising, checking, or submitting a UW-River Falls (UWRF) course syllabus, or when evaluating/reviewing someone else's UWRF syllabus for compliance (e.g., as chair, on a committee, or peer review). Triggers include "check my syllabus", "does this syllabus have everything", "syllabus requirements", "syllabus checklist", "review this syllabus", "evaluate this syllabus", "syllabus repository", "submit my syllabus", "name the syllabus file", "syllabus insert", "required syllabus components", or /uwrf-syllabus.
---

# UWRF Syllabus

> **Institution-specific skill.** Everything below is the policy of the University of Wisconsin-River Falls (UWRF). It is not a general standard. A course at another institution should not use it as written; see **Adapting this skill for another institution** at the end, which explains how to build an equivalent skill for your own school's policy.
>
> This skill is opt-in. A course installs it with `coursepack::install_skills(which = "uwrf-syllabus")`; `install_skills()` with no `which` leaves it out.

Checks a UWRF working syllabus against the Faculty Senate syllabus requirements, and prepares it for the syllabi repository. Two modes:

- **Create / self-check**: the user's own syllabus. Audit it, propose fixes, produce the repository PDF.
- **Evaluate**: someone else's syllabus. Read-only audit and a written report. Never edit their file.

If the mode is unclear from the request, ask.

## Sources and currency

The rules below come from two UWRF documents, as published for the 2026-2027 academic year:

1. **Academic Standards and Expectations for Syllabi** (employees site, requires Falcon login):
   `https://employees.uwrf.edu/administration/academic-standards-and-expectations-syllabi`
   Requirements approved by Faculty Senate March 1, 2017, amended April 10, 2019.
2. **2026-2027 Syllabi Checklist and Insert** (Word file linked from that page):
   `https://fs.uwrf.edu/administration/provost/2026%202027%20Syllabus%20Checklist%20and%20Insert.docx`

The checklist is reissued each academic year. For any academic year after 2026-27, tell the user the rules here may be stale and ask them to paste the current checklist before relying on them. Both pages sit behind the Falcon login, so fetching them returns a login screen. **Do not web-search or fetch without the user's go-ahead**; ask them to paste the page instead.

Verbatim campus-policy text (the "Syllabus Insert") is in `references/syllabus-insert.md`. Use it when a syllabus needs the required language added, and when comparing a syllabus's wording to the official text.

## Scope

Every class needs a working syllabus **except** individualized-instruction courses: internships, mentorship, independent reading, independent study. The syllabus goes to students online or in hard copy.

Instructors may modify the course if the change is consistent with the official course specifications and any formally approved written departmental expectations, and is communicated to students in a timely manner.

## Required components

Check each item. Note the footnote rules; they are where syllabi most often fall short.

| # | Component | What satisfies it |
|---|---|---|
| 1 | Course Title | |
| 2 | Subject Code or Department/Program Prefix | e.g., ABCD |
| 3 | Course Number | |
| 4 | Section Number | |
| 5 | Credits | See **Credit hours** below |
| 6 | Catalog Description | Should match the official catalog description |
| 7 | Course Objectives | |
| 8 | Name of Instructor(s) | |
| 9 | Instructor's Email **and** Phone Number | Both required; one alone is Partial |
| 10 | Instructor In-Person and/or On-Line Office Hours | "By appointment" alone is thin; flag as Partial and let the user judge |
| 11 | Mode of Instruction | In-Person, Distance, or Hybrid |
| 12 | Use of Generative AI Policy | See **Generative AI statement** below |
| 13 | Prerequisites and Co-requisites | "None" is acceptable if stated |
| 14 | Course On-Line Location or Web Page | Required for courses partially or wholly offered through distance education; good practice for all |
| 15 | Class meeting dates and times, **or** description of how required student contact hours are met | See **Contact hours** below |
| 16 | Classroom or Location | As appropriate to the mode of instruction |
| 17 | Required Textbook and other Required Materials | |
| 18 | Required Course Content and any additional content | See **Combined undergraduate/graduate** below |
| 19 | List of Major Assignments and/or Examinations | See **Combined undergraduate/graduate** below |
| 20 | Grading Policy | |
| 21 | Late work **and** missed examination policies | Both halves needed |
| 22 | Counseling Services paragraph | Required for all semesters after Fall 2023-24 (Faculty Senate motion #9, 2023-2024). Official text in the insert |
| 23 | Campus policies on inclusion, respect, ability/disability, accommodation, and academic integrity | The policy text **or** a link to the campus policies. Official text in the insert. Check all five topics are covered: inclusion/discrimination and harassment, respect/Title IX (including faculty as Responsible Employees), disability/DRC accommodation, academic integrity (UWS Chapter 14) |
| 24 | Recording/Copyright policy | Instructor sets it. The official model: recording only with the instructor's advance written permission; permitted personal recordings are for personal study only and may not be distributed, circulated, or sold without written permission |

Items 22 and 23 can be satisfied by attaching the Syllabus Insert.

### Optional components

- **Religious Observances** policy (Faculty and Staff Handbook section 9.2.12). Summary or full text.
- **Land Acknowledgment** statement (encouraged by Faculty Senate Motion 90, April 13, 2022). Full text, or the short version if the audience knows where to find the full one.

Never report an optional item as missing. List it as "optional, not included" at most.

### Generative AI statement (item 12)

Faculty Senate Motion 32 (2024-2025), passed February 5, 2025. The statement must:

- explain the instructor's rules and expectations for generative AI in course assignments and research projects, including any restrictions, guidelines, or requirements; **and**
- emphasize the AI user's **personal responsibility for the accuracy and authenticity** of work produced with these tools.

A statement that bans or permits AI but never mentions personal responsibility for accuracy and authenticity is **Partial**. Instructors have academic freedom over the policy itself (allow, restrict, or guide); do not judge the policy's content, only that both elements are present. CETL has sample statements.

### Credit hours (item 5)

UWRF follows the U.S. Department of Education definition (Handbook section 9.2.2). Per credit, not less than approximately:

- **740 minutes** of class time or direct faculty instruction, **and**
- **1,480 minutes** of out-of-class work,

or the equivalent over a different span (compressed courses), and equivalent work for online, hybrid, studio, lab, co-op, internship, education abroad, and directed independent work.

When the syllabus gives meeting days, times, and dates, check the arithmetic: a 3-credit course needs at least 2,220 instructional minutes (e.g., 2 x 75 min x 15 weeks = 2,250). Show the calculation. If it falls short, flag it; do not decide whether exam week or holidays count, ask.

### Contact hours (item 15)

For any course **not 100 percent face-to-face**, the syllabus must describe how meetings, assignments, activities, and/or online work meet U.S. Department of Education and Higher Learning Commission expectations. Meeting times alone do not satisfy this for hybrid or online courses.

### Combined undergraduate/graduate courses (items 18, 19)

When a course is taught simultaneously as undergraduate and graduate, the syllabus must distinguish graduate expectations on all three of:

- **Content**: additional content, or additional depth and scope.
- **Intensity**: additional readings, assignments, requirements, evaluations reflecting added rigor.
- **Self-direction**: out-of-class work reflecting increased self-directed learning.

Skip this check for single-level courses, and say it was skipped.

## Audit procedure (both modes)

1. **Read the whole syllabus from the file** (QMD, DOCX, PDF, HTML). Never audit from memory or a summary. For a rendered syllabus, also check the version students actually see, since text can be conditional or included from another file.
2. Establish context: course level (undergrad, grad, combined), mode of instruction, credits, academic year. These decide which conditional rules apply.
3. Walk items 1-24, then the optional items. For each, record a status and **evidence**: the heading or line number where it appears, or a short quote.
   - **Present**: fully satisfies the requirement.
   - **Partial**: there but incomplete (e.g., email without phone; AI policy without the responsibility statement; late work without missed exams).
   - **Missing**: not found anywhere.
   - **N/A**: conditional rule does not apply (say why).
4. Run the conditional checks: credit-hour arithmetic, contact-hour description (non-face-to-face), graduate distinctions (combined courses).
5. Compare required policy language against `references/syllabus-insert.md`. Flag outdated contact details (phone numbers, office names, URLs) or wording that drops a required element. Minor rewording is fine; missing substance is not.
6. Consistency checks worth flagging (not requirements): dates that disagree with the course calendar, weights that do not sum to 100, a stated term that does not match the submission file name.

Do not mark something Missing without searching the full text for synonyms (e.g., "Artificial Intelligence", "ChatGPT", "Mental Health" for counseling, "Accessibility" for disability).

## Mode: Create / self-check (the user's syllabus)

- Report the audit table first. Fix nothing until the user picks what to fix.
- For each fix, show the exact before/after text and wait for approval. Required policy language comes from `references/syllabus-insert.md`, verbatim, not paraphrased.
- Syllabus prose is student-facing: no em-dashes in anything added.
- Do not re-render the site or touch other files unless asked. If a PDF is needed, first check whether an existing rendered PDF is newer than the source; if so, copy it rather than re-rendering.

## Mode: Evaluate (someone else's syllabus)

- **Read-only.** Never edit, move, rename, or re-save the file under review. Other people's files may live outside the workspace; reading them is fine only where the user pointed you.
- Output an evaluation report (template below). Findings are reports, not actions.
- Judge compliance, not pedagogy. Do not critique the instructor's grading scheme, AI stance, or course design unless the user asks.
- The report may be forwarded to a colleague: write it in plain, professional language, no em-dashes, and no mention of AI tools.

### Evaluation report template

```
Syllabus review: [PREFIX NUMBER-SECTION], [Course title], [Term]
Instructor: [name]    Reviewed against: UWRF 2026-2027 Syllabi Checklist

Summary: [N] of 24 required components present, [N] partial, [N] missing.

Missing
- [Component]: [what is needed]

Partial
- [Component]: [what is there] / [what is missing]

Conditional checks
- Credit hours: [calculation and result, or N/A with reason]
- Contact-hour description: [result, or N/A (fully face-to-face)]
- Graduate distinctions: [result, or N/A (single-level course)]

Present
- [Component] ([location])
...

Optional
- Religious Observances: [included / not included]
- Land Acknowledgment: [included / not included]

Other notes
- [outdated contact info, calendar inconsistencies, etc.]
```

## Submitting to the syllabi repository

- Format: **PDF**, one per section, every term.
- Send: email to **syllabi@uwrf.edu**. (The standards page also mentions sending it to the program/department representative for the repository at `T:Collaboration\Syllabi Repository\Working Syllabi`; the checklist's email instruction is the current one.)
- File name pattern:
  `Prefix-Course Number-Short Title Description-Year Offered-Term Offered-Section Number`
  Official example: `COUN-610-IntrotoSchoolCounseling-2026-27-Sp-1`
- Conventions this skill applies where the official example is silent:
  - **Year Offered** is the academic year, `2026-27`, for both fall and spring of that year.
  - **Term** uses two letters: `Fa`, `Sp` (and `Su`, `Wi` by the same pattern). Only `Sp` appears in the official example; the rest are inferred.
  - **Section** keeps the leading zero: `01`, not `1`, as good practice for sorting.
  - Short title: CamelCase, no spaces or punctuation.
  - Example: `ABCD-101-DemoCourse-2026-27-Fa-01.pdf`
- Save the PDF to the course's syllabus archive, `semester/archive-syllabus/`, one directory across all terms (the file name carries the term). If the course has no such directory, ask before creating it. Never overwrite an existing file (`cp -n` / `mv -n`).
- Repository questions: Caroline Baker, Interim Associate Provost, caroline.baker@uwrf.edu, 715-425-3237 (as of 2026-27).

## Support

UWRF Center for Excellence in Teaching and Learning (CETL): https://students.uwrf.edu/cetl. Sample AI statements and course-design help.
Falcon Student Handbook: https://students.uwrf.edu/handbook.

## Adapting this skill for another institution

This skill is a model. To build the equivalent for another school:

1. **Collect the sources.** Your institution's syllabus policy (often a faculty senate or provost page) and any checklist or boilerplate "insert" it publishes. Note the approval dates and the academic year each applies to.
2. **Copy the structure, not the content.** Keep the sections: sources and currency, scope, a numbered table of required components with "what satisfies it", optional components, conditional rules, the audit procedure, the two modes, the report template, and submission. Replace every UWRF rule with your own.
3. **Put verbatim policy text in `references/`**, never paraphrased, so an added paragraph matches the official wording exactly.
4. **Write the conditional rules out.** The checks that catch real gaps are the ones with conditions: statements that need two elements, credit-hour arithmetic, online-course contact-hour descriptions, combined-level courses. Spell out what makes each one Partial.
5. **Record your conventions separately** from the institution's rules, so a reader can tell policy from house style (here, the leading-zero section number).
6. **Name it for the institution**, `<institution-id>-syllabus`, and mark it institution-specific at the top, so no other school installs it by mistake.
