# The cartridge surface.
#
# The wiki pages inside an .imscc are HTML fragments, not documents. Serving
# them and running pa11y would report a missing <html lang> and a missing
# <title> on every one, which is noise: Canvas supplies the document. So the
# iframe-titling and weblink-text checks below audit statically and check
# only what a fragment is actually responsible for.
#
# Amended 2026-08-13, coordinator review, finding 1c: audit_cartridge() is no
# longer purely static. It also resolves every embedded YouTube video's
# availability (via video_caption_state(), below) and emits a finding when
# one is dead, because a broken embed is a more urgent defect than any
# caption gap it might be hiding behind, and nothing was surfacing it. That
# one check touches the network; the iframe-titling and weblink-text checks
# still do not.
#
# Amended again 2026-08-13, final whole-branch review, finding C2 (critical):
# the SAME resolution pass now also emits WCAG 1.2.2 findings for the caption
# states it was already computing and throwing away (see
# check_video_captions() below). Until that fix, four of the five states
# parse_caption_state() can return produced no output of any kind, so a
# course with an uncaptioned video and a course with a fully captioned one
# produced byte-identical caption evidence: none.
#
# The important consequence for the STATIC checks' fixes is where they land.
# These fragments are GENERATED. Editing the zip is pointless; the next build
# overwrites it. Every finding here, video-availability included, names the
# module manifest or the cartridge builder as the target, because that is where
# the fragment's source (or the embedded video's URL) is actually authored.
#
# `level` is left NA_character_ on every finding() call below, matching the
# discipline the source checks already settled on: this project defers
# WCAG-level assignment to a verified criterion-to-level lookup at the
# reporting stage, rather than typing a level in at check-authoring time. 4.1.2
# and 2.4.4 are both published Level A, but hardcoding that here would
# reintroduce the exact per-file guessing the project moved away from, just for
# two criteria instead of one. The video-availability finding's criterion,
# "broken-embed", is not a WCAG success criterion at all -- confirmed against
# the report layer's level_for(), which looks it up in a named vector and
# safely returns NA for any key it doesn't recognize, exactly the same path an
# unlisted real criterion like "9.9.9" already takes. It rides in the same
# findings table because a broken link IS something a course accessibility pass
# needs to catch, even though WCAG itself has no numbered criterion for "the
# content has to actually exist."

CART_GENERATOR <- "modules.yml or the coursepack cartridge builder"

# ---- iframe titling --------------------------------------------------------
# An <iframe> with no title is announced to a screen reader only as "frame",
# with nothing to say which frame. Statically checked because Canvas wraps
# these fragments in its own document; running pa11y against the fragment
# directly would also flag the missing <html lang> and <title> Canvas
# supplies, which is noise this project has already decided not to serve
# fragments to avoid (see the file header).
#
# Amended 2026-08-13, coordinator review, findings 2 and 5:
# - Finding 2 (critical): title="" used to count as titled, because the old
#   check only tested for the ATTRIBUTE's presence (`\\stitle=`), never its
#   value. An empty title gives the frame no accessible name and fails 4.1.2
#   exactly as badly as no title attribute at all. The check now extracts the
#   value and requires nzchar(trimws(value)); is.na() is checked first
#   because trimws(NA) is NA and nzchar(NA) is NA, not FALSE.
# - Finding 5 (minor): the iframe tag and its title attribute are now matched
#   case-insensitively. Case sensitivity was already safe in one direction
#   (an uppercase TITLE= attribute was misread as absent, so a real title
#   would have been wrongly flagged -- a false positive, not a false pass)
#   but unsafe in the other: an uppercase <IFRAME> tag was invisible to the
#   check entirely, which is the dangerous direction for a compliance tool.
IFRAME_TAG_RE   <- stringr::regex("<iframe[^>]*>", ignore_case = TRUE)
IFRAME_TITLE_RE <- stringr::regex("\\stitle\\s*=\\s*[\"']([^\"']*)[\"']", ignore_case = TRUE)
IFRAME_SRC_RE   <- stringr::regex("\\ssrc\\s*=\\s*[\"']([^\"']+)[\"']", ignore_case = TRUE)

