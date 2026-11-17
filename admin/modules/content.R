teacher_payoffs <- function() {
  data.frame(Choice = paste0("D", 1:6), Equal = rep("You 10 / Other 10", 6),
    Unequal = c("You 8 / Other 16", "You 12 / Other 4", "You 10 / Other 18",
      "You 10 / Other 6", "You 16 / Other 4", "You 11 / Other 19"))
}

teacher_html_table <- function(data, caption = NULL) {
  tags$div(class = "research-table-scroll", tabindex = "0",
    tags$table(class = "research-table",
      if (!is.null(caption)) tags$caption(caption),
      tags$thead(tags$tr(lapply(names(data), function(name) tags$th(scope = "col", name)))),
      tags$tbody(lapply(seq_len(nrow(data)), function(i) tags$tr(lapply(seq_len(ncol(data)), function(j) {
        tags$td(as.character(data[i, j]))
      }))))
    )
  )
}

teacher_slides <- function() {
  list(
    list(title = "What do our choices reveal about inequality?", content = tagList(
      p(class = "slide-lead", "Six allocation choices. Several social motives. A shared inquiry."),
      div(class = "allocation-pair", div(strong("You"), span("Decision-maker")),
        div(strong("Other"), span("Anonymous recipient")))),
      notes = "Introduce the research question before showing classifications. Invite students to describe trade-offs rather than predict which choice is morally correct."),
    list(title = "One decision-maker, two allocations", content = tagList(
      p(class = "slide-lead", "Each option specifies a payoff for you and for another person."),
      div(class = "allocation-pair", div(span("Equal option"), strong("10 / 10")),
        div(span("Unequal example"), strong("12 / 4"))),
      p("The recipient cannot change your choice. There is no negotiation.")),
      notes = "Read each pair as your payoff first, the other person's payoff second. Explain the actual participation and incentive arrangements used in your class without implying arrangements that have not been established."),
    list(title = "The six allocation choices", content = teacher_html_table(teacher_payoffs(),
      "Payoff pairs: decision-maker / recipient"),
      notes = "The equal allocation remains 10 / 10. Point out that some unequal options change only the recipient's payoff, while others change both. These are the documented task choices; do not alter them during the activity."),
    list(title = "Read a pattern, not a personality", content = tagList(
      p(class = "slide-lead", "The six decisions are interpreted together."),
      tags$ul(tags$li("Altruist"), tags$li("Egalitarian"), tags$li("Selfish"), tags$li("Antisocial")),
      p("These indicators can overlap. They are not labels for individuals.")),
      notes = "Explain that the names refer to indicators defined by the original classification rules. One consistent pattern can match more than one indicator. Avoid inviting students to identify classmates."),
    list(title = "Two dimensions beneath the indicators", content = tagList(
      div(class = "slide-columns", div(h3("Compassion"), p("Aversion to being ahead of the other person.")),
        div(h3("Envy"), p("Aversion to being behind the other person."))),
      p(class = "slide-lead", "Four ordered levels on each dimension form a 4 × 4 map.")),
      notes = "Treat the levels as ordered categories, not calibrated psychological distances. The matrix describes consistent response patterns, not a clinical or personality measure."),
    list(title = "Which responses are in the denominator?", content = tagList(
      div(class = "slide-columns", div(h3("Four social indicators"), p("Consistent responses")),
        div(h3("Inconsistent"), p("Complete binary responses"))),
      p(class = "slide-lead", "The social percentages may add to more than 100%.")),
      notes = "Partial and non-binary responses are excluded from public calculations. Inconsistency is a property of a response pattern under this rule, not an assessment of a student's ability."),
    list(title = "Hidden is not zero", content = tagList(
      p(class = "slide-lead", "Small counts and values that could expose them are suppressed."),
      tags$ul(tags$li("A protected cell contains no published number."),
        tags$li("Other related cells may also be hidden."), tags$li("Do not reconstruct a hidden result from other figures."))),
      notes = "The threshold is five, with complementary and cross-table suppression. This reduces disclosure; it is not a claim of complete anonymity, especially when successive versions or outside knowledge are available."),
    list(title = "What is the latest group?", content = tagList(
      p(class = "slide-lead", "The one-hour window ending at the latest valid response EndDate."),
      p("The latest EndDate is found before response-quality exclusions. Older completed activities remain available until newer responses arrive."),
      p("Window: start excluded, end included. Times are shown in UTC.")),
      notes = "There is no class code selector. The group is selected from timestamps, not the current clock. If unrelated groups complete the same survey in this hour, they are included together; organise collection accordingly."),
    list(title = "Our latest published group", content = NULL,
      notes = "This slide is pinned to the publication present when presentation mode began. Explain the sample and denominator before comparing bar lengths. An unpublished private demonstration is not used here."),
    list(title = "A reference is a comparison, not a ranking", content = tagList(
      p(class = "slide-lead", "Describe a difference before explaining it."),
      tags$ul(tags$li("Compare like denominators."), tags$li("Use percentage points for percentage differences."),
        tags$li("Notice sample composition and protected values."))),
      notes = "The international reference is a sample of activity participants. It does not automatically represent entire countries, universities or genders. Differences alone do not establish causes or statistical significance."),
    list(title = "What else could explain this pattern?", content = tagList(
      div(class = "slide-columns", div(h3("Context"), p("Instructions, incentives and the setting.")),
        div(h3("Composition"), p("Who took part, and which responses were usable."))),
      p(class = "slide-lead", "Which explanations cannot be separated by these data?")),
      notes = "Invite competing explanations and explicitly distinguish observation from interpretation. Encourage students to identify additional evidence that would help, without collecting identifiable disclosures in discussion."),
    list(title = "From allocation choices to a discussion", content = tagList(
      tags$ol(tags$li("What did you observe?"), tags$li("Which explanations remain plausible?"),
        tags$li("Where do equality and efficiency conflict in everyday decisions?")),
      p("Corgnet, Espín & Hernán-González (2015), Frontiers in Behavioral Neuroscience, 9, 287.")),
      notes = "Close with a question rather than a ranking. The task comes from The cognitive basis of social behavior: Cognitive reflection overrides antisocial but not always prosocial motives. DOI: 10.3389/fnbeh.2015.00287.")
  )
}

