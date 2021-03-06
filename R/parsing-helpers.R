# new and moved internal helper functions from freeze 5 refactoring ------------

#' hack to pass devtools::check()
#' see: https://stackoverflow.com/questions/9439256/
#' @noRd
utils::globalVariables(c("MAP35_140bp", ".data", "field", "SNV", "indel",
                         "dbnsfp", "sourceGroup", "pivotGroup", "pivotChar",
                         "parseGroup", "transformation", ".", "p_list",
                         "match_mask", "r_list", "r_corresponding",
                         "new_p", "p_max", "p_min", "toRemove", "outputOrder",
                         "pivotChar2", ".out", "counts", "replacement",
                         "aaref", "aaalt"))

#' Check whether the source_file is WGSA indel annotation
#' @noRd
.is_indel <- function(header){
  any(stringr::str_detect(header, "indel_focal_length"))
}

#' use read_tsv to read fields from raw chunk of TSV from readLines()
#' @noRd
.get_fields_from_chunk <- function(raw_chunk) {
  readr::read_tsv(paste0(raw_chunk, collapse = "\n"),
                  col_types = readr::cols(.default = readr::col_character()))
}

#' Check if the current chunk includes a header row describing the fields
#' @noRd
.has_header <- function(raw_chunk){
  expression <- paste0(
    "(^CHROM\\tPOS\\tREF\\tALT)|",
    "(#chr\\tpos\\tref\\talt\\t)|",
    "(chr\\tpos\\tref\\talt\\t)"
  )
  any(stringr::str_detect(raw_chunk,
                          stringr::regex(expression, ignore_case = TRUE)))
}

#' add column_name_unparsed column to tibble prior to parsing (for debugging,
#' mostly)
#' @importFrom magrittr "%>%"
#' @noRd
.preserve_raw <- function(selected_columns, to_parse) {
  if (length(to_parse) == 0) {
    return(selected_columns)
  }
  selected_columns <- selected_columns %>%
    dplyr::bind_cols(dplyr::select_at(
      .,
      .vars = to_parse,
      .funs = dplyr::funs(paste0(., "_unparsed"))
    ))
  return(selected_columns)
}

#' remove spurious {*} strings from fields:
#' .{n} -> .
#' .{n}; -> .;
#' .{n}. -> .,. (or .{n}. -> . ?)
#'
#' @importFrom magrittr "%>%"
#' @noRd
.parse_clean <- function(selected_columns, to_clean){
  if (length(to_clean) == 0){
    return(selected_columns)
  }

  # if no {*}, no parsing needed.
  if (!any(
    suppressWarnings(selected_columns %>%
    dplyr::select(to_clean) %>%
    stringr::str_detect("\\{[^\\}]+\\}")))
    ){
    return(selected_columns)
  }

  selected_columns <-
    selected_columns %>%
    #.{n} -> .
    dplyr::mutate_at(.vars = dplyr::vars(to_clean),
                     .funs = dplyr::funs(
                       stringr::str_replace_all(., "\\{[^\\}]+\\}$", "")
                       )
                     ) %>%
    # .{n}; -> .;
    dplyr::mutate_at(.vars = dplyr::vars(to_clean),
                     .funs = dplyr::funs(
                       stringr::str_replace_all(., "\\{[^\\}]+\\};", ";")
                       )
                     ) %>%
    # .{n}. -> .,. (or should it be .{n}. -> . ? or .{n}. -> .;. ?)
    dplyr::mutate_at(.vars = dplyr::vars(to_clean),
                     .funs = dplyr::funs(
                       stringr::str_replace_all(.,
                        "\\.\\{[^\\}]+\\}(?!;)", ".,")
                       )
                     )
  return(selected_columns)
}

#' pick maximum or minimum value from compound entry in column
#' @examples
#' \dontrun{
#' .parse_extreme_columns(selected_columns, max_columns, "max")
#' .parse_extreme_columns(selected_columns, min_columns, "min")
#' }
#' @importFrom magrittr "%>%"
#' @noRd

