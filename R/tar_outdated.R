#' @title Check which targets are outdated.
#' @export
#' @family inspect
#' @description Checks for outdated targets in the pipeline,
#'   targets that will be rerun automatically if you call
#'   [tar_make()] or similar. See [tar_cue()] for the rules
#'   that decide whether a target needs to rerun.
#' @details Requires that you define a pipeline
#'   with a target script file (default: `_targets.R`).
#'   (See [tar_script()] for details.)
#' @return Names of the outdated targets.
#' @param names Names of the targets. `tar_outdated()` will check
#'   these targets and all upstream ancestors in the dependency graph.
#'   Set `names` to `NULL` to check/build all the targets (default).
#'   Otherwise, you can supply symbols
#'   or `tidyselect` helpers like [starts_with()].
#'   Applies to ordinary targets (stem) and whole dynamic branching targets
#'   (patterns) by not individual dynamic branches.
#' @param shortcut Logical of length 1, how to interpret the `names` argument.
#'   If `shortcut` is `FALSE` (default) then the function checks
#'   all targets upstream of `names` as far back as the dependency graph goes.
#'   If `TRUE`, then the function only checks the targets in `names`
#'   and uses stored metadata for information about upstream dependencies
#'   as needed. `shortcut = TRUE` increases speed if there are a lot of
#'   up-to-date targets, but it assumes all the dependencies
#'   are up to date, so please use with caution.
#'   Also, `shortcut = TRUE` only works if you set `names`.
#' @param branches Logical of length 1, whether to include branch names.
#'   Including branches could get cumbersome for large pipelines.
#'   Individual branch names are still omitted when branch-specific information
#'   is not reliable: for example, when a pattern branches over
#'   an outdated target.
#' @param targets_only Logical of length 1, whether to just restrict to targets
#'   or to include functions and other global objects from the environment
#'   created by running the target script file (default: `_targets.R`).
#' @param reporter Character of length 1, name of the reporter to user.
#'   Controls how messages are printed as targets are checked. Choices:
#'   * `"silent"`: print nothing.
#'   * `"forecast"`: print running totals of the checked and outdated
#'     targets found so far.
#' @inheritParams tar_validate
#' @examples
#' if (identical(Sys.getenv("TAR_EXAMPLES"), "true")) {
#' tar_dir({ # tar_dir() runs code from a temporary directory.
#' tar_script(list(tar_target(x, 1 + 1)))
#' tar_outdated()
#' tar_script({
#'   list(
#'     tar_target(y1, 1 + 1),
#'     tar_target(y2, 1 + 1),
#'     tar_target(z, y1 + y2)
#'   )
#' }, ask = FALSE)
#' tar_outdated()
#' })
#' }
tar_outdated <- function(
  names = NULL,
  shortcut = targets::tar_config_get("shortcut"),
  branches = FALSE,
  targets_only = TRUE,
  reporter = targets::tar_config_get("reporter_outdated"),
  callr_function = callr::r,
  callr_arguments = targets::callr_args_default(callr_function, reporter),
  envir = parent.frame(),
  script = targets::tar_config_get("script"),
  store = targets::tar_config_get("store")
) {
  force(envir)
  tar_assert_scalar(shortcut)
  tar_assert_lgl(shortcut)
  tar_assert_lgl(branches)
  tar_assert_flag(reporter, tar_outdated_reporters())
  tar_assert_callr_function(callr_function)
  tar_assert_list(callr_arguments)
  targets_arguments <- list(
    path_store = store,
    names_quosure = rlang::enquo(names),
    shortcut = shortcut,
    branches = branches,
    targets_only = targets_only,
    reporter = reporter
  )
  callr_outer(
    targets_function = tar_outdated_inner,
    targets_arguments = targets_arguments,
    callr_function = callr_function,
    callr_arguments = callr_arguments,
    envir = envir,
    script = script
  )
}

tar_outdated_inner <- function(
  pipeline,
  path_store,
  names_quosure,
  shortcut,
  branches,
  targets_only,
  reporter
) {
  names_all <- pipeline_get_names(pipeline)
  names <- tar_tidyselect_eval(names_quosure, names_all)
  meta <- meta_init(path_store = path_store)
  outdated_globals <- if_any(
    targets_only,
    character(0),
    tar_outdated_globals(pipeline, meta)
  )
  outdated <- outdated_init(
    pipeline = pipeline,
    meta = meta_init(path_store = path_store),
    names = names,
    shortcut = shortcut,
    queue = "sequential",
    reporter = reporter
  )
  outdated$run()
  outdated_targets <- counter_get_names(outdated$outdated)
  if (!branches) {
    outdated_targets <- intersect(outdated_targets, names_all)
  }
  c(outdated_globals, outdated_targets)
}

tar_outdated_globals <- function(pipeline, meta) {
  meta$database$ensure_preprocessed(write = FALSE)
  new <- hash_imports(pipeline$imports)
  new$new <- new$data
  recorded <- fltr(new$name, ~meta$exists_record(.x))
  if (!length(recorded)) {
    return(new$name)
  }
  data <- map_chr(recorded, ~meta$get_record(.x)$data)
  old <- utils::stack(data)
  old$name <- as.character(old$ind)
  old$old <- old$values
  comparison <- merge(new, old, all.x = TRUE)
  comparison$values[is.na(comparison$values)] <- ""
  different <- comparison$new != comparison$old
  different[is.na(different)] <- TRUE
  comparison$name[different]
}
