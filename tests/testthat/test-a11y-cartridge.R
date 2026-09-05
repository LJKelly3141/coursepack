# Ported from the snapshot's own self-checking audit test script: the
# cartridge sections. Each printed banner there is a test_that() block here and
# each check() is an expectation carrying the original label.
#
# Three departures from a straight transcription, all required by the plan:
#
# 1. The section that audited a real Canvas export replaced it with a
#    synthetic cartridge, `write_a11y_cartridge()` in helper-cartridge.R. It
#    carries the same shapes the real export carried (a titled iframe beside an
#    untitled one, a weblink, an embedded video), so the assertions still
#    discriminate; the counts are the fixture's, hand-typed.
# 2. The section that inventoried a real textbook repository runs against the
#    `pair/alpha` fixture with one image, one PDF, and one PDF under a
#    `bibtex/` directory written into a copy of it.
# 3. The two sections that reach YouTube over the network skip unless
#    COURSEPACK_NETWORK_TESTS is set.
#
# The three cartridge-bearing fixtures of the declared-surfaces negative
# control land here too: they drive `intended_surfaces()`, which reads the
# cartridge functions this file's library provides.

# A cartridge directory zipped in place, the way a Canvas export is shaped.
zip_cartridge <- function(root, zip_path) {
  unlink(zip_path)
  old <- setwd(root)
  on.exit(setwd(old), add = TRUE)
  utils::zip(zip_path, list.files(".", recursive = TRUE), flags = "-q")
  zip_path
}

# Every real-video fixture below carries REAL_PAGE_MARKER, the
# ytInitialPlayerResponse + videoId proof that a real watch page loaded. Without
# it, the top-level gate in parse_caption_state() would read every one of them
# as "undetermined" before ever reaching the caption logic each fixture exists
# to exercise. These are file-level because five separate sections drive them.
REAL_PAGE_MARKER <- paste0(
  '"ytInitialPlayerResponse":{"playabilityStatus":{"status":"OK"},',
  '"videoDetails":{"videoId":"abc123XYZ9"}},')

auto_only_page <- paste0(REAL_PAGE_MARKER,
  'noise noise "captionTracks":[{"baseUrl":"u","name":{"simpleText":',
  '"English (auto-generated)"},"vssId":"a.en","languageCode":"en",',
  '"kind":"asr","isTranslatable":true,"trackName":""}],',
  '"audioTracks":[{"x":1}] more noise')
mixed_page <- paste0(REAL_PAGE_MARKER,
  'noise "captionTracks":[{"baseUrl":"u1","name":{"simpleText":"English"},',
  '"vssId":".en","languageCode":"en","isTranslatable":true,"trackName":""},',
  '{"baseUrl":"u2","name":{"simpleText":"English (auto-generated)"},',
  '"vssId":"a.en","languageCode":"en","kind":"asr","isTranslatable":true,',
  '"trackName":""}],"audioTracks":[{"x":1}] more noise')
genuine_none_page   <- paste0(REAL_PAGE_MARKER, " no caption signal of any kind here")
tracklist_only_page <- paste0(REAL_PAGE_MARKER,
  " stuff playerCaptionsTracklistRenderer stuff, no tracks array here")
malformed_page      <- paste0(REAL_PAGE_MARKER,
  ' weird "captionTracks": true, no array here, "somethingElse":[1,2,3]')

# A video whose account was terminated returns HTTP 200 with a real
# ytInitialPlayerResponse but playabilityStatus.status "ERROR" and reason
# "Video unavailable". This must resolve to "unavailable", never "none", which
# would misreport a dead video as merely uncaptioned.
unavailable_page <- paste0(
  '"ytInitialPlayerResponse":{"playabilityStatus":{"status":"ERROR",',
  '"reason":"Video unavailable","errorScreen":{}},',
  '"videoDetails":{"videoId":"deadDEAD01"}}')

# No ytInitialPlayerResponse and no videoId marker at all. This is what a
# bot-check interstitial, a consent page, or a private/region-blocked redirect
# look like: HTTP 200, no error thrown, but not YouTube's real player response.
# The old code read this exact shape as "none" (no captionTracks, no
# tracklistRenderer, therefore "this video has no captions"), which is precisely
# the false claim a live fetch caught. A dead video and an unreadable page are
# not the same fact as "no captions".
no_signal_page <- "no signal here at all, no player response marker of any kind"
interstitial_page <- paste0(
  "<html><body>Before you continue to YouTube ",
  "<form action='https://consent.youtube.com/save'>",
  "we use cookies and data to...</form></body></html>")

test_that("cartridge: iframes, weblinks, and broken embeds, synthetic export", {
  skip_if_no("zip")
  # The snapshot audited a real Canvas export of a real course and asserted its
  # measured counts (6 iframes, 3 of them untitled; 32 weblinks, none weak; one
  # dead embed). That file is one course's content and does not ship with the
  # package, so the fixture carries the same SHAPES and the counts are
  # hand-typed for it: a titled iframe sits beside the untitled one in the same
  # wiki_content directory, so a check that flagged every iframe would report 2
  # and a check that flagged none would report 0. Only a check that reads the
  # title attribute lands on 1.
  d <- withr::local_tempdir()
  z <- write_a11y_cartridge(file.path(d, "course-a.imscc"))

  # Deterministic and network-free: the one embed resolves through an injected
  # fetcher returning the real dead-video payload shape.
  dead_fetch <- function(id) unavailable_page
  cf <- audit_cartridge(z, surface = "course-a-cartridge", video_fetch = dead_fetch)

  expect_identical(unique(cf$surface), "course-a-cartridge",
    info = "surface carries the caller-supplied course origin, not a constant")

  untitled <- cf[cf$criterion == "4.1.2", , drop = FALSE]
  weak     <- cf[cf$criterion == "2.4.4", , drop = FALSE]
  broken   <- cf[cf$criterion == "broken-embed", , drop = FALSE]

  expect_identical(nrow(untitled), 1L,
    info = "finds exactly the untitled iframe, not the titled one beside it")
  expect_identical(all(grepl("modules.yml|cartridge builder", untitled$fix_target)), TRUE,
    info = "fix target is the generator")
  expect_identical(all(is.na(untitled$level)), TRUE,
    info = "no level is invented for untitled-iframe findings")

  expect_identical(nrow(weak), 1L,
    info = "the weblink whose text says nothing out of context is flagged")

  # A broken embed is a more urgent defect than any caption gap it might be
  # hiding behind, so audit_cartridge() resolves every embedded video's
  # availability and emits its own finding for a dead one.
  expect_identical(nrow(broken), 1L,
    info = "audit_cartridge emits exactly one broken-embed finding for the dead video")
  expect_identical(broken$file[1], "syllabus.html",
    info = "the broken-embed finding names the file with the dead embed")
  expect_identical(grepl("modules.yml|cartridge builder", broken$fix_target[1]), TRUE,
    info = "broken-embed fix target is the generator, same as other cartridge findings")
  expect_identical(is.na(broken$level[1]), TRUE,
    info = "broken-embed carries no invented WCAG level (it is not a WCAG criterion at all)")

  # How many wiki pages this call actually read, taken from the code path that
  # did the work rather than from a second read of the declaration. A cartridge
  # holding one wiki page and one holding a hundred must not contribute the
  # same figure to a count of real HTML pages.
  expect_identical(attr(cf, "wiki_pages_read"), 2L,
    info = "the audit reports the wiki pages it actually read")
})