.parse_extreme_columns <- function(selected_columns, target_columns, sense) {
  if (length(target_columns) == 0){
    return(selected_columns)
  }

  # if no ;, |, or {*}, only single values, so no parsing needed
  # suppressWarnings to avoid warning - stri_detect_regex argument is not an
  # atomic vector
  if (!any(suppressWarnings(
    selected_columns %>%
    dplyr::select(target_columns) %>%
    stringr::str_detect("\\{[^\\}]+\\}|;|\\|")))
  ){
    return(selected_columns)
  }

  if (! sense %in% c("max", "min")){
    stop('sense must be "max" or "min"')
  }
  # if ; or {*} or |, replace with a space, split on whitespace, and return
  # extreme value
  if (sense == "max") {
    to_replace <- "-Inf"
  } else {
    to_replace <- "Inf"
  }

  selected_columns <-
    suppressWarnings(
      selected_columns %>%
        # replace ; or {*} with a space
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(
            stringr::str_replace_all(., "(?:\\{.*?\\})|;|\\|", " ")) # added |
        ) %>%
        # trim white space padding to be safe
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(stringr::str_trim(., side = "both"))
        ) %>%
        # also trim multiple spaces to be safe
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(stringr::str_replace(., "\\s{2,}", " ")) #nolint
        ) %>%
        # split the string at the space
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(stringr::str_split(., "\\s+"))
        ) %>%
        # make values numeric
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(purrr::map(., as.numeric))
        ) %>%
        # get the max values
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(
            purrr::invoke_map_dbl(., .f = sense, na.rm = TRUE))
        ) %>%
        # change to character
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(as.character)
        ) %>%
        # change "-Inf" or "Inf" to "."
        dplyr::mutate_at(
          .vars = dplyr::vars(target_columns),
          .funs = dplyr::funs(ifelse((. == to_replace), ".", .)) #nolint
        )
    )
  return(selected_columns)
}

# TODO: is there a way to short-circuit parsing on trivial case?
#' @examples
#' \dontrun{
#' .parse_y_n_columns(selected_columns, yes_columns, "yes")
#' .parse_y_n_columns(selected_columns, no_columns, "no")
#' }
#' @importFrom magrittr "%>%"
#' @noRd
.parse_y_n_columns <- function(selected_columns, target_columns, sense){
  if (length(target_columns) == 0){
    return(selected_columns)
  }

  if (! sense %in% c("yes", "no")){
    stop('sense must be "yes" or "no"')
  }

  if (sense == "yes") {
    preference <- "Y"
    second <- "N"
  } else {
    preference <- "N"
    second <- "Y"
  }

  selected_columns <-
    suppressWarnings(
      selected_columns %>%
        # parse:  preference if present, else second if present, else .
        dplyr::mutate_at(.vars = dplyr::vars(target_columns),
                         .funs = dplyr::funs(ifelse(
                           stringr::str_detect(., preference),
                           preference,
                           ifelse(stringr::str_detect(., second),
                                  second, ".")
                         )))
    )
  return(selected_columns)
}

# TODO: is there a way to short-circuit parsing on trivial case?
#' @importFrom magrittr "%>%"
#' @noRd
.parse_a_columns <- function(selected_columns, a_columns){
  if (length(a_columns) == 0){
    return(selected_columns)
  }
  selected_columns <-
    suppressWarnings(
      selected_columns %>%
        # parse: A if A present, then D, P, N, else .
        dplyr::mutate_at(.vars = dplyr::vars(a_columns),
                  .funs = dplyr::funs(
                    ifelse(stringr::str_detect(., "A"), "A",
                           ifelse(stringr::str_detect(., "D"), "D",
                                  ifelse(stringr::str_detect(., "P"), "P",
                                         ifelse(stringr::str_detect(., "N"),
                                                "N", ".")
                                  )
                           )
                    )
                  )
        )
    )
  return(selected_columns)
}

# helper for .parseDistinct() - returns |-separated unique values from
# character vector
#' @importFrom magrittr "%>%"
#' @noRd
.collapse_unique <- function(x) {
  unique(x) %>%
    stringr::str_c(collapse = "|")
}

# helper for .parseDistinct()
# takes complicated string and simplifies to a ;-separated string, then
# calls .collapse_unique() to return a string of |-separated unique values

#' @importFrom magrittr "%>%"
#' @noRd
.unique_values <- function(a_string) {
  a_string %>%
    # replace {n} with ;
    stringr::str_replace_all("\\{.*?\\}", ";") %>%
    # trim any padding spaces to be safe
    stringr::str_trim(side = "both") %>%
    # replace ".;" at the end of the line with "."
    stringr::str_replace_all("\\.;$", ".") %>%
    # remove ".;" within the string
    stringr::str_replace_all("\\.;", "") %>%
    # remove ";;"
    stringr::str_replace_all(";;", ";") %>%
    # remove ";" if it's the beginning or end of the string
    stringr::str_replace_all("^;|;$", "") %>%
    # split the string at the semicolon (makes list of character vectors)
    stringr::str_split(";") %>%
    # collapse_unique returns |-separated unique values from character vector
    purrr::map_chr(.collapse_unique)
}

