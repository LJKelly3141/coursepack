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
