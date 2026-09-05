# A cartridge shaped for the accessibility audit rather than for the builder.
# It stands in for the real Canvas export the snapshot's own section audited,
# which is one course's content and does not ship here. Two wiki pages, so
# `wiki_pages_read` has a number that is not 1 and not the file count; one
# untitled iframe and one titled one, so the iframe check has to read the
# attribute rather than count tags; one weblink whose text says nothing out of
# context; and one embedded video, in a TITLED frame, so the video checks have
# something to resolve without adding a second untitled-iframe finding.
#
# `topics` adds announcement topics, each a list of id, title and html. Empty
# by default, so every caller written before announcements were audited gets
# the identical cartridge it always got. The shape is the one
# R/cartridge-announcements.R writes: an imsdt_v1p1 <topic> whose body is
# XML-ESCAPED inside <text texttype="text/html">. The escaping is written out
# below rather than borrowed from the builder's own xtext(), so the audit's
# unescape is checked against an independent implementation of the escape and
# not against the same three lines that produced it.
#
# `pages` turns the same cartridge into something `extract_manifest()` can read:
# each entry, a list of slug, title and src, is written as a page carrying the
# builder's iframe wrapper, declared in an `imsmanifest.xml` and listed as a
# module item, beside the minimal `course_settings/` a Canvas export carries.
# Empty by default, so every caller written before extraction gets the identical
# cartridge it always got. The wrapper is spelled out here rather than borrowed
# from the builder's own `iframe_wrapper()`, so the extractor's detection is
# checked against an independent copy of the template and not against the same
# nine lines that produced it.
write_a11y_cartridge <- function(zip_path, topics = list(), pages = list()) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(d, "wiki_content"))
  writeLines(paste0(
    "<html><body>",
    "<iframe src=\"x\"></iframe>",
    "</body></html>"),
    file.path(d, "wiki_content", "welcome.html"))
  writeLines(paste0(
    "<html><body>",
    "<iframe title=\"Syllabus\" src=\"y\"></iframe>",
    "<iframe title=\"Orientation\" ",
    "src=\"https://www.youtube-nocookie.com/embed/DEADEMBED01\"></iframe>",
    "</body></html>"),
    file.path(d, "wiki_content", "syllabus.html"))
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<webLink xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imswl_v1p1">',
    '  <title>click here</title>',
    '  <url href="https://example.invalid/reading"/>',
    '</webLink>'), file.path(d, "weblink.xml"))
  esc <- function(s) {
    s <- gsub("&", "&amp;", s, fixed = TRUE)
    s <- gsub("<", "&lt;",  s, fixed = TRUE)
    gsub(">", "&gt;", s, fixed = TRUE)
  }
  for (tp in topics) {
    writeLines(c(
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<topic xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imsdt_v1p1">',
      paste0('  <title>', esc(tp$title), '</title>'),
      paste0('  <text texttype="text/html">', esc(tp$html), '</text>'),
      '</topic>'), file.path(d, paste0(tp$id, ".xml")))
  }
  if (length(pages)) {
    gid29 <- function(tag) paste0("g", strrep("0", 29), tag)
    res <- character(); items <- character()
    for (i in seq_along(pages)) {
      p <- pages[[i]]
      rid <- gid29(sprintf("d%02d", i)); iid <- gid29(sprintf("e%02d", i))
      href <- paste0("wiki_content/", p$slug, ".html")
      writeLines(c(
        "<html>", "<head>",
        '<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>',
        paste0("<title>", p$title, "</title>"),
        paste0('<meta name="identifier" content="', rid, '"/>'),
        '<meta name="editing_roles" content="teachers"/>',
        '<meta name="workflow_state" content="active"/>',
        "</head>", "<body>",
        '<div style="width: 100%; max-width: 100%; margin: 0 auto;">',
        paste0('  <iframe title="', p$title, '" src="', p$src, '" width="100%"',
               ' height="1200px" style="border: 0;" loading="lazy" allowfullscreen=""></iframe>'),
        '  <p style="margin-top: 10px; font-size: 0.9em;">',
        paste0('    <a href="', p$src, '" target="_blank" style="color: #0066cc;">Open in new tab</a>'),
        "  </p>", "</div>", "</body>", "</html>"), file.path(d, href))
      res <- c(res, sprintf('<resource identifier="%s" type="webcontent" href="%s"><file href="%s"/></resource>',
                            rid, href, href))
      items <- c(items, sprintf(paste0('<item identifier="%s"><content_type>WikiPage</content_type>',
                                       '<workflow_state>active</workflow_state><title>%s</title>',
                                       '<identifierref>%s</identifierref><position>%d</position>',
                                       '<new_tab>false</new_tab><indent>0</indent></item>'),
                                iid, p$title, rid, i))
    }
    dir.create(file.path(d, "course_settings"), showWarnings = FALSE)
    writeLines(c('<?xml version="1.0" encoding="UTF-8"?>',
                 '<course xmlns="http://canvas.instructure.com/xsd/cccv1p0">',
                 '  <title>Synthetic Course</title>',
                 '  <course_code>SYN 100</course_code>',
                 '  <is_public>false</is_public>',
                 '  <default_view>modules</default_view>',
                 '  <group_weighting_scheme>percent</group_weighting_scheme>',
                 '</course>'), file.path(d, "course_settings", "course_settings.xml"))
    writeLines(c('<?xml version="1.0" encoding="UTF-8"?>',
                 '<assignmentGroups xmlns="http://canvas.instructure.com/xsd/cccv1p0">',
                 paste0('  <assignmentGroup identifier="', gid29("00c"), '">'),
                 '    <title>Assignments</title>', '    <position>1</position>',
                 '    <group_weight>100.0</group_weight>',
                 '  </assignmentGroup>', '</assignmentGroups>'),
               file.path(d, "course_settings", "assignment_groups.xml"))
    writeLines(c('<?xml version="1.0" encoding="UTF-8"?>',
                 '<modules xmlns="http://canvas.instructure.com/xsd/cccv1p0">',
                 paste0('<module identifier="', gid29("f01"), '"><title>Only Module</title>'),
                 '<workflow_state>active</workflow_state><position>1</position>',
                 '<require_sequential_progress>false</require_sequential_progress><items>',
                 items, '</items></module>', '</modules>'),
               file.path(d, "course_settings", "module_meta.xml"))
    writeLines(c('<?xml version="1.0" encoding="UTF-8"?>',
                 '<manifest xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1"><resources>',
                 res, '</resources></manifest>'), file.path(d, "imsmanifest.xml"))
  }
  old <- setwd(d); on.exit(setwd(old), add = TRUE)
  utils::zip(zip_path, list.files(".", recursive = TRUE), flags = "-q -X")
  zip_path
}

