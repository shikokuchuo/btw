#' Create a btw-enhanced ellmer chat client
#'
#' @description
#' Creates an [ellmer::Chat] client, enhanced with the tools from
#' [btw_tools()]. Use `btw_client()` to create the chat client for
#' general or interactive use at the console, or `btw_app()` to create a chat
#' client and launch a Shiny app for chatting with a btw-enhanced LLM in your
#' local workspace.
#'
#' ## Project Context
#'
#' You can keep track of project-specific rules, guidance and context by adding
#' a `btw.md` file in your project directory. Any time you start a chat client
#' with `btw_client()` or launch a chat session with `btw_app()`, btw will
#' automatically find and include the contents of the `btw.md` file in your
#' chat.
#'
#' Use `btw.md` to inform the LLM of your preferred code style, to provide
#' domain-specific terminology or definitions, to establish project
#' documentation, goals and constraints, to include reference materials such or
#' technical specifications, or more. Storing this kind of information in
#' `btw.md` may help you avoid repeating yourself and can be used to maintain
#' coherence across many chat sessions.
#'
#' The `btw.md` file, when present, is included as part of the system prompt for
#' your chat conversation. You can structure the file in any way you wish.
#'
#' You can also use the `btw.md` file to choose default chat settings for your
#' project in a YAML block at the top of the file. In this YAML block you can
#' choose the default `provider`, `model` and `tools` for `btw_client()` or
#' `btw_app()`. `provider` chooses the `ellmer::chat_*()` function, e.g.
#' `provider: openai` or `provider: chat_openai` to use [ellmer::chat_openai()].
#' `tools` chooses which btw tools are included in the chat, and all other
#' values are passed to the `ellmer::chat_*()` constructor, e.g. `model:
#' gpt-4o`, `seed: 42`, or `echo: all``.
#'
#' Here's an example `btw.md` file:
#'
#' ````
#' ---
#' provider: claude
#' model: claude-3-7-sonnet-20250219
#' tools: [data, docs, environment]
#' ---
#'
#' Follow these important style rules for any R code in this project:
#'
#' * Prefer solutions that use {tidyverse}
#' * Always use `<-` for assignment
#' * Always use the native base-R pipe `|>` for piped expressions
#' ````
#'
#' You can hide parts of the `btw.md` file from the system prompt by wrapping
#' them in HTML `<!-- HIDE -->` and `<!-- /HIDE -->` comment tags. A single
#' `<!-- HIDE -->` comment tag will hide all content after it until the next
#' `<!-- /HIDE -->` tag, or the end of the file. This is particularly useful
#' when your system prompt contains notes to yourself or future tasks that you
#' do not want to be included in the system prompt.
#'
#' For project-specific configuration, store your `btw.md` file in the root of
#' your project directory. For global configuration, you can maintain a `btw.md`
#' file in your home directory (at `btw.md` or `.config/btw/btw.md` in your home
#' directory, using `fs::path_home()`). This file will be used by default when a
#' project-specific `btw.md` file is not found.
#'
#' ## Client Options
#'
#' * `btw.client`: The [ellmer::Chat] client to use as the basis for new
#'   `btw_client()` or `btw_app()` chats.
#' * `btw.tools`: The btw tools to include by default when starting a new
#'   btw chat, see [btw_tools()] for details.
#'
#' @examplesIf rlang::is_interactive()
#' withr::local_options(list(
#'   btw.client = ellmer::chat_ollama(model="llama3.1:8b")
#' ))
#'
#' chat <- btw_client()
#' chat$chat("How can I replace `stop()` calls with functions from the cli package?")
#'
#' @param client An [ellmer::Chat] client, defaults to
#'   [ellmer::chat_anthropic()]. You can use the `btw.client` option to set a
#'   default client for new `btw_client()` calls, or use a `btw.md` project file
#'   for default chat client settings, like provider and model. We check the
#'   `client` argument, then the `btw.client` R option, and finally the `btw.md`
#'   project file, using only the client definition from the first of these that
#'   is available.
#' @param tools Optional names of tools or tool groups to include in the chat
#'   client. By default, all btw tools are included. For example, use
#'   `include = "docs"` to include only the documentation related tools, or
#'   `include = c("env", "docs")`, etc. `btw_client()` also supports
#'   `tools = FALSE` to skip registering \pkg{btw} tools with the chat client.
#' @param path_btw A path to a `btw.md` project context file. If `NULL`, btw
#'   will find a project-specific `btw.md` file in the parents of the current
#'   working directory.
#' @param ... Additional arguments are ignored. `...` are included for future
#'   feature expansion.
#'
#' @return Returns an [ellmer::Chat] object with additional tools registered
#'   from [btw_tools()]. `btw_app()` returns the chat object invisibly, and
#'   the chat object with the messages added during the chat session.
#'
#' @describeIn btw_client Create a btw-enhanced [ellmer::Chat] client
#' @export
btw_client <- function(..., client = NULL, tools = NULL, path_btw = NULL) {
  check_dots_empty()

  config <- btw_client_config(client, tools, config = read_btw_file(path_btw))
  skip_tools <- isFALSE(config$tools) || identical(config$tools, "none")

  client <- config$client

  sys_prompt <- client$get_system_prompt()
  sys_prompt <- c(
    "# System and Session Context",
    "Please account for the following R session and system settings in all responses.",
    "",
    btw_tool_session_platform_info()@value,
    "",
    if (!skip_tools) {
      c(
        "# Tools",
        "",
        paste(
          "You have access to tools that help you interact with the user's R session and workspace.",
          "Use these tools when they are helpful and appropriate to complete the user's request.",
          "These tools are available to augment your ability to help the user,",
          "but you are smart and capable and can answer many things on your own.",
          "It is okay to answer the user without relying on these tools."
        ),
        ""
      )
    },
    if (!is.null(config$btw_system_prompt)) {
      c(
        "# Project Context",
        "",
        trimws(paste(config$btw_system_prompt, collapse = "\n")),
        ""
      )
    },
    "---\n",
    sys_prompt
  )
  client$set_system_prompt(paste(sys_prompt, collapse = "\n"))

  if (!skip_tools) {
    client$set_tools(tools = c(client$get_tools(), btw_tools(config$tools)))
  }

  client
}

