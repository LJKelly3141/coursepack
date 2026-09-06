# Quizzes generated from a JSON question bank.
#
# A quiz definition carrying a `bank:` block names the bank directory, the
# chapters to pool, and how many items to draw from each group. The three files
# and two manifest resources Canvas wants are the same ones R/cartridge-quiz.R
# documents for a quiz that arrives as a QTI zip; what changes here is where the
# questions come from. Every byte shape below was copied from a real Canvas
# export, and the port is checked item for item against the generator it came
# from in tests/testthat/test-generate-quiz.R.
#
# Question stems are HTML already (a bank writes <br>, <i> and <table> into
# them), so a stem is wrapped in <div> and escaped exactly ONCE, as XML text.
# Canvas unescapes the node and renders the HTML that remains. Escaping it twice
# shows students the markup; not escaping it at all breaks the XML. Options and
# feedback are text/plain and escaped once as well.
#
# Refusals stop the build. A quiz that silently under-draws, or a question whose
# figure is missing, is a defect students meet and nobody else sees. The one
# advisory is a figure with no alt text: the item still renders, so the build
# carries on and the author is told what to write.

CANVAS_NS <- "http://canvas.instructure.com/xsd/cccv1p0"
XSI_URI <- "http://www.w3.org/2001/XMLSchema-instance"
CANVAS_SCHEMA <- paste0(CANVAS_NS, " https://canvas.instructure.com/xsd/cccv1p0.xsd")
QTI_NS <- "http://www.imsglobal.org/xsd/ims_qtiasiv1p2"
# The Canvas-flavoured group file and the flat Common Cartridge copy point at
# different schemas. Both strings are verbatim from the export.
QTI_SCHEMA_CANVAS <- paste0(QTI_NS, " http://www.imsglobal.org/xsd/ims_qtiasiv1p2p1.xsd")
QTI_SCHEMA_CC <- paste0(QTI_NS, " http://www.imsglobal.org/profile/cc/ccv1p1/ccv1p1_qtiasiv1p2p1_v1p0.xsd")

TYPE_ASSESSMENT <- "imsqti_xmlv1p2/imscc_xmlv1p1/assessment"
TYPE_LAR <- "associatedcontent/imscc_xmlv1p1/learning-application-resource"

QUIZ_IMAGE_DIR <- "quiz_images"           # under web_resources/ in the cartridge
QUIZ_FILEBASE <- "$IMS-CC-FILEBASE$"      # Canvas rewrites this to the course files URL

# ---- helpers -------------------------------------------------------------

# Replace every {name} token in a template with its value. One pass per name,
# matched literally, so a value that happens to contain a brace is left alone.
# Values whose content comes from the bank are substituted last for the same
# reason: nothing a question stem holds can name another token.
fill <- function(template, values) {
  for (n in names(values))
    template <- gsub(paste0("{", n, "}"), values[[n]], template, fixed = TRUE)
  template
}

# The five characters an HTML attribute value cannot hold raw. Used for the src
# and the alt of a figure inside a stem, which are HTML attributes inside the
# HTML the stem carries, before the whole stem is escaped once as XML text.
html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub('"', "&quot;", x, fixed = TRUE)
  gsub("'", "&#x27;", x, fixed = TRUE)
}

# ---- QTI items -----------------------------------------------------------

# Small integer answer ids, deterministic AND unique within the item.
#
# Canvas uses these to match a response to an option. The plain hash collides
# about once in 9000 pairs, which was enough to ship an item with two options
# sharing an id. On a collision the key is salted and rehashed until the id is
# free, so a rebuild still gives the same ids and no two options in one item
# ever share one.
answer_ids <- function(ident, letters) {
  used <- integer()
  out <- list()
  for (k in letters) {
    salt <- 0L
    repeat {
      key <- if (salt == 0L) paste0(ident, ":", k) else paste0(ident, ":", k, ":", salt)
      v <- strtoi(substr(digest::digest(key, algo = "md5", serialize = FALSE), 1L, 6L), 16L) %% 9000L + 1000L
      if (!v %in% used) break
      salt <- salt + 1L
    }
    used <- c(used, v)
    out[[k]] <- v
  }
  out
}

TABLE_RE <- "(?is)<table\\b[^>]*>.*?</table>"
ROW_RE <- "(?is)<tr\\b[^>]*>.*?</tr>"

