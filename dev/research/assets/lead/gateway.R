# 1. classed logical inside if()/while()/&&/ifelse/vapply
d <- structure(TRUE, class = c("gptr_decision", "logical"), prob = 0.93, question = "is it a dog?")
cat("if():", if (d) "yes" else "no", "\n")
cat("&&:", isTRUE(d && TRUE), " isTRUE(d):", isTRUE(d), "\n")
v <- structure(c(TRUE, FALSE, NA), class = c("gptr_decision", "logical"), prob = c(.9, .2, .5))
cat("which():", which(v), " sum:", sum(v, na.rm = TRUE), " ifelse:", ifelse(v, "a", "b"), "\n")
r <- tryCatch(if (v[3]) 1, error = function(e) conditionMessage(e)); cat("if(NA):", r, "\n")
# subsetting drops attributes unless a `[` method exists
cat("class after [ :", class(v[1]), " prob kept? ", !is.null(attr(v[1], "prob")), "\n")
`[.gptr_decision` <- function(x, i) structure(unclass(x)[i], class = class(x), prob = attr(x, "prob")[i])
cat("with [ method  :", class(v[1]), " prob:", attr(v[1], "prob"), "\n")

# 2. single variadic gateway: gptr(...) 
gptr <- function(..., model = NULL, skills = NULL, mode = NULL, envir = parent.frame()) {
  mc <- match.call(expand.dots = FALSE)
  bare <- function(e) if (is.null(e)) NULL else if (is.symbol(e)) as.character(e) else if (is.call(e) && identical(e[[1]], as.name("c"))) vapply(as.list(e)[-1], function(z) if (is.symbol(z)) as.character(z) else as.character(eval(z, envir)), "") else as.character(eval(e, envir))
  dots_expr <- mc$...
  dots <- list(...)
  nm <- names(dots); if (is.null(nm)) nm <- rep("", length(dots))
  is_prompt <- vapply(dots, function(x) is.character(x) && is.null(attr(x, "class")), NA) & nm == ""
  session <- Filter(function(x) inherits(x, "gptr_session") || inherits(x, "gptr_result"), dots)
  objs <- dots[!is_prompt & !vapply(dots, function(x) inherits(x, "gptr_session") || inherits(x, "gptr_result"), NA)]
  obj_labels <- vapply(dots_expr[!is_prompt & !vapply(dots, function(x) inherits(x, "gptr_result"), NA)], function(e) paste(deparse(e), collapse = ""), "")
  kind <- if (!any(is_prompt) && !length(objs) && !length(session)) "interactive" else "prompt"
  structure(list(kind = kind, prompt = unlist(dots[is_prompt]), model = bare(mc$model), skills = bare(mc$skills),
                 objects = obj_labels, continued = length(session) > 0,
                 env_is_global = identical(envir, globalenv())), class = "gptr_result")
}
str(unclass(gptr()))
str(unclass(gptr("summarise this", mtcars, model = jev, skills = c(seurat, plotting))))
m <- "sonnet"; str(unclass(gptr("hi", model = "opus"))[c("model")])
str(unclass(gptr("p1") |> gptr("p2", model = sonnet))[c("kind","prompt","model","continued")])
str(unclass(mtcars |> gptr("describe"))[c("prompt","objects")])
f <- function() gptr("inside")$env_is_global; cat("env global at top:", gptr("x")$env_is_global, " inside fn:", f(), "\n")