# Audited for the same id-collision class that dropped 30 real
# check_missing_fig_alt() findings (see that function's comment in the source
# checks). `selector` here is already built from the iframe's own `src`, a real
# identifying property of the element rather than a position, so two untitled
# iframes on the same page with genuinely different targets already get
# distinct ids.
#
# A narrower residual gap was identified (two SEPARATE iframe tags with a
# byte-identical `src` on the same page) and a fix was tried and REVERTED the
# same session: passing the full raw `<iframe ...>` tag text as `code`
# closed that gap but broke something real to do it. Verified against two real
# `.imscc` files of one course, an export and its Canvas round trip: the round
# trip does not only strip the `title` attribute (see the file header); on one
# wiki page it ALSO drops an unrelated `autoplay=0;` clause from the iframe's
# `allow` attribute, so the two cartridges' otherwise-identical untitled-iframe
# tags stopped being byte-identical, split into 2 rows instead of correctly
# deduping to 1, and the two dedup log entries for the other two
# genuinely-shared untitled iframes shrank from 3 to 2. The `allow` attribute
# is irrelevant to whether
# an iframe has a title; keying the id on the WHOLE tag made the id sensitive
# to noise the check does not care about. `selector` (built from `src` alone)
# is the right granularity for what this check is actually about and is left
# as the only discriminator; the narrow same-page-same-src gap is accepted
# rather than fixed with a broader key that reintroduces a worse, real
# problem to close a narrower, unobserved one.
#
# `surface` amended 2026-08-13, coordinator re-review, Finding 4 (important,
# and the inverse failure direction from every other fix today). This and
# the other two check functions below used to hardcode `surface = "cartridge"`
# regardless of which repo's `.imscc` was being audited. Auditing two
# courses in one invocation is an explicitly supported use case, and two
# different courses can both use a conventionally-named wiki page (a
# "syllabus.html" both embed their own site's iframe at) with the same `src`
# pattern, or by chance an identical `src`. Two DIFFERENT courses' findings
# would then share the identical (surface, file, criterion, selector) key and
# collapse into an "expected duplicate" in report_and_dedup() -- one course's
# real finding silently disappearing into another's, the false-negative mirror
# of the collision-halt this project spent the rest of the day making loud.
# `surface` is now a required argument, always the caller's course-of-origin
# label (the audit driver derives it from the repo path, matching how a
# page-based surface is already named, suffixed so a cartridge finding is
# never mixed into the same report bucket as that course's page findings),
# so two different courses' cartridge findings can never share a surface and
# therefore can never collapse into each other, no matter how similar the
# rest of the key looks.

#' Untitled iframes in a cartridge's wiki pages
#'
#' An `<iframe>` with no usable `title` is announced to a screen reader only as
#' "frame", which fails WCAG 4.1.2. An empty `title=""` counts as untitled, and
#' the tag and its attribute are matched case-insensitively.
#'
#' @param wiki_files Paths to the cartridge's wiki HTML fragments.
#' @param surface The caller's course-of-origin label. Required, so two
#'   courses' findings can never collapse into each other.
#' @return A list of one-row findings, empty when every frame is titled.
#' @export
check_untitled_iframes <- function(wiki_files, surface) {
  out <- list()
  for (w in wiki_files) {
    txt    <- paste(readLines(w, warn = FALSE), collapse = "\n")
    frames <- stringr::str_extract_all(txt, IFRAME_TAG_RE)[[1]]
    for (fr in frames) {
      title_val <- stringr::str_match(fr, IFRAME_TITLE_RE)[, 2]
      has_real_title <- !is.na(title_val) && nzchar(trimws(title_val))
      if (!has_real_title) {
        src <- stringr::str_match(fr, IFRAME_SRC_RE)[, 2]
        f <- finding(
          surface = surface, file = basename(w), criterion = "4.1.2",
          level = NA_character_,
          issue = "iframe has no title, so it is announced only as 'frame'",
          selector = sprintf("iframe[src='%s']", src %||% "?"),
          severity = "serious",
          detail = sprintf("src=%s", src %||% "(none)"), source = "custom")
        f$fix_target <- CART_GENERATOR
        out[[length(out) + 1]] <- f
      }
    }
  }
  out
}

# ---- weblink text quality ---------------------------------------------------
# "Click here" and a bare URL both fail 2.4.4 when read out of context, which
# is how a screen reader user navigates a link list (by pulling every link's
# accessible name out of the page and reading just that list). An empty
# <title></title> fails the same way -- no accessible name at all -- and is
# at least as bad as "click here" (coordinator review, finding 3, 2026-08-13).
# It is not NA (the tag exists, it is just empty), so the old check let it
# through: it is not blank enough to be skipped by is.na(), and "" matches
# neither the weak-text pattern nor the bare-URL pattern.
#
# A Common Cartridge weblink resource is an `imswl_v1p1`-namespaced <webLink>
# element; the manifest's `type="imswl_xmlv1p1"` attribute describes the
# resource ENTRY, not the resource FILE's own content, so matching that
# literal string against a weblink XML file's text never matches -- verified
# against all 32 real weblink resources in one real export, none of which
# contain that substring. <webLink is what every one of those 32 files
# actually starts with, and is what this checks for instead.
WEAK_LINK_RE <- "^(click here|here|read more|link|this|more)$"

