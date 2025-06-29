#' @include tool-result.R
NULL

#' Tool: List files
#'
#' @examples
#' withr::with_tempdir({
#'   write.csv(mtcars, "mtcars.csv")
#'
#'   btw_tool_files_list_files(type = "file")
#' })
#'
#' @param path Path to a directory or file for which to get information. The
#'   `path` must be in the current working directory. If `path` is a directory,
#'   we use [fs::dir_info()] to list information about files and directories in
#'   `path` (use `type` to pick only one or the other). If `path` is a file, we
#'   show information about that file.
#' @param type File type(s) to return, one of `"any"` or `"file"` or
#'   `"directory"`.
#' @inheritParams fs::dir_ls
#'
#' @return Returns a character table of file information.
#'
#' @family Tools
#' @export
btw_tool_files_list_files <- function(
  path = NULL,
  type = c("any", "file", "directory"),
  regexp = ""
) {
  path <- path %||% getwd()
  type <- type %||% "any"
  check_string(path) # one path a time, please

  type <- arg_match(type, multiple = TRUE)
  if (identical(type, c("any", "file", "directory"))) {
    type <- c("file", "directory", "symlink")
  }

  regexp <- if (nzchar(regexp)) regexp

  # Disallow listing files outside of the project directory
  check_path_within_current_wd(path)

  info <-
    if (fs::is_file(path)) {
      if (!fs::file_exists(path)) {
        cli::cli_abort(
          "The path {.path {path}} does not exist. Did you use a relative path?"
        )
      }
      fs::file_info(path)
    } else {
      fs::dir_info(path, type = type, regexp = regexp, recurse = TRUE)
    }

  info <- info[!is_common_ignorable_files(info$path), ]

  if (nrow(info) == 0) {
    return(sprintf("No %s found in %s", paste(type, collapse = "/"), path))
  }

  info$path <- fs::path_rel(info$path)

  fields <- c("path", "type", "size", "modification_time")

  btw_tool_result(md_table(info[fields]), data = info[fields])
}

.btw_add_to_tools(
  name = "btw_tool_files_list_files",
  group = "files",
  tool = function() {
    ellmer::tool(
      btw_tool_files_list_files,
      .description = r"---(List files or directories in the project.

WHEN TO USE:
* Use this tool to discover the file structure of a project.
* When you want to understand the project structure, use `type = "directory"` to list all directories.
* When you want to find a specific file, use `type = "file"` and `regexp` to filter files by name or extension.

CAUTION: Do not list all files in a project, instead prefer listing files in a specific directory with a `regexp` to filter to files of interest.
      )---",
      .annotations = ellmer::tool_annotations(
        title = "Project Files",
        read_only_hint = TRUE,
        open_world_hint = FALSE,
        idempotent_hint = FALSE
      ),
      path = ellmer::type_string(
        paste(
          "The relative path to a folder or file.",
          "If `path` is a directory, all files or directories (see `type`) are listed.",
          'Use `"."` to refer to the current working directory.',
          "If `path` is a file, information for just the selected file is listed."
        ),
        required = FALSE
      ),
      type = ellmer::type_enum(
        "Whether to list files, directories or any file type, default is `any`.",
        values = c("any", "file", "directory"),
        required = FALSE
      ),
      regexp = ellmer::type_string(
        paste(
          'A regular expression to use to identify files, e.g. `regexp="[.]csv$"` to find files with a `.csv` extension.',
          "Note that it's best to be as general as possible to find the file you want."
        ),
        required = FALSE
      )
    )
  }
)

#' Tool: Read a file
#'
#' @examples
#' withr::with_tempdir({
#'   write.csv(mtcars, "mtcars.csv")
#'
#'   btw_tool_files_read_text_file("mtcars.csv", max_lines = 5)
#' })
#'
#' @param path Path to a file for which to get information. The `path` must be
#'   in the current working directory.
#' @param max_lines Number of lines to include. Defaults to 1,000 lines.
#'
#' @return Returns a character vector of lines from the file.
#'
#' @family Tools
#' @export
btw_tool_files_read_text_file <- function(path, max_lines = 1000) {
  check_path_within_current_wd(path)

  if (!fs::is_file(path) || !fs::file_exists(path)) {
    cli::cli_abort(
      "Path {.path {path}} is not a file or does not exist. Check the path and ensure that it is provided as a relative path."
    )
  }

  if (!isTRUE(is_text_file(path))) {
    cli::cli_abort(
      "Path {.path {path}} is not a path to a text file."
    )
  }

  BtwTextFileToolResult(
    md_code_block(
      fs::path_ext(path),
      readLines(path, warn = FALSE, n = max_lines)
    ),
    extra = list(path = fs::path_rel(path))
  )
}

BtwTextFileToolResult <- S7::new_class(
  "BtwTextFileToolResult",
  parent = BtwToolResult
)

.btw_add_to_tools(
  name = "btw_tool_files_read_text_file",
  group = "files",
  tool = function() {
    ellmer::tool(
      btw_tool_files_read_text_file,
      .description = "Read an entire text file.",
      .annotations = ellmer::tool_annotations(
        title = "Read File",
        read_only_hint = TRUE,
        open_world_hint = FALSE,
        idempotent_hint = FALSE
      ),
      path = ellmer::type_string(
        "The relative path to a file that can be read as text, such as a CSV, JSON, HTML, markdown file, etc.",
      ),
      max_lines = ellmer::type_number(
        "How many lines to include from the file? The default is 100 and is likely already too high.",
        required = FALSE
      )
    )
  }
)