teacher_results_empty <- function(results) {
  is.null(results) || is.null(results$cells) ||
    (is.data.frame(results$cells) && nrow(results$cells) == 0L) || !length(results$cells)
}

teacher_snapshot_summary <- function(results, heading = "Confirmed student snapshot") {
  if (teacher_results_empty(results)) {
    return(div(class = "research-empty", h3("No group has been published yet"),
      p("Use Update to download Qualtrics responses and publish the latest protected group.")))
  }
  meta <- results$metadata
  div(class = "snapshot-summary",
    h3(if (identical(meta$data_mode, "demonstration")) "Private synthetic demonstration" else heading),
    p(class = "publication-id", meta$publication_id),
    if (!is.null(meta$window_end_utc)) p("Response window: ", meta$window_start_utc, " to ", meta$window_end_utc, " (UTC)"),
    p("Generated: ", meta$generated_at_utc),
    p("Protected values are hidden. Social indicators use consistent responses."))
}

teacher_group_bars <- function(results) {
  if (teacher_results_empty(results)) return(p("There are no published results to display."))
  cells <- results$cells
  cells <- cells[cells$scope == "class" & cells$gender == "all" & cells$behaviour != "inconsistent", , drop = FALSE]
  labels <- c(altruist = "Altruist", egalitarian = "Egalitarian", selfish = "Selfish", antisocial = "Antisocial")
  div(class = "teacher-bars", lapply(names(labels), function(name) {
    cell <- cells[cells$behaviour == name, , drop = FALSE]
    visible <- nrow(cell) == 1L && !isTRUE(cell$suppressed[[1L]]) && !is.na(cell$percentage[[1L]])
    percentage <- if (visible) max(0, min(100, cell$percentage[[1L]])) else 0
    div(class = "teacher-bar", span(labels[[name]]),
      div(class = "teacher-bar-track", `aria-hidden` = "true",
        div(class = if (visible) "teacher-bar-fill" else "teacher-bar-hidden", style = paste0("width:", if (visible) percentage else 100, "%;"))),
      strong(if (visible) paste0(format(round(percentage, 1), nsmall = 1), "%") else "Hidden"))
  }))
}

teacher_table_preview <- function(results, name) {
  if (is.null(results) || !is.data.frame(results[[name]])) return(NULL)
  data <- results[[name]]
  for (column in intersect(c("count", "denominator_n", "percentage", "n_complete", "n_consistent"), names(data))) {
    data[[column]] <- ifelse(is.na(data[[column]]), "Hidden", as.character(data[[column]]))
  }
  data
}