# Audited for the id-collision class documented on check_missing_fig_alt() in
# the source checks. Found sound, unchanged: each weblink resource is its own
# XML file (`x`), Canvas assigns each one a unique generated basename
# (verified: all 32 real weblink resources in that export have distinct
# basenames), and this loop reads at most one <title> per file, so
# `file = basename(x)` alone already gives every possible finding here a
# unique key. No two rows from this function can ever legitimately share a
# file, so there is nothing for a same-file collision to happen to.
#
# `surface` amended 2026-08-13, coordinator re-review, Finding 4: see
# check_untitled_iframes() above for the full reasoning. Canvas's generated
# basenames are unique WITHIN one export, but nothing stops two different
# courses' Canvas exports from each generating a resource that happens to
# collide on basename (or, more realistically, from each embedding a link
# with the identical weak text "click here" against a coincidentally
# matching selector/criterion), so `surface` still has to carry the
# course of origin to keep two different courses' findings apart.

#' Weblink text that says nothing out of context
#'
#' "Click here", a bare URL, and an empty `<title></title>` all fail WCAG 2.4.4
#' when read out of context, which is how a screen reader user navigates a link
#' list. Reads the cartridge's `<webLink>` resource files.
#'
#' @param xml_files Paths to the cartridge's XML files. Anything that is not a
#'   `<webLink>` resource is skipped.
#' @param surface The caller's course-of-origin label. Required, for the same
#'   reason [check_untitled_iframes()] requires it.
#' @return A list of one-row findings, empty when every link reads well.
#' @export
check_weak_link_text <- function(xml_files, surface) {
  out <- list()
  for (x in xml_files) {
    txt <- paste(readLines(x, warn = FALSE), collapse = "\n")
    if (!grepl("<webLink", txt, fixed = TRUE)) next
    title <- stringr::str_match(txt, "<title>([^<]*)</title>")[, 2]
    if (is.na(title)) next
    trimmed  <- trimws(title)
    is_empty <- !nzchar(trimmed)
    is_weak  <- grepl(WEAK_LINK_RE, tolower(trimmed))
    is_url   <- grepl("^https?://", title)
    if (is_empty || is_weak || is_url) {
      f <- finding(
        surface = surface, file = basename(x), criterion = "2.4.4",
        level = NA_character_,
        issue = if (is_empty)
          "link has no text at all, so it has no accessible name"
        else
          "link text does not describe its destination out of context",
        selector = NA_character_, severity = "moderate",
        detail = sprintf("title=\"%s\"", title), source = "custom")
      f$fix_target <- CART_GENERATOR
      out[[length(out) + 1]] <- f
    }
  }
  out
}

