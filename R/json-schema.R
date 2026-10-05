# JSON Schema validation with explicit coercion (INFRA-09) and one-line R signatures of tool
# schemas. The subset supported is what tool definitions use: type (one or several), properties,
# required, additionalProperties, items and enum.

#' JSON types understood by the validator
#' @noRd
schema_types = c("object", "array", "string", "number", "integer", "boolean", "null")

#' Validate (and coerce) a parsed JSON input against a schema
#'
#' Returns `list(ok, input, errors)`. Missing required properties are errors naming the property.
#' The only coercions: integer-valued numbers become integers where the schema says `integer`,
#' and a scalar becomes a length-1 array where the schema says `array` of scalars. Unknown
#' properties are kept unless `additionalProperties` is `false`.
#' @noRd
schema_validate = function(schema, input) {
  check_list(schema, "schema")
  types = unlist(schema$type)
  object_schema = "object" %in% types || !is.null(schema$properties)
  if (is.null(input) && !("null" %in% types) && object_schema) {
    input = json_obj()
  }
  res = schema_check(schema, input, "")
  list(ok = !length(res$errors), input = res$value, errors = res$errors)
}

#' @noRd
schema_label = function(path) {
  if (nzchar(path)) paste0("'", path, "'") else "the input"
}

#' @noRd
schema_is_object = function(value) {
  is.list(value) && !is.data.frame(value) && !is.null(names(value))
}

#' @noRd
schema_is_scalar = function(value) {
  is.atomic(value) && length(value) == 1L && !is.na(value)
}

#' Check one value against one type; returns list(ok, value)
#' @noRd
schema_check_type = function(type, value, schema) {
  switch(type,
    object = list(ok = schema_is_object(value), value = value),
    array = {
      if (is.list(value) && is.null(names(value))) {
        list(ok = TRUE, value = value)
      } else if (is.atomic(value) && !is.null(value) && length(value) != 1L) {
        list(ok = TRUE, value = as.list(value))
      } else if (schema_is_scalar(value) && !identical(schema$items$type, "array") &&
                   !identical(schema$items$type, "object")) {
        list(ok = TRUE, value = list(value))
      } else {
        list(ok = FALSE, value = value)
      }
    },
    string = list(ok = is.character(value) && schema_is_scalar(value), value = value),
    number = list(ok = is.numeric(value) && schema_is_scalar(value) && is.finite(value),
                  value = value),
    integer = {
      ok = is.numeric(value) && schema_is_scalar(value) && is.finite(value) &&
        value == round(value) && abs(value) <= .Machine$integer.max
      list(ok = ok, value = if (ok) as.integer(value) else value)
    },
    boolean = list(ok = is.logical(value) && schema_is_scalar(value), value = value),
    null = list(ok = is.null(value), value = value),
    list(ok = TRUE, value = value)
  )
}

#' JSON equality for enum values: equal canonical JSON (object key order ignored, 1L equals 1)
#' @noRd
schema_json_equal = function(x, y) {
  schema_json_plain(x) && schema_json_plain(y) && identical(canonical_json(x), canonical_json(y))
}

#' Only JSON values: canonical JSON would write Inf as "Inf" and NA as null
#' @noRd
schema_json_plain = function(x) {
  if (is.list(x)) return(!is.data.frame(x) && all(vapply(x, schema_json_plain, NA)))
  is.null(x) || ((is.character(x) || is.logical(x)) && !anyNA(x)) ||
    (is.numeric(x) && all(is.finite(x)))
}

