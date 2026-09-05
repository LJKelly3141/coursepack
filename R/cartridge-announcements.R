# ---- announcements -------------------------------------------------------
stage_announcements <- function(ann, stage) {
anns <- ann$announcements
ann_dir <- ann$body_dir
ann_tz <- ann$tz
#
# Optional, on the same pattern as the course card: no announcements.yml, no
# announcements, and nothing in this section runs.
#
# Canvas packages an announcement as TWO files plus two manifest resources,
# confirmed against a real round-trip export of the first course, which
# carried all seven of them:
#
#   <id>.xml       an imsdt_v1p1 <topic>: the title and the HTML body, nothing else
#   <metaid>.xml   a Canvas <topicMeta>: type, post time, workflow state
#
# The topic resource (type imsdt_xmlv1p1) declares a <dependency> on the meta
# resource, a learning-application-resource whose href is its own file, and the
# meta points back through <topic_id>. Nothing else references either: an
# announcement is not a module item and appears in no <organizations> tree.
# Canvas finds it by resource type alone, which is why the orphan check at the
# end has to admit these ids by name.
#
# Three things the export settles, each a trap:
#
#   1. <type>announcement</type> is the ONLY thing that makes it an announcement.
#      Leave it out or change it and Canvas imports a discussion topic students
#      can reply to.
#   2. <delayed_post_at> is UTC with NO zone marker. Midnight Central is stored
#      as 05:00:00 while daylight time is in force and 06:00:00 after it ends.
#      The offset is derived per date from the IANA zone in announcements.yml,
#      not hardcoded, so a spring course crossing the March boundary gets each
#      post right. Written in local time, a post lands the previous evening.
#   3. An announcement that posts on import has NO <delayed_post_at> element at
#      all, and workflow_state is `active` rather than `post_delayed`. The
#      welcome announcement in the export is exactly this case.
#
# The body files open with their own title as an <h2>. The export holds the
# title in <title> and the body WITHOUT that heading, so here the heading is
# checked against the declared title and then dropped from the body. Ship it in
# the body too and every announcement renders its title twice.

# Exactly three forms are accepted and everything else stops the build, because
# a value that fails to parse must never quietly become "post now":
#   immediately        posts on import; no delayed_post_at, state active
#   YYYY-MM-DD         midnight local at the start of that day
#   YYYY-MM-DD HH:MM   that local time
# Returns NULL for immediately, otherwise a POSIXct in the course zone.
ann_res  <- vapply(names(anns), function(k) gid("announcement",     k), "")
ann_meta <- vapply(names(anns), function(k) gid("announcementmeta", k), "")
ann_past <- character()

for (i in seq_along(anns)) {
  a <- anns[[i]]; k <- names(anns)[i]
  f <- file.path(ann_dir, a$body)
  if (!file.exists(f))
    stop("announcement '", k, "' names a body file that does not exist: ", f,
         "\n  The build does not skip it: a cartridge short of one announcement ",
         "looks finished until the morning it fails to appear.")
  body <- paste(readLines(f, warn = FALSE), collapse = "\n")

  # A leading <h2> is the body's own copy of the title. It must agree with the
  # declaration, so YAML and file cannot drift apart, and then it goes.
  h2_re <- "^\\s*<h2>([^<]*)</h2>\\s*"
  if (grepl(h2_re, body, perl = TRUE)) {
    # Group 1 out of the matched text only. Appending .*$ to reach the end of
    # the body does not work: without (?s) a dot stops at the first newline.
    h2 <- trimws(sub(h2_re, "\\1", regmatches(body, regexpr(h2_re, body, perl = TRUE)), perl = TRUE))
    if (!identical(h2, trimws(a$title)))
      stop("announcement '", k, "': the body's <h2> reads\n    ", h2,
           "\n  but announcements.yml declares\n    ", a$title,
           "\n  Canvas shows the declared title; the file's heading is the ",
           "check on it. Make them agree.")
    body <- sub(h2_re, "", body, perl = TRUE)
  }
  body <- trimws(body)
  if (!nzchar(body))
    stop("announcement '", k, "' has an empty body after its heading. An empty ",
         "announcement posts on schedule and says nothing.")

  when <- parse_when(a$post, ann$tz, k)
  if (!is.null(when)) {
    local_day <- as.Date(format(when, "%Y-%m-%d", tz = ann_tz))
    if (local_day < ann$first_day || local_day > ann$last_day)
      stop("announcement '", k, "' posts ", format(when, "%Y-%m-%d %H:%M", tz = ann_tz),
           " ", ann_tz, ", outside the term window ", ann$first_day, " to ", ann$last_day,
           " declared in announcements.yml.")
    if (when < Sys.time()) ann_past <- c(ann_past, k)
  }

  writef(file.path(stage, paste0(ann_res[[k]], ".xml")), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<topic xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imsdt_v1p1" ', XSI,
' xsi:schemaLocation="http://www.imsglobal.org/xsd/imsccv1p1/imsdt_v1p1',
'  http://www.imsglobal.org/profile/cc/ccv1p1/ccv1p1_imsdt_v1p1.xsd">\n',
'  <title>', xtext(a$title), '</title>\n',
'  <text texttype="text/html">', xtext(body), '</text>\n',
'</topic>'))

  # UTC, no zone suffix. format() with tz = "UTC" does the conversion from the
  # POSIXct's own zone, which is where the daylight-time arithmetic happens.
  delayed <- if (is.null(when)) '' else
    paste0('  <delayed_post_at>', format(when, "%Y-%m-%dT%H:%M:%S", tz = "UTC"),
           '</delayed_post_at>\n')

  writef(file.path(stage, paste0(ann_meta[[k]], ".xml")), paste0(
'<?xml version="1.0" encoding="UTF-8"?>\n',
'<topicMeta identifier="', ann_meta[[k]], '" ', CCV, '>\n',
'  <topic_id>', ann_res[[k]], '</topic_id>\n',
'  <title>', xtext(a$title), '</title>\n',
delayed,
'  <position>', i, '</position>\n',
'  <type>announcement</type>\n',
'  <discussion_type>threaded</discussion_type>\n',
'  <has_group_category>false</has_group_category>\n',
'  <workflow_state>', if (is.null(when)) 'active' else 'post_delayed', '</workflow_state>\n',
'  <module_locked>false</module_locked>\n',
'  <allow_rating>false</allow_rating>\n',
'  <only_graders_can_rate>false</only_graders_can_rate>\n',
'  <sort_by_rating>false</sort_by_rating>\n',
'  <sort_order>asc</sort_order>\n',
'  <sort_order_locked>false</sort_order_locked>\n',
'  <expanded>true</expanded>\n',
'  <expanded_locked>false</expanded_locked>\n',
'  <todo_date/>\n',
'</topicMeta>'))

  cat(sprintf("  announcement %-10s %s\n", k,
              if (is.null(when)) "posts on import"
              else paste0("posts ", format(when, "%a %d %b %Y %H:%M", tz = ann_tz),
                          " (", format(when, "%Y-%m-%dT%H:%M:%S", tz = "UTC"), " UTC)")))
}

