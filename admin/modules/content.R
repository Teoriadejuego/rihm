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
  decision <- function(equal, unequal) div(class = "allocation-pair",
    div(span("Equal split"), strong(equal)), div(span("Unequal split"), strong(unequal)))
  list(
    list(title = "What makes a split fair?", content = tagList(
      p(class = "slide-lead", "Think back to one choice where you hesitated. What were you weighing?"),
      p("Take 20 seconds to think. Then hear a partner’s reasoning. You can discuss either option without disclosing your answer.")),
      notes = "Use after the survey. Give everyone quiet thinking time, then ask for two different reasons. Keep individual votes private."),
    list(title = "Would you give up two points?", content = tagList(
      p("Decision D1 · Your payoff first, the recipient’s second."),
      decision("10 / 10", "8 / 16"),
      p(class = "slide-lead", "Which option gives the pair more? Who pays for that gain?")),
      notes = "Pause before explaining. The total rises from 20 to 24. You give up 2 and the recipient gains 6. Ask how empathy or a concern for equal outcomes might change the decision."),
    list(title = "What if your payoff stays at ten?", content = tagList(
      p("Decision D3 · Your payoff first, the recipient’s second."),
      decision("10 / 10", "10 / 18"),
      p(class = "slide-lead", "Would your reasoning from D1 still apply? Explain what has changed.")),
      notes = "Here the recipient can gain 8 at no cost to the decision-maker. Ask partners to make the strongest case for each option before comparing them."),
    list(title = "What do the six decisions tell us?", content = tagList(
      teacher_html_table(teacher_payoffs(), "Points for you / points for the recipient"),
      p("Find two decisions where your own payoff stays the same. What changes for the recipient?")),
      notes = "D3 increases the recipient’s payoff. D4 reduces it. Read the pattern across all six choices before interpreting a single response."),
    list(title = "Which motives fit the same choice?", content = tagList(
      div(class = "motive-grid",
        div(h3("Altruist"), p("Favour gains for the recipient and the pair.")),
        div(h3("Egalitarian"), p("Keep the two payoffs close.")),
        div(h3("Selfish"), p("Favour the decision-maker’s own payoff.")),
        div(h3("Antisocial"), p("Reduce the recipient’s payoff or widen the gap."))),
      p("In D2, choosing 10 / 10 over 12 / 4 gives the recipient more and preserves equality. Which motives could fit?")),
      notes = "Equality and concern for the recipient both fit this choice. The published indicators depend on the six-decision pattern and can overlap. Avoid assigning a personality to a classmate."),
    list(title = "Read a percentage from our class", kind = "group",
      notes = "Point to one visible bar and ask what its denominator is. Social indicators use consistent responses. Inconsistency is measured among complete binary responses. A protected cell has no published percentage. The group spans the hour ending at the latest valid class response in the database."),
    list(title = "Compare the class with Madagascar", kind = "comparison",
      notes = "This follows RIHM’s country-comparison exercise using the published egalitarian indicator. Ask students to read both sample sizes aloud. If either value is protected, discuss what the public data allow you to say."),
    list(title = "What could explain a difference?", content = tagList(
      p(class = "slide-lead", "Two classes in the same city could also produce different results."),
      p("In pairs, suggest one explanation about who took part and one about the setting. What evidence would help you tell them apart?")),
      notes = "Allow one minute. Possible explanations include recruitment, course, incentives or instructions. Ask what would support each account. A participating university sample cannot establish a national trait."),
    list(title = "How would you divide a team bonus?", content = tagList(
      p(class = "slide-lead", "Two colleagues finish a project. One logged more hours. The other spotted the error that saved the project."),
      p("Agree on a rule for sharing the bonus. Would you announce that rule before the next project begins? Why?")),
      notes = "Allow two minutes. Ask groups to defend equality, contribution or need. Invite another group to explain how the proposed rule might change future cooperation."),
    list(title = "Who should pay for a cooler school?", content = tagList(
      p(class = "slide-lead", "A school can shade its playground. All families benefit, but some can contribute much more than others."),
      p("Would you ask for equal payments or payments based on means? Whose perspective would you seek before deciding?")),
      notes = "Adaptation of RIHM’s climate and community prompts. Ask who bears the cost today and who receives the benefit later. Connect one proposal back to D1."),
    list(title = "Would your rule work at home?", content = tagList(
      p(class = "slide-lead", "Two siblings share the care of a relative. One lives nearby. The other can afford more of the expenses."),
      p("Try applying your bonus rule to this family. What would you keep, and what would you change?")),
      notes = "Use the fictional family so students can join without personal disclosure. Give each partner a turn. Ask how time, money and need affect what counts as a fair contribution."),
    list(title = "Test one observation with the dashboard", kind = "results",
      notes = "Give the class two minutes. Invite one observation grounded in the chart and one question the data leave open. Discussion themes adapted from the RIHM teacher guide on promoting reflection.")
  )
}

teacher_comparison_slide <- function(results) {
  if (teacher_results_empty(results)) return(p("Open this slide after the teacher publishes the group results."))
  cells <- results$cells
  one <- function(scope, country) {
    row <- cells[cells$scope == scope & cells$country == country & cells$gender == "all" &
      cells$behaviour == "egalitarian", , drop = FALSE]
    if (!nrow(row)) return(p("No published cell"))
    if (!identical(row$suppressed[[1]], FALSE) || is.na(row$percentage[[1]])) return(p("Protected"))
    tagList(strong(sprintf("%.1f%%", row$percentage[[1]])),
      span(sprintf("%d of %d consistent responses", row$count[[1]], row$denominator_n[[1]])))
  }
  tagList(p("Egalitarian choices across the six decisions"),
    div(class = "allocation-pair", div(h3("Our class"), one("class", "Class")),
      div(h3("Madagascar sample"), one("international", "Madagascar"))),
    p("Read each sample size. If both percentages are visible, how many percentage points apart are they?"))
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