# nocov start

#' @describeIn btw_client Create a btw-enhanced client and launch a Shiny app to
#'   chat
#' @export
btw_app <- function(..., client = NULL, tools = NULL, path_btw = NULL) {
  check_dots_empty()
  rlang::check_installed("shiny")
  rlang::check_installed("bslib")
  rlang::check_installed("shinychat", version = "0.2.0")

  client <- btw_client(
    client = client,
    tools = tools,
    path_btw = path_btw
  )

  path_figures_installed <- system.file("help", "figures", package = "btw")
  path_figures_dev <- system.file("man", "figures", package = "btw")
  path_logo <- "btw_figures/logo.png"

  if (nzchar(path_figures_installed)) {
    shiny::addResourcePath("btw_figures", path_figures_installed)
  } else if (nzchar(path_figures_dev)) {
    shiny::addResourcePath("btw_figures", path_figures_dev)
  } else {
    path_logo <- NULL
  }

  btw_title <- function(in_sidebar) {
    logo <- shiny::img(
      src = path_logo,
      class = "me-2 dib",
      style = bslib::css(max_width = "35px"),
      .noWS = c("before", "after")
    )
    shiny::tags$header(
      if (!is.null(path_logo)) {
        if (in_sidebar) {
          shiny::span(logo)
        } else {
          shiny::actionLink("show_sidebar", logo)
        }
      },
      "Chat with",
      shiny::code("{btw}"),
      "tools",
      class = "sidebar-title mb-0",
    )
  }

  ui <- bslib::page_sidebar(
    window_title = "Chat with {btw} tools",
    sidebar = bslib::sidebar(
      id = "tools_sidebar",
      title = btw_title(TRUE),
      width = NULL,
      height = "100%",
      style = bslib::css(max_height = "100%"),
      open = "closed",
      shiny::div(
        class = "btn-group",
        shiny::actionButton(
          "select_all",
          "Select All",
          icon = shiny::icon("check-square"),
          class = "btn-sm"
        ),
        shiny::actionButton(
          "deselect_all",
          "Select none",
          icon = shiny::icon("square"),
          class = "btn-sm"
        )
      ),
      shiny::div(
        class = "overflow-y-auto overflow-x-visible",
        app_tool_group_inputs(
          btw_tools_df(),
          initial_tool_names = map_chr(client$get_tools(), function(.x) .x@name)
        ),
        shiny::uiOutput("ui_other_tools")
      ),
      bslib::input_dark_mode(style = "display: none")
    ),
    shiny::actionButton(
      "close_btn",
      label = "",
      class = "btn-close",
      style = "position: fixed; top: 6px; right: 6px;"
    ),
    btw_title(FALSE),
    shinychat::chat_mod_ui("chat", client = client),
    shiny::tags$head(
      shiny::tags$style(shiny::HTML(
        "
        :root { --bslib-sidebar-width: max(30vw, 275px); }
        .opacity-100-hover:hover { opacity: 1 !important; }
        :hover > .opacity-100-hover-parent, .opacity-100-hover-parent:hover { opacity: 1 !important; }
        .bslib-sidebar-layout > .main > main .sidebar-title { display: none; }
        .sidebar-collapsed > .main > main .sidebar-title { display: block; }
        .bslib-sidebar-layout.sidebar-collapsed>.collapse-toggle { top: 1.8rem; }
      "
      )),
    )
  )

  server <- function(input, output, session) {
    shinychat::chat_mod_server("chat", client = client)
    shiny::observeEvent(input$close_btn, {
      shiny::stopApp()
    })

    shiny::observeEvent(input$show_sidebar, {
      bslib::sidebar_toggle("tools_sidebar")
    })

    tool_groups <- unique(btw_tools_df()$group)
    other_tools <- keep(client$get_tools(), function(tool) {
      !identical(substring(tool@name, 1, 9), "btw_tool_")
    })

    selected_tools <- shiny::reactive({
      tool_groups <- c(tool_groups, if (length(other_tools) > 0) "other")
      unlist(
        map(tool_groups, function(group) input[[paste0("tools_", group)]])
      )
    })

    shiny::observeEvent(input$select_all, {
      tools <- btw_tools_df()
      for (group in tool_groups) {
        shiny::updateCheckboxGroupInput(
          session = session,
          inputId = paste0("tools_", group),
          selected = tools[tools$group == group, ][["name"]]
        )
      }
    })

    shiny::observeEvent(input$deselect_all, {
      tools <- btw_tools_df()
      for (group in tool_groups) {
        shiny::updateCheckboxGroupInput(
          session = session,
          inputId = paste0("tools_", group),
          selected = ""
        )
      }
    })

    shiny::observe({
      if (!length(selected_tools())) {
        client$set_tools(list())
      } else {
        .btw_tools <- keep(btw_tools(), function(tool) {
          tool@name %in% selected_tools()
        })
        .other_tools <- keep(other_tools, function(tool) {
          tool@name %in% selected_tools()
        })
        client$set_tools(c(.btw_tools, other_tools))
      }
    })

    output$ui_other_tools <- shiny::renderUI({
      if (length(other_tools) == 0) {
        return(NULL)
      }

      other_tools_df <- dplyr::bind_rows(
        map(other_tools, function(tool) {
          dplyr::tibble(
            group = "other",
            name = tool@name,
            description = tool@description,
            title = tool@annotations$title %||% tool@name,
            is_read_only = tool@annotations$read_only_hint %||% NA,
            is_open_world = tool@annotations$open_world_hint %||% NA
          )
        })
      )

      app_tool_group_choice_input("other", other_tools_df)
    })
  }

  app <- shiny::shinyApp(ui, server)
  tryCatch(shiny::runGadget(app), interrupt = function(cnd) NULL)
  invisible(client)
}