test_that("a topic body with a bare-URL link produces one 2.4.4 finding, attributed to the body file", {
  skip_if_no("zip")
  z <- write_a11y_cartridge(tempfile(fileext = ".imscc"),
         topics = list(list(id = "gtopic1", title = "Week 1", html = '<p>See <a href="https://example.invalid/x">https://example.invalid/x</a></p>')))
  res <- audit_cartridge(z, surface = "t-cartridge")
  hit <- res[res$criterion == "2.4.4" & res$file == "gtopic1.xml", ]
  expect_equal(nrow(hit), 1L)
  expect_equal(attr(res, "topics_read"), 1L)
})

test_that("cartridge: announcement bodies, discrimination and attribution", {
  skip_if_no("zip")
  # The body arrives XML-ESCAPED inside <text texttype="text/html">, so a
  # check that read the raw .xml would see `&lt;a href=...` and find no tags at
  # all. Four topics side by side: one bare-URL link (flagged), one link whose
  # text describes its destination (not flagged), one untitled iframe
  # (flagged), and one titled iframe (not flagged). A check that reported
  # everything fails the two negatives; one that reported nothing fails the two
  # positives; one that skipped the unescape fails all four.
  z <- write_a11y_cartridge(
    tempfile(fileext = ".imscc"),
    topics = list(
      list(id = "gtopicA", title = "Week 1", html = paste0(
        '<p>See <a href="https://example.invalid/a">https://example.invalid/a</a>',
        ' and <a href="https://example.invalid/b">the week 1 reading list</a></p>')),
      list(id = "gtopicB", title = "Week 2", html = paste0(
        '<p><iframe src="https://example.invalid/untitled"></iframe>',
        '<iframe title="Week 2 walkthrough" src="https://example.invalid/titled"></iframe></p>'))))
  res <- audit_cartridge(z, surface = "ann-cartridge",
                         video_fetch = function(id) unavailable_page)

  weak <- res[res$criterion == "2.4.4" & res$file == "gtopicA.xml", , drop = FALSE]
  expect_identical(nrow(weak), 1L,
    info = "exactly the bare-URL link in the announcement body is flagged")
  expect_identical(grepl("example.invalid/a", weak$selector[1], fixed = TRUE), TRUE,
    info = "and the finding names that link, not the descriptive one beside it")
  expect_identical(weak$fix_target[1], "the announcement body file",
    info = "an announcement body is authored, so the fix goes to the body file, not the generator")

  frames <- res[res$criterion == "4.1.2" & res$file == "gtopicB.xml", , drop = FALSE]
  expect_identical(nrow(frames), 1L,
    info = "exactly the untitled iframe inside the announcement body is flagged")
  expect_identical(grepl("untitled", frames$selector[1], fixed = TRUE), TRUE,
    info = "and it is the untitled one, not the titled one beside it")
  expect_identical(frames$fix_target[1], "the announcement body file",
    info = "the iframe finding is attributed to the body file too")

  expect_identical(attr(res, "topics_read"), 2L,
    info = "both topic bodies are counted as read")
  expect_identical(attr(res, "wiki_pages_read"), 2L,
    info = "and the wiki-page count is unchanged by the topics beside it")

  # The id hashes the file, so re-attributing a finding to the topic it came
  # from has to recompute it. Two topics carrying the byte-identical defect
  # would otherwise share one id and report_and_dedup() would silently drop the
  # second as "the same finding, seen twice".
  same <- write_a11y_cartridge(
    tempfile(fileext = ".imscc"),
    topics = list(
      list(id = "gtopicC", title = "One", html = '<p><iframe src="https://example.invalid/same"></iframe></p>'),
      list(id = "gtopicD", title = "Two", html = '<p><iframe src="https://example.invalid/same"></iframe></p>')))
  res2 <- audit_cartridge(same, surface = "twin-cartridge",
                          video_fetch = function(id) unavailable_page)
  twins <- res2[res2$criterion == "4.1.2" &
                res2$file %in% c("gtopicC.xml", "gtopicD.xml"), , drop = FALSE]
  expect_identical(nrow(twins), 2L,
    info = "the identical defect in two topics is two findings")
  expect_identical(length(unique(twins$id)), 2L,
    info = "with distinct ids, so neither disappears into the other as a duplicate")
})

test_that("cartridge: a textless link in an announcement body, and the one that only looks textless", {
  skip_if_no("zip")
  # An announcement body is authored prose, so unlike a <webLink> resource its
  # links can wrap other elements. A link holding nothing at all has no
  # accessible name and fails 2.4.4 exactly as an empty <title></title> does; a
  # link wrapping an image with real alt text has a perfectly good name that
  # simply is not a text node, and reporting it would be a false positive.
  z <- write_a11y_cartridge(
    tempfile(fileext = ".imscc"),
    topics = list(list(id = "gtopicE", title = "Week 3", html = paste0(
      '<p><a href="https://example.invalid/textless"></a>',
      '<a href="https://example.invalid/mapped">',
      '<img src="map.png" alt="The week 3 study map"></a></p>'))))
  res <- audit_cartridge(z, surface = "textless-cartridge",
                         video_fetch = function(id) unavailable_page)
  weak <- res[res$criterion == "2.4.4" & res$file == "gtopicE.xml", , drop = FALSE]
  expect_identical(nrow(weak), 1L,
    info = "exactly the link with no accessible name at all is flagged")
  expect_identical(grepl("textless", weak$selector[1], fixed = TRUE), TRUE,
    info = "and it is the empty one, not the image link beside it")
  expect_identical(grepl("no text at all", weak$issue[1]), TRUE,
    info = "the textless issue text is distinct from the weak-text one, as it is for weblinks")
})