#' Recursive validation; returns list(value, errors)
#' @noRd
schema_check = function(schema, value, path) {
  errors = character()
  types = unlist(schema$type)
  if (length(types)) {
    matched = FALSE
    for (type in types) {
      res = schema_check_type(type, value, schema)
      if (isTRUE(res$ok)) {
        matched = TRUE
        value = res$value
        break
      }
    }
    if (!matched) {
      got = if (is.null(value)) "null" else paste0(class(value)[1L], " of length ", length(value))
      return(list(value = value, errors = paste0(
        schema_label(path), " must be ", paste(types, collapse = " or "), ", not ", got, "."
      )))
    }
  }
  if (!is.null(schema$enum)) {
    allowed = as.list(schema$enum)
    if (!any(vapply(allowed, function(candidate) schema_json_equal(value, candidate), TRUE))) {
      labels = vapply(allowed, json_encode, "")
      errors = c(errors, paste0(
        schema_label(path), " must be one of ", paste(labels, collapse = ", "), "."
      ))
    }
  }
  if (schema_is_object(value)) {
    props = schema$properties %||% list()
    required = as.character(unlist(schema$required))
    for (name in setdiff(required, names(value))) {
      errors = c(errors, paste0("missing required property '", schema_path(path, name), "'."))
    }
    for (name in names(value)) {
      sub = props[[name]]
      if (!is.null(sub)) {
        res = schema_check(sub, value[[name]], schema_path(path, name))
        if (!is.null(res$value)) value[[name]] = res$value
        errors = c(errors, res$errors)
      } else if (isFALSE(schema$additionalProperties)) {
        errors = c(errors, paste0("unknown property '", schema_path(path, name), "'."))
      } else if (is.list(schema$additionalProperties)) {
        res = schema_check(schema$additionalProperties, value[[name]], schema_path(path, name))
        if (!is.null(res$value)) value[[name]] = res$value
        errors = c(errors, res$errors)
      }
    }
  }
  if (is.list(value) && is.null(names(value)) && is.list(schema$items) && length(value)) {
    for (i in seq_along(value)) {
      res = schema_check(schema$items, value[[i]], paste0(path, "[", i, "]"))
      if (!is.null(res$value)) value[[i]] = res$value
      errors = c(errors, res$errors)
    }
  }
  list(value = value, errors = errors)
}

#' @noRd
schema_path = function(path, name) {
  if (nzchar(path)) paste0(path, ".", name) else name
}

#' One-line R signature of a tool schema: `name(a: string, b?: number)  # First sentence.`
#' @noRd
schema_signature = function(name, schema, description = NULL, prefix = "") {
  check_string(name, "name")
  check_list(schema, "schema")
  check_string(prefix, "prefix", empty = TRUE)
  props = schema$properties %||% list()
  required = as.character(unlist(schema$required))
  args = vapply(names(props), function(prop) {
    type = unlist(props[[prop]]$type)
    label = if (length(type)) paste(type, collapse = "|") else "any"
    paste0(prop, if (prop %in% required) "" else "?", ": ", label)
  }, "", USE.NAMES = FALSE)
  signature = paste0(prefix, name, "(", paste(args, collapse = ", "), ")")
  sentence = first_sentence(description %||% schema$description)
  if (nzchar(sentence)) signature = paste0(signature, "  # ", sentence)
  signature
}

#' The first sentence of the first line of a description ("" when there is none)
#' @noRd
first_sentence = function(text) {
  if (is.null(text) || !length(text) || is.na(text[[1L]])) return("")
  line = trimws(strsplit(as_utf8(text[[1L]]), "\n", fixed = TRUE)[[1L]][1L])
  if (is.na(line)) return("")
  sub("^(.*?[.!?])(\\s.*)?$", "\\1", line, perl = TRUE)
}

#' Structural problems of a schema (character(0) when valid)
#' @noRd
schema_problems = function(schema) {
  schema_problems_at(schema, "")
}

#' Structural problems of the schema found at `path` (recursive worker of schema_problems())
#' @noRd
schema_problems_at = function(schema, path) {
  where = function(msg) paste0(if (nzchar(path)) paste0(path, ": ") else "", msg)
  if (!is.list(schema) || (length(schema) && is.null(names(schema)))) {
    return(where("a schema must be a JSON object (a named list)"))
  }
  problems = character()
  types = unlist(schema$type)
  if (!is.null(schema$type) && (!is.character(types) || !all(types %in% schema_types))) {
    allowed = paste(schema_types, collapse = ", ")
    problems = c(problems, where(paste0("type must be one of ", allowed)))
  }
  props = schema$properties
  if (!is.null(props)) {
    if (!is.list(props) || (length(props) && is.null(names(props)))) {
      problems = c(problems, where("properties must be an object"))
      props = list()
    }
    for (name in names(props)) {
      problems = c(problems, schema_problems_at(props[[name]], schema_path(path, name)))
    }
  }
  if (!is.null(schema$required)) {
    required = unlist(schema$required)
    if (!is.character(required)) {
      problems = c(problems, where("required must be an array of strings"))
    } else if (!is.null(props)) {
      for (name in setdiff(required, names(props))) {
        problems = c(problems, where(paste0("required property '", name, "' is not in properties")))
      }
    }
  }
  if (!is.null(schema$items)) {
    problems = c(problems, schema_problems_at(schema$items, paste0(path, "[]")))
  }
  if (!is.null(schema$enum) && !length(schema$enum)) {
    problems = c(problems, where("enum must be a non-empty array"))
  }
  problems
}