# Give a data table the header semantics a screen reader needs.
#
# Bank stems get authored in batches, and a batch that wrote <th> cells with no
# scope reads as a grid of unlabelled numbers. Canvas renders the stem HTML as
# it arrives, so this normalizes every table at generation time: every <th> in
# the first row gets scope="col" if it has none, and when that first row is all
# header cells it is wrapped in <thead> with the remaining rows in <tbody>. Cell
# contents, <td> cells and existing scope values are untouched.
normalize_table <- function(table_html) {
  if (!grepl("(?i)<caption\\b", table_html, perl = TRUE)) {
    # A visible, short caption. Canvas may strip class and style attributes from
    # imported HTML, so a screen-reader-only caption cannot be relied on; a
    # short visible one names the table for everyone.
    k <- regexpr(">", table_html, fixed = TRUE)
    table_html <- paste0(substr(table_html, 1L, k), "<caption>Data for this question</caption>",
                         substring(table_html, k + 1L))
  }
  if (grepl("(?i)<thead\\b", table_html, perl = TRUE)) return(table_html)
  first <- regexpr(ROW_RE, table_html, perl = TRUE)
  if (first < 0L) return(table_html)
  fstart <- as.integer(first)
  fend <- fstart + attr(first, "match.length") - 1L
  first_html <- gsub("(?i)<th\\b(?![^>]*\\bscope=)([^>]*)>", '<th scope="col"\\1>',
                     substr(table_html, fstart, fend), perl = TRUE)
  cells <- regmatches(first_html, gregexpr("(?i)<t[hd]\\b", first_html, perl = TRUE))[[1]]
  all_th <- length(cells) > 0L && all(grepl("(?i)^<th", cells, perl = TRUE))
  if (!all_th)
    return(paste0(substr(table_html, 1L, fstart - 1L), first_html, substring(table_html, fend + 1L)))
  open_tag_end <- as.integer(regexpr(">", table_html, fixed = TRUE))
  cap <- regexpr("(?is)^<caption\\b.*?</caption>", substring(table_html, open_tag_end + 1L), perl = TRUE)
  if (cap > 0L) open_tag_end <- open_tag_end + attr(cap, "match.length")
  prefix <- substr(table_html, 1L, open_tag_end)
  between <- substr(table_html, open_tag_end + 1L, fstart - 1L)
  rest <- substring(table_html, fend + 1L)
  close_at <- utils::tail(as.integer(gregexpr("(?i)</table>", rest, perl = TRUE)[[1]]), 1L)
  body_rows <- substr(rest, 1L, close_at - 1L)
  tail_html <- substring(rest, close_at)
  paste0(prefix, between, "<thead>", first_html, "</thead>",
         if (nzchar(trimws(body_rows))) paste0("<tbody>", body_rows, "</tbody>") else body_rows,
         tail_html)
}

#' Normalize the tables in a question stem
#'
#' Every `<table>` in `html` is given a caption if it has none, `scope="col"` on
#' every unscoped `<th>` of its first row, and a `<thead>` and `<tbody>` split
#' when that first row is all header cells. A table that already carries those
#' is returned unchanged, so running this twice changes nothing.
#'
#' Exported because a bank-authoring session normalizes a stem the same way the
#' generator will, and comparing the two is how an author sees what the build
#' will change.
#'
#' @param html A question stem, or any HTML fragment.
#' @return The same HTML with every table normalized.
#' @examples
#' html <- paste0("<p>Use the table.</p><table><tr><th>x</th><th>y</th></tr>",
#'                "<tr><td>1</td><td>2</td></tr></table>")
#' out <- normalize_tables(html)
#' # The first row was all header cells, so it became a scoped thead.
#' grepl("<thead>", out, fixed = TRUE)
#'
#' # Running it a second time changes nothing further.
#' identical(normalize_tables(out), out)
#' @export
normalize_tables <- function(html) {
  m <- gregexpr(TABLE_RE, html, perl = TRUE)
  hits <- regmatches(html, m)[[1]]
  if (!length(hits)) return(html)
  regmatches(html, m) <- list(unname(vapply(hits, normalize_table, "")))
  html
}

# The question stem as HTML. Stems in the bank are HTML already; tables are
# normalized for header semantics on the way through.
stem_html <- function(q, image_base) {
  body <- normalize_tables(trimws(as.character(q$question)))
  image <- as.character(q$image %||% "")
  if (nzchar(image)) {
    alt <- html_escape(as.character(q$figure$alt %||% ""))
    src <- html_escape(paste0(image_base, "/", image))
    body <- paste0(body, '<br><img src="', src, '" alt="', alt, '" ',
                   'style="max-width: 100%; height: auto;">')
  }
  paste0("<div>", body, "</div>")
}