# distinct_example:
# Before
# chr pos Ensembl_Regulatory_Build_TFBS
# 1  100  .{1}Tr4;Egr1;Egr1{4}
# 1  200  .{4}Egr1{3}Gabp{5}Gabp;Egr1{1}Gabp;Gabp{7}Gabp;Gabp;Egr1{4}
#
# After
# chr pos Ensembl_Regulatory_Build_TFBS
# 1  100  Tr4
# 1  100  Egr1
# 1  200  Egr1
# 1  200  Gabp

#' @importFrom magrittr "%>%"
#' @noRd
.parse_distinct <- function(selected_columns, distinct_columns){
  # trivial case
  if (length(distinct_columns) == 0){
    return(selected_columns)
  }

  # if no {*} or ;, no parsing needed.
  if (!any(
    suppressWarnings(
    selected_columns %>%
      dplyr::select(distinct_columns) %>%
      stringr::str_detect("(?:\\{.*?\\})|;"))
  )
  ){
    return(selected_columns)
  }

  # now parse column using new functions
  selected_columns <-
    selected_columns %>%
    purrr::map_at(distinct_columns, .unique_values) %>% # may need vars()?
    dplyr::as_tibble()

  return(selected_columns)
  # NOTE: selected_columns still needs to be pivoted on the distinct field(s)
  # after this function call
}

#' @importFrom magrittr "%>%"
#' @importFrom rlang ":="
#' @noRd
.parse_pairs_max <- function(selected_columns, pair_columns) {
  if (typeof(pair_columns) != "list") {
    stop("pair_columns must be a list")
  }
  # perhaps map()?
  parsed_columns <- selected_columns
  for (pair in pair_columns) {
    # if a single, pass it along.
    if (length(pair) == 1){
      parsed_columns <- .preserve_raw(parsed_columns, unlist(pair))
      parsed_columns <-
        .parse_extreme_columns(parsed_columns, unlist(pair), "max")
      next
    }
    if (length(pair) != 2){
      stop("pair columns not length 1 or 2")
    }
    # if we've really got a pair, parse them.
    current_pair <- rlang::syms(pair)
    score_name <- pair[[1]]
    pred_name <- pair[[2]]
    unparsed_score_name <- paste0(score_name, "_unparsed")
    unparsed_pred_name <- paste0(pred_name, "_unparsed")

    parsed_columns <-
      suppressWarnings(
        parsed_columns %>%
          dplyr::mutate(
            p_list = stringr::str_split(rlang::UQ(current_pair[[1]]), ";"),
            p_list = purrr::map(p_list, as.numeric),
            p_max = purrr::map_dbl(p_list, max, na.rm = TRUE),
            p_max = as.character(p_max),
            p_max = ifelse( (p_max == "-Inf"), ".", p_max),
            match_mask = purrr::map2(p_list, p_max, stringr::str_detect),
            # replace NA with false
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      replace(x, is.na(x), FALSE)),
            # if all FALSE, change all to TRUE, then keep only first
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      if (all(x == FALSE))
                                        ! x
                                    else
                                      x),
            # if match_mask has more than one TRUE, keep only first TRUE
            # -- thanks Adrienne!
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      x & !duplicated(x)),
            r_list =  stringr::str_split(rlang::UQ(current_pair[[2]]), ";"),
            r_corresponding = purrr::map2_chr(match_mask, r_list,
                                              function(logical, string)
                                                ifelse(length(string) == 1,
                                                       string,
                                                       subset(string, logical)))
          ) %>%
          dplyr::select(-p_list,
                        -match_mask,
                        -r_list) %>%
          dplyr::rename(
            rlang::UQ(unparsed_score_name) := rlang::UQ(current_pair[[1]]),
            rlang::UQ(current_pair[[1]]) := p_max,
            rlang::UQ(unparsed_pred_name) := rlang::UQ(current_pair[[2]]),
            rlang::UQ(current_pair[[2]]) := r_corresponding
          )
      )
  }
  return(parsed_columns)
}