# ---- video captions and availability ---------------------------------------
# Fetches the watch page and inspects the (undocumented) player-response
# payload embedded in it. This is a heuristic against a page format YouTube
# publishes no contract for, and it WILL break. When it cannot tell, it
# returns "undetermined" and the report says so. It never guesses, because
# "this video has captions" is a compliance claim -- and, as of the rewrite
# below, so is "this video merely lacks captions" when the real problem is
# that the video does not exist at all.
#
# parse_caption_state() is split from the network fetch so the payload logic
# can be exercised against synthetic strings without hitting the network.
# video_caption_state() takes the fetch itself as an injectable `fetch`
# argument for the same reason, one level up (coordinator review, finding 4,
# 2026-08-13): every check that existed before only asserted membership in
# the state set, which a stub ignoring its argument and always returning
# "undetermined" would also satisfy. Driving the real wrapper against a
# frozen payload, and separately against a fetcher that hits a real refused
# connection, is what actually proves the fetch -> parse wiring and the
# network-failure path both work, not just the parser in isolation.
#
# Rewritten 2026-08-13, coordinator review, finding 1 (critical, and worse
# than first reported). The original version could not tell "no captions"
# apart from "could not verify" apart from "the video is gone": when neither
# a captionTracks nor a playerCaptionsTracklistRenderer marker appeared, it
# returned "none" unconditionally. A private or deleted video, a bot-check
# interstitial, and a Google consent page can all return HTTP 200 with
# neither marker present and no read error, so try() never fires and nothing
# ever became "undetermined" for any of them. Confirmed against the 4 real
# embeds of one real course: a live fetch of one wiki page's video found
# playabilityStatus.status "ERROR", reason "Video unavailable" (the YouTube
# account behind it had been terminated), no og:title, and, naturally, zero
# caption data -- which the old code read as "none: this video has no
# captions," a claim that implies the video plays but lacks captions. It
# does not play at all. A control fetch of a real working video under the same
# code path returns status OK with a real title, ruling out "every fetch from
# this network looks like this."
#
# Fixed in two layers, both gating on facts verified against real pages, not
# assumed from YouTube's documentation (there isn't any for this payload):
#
# 1. Positive proof the real watch page loaded at all. Every real watch page
#    fetched during this task -- captioned, auto-only, no-caption, AND the
#    genuinely dead one -- carries `ytInitialPlayerResponse` and a
#    `"videoId":"..."` marker. A page that lacks BOTH is not trusted to mean
#    anything about the video; it means the fetch landed on something that
#    isn't the real player response (a consent screen, a bot-check
#    interstitial, or some future YouTube page shape this file doesn't know
#    about), and the honest answer is "undetermined", not "none".
# 2. Given a real player response, `playabilityStatus.status` of "ERROR" or
#    "UNPLAYABLE", or the literal reason text "Video unavailable" as a
#    fallback signal in case the status enum value ever differs from what was
#    observed, means the video does not exist in a playable state at all.
#    That is the NEW "unavailable" state, and it is deliberately not folded
#    into "none": "none" means a real, loading video with a confirmed absence
#    of captions; "unavailable" means there is no video to caption.
#
# check_unavailable_videos(), below, turns "unavailable" into its own
# finding, separate from any caption finding, wired into audit_cartridge()
# so a broken embed is caught by the same pass that catches an untitled
# iframe, not left as something only a standalone video_caption_state() probe
# would ever surface.
parse_caption_state <- function(page) {
  has_real_player_response <-
    grepl("ytInitialPlayerResponse", page, fixed = TRUE) ||
    grepl('"videoId":"', page, fixed = TRUE)
  if (!has_real_player_response) return("undetermined")

  is_unavailable <-
    grepl('"status":"ERROR"', page, fixed = TRUE) ||
    grepl('"status":"UNPLAYABLE"', page, fixed = TRUE) ||
    grepl('"reason":"Video unavailable"', page, fixed = TRUE)
  if (is_unavailable) return("unavailable")

  if (!grepl("captionTracks", page, fixed = TRUE)) {
    return(if (grepl("playerCaptionsTracklistRenderer", page, fixed = TRUE))
      "undetermined" else "none")
  }
  # Bounded on the right by the key that immediately follows captionTracks in
  # every real payload seen (audioTracks). If that shape isn't there, YouTube
  # changed something this regex doesn't know about -- say so, don't guess.
  m <- regexpr('"captionTracks":\\[.*?\\](?=,"audioTracks")', page, perl = TRUE)
  if (m == -1) return("undetermined")
  blob   <- regmatches(page, m)
  # Track objects are separated by `},{"baseUrl"`; the one nested object each
  # track carries (`"name":{"simpleText":...}`) closes with `},"vssId"`, not
  # `},{`, so this split doesn't cut through it.
  #
  # The auto-vs-manual signal is "kind":"asr" on the INDIVIDUAL track object,
  # not on the payload as a whole. Verified live against a real course's
  # embeds: two of them carry BOTH a manual English track (no `kind` key,
  # vssId ".en") AND a fallback auto-generated one (`"kind":"asr"`, vssId
  # "a.en") in the same captionTracks array, because YouTube adds an ASR
  # fallback to most videos regardless of whether real captions already
  # exist. Flagging "auto-only" whenever "kind":"asr" appears ANYWHERE in the
  # payload would report "auto-only" on both even though real captions
  # exist, and since an ASR fallback is nearly universal, would make
  # "captions" almost unreachable for any real video. The right question:
  # is EVERY track in the array auto (auto-only), or does at least one lack
  # "kind":"asr" (captions).
  tracks <- strsplit(blob, '\\},\\{"baseUrl"', perl = TRUE)[[1]]
  if (!length(tracks)) return("undetermined")
  if (all(grepl('"kind":"asr"', tracks, fixed = TRUE))) "auto-only" else "captions"
}

# The one network-touching seam in the whole caption/availability check. A
# caller substitutes a different `fetch` to drive video_caption_state()
# deterministically, either against a frozen payload or against a real
# connection engineered to fail.
default_youtube_fetch <- function(video_id) {
  url <- sprintf("https://www.youtube.com/watch?v=%s", video_id)
  paste(readLines(url, warn = FALSE), collapse = "")
}