write_mini_cartridge <- function(zip_path, modules, due = "") {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(d, "course_settings")); dir.create(file.path(d, "a1"))
  mm <- c('<?xml version="1.0" encoding="UTF-8"?>', '<modules xmlns="http://canvas.instructure.com/xsd/cccv1p0">')
  res <- character(); n <- 0L
  for (i in seq_along(modules)) {
    m <- modules[[i]]
    mm <- c(mm, sprintf('<module identifier="m%d"><title>%s</title><workflow_state>active</workflow_state><position>%d</position><require_sequential_progress>false</require_sequential_progress><items>', i, m$title, i))
    for (it in m$items) {
      n <- n + 1L
      mm <- c(mm, sprintf('<item identifier="i%d"><content_type>%s</content_type><workflow_state>active</workflow_state><title>%s</title><identifierref>r%d</identifierref>%s<position>%d</position><new_tab>%s</new_tab><indent>%s</indent></item>',
                          n, it$ctype, it$title, n, if (is.null(it$url)) "" else sprintf("<url>%s</url>", it$url), n, it$newtab %||% "false", it$indent %||% "0"))
      res <- c(res, sprintf('<resource identifier="r%d" type="%s" href="x%d.html"><file href="x%d.html"/></resource>', n,
                            if (it$ctype == "ExternalUrl") "imswl_xmlv1p1" else "webcontent", n, n))
      writeLines("x", file.path(d, sprintf("x%d.html", n)))
    }
    mm <- c(mm, "</items></module>")
  }
  writeLines(c(mm, "</modules>"), file.path(d, "course_settings", "module_meta.xml"))
  writeLines(c('<?xml version="1.0" encoding="UTF-8"?>', '<manifest xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imscp_v1p1"><resources>', res, '</resources></manifest>'),
             file.path(d, "imsmanifest.xml"))
  writeLines(c('<?xml version="1.0" encoding="UTF-8"?>', '<assignment xmlns="http://canvas.instructure.com/xsd/cccv1p0"><title>HW</title>',
               sprintf('<due_at>%s</due_at>', due), '<workflow_state>published</workflow_state><points_possible>50.0</points_possible></assignment>'),
             file.path(d, "a1", "assignment_settings.xml"))
  old <- setwd(d); on.exit(setwd(old), add = TRUE)
  utils::zip(zip_path, list.files(".", recursive = TRUE), flags = "-q -X")
  zip_path
}
