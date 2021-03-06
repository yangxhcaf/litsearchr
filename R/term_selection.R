#' Extract potential keywords from abstracts and titles
#' @description Extracts potential keyword terms from text (e.g. titles and abstracts)
#' @param text A character object of text from which to extract terms
#' @param keywords A character vector of keywords tagged by authors and/or databases if using method="tagged"
#' @param method The method of extracting keywords; options are fakerake (a quick implementation similar to Rapid Automatic Keyword Extraction), or tagged for author-tagged keywords
#' @param min_freq Numeric: the minimum occurrences of a potential term
#' @param ngrams Logical: should litsearchr only extracts phrases with word count greater than a specified n?
#' @param min_n Numeric: the minimum length ngram to consider
#' @param max_n Numeric: the maximum length ngram to consider
#' @param stopwords A character vector of stopwords.
#' @param language A string indicating the language of input data to use for stopwords if none are supplied.
#' @return Returns a character vector of potential keyword terms.
#' @example inst/examples/extract_terms.R
extract_terms <- function(text = NULL,
                          keywords = NULL,
                          method = c("fakerake", "tagged"),
                          min_freq = 2,
                          ngrams = TRUE,
                          min_n = 2,
                          max_n = 5,
                          stopwords = NULL,
                          language = "English") {
  if (!is.null(text)) {
    text <- tolower(text)
  }

  if (missing(language)) {
    language <- "English"
  }

  if (is.null(stopwords)) {
    stopwords <- litsearchr::get_stopwords(language)
  }



  if (method == "fakerake") {
    if (is.null(text)) {
      stop("Please specify a body of text from which to extract terms using fakerake.")
    } else{
      terms <-
        litsearchr::fakerake(text, stopwords, min_n = min_n, max_n = max_n)
    }
  }

  if (method == "tagged") {
    if (is.null(keywords)) {
      stop("Please specify a vector of keywords from which to extract terms.")
    } else{
      keywords <- tolower(paste(keywords, collapse = " and "))
      keywords <- litsearchr::clean_keywords(keywords)
      terms <- strsplit(keywords, ";")[[1]]
      if (any(terms == "NA")) {
        terms <- terms[-which(terms == "NA")]
      }
      if(any(nchar(terms)<3)){
        terms <- terms[nchar(terms)>=3]
      }
    }
  }

  freq_terms <- names(table(terms))[which(table(terms) >= min_freq)]
  if (ngrams == TRUE) {
    n_words <- sapply(strsplit(as.character(freq_terms), " "), length)
    freq_terms <-
      freq_terms[which((n_words >= min_n) & (n_words <= max_n))]
  }

  return(freq_terms)

}

#' Quick keyword extraction
#' @description Extracts potential keywords from text separated by stopwords
#' @param text A string object to extract terms from
#' @param stopwords A character vector of stopwords to remove
#' @param min_n Numeric: the minimum length ngram to consider
#' @param max_n Numeric: the maximum length ngram to consider
#' @return A character vector of potential keywords
fakerake <- function(text,
                     stopwords,
                     min_n = 2,
                     max_n = 5) {
  if (missing(stopwords)) {
    stopwords <- litsearchr::get_stopwords()
  }

  stops <- unique(append(
    stopwords,
    c(
      ",",
      "\\.",
      ":",
      ";",
      "\\[",
      "\\]",
      "/",
      "\\(",
      "\\)",
      "\"",
      "&",
      "=",
      "<",
      ">",
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      0
    )
  ))

  # text <- litsearchr::remove_punctuation(text, preserve_punctuation = c("-", "_"))
  stop1 <- paste(" ", stops[1], " ", sep = "")
  text <- gsub("([-_])|[[:punct:]]", stop1, text)

  if (any(grepl("  ", text))) {
    while (any(grepl("  ", text))) {
      text <- gsub("  ", " ", text)
    }
  }

  text <- tolower(text)

  n_lengths <- seq(min_n, max_n, 1)
  for (i in min_n:max_n) {
    if (i == min_n) {
      ngrams <-
        lapply(text,
               litsearchr::get_ngrams,
               n = i,
               stop_words = stops)
    } else{
      ngrams <-
        Map(c,
            ngrams,
            lapply(text,
                   litsearchr::get_ngrams,
                   n = i,
                   stop_words = stops))
    }
  }

  terms <- unlist(ngrams)
  return(terms)
}