# One QTI <item>. Byte shape matches the export's items.
#
# meta_fields is the named character vector of fieldlabel to fieldentry pairs
# for the itemmetadata block: the Canvas group file carries question_type,
# points_possible, original_answer_ids and assessment_question_identifierref;
# the flat Common Cartridge copy carries only cc_profile. `ids` are the answer
# ids to use; by default they are derived from `ident`.
item_xml <- function(ident, title, q, meta_fields, image_base, indent = "        ", ids = NULL) {
  opts <- q$options
  if (is.null(ids)) ids <- answer_ids(ident, names(opts))
  correct <- ids[[as.character(q$answer)]]
  feedback <- trimws(as.character(q$explanation %||% ""))
  i <- indent

  meta <- paste0(
    i, "      <qtimetadatafield>\n",
    i, "        <fieldlabel>", xtext(names(meta_fields)), "</fieldlabel>\n",
    i, "        <fieldentry>", xtext(unname(meta_fields)), "</fieldentry>\n",
    i, "      </qtimetadatafield>\n", collapse = "")

  labels <- paste0(
    i, '        <response_label ident="', vapply(names(opts), function(k) as.character(ids[[k]]), ""), '">\n',
    i, "          <material>\n",
    i, '            <mattext texttype="text/plain">', xtext(vapply(opts, as.character, "")), "</mattext>\n",
    i, "          </material>\n",
    i, "        </response_label>\n", collapse = "")

  # General feedback is present only when the bank has an explanation. The
  # export omits both the <other/> condition and <itemfeedback> otherwise.
  fb_cond <- if (nzchar(feedback)) paste0(
    i, '    <respcondition continue="Yes">\n',
    i, "      <conditionvar>\n",
    i, "        <other/>\n",
    i, "      </conditionvar>\n",
    i, '      <displayfeedback feedbacktype="Response" linkrefid="general_fb"/>\n',
    i, "    </respcondition>\n") else ""
  fb_block <- if (nzchar(feedback)) paste0(
    i, '  <itemfeedback ident="general_fb">\n',
    i, "    <flow_mat>\n",
    i, "      <material>\n",
    i, '        <mattext texttype="text/plain">', xtext(feedback), "</mattext>\n",
    i, "      </material>\n",
    i, "    </flow_mat>\n",
    i, "  </itemfeedback>\n") else ""

  # The stem is HTML inside an XML text node. Escape it ONCE, as XML text;
  # Canvas unescapes the node and renders the HTML that remains.
  stem <- xtext(stem_html(q, image_base))

  paste0(
    i, '<item ident="', ident, '" title="', xesc(title), '">\n',
    i, "  <itemmetadata>\n",
    i, "    <qtimetadata>\n",
    meta,
    i, "    </qtimetadata>\n",
    i, "  </itemmetadata>\n",
    i, "  <presentation>\n",
    i, "    <material>\n",
    i, '      <mattext texttype="text/html">', stem, "</mattext>\n",
    i, "    </material>\n",
    i, '    <response_lid ident="response1" rcardinality="Single">\n',
    i, "      <render_choice>\n",
    labels,
    i, "      </render_choice>\n",
    i, "    </response_lid>\n",
    i, "  </presentation>\n",
    i, "  <resprocessing>\n",
    i, "    <outcomes>\n",
    i, '      <decvar maxvalue="100" minvalue="0" varname="SCORE" vartype="Decimal"/>\n',
    i, "    </outcomes>\n",
    fb_cond,
    i, '    <respcondition continue="No">\n',
    i, "      <conditionvar>\n",
    i, '        <varequal respident="response1">', correct, "</varequal>\n",
    i, "      </conditionvar>\n",
    i, '      <setvar action="Set" varname="SCORE">100</setvar>\n',
    i, "    </respcondition>\n",
    i, "  </resprocessing>\n",
    fb_block,
    i, "</item>\n")
}

# ---- templates -----------------------------------------------------------
#
# Copied element for element from a real Canvas export. The two files written
# whole end at their closing tag with no trailing newline, because writef()
# writes one; GROUP keeps its own, because it is concatenated rather than
# written.