test_that("cartridge: a cartridge with no topics reports topics_read 0", {
  skip_if_no("zip")
  # The counter must exist and read zero, rather than being absent, on a
  # cartridge that holds no announcements at all: absent and zero are the same
  # distinction wiki_pages_read already draws.
  z <- write_a11y_cartridge(tempfile(fileext = ".imscc"))
  res <- audit_cartridge(z, surface = "no-topics-cartridge",
                         video_fetch = function(id) unavailable_page)
  expect_identical(attr(res, "topics_read"), 0L,
    info = "no topics in the cartridge is an honest 0, not a missing attribute")
})

test_that("cartridge: discrimination fixture (positive and negative in one cartridge)", {
  skip_if_no("zip")
  # Builds one small real .imscc-shaped zip carrying, side by side: an iframe
  # with no title (should be flagged) and one with a title (should not), and
  # a weblink resource with a weak title (should be flagged) and one with a
  # descriptive title (should not). A check that always returns empty fails
  # both "exactly one" assertions below; a check that flags every iframe or
  # every weblink regardless of its title also fails them, because it would
  # catch the negative case too.
  fx_root <- file.path(tempdir(), "cartridge_fixture"); unlink(fx_root, recursive = TRUE)
  dir.create(file.path(fx_root, "wiki_content"), recursive = TRUE)
  writeLines(paste0(
    "<html><body>",
    "<iframe src='https://example.invalid/frame-a'></iframe>",
    "</body></html>"), file.path(fx_root, "wiki_content", "no-title.html"))
  writeLines(paste0(
    "<html><body>",
    "<iframe title='Course intro video' src='https://example.invalid/frame-b'></iframe>",
    "</body></html>"), file.path(fx_root, "wiki_content", "has-title.html"))
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<webLink xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imswl_v1p1">',
    '  <title>Click here</title>',
    '  <url href="https://example.invalid/weak"/>',
    '</webLink>'), file.path(fx_root, "weak-link.xml"))
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<webLink xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imswl_v1p1">',
    '  <title>Reading: Chapter 1</title>',
    '  <url href="https://example.invalid/good"/>',
    '</webLink>'), file.path(fx_root, "good-link.xml"))

  fx_zip <- zip_cartridge(fx_root, file.path(tempdir(), "cartridge_fixture.imscc"))

  cf_fx       <- audit_cartridge(fx_zip, surface = "fixture-course-a-cartridge")
  fx_untitled <- cf_fx[cf_fx$criterion == "4.1.2", , drop = FALSE]
  fx_weak     <- cf_fx[cf_fx$criterion == "2.4.4", , drop = FALSE]
  expect_identical(nrow(fx_untitled), 1L,
    info = "fixture: exactly the untitled iframe is flagged")
  expect_identical(any(grepl("has-title.html", fx_untitled$file)), FALSE,
    info = "fixture: the titled iframe is not flagged")
  expect_identical(nrow(fx_weak), 1L,
    info = "fixture: exactly the weak-text link is flagged")
  expect_identical(any(grepl("good-link.xml", fx_weak$file)), FALSE,
    info = "fixture: the descriptive link is not flagged")
})

test_that("cartridge: empty-title and case-insensitivity fixtures (findings 2, 3, 5)", {
  skip_if_no("zip")
  # Finding 2 (critical): title="" used to count as titled, because the old
  # check only tested for the attribute's presence, never its value. Finding 5
  # (minor): an uppercase <IFRAME> tag was invisible to the check entirely (the
  # unsafe direction), while an uppercase TITLE= was misread as absent (the
  # safe direction, but still worth fixing since it was a false positive).
  # Both are exercised in one fixture: an empty title (must be flagged) next to
  # an uppercase tag carrying a real title (must not be).
  fx2_root <- file.path(tempdir(), "cartridge_fixture_empty_title")
  unlink(fx2_root, recursive = TRUE)
  dir.create(file.path(fx2_root, "wiki_content"), recursive = TRUE)
  writeLines(paste0(
    "<html><body>",
    "<iframe title='' src='https://example.invalid/frame-empty'></iframe>",
    "<IFRAME TITLE='Uppercase tag and attribute, real text' ",
    "src='https://example.invalid/frame-upper'></IFRAME>",
    "</body></html>"), file.path(fx2_root, "wiki_content", "empty-title.html"))
  fx2_zip <- zip_cartridge(fx2_root,
                           file.path(tempdir(), "cartridge_fixture_empty_title.imscc"))
  # No YouTube URLs in this fixture, so the broken-embed check never calls the
  # fetcher; the stop() is there so a future edit that accidentally adds one
  # fails loudly here instead of quietly reaching the real network.
  cf2 <- audit_cartridge(fx2_zip, surface = "fixture-empty-title-cartridge",
                         video_fetch = function(id) stop("unexpected fetch in a no-video fixture"))
  u2 <- cf2[cf2$criterion == "4.1.2", , drop = FALSE]
  expect_identical(any(grepl("frame-empty", u2$selector)), TRUE,
    info = "title=\"\" is flagged as untitled, same as a missing title")
  expect_identical(any(grepl("frame-upper", u2$selector)), FALSE,
    info = "an uppercase IFRAME/TITLE with real text is correctly read, not flagged")
  expect_identical(nrow(u2), 1L,
    info = "exactly the one empty-title iframe is flagged in this fixture")

  # Finding 3 (important): the weblink check's exact same gap, <title></title>.
  fx3_root <- file.path(tempdir(), "cartridge_fixture_empty_link_title")
  unlink(fx3_root, recursive = TRUE)
  dir.create(fx3_root, recursive = TRUE)
  writeLines(c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<webLink xmlns="http://www.imsglobal.org/xsd/imsccv1p1/imswl_v1p1">',
    '  <title></title>',
    '  <url href="https://example.invalid/empty"/>',
    '</webLink>'), file.path(fx3_root, "empty-title-link.xml"))
  fx3_zip <- zip_cartridge(fx3_root,
                           file.path(tempdir(), "cartridge_fixture_empty_link_title.imscc"))
  cf3 <- audit_cartridge(fx3_zip, surface = "fixture-empty-link-cartridge",
                         video_fetch = function(id) stop("unexpected fetch in a no-video fixture"))
  w3 <- cf3[cf3$criterion == "2.4.4", , drop = FALSE]
  expect_identical(nrow(w3), 1L,
    info = "an empty <title></title> weblink is flagged, not silently skipped")
  expect_identical(grepl("no text at all", w3$issue[1]), TRUE,
    info = "the empty-title issue text is distinct from the weak-text issue text")
})