#' Create a document-feature matrix
#' @description Given a character vector of document information, creates a document-feature matrix.
#' @param elements a character vector of document information (e.g. document titles or abstracts)
#' @param features a character vector of terms to use as document features (e.g. keywords)
#' @return a matrix with documents as rows and terms as columns
#' @example inst/examples/create_dfm.R
create_dfm <-
  function(elements, features){

    elements <- tolower(elements)
    features <- tolower(features)

    detections <- lapply(features, function(x){
      grep(x, elements)
    })

    dfm_holder <- array(dim=c(length(elements), length(features)))
    for(i in 1:length(features)){
      dfm_holder[unlist(detections[[i]]), i] <- 1
    }
    dfm_holder[is.na(dfm_holder)] <- 0
    dfm <- as.matrix(dfm_holder)
    colnames(dfm) <- features
    return(dfm)
  }

#' Create a keyword co-occurrence network
#' @description Creates a keyword co-occurrence network from an adjacency matrix trimmed to remove rare terms.
#' @param search_dfm a document-feature matrix created with create_dfm()
#' @param min_studies the minimum number of studies a term must occur in to be included
#' @param min_occ the minimum total number of times a term must occur (counting repeats in the same document)
#' @return an igraph weighted graph
#' @example inst/examples/create_network.R
create_network <- function(search_dfm,
                           min_studies = 3,
                           min_occ = 3) {
  presences <- search_dfm
  presences[which(presences > 0)] <- 1
  study_counts <-
    which(as.numeric(colSums(presences)) < min_studies)
  if (length(study_counts) > 0) {
    search_dfm <- search_dfm[,-study_counts]
  }

  occur_counts <- which(colSums(search_dfm) < min_occ)
  if (length(occur_counts) > 0) {
    search_dfm <- search_dfm[,-occur_counts]
  }

  dropped_studies <- which(rowSums(search_dfm) < 1)

  if (length(dropped_studies) > 0) {
    search_dfm <- search_dfm[-dropped_studies,]
  }
  trimmed_mat <- t(search_dfm) %*% search_dfm

  search_mat <- as.matrix(trimmed_mat)
  search_graph <- igraph::graph.adjacency(search_mat,
                                          weighted = TRUE,
                                          mode = "undirected",
                                          diag = FALSE)
  return(search_graph)
}


#' Subset strength data from a graph
#' @description Selects only the node strength data from a graph.
#' @param graph an igraph graph
#' @param imp_method a character specifying the importance measurement to be used; takes arguments of "strength", "eigencentrality", "alpha", "betweenness", "hub" or "power"
#' @return a data frame of node strengths, ranks, and names
#' @example inst/examples/make_importance.R
make_importance <- function(graph, imp_method = "strength") {

  if (imp_method == "strength") {
    importance <- sort(igraph::strength(graph))
  }
  if (imp_method == "eigencentrality") {
    importance <- sort(igraph::eigen_centrality(graph))
  }
  if (imp_method == "alpha") {
    importance <- sort(igraph::alpha_centrality(graph))
  }
  if (imp_method == "betweenness") {
    importance <- sort(igraph::betweenness(graph))
  }
  if (imp_method == "hub") {
    importance <- sort(igraph::hub_score(graph))
  }
  if (imp_method == "power") {
    importance <- sort(igraph::power_centrality(graph))
  }
  importances <-
    cbind(seq(1, length(importance), 1), as.numeric(importance))
  colnames(importances) <- c("rank", "importance")
  importances <- as.data.frame(importances)
  importances$nodename <- names(importance)
  importances$rank <- as.numeric(importances$rank)
  importances$importance <- as.numeric(importances$importance)
  return(importances)
}