#' The caption state of one embedded video
#'
#' Fetches the watch page and inspects the undocumented player-response payload
#' embedded in it. Returns one of five states: `"captions"` (at least one
#' non-machine track), `"auto-only"` (every track is the platform's own ASR
#' track), `"none"` (a real, loading video with a confirmed absence of tracks),
#' `"unavailable"` (there is no playable video at all), or `"undetermined"`
#' (the page could not be confirmed to be a real player response). It never
#' guesses: "this video has captions" is a compliance claim.
#'
#' @param video_id The video's id.
#' @param fetch The function that returns the watch page's text. Injectable so
#'   a caller can drive this deterministically, without the network.
#' @return One of the five state strings.
#' @export
video_caption_state <- function(video_id, fetch = default_youtube_fetch) {
  page <- tryCatch(suppressWarnings(fetch(video_id)),
                    error = function(e) NA_character_)
  if (is.null(page) || length(page) != 1 || is.na(page) || !nzchar(page)) {
    return("undetermined")
  }
  parse_caption_state(page)
}

# ---- broken embeds ----------------------------------------------------------
# An unavailable video is a more urgent defect than any caption gap it might
# be hiding behind: a student who clicks it gets nothing at all, not merely
# an accessibility gap. This is its own finding, never merged into a caption
# finding, so it cannot be mistaken for "needs captions" by anyone reading
# the findings table (coordinator review, finding 1c, 2026-08-13).
YOUTUBE_ID_RE <- stringr::regex(
  paste0("(?:youtube(?:-nocookie)?\\.com/(?:embed/|watch\\?v=)|",
         "youtu\\.be/)([A-Za-z0-9_-]{6,})"),
  ignore_case = TRUE)

extract_youtube_ids <- function(txt) {
  m <- stringr::str_match_all(txt, YOUTUBE_ID_RE)[[1]]
  if (!nrow(m)) character(0) else unique(m[, 2])
}

# Audited for the id-collision class documented on check_missing_fig_alt() in
# the source checks. Found sound, unchanged: `selector` below is built from
# `vid`, the real YouTube video id, so two different dead embeds on the same
# wiki page already get two different selectors and two different ids. The
# `extract_youtube_ids()` call above also already de-duplicates ids WITHIN
# one page (`unique(m[, 2])`), so this function cannot even attempt to
# construct two rows for the identical video on the same page in the first
# place.
#
# `surface` amended 2026-08-13, coordinator re-review, Finding 4: see
# check_untitled_iframes() above. Two different courses embedding the exact
# same YouTube video (a shared department orientation clip, for instance)
# would otherwise report the identical broken-embed finding for both, and
# the second course's copy would silently vanish into the first's.
# One video state per video id per RUN, not per cartridge.
#
# Added with the caption findings, and immediately amended by what the first
# real run did with it. The cache started out local to each
# resolve_video_states() call, so a video embedded in two cartridges was
# fetched twice, and the second real run caught the consequence loudly:
# halt_on_collision() stopped the audit because one wiki page's video resolved
# to two DIFFERENT states within one run (a live third-party fetch is flaky by
# construction; this file's own header says so). Two rows then shared a finding
# id, since the id keys on (surface, file, criterion, selector) and a caption
# state is none of those, while disagreeing on their own issue and detail text.
# That is a genuine collision, and the detector was right to stop.
#
# The fix is one measurement per video per run rather than a wider id: a
# video's caption state is a property of the VIDEO, not of which cartridge
# happens to embed it, so fetching it twice and getting two answers is the
# bug. This env lives for the R session, exactly like the finding model's
# one-shot warning flag, and for the same reason: the guarantee belongs inside
# the function rather than depending on a caller to arrange it.
#
# An INJECTED fetcher gets a fresh cache instead of this one. Two test
# fixtures driving different deterministic fetchers must not read each
# other's answers, and a caller who supplies a fetcher is by definition not
# talking to the shared, real YouTube.
.video_state_cache <- new.env(parent = emptyenv())

video_state_cache_for <- function(fetch) {
  if (identical(fetch, default_youtube_fetch)) .video_state_cache
  else new.env(parent = emptyenv())
}

# Every (wiki page, video id) pair in a cartridge, each with its resolved
# state. Two checks read these states (availability and captions); each used
# to own its own fetch loop, which doubled the network work and let the two
# disagree about the same video within one run.
resolve_video_states <- function(wiki_files, fetch = default_youtube_fetch,
                                  seen = video_state_cache_for(fetch)) {
  out <- list()
  for (w in wiki_files) {
    txt <- paste(readLines(w, warn = FALSE), collapse = "\n")
    for (vid in extract_youtube_ids(txt)) {
      if (!exists(vid, envir = seen, inherits = FALSE)) {
        assign(vid, video_caption_state(vid, fetch = fetch), envir = seen)
      }
      out[[length(out) + 1]] <- list(
        file  = basename(w), vid = vid,
        state = get(vid, envir = seen, inherits = FALSE))
    }
  }
  out
}