QUIZ_META <- '<?xml version="1.0" encoding="UTF-8"?>
<quiz identifier="{quiz_id}" xmlns="{ns}" xmlns:xsi="{xsi}" xsi:schemaLocation="{schema}">
  <title>{title}</title>
  <description>{description}</description>
  <due_at>{due_at}</due_at>
{window_xml}  <shuffle_answers>{shuffle_answers}</shuffle_answers>
  <scoring_policy>{scoring_policy}</scoring_policy>
  <hide_results></hide_results>
  <quiz_type>{quiz_type}</quiz_type>
  <points_possible>{points}</points_possible>
  <require_lockdown_browser>false</require_lockdown_browser>
  <require_lockdown_browser_for_results>false</require_lockdown_browser_for_results>
  <require_lockdown_browser_monitor>false</require_lockdown_browser_monitor>
  <lockdown_browser_monitor_data/>
  <show_correct_answers>{show_correct_answers}</show_correct_answers>
  <anonymous_submissions>false</anonymous_submissions>
  <could_be_locked>true</could_be_locked>
  <disable_timer_autosubmission>false</disable_timer_autosubmission>
  <allowed_attempts>{allowed_attempts}</allowed_attempts>
  <one_question_at_a_time>{one_question_at_a_time}</one_question_at_a_time>
  <cant_go_back>false</cant_go_back>
  <available>{available}</available>
  <one_time_results>false</one_time_results>
  <show_correct_answers_last_attempt>false</show_correct_answers_last_attempt>
  <only_visible_to_overrides>false</only_visible_to_overrides>
  <module_locked>false</module_locked>
  <assignment identifier="{assignment_id}">
    <title>{title}</title>
    <due_at>{due_at}</due_at>
    <lock_at>{lock_at}</lock_at>
    <unlock_at>{unlock_at}</unlock_at>
    <module_locked>false</module_locked>
    <all_day_date>{all_day_date}</all_day_date>
    <assignment_group_identifierref>{group_id}</assignment_group_identifierref>
    <workflow_state>{workflow_state}</workflow_state>
    <assignment_overrides>
    </assignment_overrides>
    <quiz_identifierref>{quiz_id}</quiz_identifierref>
    <allowed_extensions></allowed_extensions>
    <has_group_category>false</has_group_category>
    <points_possible>{points}</points_possible>
    <grading_type>points</grading_type>
    <all_day>false</all_day>
    <submission_types>online_quiz</submission_types>
    <position>{position}</position>
    <turnitin_enabled>false</turnitin_enabled>
    <vericite_enabled>false</vericite_enabled>
    <peer_review_count>0</peer_review_count>
    <peer_reviews>false</peer_reviews>
    <automatic_peer_reviews>false</automatic_peer_reviews>
    <anonymous_peer_reviews>false</anonymous_peer_reviews>
    <grade_group_students_individually>false</grade_group_students_individually>
    <freeze_on_copy>false</freeze_on_copy>
    <omit_from_final_grade>false</omit_from_final_grade>
    <hide_in_gradebook>false</hide_in_gradebook>
    <intra_group_peer_reviews>false</intra_group_peer_reviews>
    <only_visible_to_overrides>false</only_visible_to_overrides>
    <post_to_sis>false</post_to_sis>
    <moderated_grading>false</moderated_grading>
    <grader_count>0</grader_count>
    <grader_comments_visible_to_graders>true</grader_comments_visible_to_graders>
    <anonymous_grading>false</anonymous_grading>
    <graders_anonymous_to_graders>false</graders_anonymous_to_graders>
    <grader_names_visible_to_final_grader>true</grader_names_visible_to_final_grader>
    <anonymous_instructor_annotations>false</anonymous_instructor_annotations>
    <post_policy>
      <post_manually>false</post_manually>
    </post_policy>
  </assignment>
  <assignment_group_identifierref>{group_id}</assignment_group_identifierref>
  <assignment_overrides>
  </assignment_overrides>
</quiz>'

QTI_GROUPED <- '<?xml version="1.0" encoding="UTF-8"?>
<questestinterop xmlns="{ns}" xmlns:xsi="{xsi}" xsi:schemaLocation="{schema}">
  <assessment ident="{quiz_id}" title="{title}">
    <qtimetadata>
      <qtimetadatafield>
        <fieldlabel>cc_maxattempts</fieldlabel>
        <fieldentry>{max_attempts}</fieldentry>
      </qtimetadatafield>
    </qtimetadata>
    <section ident="root_section">
{groups}    </section>
  </assessment>
</questestinterop>'

QTI_FLAT <- '<?xml version="1.0" encoding="UTF-8"?>
<questestinterop xmlns="{ns}" xmlns:xsi="{xsi}" xsi:schemaLocation="{schema}">
  <assessment ident="{quiz_id}" title="{title}">
    <qtimetadata>
      <qtimetadatafield>
        <fieldlabel>cc_profile</fieldlabel>
        <fieldentry>cc.exam.v0p1</fieldentry>
      </qtimetadatafield>
      <qtimetadatafield>
        <fieldlabel>qmd_assessmenttype</fieldlabel>
        <fieldentry>Examination</fieldentry>
      </qtimetadatafield>
      <qtimetadatafield>
        <fieldlabel>qmd_scoretype</fieldlabel>
        <fieldentry>Percentage</fieldentry>
      </qtimetadatafield>
      <qtimetadatafield>
        <fieldlabel>cc_maxattempts</fieldlabel>
        <fieldentry>{max_attempts}</fieldentry>
      </qtimetadatafield>
    </qtimetadata>
    <section ident="root_section">
{items}    </section>
  </assessment>
