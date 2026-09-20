binary_grid <- function() {
  grid <- expand.grid(rep(list(0:1), 6), KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  names(grid) <- paste0("DP", 1:6)
  grid
}

make_raw_dic <- function(decisions, session = "CLASS-1", country_uni = 18, gender = 1) {
  data.frame(
    DIC4 = decisions$DP1,
    DIC5 = decisions$DP2,
    DIC3 = decisions$DP3,
    DIC6 = decisions$DP4,
    DIC2 = decisions$DP5,
    DIC1 = decisions$DP6,
    gender = rep(gender, nrow(decisions)),
    uni = rep(country_uni, nrow(decisions)),
    session_password = rep(session, nrow(decisions)),
    ResponseId = paste0("R_", seq_len(nrow(decisions))),
    EndDate = sprintf("2026-01-01 10:%02d:00", seq_len(nrow(decisions)) %% 60),
    stringsAsFactors = FALSE
  )
}

make_raw_pairs <- function(decisions, session = "CLASS-1", country_uni = 18, gender = 2) {
  data.frame(
    dic10_6 = decisions$DP1,
    dic16_4 = decisions$DP2,
    dic10_18 = decisions$DP3,
    dic11_19 = decisions$DP4,
    dic12_4 = decisions$DP5,
    dic8_16 = decisions$DP6,
    gender = rep(gender, nrow(decisions)),
    uni = rep(country_uni, nrow(decisions)),
    session_password = rep(session, nrow(decisions)),
    ResponseId = paste0("P_", seq_len(nrow(decisions))),
    stringsAsFactors = FALSE
  )
}

test_locations <- function() {
  data.frame(uni = c(18, 29), country = c("Spain", "Salvador"), stringsAsFactors = FALSE)
}