check_unavailable_videos <- function(wiki_files, surface,
                                      fetch = default_youtube_fetch,
                                      states = resolve_video_states(wiki_files, fetch)) {
  out <- list()
  for (s in states) {
    if (!identical(s$state, "unavailable")) next
    f <- finding(
      surface = surface, file = s$file, criterion = "broken-embed",
      level = NA_character_,
      issue = paste("embedded video is unavailable (removed, private, or",
                    "otherwise unplayable); a student who clicks it gets",
                    "no content"),
      selector = sprintf("iframe[src*='%s']", s$vid), severity = "serious",
      detail = sprintf("youtube video id %s", s$vid), source = "custom")
    f$fix_target <- CART_GENERATOR
    out[[length(out) + 1]] <- f
  }
  out
}

# ---- captions (1.2.2) -------------------------------------------------------
# Added 2026-08-13, final whole-branch review, finding C2 (critical).
#
# parse_caption_state() has computed five states since the day it was
# written, and exactly ONE of them (unavailable) ever produced a finding. The
# other four were computed, discarded, and never appeared in any output:
# verified against the shipped JSON, which carried zero findings under any
# 1.2.x criterion at all, while three separate documents said captions were
# checked. A measured Level A failure that no one is ever told about is worse
# than an unchecked one, because the silence reads as a pass.
#
# What each state emits, and why:
#
# - "none": a real, loading video confirmed to carry no caption track.
#   Criterion 1.2.2 (Captions, Prerecorded), Level A. A finding.
# - "auto-only": every track in the payload is YouTube's own ASR track.
#   ALSO a 1.2.2 failure. WCAG 1.2.2 requires captions that are accurate and
#   synchronized; machine-generated captions are not accepted as satisfying
#   it (this project's own decision record already said so in prose: "YouTube
#   auto-captions do not on their own satisfy 1.2.2"), and the check has been
#   able to tell auto-only from real captions since it learned to look at
#   "kind":"asr" per TRACK rather than per payload.
# - "undetermined": the tool could not verify. NOT a failure claim, and
#   deliberately not silent either: "could not verify" is a real state a
#   compliance document has to carry, or an unverifiable video is
#   indistinguishable from a passing one. severity "review", which
#   classify_fixes() routes to a human by design.
# - "unavailable": no finding here. check_unavailable_videos() above already
#   reports it, and there is no video to caption; emitting a caption finding
#   too would double-count one defect and imply the fix is captioning
#   something that does not play.
# - "captions": at least one non-ASR track. No finding.
#
# Severity for the two real failures is "serious" and the fix_target is
# CART_GENERATOR, matching every other cartridge finding: the embed URL is
# authored in the module manifest, so that is where a swap to a captioned
# video lands. classify_fixes(), in the report layer, routes 1.2.2 to
# class (c), human judgement, alongside 2.4.4 link text and 1.1.1 alt text,
# for the same reason all three share: writing (or commissioning) captions is
# content work per video, and no single generator edit produces them.
check_video_captions <- function(wiki_files, surface,
                                  fetch = default_youtube_fetch,
                                  states = resolve_video_states(wiki_files, fetch)) {
  out <- list()
  for (s in states) {
    spec <- switch(s$state,
      "none" = list(
        severity = "serious",
        issue = paste("embedded video has no captions, which fails WCAG 1.2.2",
                      "(Captions, Prerecorded, Level A)"),
        detail = sprintf("youtube video id %s: caption state 'none' (a real, loading video with a confirmed absence of caption tracks)",
                         s$vid)),
      "auto-only" = list(
        severity = "serious",
        issue = paste("embedded video has only auto-generated captions, which",
                      "do not satisfy WCAG 1.2.2 (Captions, Prerecorded,",
                      "Level A) on their own"),
        detail = sprintf("youtube video id %s: caption state 'auto-only' (every caption track in the payload is YouTube's own ASR track)",
                         s$vid)),
      # "undetermined" means the fetch or the parse failed, so NOTHING about
      # this video was established: not its captions and not its
      # availability. Both halves are said out loud, and the second matters
      # more than it looks. Re-review finding 4: on a degraded network a
      # previously reported dead embed resolves to undetermined, its
      # broken-embed finding is simply absent from this run, and the diff
      # against the last run reports it as FIXED. A false negative in the
      # direction that matters, since someone could conclude a dead video had
      # been repaired. This row is the only thing standing next to that
      # disappearance, so it names it explicitly rather than leaving a reader
      # to notice an absence.
      "undetermined" = list(
        severity = "review",
        issue = paste("captions on this embedded video COULD NOT BE VERIFIED;",
                      "this is not a pass, it is an unanswered question a",
                      "person has to answer by opening the video. Nothing",
                      "about this video was established this run, its",
                      "availability included: if a previous audit reported",
                      "this embed as broken, do NOT read that finding's",
                      "absence from this run as a fix"),
        detail = sprintf("youtube video id %s: caption state 'undetermined' (the fetched page could not be confirmed to be a real player response, or its payload shape is not one this check knows). Availability is equally unverified, so any broken-embed finding for this id that disappeared between runs disappeared for lack of evidence, not because it was repaired.",
                         s$vid)),
      NULL)
    if (is.null(spec)) next
    f <- finding(
      surface = surface, file = s$file, criterion = "1.2.2",
      level = NA_character_, issue = spec$issue,
      selector = sprintf("iframe[src*='%s']", s$vid),
      severity = spec$severity, detail = spec$detail, source = "custom")
    f$fix_target <- CART_GENERATOR
    out[[length(out) + 1]] <- f
  }
  out
}

