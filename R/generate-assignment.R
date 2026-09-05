# Assignments whose body is written in the manifest.
#
# An assignment definition carrying `description:` holds its own HTML. Nothing
# is extracted from the textbook and no quiz source is read: what the key says
# is what a student sees. It is the form a memo, a draft or a participation
# task takes, where the directions are two sentences and live nowhere else.
#
# The settings file is the SAME one every other assignment gets. There is one
# assignment_settings.xml template in this package and it is the shape a real
# Canvas export writes; a second template for one body form would drift from it
# and the byte gate would stop meaning anything. What a `description:`
# assignment adds is that four of that template's values become the
# definition's own rather than the course's defaults: `points`, `grading_type`,
# `submission_types` and `allowed_extensions`. Those keys are read for every
# assignment, because the writer is shared; an assignment that declares none of
# them is written exactly as before.

# The four grading types Canvas accepts on an assignment. Anything else stops:
# Canvas silently falls back to points, so a typo costs a pass/fail assignment
# its whole grading scheme and reports nothing.
GRADING_TYPES <- c("points", "pass_fail", "percent", "letter_grade")

grading_type_for <- function(a, k) {
  v <- as.character(a$grading_type %||% "points")
  if (length(v) != 1L || !v %in% GRADING_TYPES)
    stop("assignment '", k, "': grading_type must be points, pass_fail, percent, ",
         "or letter_grade, not ", paste(v, collapse = " "), call. = FALSE)
  v
}

# A YAML value that may be written as one string or as a list of them. Canvas
# reads both fields as a comma-separated list, so a course may write
# `submission_types: [online_upload, online_text_entry]` or the joined string
# and get the same cartridge.
csv_value <- function(v) {
  if (is.null(v)) return("")
  paste(vapply(unlist(v), as.character, ""), collapse = ",")
}

# The HTML body of a `description:` assignment, exactly as the definition wrote
# it. An empty description stops: an assignment with no directions imports into
# Canvas without complaint and looks like a finished assignment nobody can do.
description_body <- function(a, k) {
  html <- trimws(paste(vapply(unlist(a$description), as.character, ""), collapse = "\n"))
  if (!nzchar(html))
    stop("assignment '", k, "' declares description: but it is empty. An ",
         "assignment with no directions imports into Canvas without complaint.",
         call. = FALSE)
  html
}

# THE ONE assignment_settings.xml TEMPLATE. Shaped against a real Canvas
# export and pinned by the byte gate. Every element below is one the export
# carries; the Python generator this ports emitted several more on a generated
# assignment (peer review counts, moderated grading, a post policy of its own),
# and those are deliberately not written here, because the export this package
# is shaped against does not carry them.
assignment_settings_xml <- function(rid, title, due_xml, ag_id, state, allowed_extensions,
                                    points, grading_type, submission_types, position) {
  paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<assignment identifier="', rid, '" ', CCV, '>\n',
'  <title>', xesc(title), '</title>\n',
due_xml, '  <lock_at/>\n  <unlock_at/>\n',
'  <module_locked>false</module_locked>\n',
'  <assignment_group_identifierref>', ag_id, '</assignment_group_identifierref>\n',
'  <workflow_state>', state, '</workflow_state>\n',
'  <assignment_overrides>\n  </assignment_overrides>\n',
'  <allowed_extensions>', allowed_extensions, '</allowed_extensions>\n',
'  <has_group_category>false</has_group_category>\n',
'  <points_possible>', format(points, nsmall = 1), '</points_possible>\n',
'  <grading_type>', grading_type, '</grading_type>\n',
'  <submission_types>', submission_types, '</submission_types>\n',
'  <position>', position, '</position>\n',
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
'</assignment>')
}