#' @importFrom magrittr "%>%"
#' @noRd
.parse_pairs_min <- function(selected_columns, pair_columns) {
  if (typeof(pair_columns) != "list") {
    stop("pair_columns must be a list")
  }
  # perhaps map()?
  parsed_columns <- selected_columns
  for (pair in pair_columns) {
    # if a single, pass it along.
    if (length(pair) == 1){
      parsed_columns <- .preserve_raw(parsed_columns, unlist(pair))
      parsed_columns <-
        .parse_extreme_columns(parsed_columns, unlist(pair), "min")
      next
    }
    if (length(pair) != 2){
      stop("pair columns not length 1 or 2")
    }
    # if we've really got a pair, parse them.
    current_pair <- rlang::syms(pair)
    score_name <- pair[[1]]
    pred_name <- pair[[2]]
    unparsed_score_name <- paste0(score_name, "_unparsed")
    unparsed_pred_name <- paste0(pred_name, "_unparsed")

    parsed_columns <-
      suppressWarnings(
        parsed_columns %>%
          dplyr::mutate(
            p_list = stringr::str_split(rlang::UQ(current_pair[[1]]), ";"),
            p_list = purrr::map(p_list, as.numeric),
            p_min = purrr::map_dbl(p_list, min, na.rm = TRUE),
            p_min = as.character(p_min),
            p_min = ifelse( (p_min == "Inf"), ".", p_min),
            match_mask = purrr::map2(p_list, p_min, stringr::str_detect),
            # replace NA with false
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      replace(x, is.na(x), FALSE)),
            # if all FALSE, change all to TRUE, then keep only first
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      if (all(x == FALSE))
                                        ! x
                                    else
                                      x),
            # if match_mask has more than one TRUE, keep only first TRUE
            # -- thanks Adrienne!
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      x & !duplicated(x)),
            r_list =  stringr::str_split(rlang::UQ(current_pair[[2]]), ";"),
            r_corresponding = purrr::map2_chr(match_mask, r_list,
                                              function(logical, string)
                                                ifelse(length(string) == 1,
                                                       string,
                                                       subset(string, logical)))
          ) %>%
          dplyr::select(-p_list,
                        -match_mask,
                        -r_list) %>%
          dplyr::rename(
            rlang::UQ(unparsed_score_name) := rlang::UQ(current_pair[[1]]),
            rlang::UQ(current_pair[[1]]) := p_min,
            rlang::UQ(unparsed_pred_name) := rlang::UQ(current_pair[[2]]),
            rlang::UQ(current_pair[[2]]) := r_corresponding
          )
      )
  }
  return(parsed_columns)
}

#' @importFrom magrittr "%>%"
#' @noRd
.parse_pairs_pick_y <- function(selected_columns, pair_columns) {
  if (typeof(pair_columns) != "list") {
    stop("pair_columns must be a list")
  }
  # perhaps map()?
  parsed_columns <- selected_columns
  for (pair in pair_columns) {
    if (length(pair) == 1){
      parsed_columns <- .preserve_raw(parsed_columns, unlist(pair))
      parsed_columns <- .parse_y_n_columns(parsed_columns, unlist(pair), "yes")
      next
    }
    if (length(pair) != 2){
      stop("pair columns not length 1 or 2")
    }
    stop(".parse_pairs_pick_y() not implemented yet")
  }
  return(parsed_columns)
}

#' @importFrom magrittr "%>%"
#' @noRd
.parse_pairs_pick_n <- function(selected_columns, pair_columns) {
  if (typeof(pair_columns) != "list") {
    stop("pair_columns must be a list")
  }
  # perhaps map()?
  parsed_columns <- selected_columns
  for (pair in pair_columns) {
    if (length(pair) == 1){
      parsed_columns <- .preserve_raw(parsed_columns, unlist(pair))
      parsed_columns <- .parse_y_n_columns(parsed_columns, unlist(pair), "no")
      next
    }
    if (length(pair) != 2){
      stop("pair columns not length 1 or 2")
    }
    stop(".parse_pairs_pick_n() not implemented yet")
  }
  return(parsed_columns)
}