test_that("cartridge: broken-embed discrimination (injected fetcher, no network)", {
  skip_if_no("zip")
  # Finding 1c, discrimination: one fixture with two embedded videos, one dead
  # and one working, driven entirely by an injected fetcher so this is
  # deterministic and network-free. A check that always emits a finding would
  # fail "the working video does not"; a check that never does would fail
  # "exactly the dead video gets a broken-embed finding".
  fx4_root <- file.path(tempdir(), "cartridge_fixture_broken_embed")
  unlink(fx4_root, recursive = TRUE)
  dir.create(file.path(fx4_root, "wiki_content"), recursive = TRUE)
  writeLines(paste0(
    "<html><body>",
    "<iframe title='Dead video' src='https://www.youtube-nocookie.com/embed/DEADVIDEOID1'></iframe>",
    "<iframe title='Working video' src='https://www.youtube-nocookie.com/embed/OKVIDEOID111'></iframe>",
    "</body></html>"), file.path(fx4_root, "wiki_content", "videos.html"))
  fx4_zip <- zip_cartridge(fx4_root,
                           file.path(tempdir(), "cartridge_fixture_broken_embed.imscc"))
  fake_video_fetch <- function(id) {
    if (identical(id, "DEADVIDEOID1")) {
      paste0('"ytInitialPlayerResponse":{"playabilityStatus":{"status":"ERROR",',
             '"reason":"Video unavailable"},"videoDetails":{"videoId":"DEADVIDEOID1"}}')
    } else {
      paste0('"ytInitialPlayerResponse":{"playabilityStatus":{"status":"OK"},',
             '"videoDetails":{"videoId":"OKVIDEOID111"}}; "captionTracks":[{"baseUrl":"u",',
             '"name":{"simpleText":"e"},"vssId":".en","languageCode":"en",',
             '"isTranslatable":true,"trackName":""}],"audioTracks":[{"x":1}]')
    }
  }
  cf4 <- audit_cartridge(fx4_zip, surface = "fixture-broken-embed-cartridge",
                         video_fetch = fake_video_fetch)
  b4 <- cf4[cf4$criterion == "broken-embed", , drop = FALSE]
  expect_identical(nrow(b4), 1L,
    info = "exactly the dead video gets a broken-embed finding")
  expect_identical(any(grepl("OKVIDEOID111", b4$selector)), FALSE,
    info = "the working video does not get a broken-embed finding")
  expect_identical(any(grepl("DEADVIDEOID1", b4$selector)), TRUE,
    info = "the dead video's id is named in the finding's selector")
})

test_that("cartridge: two different courses' findings never merge (Finding 4)", {
  skip_if_no("zip")
  # All three cartridge checks used to hardcode surface = "cartridge"
  # regardless of which repo's .imscc was being audited. Auditing more than one
  # course in one invocation is explicitly supported, and two different
  # courses' cartridges can share a conventionally-named wiki page
  # ("syllabus.html") carrying the identical untitled iframe, built here as two
  # BYTE-IDENTICAL cartridges standing in for two different, unrelated courses
  # that happen to look alike. Before the fix, both cartridges' findings would
  # have shared the exact same (surface, file, criterion, selector) key
  # regardless of which course each came from, and report_and_dedup() would
  # have silently treated the second course's real, distinct finding as "the
  # same finding, seen twice" and discarded it: a false negative, not a crash,
  # so nobody would have known.
  two_course_root <- file.path(tempdir(), "two_course_cartridge_fixture")
  unlink(two_course_root, recursive = TRUE)
  dir.create(file.path(two_course_root, "wiki_content"), recursive = TRUE)
  writeLines(paste0(
    "<html><body>",
    "<iframe src='https://example.invalid/course-syllabus-frame'></iframe>",
    "</body></html>"), file.path(two_course_root, "wiki_content", "syllabus.html"))
  two_course_zip <- zip_cartridge(
    two_course_root, file.path(tempdir(), "two_course_cartridge_fixture.imscc"))

  cf_course_a <- audit_cartridge(two_course_zip, surface = "course-a-cartridge")
  cf_course_b <- audit_cartridge(two_course_zip, surface = "course-b-cartridge")
  expect_identical(nrow(cf_course_a), 1L,
    info = "course A's fixture produces the untitled-iframe finding")
  expect_identical(nrow(cf_course_b), 1L,
    info = "course B's fixture produces the untitled-iframe finding")
  expect_identical(
    identical(cf_course_a[, c("file", "criterion", "selector")],
              cf_course_b[, c("file", "criterion", "selector")]),
    TRUE,
    info = "both courses' findings share the same file, criterion, and selector")
  expect_identical(c(cf_course_a$surface, cf_course_b$surface),
                   c("course-a-cartridge", "course-b-cartridge"),
    info = "but carry the caller-supplied surface, not a shared constant")

  both_courses <- rbind(cf_course_a, cf_course_b)
  expect_identical(length(unique(both_courses$id)), 2L,
    info = "with everything else identical, the surface difference alone gives them distinct ids")

  deduped_both <- report_and_dedup(both_courses, quiet = TRUE)
  expect_identical(nrow(deduped_both), 2L,
    info = "report_and_dedup() keeps BOTH courses' findings, not just one")
  expect_identical(attr(deduped_both, "n_removed"), 0L,
    info = "nothing was removed: two different courses' findings are not duplicates of each other")
  expect_identical(length(attr(deduped_both, "collided_ids")), 0L,
    info = "neither is flagged as a collision either, they are simply two separate, real findings")
})

test_that("video caption state: synthetic payload discrimination", {
  # parse_caption_state() is the pure half of video_caption_state(): given the
  # text of a watch page, it never touches the network, so these cases are
  # deterministic where a live YouTube fetch would not be. Modeled directly on
  # real payload shapes captured from real embeds.
  expect_identical(parse_caption_state(auto_only_page), "auto-only",
    info = "every track is asr, real page -> auto-only")
  expect_identical(parse_caption_state(mixed_page), "captions",
    info = "a manual track alongside the asr fallback, real page -> captions, not auto-only")
  expect_identical(parse_caption_state(genuine_none_page), "none",
    info = "real page, genuinely no caption signal -> none")
  expect_identical(parse_caption_state(tracklist_only_page), "undetermined",
    info = "real page, tracklist renderer present but no track array -> undetermined")
  expect_identical(parse_caption_state(malformed_page), "undetermined",
    info = "real page, captionTracks present but not in the expected shape -> undetermined, not a guess")
  expect_identical(parse_caption_state(unavailable_page), "unavailable",
    info = "playabilityStatus ERROR with reason Video unavailable -> unavailable, not none")
  expect_identical(parse_caption_state(no_signal_page), "undetermined",
    info = "no ytInitialPlayerResponse/videoId marker at all -> undetermined, NOT none (finding 1's root cause)")
  expect_identical(parse_caption_state(interstitial_page), "undetermined",
    info = "a consent/bot-check-interstitial-shaped page -> undetermined, NOT none")
})

