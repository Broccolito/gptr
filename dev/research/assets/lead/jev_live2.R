suppressPackageStartupMessages({library(httr2); library(jsonlite)})
ln <- readLines("/Users/wanjun/Downloads/jev-key.env", warn = FALSE); ln <- ln[grepl("^jev-key=", ln)]
key <- gsub("^(['\"])(.*)\\1$", "\\2", trimws(sub("^[^=]*=", "", ln)))
s1 <- function(state, questions, model = "jev-latest") {
  request("https://api.typesafe.ai/v1/systemone") |>
    req_headers(Authorization = paste("Bearer", key), .redact = "Authorization") |>
    req_body_json(list(model = model, state = state, questions = questions), auto_unbox = TRUE) |>
    req_error(is_error = function(resp) FALSE) |> req_timeout(30)
}
qdog <- list(is_dog = list(type = "noul", instructions = "Does `text` describe a dog?",
             criteria = list(true = "The text describes a dog", false = "The text does not describe a dog")))
texts <- c("A beagle barked at the mailman.", "The tabby cat slept on the sofa.", "A parrot repeated my words.",
           "The puppy chewed my shoe.", "Quarterly revenue rose by 4 percent.", "My labrador loves swimming.",
           "The kitten chased a laser dot.", "A husky pulled the sled.", "The goldfish swam in circles.", "He walked his poodle.",
           "An owl hooted at night.", "The terrier dug a hole.", "She adopted a Siamese.", "A wolf howled.", "The dachshund is long.",
           "It rained all day.", "The greyhound sprinted.", "A hamster ran on a wheel.", "The corgi herded sheep.", "Stock markets fell.")
reqs <- lapply(texts, function(t) s1(list(text = t), qdog))
t0 <- Sys.time(); resps <- req_perform_parallel(reqs, max_active = 10, on_error = "continue", progress = FALSE)
el <- round(as.numeric(Sys.time() - t0, units = "secs") * 1000)
ok <- vapply(resps, function(r) inherits(r, "httr2_response") && resp_status(r) == 200, NA)
p <- vapply(resps, function(r) if (inherits(r, "httr2_response") && resp_status(r) == 200) resp_body_json(r)$answers$is_dog$noul else NA_real_, 0)
cat("20 parallel requests (max_active=10): wall ms =", el, " ok =", sum(ok), "/ 20\n")
out <- structure(p >= 0.5, class = c("gptr_decision", "logical"), prob = p)
print(data.frame(prob = p, decision = unclass(out) , text = texts)[order(-p), ], row.names = FALSE)
statuses <- vapply(resps, function(r) if (inherits(r, "httr2_response")) resp_status(r) else NA_integer_, 0L); cat("status table:"); print(table(statuses, useNA = "ifany"))

cat("\n--- error shapes ---\n")
e1 <- req_perform(s1(list(text = "x"), list(q = list(type = "banana", instructions = "?", criteria = list(a = "a")))))
cat("bad question type -> status", resp_status(e1), "\n", resp_body_string(e1), "\n")
e2 <- req_perform(s1(list(text = "x"), qdog, model = "no-such-model"))
cat("bad model -> status", resp_status(e2), "\n", resp_body_string(e2), "\n")
e3 <- request("https://api.typesafe.ai/v1/systemone") |> req_headers(Authorization = "Bearer invalid-key-for-error-shape-test") |>
  req_body_json(list(model = "jev-latest", state = list(text = "x"), questions = qdog), auto_unbox = TRUE) |>
  req_error(is_error = function(resp) FALSE) |> req_perform()
cat("bad key -> status", resp_status(e3), "\n", resp_body_string(e3), "\n")
cat("\n--- bool alias accepted on the wire? ---\n")
e4 <- req_perform(s1(list(text = "A beagle barked."), list(q = list(type = "bool", instructions = "Is `text` about a dog?", criteria = list(true = "yes", false = "no")))))
cat("type=bool -> status", resp_status(e4), "\n", substr(resp_body_string(e4), 1, 400), "\n")
cat("\n--- models endpoint? ---\n")
m <- request("https://api.typesafe.ai/v1/models") |> req_headers(Authorization = paste("Bearer", key), .redact = "Authorization") |> req_error(is_error = function(resp) FALSE) |> req_perform()
cat("GET /v1/models -> status", resp_status(m), "\n", substr(resp_body_string(m), 1, 800), "\n")
