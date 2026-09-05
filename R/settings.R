CANVAS_SETTINGS_KEYS <- c(
  "course_code",
  "is_public",
  "indexed",
  "default_view",
  "license",
  "grading_standard_enabled",
  "group_weighting_scheme",
  "restrict_enrollments_to_course_dates",
  "allow_student_wiki_edits",
  "restrict_student_future_view",
  "restrict_student_past_view"
)

course_settings_xml <- function(course, tile, has_grading_standard) {
  cs <- course$canvas %||% list()
  unknown <- setdiff(names(cs), CANVAS_SETTINGS_KEYS)
  if (length(unknown))
    stop("unknown canvas: key: ", unknown[[1]])
  if (is.null(cs$course_code))
    stop("canvas: course_code is required")

  setting_xml <- function(key) {
    value <- cs[[key]]
    if (is.logical(value)) value <- tolower(as.character(value))
    paste0("  <", key, ">", xesc(value), "</", key, ">\n")
  }

  lines <- paste0(
    '<?xml version="1.0" encoding="UTF-8"?>\n',
    '<course identifier="', course_identifier(course), '" ', CCV, '>\n',
    '  <title>', xesc(course$title), '</title>\n'
  )
  for (key in CANVAS_SETTINGS_KEYS) {
    if (is.null(cs[[key]])) next
    lines <- paste0(lines, setting_xml(key))
    if (key == "course_code" && isTRUE(tile$has_tile))
      lines <- paste0(lines, '  <image_identifier_ref>', tile$tile_res,
                      '</image_identifier_ref>\n')
    if (key == "grading_standard_enabled" && isTRUE(has_grading_standard))
      lines <- paste0(lines, '  <grading_standard_identifier_ref>',
                      gid("gradingstandard", course$grading_standard$title),
                      '</grading_standard_identifier_ref>\n')
  }
  paste0(lines, '</course>')
}
