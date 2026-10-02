suppressPackageStartupMessages({library(httr2); library(jsonlite)})
read_env <- function(path) {
  ln <- readLines(path, warn = FALSE); ln <- ln[grepl("=", ln, fixed = TRUE) & !grepl("^\\s*#", ln)]
  k <- trimws(sub("=.*$", "", ln)); v <- trimws(sub("^[^=]*=", "", ln))
  v <- gsub("^(['\"])(.*)\\1$", "\\2", v); stats::setNames(as.list(v), k)
}
key <- read_env("/Users/wanjun/Downloads/jev-key.env")[["jev-key"]]
stopifnot(is.character(key), nzchar(key)); cat("key loaded: nchar =", nchar(key), "(value not shown)\n")
s1 <- function(state, questions, model = "jev-latest") {
  request("https://api.typesafe.ai/v1/systemone") |>
    req_headers(Authorization = paste("Bearer", key), .redact = "Authorization") |>
    req_body_json(list(model = model, state = state, questions = questions), auto_unbox = TRUE) |>
    req_error(is_error = function(resp) FALSE) |> req_timeout(30)
}
q <- list(
  is_dog = list(type = "noul", instructions = "Does `text` describe a dog?",
                criteria = list(true = "The text describes a dog", false = "The text does not describe a dog")),
  animal = list(type = "choice", instructions = "Which animal does `text` describe?",
                criteria = list(dog = "A dog", cat = "A cat", bird = "A bird", other = "None of these")),
  cuteness = list(type = "score", instructions = "How positive is the sentiment of `text`?",
                  criteria = list("Very negative", "Neutral", "Very positive"))
)
t0 <- Sys.time(); resp <- req_perform(s1(list(text = "A golden retriever puppy fetched the ball and wagged its tail."), q))
cat("status:", resp_status(resp), " elapsed ms:", round(as.numeric(Sys.time() - t0, units = "secs") * 1000), "\n")
cat("content-type:", resp_content_type(resp), "\n")
cat("rate/limit headers:", paste(grep("rate|limit|retry|request-id", names(resp_headers(resp)), value = TRUE, ignore.case = TRUE), collapse = ", "), "\n")
body <- resp_body_string(resp); cat(prettify(body), "\n")
