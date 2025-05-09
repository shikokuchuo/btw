#' Tool: Describe user's platform
#'
#' Describes the R version, operating system, and language and locale settings
#' for the user's system. When using [btw_client()] or [btw_app()], this
#' information is automatically included in the system prompt.
#'
#' @seealso [btw_tools()]
#'
#' @returns Returns a string describing the user's platform.
#'
#' @examples
#' cat(btw_tool_session_platform_info())
#'
#' @family Tools
#' @export
btw_tool_session_platform_info <- function() {
  platform <- platform_info()
  platform <- trimws(capture.output(platform)[-1])
  platform <- sub(" +", " ", platform)
  platform <- paste(platform, collapse = "\n")

  sprintf("<system_info>\n%s\n</system_info>", platform)
}

.btw_add_to_tools(
  name = "btw_tool_session_platform_info",
  group = "session",
  tool = function() {
    ellmer::tool(
      btw_tool_session_platform_info,
      .description = "Describes the R version, operating system, language and locale settings for the user's system."
    )
  }
)

platform_date <- function(when = Sys.time()) {
  format(when, "%A, %B %e, %Y (%F)")
}

platform_info <- function() {
  platform <- sessioninfo::platform_info()

  platform$date <- platform_date()
  platform$pandoc <- NULL
  platform$quarto <- NULL

  if (identical(Sys.getenv("POSITRON"), "1")) {
    platform$ui <- "Positron (a VS Code equivalent)"
  } else if (identical(Sys.getenv("RSTUDIO"), "1")) {
    platform$ui <- "RStudio"
  } else if (identical(Sys.getenv("TERM_PROGRAM"), "vscode")) {
    platform$ui <- "VS Code"
  }

  recode <- c(
    "version" = "r_version",
    "collate" = "locale",
    "ctype" = "encoding",
    "tz" = "timezone"
  )

  needs_recode <- names(platform) %in% names(recode)

  names(platform)[needs_recode] <- recode[names(platform)[needs_recode]]
  names(platform) <- sprintf("%s:", toupper(names(platform)))

  platform
}

#' Tool: Gather information about a package or currently loaded packages
#'
#' Uses [sessioninfo::package_info()] to provide information about the loaded,
#' attached, or installed packages. The primary use case is to verify that a
#' package is installed; check the version number of a specific packages; or
#' determine which packages are already in use in a session.
#'
#' @seealso [btw_tools()], [btw_tool_session_platform_info()]
#'
#' @param packages Which packages to show, or `"loaded"` to show all loaded
#'   packages, `"attached"` to show all attached packages, or `"installed"` to
#'   show all installed packages.
#' @param dependencies Whether to include the dependencies when listing package
#'   information.
#' @returns Returns a string describing the selected packages.
#'
#' @examples
#' cat(btw_tool_session_package_info("btw"))
#'
#' @family Tools
#' @export
btw_tool_session_package_info <- function(
  packages = "attached",
  dependencies = ""
) {
  if (
    !any(nzchar(dependencies)) ||
      identical(dependencies, "FALSE") ||
      identical(dependencies, "false")
  ) {
    dependencies <- FALSE
  }
  if (identical(dependencies, "TRUE") || identical(dependencies, "true")) {
    dependencies <- TRUE
  }

  packages <- trimws(strsplit(packages, ",")[[1]])
  if (is.character(dependencies)) {
    dependencies <- trimws(strsplit(dependencies, ",")[[1]])
  }

  title <- NULL
  if (
    length(packages) == 1 && packages %in% c("loaded", "attached", "installed")
  ) {
    title <- switch(
      packages,
      loaded = "Loaded Packages",
      attached = "Attached Packages",
      installed = "Installed Packages"
    )
    title <- c(paste("###", title), "")
  }

  packages <- package_info(packages, dependencies)
  packages <- as.character(packages)
  packages <- md_code_block(type = "", packages)

  packages <- gsub(" R ", " X ", packages)
  packages <- sub(
    "Package was removed from disk.",
    "Package is not installed",
    packages
  )

  paste(c(title, packages), collapse = "\n")
}

package_info <- function(pkgs = NULL, dependencies = NA) {
  if (is.character(dependencies)) {
    if (setequal(dependencies, c("Imports", "Suggests"))) {
      # We don't want really want recursive suggested packages,
      # `dependencies = TRUE` only considers first-level suggested deps
      dependencies <- TRUE
    }
  }
  sessioninfo::package_info(pkgs = pkgs, dependencies = dependencies)
}

.btw_add_to_tools(
  name = "btw_tool_session_package_info",
  group = "session",
  tool = function() {
    ellmer::tool(
      btw_tool_session_package_info,
      .description = paste(
        "Verify that a specific package is installed,",
        "or find out which packages are in use in the current session.",
        "As a last resort, this function can also list all installed packages."
      ),
      packages = ellmer::type_string(
        description = paste(
          "Provide a commma-separated list of package names to check that these packages are",
          "installed and to confirm which versions of the packages are available.",
          "Use the single string \"attached\" to show packages that have been attached by the user,",
          "i.e. are explicitly in use in the session. Use the single string \"loaded\" to show all",
          "packages, including implicitly loaded packages, that are in use in the",
          "session (useful for debugging). Finally, the string \"installed\" lists all",
          "installed packages. Try using the other available options prior to",
          "listing all installed packages."
        ),
        required = TRUE
      ),
      dependencies = ellmer::type_string(
        description = paste(
          "When describing the installed or loaded version of a specific package,",
          "you can use `dependencies = \"true\"` to list dependencies of the",
          "package. Alternatively, you can give a comma-separated list of dependency types, ",
          'choosing from `"Depends"`, `"Imports"`, `"Suggests"`, `"LinkingTo"`, `"Enhances"`.'
        ),
        required = FALSE
      )
    )
  }
)