# ---- putting the cartridge checks together ----------------------------------
# Amended 2026-08-13, coordinator review, finding 6 (minor): the extraction
# directory used to be a deterministic name derived only from the input
# file's basename, with no on.exit cleanup. An error partway through left
# debris behind, and two concurrent audits of two cartridges that happened to
# share a basename (e.g. two different courses each exporting
# "coursepack.imscc" into a shared CI temp root) would race on the same
# directory. tempfile() is unique per call; on.exit(..., add = TRUE) cleans
# up on every exit path, including an error, not just the normal return.
#
# `video_fetch` defaults to the real network fetcher and exists so a caller
# (this file's own test suite) can drive the video-availability check
# without the network, the same way video_caption_state() itself allows.
#
# `surface` amended 2026-08-13, coordinator re-review, Finding 4 (important).
# Required, not defaulted: a `.imscc` has no course identity of its own once
# unzipped (there is no field inside the manifest this project trusts for
# it; `course.yml`'s own name is Canvas-shell-specific, not general to any
# cartridge), so the caller, which DOES know which repo this file came from,
# must say so. Threading it through to all three checks below is what stops
# two different courses' cartridge findings from ever sharing a surface, and
# therefore from ever collapsing into each other via report_and_dedup()'s
# "expected duplicate" path -- the false-negative, silent-disappearance
# mirror of the id-collision halt built earlier the same day. A bare
# "cartridge" default was deliberately NOT kept for backward compatibility;
# every caller, including this file's own test suite, now has to name a real
# surface, the same discipline `discover_target()` already applies to a repo
# path.
# Cartridge locations this project ever looks in. The ONE place this list
# is written -- the audit driver's real audit loop and intended_surfaces()'s
# declaration both call cartridges_in() below rather than each keeping their
# own copy of it, so a search directory added to one can never silently be
# missing from the other.
CARTRIDGE_SEARCH_DIRS <- c("build/coursepack", "reference")

#' Every cartridge under a repository's conventional locations
#'
#' The one place the search directories are read, so the audit driver and the
#' declaration in [intended_surfaces()] can never look in different places.
#'
#' @param repo The repository path.
#' @param dirs Directories under `repo` to search, relative. Defaults to the
#'   conventional pair; an argument so a caller with a differently shaped
#'   repository is not forced to move its files.
#' @return Full paths to every `.imscc` found, possibly none.
#' @export
cartridges_in <- function(repo, dirs = CARTRIDGE_SEARCH_DIRS) {
  unlist(lapply(dirs, function(d) {
    list.files(file.path(repo, d), pattern = "\\.imscc$", full.names = TRUE)
  }), use.names = FALSE)
}

# How many wiki HTML pages -- the actual navigable Canvas pages, as
# distinct from weblinks, assignments, or any other non-HTML cartridge
# content -- a single cartridge file contains. A cartridge's honest
# contribution to a `pages_examined` count is this number, never the raw count
# of `.imscc` FILES examined -- a
# cartridge holding one wiki page and one holding a hundred used to both
# contribute the same "1" to a field that otherwise counts real HTML pages,
# silently mixing units under one figure ("Pages examined: N") that a
# reader has no way to know means two different things.
#
# Self-contained: unzips, counts, cleans up, and returns only the integer,
# rather than handing back file paths into a temp directory this function
# is about to delete out from under them. audit_cartridge() below still
# does its own separate unzip to get real, live paths it can actually read
# for its checks; this duplicates two lines of glob logic against that (the
# `wiki_content/*.html` pattern), not a naming or business rule, and is the
# safer tradeoff against returning paths into an already-unlinked
# directory.
cartridge_wiki_page_count <- function(imscc_path) {
  tmp <- tempfile("imscc-")
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  utils::unzip(imscc_path, exdir = tmp)
  length(list.files(file.path(tmp, "wiki_content"), pattern = "\\.html$"))
}