btw_tools_df <- function() {
  .btw_tools <- map(.btw_tools, function(def) {
    tool <- def$tool()
    if (is.null(tool)) {
      return()
    }
    dplyr::tibble(
      group = def$group,
      name = tool@name,
      description = tool@description,
      title = tool@annotations$title,
      is_read_only = tool@annotations$read_only_hint %||% NA,
      is_open_world = tool@annotations$open_world_hint %||% NA
    )
  })
  dplyr::bind_rows(.btw_tools)
}

app_tool_group_inputs <- function(tools_df, initial_tool_names = NULL) {
  tools_df <- split(tools_df, tools_df$group)

  map2(
    names(tools_df),
    tools_df,
    app_tool_group_choice_input,
    initial_tool_names = initial_tool_names
  )
}

app_tool_group_choice_input <- function(
  group,
  group_tools_df,
  initial_tool_names = NULL
) {
  choice_names <- pmap(group_tools_df, app_tool_group_choices_labels)

  if (is.null(initial_tool_names)) {
    initial_tool_names <- group_tools_df$name
  }

  label_text <- switch(
    group,
    "docs" = shiny::span(shiny::icon("book"), "Documentation"),
    "env" = shiny::span(shiny::icon("globe"), "Environment"),
    "files" = shiny::span(shiny::icon("folder"), "Files"),
    "ide" = shiny::span(shiny::icon("code"), "IDE"),
    "search" = shiny::span(shiny::icon("search"), "Search"),
    "session" = shiny::span(shiny::icon("desktop"), "Session Info"),
    "other" = shiny::span(shiny::icon("tools"), "Other Tools"),
    paste0(toupper(substring(group, 1, 1)), substring(group, 2))
  )

  shiny::checkboxGroupInput(
    inputId = paste0("tools_", group),
    label = shiny::h3(label_text, class = "h6 mb-0"),
    choiceNames = choice_names,
    choiceValues = group_tools_df$name,
    selected = intersect(group_tools_df$name, initial_tool_names),
  )
}