test_that("video caption state: the network wrapper itself, driven by an injected fetcher", {
  # Finding 4 (important): every check above this point, before the revision
  # that added it, asserted only membership in the state set against the REAL
  # network wrapper, which a stub ignoring its argument and always returning
  # "undetermined" would also pass. These drive video_caption_state() itself
  # (not parse_caption_state()) through an injected fetch function, proving the
  # fetch to parse wiring actually works and that a real network failure
  # degrades correctly, not just that the parser does when handed a string
  # directly.
  expect_identical(video_caption_state("any-id", fetch = function(id) mixed_page),
                   "captions",
    info = "wrapper: a frozen captioned payload reaches parse_caption_state via the real wrapper")
  expect_identical(video_caption_state("any-id", fetch = function(id) genuine_none_page),
                   "none",
    info = "wrapper: a frozen no-caption payload reaches the wrapper as none")
  expect_identical(video_caption_state("any-id", fetch = function(id) unavailable_page),
                   "unavailable",
    info = "wrapper: a frozen unavailable payload reaches the wrapper as unavailable")

  # Not a mocked failure: a real R networking error from a connection nothing
  # is listening on (loopback port 1, refused essentially instantly on any
  # machine, no DNS involved so no risk of a wildcard resolver making this
  # flaky). This is what proves the tryCatch() in video_caption_state() itself
  # survives a genuine connection failure, not just a stub that hands back NA
  # directly.
  refused_fetch <- function(id) {
    paste(readLines("http://127.0.0.1:1/", warn = FALSE), collapse = "")
  }
  expect_identical(video_caption_state("any-id", fetch = refused_fetch), "undetermined",
    info = "wrapper: a genuine refused connection degrades to undetermined, never a caption claim")
})

test_that("video caption state: unknown id (network)", {
  if (!nzchar(Sys.getenv("COURSEPACK_NETWORK_TESTS"))) {
    testthat::skip("COURSEPACK_NETWORK_TESTS is not set")
  }
  # A syntactically invalid id is served as a real player response with
  # playabilityStatus ERROR ("Video unavailable"), the same shape as a
  # genuinely deleted video. "unavailable" is the expected value;
  # "undetermined" stays accepted alongside it only because a real network call
  # to a third party can legitimately fail this run for reasons unrelated to
  # the code being tested.
  expect_identical(
    video_caption_state("zzzzINVALIDzzz") %in% c("unavailable", "undetermined"),
    TRUE,
    info = "unknown id is unavailable, or undetermined if the network failed this run")
})

test_that("video caption state: real ids over the network", {
  if (!nzchar(Sys.getenv("COURSEPACK_NETWORK_TESTS"))) {
    testthat::skip("COURSEPACK_NETWORK_TESTS is not set")
  }
  # Not asserted against a specific state per id: a live fetch against a third
  # party is exactly what the cartridge library's own header warns will be
  # flaky, and the true state can legitimately change later (real captions get
  # added, or a dead video's channel comes back). What IS asserted, per id, is
  # that the call completes and returns one of the five documented states: it
  # must never error on real production input and must never answer outside its
  # own contract. The ids are opaque public YouTube ids kept from the snapshot
  # so this runs against real production input rather than a payload the suite
  # wrote itself.
  VALID_CAPTION_STATES <- c("captions", "auto-only", "none", "unavailable", "undetermined")
  real_video_ids <- c("K3GMkWfpj4s", "C4sptqFb0Bk", "7ggoO2LZsY0", "6xaVenzT3Dk")
  for (vid in real_video_ids) {
    st <- tryCatch(video_caption_state(vid), error = function(e) NA_character_)
    if (is.na(st)) {
      testthat::skip(paste0("the network call for ", vid, " errored"))
    }
    expect_identical(st %in% VALID_CAPTION_STATES, TRUE,
      info = paste0("video_caption_state(", vid, ") returns a documented state"))
  }
})

test_that("non-HTML media inventory: fixture discrimination", {
  # One small repo carrying, side by side: files that must survive the filter
  # (a real image, a real pdf) and files that must not (one per exclusion
  # rule: docs/, .quarto/, an _files/ directory, and .Rproj.user/, an editor's
  # own gitignored session cache, which still leaves real image files on disk).
  # A version of inventory_media() that always returned everything would fail
  # every "excludes" check below; a version that always returned nothing would
  # fail every "includes" check.
  im_root <- file.path(tempdir(), "inv_fixture"); unlink(im_root, recursive = TRUE)
  dir.create(file.path(im_root, "docs"), recursive = TRUE)
  dir.create(file.path(im_root, ".quarto"), recursive = TRUE)
  dir.create(file.path(im_root, "img"), recursive = TRUE)
  dir.create(file.path(im_root, "lecture_notes"), recursive = TRUE)
  dir.create(file.path(im_root, "ch1_files"), recursive = TRUE)
  dir.create(file.path(im_root, ".Rproj.user", "tmp"), recursive = TRUE)
  writeLines("x", file.path(im_root, "docs", "excluded.png"))
  writeLines("x", file.path(im_root, ".quarto", "excluded.pdf"))
  writeLines("x", file.path(im_root, "img", "included.png"))
  writeLines("x", file.path(im_root, "lecture_notes", "included.pdf"))
  writeLines("x", file.path(im_root, "ch1_files", "excluded.png"))
  writeLines("x", file.path(im_root, ".Rproj.user", "tmp", "excluded.png"))
  inv <- inventory_media(im_root)
  expect_identical("img/included.png" %in% inv$ref, TRUE,
    info = "inventory: includes a real image")
  expect_identical("lecture_notes/included.pdf" %in% inv$ref, TRUE,
    info = "inventory: includes a real pdf")
  expect_identical("docs/excluded.png" %in% inv$ref, FALSE,
    info = "inventory: excludes docs/")
  expect_identical(".quarto/excluded.pdf" %in% inv$ref, FALSE,
    info = "inventory: excludes .quarto/")
  expect_identical("ch1_files/excluded.png" %in% inv$ref, FALSE,
    info = "inventory: excludes an _files/ dir")
  expect_identical(".Rproj.user/tmp/excluded.png" %in% inv$ref, FALSE,
    info = "inventory: excludes .Rproj.user/")
  expect_identical(nrow(inv), 2L,
    info = "inventory: exactly the 2 real files survive")
})