#' Audit one cartridge
#'
#' Unzips the cartridge, runs the four checks a Common Cartridge is
#' responsible for (untitled iframes, weblink text, broken embeds, captions),
#' and reports how many wiki pages it actually read as the `wiki_pages_read`
#' attribute of the result.
#'
#' @param imscc_path Path to the `.imscc` file.
#' @param surface The caller's course-of-origin label. Required, not
#'   defaulted: a cartridge has no course identity of its own once unzipped, so
#'   the caller, which does know which repository it came from, must say so.
#' @param video_fetch The watch-page fetcher passed to [video_caption_state()].
#'   Defaults to the real network fetcher.
#' @return A findings data frame, possibly with no rows, carrying the
#'   `wiki_pages_read` attribute.
#' @export
audit_cartridge <- function(imscc_path, surface, video_fetch = default_youtube_fetch) {
  tmp <- tempfile("imscc-")
  dir.create(tmp, recursive = TRUE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  utils::unzip(imscc_path, exdir = tmp)

  wiki <- list.files(file.path(tmp, "wiki_content"), pattern = "\\.html$",
                     full.names = TRUE)
  xmls <- list.files(tmp, pattern = "\\.xml$", recursive = TRUE, full.names = TRUE)

  # One video resolution pass, shared by the availability and caption checks
  # below, so a video embedded on more than one page is fetched once and both
  # checks read the identical state for it (finding C2).
  states <- resolve_video_states(wiki, fetch = video_fetch)

  out <- c(check_untitled_iframes(wiki, surface),
           check_weak_link_text(xmls, surface),
           check_unavailable_videos(wiki, surface, states = states),
           check_video_captions(wiki, surface, states = states))

  res <- if (!length(out)) finding("x","x","x","x","x","x","x")[0, ]
         else do.call(rbind, out)
  # How many wiki pages this call ACTUALLY read, reported back to the caller
  # so a driver's pages_examined can be an empirical measurement taken from
  # the code path that did the work, never a second read of the declaration
  # (finding C1). A cartridge that produced zero findings still examined
  # these pages, and a cartridge whose audit never ran contributes nothing,
  # which is the distinction the whole counter exists to preserve. Rides as
  # an attribute for the same reason check_missing_fig_alt()'s `mode` does:
  # it must not become a findings column that rbind() would have to carry.
  attr(res, "wiki_pages_read") <- length(wiki)
  res
}

# ---- non-HTML media inventory ------------------------------------------------
# Not a finding source. This lists what pa11y and the HTML-only source checks
# structurally cannot see, so nothing gets audited by silent omission.
# Classifying a listed file as in-scope, a working file, or
# published-but-out-of-scope is a per-repo editorial call the report makes,
# not something this function decides.
#
# `docs/`, `.quarto/`, `bak/`, `*_files/`, and `site_libs` are Quarto/git
# build or working-file conventions, not any one course's paths, so excluding
# them holds for any repo built the same way. `.Rproj.user/` is added to the
# image exclusion for the same reason: it is an editor's own local session
# cache, gitignored by convention, yet still materializes real image files on
# disk that are stale editor artifacts, never authored content -- confirmed
# against a real repository, which had 27 such files still on disk at audit
# time.
#
# The `bibtex/` exclusion on the PDF side is a textbook-repository convention
# riding along with the build-output ones: a bibliography directory's PDFs are
# reference copies, not published course material.

#' What pa11y and the HTML checks structurally cannot see
#'
#' Lists a repository's images and PDFs so non-HTML media is inventoried rather
#' than silently omitted. Not a finding source: whether a listed file is in
#' scope, a working file, or published but out of scope is an editorial call
#' the report makes.
#'
#' @param repo The repository path.
#' @return A data frame with `kind`, `ref`, and `note` columns, or `NULL` when
#'   the repository has neither images nor PDFs.
#' @export
inventory_media <- function(repo) {
  imgs <- list.files(repo, pattern = "\\.(png|jpe?g|gif|svg|webp)$",
                     recursive = TRUE)
  imgs <- imgs[!grepl("^(docs|\\.quarto|bak)/|_files/|site_libs|\\.Rproj\\.user/",
                      imgs)]
  pdfs <- list.files(repo, pattern = "\\.pdf$", recursive = TRUE)
  pdfs <- pdfs[!grepl("^(docs|\\.quarto|bibtex|bak)/|_files/", pdfs)]
  rbind(
    if (length(imgs)) data.frame(kind = "image", ref = imgs,
      note = "needs a text alternative", stringsAsFactors = FALSE),
    if (length(pdfs)) data.frame(kind = "pdf", ref = pdfs,
      note = "classify as live or working file before auditing",
      stringsAsFactors = FALSE))
}