#' Subset n-grams from node names
#' @description Selects only nodes from a graph whose node names are at least n-grams, where n is the minimum number of words in the node name. The default n-gram is a 2+-gram, which captures potential keyword terms that are at least two words long. The reason for this is that unigrams (terms with only one word) are detected more frequently, but are also generally less relevant to finding keyword terms.
#' @param graph an igraph object
#' @param n a minimum number of words in an n-gram
#' @param imp_method a character specifying the importance measurement to be used; takes arguments of "strength", "eigencentrality", "alpha", "betweenness", "hub" or "power"
#' @return a data frame of node names, strengths, and rank
#' @example inst/examples/select_ngrams.R
select_ngrams <- function(graph,
                          n = 2,
                          imp_method = "strength") {
  importances <- make_importance(graph, imp_method = imp_method)
  ngrams <-
    importances[which(sapply(strsplit(
      as.character(importances$nodename), " "
    ), length) >= n),]
  return(ngrams)
}

#' Subset unigrams from node names
#' @description Selects only nodes from a graph whose node names are single words.
#' @param graph an igraph object
#' @param imp_method a character specifying the importance measurement to be used; takes arguments of "strength", "eigencentrality", "alpha", "betweenness", "hub" or "power"
#' @return a data frame of node names, strengths, and rank
#' @example inst/examples/select_ngrams.R
select_unigrams <- function(graph, imp_method = "strength") {
  importances <- make_importance(graph, imp_method = imp_method)
  unigrams <-
    importances[which(sapply(strsplit(
      as.character(importances$nodename), " "
    ), length) == 1),]
  return(unigrams)
}

#' Find node cutoff strength
#' @description Find the minimum node strength to use as a cutoff point for important nodes.
#' @param graph An igraph graph object
#' @param method the cutoff method to use, either "changepoint" or "cumulative"
#' @param percent if using method cumulative, the total percent of node strength to capture
#' @param knot_num if using method changepoint, the number of knots to identify
#' @param imp_method a character specifying the importance measurement to be used; takes arguments of "strength", "eigencentrality", "alpha", "betweenness", "hub" or "power"
#' @details The changepoint fit finds tipping points in the ranked order of node strengths to use as cutoffs. The cumulative fit option finds the node strength cutoff point at which a certain percent of the total strength of the graph is captured (e.g. the fewest nodes that contain 80\% of the total strength).
#' @return a vector of suggested node cutoff strengths
#' @example inst/examples/find_cutoff.R
find_cutoff <-
  function(graph,
           method = c("changepoint", "cumulative"),
           percent = 0.8,
           knot_num = 3,
           imp_method = "strength") {
    importances <- make_importance(graph, imp_method = imp_method)

    if (method == "changepoint") {
      knots <- suppressWarnings(changepoint::cpt.mean(importances$importance,penalty="Manual",pen.value="2*log(n)",method="BinSeg",Q=knot_num,class=FALSE))
      cut_strengths <- (importances$importance)[knots]
    }

    if (method == "cumulative") {
      cum_str <- max(cumsum(sort(importances$importance)))
      cut_point <-
        (which(cumsum(
          sort(importances$importance, decreasing = TRUE)
        ) >= cum_str * percent))[1]
      cut_strengths <-
        as.numeric(sort(as.numeric(importances$importance), decreasing = TRUE)[cut_point])
    }
    return(cut_strengths)
  }

#' Extract potential keywords
#' @description Extracts keywords identified as important.
#' @param reduced_graph a reduced graph with only important nodes created with reduce_graph()
#' @return a character vector of potential keywords to consider
#' @example inst/examples/get_keywords.R
get_keywords <- function(reduced_graph) {
  potential_keys <- names(igraph::V(reduced_graph))
  return(potential_keys)
}


#' Create reduced graph of important nodes
#' @description Takes the full graph and reduces it to only include nodes (and associated edges) greater than the cutoff strength for important nodes.
#' @param graph the full graph object
#' @param cutoff_strength the minimum node importance to be included in the reduced graph
#' @param imp_method a character specifying the importance measurement to be used; takes arguments of "strength", "eigencentrality", "alpha", "betweenness", "hub" or "power"
#' @return an igraph graph with only important nodes
#' @example inst/examples/reduce_graph.R
reduce_graph <-
  function(graph, cutoff_strength, imp_method = "strength") {
    importances <- make_importance(graph, imp_method = imp_method)
    important_nodes <-
      importances$nodename[which(importances$importance >= cutoff_strength)]
    reduced_graph <-
      igraph::induced_subgraph(graph, v = important_nodes)
    return(reduced_graph)
  }
