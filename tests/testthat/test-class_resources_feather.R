tar_test("create tar_resources_feather object", {
  x <- resources_feather_init(compression = "zstd")
  expect_silent(resources_validate(x))
})

tar_test("prohibit empty tar_resources_feather object", {
  x <- resources_feather_init(compression = NULL)
  expect_error(resources_validate(x), class = "tar_condition_validate")
})

tar_test("print tar_resources_feather object", {
  x <- resources_feather_init(compression = "zstd")
  out <- utils::capture.output(print(x))
  expect_true(any(grepl("tar_resources_feather", out)))
})