is_text_file <- function(file_path) {
  # Note: this function was written by claude-3.7-sonnet.
  # Try to read the first chunk of the file as binary
  tryCatch(
    {
      # Read first 8KB of the file
      con <- file(file_path, "rb")
      bytes <- readBin(con, what = "raw", n = 8192)
      close(con)

      # If file is empty, consider it text
      if (length(bytes) == 0) {
        return(TRUE)
      }

      # Check for NULL bytes (common in binary files)
      if (any(bytes == as.raw(0))) {
        return(FALSE)
      }

      # Count control characters (excluding common text file control chars)
      # Allow: tab (9), newline (10), carriage return (13)
      allowed_control <- as.raw(c(9, 10, 13))
      control_chars <- bytes[bytes < as.raw(32) & !(bytes %in% allowed_control)]

      # If more than 10% of the first 8KB are control characters, likely binary
      if (length(control_chars) / length(bytes) > 0.1) {
        return(FALSE)
      }

      # Check for high proportion of extended ASCII or non-UTF8 characters
      extended_chars <- bytes[bytes > as.raw(127)]
      if (length(extended_chars) / length(bytes) > 0.3) {
        # Try to interpret as UTF-8
        text <- rawToChar(bytes)
        if (Encoding(text) == "unknown" || !validUTF8(text)) {
          return(FALSE)
        }
      }

      # If we've made it this far, it's likely a text file
      return(TRUE)
    },
    error = function(e) {
      warning("Error reading file: ", e$message)
      return(NA)
    }
  )
}


check_path_within_current_wd <- function(path) {
  if (!fs::path_has_parent(path, getwd())) {
    cli::cli_abort(
      "You are not allowed to list or read files outside of the project directory. Make sure that `path` is relative to the current working directory."
    )
  }
}

is_common_ignorable_files <- function(paths) {
  ignorable_files <- c(".DS_Store", "Thumbs.db")

  ignorable_dir <- c(
    # Version control
    ".git",
    ".svn",
    ".hg",
    ".bzr",

    # Package management
    "node_modules",
    "bower_components",
    "jspm_packages",

    # Python
    ".venv",
    "venv",
    "__pycache__",
    ".pytest_cache",
    "eggs",
    ".eggs",
    ".tox",
    ".nox",
    "*.egg-info",
    "*.egg",

    # R specific
    "renv/library",
    ".Rproj.user",
    "packrat/lib",
    "packrat/src",

    # JavaScript/TypeScript
    "out",
    ".next",
    ".nuxt",
    ".cache",

    # Docker
    ".docker",

    # Documentation builds
    "_site",
    "site",
    "docs/_build",
    "docs/build",
    "public"
  )
  is_ignorable_file <- fs::path_file(paths) %in% ignorable_files
  ignorable_dir_combo <- grep("/", ignorable_dir, fixed = TRUE, value = TRUE)
  ignorable_dir_simple <- setdiff(ignorable_dir, ignorable_dir_combo)

  is_in_ignorable_dir <- map_lgl(
    fs::path_split(fs::path_dir(paths)),
    function(path_parts) {
      some(path_parts, function(part) part %in% ignorable_dir_simple) ||
        # R Markdown built files
        any(grepl("_files$", path_parts)) ||
        some(
          ignorable_dir_combo,
          function(id) grepl(id, fs::path_join(path_parts), fixed = TRUE)
        )
    }
  )

  is_ignorable_file | is_in_ignorable_dir
}

#' Tool: Write a text file
#'
#' @examples
#' withr::with_tempdir({
#'   btw_tool_files_write_text_file("example.txt", "Hello\nWorld!")
#'   readLines("example.txt")
#' })
#'
#' @param path Path to the file to write. The `path` must be in the current
#'   working directory.
#' @param content The text content to write to the file. This should be the
#'   complete content as the file will be overwritten.
#'
#' @return Returns a message confirming the file was written.
#'
#' @family Tools
#' @export
btw_tool_files_write_text_file <- function(path, content) {
  check_string(path)
  check_string(content)
  check_path_within_current_wd(path)

  if (fs::is_dir(path)) {
    cli::cli_abort(
      "Path {.path {path}} is a directory, not a file. Please provide a file path."
    )
  }

  # Ensure the directory exists
  dir_path <- fs::path_dir(path)
  if (dir_path != "." && !fs::dir_exists(dir_path)) {
    fs::dir_create(dir_path, recurse = TRUE)
  }

  previous_content <- if (fs::file_exists(path)) {
    paste(readLines(path, warn = FALSE), collapse = "\n")
  }

  writeLines(content, path)

  BtwWriteFileToolResult(
    "Success",
    extra = list(
      path = path,
      content = content,
      previous_content = previous_content
    )
  )
}

BtwWriteFileToolResult <- S7::new_class(
  "BtwWriteFileToolResult",
  parent = BtwToolResult
)

.btw_add_to_tools(
  name = "btw_tool_files_write_text_file",
  group = "files",
  tool = function() {
    ellmer::tool(
      btw_tool_files_write_text_file,
      .description = 'Write content to a text file.

If the file doesn\'t exist, it will be created, along with any necessary parent directories.

WHEN TO USE:
Use this tool only when the user has explicitly asked you to write or create a file.
Do not use for temporary or one-off content; prefer direct responses for those cases.
Consider checking with the user to ensure that the file path is correct and that they want to write to a file before calling this tool.

CAUTION:
This completely overwrites any existing file content.
To modify an existing file, first read its content using `btw_tool_files_read_text_file`, make your changes to the text, then write back the complete modified content.
',
      .annotations = ellmer::tool_annotations(
        title = "Write File",
        read_only_hint = FALSE,
        open_world_hint = FALSE,
        idempotent_hint = TRUE
      ),
      path = ellmer::type_string(
        "The relative path to the file to write. The file will be created if it doesn't exist, or overwritten if it does."
      ),
      content = ellmer::type_string(
        "The complete text content to write to the file."
      )
    )
  }
)