</questestinterop>'

GROUP <- '      <section ident="{ident}" title="{title}">
        <selection_ordering>
          <selection>
            <selection_number>{n}</selection_number>
            <selection_extension>
              <points_per_item>1.0</points_per_item>
            </selection_extension>
          </selection>
        </selection_ordering>
{items}      </section>
'

# ---- groups and draws ----------------------------------------------------

# Turn a section whose draw is a list into that many question groups.
#
# A reviewer sometimes rules that two items in one section must not land in the
# same quiz. Canvas draws at random inside a group, so the only way to honor
# that is to put the two items in different groups. The section's entry in
# `draws:` becomes a list, one draw per part, and `splits:` names the section
# with one id list per part. Every id in the section must appear in exactly one
# part.
expand_splits <- function(groups, raw_draws, splits, title) {
  out_groups <- list()
  out_draws <- integer()
  used <- character()
  for (gi in seq_along(groups)) {
    g <- groups[[gi]]
    d <- raw_draws[[gi]]
    if (!is.list(d)) {
      out_groups[[length(out_groups) + 1L]] <- g
      out_draws <- c(out_draws, as.integer(d))
      next
    }
    parts <- splits[[g$name]]
    if (is.null(parts))
      stop(title, ": draws for Ch. ", g$ch, " - ", g$name,
           " is a list but splits has no entry for that section", call. = FALSE)
    if (length(parts) != length(d))
      stop(title, ": Ch. ", g$ch, " - ", g$name, " has ", length(d), " draws but ",
           length(parts), " id lists in splits", call. = FALSE)
    used <- c(used, g$name)
    ids_in_section <- vapply(g$qs, function(x) as.integer(x$id), 0L)
    seen <- integer()
    for (k in seq_along(parts)) {
      part_ids <- as.integer(unlist(parts[[k]]))
      absent <- part_ids[!part_ids %in% ids_in_section]
      if (length(absent))
        stop(title, ": Ch. ", g$ch, " - ", g$name, " part ", k,
             " names ids not in the section: ", paste(absent, collapse = ", "), call. = FALSE)
      dup <- part_ids[part_ids %in% seen]
      if (length(dup))
        stop(title, ": Ch. ", g$ch, " - ", g$name, " lists ids in two parts: ",
             paste(dup, collapse = ", "), call. = FALSE)
      seen <- c(seen, part_ids)
      out_groups[[length(out_groups) + 1L]] <- list(
        ch = g$ch, name = paste0(g$name, " (part ", k, ")"),
        qs = g$qs[vapply(g$qs, function(x) as.integer(x$id) %in% part_ids, TRUE)])
      out_draws <- c(out_draws, as.integer(d[[k]]))
    }
    left <- ids_in_section[!ids_in_section %in% seen]
    if (length(left))
      stop(title, ": Ch. ", g$ch, " - ", g$name, " splits leave ids out: ",
           paste(left, collapse = ", "), call. = FALSE)
  }
  unused <- setdiff(names(splits), used)
  if (length(unused))
    stop(title, ": splits names sections whose draw is not a list: ",
         paste(unused, collapse = ", "), call. = FALSE)
  list(groups = out_groups, draws = out_draws)
}