#' @importFrom magrittr "%>%"
#' @importFrom rlang ":="
#' @noRd
#'
.parse_pairs_a <- function(selected_columns, pair_columns) {
  if (typeof(pair_columns) != "list") {
    stop("pair_columns must be a list")
  }
  # perhaps map()?
  parsed_columns <- selected_columns
  for (pair in pair_columns) {
    if (length(pair) == 1){
      parsed_columns <- .preserve_raw(parsed_columns, unlist(pair))
      parsed_columns <- .parse_a_columns(parsed_columns, unlist(pair))
      next
    }
    if (length(pair) != 2){
      stop("pair columns not length 1 or 2")
    }

    # if we've really got a pair, parse them.
    current_pair <- rlang::syms(pair)
    score_name <- pair[[2]]
    pred_name <- pair[[1]]
    unparsed_score_name <- paste0(score_name, "_unparsed")
    unparsed_pred_name <- paste0(pred_name, "_unparsed")

    parsed_columns <-
      suppressWarnings(
        parsed_columns %>%
          dplyr::mutate(
            # If A present keep A,
            # else if D present keep D,
            # else if P present keep P,
            # else if N present keep N,
            # else .
            new_p = ifelse(
              stringr::str_detect(rlang::UQ(current_pair[[1]]), "A"),
              "A",
              ifelse(
                stringr::str_detect(rlang::UQ(current_pair[[1]]), "D"),
                "D",
                ifelse(
                  stringr::str_detect(rlang::UQ(current_pair[[1]]), "P"),
                  "P",
                  ifelse(stringr::str_detect(rlang::UQ(current_pair[[1]]), "N"),
                         "N",
                         ".")
                )
              )
            ),
            p_list = stringr::str_split(rlang::UQ(current_pair[[1]]), ";"),
            match_mask = purrr::map2(p_list, new_p, stringr::str_detect),
            # if match_mask has more than one TRUE, keep only first TRUE
            # -- thanks Adrienne!
            match_mask = purrr::map(match_mask,
                                    function(x)
                                      x & !duplicated(x)),
            r_list =  stringr::str_split(rlang::UQ(current_pair[[2]]), ";"),
            r_corresponding = purrr::map2_chr(match_mask, r_list,
                                       function(logical, string)
                                         ifelse(length(string) == 1,
                                                string,
                                                subset(string, logical)))
          ) %>%
          dplyr::select(-p_list,
                        -match_mask,
                        -r_list) %>%
          dplyr::rename(
            rlang::UQ(unparsed_score_name) := rlang::UQ(current_pair[[2]]),
            rlang::UQ(current_pair[[2]]) := r_corresponding,
            rlang::UQ(unparsed_pred_name) := rlang::UQ(current_pair[[1]]),
            rlang::UQ(current_pair[[1]]) := new_p
          )
      )
  }
  return(parsed_columns)
}

# this function is required to work around a bug relating to fields requiring
# a second pivoting operation (e.g. fields like value;value|value;value). In
# some cases, this is mistakenly annotated as value;value|.) Thus, the number of
# dots needs to be padded to enable the second pivot operation.
#' @importFrom magrittr "%>%"
#' @noRd
.pad_dots <- function(pivoted_columns, cols_to_pad){
  # filter to get rows with ";" in the cols_to_pad columns
  semicolon_rows <- pivoted_columns %>%
    dplyr::filter_at(
      .vars = unlist(cols_to_pad),
      dplyr::any_vars(stringr::str_detect(., pattern = ";")))

  # from that, filter rows that have cells with just "." in the cols_to_pad
  semicolon_rows_2 <- semicolon_rows %>%
    dplyr::filter_at(
      .vars = unlist(cols_to_pad),
      dplyr::any_vars(stringr::str_detect(., pattern = "^\\.$")))

  # short circuit evaluation if there's no padding needed
  if (nrow(semicolon_rows_2) == 0){
    return(pivoted_columns)
  }

  # next want to get column names we want to do 2nd pivot on that have just "."
  # as value from those rows
  desired_cols <- semicolon_rows_2 %>%
    dplyr::select(tidyselect::one_of(unlist(cols_to_pad))) %>%
    purrr::map(function(x) stringr::str_detect(x, pattern = "^\\.$")) %>%
    purrr::map_lgl(function(x) any(x)) # or do I want "all?

  dot_cols <- semicolon_rows_2 %>%
    dplyr::select(which(desired_cols)) %>% names()

  # short circuit evaluation if there's no padding needed
  if (length(dot_cols) == 0){
    return(pivoted_columns)
  }

  # get number of semicolons from cells in rows we want to pivot that have them.
  # first find cols with semicolons in
  desired_cols <- semicolon_rows_2 %>%
    dplyr::select(tidyselect::one_of(unlist(cols_to_pad))) %>%
    purrr::map(function(x) stringr::str_detect(x, pattern = ";")) %>%
    purrr::map_lgl(function(x) any(x)) # or do I want "all?

  semicolon_cols <- semicolon_rows_2 %>%
    dplyr::select(which(desired_cols)) %>% names()

  # short circuit evaluation if there's no padding needed
  if (length(semicolon_cols) == 0){
    return(pivoted_columns)
  }

  # Count nonzero semicolons in each row, confirm they're all the same
  semicolon_counts <- semicolon_rows_2 %>%
    dplyr::select(semicolon_cols) %>%
    purrrlyr::by_row(function(x) stringr::str_count(x, pattern = ";")) %>%
    rename(counts = .out) %>% dplyr::select(counts) %>%
    purrr::map_depth(2, function(x) x[!x == 0])

  # error if any semicolon_counts have more than one nonzero value
  distinct_counts <- purrr::map(semicolon_counts$counts,
                                function(x) length(unique(x))) %>%
    unlist()

  if (any(distinct_counts != 1 & distinct_counts != 0)){
    msg <-
      paste0("cells in desired pivot2 columns have differing numbers of ",
             "semicolons.")
    stop(msg)
  }

  # here's a vector of the semicolon counts by row
  semicolon_counts <- purrr::map(semicolon_counts$counts,
                                 function(x) unique(x)) %>%
    unlist()

  #next make a vector of replacement_strings
  replacement_strings <- purrr::map_chr(semicolon_counts,
                                        function(x) paste0(rep(".", x + 1),
                                                           collapse = ";"))

  # now transmute_at the dot_cols with a if_else() function to replace "."
  padded <- semicolon_rows_2 %>%
    dplyr::mutate(replacement = replacement_strings) %>%
    dplyr::mutate_at(.vars = dplyr::vars(dot_cols),
                     .funs = ~ dplyr::if_else(stringr::str_detect(., "^\\.$"),
                                              true = replacement,
                                              false = .)) %>%
    dplyr::select(-replacement)

  # next replace original rows in pivoted_columns:
  # get the rows that didn't need padding
  compliment <- dplyr::anti_join(pivoted_columns, semicolon_rows_2)

  # then concatinate the padded rows and the rows that didn't need padding
  pre_pivot <- dplyr::bind_rows(compliment, padded)

  return(pre_pivot)
}