app_tool_group_choices_labels <- function(
  title,
  description,
  ...,
  is_read_only = NA,
  is_open_world = NA
) {
  description <- strsplit(description, "\\.\\s")[[1]][1]
  description <- paste0(sub("\\.$", "", description), ".")

  shiny::tagList(
    bslib::tooltip(
      shiny::span(
        title,
        shiny::HTML("&nbsp;", .noWS = c("before", "after")),
        shiny::icon(
          "info-circle",
          class = "small text-secondary opacity-50 opacity-100-hover-parent",
          .noWS = c("before", "after")
        ),
      ),
      description,
      placement = "right"
    ),
    if (!isTRUE(is_read_only)) {
      bslib::tooltip(
        shiny::icon(
          "file-pen",
          class = "small text-danger opacity-50 opacity-100-hover"
        ),
        shiny::HTML(
          "<strong>Not Read-Only</strong><br>This tool self-reports that it can modify files."
        )
      )
    },
    if (isTRUE(is_open_world)) {
      bslib::tooltip(
        shiny::icon(
          "satellite-dish",
          class = "small text-primary opacity-50 opacity-100-hover"
        ),
        shiny::HTML(
          "<strong>Open World Tool</strong><br>This tool may access external resources, such as the web or databases."
        )
      )
    }
  )
}

# nocov end

btw_client_config <- function(client = NULL, tools = NULL, config = list()) {
  config$tools <-
    tools %||%
    getOption("btw.tools") %||%
    config$tools

  if (!is.null(client)) {
    check_inherits(client, "Chat")
    config$client <- client
    return(config)
  }

  default <- getOption("btw.client")
  if (!is.null(default)) {
    check_inherits(default, "Chat")
    config$client <- default$clone()
    return(config)
  }

  not_chat_args <- c("tools", "provider", "btw_system_prompt")

  if (!is.null(config$provider)) {
    chat_args <- utils::modifyList(
      list(echo = "output"), # defaults
      config[setdiff(names(config), not_chat_args)] # user config
    )

    chat_fn <- gsub(" ", "_", tolower(config$provider))
    if (!grepl("^chat_", chat_fn)) {
      chat_fn <- paste0("chat_", chat_fn)
    }

    chat_client <- call2(.ns = "ellmer", chat_fn, !!!chat_args)
    config$client <- eval(chat_client)

    if (!is.null(chat_args$model)) {
      cli::cli_inform(
        "Using {.field {chat_args$model}} from {.strong {config$client$get_provider()@name}}."
      )
    }
    return(config)
  }

  config$client <- ellmer::chat_anthropic(echo = "output")
  config
}

read_btw_file <- function(path = NULL) {
  must_find <- !is.null(path)

  path <- path %||% path_find_in_project("btw.md") %||% path_find_user("btw.md")

  if (!must_find && is.null(path)) {
    return(list())
  }

  if (must_find && (is.null(path) || !fs::file_exists(path))) {
    cli::cli_abort("Invalid {.arg path}: {.path {path}} does not exist.")
  }

  config <- rmarkdown::yaml_front_matter(path)

  read_without_yaml <- function(path) {
    pyfm <- asNamespace("rmarkdown")[["partition_yaml_front_matter"]]
    pyfm(readLines(path, warn = FALSE))$body
  }

  btw_system_prompt <- read_without_yaml(path)
  config$btw_system_prompt <- remove_hidden_content(btw_system_prompt)
  config
}

remove_hidden_content <- function(lines) {
  if (length(lines) == 0) {
    return(character(0))
  }

  starts <- cumsum(trimws(lines) == "<!-- HIDE -->")
  ends <- trimws(lines) == "<!-- /HIDE -->"

  # Shift ends to avoid including /HIDE
  shift <- function(x) c(0, x[-length(x)])

  ends[starts - cumsum(ends) < 0 & ends] <- FALSE

  lines[starts - shift(cumsum(ends)) <= 0]
}
