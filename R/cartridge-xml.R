# ---- course card image ---------------------------------------------------
#
# Optional. If assets/images/course-tile.png exists it travels in the cartridge
# and Canvas sets it as the dashboard card on import; if it does not, the
# cartridge is built exactly as before and the card is uploaded by hand.
# Generate it with `course_tile()`.
#
# Verified against the reference export, which carries its own card the same
# way: a webcontent resource at web_resources/course_image/course_img.png, and
# an <image_identifier_ref> in course_settings.xml naming that resource's id.
# No $IMS-CC-FILEBASE$ token is involved, which is what makes this different
# from embedding a page asset.
stage_course_card <- function(proj, stage) {
tile_src <- file.path(proj, "assets", "images", "course-tile.png")
has_tile <- file.exists(tile_src)
tile_href <- "web_resources/course_image/course_img.png"
tile_res  <- gid("resource", "course_image")

if (has_tile) {
  dir.create(file.path(stage, dirname(tile_href)), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(tile_src, file.path(stage, tile_href), overwrite = TRUE)
  if (!ok) stop("could not stage the course card image from ", tile_src)
}
list(has_tile = has_tile, tile_href = tile_href, tile_res = tile_res)
}

# ---- course_settings/ ----------------------------------------------------
write_course_settings <- function(stage, course, tile) {
writef(file.path(stage, "course_settings/course_settings.xml"),
       course_settings_xml(course, tile, !is.null(course$grading_standard)))
}

write_assignment_groups <- function(stage, course, groups) {
assignment_groups <- vapply(seq_along(course$assignment_groups), function(i) {
  g <- course$assignment_groups[[i]]
  paste0(
'  <assignmentGroup identifier="', groups[[g$name]], '">\n',
'    <title>', xesc(g$name), '</title>\n',
'    <position>', g$position, '</position>\n',
'    <group_weight>', format(as.numeric(g$weight), nsmall = 1), '</group_weight>\n',
'  </assignmentGroup>')
}, "")
writef(file.path(stage, "course_settings/assignment_groups.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<assignmentGroups ', CCV, '>\n',
paste(assignment_groups, collapse = "\n"), '\n',
'</assignmentGroups>'))
invisible(NULL)
}

write_course_settings_files <- function(stage, course) {
gs <- course$grading_standard
if (!is.null(gs)) {
writef(file.path(stage, "course_settings/grading_standards.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<gradingStandards ', CCV, '>\n',
'  <gradingStandard identifier="', gid("gradingstandard", gs$title), '" version="2">\n',
'    <title>', xesc(gs$title), '</title>\n',
'    <data>', xesc(gs$data), '</data>\n',
'    <points_based>false</points_based>\n',
'    <scaling_factor>1.0</scaling_factor>\n',
'  </gradingStandard>\n',
'</gradingStandards>'))
}

lp <- course$late_policy
if (!is.null(lp)) {
writef(file.path(stage, "course_settings/late_policy.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<late_policy identifier="', gid("latepolicy", course$code), '" ', CCV, '>\n',
'  <missing_submission_deduction_enabled>',
   tolower(as.character(lp$missing_submission_deduction_enabled)),
   '</missing_submission_deduction_enabled>\n',
'  <missing_submission_deduction>100.0</missing_submission_deduction>\n',
'  <late_submission_deduction_enabled>',
   tolower(as.character(lp$late_submission_deduction_enabled)),
   '</late_submission_deduction_enabled>\n',
'  <late_submission_deduction>0.0</late_submission_deduction>\n',
'  <late_submission_interval>day</late_submission_interval>\n',
'  <late_submission_minimum_percent_enabled>',
   tolower(as.character(lp$late_submission_minimum_percent_enabled)),
   '</late_submission_minimum_percent_enabled>\n',
'  <late_submission_minimum_percent>0.0</late_submission_minimum_percent>\n',
'</late_policy>'))
}

writef(file.path(stage, "course_settings/files_meta.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n<fileMeta ', CCV, '>\n</fileMeta>'))
writef(file.path(stage, "course_settings/media_tracks.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n<media_tracks ', CCV, '>\n</media_tracks>'))
writef(file.path(stage, "course_settings/canvas_export.txt"),
       "Q: How do you know a cartridge imported?\nA: You look. Canvas will not tell you.")

}

write_module_meta <- function(stage, modmeta) {
# ---- course_settings/module_meta.xml -------------------------------------
mm <- c('<?xml version="1.0" encoding="UTF-8"?>', paste0('<modules ', CCV, '>'))
for (m in modmeta) {
  mm <- c(mm, '  ',
    paste0('  <module identifier="', m$id, '">'),
    paste0('    <title>', xesc(m$title), '</title>'),
    paste0('    <workflow_state>', m$state, '</workflow_state>'),
    paste0('    <position>', m$position, '</position>'),
    paste0('    <require_sequential_progress>', tolower(as.character(m$sequential)),
           '</require_sequential_progress>'),
    '    <locked>false</locked>', '    <items>')
  for (r in m$items) {
    mm <- c(mm,
      paste0('      <item identifier="', r$item_id, '">'),
      paste0('        <content_type>', r$ctype, '</content_type>'),
      paste0('        <workflow_state>', r$state, '</workflow_state>'),
      paste0('        <title>', xesc(r$title), '</title>'))
    if (!is.null(r$mm_idref))
      mm <- c(mm, paste0('        <identifierref>', r$mm_idref, '</identifierref>'))
    if (!is.null(r$url))
      mm <- c(mm, paste0('        <url>', xesc(r$url), '</url>'))
    mm <- c(mm,
      paste0('        <position>', r$position, '</position>'),
      paste0('        <new_tab>', r$new_tab, '</new_tab>'),
      paste0('        <indent>', r$indent, '</indent>'),
      '        <link_settings_json>null</link_settings_json>',
      '      </item>')
  }
  mm <- c(mm, '    </items>', '  </module>')
}
mm <- c(mm, '</modules>')
writef(file.path(stage, "course_settings/module_meta.xml"), paste(mm, collapse = "\n"))

}

write_weblinks <- function(stage, items) {
# ---- weblink resources (one .xml per ExternalUrl item) -------------------
weblinks <- Filter(function(r) r$ctype == "ExternalUrl", items)
for (r in weblinks) {
  writef(file.path(stage, paste0(r$man_idref, ".xml")), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<webLink xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imswl_v1p1" ', XSI,
' xsi:schemaLocation="http://www.imsglobal.org/xsd/imsccv1p1/imswl_v1p1',
' http://www.imsglobal.org/profile/cc/ccv1p1/ccv1p1_imswl_v1p1.xsd">\n',
'  <title>', xesc(r$title), '</title>\n',
'  <url href="', xesc(r$url), '"/>\n',
'</webLink>'))
}

}

write_wiki_pages <- function(stage, proj, pages, page_res, urls) {
# ---- wiki pages ----------------------------------------------------------
#
# Two body forms, selected by which key the page declares in modules.yml:
#
#   iframe:     the original form. One <iframe> at a hand-measured height. Used
#               for the syllabus, the welcome page and the YouTube embeds. The
#               frame is titled from the page's own `title:`, or from an
#               optional `iframe_title:` where the two differ; see the loop.
#   body: true  generated HTML read from content/canvas/<slug>.html. Used for
#               every chapter, module overview and end-of-module page.
#
# A `body:` page carries NO height, which is the reason chapters use this form:
# a chapter's rendered height changes every time the chapter is edited, and
# Canvas cannot size a cross-origin frame, so a measured height would be wrong
# within a week. See the package README.
#
# The body file is NOT generated here. The course must generate it before this
# writer runs. What this loop must still do is fail loudly if the
# file is absent, because an empty page imports into Canvas perfectly happily
# and looks like a finished course with nothing in it.
canvas_dir <- file.path(proj, "content", "canvas")
for (k in names(pages)) {
  p <- pages[[k]]
  # A carried page's HTML is staged out of the source cartridge byte for byte.
  # Generating one here would overwrite it with something that only resembles it.
  if (!is.null(p$source_ref)) next

  if (isTRUE(p$body)) {
    f <- file.path(canvas_dir, paste0(k, ".html"))
    if (!file.exists(f))
      stop("page '", k, "' declares body: true but content/canvas/", k,
           ".html does not exist; the course must generate content/canvas/", k,
           ".html before building")
    inner <- paste(readLines(f, warn = FALSE), collapse = "\n")
    if (!nzchar(trimws(inner)))
      stop("page '", k, "' has an empty body file. An empty page imports ",
           "into Canvas without error and looks like a finished course with ",
           "nothing in it.")
  } else {
    src <- interp_urls(p$iframe, urls)
    allow <- if (isTRUE(p$video))
      ' allow="accelerometer; clipboard-write; encrypted-media; gyroscope; picture-in-picture"' else ''

    # WHY EVERY FRAME IS TITLED, AND WHY THE TITLE COMES FROM THE PAGE.
    # An <iframe> with no title is announced by a screen reader as "frame" and
    # nothing else. On these pages the frame IS the body, so an untitled frame
    # makes the whole page announce as empty. WCAG 4.1.2; ten findings, all of
    # this one shape, carried since 2026-08-12.
    #
    # The page's `title:` is taken as the frame's name rather than authoring
    # new text, because the page and the frame are already the same object
    # here: "Syllabus" is what the page is called AND what is inside the
    # frame. Deriving it means a page added to modules.yml tomorrow is titled
    # automatically, which is the whole point of fixing this in the generator
    # instead of in the eight files it currently emits.
    #
    # `iframe_title:` overrides it for the case where the frame holds only
    # part of what the page is named after. Nothing declares one today; it
    # exists so that page stays a key in modules.yml rather than becoming a
    # slug-matching special case in this script.
    #
    # An empty title is a hard stop, not a silent fallback, because title=""
    # fails 4.1.2 exactly as badly as no title while LOOKING fixed: the
    # attribute is present, so any check that tests only for the attribute
    # passes it. That is not hypothetical, it is a bug this project's own
    # audit shipped with; see check_untitled_iframes() in the accessibility
    # checker.
    ftitle <- if (!is.null(p$iframe_title)) p$iframe_title else p$title
    if (is.null(ftitle) || !nzchar(trimws(ftitle)))
      stop("page '", k, "' declares iframe: but resolves to an empty frame ",
           "title. A frame with no accessible name is announced only as ",
           "'frame'. Give the page a title:, or an iframe_title: for the ",
           "frame alone.")
    # `height:` is the only height this writer reads. An iframe page may also
    # carry `height_measured:`, the timestamp of the last measurement, which is
    # recorded so a stale height can be found later and is deliberately not
    # used here: the frame ships at whatever the course declares.
    if (is.null(p$height))
      stop("page '", k, "' declares iframe: but no height:")

    inner <- paste0(
'<div style="width: 100%; max-width: 100%; margin: 0 auto;">\n',
'  <iframe title="', xesc(ftitle), '" src="', xesc(src), '" width="', p$width,
'" height="', p$height, '" style="border: 0;" loading="lazy" allowfullscreen=""',
allow, '></iframe>\n',
'  <p style="margin-top: 10px; font-size: 0.9em;">\n',
'    <a href="', xesc(src),
'" target="_blank" style="color: #0066cc;">Open in new tab</a>\n',
'  </p>\n',
'</div>')
  }

  writef(file.path(stage, "wiki_content", paste0(k, ".html")), paste0(
'<html>\n<head>\n<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>\n',
'<title>', xesc(p$title), '</title>\n',
'<meta name="identifier" content="', page_res[[k]], '"/>\n',
'<meta name="editing_roles" content="teachers"/>\n',
'<meta name="workflow_state" content="active"/>\n',
'</head>\n<body>\n',
inner, '\n',
'</body>\n</html>'))
}

}

# ---- assignments ---------------------------------------------------------

# A quiz assignment carries its questions in its own Canvas description rather
# than linking out to the textbook, because the quizzes are course assessment
# and are deliberately NOT published in the book.
#
# THE SAFETY PROPERTY THIS FUNCTION EXISTS TO HOLD. The source file holds the
# questions AND the answer key AND the rubric. Only sections 1 and 2 may ever
# reach Canvas, because an assignment description is shown to students exactly
# as written. That is the opposite of quiz QTI, where an answer key may
# legitimately travel in the cartridge because Canvas withholds it for grading.
#
# Three independent things have to fail before an answer key could ship:
#   1. this function truncates at the ANSWER KEY heading,
#   2. it then hard-stops if the leak canary survived the truncation,
#   3. build_cartridge's own pre-zip scan fails the build on a canary anywhere
#      under the staging tree.
# Do not remove any of the three on the grounds that the others cover it.
# Where the RENDERED textbook lives. Case study directions are copied out of it.
# Same resolution build_preview.R uses, so the two read the same files.
# THE ONLY ASSIGNMENT PROSE THE PACKAGE OWNS.
#
# The sentence above the copied directions. It says the one thing that is true
# of any course whose directions are copied out of a textbook: where the copy
# came from, and which of the two wins. `{href}` and `{title}` are filled in
# with the textbook link and the section's title.
#
# A course overrides it with `assignment_defaults.homework_intro:` in
# course.yml, or per assignment with the same key. Anything that names a tool, a
# file format or a submission workflow is that course's own policy, not a fact
# about assignments, so it goes in that course's
# `assignment_defaults.submission_note:`, which is appended after the
# directions and defaults to empty, so nothing is appended.
HOMEWORK_INTRO_DEFAULT <- paste0(
  '<p>The directions below are copied from <a class="inline_disabled" ',
  'title="Link" href="{href}" target="_blank">{title}</a> in the course ',
  'textbook, which is the source of record.</p>')

assignment_body <- function(a, course, tb_docs) {
  if (!is.null(a$quiz_file))
    return(quiz_student_html(a$quiz_file, a$id, course$urls$site))
  hw   <- a$homework
  base <- course$urls$textbook

  if (is.null(hw$anchor)) {
    href <- paste0(base, "/", hw$chapter, ".html")
    return(paste0(
      '<p><strong>This assignment is not ready.</strong> The textbook ',
      'section it depends on has not been written yet. See <a class="inline_disabled" ',
      'title="Link" href="', xesc(href), '" target="_blank">the case study</a>.</p>'))
  }

  # A course that declares `textbook_docs: none` has no rendered textbook to copy
  # from. Without this the failure lands inside homework_section_html() as a
  # zero-length path, which reads like a bug in the extractor rather than a
  # manifest that asks for directions the course does not have.
  if (is.null(tb_docs))
    stop("assignment '", a$id, "' inlines directions from the textbook but ",
         "textbook_docs is none", call. = FALSE)

  # The directions are COPIED here rather than linked to, so a student never has
  # to leave Canvas to find out what the assignment is. The textbook chapter is
  # unchanged and remains the source of record; the link below is kept so the
  # copy can always be checked against it.
  href <- paste0(base, "/", hw$chapter, ".html#", hw$anchor)
  directions <- homework_section_html(hw$chapter, hw$anchor, tb_docs, base, a$id)

  d <- course$assignment_defaults
  intro <- a$homework_intro %||% d$homework_intro %||% HOMEWORK_INTRO_DEFAULT
  note  <- a$submission_note %||% d$submission_note %||% ""
  intro <- gsub("{title}", xesc(hw$title %||% hw$chapter),
                gsub("{href}", xesc(href), intro, fixed = TRUE), fixed = TRUE)

  paste0(intro, '\n<hr>\n', directions,
         if (nzchar(note)) paste0('\n<hr>\n', note) else '')
}

write_assignments <- function(stage, asg, ids, course, tb_docs, groups, proj, tz) {
asg_res <- ids$asg_res
asg_pos <- ids$asg_pos
d <- course$assignment_defaults
for (k in names(asg)) {
  a <- asg[[k]]
  if (!is.null(a$source_ref)) next                     # carried, not generated
  if (!is.null(a$todo) && isTRUE(a$published))
    stop("REFUSING TO BUILD: ", k, " carries a todo: but is published: true. ",
         "A placeholder must never go live.")
  rid  <- asg_res[[k]]
  slug <- slugify(a$title)
  state <- if (isTRUE(a$published)) "published" else "unpublished"
  # as.numeric matters: format(50L, nsmall = 1) is "50", not "50.0". Canvas
  # writes "50.0" and points_possible is a decimal field.
  pts  <- as.numeric(if (!is.null(a$points)) a$points else d$points)
  ag_id <- group_id_for(a$group %||% d$group, groups,
                        paste0("assignment '", k, "'"))

  body_def <- a
  if (!is.null(body_def$quiz_file)) body_def$quiz_file <- proj_path(proj, body_def$quiz_file)

  writef(file.path(stage, rid, paste0(slug, ".html")), paste0(
'<html>\n<head>\n<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>\n',
'<title>Assignment: ', xesc(a$title), '</title>\n</head>\n<body>\n',
assignment_body(body_def, course, tb_docs), '\n</body>\n</html>'))

  # DUE DATES. The seconds now match what Canvas writes for an end-of-day
  # deadline (T04:59:59, verified against the 2026-09-02 round trip). The clock
  # time is the course's due_time.
  due_xml <- "  <due_at/>\n"
  if (!is.null(a$due))
    due_xml <- paste0("  <due_at>", due_stamp(a$due, course$due_time, tz), "</due_at>\n")

  writef(file.path(stage, rid, "assignment_settings.xml"), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<assignment identifier="', rid, '" ', CCV, '>\n',
'  <title>', xesc(a$title), '</title>\n',
due_xml, '  <lock_at/>\n  <unlock_at/>\n',
'  <module_locked>false</module_locked>\n',
'  <assignment_group_identifierref>', ag_id, '</assignment_group_identifierref>\n',
'  <workflow_state>', state, '</workflow_state>\n',
'  <assignment_overrides>\n  </assignment_overrides>\n',
'  <allowed_extensions>', d$allowed_extensions, '</allowed_extensions>\n',
'  <has_group_category>false</has_group_category>\n',
'  <points_possible>', format(pts, nsmall = 1), '</points_possible>\n',
'  <grading_type>points</grading_type>\n',
'  <submission_types>', d$submission_types, '</submission_types>\n',
'  <position>', asg_pos[[k]], '</position>\n',
'  <turnitin_enabled>false</turnitin_enabled>\n',
'  <peer_reviews>false</peer_reviews>\n',
'  <automatic_peer_reviews>false</automatic_peer_reviews>\n',
'  <grade_group_students_individually>false</grade_group_students_individually>\n',
'  <omit_from_final_grade>false</omit_from_final_grade>\n',
'  <only_visible_to_overrides>false</only_visible_to_overrides>\n',
'  <post_to_sis>false</post_to_sis>\n',
'  <moderated_grading>false</moderated_grading>\n',
'  <anonymous_grading>false</anonymous_grading>\n',
'  <post_policy>\n    <post_manually>false</post_manually>\n  </post_policy>\n',
'</assignment>'))
}

}

write_manifest <- function(stage, course, modmeta, items, ids, tile, ann_ids, m,
                           carried_raw = character()) {
pages <- m$pages
asg <- m$assignments
quiz <- m$quizzes
quiz_res <- ids$quiz_res
quiz_meta <- ids$quiz_meta
asg_res <- ids$asg_res
page_res <- ids$page_res
has_tile <- tile$has_tile
tile_res <- tile$tile_res
tile_href <- tile$tile_href
ann_res <- ann_ids$ann_res
ann_meta <- ann_ids$ann_meta
anns <- ann_res
weblinks <- Filter(function(r) r$ctype == "ExternalUrl", items)
man <- c('<?xml version="1.0" encoding="UTF-8"?>',
paste0('<manifest identifier="', gid("manifest", course$code, course$title), '" ',
'xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1" ',
'xmlns:lom="http://ltsc.ieee.org/xsd/imsccv1p1/LOM/resource" ',
'xmlns:lomimscc="http://ltsc.ieee.org/xsd/imsccv1p1/LOM/manifest" ', XSI, ' ',
'xsi:schemaLocation="http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1 ',
'http://www.imsglobal.org/profile/cc/ccv1p1/ccv1p1_imscp_v1p2_v1p0.xsd ',
'http://ltsc.ieee.org/xsd/imsccv1p1/LOM/resource ',
'http://www.imsglobal.org/profile/cc/ccv1p1/LOM/ccv1p1_lomresource_v1p0.xsd ',
'http://ltsc.ieee.org/xsd/imsccv1p1/LOM/manifest ',
'http://www.imsglobal.org/profile/cc/ccv1p1/LOM/ccv1p1_lommanifest_v1p0.xsd">'),
'  <metadata>',
'    <schema>IMS Common Cartridge</schema>',
'    <schemaversion>1.1.0</schemaversion>',
'    <lomimscc:lom>',
'      <lomimscc:general>',
'        <lomimscc:title>',
paste0('          <lomimscc:string>', xesc(course$title), '</lomimscc:string>'),
'        </lomimscc:title>',
'      </lomimscc:general>',
'      <lomimscc:lifeCycle>',
'        <lomimscc:contribute>',
'          <lomimscc:date>',
paste0('            <lomimscc:dateTime>', format(Sys.Date()), '</lomimscc:dateTime>'),
'          </lomimscc:date>',
'        </lomimscc:contribute>',
'      </lomimscc:lifeCycle>',
'      <lomimscc:rights>',
'        <lomimscc:copyrightAndOtherRestrictions>',
'          <lomimscc:value>yes</lomimscc:value>',
'        </lomimscc:copyrightAndOtherRestrictions>',
'        <lomimscc:description>',
'          <lomimscc:string>Private (Copyrighted) - http://en.wikipedia.org/wiki/Copyright</lomimscc:string>',
'        </lomimscc:description>',
'      </lomimscc:rights>',
'    </lomimscc:lom>',
'  </metadata>',
'  <organizations>',
'    <organization identifier="org_1" structure="rooted-hierarchy">',
'      <item identifier="LearningModules">')
for (m in modmeta) {
  man <- c(man, paste0('        <item identifier="', m$id, '">'),
                paste0('          <title>', xesc(m$title), '</title>'))
  for (r in m$items) {
    open <- if (is.null(r$man_idref))
      paste0('          <item identifier="', r$item_id, '">')
    else
      paste0('          <item identifier="', r$item_id, '" identifierref="', r$man_idref, '">')
    man <- c(man, open,
             paste0('            <title>', xesc(r$title), '</title>'),
             '          </item>')
  }
  man <- c(man, '        </item>')
}
man <- c(man, '      </item>', '    </organization>', '  </organizations>', '  <resources>')

settings_res <- gid("resource", "course_settings")
settings_files <- c(
  "course_settings.xml",
  "module_meta.xml",
  "assignment_groups.xml",
  if (!is.null(course$grading_standard)) "grading_standards.xml",
  "files_meta.xml",
  if (!is.null(course$late_policy)) "late_policy.xml",
  "media_tracks.xml",
  "canvas_export.txt"
)
man <- c(man,
paste0('    <resource identifier="', settings_res,
       '" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" ',
       'href="course_settings/canvas_export.txt">'),
paste0('      <file href="course_settings/', settings_files, '"/>'),
'    </resource>')

if (has_tile) man <- c(man,
  paste0('    <resource identifier="', tile_res, '" type="webcontent" href="', tile_href, '">'),
  paste0('      <file href="', tile_href, '"/>'),
  '    </resource>')

for (r in weblinks) man <- c(man,
  paste0('    <resource identifier="', r$man_idref, '" type="imswl_xmlv1p1">'),
  paste0('      <file href="', r$man_idref, '.xml"/>'),
  '    </resource>')

for (k in names(pages)) {
  if (!is.null(pages[[k]]$source_ref)) next            # its block is carried below
  h <- paste0("wiki_content/", k, ".html")
  man <- c(man,
    paste0('    <resource identifier="', page_res[[k]], '" type="webcontent" href="', h, '">'),
    paste0('      <file href="', h, '"/>'), '    </resource>')
}

for (k in names(asg)) {
  if (!is.null(asg[[k]]$source_ref)) next              # its block is carried below
  rid <- asg_res[[k]]; h <- paste0(rid, "/", slugify(asg[[k]]$title), ".html")
  man <- c(man,
    paste0('    <resource identifier="', rid,
           '" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="', h, '">'),
    paste0('      <file href="', h, '"/>'),
    paste0('      <file href="', rid, '/assignment_settings.xml"/>'), '    </resource>')
}

for (k in names(quiz)) {
  if (!is.null(quiz[[k]]$source_ref)) next             # its block is carried below
  man <- c(man,
    paste0('    <resource identifier="', quiz_res[[k]],
           '" type="imsqti_xmlv1p2/imscc_xmlv1p1/assessment">'),
    paste0('      <file href="', quiz_res[[k]], '/assessment_qti.xml"/>'),
    paste0('      <dependency identifierref="', quiz_meta[[k]], '"/>'),
    '    </resource>',
    paste0('    <resource identifier="', quiz_meta[[k]],
           '" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="',
           quiz_res[[k]], '/assessment_meta.xml">'),
    paste0('      <file href="', quiz_res[[k]], '/assessment_meta.xml"/>'),
    paste0('      <file href="non_cc_assessments/', quiz_res[[k]], '.xml.qti"/>'),
    '    </resource>')
}

# Announcements: the topic depends on the meta; the meta's href is its own file.
# Neither is referenced from anywhere else, matching the round-trip export.
for (k in names(anns)) man <- c(man,
  paste0('    <resource identifier="', ann_res[[k]], '" type="imsdt_xmlv1p1">'),
  paste0('      <file href="', ann_res[[k]], '.xml"/>'),
  paste0('      <dependency identifierref="', ann_meta[[k]], '"/>'),
  '    </resource>',
  paste0('    <resource identifier="', ann_meta[[k]],
         '" type="associatedcontent/imscc_xmlv1p1/learning-application-resource" href="',
         ann_meta[[k]], '.xml">'),
  paste0('      <file href="', ann_meta[[k]], '.xml"/>'),
  '    </resource>')

# Carried <resource> blocks, verbatim, after everything this file generated.
# The span starts at the "<resource" itself, so the four spaces that put it at
# the same depth as the generated blocks are added back here.
if (length(carried_raw)) man <- c(man, paste0("    ", carried_raw))

man <- c(man, '  </resources>', '</manifest>')
writef(file.path(stage, "imsmanifest.xml"), paste(man, collapse = "\n"))

settings_res
}