#' @importFrom magrittr "%>%"
#' @noRd
.pivot_fields <- function(selected_columns, pivot_columns) {
  if (typeof(pivot_columns) != "list") {
    stop("pivot_columns must be a list")
  }
  # perhaps map()?
  pivoted_columns <- selected_columns
  for (pivot_set in pivot_columns) {
    regexp <- paste0("\\", pivot_set$pivotChar[[1]]) #nolint
    pivoted_columns <- pivoted_columns %>%
      tidyr::separate_rows(dplyr::one_of(pivot_set$field), sep = regexp)
    # with WGSA v 0.8, need to do second pivot for some fields
    if ("pivotChar2" %in% names(pivot_set)) {
      # get the list of fields that have non-NA pivotChar
      pivot2 <- pivot_set %>%
        dplyr::filter(!is.na(pivotChar2)) #nolint
      # if there are any fields that should be pivoted, make regex of
      # pivotChar2, prepare as needed (pad dots), then pivot
      if (dplyr::n_distinct(pivot2) > 0) {
        regexp2 <- paste0("\\", pivot2$pivotChar2[[1]]) #nolint
        # pad here - CAUTION: this assumes pivotChar is ";"
        pivoted_columns <- .pad_dots(pivoted_columns, pivot2$field)
        # do the second pivot
        pivoted_columns <- pivoted_columns %>%
          tidyr::separate_rows(dplyr::one_of(pivot2$field), sep = regexp2)
      }
    }
  }
  pivoted_columns <- dplyr::distinct(pivoted_columns)
  return(pivoted_columns)
}

#' @importFrom magrittr "%>%"
#' @noRd
.fix_nulls <- function(chunk, config){
  config <- .clean_config(config)
  # if no default null Values, no changes to make
  if (!("toRemove" %in% colnames(config))) {
    return(chunk)
  }
  # see https://stackoverflow.com/questions/53071578/
  listed_tibble_list <-
    dplyr::tibble(all_cols = names(chunk)) %>%
    dplyr::left_join(config, by = c("all_cols" = "field")) %>%
    split(.$all_cols) %>%
    purrr::map(as.list)

  nullfixed <-
    listed_tibble_list[names(chunk)] %>% # confirm column order
    purrr::map2_dfc(chunk, function(info, text) {
      if (is.na(info$toRemove)) { #nolint
        text
      } else {
        stringr::str_replace_all(text, info$toRemove, "") #nolint
      }
    })
  colnames(nullfixed) <- colnames(chunk) # reconfirm column order
  nullfixed
}