test_that("non-HTML media inventory: a repository fixture on disk", {
  # The snapshot ran this against whatever real textbook repository an
  # environment variable pointed at, asserting the PDF count fell in the range
  # its working-file directory produced and that its `bibtex/` directory was
  # excluded. No real repository ships here, so the same two properties are
  # asserted against a copy of the `pair/alpha` fixture with one image, one
  # published PDF, and one PDF under `bibtex/` written into it: the count is
  # exact rather than a range, because the fixture's contents are hand-typed.
  d <- withr::local_tempdir()
  ok <- file.copy(fixture_path("pair", "alpha"), d, recursive = TRUE)
  expect_identical(all(ok), TRUE, info = "the fixture repository copied")
  repo <- file.path(d, "alpha")
  dir.create(file.path(repo, "img"))
  dir.create(file.path(repo, "handouts"))
  dir.create(file.path(repo, "bibtex"))
  writeLines("x", file.path(repo, "img", "figure.png"))
  writeLines("x", file.path(repo, "handouts", "week1.pdf"))
  writeLines("x", file.path(repo, "bibtex", "refs.pdf"))

  inv_real <- inventory_media(repo)
  expect_identical(sum(inv_real$kind == "pdf"), 1L,
    info = "the pdf inventory counts the published pdf, not the raw unfiltered count")
  expect_identical(any(grepl("^bibtex/", inv_real$ref)), FALSE,
    info = "the pdf inventory excludes bibtex/")
  expect_identical(sum(inv_real$kind == "image"), 1L,
    info = "and the one real image is inventoried alongside it")
})

test_that("negative control: caption state never claims 'none' without proof a page loaded", {
  # An even more extreme case than the no_signal_page/interstitial_page
  # fixtures proven earlier in this file: a genuinely empty response body,
  # the shape a totally dead connection or an empty HTTP 200 would produce.
  # This must read as "undetermined", never "none". "none" is a claim about
  # a real, loaded, confirmed-uncaptioned video, and an empty string proves
  # nothing about any video at all.
  expect_identical(parse_caption_state(""), "undetermined",
    info = "negative control: a genuinely empty response is undetermined, not none")
  expect_identical(
    parse_caption_state(paste0(REAL_PAGE_MARKER, " nothing caption-shaped here at all")),
    "none",
    info = "negative control: a real, loaded page with zero caption signal is genuinely none")
})

test_that("C2: the caption states that were computed and thrown away", {
  skip_if_no("zip")
  # parse_caption_state() computed five states; check_unavailable_videos()
  # emitted a finding for exactly one. "none" and "auto-only" are real Level A
  # failures under WCAG 1.2.2 and produced silence; "undetermined" means the
  # tool could not verify and also produced silence. Verified against the
  # shipped JSON before this fix: zero findings under any 1.2.x criterion,
  # while three documents said captions were checked.
  #
  # One fixture, five videos, one injected fetcher: a check that emitted a
  # caption finding for everything would fail the captioned and unavailable
  # cases; a check that emitted none would fail the other three.
  c2_root <- file.path(tempdir(), "c2_caption_fixture"); unlink(c2_root, recursive = TRUE)
  dir.create(file.path(c2_root, "wiki_content"), recursive = TRUE)
  writeLines(paste0("<html><body>",
    "<iframe title='t' src='https://www.youtube-nocookie.com/embed/NOCAPSVIDEO'></iframe>",
    "<iframe title='t' src='https://www.youtube-nocookie.com/embed/AUTOONLYVID'></iframe>",
    "<iframe title='t' src='https://www.youtube-nocookie.com/embed/REALCAPSVID'></iframe>",
    "<iframe title='t' src='https://www.youtube-nocookie.com/embed/DEADVIDEO01'></iframe>",
    "<iframe title='t' src='https://www.youtube-nocookie.com/embed/UNKNOWNVID1'></iframe>",
    "</body></html>"), file.path(c2_root, "wiki_content", "videos.html"))
  c2_zip <- zip_cartridge(c2_root, file.path(tempdir(), "c2_caption_fixture.imscc"))

  c2_fetch <- function(id) switch(id,
    "NOCAPSVIDEO" = genuine_none_page,
    "AUTOONLYVID" = auto_only_page,
    "REALCAPSVID" = mixed_page,
    "DEADVIDEO01" = unavailable_page,
    no_signal_page)                       # UNKNOWNVID1 -> undetermined

  c2_cf  <- audit_cartridge(c2_zip, surface = "c2-cartridge", video_fetch = c2_fetch)
  c2_cap <- c2_cf[c2_cf$criterion == "1.2.2", , drop = FALSE]
  expect_identical(sum(grepl("NOCAPSVIDEO", c2_cap$selector)), 1L,
    info = "C2: a video with no captions produces a 1.2.2 finding")
  expect_identical(sum(grepl("AUTOONLYVID", c2_cap$selector)), 1L,
    info = "C2: auto-generated captions alone also fail 1.2.2")
  expect_identical(
    unique(c2_cap$severity[grepl("NOCAPSVIDEO|AUTOONLYVID", c2_cap$selector)]),
    "serious",
    info = "C2: both of those are serious, not advisory")
  expect_identical(any(grepl("REALCAPSVID", c2_cap$selector)), FALSE,
    info = "C2: a genuinely captioned video produces no caption finding")
  expect_identical(any(grepl("DEADVIDEO01", c2_cap$selector)), FALSE,
    info = "C2: an unavailable video produces no caption finding (there is no video to caption)")
  expect_identical(
    sum(grepl("DEADVIDEO01", c2_cf$selector[c2_cf$criterion == "broken-embed"])), 1L,
    info = "C2: but it still produces its broken-embed finding")
  expect_identical(sum(grepl("UNKNOWNVID1", c2_cap$selector)), 1L,
    info = "C2: 'could not verify' appears in the document as a review row, never as silence")
  expect_identical(c2_cap$severity[grepl("UNKNOWNVID1", c2_cap$selector)], "review",
    info = "C2: and it is review severity, not a failure claim")
  expect_identical(
    grepl("UNKNOWNVID1", c2_cap$detail[grepl("UNKNOWNVID1", c2_cap$selector)]), TRUE,
    info = "C2: the undetermined row names the video id a person has to go look at")
  expect_identical(nrow(c2_cap), 3L,
    info = "C2: exactly three caption findings from five videos")
  expect_identical(all(grepl("modules.yml|cartridge builder", c2_cap$fix_target)), TRUE,
    info = "C2: caption findings name the generator, not the built zip")
  expect_identical(all(is.na(c2_cap$level)), TRUE,
    info = "C2: no WCAG level is invented at check-authoring time")

  # A caption finding arrives with fix_target already set, which is exactly the
  # shape that lands in class (a) ("already targeted") unless 1.2.2 is
  # protected the way 1.1.1 and 2.4.4 are. One generator edit titles every
  # iframe; no generator edit captions a video.
  c2_cls <- classify_fixes(c2_cap, list(stylesheet = NA_character_,
                                        framework = NA_character_,
                                        repo = NA_character_))
  expect_identical(unique(c2_cls$fix_class), "c",
    info = "C2: captioning is class (c) human work, never a shared-edit class (a) promise")
  expect_identical(unique(c2_cls$leverage), 1L,
    info = "C2: and no caption finding claims leverage over another")

  # The real run caught this the moment caption findings started being emitted:
  # a video embedded in TWO cartridges was fetched twice, a live third-party
  # fetch is flaky by construction, the two answers disagreed, and
  # halt_on_collision() stopped the audit because two rows shared a finding id
  # while disagreeing on their own text. A caption state is a property of the
  # video, not of which cartridge embeds it, so the answer is one measurement
  # per video per run. Driven here by a fetcher that returns a DIFFERENT state
  # every time it is called: with the cache doing its job, it is called once,
  # and both cartridges report the same state.
  c2_flaky_states <- c("none", "auto-only", "undetermined")
  c2_flaky_n <- 0L
  c2_flaky_fetch <- function(id) {
    c2_flaky_n <<- c2_flaky_n + 1L
    switch(c2_flaky_states[min(c2_flaky_n, length(c2_flaky_states))],
           "none" = genuine_none_page, "auto-only" = auto_only_page,
           no_signal_page)
  }
  c2_shared_cache <- new.env(parent = emptyenv())
  c2_two_pages <- file.path(tempdir(), "c2_two_pages"); unlink(c2_two_pages, recursive = TRUE)
  dir.create(c2_two_pages, recursive = TRUE)
  for (nm in c("copy1.html", "copy2.html")) {
    writeLines("<iframe src='https://www.youtube-nocookie.com/embed/SAMEVIDEO01'></iframe>",
               file.path(c2_two_pages, nm))
  }
  c2_states_shared <- resolve_video_states(
    list.files(c2_two_pages, full.names = TRUE),
    fetch = c2_flaky_fetch, seen = c2_shared_cache)
  expect_identical(c2_flaky_n, 1L,
    info = "C2: a video embedded twice is fetched exactly once")
  expect_identical(length(unique(vapply(c2_states_shared, function(s) s$state, ""))), 1L,
    info = "C2: and both embeds report the identical state, so no two rows can disagree")
  expect_identical(identical(video_state_cache_for(default_youtube_fetch),
                             video_state_cache_for(default_youtube_fetch)), TRUE,
    info = "C2: the real fetcher shares one session cache across cartridges")
  expect_identical(identical(video_state_cache_for(c2_flaky_fetch),
                             video_state_cache_for(c2_flaky_fetch)), FALSE,
    info = "C2: an injected fetcher never reads another fixture's cached answers")
})