# A past post time is legitimate for a test shell and for a rebuild, so it is
# reported rather than refused. What Canvas does with a post_delayed
# announcement whose time has already passed has NOT been verified by import;
# assume it posts at once, and do not re-import into a live course expecting
# the past ones to stay quiet.
if (length(ann_past))
  cat("  NOTE: ", length(ann_past), " announcement(s) are scheduled before this build: ",
      paste(ann_past, collapse = ", "), "\n", sep = "")

list(ann_res = ann_res, ann_meta = ann_meta, ann_past = ann_past)
}

# ---- announcements, read back from the staging tree ----------------------
check_announcements <- function(stage, ann, ann_res, p_fail) {
anns <- if (is.null(ann)) list() else ann$announcements
ann_tz <- if (is.null(ann)) NULL else ann$tz
ann_first <- if (is.null(ann)) NULL else ann$first_day
ann_last <- if (is.null(ann)) NULL else ann$last_day
#
# Everything here is read from the manifest and the files ON DISK, never from
# the R objects that wrote them, so it tests what ships rather than what was
# meant. Two directions throughout: every declared announcement must be in the
# manifest in full, and the manifest and disk must hold nothing beyond what was
# declared.
xread <- function(f) tryCatch({ x <- xml2::read_xml(f); xml2::xml_ns_strip(x); x },
                              error = function(e) NULL)
xt <- function(node, path) {
  n <- xml2::xml_find_first(node, path)
  if (inherits(n, "xml_missing")) NA_character_ else xml2::xml_text(n)
}
mx <- xread(file.path(stage, "imsmanifest.xml"))
topics <- if (is.null(mx)) list() else
  xml2::xml_find_all(mx, "//resources/resource[@type='imsdt_xmlv1p1']")
topic_ids <- xml2::xml_attr(topics, "identifier")

# Direction one: declared -> manifest.
if (length(topics) != length(anns))
  p_fail("announcements: ", length(anns), " declared, ", length(topics),
         " imsdt_xmlv1p1 resources in the manifest")
for (k in names(anns)) if (!ann_res[[k]] %in% topic_ids)
  p_fail("announcement '", k, "' is declared but has no topic resource in the manifest")

# Direction two: every topic in the manifest is complete, consistent, and
# actually an announcement.
metas_used <- character(); positions <- integer(); posted <- character()
for (t in topics) {
  tid  <- xml2::xml_attr(t, "identifier")
  deps <- xml2::xml_attr(xml2::xml_find_all(t, "dependency"), "identifierref")
  if (length(deps) != 1) {
    p_fail("announcement topic ", tid, " has ", length(deps), " dependencies; Canvas needs exactly one, on its meta"); next
  }
  mid <- deps
  mres <- xml2::xml_find_first(mx, sprintf("//resources/resource[@identifier='%s']", mid))
  if (inherits(mres, "xml_missing")) { p_fail("announcement topic ", tid, " depends on undeclared resource ", mid); next }
  if (!identical(xml2::xml_attr(mres, "type"), "associatedcontent/imscc_xmlv1p1/learning-application-resource"))
    p_fail("announcement meta ", mid, " has the wrong resource type: ", xml2::xml_attr(mres, "type"))
  if (!identical(xml2::xml_attr(mres, "href"), paste0(mid, ".xml")))
    p_fail("announcement meta ", mid, " href is not its own file")
  metas_used <- c(metas_used, mid)

  topic <- xread(file.path(stage, paste0(tid, ".xml")))
  meta  <- xread(file.path(stage, paste0(mid, ".xml")))
  if (is.null(topic)) { p_fail("announcement topic file unreadable: ", tid, ".xml"); next }
  if (is.null(meta))  { p_fail("announcement meta file unreadable: ",  mid, ".xml"); next }
  if (!identical(xml2::xml_name(topic), "topic")) p_fail(tid, ".xml is not a <topic>")
  if (!identical(xml2::xml_name(meta), "topicMeta")) p_fail(mid, ".xml is not a <topicMeta>")
  if (!identical(xml2::xml_attr(meta, "identifier"), mid))
    p_fail("announcement meta ", mid, " carries identifier ", xml2::xml_attr(meta, "identifier"))
  if (!identical(xt(meta, "topic_id"), tid))
    p_fail("announcement meta ", mid, " points back at ", xt(meta, "topic_id"), ", not its topic ", tid)

  # THE line that makes it an announcement rather than a discussion.
  if (!identical(xt(meta, "type"), "announcement"))
    p_fail("announcement ", tid, " would import as a DISCUSSION: <type> is ",
           if (is.na(xt(meta, "type"))) "absent" else xt(meta, "type"))

  if (!identical(xt(topic, "title"), xt(meta, "title")))
    p_fail("announcement ", tid, " topic and meta titles differ")
  if (is.na(xt(topic, "title")) || !nzchar(trimws(xt(topic, "title"))))
    p_fail("announcement ", tid, " has an empty title")
  body <- xt(topic, "text")
  if (is.na(body) || !nzchar(trimws(body))) p_fail("announcement ", tid, " has an empty body")
  else if (grepl("^\\s*<h2>", body)) p_fail("announcement ", tid, " body still opens with its <h2>; the title would render twice")

  # Post time and state must agree, and the time must be a bare UTC stamp.
  dp <- xt(meta, "delayed_post_at"); ws <- xt(meta, "workflow_state")
  if (is.na(dp)) {
    if (!identical(ws, "active")) p_fail("announcement ", tid, " has no delayed_post_at but workflow_state ", ws)
  } else {
    if (!identical(ws, "post_delayed")) p_fail("announcement ", tid, " has delayed_post_at but workflow_state ", ws)
    if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$", dp))
      p_fail("announcement ", tid, " delayed_post_at is not a bare UTC timestamp: ", dp)
    else {
      # Convert what is on disk back to the course zone and test the window, so
      # the check covers the conversion and not just the input.
      utc <- as.POSIXct(dp, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC")
      day <- as.Date(format(utc, "%Y-%m-%d", tz = ann_tz))
      if (day < ann_first || day > ann_last)
        p_fail("announcement ", tid, " posts ", format(utc, "%Y-%m-%d %H:%M", tz = ann_tz),
               " ", ann_tz, ", outside the term window")
      posted <- c(posted, dp)
    }
  }
  positions <- c(positions, suppressWarnings(as.integer(xt(meta, "position"))))
}
if (anyDuplicated(metas_used))
  p_fail("announcement metas shared between topics: ", paste(unique(metas_used[duplicated(metas_used)]), collapse = ", "))
if (length(topics) && !identical(sort(positions), seq_along(topics)))
  p_fail("announcement positions are not 1..", length(topics), ": ", paste(positions, collapse = ","))
if (anyDuplicated(posted))
  p_fail("two announcements post at the same instant: ", paste(unique(posted[duplicated(posted)]), collapse = ", "))

# Every <topicMeta> on disk must belong to a topic in the manifest. A meta with
# no topic is inert, but a topic with no meta is a discussion with no schedule,
# and both mean the two halves came apart somewhere.
metas_on_disk <- character()
for (f in list.files(stage, pattern = "\\.xml$", full.names = TRUE)) {
  x <- xread(f)
  if (!is.null(x) && identical(xml2::xml_name(x), "topicMeta"))
    metas_on_disk <- c(metas_on_disk, tools::file_path_sans_ext(basename(f)))
}
for (m in setdiff(metas_on_disk, metas_used)) p_fail("topicMeta on disk with no topic depending on it: ", m)
cat(sprintf("  announcements declared=%d  topics=%d  metas=%d  scheduled=%d  immediate=%d\n",
            length(anns), length(topics), length(metas_on_disk), length(posted),
            length(topics) - length(posted)))

}