#' chunk = with colnames, as from wgsaparsr:::.get_fields_from_chunk()
#' config = tibble as from load_config()
#' type = "SNV"|"indel"
#' @importFrom magrittr "%>%"
#' @noRd
.parse_then_pivot <- function(chunk, config, type) {
  # check args---------------------------
  if (!(type %in% c("SNV", "indel"))) {
    stop('type must be one of "SNV" or "indel"')
  }

  validate_config(config)

  # get desired fields from config to validate
  desired <- .get_list_from_config(config, "desired", type)

  # validate the config against chunk
  if (!all(unlist(desired) %in% names(chunk))) {
    stop("not all desired fields are in sourcefile")
  }

  # build lists from config file---------
  # fields that are transformed by themselves:
  parse_max <- .get_list_from_config(config, "max", type)
  parse_min <- .get_list_from_config(config, "min", type)
  pick_y <- .get_list_from_config(config, "pick_Y", type)
  pick_n <- .get_list_from_config(config, "pick_N", type)
  pick_a <- .get_list_from_config(config, "pick_A", type)
  parse_clean <- .get_list_from_config(config, "clean", type)
  parse_distinct <- .get_list_from_config(config, "distinct", type)

  # fields that are transformed as pairs:
  parse_pairs_max <- .get_list_from_config(config, "max_pairs", type)
  parse_pairs_min <- .get_list_from_config(config, "min_pairs", type)
  parse_pairs_pick_y <- .get_list_from_config(config, "pick_Y_pairs", type)
  parse_pairs_pick_n <- .get_list_from_config(config, "pick_N_pairs", type)
  parse_pairs_pick_a <- .get_list_from_config(config, "pick_A_pairs", type)

  # pivoting
  to_pivot <- .get_list_from_config(config, "pivots", type)

  # select the variables from chunk----------
  selected <- chunk %>% dplyr::select(unlist(desired))

  # parse the chunk single fields-------------
  # preserve unparsed, first (maybe with flag?)
  parsed <- .preserve_raw(selected, unlist(parse_max))
  parsed <- .parse_extreme_columns(parsed, unlist(parse_max), "max")

  parsed <- .preserve_raw(parsed, unlist(parse_min))
  parsed <- .parse_extreme_columns(parsed, unlist(parse_min), "min")

  parsed <- .preserve_raw(parsed, unlist(pick_y))
  parsed <- .parse_y_n_columns(parsed, unlist(pick_y), "yes")

  parsed <- .preserve_raw(parsed, unlist(pick_n))
  parsed <- .parse_y_n_columns(parsed, unlist(pick_n), "no")

  parsed <- .preserve_raw(parsed, unlist(pick_a))
  parsed <- .parse_a_columns(parsed, unlist(pick_a))

  parsed <- .preserve_raw(parsed, unlist(parse_clean))
  parsed <- .parse_clean(parsed, unlist(parse_clean))

  parsed <- .preserve_raw(parsed, unlist(parse_distinct))
  parsed <- .parse_distinct(parsed, unlist(parse_distinct))

  # parse the chunk pair fields-------------
  parsed <- .parse_pairs_max(parsed, parse_pairs_max)
  parsed <- .parse_pairs_min(parsed, parse_pairs_min)
  parsed <- .parse_pairs_pick_y(parsed, parse_pairs_pick_y)
  parsed <- .parse_pairs_pick_n(parsed, parse_pairs_pick_n)
  parsed <- .parse_pairs_a(parsed, parse_pairs_pick_a)

  # pivot chunk on pivot fields--------------
  pivoted <- .pivot_fields(parsed, to_pivot)

  # fix null values--------------------------
  if ("toRemove" %in% colnames(config)) {
    pivoted <- .fix_nulls(pivoted, config)
  }

  return(pivoted)
}