#' The question groups a `bank:` block draws from
#'
#' Reads every chapter the block names and returns the groups in chapter then
#' section order, with the flat draws that go with them. With
#' `group_by: chapter` each chapter's sections are pooled into one group named
#' by the bank title, and `draws:` has one entry per chapter instead; a
#' comprehensive exam uses that so every section of a chapter stays in play
#' while the exam draws only a few items from it.
#'
#' Every refusal the generator makes is made here, before anything is written:
#' no chapters, no points, an unknown `group_by:`, a draw count that does not
#' match the groups (the message lists the expected order), draws that do not
#' sum to `points:`, a negative draw, and a draw larger than its group.
#'
#' Exported because the printed form of a quiz draws from the same groups, and
#' because an author can ask what a block would pool without building anything.
#'
#' @param spec A `bank:` block: `dir`, `chapters`, `draws`, `splits`,
#'   `group_by`, `points`.
#' @param proj Course project root; `dir` is read relative to it.
#' @param title The quiz title, used to prefix every refusal.
#' @return `list(groups, draws)`. `groups` is a list of
#'   `list(ch, name, qs)`; `draws` is an integer vector the same length.
#' @examples
#' proj <- tempfile("course-")
#' dir.create(file.path(proj, "questions"), recursive = TRUE)
#' item <- function(id, answer) sprintf(
#'   '{"id": %d, "type": "multiple_choice", "question": "Which one?",
#'     "options": {"A": "the first", "B": "the second"}, "answer": "%s"}',
#'   id, answer)
#' writeLines(sprintf('{"chapter": 1, "title": "Sample Chapter", "sections":
#'   [{"section": "1.1 Ideas", "questions": [%s, %s]}]}',
#'   item(1, "A"), item(2, "B")),
#'   file.path(proj, "questions", "chapter_01.json"))
#' spec <- list(dir = "questions", chapters = 1, draws = 2, points = 2)
#' drawn <- bank_groups(spec, proj, "Module 1 Quiz")
#' drawn$draws
#' vapply(drawn$groups, function(g) g$name, "")
#' unlink(proj, recursive = TRUE)
#' @export
bank_groups <- function(spec, proj, title) {
  bank <- as.character(spec$dir %||% "questions")
  chapters <- as.integer(unlist(spec$chapters %||% list()))
  raw_draws <- spec$draws %||% list()
  splits <- spec$splits %||% list()
  points <- spec$points
  if (!length(chapters)) stop(title, ": bank.chapters is empty", call. = FALSE)
  if (is.null(points)) stop(title, ": bank.points is required", call. = FALSE)
  points <- as.numeric(points)

  # Collect (chapter, section name, questions) in chapter then section order.
  group_by <- as.character(spec$group_by %||% "section")
  if (!group_by %in% c("section", "chapter"))
    stop(title, ": bank.group_by must be section or chapter, not ", group_by, call. = FALSE)
  groups <- list()
  for (ch in chapters) {
    bk <- read_bank(file.path(proj, bank), ch)
    if (identical(group_by, "chapter")) {
      pooled <- unlist(lapply(bk$sections %||% list(), function(s) s$questions %||% list()),
                       recursive = FALSE)
      groups[[length(groups) + 1L]] <- list(
        ch = ch, name = trimws(as.character(bk$title %||% paste("Chapter", ch))), qs = pooled)
      next
    }
    for (s in bk$sections %||% list())
      groups[[length(groups) + 1L]] <- list(
        ch = ch, name = trimws(as.character(s$section)), qs = s$questions %||% list())
  }
  if (length(raw_draws) != length(groups)) {
    nm <- vapply(groups, function(g) paste0("Ch. ", g$ch, " - ", g$name), "")
    stop(title, ": ", length(raw_draws), " draws given for ", length(groups), " bank ",
         if (identical(group_by, "chapter")) "chapters" else "sections",
         ". One draw per group, in this order: ", paste(nm, collapse = ", "), call. = FALSE)
  }
  out <- expand_splits(groups, raw_draws, splits, title)
  if (sum(out$draws) != points)
    stop(title, ": draws sum to ", sum(out$draws), " but points is ", sprintf("%g", points),
         "; points_per_item is 1.0 so they must match", call. = FALSE)
  for (gi in seq_along(out$groups)) {
    g <- out$groups[[gi]]
    n <- out$draws[[gi]]
    if (n < 0L)
      stop(title, ": negative draw for Ch. ", g$ch, " - ", g$name, call. = FALSE)
    if (n > length(g$qs))
      stop(title, ": Ch. ", g$ch, " - ", g$name, " has ", length(g$qs),
           " questions, cannot draw ", n, call. = FALSE)
  }
  out
}

# An availability boundary from the bank block, written in the course zone as
# "YYYY-MM-DD HH:MM:SS" and returned as the UTC stamp Canvas stores. Empty when
# unset. A quiz with unlock_at cannot be opened before that moment even if it is
# published, which is the guarantee an exam needs.
window_utc <- function(value, tz, title, field) {
  if (is.null(value)) return("")
  v <- as.character(value)
  if (!length(v) || is.na(v[1]) || !nzchar(v[1])) return("")
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$", v[1]))
    stop(title, ": ", field, " must be 'YYYY-MM-DD HH:MM:SS' in the course timezone, not ",
         v[1], call. = FALSE)
  local_to_utc(substr(v[1], 1L, 10L), substr(v[1], 12L, 19L), tz)
}

# ---- the three files -----------------------------------------------------

