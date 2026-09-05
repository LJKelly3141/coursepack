test_that("assignment_group_ids derives or honours ids and checks the percent sum", {
  c1 <- list(canvas = list(group_weighting_scheme = "percent"),
             assignment_groups = list(list(name = "A", weight = 80), list(name = "B", weight = 20, id = "g0123456789abcdef0123456789abcdef")))
  g <- assignment_group_ids(c1)
  expect_named(g, c("A", "B")); expect_equal(unname(g["B"]), "g0123456789abcdef0123456789abcdef")
  expect_match(unname(g["A"]), "^g[0-9a-f]{32}$")
  c1$assignment_groups[[1]]$weight <- 70
  expect_error(assignment_group_ids(c1), "sum to 90, not 100")
  expect_error(group_id_for("Homework", g, "assignment 'hw-1'"), "assignment 'hw-1' names assignment group 'Homework', which is not declared")
})