#' chunk = with colnames, as from wgsaparsr:::.get_fields_from_chunk()
#' config = tibble as from load_config()
#' type = "dbnsfp"
#' @importFrom magrittr "%>%"
#' @noRd
.pivot_then_parse <- function(chunk, config, type = "dbnsfp") {
  # check args---------------------------
  if (!(type %in% c("dbnsfp"))) {
    stop('type must be "dbnsfp"')
  }

  validate_config(config)

  # get desired fields from config to validate
  desired <- .get_list_from_config(config, "desired", type)
  # short circuit if no desired dbnsfp fields
  if (length(desired) == 0) {
    return(dplyr::tibble())
  }

  # validate the config against chunk-----
  if (!all(unlist(desired) %in% names(chunk))) {
    stop("not all desired fields are in sourcefile")
  }

  # warn if can't filter rows for mostly-missing values
  if (! all(c("aaref", "aaalt") %in% desired)) {
    msg <- paste0("'aaref' and 'aaalt' not in desired dbnsfp fields. Can't ",
                  "filter variants not annotated by dbnsfp.")
    warning(msg)
  }

  # build lists from config file---------
  # fields that are transformed by themselves:
  parse_max <- .get_list_from_config(config, "max", type)
  parse_min <- .get_list_from_config(config, "min", type)
  pick_y <- .get_list_from_config(config, "pick_Y", type)
  pick_n <- .get_list_from_config(config, "pick_N", type)
  pick_a <- .get_list_from_config(config, "pick_A", type)
  parse_clean <- .get_list_from_config(config, "clean", type)
  parse_distinct <- .get_list_from_config(config, "distinct", type)

  # fields that are transformed as pairs:
  parse_pairs_max <- .get_list_from_config(config, "max_pairs", type)
  parse_pairs_min <- .get_list_from_config(config, "min_pairs", type)
  parse_pairs_pick_y <- .get_list_from_config(config, "pick_Y_pairs", type)
  parse_pairs_pick_n <- .get_list_from_config(config, "pick_N_pairs", type)
  parse_pairs_pick_a <- .get_list_from_config(config, "pick_A_pairs", type)

  # pivoting
  to_pivot <- .get_list_from_config(config, "pivots", type)

  # select the variables from chunk----------
  selected <- chunk %>% dplyr::select(unlist(desired))

  # pivot chunk on pivot fields--------------
  pivoted <- .pivot_fields(selected, to_pivot)

  # filter rows for which both aaref and aaalt are "."
  if (all(c("aaref", "aaalt") %in% desired)) {
    pivoted <- pivoted %>% dplyr::filter(!(aaref == "." & aaalt == "."))
  }

  # parse the chunk single fields-------------
  # preserve unparsed, first (maybe with flag?)
  parsed <- .preserve_raw(pivoted, unlist(parse_max))
  parsed <- .parse_extreme_columns(parsed, unlist(parse_max), "max")

  parsed <- .preserve_raw(parsed, unlist(parse_min))
  parsed <- .parse_extreme_columns(parsed, unlist(parse_min), "min")

  parsed <- .preserve_raw(parsed, unlist(pick_y))
  parsed <- .parse_y_n_columns(parsed, unlist(pick_y), "yes")

  parsed <- .preserve_raw(parsed, unlist(pick_n))
  parsed <- .parse_y_n_columns(parsed, unlist(pick_n), "no")

  parsed <- .preserve_raw(parsed, unlist(pick_a))
  parsed <- .parse_a_columns(parsed, unlist(pick_a))

  parsed <- .preserve_raw(parsed, unlist(parse_clean))
  parsed <- .parse_clean(parsed, unlist(parse_clean))

  parsed <- .preserve_raw(parsed, unlist(parse_distinct))
  parsed <- .parse_distinct(parsed, unlist(parse_distinct))

  # parse the chunk pair fields-------------
  parsed <- .parse_pairs_max(parsed, parse_pairs_max)
  parsed <- .parse_pairs_min(parsed, parse_pairs_min)
  parsed <- .parse_pairs_pick_y(parsed, parse_pairs_pick_y)
  parsed <- .parse_pairs_pick_n(parsed, parse_pairs_pick_n)
  parsed <- .parse_pairs_a(parsed, parse_pairs_pick_a)

  # fix null values--------------------------
  if ("toRemove" %in% colnames(config)) {
    parsed <- .fix_nulls(parsed, config)
  }
  return(parsed)
}

#' @noRd
.last <- function() {
  message("You're a rock star!")
}

#' config = tibble as from load_config()
#' field_list - as from get_list_from_config(cleaned_config, "desired", "SNV")
#' @importFrom magrittr "%>%"
#' @importFrom dplyr rename
#' @noRd
.rename_chunk_variables <- function(config, chunk) {
  if (!("outputName" %in% colnames(config))) {
    stop("outputName not in config")
  }
  to_rename <- config$field
  names(to_rename) <- config$outputName #nolint

  rename_set <- to_rename[to_rename %in% colnames(chunk)]
  chunk %>% rename(!!! rename_set)
}