test_that("an undetermined video does not read as a repaired one", {
  # Re-review finding 4: a degraded network makes a real defect look FIXED. An
  # unreachable YouTube resolves a dead embed to "undetermined", its
  # broken-embed finding is absent from the run, and the diff reports it as
  # fixed. The undetermined row is what stands next to that disappearance.
  und_page <- file.path(tempdir(), "und_page.html")
  writeLines("<iframe src='https://www.youtube-nocookie.com/embed/GONEVIDEO01'></iframe>",
             und_page)
  und_state <- resolve_video_states(und_page,
                                    fetch = function(id) no_signal_page,
                                    seen = new.env(parent = emptyenv()))
  und_rows <- check_video_captions(character(), "und-cartridge", states = und_state)
  und <- do.call(rbind, und_rows)
  expect_identical(grepl("availability", und$issue[1]), TRUE,
    info = "undetermined: the row says availability was not established either")
  expect_identical(
    grepl("do NOT read that finding's absence from this run as a fix",
          und$issue[1], fixed = TRUE), TRUE,
    info = "undetermined: and warns against reading a vanished broken-embed finding as a fix")
  expect_identical(
    length(check_unavailable_videos(character(), "und-cartridge", states = und_state)),
    0L,
    info = "undetermined: no broken-embed finding is emitted for it, which is the risk")
})

test_that("I4: the media inventory reaches the report instead of being omitted", {
  # inventory_media() was written, tested, and called by nothing, while the
  # audit's own documentation said non-HTML media is inventoried "so nothing
  # goes missing by silent omission". The inventory was itself the thing going
  # missing by silent omission.
  i4_empty_df <- finding("i4-media-repo", "x", "1.1.1", NA_character_, "x", NA, "serious")[0, ]
  i4_root <- file.path(tempdir(), "i4-media-repo"); unlink(i4_root, recursive = TRUE)
  dir.create(file.path(i4_root, "assets"), recursive = TRUE)
  writeLines("x", file.path(i4_root, "assets", "figure.png"))
  writeLines("x", file.path(i4_root, "assets", "handout.pdf"))
  i4_inv <- inventory_media(i4_root)
  i4_path <- file.path(tempdir(), "i4_report.md")
  render_report(i4_empty_df, list(date = "2026-08-13", tool = "pa11y@9.1.1",
                                  pages_examined = c(`i4-media-repo` = 1L),
                                  surfaces = "i4-media-repo",
                                  failed_pages = character(),
                                  media_inventory = list(`i4-media-repo` = i4_inv)),
                i4_path)
  i4_txt <- paste(readLines(i4_path, warn = FALSE), collapse = "\n")
  expect_identical(
    grepl("Non-HTML media, inventoried not audited", i4_txt, fixed = TRUE), TRUE,
    info = "I4: the inventory section is rendered")
  expect_identical(grepl("| i4-media-repo | image | 1 |", i4_txt, fixed = TRUE), TRUE,
    info = "I4: with the image count")
  expect_identical(grepl("| i4-media-repo | pdf | 1 |", i4_txt, fixed = TRUE), TRUE,
    info = "I4: and the pdf count")

  i4_empty_path <- file.path(tempdir(), "i4_report_empty.md")
  render_report(i4_empty_df,
                list(date = "2026-08-13", tool = "pa11y@9.1.1",
                     pages_examined = c(s = 1L), surfaces = "s",
                     failed_pages = character(),
                     media_inventory = list(s = NULL)), i4_empty_path)
  expect_identical(
    grepl("inventory ran and found no non-HTML media",
          paste(readLines(i4_empty_path, warn = FALSE), collapse = "\n"), fixed = TRUE),
    TRUE,
    info = "I4: a surface with no media says the inventory ran and found nothing")
})