# Write one generated quiz's three files into `stage` and return its manifest
# resources and the figure hrefs it carried in. `ids` is the block
# resolve_items() computed: the assessment resource, the meta resource, and the
# inner assignment, one entry per quiz id. `groups` is assignment_group_ids().
generate_quiz_files <- function(q, module_title, course, proj, stage, ids, groups) {
  title <- as.character(q$title)
  spec <- q$bank %||% list()
  out <- bank_groups(spec, proj, title)
  bank <- as.character(spec$dir %||% "questions")
  points <- as.numeric(spec$points)

  k <- as.character(q$id)
  quiz_id <- ids$quiz_res[[k]]
  meta_id <- ids$quiz_meta[[k]]
  assignment_id <- ids$quiz_aid[[k]]
  group_name <- as.character(q$group %||% spec$group %||% "Module Quizzes")
  group_id <- group_id_for(group_name, groups, paste0("quiz '", k, "'"))
  allowed_attempts <- as.integer(spec$allowed_attempts %||% -1L)
  image_base <- paste0(QUIZ_FILEBASE, "/", QUIZ_IMAGE_DIR)
  img_src_dir <- file.path(proj, bank, "images")
  tz <- read_timezone(course)

  images <- list()
  grouped <- character()
  flat <- character()
  for (gi in seq_along(out$groups)) {
    g <- out$groups[[gi]]
    n <- out$draws[[gi]]
    gtitle <- paste0("Ch. ", g$ch, " - ", g$name)
    items <- character()
    flat_items <- character()
    for (qi in seq_along(g$qs)) {
      qq <- g$qs[[qi]]
      where <- paste0(title, ": ", gtitle, " question id ", qq$id)
      check_question(qq, where)
      image <- as.character(qq$image %||% "")
      if (nzchar(image)) {
        src <- file.path(img_src_dir, image)
        if (!file.exists(src)) stop(where, ": image ", src, " does not exist", call. = FALSE)
        if (!nzchar(as.character(qq$figure$alt %||% "")))
          warning(where, ": figure has no alt text", call. = FALSE)
        images[[image]] <- src
      }
      ident <- gid("q", g$ch, g$name, qq$id)
      aq <- gid("aq", ident)
      aids <- answer_ids(ident, names(qq$options))
      items <- c(items, item_xml(ident, paste0("Q", qi), qq, c(
        question_type = "multiple_choice_question",
        points_possible = "1.0",
        original_answer_ids = paste(unlist(aids), collapse = ","),
        assessment_question_identifierref = aq), image_base, ids = aids))
      if (qi <= n)
        # The flat Common Cartridge copy holds the first selection_number items
        # of each group, keyed by the bank question id, with the same answer
        # ids. That is what Canvas's own exporter writes.
        flat_items <- c(flat_items, item_xml(aq, paste0("Q", qi), qq,
          c(cc_profile = "cc.multiple_choice.v0p1"), image_base, indent = "      ", ids = aids))
    }
    grouped <- c(grouped, fill(GROUP, list(
      ident = gid("group", g$ch, g$name), title = xesc(gtitle), n = as.character(n),
      items = paste0(items, collapse = ""))))
    flat <- c(flat, flat_items)
  }

  max_attempts <- if (allowed_attempts < 0L) "unlimited" else as.character(allowed_attempts)
  writef(file.path(stage, "non_cc_assessments", paste0(quiz_id, ".xml.qti")),
         fill(QTI_GROUPED, list(ns = QTI_NS, xsi = XSI_URI, schema = QTI_SCHEMA_CANVAS,
                                quiz_id = quiz_id, max_attempts = max_attempts,
                                title = xesc(title), groups = paste0(grouped, collapse = ""))))
  writef(file.path(stage, quiz_id, "assessment_qti.xml"),
         fill(QTI_FLAT, list(ns = QTI_NS, xsi = XSI_URI, schema = QTI_SCHEMA_CC,
                             quiz_id = quiz_id, max_attempts = max_attempts,
                             title = xesc(title), items = paste0(flat, collapse = ""))))

  description <- spec$description
  if (is.null(description))
    description <- paste0("<p>Quiz for <strong>", xtext(as.character(module_title)),
                          "</strong></p><p>Each student receives ", sprintf("%g", points),
                          " randomly selected questions.</p>")
  lock_at <- window_utc(spec$lock_at, tz, title, "lock_at")
  unlock_at <- window_utc(spec$unlock_at, tz, title, "unlock_at")
  win <- c(lock_at = lock_at, unlock_at = unlock_at)
  win <- win[nzchar(win)]
  published <- isTRUE(q$published %||% TRUE)

  # THE DEADLINE. The Python this ports left every quiz date to a separate
  # apply_due_dates() pass keyed by the quiz's exact title; here the definition
  # is the handle, so a `due:` on the definition writes the date and a
  # definition with none leaves both slots empty, as the export does.
  #
  # Canvas keeps the deadline TWICE in this file, once on the quiz and once on
  # the assignment it generates beside it, and reads the second one for the
  # grade book. Filling only the first leaves the two disagreeing.
  #
  # <all_day_date> is the LOCAL calendar day Canvas displays for the deadline,
  # which is the due: date's own day; the UTC instant beside it falls on the
  # next day whenever the course zone is behind UTC. It is written by the same
  # rule apply_carried_dates() uses on a carried quiz, so a cartridge rebuilt
  # from an export of itself reproduces this file rather than moving the day.
  due_at <- ""; all_day_date <- ""
  if (!is.null(q$due)) {
    due_at <- due_stamp(q$due, course$due_time, tz)
    all_day_date <- substr(trimws(as.character(q$due)), 1L, 10L)
  }
  writef(file.path(stage, quiz_id, "assessment_meta.xml"), fill(QUIZ_META, list(
    ns = CANVAS_NS, xsi = XSI_URI, schema = CANVAS_SCHEMA,
    quiz_id = quiz_id, assignment_id = assignment_id, group_id = group_id,
    shuffle_answers = tolower(as.character(spec$shuffle_answers %||% TRUE)),
    scoring_policy = as.character(spec$scoring_policy %||% "keep_highest"),
    quiz_type = as.character(spec$quiz_type %||% "assignment"),
    points = sprintf("%.1f", points),
    show_correct_answers = tolower(as.character(spec$show_correct_answers %||% TRUE)),
    allowed_attempts = as.character(allowed_attempts),
    one_question_at_a_time = tolower(as.character(spec$one_question_at_a_time %||% FALSE)),
    workflow_state = if (published) "published" else "unpublished",
    available = if (published) "true" else "false",
    lock_at = lock_at, unlock_at = unlock_at,
    due_at = due_at, all_day_date = all_day_date,
    window_xml = if (length(win))
      paste0(paste0("  <", names(win), ">", win, "</", names(win), ">\n"), collapse = "") else "",
    position = as.character(as.integer(spec$position %||% 1L)),
    title = xtext(title), description = xtext(as.character(description)))))

  # Figures: copied under web_resources/ and declared the way the export
  # declares its course image, as a webcontent resource.
  hrefs <- character(); fids <- character()
  for (fname in sort(names(images))) {
    href <- paste0("web_resources/", QUIZ_IMAGE_DIR, "/", fname)
    dest <- file.path(stage, href)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(images[[fname]], dest, overwrite = TRUE)
    hrefs <- c(hrefs, href); fids <- c(fids, gid("file", href))
  }

  # Manifest: the same two resources a carried quiz has, in the same order,
  # plus one webcontent resource per figure.
  #
  # THE FIGURE IS A DEPENDENCY OF THE META RESOURCE, not a resource standing on
  # its own. A figure nothing points at is unreachable in two ways that both
  # matter: the pre-zip orphan check reads it as dead weight, and the carry walk
  # in R/cartridge-carry.R follows <dependency> edges, so a course that later
  # carries this quiz out of its own export would bring the quiz and leave the
  # picture behind. The dependency edge is the one line that says the quiz needs
  # it. The Python generator this ports emitted the webcontent resource with no
  # edge; that divergence is deliberate and recorded in NEWS.
  resources <- list(
    list(id = quiz_id, raw = paste0(
      '<resource identifier="', quiz_id, '" type="', TYPE_ASSESSMENT, '">\n',
      '      <file href="', quiz_id, '/assessment_qti.xml"/>\n',
      '      <dependency identifierref="', meta_id, '"/>\n',
      '    </resource>')),
    list(id = meta_id, raw = paste0(
      '<resource identifier="', meta_id, '" type="', TYPE_LAR, '" href="', quiz_id,
      '/assessment_meta.xml">\n',
      '      <file href="', quiz_id, '/assessment_meta.xml"/>\n',
      '      <file href="non_cc_assessments/', quiz_id, '.xml.qti"/>\n',
      paste0('      <dependency identifierref="', fids, '"/>\n', collapse = ""),
      '    </resource>')))
  # The identifier attribute comes FIRST, as it does on every other resource
  # this builder writes. The Python wrote the type first, copying the attribute
  # order of the export's course image; two readers here locate a resource by
  # the literal string `<resource identifier="`, the pre-zip scan that proves no
  # idref dangles and resource_span() in R/cartridge-carry.R, and a block in the
  # other order is invisible to the first and a hard stop in the second.
  for (i in seq_along(hrefs))
    resources[[length(resources) + 1L]] <- list(id = fids[[i]], raw = paste0(
      '<resource identifier="', fids[[i]], '" type="webcontent" href="', xesc(hrefs[[i]]), '">\n',
      '      <file href="', xesc(hrefs[[i]]), '"/>\n',
      '    </resource>'))
  list(resources = resources, images = hrefs)
}