test_that("negative control: declared surfaces, the cartridge-bearing fixtures", {
  skip_if_no("zip")
  # Handed off from test-a11y-targets.R, which ported the page-surface half of
  # this section and named these three as waiting on the cartridge library.
  # They drive intended_surfaces(), which calls cartridges_in() and
  # cartridge_wiki_page_count().
  #
  # Every expectation below is a LITERAL, hand-typed vector: a directory name
  # and a page or wiki-page count chosen when the fixture was built, never a
  # value computed by calling discover_target(), page_surface_name(), or any
  # other function this codebase defines. If the expected value were produced
  # by the same formula as the actual value, this would not be a check.
  #
  # Three fixtures, not three phrasings of one assertion: fixture 2 proves the
  # real function does not OVER-declare (no cartridge directory at all must
  # yield no cartridge surface, not a phantom one), and fixture 3 proves it
  # does not UNDER-declare (two real cartridges under one repo must both be
  # counted and summed, never overwritten by the second or truncated to the
  # first).
  nc_sorted <- function(v) v[order(names(v))]

  # Fixture 1: 3 real rendered pages, one cartridge holding 2 wiki pages.
  nc_decl1 <- file.path(tempdir(), "nc-decl-full"); unlink(nc_decl1, recursive = TRUE)
  dir.create(file.path(nc_decl1, "docs"), recursive = TRUE)
  writeLines("project:\n  type: default\n", file.path(nc_decl1, "_quarto.yml"))
  for (nm in c("a", "b", "c")) {
    writeLines(sprintf("<html lang='en'><title>%s</title><body>%s</body></html>", nm, nm),
               file.path(nc_decl1, "docs", paste0(nm, ".html")))
  }
  nc_decl1_cart_src <- file.path(tempdir(), "nc-decl-full-cart-src")
  unlink(nc_decl1_cart_src, recursive = TRUE)
  dir.create(file.path(nc_decl1_cart_src, "wiki_content"), recursive = TRUE)
  writeLines("<html><body>wiki 1</body></html>",
             file.path(nc_decl1_cart_src, "wiki_content", "w1.html"))
  writeLines("<html><body>wiki 2</body></html>",
             file.path(nc_decl1_cart_src, "wiki_content", "w2.html"))
  dir.create(file.path(nc_decl1, "reference"), recursive = TRUE)
  zip_cartridge(nc_decl1_cart_src, file.path(nc_decl1, "reference", "one.imscc"))

  expect_identical(nc_sorted(intended_surfaces(nc_decl1)),
                   nc_sorted(c("nc-decl-full" = 3L, "nc-decl-full-cartridge" = 2L)),
    info = "negative control: intended_surfaces() on a hand-built 3-page + 2-wiki-page-cartridge fixture matches a hand-typed literal")

  # Fixture 2: 2 real rendered pages, deliberately NO build/coursepack/ or
  # reference/ directory at all, so there is no cartridge to find.
  nc_decl2 <- file.path(tempdir(), "nc-decl-no-cartridge"); unlink(nc_decl2, recursive = TRUE)
  dir.create(file.path(nc_decl2, "docs"), recursive = TRUE)
  writeLines("project:\n  type: default\n", file.path(nc_decl2, "_quarto.yml"))
  for (nm in c("x", "y")) {
    writeLines(sprintf("<html lang='en'><title>%s</title><body>%s</body></html>", nm, nm),
               file.path(nc_decl2, "docs", paste0(nm, ".html")))
  }
  expect_identical(nc_sorted(intended_surfaces(nc_decl2)),
                   nc_sorted(c("nc-decl-no-cartridge" = 2L)),
    info = "negative control: a fixture with no cartridge directory at all declares no cartridge surface (does not over-declare)")

  # Fixture 3: 1 real rendered page, TWO real cartridges under reference/
  # (3 wiki pages + 1 wiki page), which must be summed, not overwritten.
  nc_decl3 <- file.path(tempdir(), "nc-decl-two-cartridges"); unlink(nc_decl3, recursive = TRUE)
  dir.create(file.path(nc_decl3, "docs"), recursive = TRUE)
  writeLines("project:\n  type: default\n", file.path(nc_decl3, "_quarto.yml"))
  writeLines("<html lang='en'><title>only</title><body>only</body></html>",
             file.path(nc_decl3, "docs", "only.html"))
  dir.create(file.path(nc_decl3, "reference"), recursive = TRUE)

  nc_decl3_cart_a_src <- file.path(tempdir(), "nc-decl-two-cart-a-src")
  unlink(nc_decl3_cart_a_src, recursive = TRUE)
  dir.create(file.path(nc_decl3_cart_a_src, "wiki_content"), recursive = TRUE)
  for (nm in c("p1", "p2", "p3")) {
    writeLines(sprintf("<html><body>%s</body></html>", nm),
               file.path(nc_decl3_cart_a_src, "wiki_content", paste0(nm, ".html")))
  }
  zip_cartridge(nc_decl3_cart_a_src, file.path(nc_decl3, "reference", "cart-a.imscc"))

  nc_decl3_cart_b_src <- file.path(tempdir(), "nc-decl-two-cart-b-src")
  unlink(nc_decl3_cart_b_src, recursive = TRUE)
  dir.create(file.path(nc_decl3_cart_b_src, "wiki_content"), recursive = TRUE)
  writeLines("<html><body>only wiki page</body></html>",
             file.path(nc_decl3_cart_b_src, "wiki_content", "q1.html"))
  zip_cartridge(nc_decl3_cart_b_src, file.path(nc_decl3, "reference", "cart-b.imscc"))

  expect_identical(nc_sorted(intended_surfaces(nc_decl3)),
                   nc_sorted(c("nc-decl-two-cartridges" = 1L,
                               "nc-decl-two-cartridges-cartridge" = 4L)),
    info = "negative control: two real cartridges under one repo are summed, not overwritten or truncated to one (does not under-declare)")
})
